//
//  KanjiSpotlightModels.swift
//  shizen
//
//  Deck model for the Kanji Spotlight slideshow: one subject kanji plus
//  curator-selected compounds (and optional verbs) that showcase readings.
//

import Foundation

struct KanjiSpotlightSubject: Hashable, @unchecked Sendable {
    let character: String
    let detail: KanjidicDetail

    var meaningSummary: String {
        detail.meaningList.prefix(3).joined(separator: ", ")
    }

    var badgeMeaning: String {
        detail.badgeMeaning
    }

    static func make(character: String) -> KanjiSpotlightSubject? {
        let trimmed = character.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1,
              let detail = KanjidicStore.shared.detail(forKanji: trimmed)
        else { return nil }
        return KanjiSpotlightSubject(character: trimmed, detail: detail)
    }

    static func make(from detail: KanjidicDetail) -> KanjiSpotlightSubject {
        KanjiSpotlightSubject(character: detail.character, detail: detail)
    }

    static func == (lhs: KanjiSpotlightSubject, rhs: KanjiSpotlightSubject) -> Bool {
        lhs.character == rhs.character
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(character)
    }
}

/// One hand-picked showcase entry for a spotlight deck.
struct KanjiSpotlightShowcaseItem: Hashable, @unchecked Sendable {
    enum Kind: Hashable, Sendable {
        case compound
        case verb
    }

    let entry: JMDictEntry
    let kind: Kind

    /// Stable diffable-data-source identity (avoids MainActor-isolated Hashable issues).
    var itemID: String { "\(kind)-\(entry.sequence)-\(entry.expression)" }

    var expression: String { entry.expression }
    var reading: String { entry.displayReading }
    var romaji: String {
        let romanized = HiraganaRomaji.romanize(reading)
        return romanized.isEmpty ? reading : romanized
    }
    var gloss: String { entry.firstGloss }

    var readingLine: String {
        let kana = reading.trimmingCharacters(in: .whitespacesAndNewlines)
        let romanized = romaji.trimmingCharacters(in: .whitespacesAndNewlines)
        if kana.isEmpty { return romanized }
        if romanized.isEmpty || romanized == kana { return kana }
        return "\(kana) · \(romanized)"
    }

    /// Freeform compound/verb for place names and other gaps in JMdict.
    static func writeIn(
        expression: String,
        gloss: String,
        reading: String = "",
        kind: Kind = .compound
    ) -> KanjiSpotlightShowcaseItem {
        writeInSequenceLock.lock()
        defer { writeInSequenceLock.unlock() }
        writeInSequence -= 1
        let sequence = writeInSequence
        let entry = JMDictEntry(
            id: Int64(sequence),
            sequence: sequence,
            expression: expression,
            reading: reading,
            primaryReading: nil,
            glossary: gloss,
            info: "write-in",
            tags: nil,
            score: nil
        )
        return KanjiSpotlightShowcaseItem(entry: entry, kind: kind)
    }

    private static let writeInSequenceLock = NSLock()
    private static var writeInSequence = -1

    nonisolated static func == (lhs: KanjiSpotlightShowcaseItem, rhs: KanjiSpotlightShowcaseItem) -> Bool {

        lhs.entry.sequence == rhs.entry.sequence
            && lhs.entry.expression == rhs.entry.expression
            && lhs.kind == rhs.kind
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(entry.sequence)
        hasher.combine(entry.expression)
        hasher.combine(kind)
    }
}

final class KanjiSpotlightDeck {
    let subject: KanjiSpotlightSubject
    /// Curator picks in slide order.
    private(set) var items: [KanjiSpotlightShowcaseItem]

    init(subject: KanjiSpotlightSubject, items: [KanjiSpotlightShowcaseItem]) {
        self.subject = subject
        self.items = items
    }

    var compounds: [KanjiSpotlightShowcaseItem] {
        items.filter { $0.kind == .compound }
    }

    var verbs: [KanjiSpotlightShowcaseItem] {
        items.filter { $0.kind == .verb }
    }
}

enum KanjiSpotlightCatalog {
    /// Max hand-picked compounds on a deck.
    static let maxCompounds = 4
    /// Max optional verb / non-compound slides.
    static let maxVerbs = 2

    /// Candidate compounds and verbs for a subject kanji, scored and tagged.
    static func candidates(for character: String, limit: Int = 60) -> (
        compounds: [KanjiSpotlightShowcaseItem],
        verbs: [KanjiSpotlightShowcaseItem]
    ) {
        let entries = JMDictStore.shared.compounds(forSurface: character, limit: limit)
        var compounds: [KanjiSpotlightShowcaseItem] = []
        var verbs: [KanjiSpotlightShowcaseItem] = []
        var seen = Set<String>()

        for entry in entries {
            let key = "\(entry.sequence)|\(entry.expression)"
            guard seen.insert(key).inserted else { continue }
            guard entry.expression.contains(character) else { continue }

            if entry.isSpotlightVerb {
                verbs.append(KanjiSpotlightShowcaseItem(entry: entry, kind: .verb))
            } else if entry.expression.count >= 2 {
                compounds.append(KanjiSpotlightShowcaseItem(entry: entry, kind: .compound))
            }
        }

        return (compounds, verbs)
    }

    /// Prefer a short starter set that already spans distinct readings.
    static func suggestedSelection(
        compounds: [KanjiSpotlightShowcaseItem],
        verbs: [KanjiSpotlightShowcaseItem],
        compoundCount: Int = 3,
        verbCount: Int = 0
    ) -> [KanjiSpotlightShowcaseItem] {
        var selected: [KanjiSpotlightShowcaseItem] = []
        var seenReadings = Set<String>()

        for item in compounds {
            let readingKey = normalizedReadingKey(item.reading)
            guard seenReadings.insert(readingKey).inserted || selected.isEmpty else { continue }
            selected.append(item)
            if selected.count >= compoundCount { break }
        }

        // Fill remaining compound slots even if readings repeat.
        if selected.count < compoundCount {
            for item in compounds where !selected.contains(item) {
                selected.append(item)
                if selected.count >= compoundCount { break }
            }
        }

        var verbPicks: [KanjiSpotlightShowcaseItem] = []
        for item in verbs {
            let readingKey = normalizedReadingKey(item.reading)
            guard seenReadings.insert(readingKey).inserted || verbPicks.isEmpty else { continue }
            verbPicks.append(item)
            if verbPicks.count >= verbCount { break }
        }
        selected.append(contentsOf: verbPicks)
        return selected
    }

    private static func normalizedReadingKey(_ reading: String) -> String {
        reading
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

extension JMDictEntry {
    /// Verb POS tags from JMdict (`v1`, `v5u`, …), excluding suru (`vs`).
    var isSpotlightVerb: Bool {
        guard let tags else { return false }
        return tags.split(whereSeparator: { $0 == " " || $0 == "\t" }).contains {
            $0.hasPrefix("v") && $0 != "vs"
        }
    }
}

extension KanjidicDetail {
    /// On/kun lines with kana and romaji for learner-facing copy.
    var spotlightReadingLines: (on: String?, kun: String?) {
        let on = Self.annotatedReadings(onReadingList)
        let kun = Self.annotatedReadings(kunReadingList)
        return (on.isEmpty ? nil : on, kun.isEmpty ? nil : kun)
    }

    private static func annotatedReadings(_ readings: [String]) -> String {
        readings
            .prefix(4)
            .map { reading in
                let romaji = HiraganaRomaji.romanize(reading)
                if romaji.isEmpty || romaji == reading {
                    return reading
                }
                return "\(reading) (\(romaji))"
            }
            .joined(separator: "、")
    }
}


/// Configurable title on the subject (first) slide.
enum KanjiSpotlightIntroTitle {
    static let defaultTitle = "Kanji Spotlight"

    /// Preset options shown in the picker (default first).
    static let presets: [String] = [
        defaultTitle,
        "Today's Kanji",
        "Kanji of the Day",
        "One Kanji",
        "Reading Spotlight",
    ]
}
