//
//  GeminiDialogueNuance.swift
//  shizen
//
//  Cloud Gemini notes for what a dialogue line really means — implied
//  refusals, unasked offers, cultural quirks — using surrounding lines
//  as context. Defaults to gemini-2.5-flash.
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

    enum Model: String {
        case flash = "gemini-2.5-flash"
        case flashLite = "gemini-2.5-flash-lite"
    }

    struct Result: Equatable {
        let naturalMeaning: String
        let impliedMeaning: String
        let notes: String
    }

    struct Request: Equatable {
        let context: DialogueNuanceContext
    }

    private static let endpointBase = "https://generativelanguage.googleapis.com/v1beta/models"
    private static let deterministicSeed = 42
    private static let defaultModel: Model = .flash

    private static let instructionsText = """
    You help English-speaking Japanese learners notice what one dialogue line \
    really means — especially anything hidden in context.

    Surrounding lines (up to two before and two after) are for context only. \
    Explain the focused line, not the whole conversation.

    Keep it light. One idea per field. Short sentences. No linguistics jargon, \
    no lectures, no stacked interpretations, no cultural essays.

    The learner is looking at this line alone and usually does not know who \
    said what. Write about what the line is doing, not who is doing it. Do not \
    name speakers, roles, or characters, and do not use he/she or other \
    identity details, unless the implication is otherwise unclear.

    Japanese often hides the real move in a light way:
    - Naming something can be an offer (麦茶です。冷たいですよ。).
    - Stating a circumstance and trailing off can be a polite no \
    (今から駅なんですけど → can’t take the tea; heading to the station).

    naturalMeaning: the real move, in natural English. A short phrase. \
    No speaker or character attribution unless necessary.

    impliedMeaning: one short sentence on what was left unsaid. Empty if nothing \
    is hidden. Infer only from the given lines. No speaker or character \
    attribution unless necessary.

    notes: at most one short sentence on a single tell (trailing けど, ですよ). \
    Empty if impliedMeaning already covers it. Do not repeat naturalMeaning.

    Return a JSON object with "naturalMeaning", "impliedMeaning", and "notes" string fields.
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

    static var isAvailable: Bool {
        isConfigured
    }

    static var unavailabilityMessage: String {
        isConfigured ? "" : "Gemini API key is not configured."
    }

    static func cachedResult(for request: Request, model: Model = defaultModel) async -> Result? {
        await Cache.shared.result(for: cacheKey(for: request, model: model))
    }

    static func explain(_ request: Request, model: Model = defaultModel) async throws -> Result {
        let focused = request.context.focused.japanese.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !focused.isEmpty else {
            throw NuanceError.invalidInput
        }

        let cacheKey = Self.cacheKey(for: request, model: model)
        if let cached = await Cache.shared.result(for: cacheKey) {
            return cached
        }

        guard isConfigured else {
            throw NuanceError.missingAPIKey
        }

        print("[GeminiDialogueNuance] explaining focused line: \"\(focused)\"")

        let payload = try await fetchNuance(for: request, model: model)
        let result = sanitizedResult(
            naturalMeaning: payload.naturalMeaning,
            impliedMeaning: payload.impliedMeaning,
            notes: payload.notes
        )
        guard !result.naturalMeaning.isEmpty else {
            throw NuanceError.emptyResponse
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

    private struct NuancePayload: Decodable {
        let naturalMeaning: String
        let impliedMeaning: String
        let notes: String
    }

    private static func fetchNuance(for request: Request, model: Model) async throws -> NuancePayload {
        let prompt = prompt(for: request)
        print("[GeminiDialogueNuance] prompt:\n\(prompt)")

        let requestBody = GenerateContentRequest(
            contents: [
                .init(parts: [.init(text: "\(instructionsText)\n\n\(prompt)")]),
            ],
            generationConfig: .init(
                responseMimeType: "application/json",
                responseSchema: .init(
                    type: "object",
                    properties: [
                        "naturalMeaning": .init(type: "string"),
                        "impliedMeaning": .init(type: "string"),
                        "notes": .init(type: "string"),
                    ],
                    required: ["naturalMeaning", "impliedMeaning", "notes"]
                ),
                temperature: 0,
                topP: 1,
                topK: 1,
                seed: deterministicSeed,
                candidateCount: 1
            )
        )

        guard let url = URL(string: "\(endpointBase)/\(model.rawValue):generateContent") else {
            throw NuanceError.invalidConfiguration
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(GeminiAppKey.resolved, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw NuanceError.invalidResponse
        }

        let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8 body, \(data.count) bytes>"
        print("[GeminiDialogueNuance] response (status \(http.statusCode)) raw body:\n\(rawBody)")

        let decoded = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        if let usage = decoded.usageMetadata {
            GeminiUsageTracker.shared.record(feature: .dialogueNuance, model: model.rawValue, usage: usage)
        }
        if let apiError = decoded.error {
            throw NuanceError.api(apiError.message ?? apiError.status ?? "Gemini API error")
        }
        guard (200...299).contains(http.statusCode) else {
            throw NuanceError.api(rawBody)
        }

        guard
            let jsonText = decoded.candidates?.first?.content?.parts?.first?.text,
            let jsonData = jsonText.data(using: .utf8)
        else {
            throw NuanceError.invalidResponse
        }

        print("[GeminiDialogueNuance] response candidate text:\n\(jsonText)")
        return try JSONDecoder().decode(NuancePayload.self, from: jsonData)
    }

    private static func sanitizedResult(
        naturalMeaning: String,
        impliedMeaning: String,
        notes: String
    ) -> Result {
        Result(
            naturalMeaning: naturalMeaning.trimmingCharacters(in: .whitespacesAndNewlines),
            impliedMeaning: impliedMeaning.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func cacheKey(for request: Request, model: Model) -> String {
        func lineKey(_ line: DialogueNuanceContext.Line) -> String {
            [
                line.speaker,
                line.japanese,
                line.english ?? "",
            ].joined(separator: "\u{1E}")
        }
        return [
            "gemini-nuance-v3",
            model.rawValue,
            request.context.preceding.map(lineKey).joined(separator: "\u{1D}"),
            lineKey(request.context.focused),
            request.context.following.map(lineKey).joined(separator: "\u{1D}"),
        ].joined(separator: "\u{1F}")
    }

    private static func prompt(for request: Request) -> String {
        let context = request.context
        var lines: [String] = []

        let hasNeighbors = !context.preceding.isEmpty || !context.following.isEmpty
        if hasNeighbors {
            lines.append("Dialogue (context; the line marked → is the focus):")
            for line in context.preceding {
                lines.append(formatDialogueLine(line, focused: false))
            }
            lines.append(formatDialogueLine(context.focused, focused: true))
            for line in context.following {
                lines.append(formatDialogueLine(line, focused: false))
            }
            lines.append("")
        }

        lines.append("Focused Japanese: \(context.focused.japanese)")
        if let english = context.focused.english?.trimmingCharacters(in: .whitespacesAndNewlines),
           !english.isEmpty {
            lines.append("English hint (may be approximate): \(english)")
        }
        lines.append("")
        lines.append("Stay brief. One idea per field. Do not over-explain.")
        lines.append("Do not mention who spoke unless that identity is required to understand the line.")
        lines.append("")
        lines.append("Return for the focused line only:")
        lines.append("• naturalMeaning — short natural English of the real move")
        lines.append("• impliedMeaning — one sentence on what is unsaid, or empty")
        lines.append("• notes — one short tell, or empty")
        return lines.joined(separator: "\n")
    }

    private static func formatDialogueLine(_ line: DialogueNuanceContext.Line, focused: Bool) -> String {
        let marker = focused ? "→ " : "  "
        let japanese = line.japanese.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = "\(marker)\(japanese)"
        guard !focused,
              let english = line.english?.trimmingCharacters(in: .whitespacesAndNewlines),
              !english.isEmpty else {
            return head
        }
        return "\(head)\n     (\(english))"
    }

    enum NuanceError: LocalizedError {
        case invalidInput
        case missingAPIKey
        case invalidConfiguration
        case invalidResponse
        case api(String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .invalidInput:
                return "Missing dialogue line."
            case .missingAPIKey:
                return "Gemini API key is not configured."
            case .invalidConfiguration:
                return "Gemini dialogue nuance is misconfigured."
            case .invalidResponse:
                return "Gemini returned an unexpected response."
            case .api(let message):
                return message
            case .emptyResponse:
                return "Gemini returned an empty explanation."
            }
        }
    }
}
