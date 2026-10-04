//
//  GeminiTokenLookup.swift
//  shizen
//
//  Gemini lookups for the sentence-scrub detail card: how one word is used
//  (Common Uses), and what a selected span means together (span gloss, break down).
//  Served by the LLM gateway (`POST /v1/generate`); prompts live server-side.
//

import Foundation

/// Feature `common_uses`.
enum GeminiCommonUses {

    struct Result: Equatable {
        let inThisSentence: String
        let otherUses: [String]
        /// Short kanji composition, or empty when the pieces don't add anything.
        let kanjiNote: String
    }

    struct Explanation {
        let result: Result
        let feedback: LLMFeedbackReceipt?
    }

    struct Request: Equatable {
        let sentence: String
        let surface: String
        let dictionaryGloss: String?
    }

    private actor Cache {
        static let shared = Cache()
        private var storage: [String: Explanation] = [:]

        func result(for key: String) -> Explanation? { storage[key] }

        func store(_ result: Explanation, for key: String) { storage[key] = result }
    }

    static var isConfigured: Bool { LLMGatewayClient.isAvailable }

    static var unavailabilityMessage: String {
        LLMGatewayClient.unavailabilityMessage(signInPrompt: "Sign in to see common uses.")
    }

    static func cachedResult(for request: Request) async -> Explanation? {
        await Cache.shared.result(for: cacheKey(for: request))
    }

    static func explain(_ request: Request) async throws -> Explanation {
        let sentence = request.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let surface = request.surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty, !surface.isEmpty else {
            throw GeminiTokenLookupError.invalidInput
        }

        let cacheKey = Self.cacheKey(for: request)
        if let cached = await Cache.shared.result(for: cacheKey) {
            return cached
        }
        guard isConfigured else {
            throw GeminiTokenLookupError.unavailable(unavailabilityMessage)
        }

        let hint = request.dictionaryGloss?.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[GeminiCommonUses] explaining \"\(surface)\" in \"\(sentence)\" via gateway")
        let response = try await LLMGatewayClient.postGenerate(
            "v1/generate",
            body: GatewayRequest(
                surface: surface,
                sentence: sentence,
                feature: "common_uses",
                dictionaryGloss: hint?.isEmpty == false ? hint : nil
            ),
            as: Payload.self
        )
        if let usage = response.usage {
            GeminiUsageTracker.shared.record(feature: .commonUses, model: response.model, usage: usage)
        }

        let result = sanitized(response.result, surface: surface)
        guard !result.inThisSentence.isEmpty else {
            throw GeminiTokenLookupError.emptyResponse
        }
        let explanation = Explanation(result: result, feedback: response.feedback)
        await Cache.shared.store(explanation, for: cacheKey)
        return explanation
    }

    private struct GatewayRequest: Encodable {
        let surface: String
        let sentence: String
        let feature: String
        let dictionaryGloss: String?
    }

    private struct Payload: Decodable {
        let inThisSentence: String
        let otherUses: [String]
        let kanjiNote: String

        enum CodingKeys: String, CodingKey {
            case inThisSentence, otherUses, kanjiNote
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            inThisSentence = try container.decode(String.self, forKey: .inThisSentence)
            otherUses = try container.decodeIfPresent([String].self, forKey: .otherUses) ?? []
            kanjiNote = try container.decodeIfPresent(String.self, forKey: .kanjiNote) ?? ""
        }
    }

    private static func sanitized(_ payload: Payload, surface: String) -> Result {
        let here = glossWithoutVerbLabel(payload.inThisSentence.trimmingCharacters(in: .whitespacesAndNewlines))
        var seen = Set<String>()
        var others: [String] = []
        for raw in payload.otherUses {
            let phrase = glossWithoutVerbLabel(raw.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !phrase.isEmpty, phrase.count <= 160, phrase != here, phrase != surface else { continue }
            guard seen.insert(phrase).inserted else { continue }
            others.append(phrase)
            if others.count == 4 { break }
        }
        let kanjiNote = sanitizedKanjiNote(payload.kanjiNote, surface: surface, inThisSentence: here)
        return Result(inThisSentence: here, otherUses: others, kanjiNote: kanjiNote)
    }

    /// Keeps a short composition line that actually names kanji. Drops essays and notes with no kanji.
    private static func sanitizedKanjiNote(_ raw: String, surface: String, inThisSentence: String) -> String {
        let note = glossWithoutVerbLabel(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !note.isEmpty, note.count <= 140, note != inThisSentence, note != surface else { return "" }
        let namesKanji = note.unicodeScalars.contains { scalar in
            let value = scalar.value
            return (0x3400...0x4DBF).contains(value) || (0x4E00...0x9FFF).contains(value) || value == 0x3005
        }
        return namesKanji ? note : ""
    }

    private static func cacheKey(for request: Request) -> String {
        [
            "gemini-common-uses-v6-gateway",
            request.sentence,
            request.surface,
            request.dictionaryGloss ?? "",
        ].joined(separator: "\u{1F}")
    }
}

/// Extra reading for a selected span: how the pieces fit, and other uses only when it is a real expression.
/// Feature `span_breakdown`.
enum GeminiSpanBreakdown {

    struct Result: Equatable {
        let inThisSentence: String
        let otherUses: [String]
        let partsNote: String
    }

    struct Explanation {
        let result: Result
        let feedback: LLMFeedbackReceipt?
    }

    struct Request: Equatable {
        let sentence: String
        let surface: String
    }

    private actor Cache {
        static let shared = Cache()
        private var storage: [String: Explanation] = [:]

        func result(for key: String) -> Explanation? { storage[key] }

        func store(_ result: Explanation, for key: String) { storage[key] = result }
    }

    static var isConfigured: Bool { LLMGatewayClient.isAvailable }

    static var unavailabilityMessage: String {
        LLMGatewayClient.unavailabilityMessage(signInPrompt: "Sign in to break down this phrase.")
    }

    static func cachedResult(for request: Request) async -> Explanation? {
        await Cache.shared.result(for: cacheKey(for: request))
    }

    static func explain(_ request: Request) async throws -> Explanation {
        let sentence = request.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let surface = request.surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty, !surface.isEmpty else {
            throw GeminiTokenLookupError.invalidInput
        }

        let cacheKey = Self.cacheKey(for: request)
        if let cached = await Cache.shared.result(for: cacheKey) {
            return cached
        }
        guard isConfigured else {
            throw GeminiTokenLookupError.unavailable(unavailabilityMessage)
        }

        print("[GeminiSpanBreakdown] explaining \"\(surface)\" in \"\(sentence)\" via gateway")
        let response = try await LLMGatewayClient.postGenerate(
            "v1/generate",
            body: SpanGatewayRequest(feature: "span_breakdown", sentence: sentence, surface: surface),
            as: Payload.self
        )
        if let usage = response.usage {
            GeminiUsageTracker.shared.record(feature: .spanBreakdown, model: response.model, usage: usage)
        }

        let result = sanitized(response.result, surface: surface)
        guard !result.inThisSentence.isEmpty else {
            throw GeminiTokenLookupError.emptyResponse
        }
        let explanation = Explanation(result: result, feedback: response.feedback)
        await Cache.shared.store(explanation, for: cacheKey)
        return explanation
    }

    private struct Payload: Decodable {
        let inThisSentence: String
        let otherUses: [String]
        let partsNote: String

        enum CodingKeys: String, CodingKey {
            case inThisSentence, otherUses, partsNote
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            inThisSentence = try container.decode(String.self, forKey: .inThisSentence)
            otherUses = try container.decodeIfPresent([String].self, forKey: .otherUses) ?? []
            partsNote = try container.decodeIfPresent(String.self, forKey: .partsNote) ?? ""
        }
    }

    private static func sanitized(_ payload: Payload, surface: String) -> Result {
        let here = glossWithoutVerbLabel(payload.inThisSentence.trimmingCharacters(in: .whitespacesAndNewlines))
        var seen = Set<String>()
        var others: [String] = []
        for raw in payload.otherUses {
            let phrase = glossWithoutVerbLabel(raw.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !phrase.isEmpty, phrase.count <= 160, phrase != here, phrase != surface else { continue }
            guard seen.insert(phrase).inserted else { continue }
            others.append(phrase)
            if others.count == 4 { break }
        }
        var note = glossWithoutVerbLabel(payload.partsNote.trimmingCharacters(in: .whitespacesAndNewlines))
        if note == here || note == surface || note.count > 160 { note = "" }
        return Result(inThisSentence: here, otherUses: others, partsNote: note)
    }

    private static func cacheKey(for request: Request) -> String {
        [
            "gemini-span-breakdown-v4-gateway",
            request.sentence,
            request.surface,
        ].joined(separator: "\u{1F}")
    }
}

/// Feature `span_gloss`.
enum GeminiSpanGloss {

    struct Result: Equatable {
        let meaning: String
        let note: String
    }

    struct Explanation {
        let result: Result
        let feedback: LLMFeedbackReceipt?
    }

    struct Request: Equatable {
        let sentence: String
        let surface: String
    }

    private actor Cache {
        static let shared = Cache()
        private var storage: [String: Explanation] = [:]

        func result(for key: String) -> Explanation? { storage[key] }

        func store(_ result: Explanation, for key: String) { storage[key] = result }
    }

    static var isConfigured: Bool { LLMGatewayClient.isAvailable }

    static var unavailabilityMessage: String {
        LLMGatewayClient.unavailabilityMessage(signInPrompt: "Sign in to see what this phrase means here.")
    }

    static func cachedResult(for request: Request) async -> Explanation? {
        await Cache.shared.result(for: cacheKey(for: request))
    }

    static func explain(_ request: Request) async throws -> Explanation {
        let sentence = request.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let surface = request.surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty, !surface.isEmpty else {
            throw GeminiTokenLookupError.invalidInput
        }

        let cacheKey = Self.cacheKey(for: request)
        if let cached = await Cache.shared.result(for: cacheKey) {
            return cached
        }
        guard isConfigured else {
            throw GeminiTokenLookupError.unavailable(unavailabilityMessage)
        }

        print("[GeminiSpanGloss] explaining \"\(surface)\" in \"\(sentence)\" via gateway")
        let response = try await LLMGatewayClient.postGenerate(
            "v1/generate",
            body: SpanGatewayRequest(feature: "span_gloss", sentence: sentence, surface: surface),
            as: Payload.self
        )
        if let usage = response.usage {
            GeminiUsageTracker.shared.record(feature: .spanGloss, model: response.model, usage: usage)
        }

        let meaning = response.result.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        var note = response.result.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if note == meaning { note = "" }
        guard !meaning.isEmpty else {
            throw GeminiTokenLookupError.emptyResponse
        }
        let result = Result(meaning: meaning, note: note)
        let explanation = Explanation(result: result, feedback: response.feedback)
        await Cache.shared.store(explanation, for: cacheKey)
        return explanation
    }

    private struct Payload: Decodable {
        let meaning: String
        let note: String
    }

    private static func cacheKey(for request: Request) -> String {
        [
            "gemini-span-gloss-v2-gateway",
            request.sentence,
            request.surface,
        ].joined(separator: "\u{1F}")
    }
}

enum GeminiTokenLookupError: LocalizedError {
    case invalidInput
    case unavailable(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Missing sentence or selected text."
        case .unavailable(let message):
            return message
        case .emptyResponse:
            return "Gemini returned an empty explanation."
        }
    }
}

// MARK: - Gateway plumbing shared by the token lookups

private struct SpanGatewayRequest: Encodable {
    let feature: String
    let sentence: String
    let surface: String
}

