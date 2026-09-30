//
//  VerbComboGenerator.swift
//  shizen
//
//  Asks Gemini for pattern slideshows: hook, rule, and three examples each.
//

import Foundation

enum VerbComboGenerator {

    enum Model: String {
        case flash = "gemini-3.6-flash"
    }

    private static let endpointBase = "https://generativelanguage.googleapis.com/v1beta/models"
    private static let maxAttempts = 2

    static var isConfigured: Bool {
        !GeminiAppKey.resolved.isEmpty
    }

    static func generate(
        theme: String,
        usagePrompt: String,
        model: Model = .flash
    ) async throws -> [VerbComboDeck] {
        guard isConfigured else { throw GeneratorError.missingAPIKey }

        let prompt = VerbComboPromptStore.resolvedPrompt(theme: theme, template: usagePrompt)
        print("[VerbComboGenerator] prompt:\n\(prompt)")

        var lastError: Error = GeneratorError.invalidResponse
        for attempt in 0..<maxAttempts {
            let temperature = attempt == 0 ? 0.7 : 0.4
            do {
                let payload = try await fetchPayload(prompt: prompt, model: model, temperature: temperature)
                return try makeDecks(from: payload)
            } catch {
                lastError = error
                print("[VerbComboGenerator] attempt \(attempt + 1) failed: \(error.localizedDescription)")
            }
        }
        throw lastError
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
            let responseMimeType: String
            let responseSchema: Schema
            let temperature: Double
            let topP: Double
            let candidateCount: Int
        }

        let contents: [Content]
        let generationConfig: GenerationConfig
    }

    /// Class so an array schema can point at an object schema.
    private final class Schema: Encodable {
        var type: String
        var properties: [String: Schema]?
        var required: [String]?
        var items: Schema?

        init(
            type: String,
            properties: [String: Schema]? = nil,
            required: [String]? = nil,
            items: Schema? = nil
        ) {
            self.type = type
            self.properties = properties
            self.required = required
            self.items = items
        }

        static func string() -> Schema { Schema(type: "string") }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            try container.encodeIfPresent(properties, forKey: .properties)
            try container.encodeIfPresent(required, forKey: .required)
            try container.encodeIfPresent(items, forKey: .items)
        }

        private enum CodingKeys: String, CodingKey {
            case type, properties, required, items
        }
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

    private struct Payload: Decodable {
        struct Example: Decodable {
            let compound: String
            let exampleJapanese: String
            let exampleEnglish: String
        }

        struct Deck: Decodable {
            let hookVerb: String
            let partner: String
            let rule: String
            let examples: [Example]
        }

        let decks: [Deck]
    }

    private static let exampleSchema = Schema(
        type: "object",
        properties: [
            "compound": .string(),
            "exampleJapanese": .string(),
            "exampleEnglish": .string(),
        ],
        required: ["compound", "exampleJapanese", "exampleEnglish"]
    )

    private static let deckSchema = Schema(
        type: "object",
        properties: [
            "hookVerb": .string(),
            "partner": .string(),
            "rule": .string(),
            "examples": Schema(type: "array", items: exampleSchema),
        ],
        required: ["hookVerb", "partner", "rule", "examples"]
    )

    private static let responseSchema = Schema(
        type: "object",
        properties: [
            "decks": Schema(type: "array", items: deckSchema),
        ],
        required: ["decks"]
    )

    private static func fetchPayload(
        prompt: String,
        model: Model,
        temperature: Double
    ) async throws -> Payload {
        let requestBody = GenerateContentRequest(
            contents: [.init(parts: [.init(text: prompt)])],
            generationConfig: .init(
                responseMimeType: "application/json",
                responseSchema: responseSchema,
                temperature: temperature,
                topP: 0.95,
                candidateCount: 1
            )
        )

        guard let url = URL(string: "\(endpointBase)/\(model.rawValue):generateContent") else {
            throw GeneratorError.invalidConfiguration
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(GeminiAppKey.resolved, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw GeneratorError.invalidResponse
        }

        let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8 body, \(data.count) bytes>"
        print("[VerbComboGenerator] response (status \(http.statusCode)) raw body:\n\(rawBody)")

        let decoded = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        if let usage = decoded.usageMetadata {
            GeminiUsageTracker.shared.record(feature: .verbCombo, model: model.rawValue, usage: usage)
        }
        if let apiError = decoded.error {
            throw GeneratorError.api(apiError.message ?? apiError.status ?? "Gemini API error")
        }
        guard (200...299).contains(http.statusCode) else {
            throw GeneratorError.api(rawBody)
        }

        guard
            let jsonText = decoded.candidates?.first?.content?.parts?.first?.text,
            let jsonData = jsonText.data(using: .utf8)
        else {
            throw GeneratorError.invalidResponse
        }

        print("[VerbComboGenerator] response candidate text:\n\(jsonText)")
        return try JSONDecoder().decode(Payload.self, from: jsonData)
    }

    private static func makeDecks(from payload: Payload) throws -> [VerbComboDeck] {
        let decks = try payload.decks.map(makeDeck)
        guard (3...4).contains(decks.count) else {
            throw GeneratorError.wrongCount(decks.count)
        }
        return decks
    }

    private static func makeDeck(_ payload: Payload.Deck) throws -> VerbComboDeck {
        func require(_ value: String, field: String) throws -> String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw GeneratorError.emptyField(field) }
            return trimmed
        }

        let partner = try require(payload.partner, field: "partner")
        let hookVerb = try require(payload.hookVerb, field: "hookVerb")
        let rule = try require(payload.rule, field: "rule")
        guard payload.examples.count == 3 else {
            throw GeneratorError.wrongExampleCount(payload.examples.count)
        }
        guard rule.contains(partner) else {
            throw GeneratorError.ruleMissesPartner(partner)
        }
        guard hookVerb.contains(partner) else {
            throw GeneratorError.hookMissesPartner(partner)
        }
        guard !containsLatin(partner), !containsLatin(hookVerb) else {
            throw GeneratorError.romaji
        }

        let examples = try payload.examples.map { example -> VerbComboExample in
            let compound = try require(example.compound, field: "compound")
            let japanese = try require(example.exampleJapanese, field: "exampleJapanese")
            let english = try require(example.exampleEnglish, field: "exampleEnglish")
            guard compound.contains(partner) else {
                throw GeneratorError.sentenceMissesCompound(partner)
            }
            guard sentenceIncludes(compound, in: japanese) else {
                throw GeneratorError.sentenceMissesCompound(compound)
            }
            guard !containsLatin(compound), !containsLatin(japanese) else {
                throw GeneratorError.romaji
            }
            return VerbComboExample(
                compound: compound,
                exampleJapanese: japanese,
                exampleEnglish: english
            )
        }

        return VerbComboDeck(
            hookVerb: hookVerb,
            partner: partner,
            rule: rule,
            examples: examples
        )
    }

    /// The sentence may conjugate the ending (食べてみる → 食べてみた).
    private static func sentenceIncludes(_ compound: String, in sentence: String) -> Bool {
        if sentence.contains(compound) { return true }
        let prefix = String(compound.dropLast())
        return prefix.count >= 2 && sentence.contains(prefix)
    }

    private static func containsLatin(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
        }
    }

    enum GeneratorError: LocalizedError {
        case missingAPIKey
        case invalidConfiguration
        case invalidResponse
        case api(String)
        case emptyField(String)
        case wrongCount(Int)
        case wrongExampleCount(Int)
        case ruleMissesPartner(String)
        case hookMissesPartner(String)
        case sentenceMissesCompound(String)
        case romaji

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Gemini API key is not configured."
            case .invalidConfiguration:
                return "Verb combination generator is misconfigured."
            case .invalidResponse:
                return "Gemini returned an unexpected response."
            case .api(let message):
                return message
            case .emptyField(let field):
                return "Gemini left \(field) empty."
            case .wrongCount(let count):
                return "Gemini returned \(count) slideshows. Ask for 3 or 4."
            case .wrongExampleCount(let count):
                return "Gemini returned \(count) examples. Each slideshow needs 3."
            case .ruleMissesPartner(let partner):
                return "The rule does not mention \(partner)."
            case .hookMissesPartner(let partner):
                return "The hook verb does not use \(partner)."
            case .sentenceMissesCompound(let compound):
                return "An example does not use \(compound)."
            case .romaji:
                return "Gemini put romaji in a Japanese field."
            }
        }
    }
}
