//
//  VocabSense.swift
//  shizen
//
//  A few English senses stored with a saved word, plus the join key a later
//  ranker (JEV or otherwise) can use without parsing the gloss text.
//

import Foundation

struct VocabSense: Codable, Equatable, Hashable {
    var text: String
    /// Stable source id, e.g. `jmdict:42`. Nil for a migrated gloss or a model fallback.
    /// An external ranker matches this instead of the English string.
    var sourceKey: String?

    init(text: String, sourceKey: String? = nil) {
        self.text = text
        self.sourceKey = sourceKey
    }

    static func jmdict(text: String, entryID: Int64) -> VocabSense {
        VocabSense(text: text, sourceKey: "jmdict:\(entryID)")
    }
}

enum VocabSenseList {
    static let maximumCount = 4

    /// One flashcard line from a single sense. Synonyms stay comma-separated;
    /// later, unrelated senses are left for the dictionary.
    static func flashcardLine(fromGlossary glossary: String, limit: Int = 3) -> String? {
        let parts = glossary
            .split(separator: ";", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.prefix(max(1, limit)).joined(separator: ", ")
    }

    /// Comma-separated glosses from the strongest dictionary row.
    static func flashcardLine(from entries: [JMDictEntry], limit: Int = 3) -> String? {
        guard let primary = entries.max(by: { ($0.score ?? 0) < ($1.score ?? 0) }) ?? entries.first else {
            return nil
        }
        return flashcardLine(fromGlossary: primary.glossary, limit: limit)
    }

    /// Up to `maximumCount` glosses from JMdict.
    ///
    /// Same split as `JMDictEntry.glossaryParts` / kanji `allDefinitionOptions`:
    /// higher-score rows first, `;`-separated glosses, duplicates dropped.
    /// The head gloss of each sense is taken before extra synonyms, so a long
    /// first sense does not crowd out later meanings.
    static func collect(from entries: [JMDictEntry], limit: Int = maximumCount) -> [VocabSense] {
        let cap = max(0, limit)
        guard cap > 0 else { return [] }
        let sorted = entries.sorted { ($0.score ?? 0) > ($1.score ?? 0) }
        var seen = Set<String>()
        var senses: [VocabSense] = []

        func append(_ text: String, from entry: JMDictEntry) {
            guard senses.count < cap else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { return }
            senses.append(.jmdict(text: trimmed, entryID: entry.id))
        }

        for entry in sorted {
            guard senses.count < cap else { break }
            if let head = entry.glossaryParts.first {
                append(head, from: entry)
            }
        }
        guard senses.count < cap else { return senses }
        for entry in sorted {
            guard senses.count < cap else { break }
            for gloss in entry.glossaryParts.dropFirst() {
                append(gloss, from: entry)
                if senses.count == cap { break }
            }
        }
        return senses
    }
}
