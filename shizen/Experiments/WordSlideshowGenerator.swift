//
//  WordSlideshowGenerator.swift
//  shizen
//
//  Asks the on-device Apple Intelligence model for a word slideshow
//  ("the days of the week", "5 opposites") as structured output, then runs
//  it through WordSlideshowValidator. The model only chooses words; readings
//  and meaning checks come from JMdict.
//

import Foundation
import FoundationModels

@Generable
struct GeneratedSlideWord {
    @Guide(description: "Japanese word in dictionary form, written the way Japanese normally writes it (月曜日, 広い, ありがとう). Japanese script only: no reading, no romaji, no English.")
    var word: String

    @Guide(description: "Plain English meaning, 1-3 words. Verbs as \"to X\".")
    var meaning: String
}

@Generable
struct GeneratedSlideWordList {
    @Guide(description: "Slideshow title in English, 2-5 words, e.g. \"Days of the week\".")
    var title: String

    @Guide(description: "2-6 lowercase English words naming the set, e.g. \"these common body parts\". Only those words: no \"Do you know\", no \"in Japanese\", no slashes.")
    var hook: String

    @Guide(description: "The words, in the order they should be taught.", .maximumCount(12))
    var words: [GeneratedSlideWord]
}

@Generable
struct GeneratedSlideExample {
    @Guide(description: "A complete natural Japanese sentence, 8-25 characters, ending in 。. The word in the given sense plus real context (who, what, when or where) that makes its meaning clear. Never the word alone. Japanese script only.")
    var japanese: String

    @Guide(description: "The sentence in plain natural English, one short line.")
    var english: String
}

@Generable
struct GeneratedSlideWordPair {
    var first: GeneratedSlideWord

    @Guide(description: "The true counterpart of first, same word type (広い → 狭い).")
    var second: GeneratedSlideWord
}

@Generable
struct GeneratedSlideWordPairList {
    @Guide(description: "Slideshow title in English, 2-5 words, e.g. \"Japanese opposites\".")
    var title: String

    @Guide(description: "2-6 lowercase English words naming the set, e.g. \"these common body parts\". Only those words: no \"Do you know\", no \"in Japanese\", no slashes.")
    var hook: String

    @Guide(description: "Word pairs, one per slide.", .maximumCount(8))
    var pairs: [GeneratedSlideWordPair]
}

enum WordSlideshowGenerator {
    enum GeneratorError: LocalizedError {
        case unavailable(String)
        case empty

        var errorDescription: String? {
            switch self {
            case .unavailable(let message): return message
            case .empty: return "The model didn't return any words. Try rewording the request."
            }
        }
    }

    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    static var unavailabilityMessage: String {
        FoundationModelJapaneseTokenizer.unavailabilityMessage
    }

    /// - Parameter onExampleProgress: (done, total) while writing example sentences.
    static func generate(
        request: String,
        layout: WordSlideshowLayout,
        includeExamples: Bool = false,
        instructions: String = WordSlideshowPromptStore.instructions,
        onExampleProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> WordSlideshowDeck {
        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            throw GeneratorError.unavailable(unavailabilityMessage)
        }

        let session = LanguageModelSession(model: model, instructions: instructions)
        // Some variety so Regenerate gives a different set.
        let options = GenerationOptions(temperature: 0.6)

        let deck: WordSlideshowDeck
        switch layout {
        case .single, .double:
            let response = try await session.respond(
                to: Prompt("Request: \(request)\nGive an ordered list of words."),
                generating: GeneratedSlideWordList.self,
                options: options
            )
            let words = response.content.words.map(Self.word(from:))
            deck = WordSlideshowDeck(
                title: response.content.title,
                hookPhrase: response.content.hook,
                layout: layout,
                words: words
            )
        case .pairs:
            let response = try await session.respond(
                to: Prompt("Request: \(request)\nGive pairs of related words, one pair per slide."),
                generating: GeneratedSlideWordPairList.self,
                options: options
            )
            let groups = response.content.pairs.map { pair in
                WordSlideshowGroup(words: [Self.word(from: pair.first), Self.word(from: pair.second)])
            }
            deck = WordSlideshowDeck(
                title: response.content.title,
                hookPhrase: response.content.hook,
                layout: layout,
                groups: groups
            )
        }

        guard !deck.allWords.isEmpty else { throw GeneratorError.empty }
        print("[WordSlideshowGenerator] \(deck.title): \(deck.allWords.map(\.expression))")
        let validated = WordSlideshowValidator.validated(deck)
        if includeExamples {
            validated.includesExamples = true
            await fillExamples(in: validated, onProgress: onExampleProgress)
        }
        return validated
    }

    /// Writes examples for every word that lacks one, one model call per word so
    /// the small model only has to think about one word at a time. A word whose
    /// call fails keeps an empty example (flagged in review) rather than failing the deck.
    static func fillExamples(in deck: WordSlideshowDeck, onProgress: ((Int, Int) -> Void)? = nil) async {
        let targets = deck.groups.indices.flatMap { groupIndex in
            deck.groups[groupIndex].words.indices.compactMap { wordIndex in
                deck.groups[groupIndex].words[wordIndex].hasExample ? nil : (groupIndex, wordIndex)
            }
        }
        for (done, (groupIndex, wordIndex)) in targets.enumerated() {
            onProgress?(done, targets.count)
            guard !Task.isCancelled else { return }
            let word = deck.groups[groupIndex].words[wordIndex]
            if let example = try? await example(for: word) {
                deck.groups[groupIndex].words[wordIndex].exampleJapanese = example.japanese
                deck.groups[groupIndex].words[wordIndex].exampleEnglish = example.english
            }
        }
        onProgress?(targets.count, targets.count)
        deck.groups = WordSlideshowValidator.validated(deck).groups
    }

    /// Tries up to three times, retrying when the sentence is missing the word or is
    /// little more than the word (戦う。). Returns the last attempt if none pass, so
    /// review can still flag it.
    static func example(for word: WordSlideshowWord) async throws -> (japanese: String, english: String) {
        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            throw GeneratorError.unavailable(unavailabilityMessage)
        }
        var details = ["Word: \(word.expression)"]
        if !word.reading.isEmpty, word.reading != word.expression { details.append("Reading: \(word.reading)") }
        if !word.meaning.isEmpty { details.append("Meaning: \(word.meaning)") }

        var last: (japanese: String, english: String)?
        for attempt in 0..<3 {
            guard !Task.isCancelled else { break }
            var prompt = details.joined(separator: "\n")
            if let last {
                prompt += "\n\nYour last sentence, \(last.japanese), was too bare or didn't use the word. "
                    + "Write a longer sentence that uses \(word.expression) with a subject and context."
            }
            // Fresh session each try so a bad answer isn't in the transcript twice.
            let session = LanguageModelSession(model: model, instructions: WordSlideshowPromptStore.exampleInstructions)
            let response = try await session.respond(
                to: Prompt(prompt),
                generating: GeneratedSlideExample.self,
                options: GenerationOptions(temperature: attempt == 0 ? 0.5 : 0.8)
            )
            let result = (
                japanese: response.content.japanese.trimmingCharacters(in: .whitespacesAndNewlines),
                english: response.content.english.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            var candidate = word
            candidate.exampleJapanese = result.japanese
            candidate.exampleEnglish = result.english
            if candidate.exampleWordRange != nil, !candidate.exampleIsTooBare { return result }
            print("[WordSlideshowGenerator] retrying example for \(word.expression): \(result.japanese)")
            last = result
        }
        guard let last else { throw CancellationError() }
        return last
    }

    private static func word(from generated: GeneratedSlideWord) -> WordSlideshowWord {
        WordSlideshowWord(
            expression: generated.word.trimmingCharacters(in: .whitespacesAndNewlines),
            meaning: generated.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

// MARK: - Validation

/// Checks generated words against JMdict. Fills in readings and flags words the
/// dictionary doesn't know, meanings it doesn't list, repeats, and pairs of
/// different word types. Nothing is dropped; the review screen decides.
enum WordSlideshowValidator {
    static func validated(_ deck: WordSlideshowDeck) -> WordSlideshowDeck {
        var seen = Set<String>()
        deck.title = deck.title.trimmingCharacters(in: .whitespacesAndNewlines)
        deck.hookPhrase = WordSlideshowDeck.cleanedHookPhrase(deck.hookPhrase)
        deck.groups = deck.groups.map { group in
            var group = group
            group.words = group.words.map { word in
                var checked = validated(word)
                if !seen.insert(checked.expression).inserted {
                    checked.warnings.append("Repeated word")
                }
                if deck.includesExamples, !checked.hasExample {
                    checked.warnings.append("No example")
                }
                return checked
            }
            group.warnings = deck.layout == .pairs ? pairWarnings(for: group.words) : []
            return group
        }
        return deck
    }

    static func validated(_ word: WordSlideshowWord) -> WordSlideshowWord {
        var word = word
        word.warnings = []
        word.dictionaryMeanings = []
        word.meaningMatchesDictionary = true
        word.expression = word.expression.trimmingCharacters(in: .whitespacesAndNewlines)
        word.meaning = word.meaning.trimmingCharacters(in: .whitespacesAndNewlines)

        let entries = dictionaryEntries(for: word.expression)
        guard let best = entries.first else {
            word.reading = ""
            word.warnings.append("Not in the dictionary")
            appendExampleWarning(to: &word)
            return word
        }
        word.reading = best.displayReading
        appendExampleWarning(to: &word)

        var seenGlosses = Set<String>()
        let glosses = entries.flatMap(\.glossaryParts).filter { seenGlosses.insert($0.lowercased()).inserted }
        word.dictionaryMeanings = glosses
        if word.meaning.isEmpty {
            word.meaning = best.firstGloss
        } else if !glosses.contains(where: { meaningMatches(word.meaning, gloss: $0) }) {
            word.meaningMatchesDictionary = false
            word.warnings.append("Dictionary says: \(best.firstGloss)")
        }
        return word
    }

    /// Only checked when there's an example; examples-off decks have none.
    private static func appendExampleWarning(to word: inout WordSlideshowWord) {
        word.exampleJapanese = word.exampleJapanese.trimmingCharacters(in: .whitespacesAndNewlines)
        word.exampleEnglish = word.exampleEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        guard word.hasExample else { return }
        if word.exampleWordRange == nil {
            word.warnings.append("Example doesn't use the word")
        } else if word.exampleIsTooBare {
            word.warnings.append("Example is too short")
        }
    }

    /// Exact headword rows, most common sense first.
    private static func dictionaryEntries(for expression: String) -> [JMDictEntry] {
        JMDictStore.shared.entries(matchingExpression: expression)
            .filter { $0.expression == expression }
            .sorted { ($0.score ?? 0) > ($1.score ?? 0) }
    }

    /// "to eat" matches "to eat"; "wide" matches "wide (area)"; case and articles ignored.
    private static func meaningMatches(_ meaning: String, gloss: String) -> Bool {
        let lhs = normalizedMeaning(meaning)
        let rhs = normalizedMeaning(gloss)
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        return lhs == rhs || rhs.hasPrefix(lhs + " ") || lhs.hasPrefix(rhs + " ")
    }

    private static func normalizedMeaning(_ text: String) -> String {
        var value = text.lowercased()
        if let paren = value.firstIndex(of: "(") {
            value = String(value[..<paren])
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for article in ["a ", "an ", "the "] where value.hasPrefix(article) {
            value.removeFirst(article.count)
        }
        return value
    }

    private static func pairWarnings(for words: [WordSlideshowWord]) -> [String] {
        guard words.count == 2 else { return ["A pair needs two words"] }
        let kinds = words.map { wordKind(for: $0.expression) }
        if let first = kinds[0], let second = kinds[1], first != second {
            return ["Different word types (\(first) / \(second))"]
        }
        return []
    }

    /// Broad JMdict part of speech: adjective, verb, noun, or other.
    private static func wordKind(for expression: String) -> String? {
        guard let tags = dictionaryEntries(for: expression).first?.tags else { return nil }
        let first = tags.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "," }).first.map(String.init) ?? ""
        if first.hasPrefix("adj") { return "adjective" }
        if first.hasPrefix("v") { return "verb" }
        if first.hasPrefix("n") { return "noun" }
        if first.hasPrefix("adv") { return "adverb" }
        return first.isEmpty ? nil : first
    }
}
