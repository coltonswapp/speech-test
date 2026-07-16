//
//  FoundationModelContextualGloss.swift
//  shizen
//
//  On-device contextual English gloss for a word selected in a sentence.
//

import Foundation
import FoundationModels

@Generable
struct FoundationModelContextualWordGloss {
    @Guide(description: "Plain English meaning of the selected token in this sentence. 2-8 words. Examples: 何時 → what time; スマホ → smartphone; 行きましょう → let's go. Never use linguistics jargon or word-type labels.")
    var meaning: String

    @Guide(description: "Optional note on non-obvious grammar of the token itself (inflection, fused particle, politeness). Plain English for learners. Use an empty string when there is nothing useful to add. Never name word types (compound, loanword, abbreviation, etc.) or describe neighboring words.")
    var grammarNote: String
}

enum FoundationModelContextualGloss {

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

    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
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

        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            throw GlossError.unavailable(FoundationModelJapaneseTokenizer.unavailabilityMessage)
        }

        let session = LanguageModelSession(model: model, instructions: instructionsText)
        let options = GenerationOptions(sampling: .greedy)
        let response = try await session.respond(
            to: Prompt(Self.prompt(for: request)),
            generating: FoundationModelContextualWordGloss.self,
            includeSchemaInPrompt: false,
            options: options
        )

        let result = sanitizedResult(
            meaning: response.content.meaning,
            grammarNote: response.content.grammarNote,
            request: request
        )
        guard !result.meaning.isEmpty else {
            throw GlossError.emptyResponse
        }
        await Cache.shared.store(result, for: cacheKey)
        return result
    }

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

    private static func cacheKey(for request: Request) -> String {
        [
            "gloss-v2",
            request.sentence,
            request.surface,
            request.dictionaryForm ?? "",
            request.dictionaryGloss ?? "",
        ].joined(separator: "\u{1F}")
    }

    private static func prompt(for request: Request) -> String {
        var lines = [
            "Sentence: \(request.sentence)",
            "Selected token (focus only on this span — not words before or after it): \(request.surface)",
            "",
            "Return:",
            "• meaning — plain English gloss for this token only (no linguistics labels)",
            "• grammarNote — short grammar note, or empty string if none",
        ]
        if let dictionaryForm = request.dictionaryForm?.trimmingCharacters(in: .whitespacesAndNewlines),
           !dictionaryForm.isEmpty,
           dictionaryForm != request.surface {
            lines.append("Dictionary form (hint only): \(dictionaryForm)")
        }
        if let gloss = request.dictionaryGloss?.trimmingCharacters(in: .whitespacesAndNewlines),
           !gloss.isEmpty {
            lines.append("Dictionary gloss (hint only): \(gloss)")
        }
        return lines.joined(separator: "\n")
    }

    enum GlossError: LocalizedError {
        case invalidInput
        case unavailable(String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .invalidInput:
                return "Missing sentence or selected word."
            case .unavailable(let message):
                return message
            case .emptyResponse:
                return "The on-device model returned an empty gloss."
            }
        }
    }
}
