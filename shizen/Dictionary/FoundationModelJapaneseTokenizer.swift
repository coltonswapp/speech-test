//
//  FoundationModelJapaneseTokenizer.swift
//  shizen
//
//  On-device Apple Foundation model word segmentation for tokenizer experiments.
//

import Foundation
import FoundationModels

@Generable
struct FoundationModelSegmentation {
    @Guide(description: "Surface forms in left-to-right order.", .maximumCount(80))
    var tokens: [String]
}

enum FoundationModelJapaneseTokenizer {

    struct Result {
        let tokens: [JapaneseToken]
    }

    private static let instructionsText = """
    Segment Japanese text into dictionary lookup units for language learners.
    Return tokens in original left-to-right order.
    Every token MUST be copied verbatim from the input in Japanese script (kanji, hiragana, katakana).
    NEVER output romaji, Latin letters, English, or phonetic transliteration.
    Use sentence context: keep casual verb endings with their verb \
    (e.g. 食べちゃいけない — not 食べ + ちゃ + いけない, where ちゃ could be misread as “tea”).
    Keep punctuation as separate tokens when present.
    Punctuation (、 。 , . ！ ？ ! ? …) is always a hard token boundary — \
    never keep words on both sides of a comma or period in one token \
    (e.g. え、いいん must be え and いいん).
    Tokens must appear in order and together cover the full input.
    """

    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    static var unavailabilityMessage: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return ""
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is not enabled on this device."
        case .unavailable(.deviceNotEligible):
            return "This device cannot run the on-device foundation model."
        case .unavailable(.modelNotReady):
            return "The on-device model is not ready yet."
        case .unavailable:
            return "The on-device foundation model is unavailable."
        }
    }

    static func tokenize(_ text: String) async throws -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Result(tokens: [])
        }

        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            throw TokenizeError.unavailable(unavailabilityMessage)
        }

        let session = LanguageModelSession(model: model, instructions: instructionsText)
        let options = GenerationOptions(sampling: .greedy)
        let response = try await session.respond(
            to: Prompt(trimmed),
            generating: FoundationModelSegmentation.self,
            includeSchemaInPrompt: false,
            options: options
        )
        let surfaces = response.content.tokens
        let tokens = JapaneseSegmentationMapping.validatedTokens(from: surfaces, in: trimmed) ?? []
        return Result(tokens: tokens)
    }

    enum TokenizeError: LocalizedError {
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let message):
                return message
            }
        }
    }
}
