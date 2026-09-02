//
//  GeminiJapaneseTokenizer.swift
//  shizen
//
//  Cloud Gemini segmentation for learner-focused Japanese tokenization.
//

import Foundation

actor GeminiJapaneseTokenCache {
    static let shared = GeminiJapaneseTokenCache()

    private var storage: [String: [JapaneseToken]] = [:]

    func tokens(for sentence: String, model: GeminiJapaneseTokenizer.Model) -> [JapaneseToken]? {
        storage[Self.cacheKey(sentence: sentence, model: model)]
    }

    func store(_ tokens: [JapaneseToken], for sentence: String, model: GeminiJapaneseTokenizer.Model) {
        storage[Self.cacheKey(sentence: sentence, model: model)] = tokens
    }

    func remove(for sentence: String, model: GeminiJapaneseTokenizer.Model) {
        storage.removeValue(forKey: Self.cacheKey(sentence: sentence, model: model))
    }

    private static func cacheKey(sentence: String, model: GeminiJapaneseTokenizer.Model) -> String {
        "\(model.rawValue)\u{1F}\(sentence)"
    }
}

enum GeminiJapaneseTokenizer {

    enum Model: String {
        case flash = "gemini-2.5-flash"
        case flashLite = "gemini-2.5-flash-lite"
        case flash31Lite = "gemini-3.1-flash-lite"
    }

    struct Result {
        let tokens: [JapaneseToken]
    }

    private static let endpointBase = "https://generativelanguage.googleapis.com/v1beta/models"
    private static let deterministicSeed = 42

    private static let instructionsText = """
    Segment Japanese text into dictionary lookup units for language learners.
    Return a JSON object with a "tokens" array in original left-to-right order.
    Every token MUST be copied verbatim from the input — a contiguous substring using the \
    original Japanese script (kanji, hiragana, katakana).
    NEVER output romaji, Latin letters, English, phonetic spellings, or translations.
    Tokens must appear in order and together cover the full input.
    Include every part of the sentence — do not skip particles, endings, or punctuation.
    Keep conjugated verbs together as one token when a learner would tap them as a unit \
    (e.g. 食べちゃいけない, 行きましょう, 飲まなくちゃ, 残ってる, 走ってる, 持ってる).
    NEVER split a verb mid-contraction — っ and the following て/てる/た/たら must stay with the verb stem \
    (e.g. 残ってる is one token, NOT 残っ + てる).
    Use sentence context: do not split casual endings into standalone hiragana that would mislead lookup \
    (e.g. in 食べちゃいけない keep ちゃ with the verb — not as separate ちゃ “tea”).
    Keep the colloquial explanatory ending ん + です/だ glued together as one token, and \
    glue it together with an immediately following けど/か/よ/から/が too — \
    do not split ん from です/だ or from that trailing particle \
    (e.g. in 行きたいんですけど keep んですけど as one token, not ん + です + けど; \
    similarly んですか, んだよ, んだから, んですが each stay as one token).
    Split standalone particles, nouns, and punctuation when that helps lookup.
    Keep punctuation as separate tokens when present.
    Punctuation (、 。 ， ． , . ！ ？ ! ? … ・ etc.) is always a hard token boundary. \
    NEVER keep words on both sides of a comma or period in one token \
    (e.g. え、いいん must be え and いいん, not one token).
    """

    private static let retrySuffix = """

    CRITICAL: Copy tokens exactly from the input string. \
    For 歩いて use 歩いて or 歩い and て in Japanese script — never arui, aruite, or te in Latin letters.
    """

    static var isConfigured: Bool {
        !GeminiAppKey.resolved.isEmpty
    }

    static var configurationMessage: String {
        isConfigured ? "Gemini API key is configured." : "Add a Gemini API key to use cloud segmentation."
    }

    static func tokenize(
        _ text: String,
        model: Model = .flash,
        useCache: Bool = true
    ) async throws -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Result(tokens: [])
        }

        if useCache, let cached = await GeminiJapaneseTokenCache.shared.tokens(for: trimmed, model: model) {
            return Result(tokens: cached)
        }

        guard isConfigured else {
            throw TokenizeError.missingAPIKey
        }

        print("[GeminiTokenizer] tokenizing sentence (\(model.rawValue)): \"\(trimmed)\"")

        let surfaces = try await fetchTokenSurfaces(for: trimmed, model: model, isRetry: false)
        print("[GeminiTokenizer] surfaces: \(surfaces)")
        if let tokens = JapaneseSegmentationMapping.validatedTokens(from: surfaces, in: trimmed) {
            print("[GeminiTokenizer] validated tokens: \(tokens.map(\.text))")
            let merged = JapaneseSegmentationMapping.mergeColloquialExplanatorySuffixes(tokens, in: trimmed)
            print("[GeminiTokenizer] merged tokens: \(merged.map(\.text))")
            await GeminiJapaneseTokenCache.shared.store(merged, for: trimmed, model: model)
            return Result(tokens: merged)
        }

        print("[GeminiTokenizer] validation failed for surfaces \(surfaces) against \"\(trimmed)\" — retrying")

        let retrySurfaces = try await fetchTokenSurfaces(for: trimmed, model: model, isRetry: true)
        print("[GeminiTokenizer] retry surfaces: \(retrySurfaces)")
        if let tokens = JapaneseSegmentationMapping.validatedTokens(from: retrySurfaces, in: trimmed) {
            print("[GeminiTokenizer] validated tokens (retry): \(tokens.map(\.text))")
            let merged = JapaneseSegmentationMapping.mergeColloquialExplanatorySuffixes(tokens, in: trimmed)
            print("[GeminiTokenizer] merged tokens (retry): \(merged.map(\.text))")
            await GeminiJapaneseTokenCache.shared.store(merged, for: trimmed, model: model)
            return Result(tokens: merged)
        }

        print("[GeminiTokenizer] retry validation also failed for surfaces \(retrySurfaces) against \"\(trimmed)\"")

        throw TokenizeError.unusableSegmentation(
            original: surfaces,
            retried: retrySurfaces
        )
    }

    // MARK: - API

    private struct GenerateContentRequest: Encodable {
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

                    struct ItemType: Encodable {
                        let type: String
                    }
                }

                let type: String
                let properties: [String: Property]
                let required: [String]
            }

            let responseMimeType: String
            let responseSchema: Schema
            let temperature: Double
            let topP: Double
            let topK: Int
            let seed: Int
            let candidateCount: Int
        }

        let contents: [Content]
        let generationConfig: GenerationConfig
    }

    private struct GenerateContentResponse: Decodable {
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
            struct Detail: Decodable {
                let message: String?
            }

            let message: String?
            let status: String?
        }

        let candidates: [Candidate]?
        let error: APIError?
        let usageMetadata: GeminiUsageMetadata?
    }

    private struct SegmentationPayload: Decodable {
        let tokens: [String]
    }

    private static func fetchTokenSurfaces(
        for text: String,
        model: Model,
        isRetry: Bool
    ) async throws -> [String] {
        let prompt = if isRetry {
            "\(instructionsText)\(retrySuffix)\n\nInput:\n\(text)"
        } else {
            "\(instructionsText)\n\nInput:\n\(text)"
        }
        print("[GeminiTokenizer] request (isRetry: \(isRetry), model: \(model.rawValue)) prompt:\n\(prompt)")
        let requestBody = GenerateContentRequest(
            contents: [
                .init(parts: [.init(text: prompt)]),
            ],
            generationConfig: .init(
                responseMimeType: "application/json",
                responseSchema: .init(
                    type: "object",
                    properties: [
                        "tokens": .init(type: "array", items: .init(type: "string")),
                    ],
                    required: ["tokens"]
                ),
                temperature: 0,
                topP: 1,
                topK: 1,
                seed: deterministicSeed,
                candidateCount: 1
            )
        )

        guard let url = URL(string: "\(endpointBase)/\(model.rawValue):generateContent") else {
            throw TokenizeError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(GeminiAppKey.resolved, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TokenizeError.invalidResponse
        }

        let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8 body, \(data.count) bytes>"
        print("[GeminiTokenizer] response (status \(http.statusCode)) raw body:\n\(rawBody)")

        let decoded = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        if let usage = decoded.usageMetadata {
            GeminiUsageTracker.shared.record(feature: .tokenizer, model: model.rawValue, usage: usage)
        }
        if let apiError = decoded.error {
            let message = apiError.message ?? apiError.status ?? "Gemini API error"
            throw TokenizeError.api(message)
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw TokenizeError.api(body)
        }

        guard
            let jsonText = decoded.candidates?.first?.content?.parts?.first?.text,
            let jsonData = jsonText.data(using: .utf8)
        else {
            throw TokenizeError.invalidResponse
        }

        print("[GeminiTokenizer] response candidate text (isRetry: \(isRetry)):\n\(jsonText)")

        let payload = try JSONDecoder().decode(SegmentationPayload.self, from: jsonData)
        print("[GeminiTokenizer] decoded tokens (isRetry: \(isRetry)): \(payload.tokens)")
        return payload.tokens
    }

    enum TokenizeError: LocalizedError {
        case missingAPIKey
        case invalidConfiguration
        case invalidResponse
        case api(String)
        case unusableSegmentation(original: [String], retried: [String])

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Gemini API key is not configured."
            case .invalidConfiguration:
                return "Gemini tokenizer is misconfigured."
            case .invalidResponse:
                return "Gemini returned an unexpected response."
            case .api(let message):
                return message
            case .unusableSegmentation(let original, let retried):
                let first = original.joined(separator: " | ")
                let second = retried.joined(separator: " | ")
                return "Gemini returned non-Japanese or non-matching tokens. First: \(first). Retry: \(second)."
            }
        }
    }
}
