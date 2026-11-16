//
//  DefinitionCalloutContent+JMDict.swift
//  shizen
//
//  Builds the rich token callout (InteractionKit `DefinitionCalloutContent`) from JMdict.
//

import Foundation
import InteractionKit

extension DefinitionCalloutContent {

    /// Callout content for a tapped token. A miss shows a short message instead of senses.
    /// A kana-only hit that is only a guess in this sentence (particles, shared readings) lists
    /// the likeliest words for that reading ("此処 — here", "個々 — individual") under a
    /// "depends on context" note; the full sheet resolves those with the contextual gloss.
    static func jmdict(surface: String, sentence: String?) -> DefinitionCalloutContent {
        let store = JMDictStore.shared
        let headword = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        let lookup = store.lookup(forSurface: headword)

        guard let primary = lookup.primaryEntry else {
            return DefinitionCalloutContent(
                headword: headword,
                reading: displayReading(surface: headword, entry: nil),
                emptyMessage: "Not in the dictionary yet. Tap for its meaning here."
            )
        }
        if store.isContextSensitiveKanaLookup(lookup, inSentence: sentence) {
            let candidates = contextCandidates(surface: headword, lookup: lookup)
            return DefinitionCalloutContent(
                headword: headword,
                senses: candidates,
                emptyMessage: "Meaning depends on context. Tap for its meaning here.",
                note: candidates.isEmpty ? nil : "Depends on context · tap for its meaning here"
            )
        }

        // Rows of one JMdict entry are its senses, in dictionary order.
        let senseRows = lookup.entries
            .filter { $0.sequence == primary.sequence }
            .sorted { $0.id < $1.id }
        let usable = senseRows.filter { !isFringeSense($0) }
        let senses = (usable.isEmpty ? senseRows : usable)
            .prefix(RichDefinitionCalloutView.maxSenses)
            .compactMap { shortGloss($0.glossary) }

        return DefinitionCalloutContent(
            headword: headword,
            reading: displayReading(surface: headword, entry: primary),
            dictionaryForm: lookup.dictionaryForm,
            partOfSpeech: partOfSpeechLabel(primary.tags),
            senses: senses,
            note: KanaLookupNote.make(surface: headword, lookup: lookup, contextSensitive: false)?.calloutText
        )
    }

    /// Likeliest words behind an ambiguous kana surface, one line each: "此処 — here; this place".
    /// Order: the store's preferred entry, then words usually written in kana, then score.
    /// Uncommon (score 0) entries drop out when any common one exists.
    static func contextCandidates(
        surface: String,
        lookup: JMDictLookupResult,
        limit: Int = RichDefinitionCalloutView.maxSenses
    ) -> [String] {
        var bySequence: [Int: [JMDictEntry]] = [:]
        var order: [Int] = []
        for entry in lookup.entries {
            if bySequence[entry.sequence] == nil { order.append(entry.sequence) }
            bySequence[entry.sequence, default: []].append(entry)
        }
        struct Group {
            let rows: [JMDictEntry]
            let score: Int
            let usuallyKana: Bool
            let preferred: Bool
        }
        var groups = order.compactMap { sequence -> Group? in
            guard let rows = bySequence[sequence]?.sorted(by: { $0.id < $1.id }) else { return nil }
            return Group(
                rows: rows,
                score: rows.map { $0.score ?? 0 }.max() ?? 0,
                usuallyKana: rows.contains(where: \.isUsuallyKana),
                preferred: sequence == lookup.preferredKanaSequence
            )
        }
        if groups.contains(where: { $0.score > 0 }) {
            groups.removeAll { $0.score == 0 }
        }
        groups.sort {
            if $0.preferred != $1.preferred { return $0.preferred }
            if $0.usuallyKana != $1.usuallyKana { return $0.usuallyKana }
            return $0.score > $1.score
        }

        return groups.prefix(limit).compactMap { group in
            let sense = group.rows.first(where: { !isFringeSense($0) }) ?? group.rows.first
            guard let sense, let gloss = shortGloss(sense.glossary, maxParts: 2) else { return nil }
            let expression = sense.expression.trimmingCharacters(in: .whitespacesAndNewlines)
            return expression.isEmpty || expression == surface ? gloss : "\(expression) — \(gloss)"
        }
    }

    // MARK: - Helpers

    private static func displayReading(surface: String, entry: JMDictEntry?) -> String? {
        let reading = JMDictStore.shared.kanaReadingForDisplay(surface: surface, matching: entry)
        return reading.isEmpty || reading == surface ? nil : reading
    }

    /// First glosses of one sense ("to go; to move (towards); to head (towards)").
    private static func shortGloss(_ glossary: String, maxParts: Int = 3) -> String? {
        let parts = glossary
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.prefix(maxParts).joined(separator: "; ")
    }

    /// Senses a learner shouldn't see first in a quick look.
    private static func isFringeSense(_ entry: JMDictEntry) -> Bool {
        guard let tags = entry.tags?.lowercased() else { return false }
        return ["archaic", "obsolete", "obscure", "rare term", "vulgar", "slang"].contains { tags.contains($0) }
    }

    /// JMdict tags in the bundled DB mix codes ("v5k", "adj-na") with spelled-out labels
    /// ("Godan verb - Iku/Yuk", "intransitive verb"). Maps them to a short learner label.
    static func partOfSpeechLabel(_ tags: String?) -> String? {
        guard let tags, !tags.isEmpty else { return nil }
        let codes = Set(tags.split(separator: " ").map(String.init))
        let lower = tags.lowercased()

        var labels: [String] = []
        func add(_ label: String) {
            if !labels.contains(label) { labels.append(label) }
        }

        if codes.contains(where: { $0.hasPrefix("v5") }) || lower.contains("godan verb") { add("godan verb") }
        if codes.contains(where: { $0.hasPrefix("v1") }) || lower.contains("ichidan verb") { add("ichidan verb") }
        if codes.contains("vk") || lower.contains("kuru verb") { add("irregular verb") }
        if codes.contains("adj-i") || codes.contains("adj-ix") { add("い-adjective") }
        if codes.contains("adj-na") { add("な-adjective") }
        if codes.contains("adj-no") { add("の-adjective") }
        if codes.contains("n") { add("noun") }
        // 勉強 → "noun · する verb"
        if codes.contains(where: { $0.hasPrefix("vs") }) || lower.contains("noun or participle w") || lower.contains("suru verb") {
            add("する verb")
        }
        if codes.contains("pn") { add("pronoun") }
        if codes.contains("adv") || codes.contains("adv-to") { add("adverb") }
        if codes.contains("prt") { add("particle") }
        if codes.contains("conj") { add("conjunction") }
        if codes.contains("int") { add("interjection") }
        if codes.contains("aux-v") || codes.contains("aux") { add("auxiliary") }
        if codes.contains("ctr") { add("counter") }
        if codes.contains("pref") { add("prefix") }
        if codes.contains("suf") { add("suffix") }
        if codes.contains("num") { add("number") }
        if codes.contains("expressions") || codes.contains("exp") { add("expression") }

        var parts = Array(labels.prefix(2))
        if lower.contains("intransitive verb") {
            parts.append("intransitive")
        } else if lower.contains("transitive verb") {
            parts.append("transitive")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Lookup assumptions

/// Why a word got the entry it did, or why it got none: mostly kana-only picks, plus a
/// polite prefix that was set aside. The dictionary sheet shows this under the headword so a
/// learner (and we) can see when the definition is a pick.
enum KanaLookupNote: Equatable {
    /// ご期待 → 期待: the tapped word is a polite お / ご / 御 on a word the dictionary lists bare.
    case honorificPrefix(prefix: String, stem: String)
    /// ここ → 此処: JMdict says this word is usually written in kana.
    case usuallyKana(kanji: String)
    /// いる → 居る: chosen from `JMDictStore.pinnedKanaHeadwords` over a higher-scored entry.
    case pinned(surface: String, headword: String)
    /// Several words share this reading. `candidates` are "此処 — here; this place" lines.
    case dependsOnContext(surface: String, candidates: [String])

    static func make(surface: String, lookup: JMDictLookupResult, contextSensitive: Bool) -> KanaLookupNote? {
        let trimmed = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        if contextSensitive {
            let candidates = DefinitionCalloutContent.contextCandidates(surface: trimmed, lookup: lookup, limit: 4)
            return candidates.isEmpty ? nil : .dependsOnContext(surface: trimmed, candidates: candidates)
        }
        if lookup.matchKind == .honorificStem,
           let split = JMDictStore.honorificPrefixSplit(trimmed) {
            return .honorificPrefix(prefix: split.prefix, stem: split.stem)
        }
        guard let preferred = lookup.preferredKanaSequence,
              let primary = lookup.primaryEntry,
              primary.sequence == preferred else { return nil }
        if JMDictStore.pinnedKanaHeadwords[trimmed] == primary.expression {
            return .pinned(surface: trimmed, headword: primary.expression)
        }
        guard primary.expression != trimmed else { return nil }
        return .usuallyKana(kanji: primary.expression)
    }

    /// Short form for the callout. Nil for `dependsOnContext`, which the callout lists itself.
    var calloutText: String? {
        switch self {
        case .honorificPrefix(let prefix, let stem):
            return "Polite \(prefix) + \(stem)"
        case .usuallyKana(let kanji):
            return "Usually written in kana · \(kanji)"
        case .pinned(_, let headword):
            return "Most common word for this reading · \(headword)"
        case .dependsOnContext:
            return nil
        }
    }

    /// Text for the sheet. `listsCandidates` is false when the definitions below already show them.
    func text(listsCandidates: Bool) -> String {
        switch self {
        case .honorificPrefix(let prefix, let stem):
            return "\(prefix) is a polite prefix on \(stem). It adds respect, not meaning."
        case .usuallyKana(let kanji):
            return "Usually written in kana · kanji \(kanji)"
        case .pinned(let surface, let headword):
            return "Shown as \(headword), the most common word read \(surface). It can mean something else in context."
        case .dependsOnContext(let surface, let candidates):
            guard listsCandidates else {
                return "Depends on context · several words are read \(surface)"
            }
            return (["Depends on context · could be:"] + candidates.map { "• \($0)" }).joined(separator: "\n")
        }
    }
}
