//
//  GeminiClient.swift
//  GrammarContentKit
//

import Foundation

public enum GeminiClient {

    public enum Model: String, Sendable {
        case flash = "gemini-2.5-flash"
        case flashLite = "gemini-2.5-flash-lite"
    }

    public enum ClientError: LocalizedError, Sendable {
        case missingAPIKey
        case invalidConfiguration
        case invalidResponse
        case api(String)

        public var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "Gemini API key is not configured."
            case .invalidConfiguration: return "Gemini client is misconfigured."
            case .invalidResponse: return "Gemini returned an unexpected response."
            case .api(let message): return message
            }
        }
    }

    struct GenerateContentRequest: Encodable {
        struct Content: Encodable {
            struct Part: Encodable {
                let text: String
            }

            let parts: [Part]
        }

        struct GenerationConfig: Encodable {
            struct Schema: Encodable {
                struct Property: Encodable {
                    let type: String
                    let items: ItemType?
                    let properties: [String: Property]?
                    let required: [String]?

                    struct ItemType: Encodable {
                        let type: String
                    }

                    init(
                        type: String,
                        items: ItemType? = nil,
                        properties: [String: Property]? = nil,
                        required: [String]? = nil
                    ) {
                        self.type = type
                        self.items = items
                        self.properties = properties
                        self.required = required
                    }
                }

                let type: String
                let properties: [String: Property]?
                let required: [String]?
            }

            let responseMimeType: String
            let responseSchema: Schema?
            let temperature: Double
            let topP: Double
            let topK: Int
            let seed: Int
            let candidateCount: Int
        }

        let contents: [Content]
        let generationConfig: GenerationConfig
    }

    struct GenerateContentResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    let text: String?
                }

                let parts: [Part]?
            }

            let content: Content?
        }

        struct APIError: Decodable {
            let message: String?
            let status: String?
        }

        let candidates: [Candidate]?
        let error: APIError?
    }

    private static let endpointBase = "https://generativelanguage.googleapis.com/v1beta/models"
    private static let deterministicSeed = 42

    public static func generateJSON(
        apiKey: String,
        prompt: String,
        model: Model = .flash,
        temperature: Double = 0.4,
        useSchema: Bool = true
    ) async throws -> Data {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.missingAPIKey
        }

        let schema: GenerateContentRequest.GenerationConfig.Schema? = useSchema
            ? .init(
                type: "object",
                properties: ["grammarPoint": .init(type: "object")],
                required: ["grammarPoint"]
            )
            : nil

        let requestBody = GenerateContentRequest(
            contents: [.init(parts: [.init(text: prompt)])],
            generationConfig: .init(
                responseMimeType: "application/json",
                responseSchema: schema,
                temperature: temperature,
                topP: 1,
                topK: 40,
                seed: deterministicSeed,
                candidateCount: 1
            )
        )

        guard let url = URL(string: "\(endpointBase)/\(model.rawValue):generateContent") else {
            throw ClientError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        if let apiError = decoded.error {
            let message = apiError.message ?? apiError.status ?? "Gemini API error"
            throw ClientError.api(message)
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw ClientError.api(body)
        }

        guard
            let jsonText = decoded.candidates?.first?.content?.parts?.first?.text,
            let jsonData = jsonText.data(using: .utf8)
        else {
            throw ClientError.invalidResponse
        }

        return jsonData
    }
}
