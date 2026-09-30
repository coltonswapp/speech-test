//
//  LLMGatewayClient.swift
//  shizen
//
//  Calls the Shizen LLM gateway (Cloud Run, services/llm-gateway) with the
//  signed-in user's Firebase ID token. The Gemini key lives on the server.
//

import FirebaseAuth
import Foundation

enum LLMGatewayError: LocalizedError {
    case notConfigured
    case notSignedIn
    case unauthorized
    case invalidRequest(String)
    case upstream
    case httpStatus(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "SHIZEN_LLM_GATEWAY_URL is not configured."
        case .notSignedIn:
            return "Sign in to use this feature."
        case .unauthorized:
            return "Your session expired. Sign in again to use this feature."
        case .invalidRequest(let detail):
            return detail
        case .upstream:
            return "Couldn't reach Gemini. Try again in a moment."
        case .httpStatus(let status):
            return "The server returned an error (\(status))."
        case .invalidResponse:
            return "The server returned an unexpected response."
        }
    }
}

struct LLMGeneratePayload<Result: Decodable> {
    let result: Result
    let model: String
    let usage: GeminiUsageMetadata?
    let feedback: LLMFeedbackReceipt?
}

enum LLMGatewayClient {

    /// Scheme env `SHIZEN_LLM_GATEWAY_URL` overrides Info.plist (e.g. a local `npm run dev`).
    static var baseURL: URL? {
        let raw = ProcessInfo.processInfo.environment["SHIZEN_LLM_GATEWAY_URL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "SHIZEN_LLM_GATEWAY_URL") as? String
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return URL(string: trimmed)
    }

    static var isConfigured: Bool { baseURL != nil }

    /// The gateway rejects anonymous tokens, matching `AuthService`.
    static var hasSignedInUser: Bool {
        guard let user = Auth.auth().currentUser else { return false }
        return !user.isAnonymous
    }

    static var isAvailable: Bool { isConfigured && hasSignedInUser }

    /// Empty when available; otherwise why a gateway feature can't run.
    static func unavailabilityMessage(signInPrompt: String) -> String {
        if !isConfigured { return LLMGatewayError.notConfigured.errorDescription ?? "" }
        if !hasSignedInUser { return signInPrompt }
        return ""
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    static func get<Response: Decodable>(
        _ path: String,
        query: [String: String] = [:],
        as _: Response.Type = Response.self
    ) async throws -> Response {
        try await request(path, method: "GET", query: query, body: nil, as: Response.self)
    }

    static func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        as _: Response.Type = Response.self
    ) async throws -> Response {
        let data = try await requestData(path, method: "POST", body: try JSONEncoder().encode(body))
        return try decode(Response.self, from: data, path: path)
    }

    /// Generate call that keeps the raw `input` and `result` objects for a later vote.
    static func postGenerate<Body: Encodable, Result: Decodable>(
        _ path: String,
        body: Body,
        as _: Result.Type = Result.self
    ) async throws -> LLMGeneratePayload<Result> {
        let bodyData = try JSONEncoder().encode(body)
        let data = try await requestData(path, method: "POST", body: bodyData)
        do {
            return try decodeGeneratePayload(data, requestBody: bodyData)
        } catch let error as LLMGatewayError {
            throw error
        } catch {
            print("[LLMGateway] decode failed for \(path): \(error)")
            throw LLMGatewayError.invalidResponse
        }
    }

    /// Vote on a generate response. Failures are swallowed so the thumb can stay selected.
    static func postFeedback(
        _ receipt: LLMFeedbackReceipt,
        rating: LLMFeedbackRating,
        reason: LLMFeedbackReason?
    ) async {
        var body: [String: Any] = [
            "requestId": receipt.requestId,
            "feedbackToken": receipt.feedbackToken,
            "feature": receipt.feature,
            "model": receipt.model,
            "rating": rating.rawValue,
            "input": receipt.inputObject,
            "result": receipt.resultObject,
            "deviceId": LLMFeedbackDevice.id,
        ]
        if let reason {
            body["reason"] = reason.rawValue
        }
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            return
        }
        do {
            _ = try await requestData("v1/feedback", method: "POST", body: data)
        } catch {
            // The selected thumb stays selected. A retry would create the same doc id.
        }
    }

    private static func request<Response: Decodable>(
        _ path: String,
        method: String,
        query: [String: String] = [:],
        body: Data?,
        as _: Response.Type
    ) async throws -> Response {
        let data = try await requestData(path, method: method, query: query, body: body)
        return try decode(Response.self, from: data, path: path)
    }

    private static func requestData(
        _ path: String,
        method: String,
        query: [String: String] = [:],
        body: Data?
    ) async throws -> Data {
        guard let baseURL else { throw LLMGatewayError.notConfigured }
        guard let user = Auth.auth().currentUser, !user.isAnonymous else {
            throw LLMGatewayError.notSignedIn
        }

        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw LLMGatewayError.invalidRequest("Bad gateway URL") }

        let token = try await user.getIDToken()
        var (data, http) = try await send(url: url, method: method, body: body, token: token)
        if http.statusCode == 401 {
            let refreshed = try await user.getIDToken(forcingRefresh: true)
            (data, http) = try await send(url: url, method: method, body: body, token: refreshed)
        }

        guard (200...299).contains(http.statusCode) else {
            throw gatewayError(status: http.statusCode, data: data)
        }
        return data
    }

    private static func decode<Response: Decodable>(_ type: Response.Type, from data: Data, path: String) throws -> Response {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            print("[LLMGateway] decode failed for \(path): \(error)")
            throw LLMGatewayError.invalidResponse
        }
    }

    private static func decodeGeneratePayload<Result: Decodable>(_ data: Data, requestBody: Data) throws -> LLMGeneratePayload<Result> {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultObject = root["result"],
              let model = root["model"] as? String,
              !model.isEmpty else {
            throw LLMGatewayError.invalidResponse
        }
        let resultData = try JSONSerialization.data(withJSONObject: resultObject)
        let result = try JSONDecoder().decode(Result.self, from: resultData)

        var usage: GeminiUsageMetadata?
        if let usageObject = root["usage"], !(usageObject is NSNull) {
            let usageData = try JSONSerialization.data(withJSONObject: usageObject)
            usage = try JSONDecoder().decode(GeminiUsageMetadata.self, from: usageData)
        }

        let inputObject = try JSONSerialization.jsonObject(with: requestBody)
        let feedback: LLMFeedbackReceipt?
        if let requestId = root["requestId"] as? String,
           let token = root["feedbackToken"] as? String,
           let feature = root["feature"] as? String,
           !requestId.isEmpty,
           !token.isEmpty,
           !feature.isEmpty {
            feedback = LLMFeedbackReceipt(
                requestId: requestId,
                feedbackToken: token,
                feature: feature,
                model: model,
                inputObject: inputObject,
                resultObject: resultObject
            )
        } else {
            feedback = nil
        }
        return LLMGeneratePayload(result: result, model: model, usage: usage, feedback: feedback)
    }

    private static func send(url: URL, method: String, body: Data?, token: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMGatewayError.invalidResponse
        }
        return (data, http)
    }

    private struct ErrorBody: Decodable {
        let error: String
        let detail: String?
    }

    private static func gatewayError(status: Int, data: Data) -> LLMGatewayError {
        let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
        print("[LLMGateway] HTTP \(status): \(body?.error ?? String(data: data, encoding: .utf8) ?? "")")
        switch status {
        case 401:
            return .unauthorized
        case 400, 413:
            return .invalidRequest(body?.detail ?? "The request was rejected (\(body?.error ?? "invalid_request")).")
        case 502:
            return .upstream
        default:
            return .httpStatus(status)
        }
    }
}
