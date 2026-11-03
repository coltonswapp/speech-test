//
//  SentenceScrubScript.swift
//  shizen
//
//  A hand-written breakdown for one sentence: its words, what each means here, and the
//  deeper reading. With a script, sentence scrub never tokenizes remotely or calls the LLM
//  gateway; it fakes the loading beats so it still looks like the live screen. Onboarding
//  uses this to show what a breakdown is like before anyone signs in.
//

import Foundation

struct SentenceScrubScript {

    struct Word {
        let surface: String
        /// What it means in this sentence. Shown as the gloss card's meaning.
        let meaning: String
        /// Grammar or usage note under the meaning; empty for none.
        var note: String = ""

        init(_ surface: String, _ meaning: String, note: String = "") {
            self.surface = surface
            self.meaning = meaning
            self.note = note
        }
    }

    /// In sentence order. Punctuation is left out.
    let words: [Word]
    let nuance: GeminiDialogueNuance.Result

    /// How long the fake loads take, so the cards arrive like they would live.
    static let glossDelay: Duration = .milliseconds(450)
    static let nuanceDelay: Duration = .milliseconds(1100)

    /// Token ranges for `words` in `sentence`, in order. Nil if a word isn't found where expected.
    func tokens(in sentence: String) -> [JapaneseToken]? {
        var searchStart = sentence.startIndex
        var tokens: [JapaneseToken] = []
        for word in words {
            guard let range = sentence.range(of: word.surface, range: searchStart..<sentence.endIndex) else {
                assertionFailure("Scripted word \(word.surface) isn't in \(sentence)")
                return nil
            }
            tokens.append(JapaneseToken(text: word.surface, range: range))
            searchStart = range.upperBound
        }
        return tokens
    }

    /// The scripted gloss for a word, or for a span of neighboring words joined together.
    func gloss(for surface: String) -> ContextualGlossResult? {
        let surface = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        if let word = words.first(where: { $0.surface == surface }) {
            return ContextualGlossResult(meaning: word.meaning, grammarNote: word.note, relatedWords: [])
        }
        for start in words.indices {
            var joined = ""
            for end in start..<words.count {
                joined += words[end].surface
                if joined == surface {
                    let span = words[start...end]
                    return ContextualGlossResult(
                        meaning: span.map(\.meaning).joined(separator: " + "),
                        grammarNote: span.map(\.note).filter { !$0.isEmpty }.joined(separator: " "),
                        relatedWords: []
                    )
                }
                if !surface.hasPrefix(joined) { break }
            }
        }
        return nil
    }
}

/// Serves glosses from a script after a short fake load. Anything unscripted fails, and the
/// detail view falls back to the bundled dictionary.
struct ScriptedContextualGlossProvider: ContextualGlossProviding {

    struct Unscripted: Error {}

    let script: SentenceScrubScript

    var isAvailable: Bool { true }

    func cachedResult(for request: ContextualGlossRequest) async -> ContextualGlossResult? {
        nil
    }

    func explain(_ request: ContextualGlossRequest) async throws -> ContextualGlossResult {
        try await Task.sleep(for: SentenceScrubScript.glossDelay)
        guard let gloss = script.gloss(for: request.surface) else { throw Unscripted() }
        return gloss
    }
}
