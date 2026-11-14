//
//  FoundationModelContextualGloss.swift
//  shizen
//
//  On-device contextual English gloss for a word selected in a sentence.
//

import Foundation
import FoundationModels

@Generable
struct FoundationModelRelatedWord {
    @Guide(description: "Japanese dictionary headword the learner can look up, in Japanese script only. For a transparent compound, a real component word (人口減少 → 人口, then 減少). Otherwise a shared-root or other-form word (引っ越し → 引っ越す). Never the selected word itself, a single kanji, or a conjugation's dictionary form when that form is already given as a hint.")
    var word: String

    @Guide(description: "Short gloss, 1-4 words. Gloss a verb as \"to X\" (to move). Never \"the verb\" or \"the verb to X\".")
    var note: String
}

@Generable
struct FoundationModelContextualWordGloss {
    @Guide(description: "Plain English meaning. 2-10 words. In a sentence, the meaning here (何時 → what time; 行きましょう → let's go). A fused ending is the whole chunk, with no dangling connector (なのかなって → wondering whether it's really OK). On its own, the word's natural meaning, with no \"in this sentence\" framing. For a katakana borrowing, add the source in plain English (デジタル → digital, from English). Never use a linguistics label as the whole meaning.")
    var meaning: String

    @Guide(description: "Optional note on non-obvious grammar of the token itself (inflection, fused particle, politeness). For a verb plus auxiliary chain, one short parts breakdown (作ってあげよう → 作る \"make\" + てあげる \"do for someone\" + よう \"I'll\"). For a fused particle chain, plain glosses: なのかなって → な \"is\" + の \"it's that\" + かな \"I wonder\" + って \"quoting that thought\". な before の is the attributive form of だ. の in のだ/んだ/のか is explanatory (\"it's that…\"), not a nominalizer. Empty string when meaning alone is enough. Never name word types, describe neighboring words, or mention related words — those belong in relatedWords.")
    var grammarNote: String

    @Guide(description: "Up to 2 related Japanese words, in display order. For a transparent compound, the real component words first (人口減少 → 人口, then 減少; a looser word such as 減る only if a slot remains). Do not split words that do not come apart (今日, スマホ, 働く) and do not repeat a single kanji. Empty when nothing useful is related.", .maximumCount(2))
    var relatedWords: [FoundationModelRelatedWord]

    @Guide(description: "Empty string unless the user message asks for a dictionary headword. When asked, the usual dictionary form for this use, in Japanese script (みたい, 見る, わ). Empty when slang or dialect has no standard dictionary form.")
    var headword: String
}

enum FoundationModelContextualGloss {

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

    private static let instructionsText = """
    You help Japanese language learners understand one selected Japanese word.

    The user message says whether they are reading that word inside a sentence \
    or looking the word up on its own. Follow that framing.

    Write for a beginner. Use only plain, useful English — never linguistics or morphology labels. \
    Gloss a verb as "to X" (働く → to work). Never write "the verb", "the verb to X", or "the verb, to X".

    meaning (2-10 words):
    - In a sentence: what the token means here. Do not translate the whole sentence.
    - On its own: the word's natural meaning. If a usage example is included, use it only \
    as a hint. Do not say "in this sentence" or describe the word's role in that line.
    - When the word is built from familiar parts, give the natural composed meaning \
    (何時 → what time; 大学生 → university student; スマホ → smartphone).
    - For conjugated forms, reflect the inflection when it changes the sense (行きましょう → let's go).
    - For a verb built with auxiliaries, give the natural meaning of the whole token \
    (作ってあげよう → I'll make it for you).
    - For a sentence-ending chain or fused particle/auxiliary token, gloss only that chunk. \
    雨なのかもしれない → it might be, not "it might rain". \
    大変だろうなって思った → probably, I'd guess, not "it's tough and I thought". \
    No dangling "and so", "because", or "and then".
    - When って or と quotes a thought, meaning is that thought \
    (なのかなって → wondering whether it's really OK).
    - For a katakana borrowing, fold the source into this field in plain English \
    (デジタル → digital, from English; ナイター → night game, from English). \
    If the Japanese sense is not the English word's sense, give the Japanese meaning \
    and name the English source (テンション → excitement, from English "tension"). \
    Write "from English", not "loanword".
    - For katakana that is not a borrowing (onomatopoeia, a name, native slang), \
    give the meaning only. If you are not sure it is borrowed, omit the source. \
    Do not invent an etymology.
    - Hiragana and kanji words are unchanged — do not add a source language.
    - NEVER use a linguistics label as the whole meaning, and do not start meaning \
    with one: transparent compound, opaque compound, loanword, abbreviation, clipping, \
    portmanteau, compound word, katakana word. A real gloss that also names a source \
    language is fine.

    grammarNote:
    - Only when the token itself has non-obvious grammar worth a short learner note.
    - OK: inflection, a particle fused to the token, politeness encoded in the form.
    - For a verb plus auxiliary chain, add one short note on how the parts add up \
    (作ってあげよう → 作る "make" + てあげる "do for someone" + よう "I'll").
    - For a fused particle/auxiliary chain, one short parts line. Every piece gets a short English gloss. \
    Never part-of-speech names (not copula, nominalizer, question particle, quotation particle).
    - な right before の is the attributive form of だ ("is"). \
    A な that is not before の is the soft sentence-ending particle \
    (だろうなって → だろう "probably" + な "you know" + って "quoting that thought").
    - の in のだ, んだ, or のか is explanatory ("it's that…"), not a nominalizer. \
    かな is "I wonder". って or と quotes a thought.
    - なのかなって → な "is" + の "it's that" + かな "I wonder" + って "quoting that thought"
    - んじゃないかな → ん "it's that" + じゃない "isn't" + かな "I wonder"
    - ないかなと → ない "not" + かな "I wonder" + と "quoting that thought"
    - Use an empty string when the meaning alone is enough (most nouns, abbreviations, and ordinary \
    compounds such as 大学生, 何時, スマホ).
    - Do NOT describe neighboring tokens (に, は, を, か, etc.).
    - Do NOT restate the meaning in different words, and do not name the word's type. \
    A parts breakdown is the note, not a second copy of meaning.
    - Do NOT mention related words here.
    - Do NOT put a source language here. That belongs in meaning.

    relatedWords:
    - Up to 2 other Japanese words a learner would look up. Order is the display order.
    - When the selected word is a transparent compound of real words, those component words \
    come first, in the order they are written. A component has to be a word or an established \
    meaningful unit in this context. 人口減少 → 人口 "population", then 減少 "decrease". \
    高速道路 → 高速 "high speed", then 道路 "road".
    - A looser relative may use a slot only after those components. \
    減る "to decrease" must not take the place of 減少.
    - Do not split a word that does not come apart. 今日, スマホ, and 働く have no component words. \
    Do not invent pieces or arbitrary character chunks (not 口減 from 人口減少, not 今 and 日 from 今日).
    - Do not suggest a single kanji. Each character is already shown on its own. \
    大学生 → 大学 "university", not 大, 学, or 生.
    - When there is no such compound, suggest a word that shares a root or is the other form \
    of this word. 引っ越し → 引っ越す "to move".
    - Each word is a dictionary headword in Japanese script only.
    - note is a short gloss, 1-4 words (population, to move). Never a part-of-speech label.
    - Leave the list empty for particles, names, and words with no useful relative.
    - Do not include the selected token. Do not repeat a word.
    - Do not include a conjugation's dictionary form when that form is already given as a hint. \
    A noun and its verb are different words; include that verb only when a slot remains after \
    the real components.

    headword:
    - Empty string unless the user message asks for a dictionary headword.
    - When asked: the usual dictionary form for this use of the token, in Japanese script \
    (みたい, 見る, わ). Empty when slang or dialect has no standard dictionary form.

    Dictionary hints are optional. In a sentence, prioritize that sentence. \
    On its own, prioritize the word.
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
            relatedWords: response.content.relatedWords.map { ($0.word, $0.note) },
            headword: response.content.headword,
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
            request.requestsHeadword ? "gloss-v9" : "gloss-v8",
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

    private static func framingLines(for request: Request) -> [String] {
        let surface = request.surface.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentence = request.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        switch request.framing {
        case .inSentence:
            return [
                "Framing: the learner is reading this token inside the sentence.",
                "Sentence: \(sentence)",
                "Selected token (focus only on this span — not words before or after it): \(surface)",
            ]
        case .word:
            var lines = [
                "Framing: the learner opened this word on its own, not as part of a sentence they are reading.",
                "Selected word: \(surface)",
            ]
            if !sentence.isEmpty, sentence != surface {
                lines.append("Usage example (hint only — do not describe its role in this line): \(sentence)")
            }
            return lines
        }
    }

    private static func prompt(for request: Request) -> String {
        var lines = framingLines(for: request)
        lines.append(contentsOf: [
            "",
            "Return:",
            "• meaning — plain English gloss for this token only (no linguistics labels as the whole answer)",
            "• grammarNote — short grammar note, or empty string if none",
            "• relatedWords — up to 2 Japanese words. Transparent compounds: real component words first, in written order. Otherwise one close relative. Empty list if none",
        ])
        if request.requestsHeadword {
            lines.append("• headword — the usual dictionary headword for this use, in Japanese script (みたい, 見る, わ), or an empty string when slang or dialect has no standard dictionary form")
        }
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
