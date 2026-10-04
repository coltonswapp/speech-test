//
//  GeminiContextualGloss.swift
//  shizen
//
//  Cloud Gemini contextual English gloss for a word selected in a sentence.
//  Mirrors FoundationModelContextualGloss's contract so callers can swap between the two.
//  Served by the LLM gateway (feature `contextual_gloss`); the prompt lives server-side.
//

import Foundation

enum GeminiContextualGloss {

    struct Result: Equatable {
        let meaning: String
        let grammarNote: String
        let relatedWords: [ContextualRelatedWord]
        let headword: String
    }

    struct Request: Equatable {
        let sentence: String
        let surface: String
        let dictionaryForm: String?
        let dictionaryGloss: String?
        let framing: ContextualGlossFraming
        let requestsHeadword: Bool
    }

    private actor Cache {
        static let shared = Cache()
        private var storage: [String: Result] = [:]

        func result(for key: String) -> Result? {
            storage[key]
        }

        func store(_ result: Result, for key: String) {
            storage[key] = result
        }
    }

    static var isConfigured: Bool {
        LLMGatewayClient.isConfigured && LLMGatewayClient.hasSignedInUser
    }

    static func cachedResult(for request: Request) async -> Result? {
        await Cache.shared.result(for: cacheKey(for: request))
    }

    static func explain(_ request: Request) async throws -> Result {
        let sentence = request.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let surface = request.surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty, !surface.isEmpty else {
            throw GlossError.invalidInput
        }

        let cacheKey = Self.cacheKey(for: request)
        if let cached = await Cache.shared.result(for: cacheKey) {
            return cached
        }

        guard isConfigured else {
            throw GlossError.unavailable
        }

        print("[GeminiContextualGloss] explaining \"\(surface)\" in sentence: \"\(sentence)\" via gateway")

        let response = try await LLMGatewayClient.post(
            "v1/generate",
            body: GatewayRequest(
                feature: "contextual_gloss",
                sentence: sentence,
                surface: surface,
                dictionaryForm: nonEmpty(request.dictionaryForm),
                dictionaryGloss: nonEmpty(request.dictionaryGloss),
                framing: request.framing.rawValue,
                requestsHeadword: request.requestsHeadword
            ),
            as: GatewayResponse.self
        )
        if let usage = response.usage {
            GeminiUsageTracker.shared.record(feature: .contextualGloss, model: response.model, usage: usage)
        }

        let payload = response.result
        let result = sanitizedResult(
            meaning: payload.meaning,
            grammarNote: payload.grammarNote,
            relatedWords: payload.relatedWords.map { ($0.word, $0.note) },
            headword: payload.headword,
            request: request
        )
        guard !result.meaning.isEmpty else {
            throw GlossError.emptyResponse
        }
        await Cache.shared.store(result, for: cacheKey)
        return result
    }

    // MARK: - Gateway

    private struct GatewayRequest: Encodable {
        let feature: String
        let sentence: String
        let surface: String
        let dictionaryForm: String?
        let dictionaryGloss: String?
        let framing: String
        let requestsHeadword: Bool
    }

    private struct GatewayResponse: Decodable {
        let result: GlossPayload
        let model: String
        let usage: GeminiUsageMetadata?
    }

    private struct GlossPayload: Decodable {
        struct RelatedWord: Decodable {
            let word: String
            let note: String
        }

        let meaning: String
        let grammarNote: String
        let relatedWords: [RelatedWord]
        let headword: String

        enum CodingKeys: String, CodingKey {
            case meaning, grammarNote, relatedWords, headword
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            meaning = try container.decode(String.self, forKey: .meaning)
            grammarNote = try container.decodeIfPresent(String.self, forKey: .grammarNote) ?? ""
            relatedWords = try container.decodeIfPresent([RelatedWord].self, forKey: .relatedWords) ?? []
            headword = try container.decodeIfPresent(String.self, forKey: .headword) ?? ""
        }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    // MARK: - Sanitization (shared rules with the on-device gloss)

    private static let metaLabelPhrases = [
        "transparent compound",
        "opaque compound",
        "loanword",
        "loan word",
        "abbreviation",
        "clipping",
        "portmanteau",
        "compound word",
        "katakana word",
        "wasei",
    ]

    private static func sanitizedResult(
        meaning: String,
        grammarNote: String,
        relatedWords: [(String, String)],
        headword: String,
        request: Request
    ) -> Result {
        var gloss = glossWithoutVerbLabel(meaning)
        var grammar = glossWithoutVerbLabel(grammarNote)

        if isMetaLabelOnly(gloss),
           let dictionary = request.dictionaryGloss?.trimmingCharacters(in: .whitespacesAndNewlines),
           !dictionary.isEmpty {
            gloss = shortGloss(from: dictionary)
        } else if isMetaLabelOnly(gloss) {
            gloss = ""
        }
        if isMetaLabelOnly(grammar) {
            grammar = ""
        }

        let related = ContextualRelatedWord.sanitized(
            from: relatedWords,
            surface: request.surface,
            dictionaryForm: request.dictionaryForm
        )
        let resolvedHeadword = request.requestsHeadword ? ContextualHeadword.sanitized(headword) : ""
        return Result(meaning: gloss, grammarNote: grammar, relatedWords: related, headword: resolvedHeadword)
    }

    private static func isMetaLabelOnly(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".…"))
        guard !normalized.isEmpty else { return false }
        return metaLabelPhrases.contains { phrase in
            normalized == phrase || normalized.hasPrefix(phrase + " ") || normalized.hasPrefix(phrase + ".")
        }
    }

    private static func shortGloss(from dictionaryGloss: String) -> String {
        let first = dictionaryGloss
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? dictionaryGloss
        let words = first.split(separator: " ")
        guard words.count > 8 else { return first }
        return words.prefix(8).joined(separator: " ")
    }

    private static func cacheKey(for request: Request) -> String {
        var parts = [
            request.requestsHeadword ? "gemini-gloss-v7-gateway-headword" : "gemini-gloss-v7-gateway",
            request.framing.rawValue,
            request.sentence,
            request.surface,
            request.dictionaryForm ?? "",
            request.dictionaryGloss ?? "",
        ]
        if request.requestsHeadword {
            parts.append("headword")
        }
        return parts.joined(separator: "\u{1F}")
    }

    enum GlossError: LocalizedError {
        case invalidInput
        case unavailable
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .invalidInput:
                return "Missing sentence or selected word."
            case .unavailable:
                return LLMGatewayClient.isConfigured
                    ? "Sign in to see Gemini word insights."
                    : LLMGatewayError.notConfigured.errorDescription
            case .emptyResponse:
                return "Gemini returned an empty gloss."
            }
        }
    }
}
