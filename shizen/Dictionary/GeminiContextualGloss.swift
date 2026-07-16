//
//  GeminiContextualGloss.swift
//  shizen
//
//  Cloud Gemini contextual English gloss for a word selected in a sentence.
//  Mirrors FoundationModelContextualGloss's contract so callers can swap between the two.
//

import Foundation

enum GeminiContextualGloss {

    enum Model: String {
        case flash = "gemini-2.5-flash"
        case flashLite = "gemini-2.5-flash-lite"
    }

    struct Result: Equatable {
        let meaning: String
        let grammarNote: String
    }

    struct Request: Equatable {
        let sentence: String
        let surface: String
        let dictionaryForm: String?
        let dictionaryGloss: String?
    }

    private static let endpointBase = "https://generativelanguage.googleapis.com/v1beta/models"
    private static let deterministicSeed = 42

    private static let instructionsText = """
    You help Japanese language learners understand one selected token inside a full sentence.

    Write for a beginner. Use only plain, useful English — never linguistics or morphology labels.

    meaning (2-8 words):
    - Give what the token means here. Do not translate the whole sentence.
    - When the word is built from familiar parts, give the natural composed meaning \
    (何時 → what time; 大学生 → university student; スマホ → smartphone).
    - For conjugated forms, reflect the inflection when it changes the sense (行きましょう → let's go).
    - NEVER output meta labels such as: transparent compound, opaque compound, loanword, \
    abbreviation, clipping, portmanteau, compound word, katakana word.

    grammarNote:
    - Only when the token itself has non-obvious grammar worth a short learner note.
    - OK: inflection, a particle fused to the token, politeness encoded in the form.
    - Use an empty string when the meaning alone is enough (most nouns, abbreviations, simple compounds).
    - Do NOT describe neighboring tokens (に, は, を, か, etc.).
    - Do NOT repeat the meaning or name the word's type.

    Dictionary hints are optional — prioritize the sentence context.

    Return a JSON object with "meaning" and "grammarNote" string fields.
    """

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
        !GeminiAppKey.resolved.isEmpty
    }

    static func cachedResult(for request: Request, model: Model = .flashLite) async -> Result? {
        await Cache.shared.result(for: cacheKey(for: request, model: model))
    }

    static func explain(_ request: Request, model: Model = .flashLite) async throws -> Result {
        let sentence = request.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let surface = request.surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty, !surface.isEmpty else {
            throw GlossError.invalidInput
        }

        let cacheKey = Self.cacheKey(for: request, model: model)
        if let cached = await Cache.shared.result(for: cacheKey) {
            return cached
        }

        guard isConfigured else {
            throw GlossError.missingAPIKey
        }

        print("[GeminiContextualGloss] explaining \"\(surface)\" in sentence: \"\(sentence)\"")

        let response = try await fetchGloss(for: request, sentence: sentence, surface: surface, model: model)
        let result = sanitizedResult(meaning: response.meaning, grammarNote: response.grammarNote, request: request)
        guard !result.meaning.isEmpty else {
            throw GlossError.emptyResponse
        }
        await Cache.shared.store(result, for: cacheKey)
        return result
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
            let message: String?
            let status: String?
        }

        let candidates: [Candidate]?
        let error: APIError?
        let usageMetadata: GeminiUsageMetadata?
    }

    private struct GlossPayload: Decodable {
        let meaning: String
        let grammarNote: String
    }

    private static func fetchGloss(
        for request: Request,
        sentence: String,
        surface: String,
        model: Model
    ) async throws -> GlossPayload {
        let prompt = prompt(for: request, sentence: sentence, surface: surface)
        print("[GeminiContextualGloss] prompt:\n\(prompt)")

        let requestBody = GenerateContentRequest(
            contents: [
                .init(parts: [.init(text: "\(instructionsText)\n\n\(prompt)")]),
            ],
            generationConfig: .init(
                responseMimeType: "application/json",
                responseSchema: .init(
                    type: "object",
                    properties: [
                        "meaning": .init(type: "string"),
                        "grammarNote": .init(type: "string"),
                    ],
                    required: ["meaning", "grammarNote"]
                ),
                temperature: 0,
                topP: 1,
                topK: 1,
                seed: deterministicSeed,
                candidateCount: 1
            )
        )

        guard let url = URL(string: "\(endpointBase)/\(model.rawValue):generateContent") else {
            throw GlossError.invalidConfiguration
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(GeminiAppKey.resolved, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw GlossError.invalidResponse
        }

        let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8 body, \(data.count) bytes>"
        print("[GeminiContextualGloss] response (status \(http.statusCode)) raw body:\n\(rawBody)")

        let decoded = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        if let usage = decoded.usageMetadata {
            GeminiUsageTracker.shared.record(feature: .contextualGloss, model: model.rawValue, usage: usage)
        }
        if let apiError = decoded.error {
            throw GlossError.api(apiError.message ?? apiError.status ?? "Gemini API error")
        }
        guard (200...299).contains(http.statusCode) else {
            throw GlossError.api(rawBody)
        }

        guard
            let jsonText = decoded.candidates?.first?.content?.parts?.first?.text,
            let jsonData = jsonText.data(using: .utf8)
        else {
            throw GlossError.invalidResponse
        }

        print("[GeminiContextualGloss] response candidate text:\n\(jsonText)")
        return try JSONDecoder().decode(GlossPayload.self, from: jsonData)
    }

    private static func prompt(for request: Request, sentence: String, surface: String) -> String {
        var lines = [
            "Sentence: \(sentence)",
            "Selected token (focus only on this span — not words before or after it): \(surface)",
            "",
            "Return:",
            "• meaning — plain English gloss for this token only (no linguistics labels)",
            "• grammarNote — short grammar note, or empty string if none",
        ]
        if let dictionaryForm = request.dictionaryForm?.trimmingCharacters(in: .whitespacesAndNewlines),
           !dictionaryForm.isEmpty,
           dictionaryForm != surface {
            lines.append("Dictionary form (hint only): \(dictionaryForm)")
        }
        if let gloss = request.dictionaryGloss?.trimmingCharacters(in: .whitespacesAndNewlines),
           !gloss.isEmpty {
            lines.append("Dictionary gloss (hint only): \(gloss)")
        }
        return lines.joined(separator: "\n")
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
        request: Request
    ) -> Result {
        var gloss = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        var grammar = grammarNote.trimmingCharacters(in: .whitespacesAndNewlines)

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

        return Result(meaning: gloss, grammarNote: grammar)
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

    private static func cacheKey(for request: Request, model: Model) -> String {
        [
            "gemini-gloss-v1",
            model.rawValue,
            request.sentence,
            request.surface,
            request.dictionaryForm ?? "",
            request.dictionaryGloss ?? "",
        ].joined(separator: "\u{1F}")
    }

    enum GlossError: LocalizedError {
        case invalidInput
        case missingAPIKey
        case invalidConfiguration
        case invalidResponse
        case api(String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .invalidInput:
                return "Missing sentence or selected word."
            case .missingAPIKey:
                return "Gemini API key is not configured."
            case .invalidConfiguration:
                return "Gemini contextual gloss is misconfigured."
            case .invalidResponse:
                return "Gemini returned an unexpected response."
            case .api(let message):
                return message
            case .emptyResponse:
                return "Gemini returned an empty gloss."
            }
        }
    }
}
