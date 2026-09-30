//
//  GeminiDialogueNuance.swift
//  shizen
//
//  Cloud Gemini notes for what a dialogue line really means — implied
//  refusals, unasked offers, cultural quirks — using surrounding lines
//  as context. Served by the LLM gateway (feature `dialogue_nuance`);
//  the prompt lives server-side.
//

import Foundation

/// A focused dialogue line plus a few neighbors so the model can judge
/// tone, relationship, and implied meaning.
struct DialogueNuanceContext: Equatable {
    struct Line: Equatable {
        let speaker: String
        let japanese: String
        let english: String?
    }

    let preceding: [Line]
    let focused: Line
    let following: [Line]

    static let neighborRadius = 2

    static func isolated(japanese: String, english: String?, speaker: String = "") -> DialogueNuanceContext {
        DialogueNuanceContext(
            preceding: [],
            focused: Line(speaker: speaker, japanese: japanese, english: english),
            following: []
        )
    }

    static func around(lines: [Line], focusedIndex: Int, radius: Int = neighborRadius) -> DialogueNuanceContext? {
        guard lines.indices.contains(focusedIndex) else { return nil }
        let start = max(0, focusedIndex - radius)
        let end = min(lines.count - 1, focusedIndex + radius)
        let preceding = start < focusedIndex ? Array(lines[start..<focusedIndex]) : []
        let following = focusedIndex < end ? Array(lines[(focusedIndex + 1)...end]) : []
        return DialogueNuanceContext(
            preceding: preceding,
            focused: lines[focusedIndex],
            following: following
        )
    }
}

enum GeminiDialogueNuance {

    struct Result: Equatable {
        let naturalMeaning: String
        let impliedMeaning: String
        let notes: String
    }

    struct Explanation {
        let result: Result
        let feedback: LLMFeedbackReceipt?
    }

    struct Request: Equatable {
        let context: DialogueNuanceContext
    }

    private actor Cache {
        static let shared = Cache()
        private var storage: [String: Explanation] = [:]

        func result(for key: String) -> Explanation? {
            storage[key]
        }

        func store(_ result: Explanation, for key: String) {
            storage[key] = result
        }
    }

    static var isConfigured: Bool {
        LLMGatewayClient.isConfigured && LLMGatewayClient.hasSignedInUser
    }

    static var isAvailable: Bool {
        isConfigured
    }

    static var unavailabilityMessage: String {
        if !LLMGatewayClient.isConfigured {
            return LLMGatewayError.notConfigured.errorDescription ?? ""
        }
        if !LLMGatewayClient.hasSignedInUser {
            return "Sign in to see dialogue nuance."
        }
        return ""
    }

    static func cachedResult(for request: Request) async -> Explanation? {
        await Cache.shared.result(for: cacheKey(for: request))
    }

    static func explain(_ request: Request) async throws -> Explanation {
        let focused = request.context.focused.japanese.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !focused.isEmpty else {
            throw NuanceError.invalidInput
        }

        let cacheKey = Self.cacheKey(for: request)
        if let cached = await Cache.shared.result(for: cacheKey) {
            return cached
        }

        guard isConfigured else {
            throw NuanceError.unavailable(unavailabilityMessage)
        }

        print("[GeminiDialogueNuance] explaining focused line: \"\(focused)\" via gateway")

        let context = request.context
        let response = try await LLMGatewayClient.postGenerate(
            "v1/generate",
            body: GatewayRequest(
                preceding: Array(gatewayLines(context.preceding).suffix(DialogueNuanceContext.neighborRadius)),
                focused: GatewayLine(context.focused),
                following: Array(gatewayLines(context.following).prefix(DialogueNuanceContext.neighborRadius))
            ),
            as: NuancePayload.self
        )
        if let usage = response.usage {
            GeminiUsageTracker.shared.record(feature: .dialogueNuance, model: response.model, usage: usage)
        }

        let payload = response.result
        let result = Result(
            naturalMeaning: payload.naturalMeaning.trimmingCharacters(in: .whitespacesAndNewlines),
            impliedMeaning: payload.impliedMeaning.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: payload.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !result.impliedMeaning.isEmpty else {
            throw NuanceError.emptyResponse
        }
        let explanation = Explanation(result: result, feedback: response.feedback)
        await Cache.shared.store(explanation, for: cacheKey)
        return explanation
    }

    // MARK: - Gateway

    private struct GatewayLine: Encodable {
        let speaker: String?
        let japanese: String
        let english: String?

        init(_ line: DialogueNuanceContext.Line) {
            let speaker = line.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
            let english = line.english?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.speaker = speaker.isEmpty ? nil : speaker
            japanese = line.japanese.trimmingCharacters(in: .whitespacesAndNewlines)
            self.english = english?.isEmpty == false ? english : nil
        }
    }

    private struct GatewayRequest: Encodable {
        let feature = "dialogue_nuance"
        let preceding: [GatewayLine]
        let focused: GatewayLine
        let following: [GatewayLine]
    }

    private struct NuancePayload: Decodable {
        let naturalMeaning: String
        let impliedMeaning: String
        let notes: String
    }

    /// The gateway takes at most `neighborRadius` non-empty neighbors on each side.
    private static func gatewayLines(_ lines: [DialogueNuanceContext.Line]) -> [GatewayLine] {
        lines.map(GatewayLine.init).filter { !$0.japanese.isEmpty }
    }

    private static func cacheKey(for request: Request) -> String {
        func lineKey(_ line: DialogueNuanceContext.Line) -> String {
            [
                line.speaker,
                line.japanese,
                line.english ?? "",
            ].joined(separator: "\u{1E}")
        }
        return [
            "gemini-nuance-v5-gateway",
            request.context.preceding.map(lineKey).joined(separator: "\u{1D}"),
            lineKey(request.context.focused),
            request.context.following.map(lineKey).joined(separator: "\u{1D}"),
        ].joined(separator: "\u{1F}")
    }

    enum NuanceError: LocalizedError {
        case invalidInput
        case unavailable(String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .invalidInput:
                return "Missing dialogue line."
            case .unavailable(let message):
                return message
            case .emptyResponse:
                return "Gemini returned an empty explanation."
            }
        }
    }
}
