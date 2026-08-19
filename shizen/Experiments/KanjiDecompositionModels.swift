//
//  KanjiDecompositionModels.swift
//  shizen
//
//  A 2- or 3-kanji compound word, split into component characters, for the
//  "character A + … = combined word" decomposition card experiment.
//

import Foundation

struct KanjiDecompositionWord: Hashable {
    let expression: String
    let characters: [Character]
    let entry: JMDictEntry

    var firstCharacter: Character { characters[0] }

    var secondCharacter: Character? {
        guard characters.count > 1 else { return nil }
        return characters[1]
    }

    static func == (lhs: KanjiDecompositionWord, rhs: KanjiDecompositionWord) -> Bool {
        lhs.expression == rhs.expression
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(expression)
    }

    /// Builds a decomposition word from a JMDict entry, requiring two or three kanji
    /// characters that all have a kanjidic entry (so a reading/compound card can be built).
    static func make(from entry: JMDictEntry) -> KanjiDecompositionWord? {
        let characters = Array(entry.expression)
        guard (2...3).contains(characters.count) else { return nil }
        guard characters.allSatisfy({ KanjidicStore.shared.detail(forKanji: String($0)) != nil }) else {
            return nil
        }

        return KanjiDecompositionWord(
            expression: entry.expression,
            characters: characters,
            entry: entry
        )
    }
}

extension JMDictEntry {
    /// First gloss only, e.g. "lightbulb; light bulb" -> "lightbulb".
    var firstGloss: String {
        glossary
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? glossary
    }
}

extension KanjidicDetail {
    /// Compact badge copy: user-selected meanings when set, otherwise up to two defaults.
    var badgeMeaning: String {
        KanjiDecompositionBadgeMeaningStore.shared.displayMeaning(
            for: character,
            from: meaningList
        )
    }
}
