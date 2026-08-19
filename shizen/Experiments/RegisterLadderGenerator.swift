//
//  RegisterLadderGenerator.swift
//  shizen
//
//  On-device Gemini generation for register-ladder slideshow decks.
//

import Foundation

enum RegisterLadderGenerator {

    enum Model: String {
        case flash = "gemini-3.6-flash"
    }

    private static let endpointBase = "https://generativelanguage.googleapis.com/v1beta/models"
    private static let maxAttempts = 2

    static var isConfigured: Bool {
        !GeminiAppKey.resolved.isEmpty
    }

    static func generate(
        targetSentence: String,
        usagePrompt: String,
        model: Model = .flash
    ) async throws -> RegisterLadderDeck {
        let sentence = targetSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { throw GeneratorError.invalidInput }
        guard isConfigured else { throw GeneratorError.missingAPIKey }

        let prompt = RegisterLadderPromptStore.resolvedPrompt(
            targetSentence: sentence,
            template: usagePrompt
        )
        print("[RegisterLadderGenerator] prompt:\n\(prompt)")

        var lastError: Error = GeneratorError.invalidResponse
        for attempt in 0..<maxAttempts {
            let temperature = attempt == 0 ? 0.4 : 0.2
            do {
                let payload = try await fetchPayload(prompt: prompt, model: model, temperature: temperature)
                return try makeDeck(from: payload, fallbackEnglish: sentence)
            } catch {
                lastError = error
                print("[RegisterLadderGenerator] attempt \(attempt + 1) failed: \(error.localizedDescription)")
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

    private struct Payload: Decodable {
        let english: String
        let casualJapanese: String
        let casualGloss: String
        let casualAudience: String
        let politeJapanese: String
        let politeAudience: String
        let formalJapanese: String
        let formalAudience: String
        let why: String
    }

    private static let responseSchema = GenerateContentRequest.GenerationConfig.Schema(
        type: "object",
        properties: [
            "english": .init(type: "string"),
            "casualJapanese": .init(type: "string"),
            "casualGloss": .init(type: "string"),
            "casualAudience": .init(type: "string"),
            "politeJapanese": .init(type: "string"),
            "politeAudience": .init(type: "string"),
            "formalJapanese": .init(type: "string"),
            "formalAudience": .init(type: "string"),
            "why": .init(type: "string"),
        ],
        required: [
            "english",
            "casualJapanese",
            "casualGloss",
            "casualAudience",
            "politeJapanese",
            "politeAudience",
            "formalJapanese",
            "formalAudience",
            "why",
        ]
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
        print("[RegisterLadderGenerator] response (status \(http.statusCode)) raw body:\n\(rawBody)")

        let decoded = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        if let usage = decoded.usageMetadata {
            GeminiUsageTracker.shared.record(feature: .registerLadder, model: model.rawValue, usage: usage)
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

        print("[RegisterLadderGenerator] response candidate text:\n\(jsonText)")
        return try JSONDecoder().decode(Payload.self, from: jsonData)
    }

    private static func makeDeck(from payload: Payload, fallbackEnglish: String) throws -> RegisterLadderDeck {
        func require(_ value: String, field: String) throws -> String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw GeneratorError.emptyField(field) }
            return trimmed
        }

        let english = (try? require(payload.english, field: "english")) ?? fallbackEnglish
        let casualJapanese = try require(payload.casualJapanese, field: "casualJapanese")
        let politeJapanese = try require(payload.politeJapanese, field: "politeJapanese")
        let formalJapanese = try require(payload.formalJapanese, field: "formalJapanese")
        let why = try require(payload.why, field: "why")

        let casualGloss = payload.casualGloss.trimmingCharacters(in: .whitespacesAndNewlines)
        let casualAudience = nonEmpty(
            payload.casualAudience,
            fallback: RegisterLadderDeck.Register.casual.defaultAudience
        )
        let politeAudience = nonEmpty(
            payload.politeAudience,
            fallback: RegisterLadderDeck.Register.polite.defaultAudience
        )
        let formalAudience = nonEmpty(
            payload.formalAudience,
            fallback: RegisterLadderDeck.Register.formal.defaultAudience
        )

        return RegisterLadderDeck(
            english: english,
            casual: RegisterLadderLevel(
                japanese: casualJapanese,
                gloss: casualGloss.isEmpty ? "everyday wording" : casualGloss,
                audience: casualAudience
            ),
            polite: RegisterLadderLevel(
                japanese: politeJapanese,
                gloss: "",
                audience: politeAudience
            ),
            formal: RegisterLadderLevel(
                japanese: formalJapanese,
                gloss: "",
                audience: formalAudience
            ),
            why: why
        )
    }

    private static func nonEmpty(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    enum GeneratorError: LocalizedError {
        case invalidInput
        case missingAPIKey
        case invalidConfiguration
        case invalidResponse
        case api(String)
        case emptyField(String)

        var errorDescription: String? {
            switch self {
            case .invalidInput:
                return "Enter a target sentence first."
            case .missingAPIKey:
                return "Gemini API key is not configured."
            case .invalidConfiguration:
                return "Register ladder generator is misconfigured."
            case .invalidResponse:
                return "Gemini returned an unexpected response."
            case .api(let message):
                return message
            case .emptyField(let field):
                return "Gemini left \(field) empty."
            }
        }
    }
}
