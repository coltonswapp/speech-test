//
//  JMDictStore.swift
//  shizen
//
//  Read-only access to bundled jmdict.sqlite (JMdict subset).
//

import Foundation
import GRDB

struct JMDictEntry: Decodable, FetchableRecord, Equatable {
    let id: Int64
    let sequence: Int
    let expression: String
    let reading: String
    /// When set, preferred yomi for this row (e.g. disambiguate 今日+は vs こんにちは).
    let primaryReading: String?
    let glossary: String
    let info: String?
    let tags: String?
    let score: Int?

    enum CodingKeys: String, CodingKey {
        case id, sequence, expression, reading
        case primaryReading = "primary_reading"
        case glossary, info, tags, score
    }

    /// Yomi to show in UI: `primary_reading` when present, else `reading`.
    var displayReading: String {
        if let p = primaryReading?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            return p
        }
        return reading
    }
}

/// Result of resolving a tapped token surface to JMdict entries.
struct JMDictLookupResult {
    let surface: String
    let entries: [JMDictEntry]

    /// Headword expression when lookup resolved to a different form than `surface` (e.g. 歩いて → 歩く).
    var dictionaryForm: String? {
        guard let primary = entries.max(by: { ($0.score ?? 0) < ($1.score ?? 0) }) ?? entries.first else {
            return nil
        }
        let expr = primary.expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expr.isEmpty, expr != surface else { return nil }
        return expr
    }

    /// Preferred yomi for `dictionaryForm`, when present.
    var dictionaryFormReading: String? {
        guard dictionaryForm != nil,
              let primary = entries.max(by: { ($0.score ?? 0) < ($1.score ?? 0) }) ?? entries.first
        else { return nil }
        let reading = primary.displayReading.trimmingCharacters(in: .whitespacesAndNewlines)
        return reading.isEmpty ? nil : reading
    }
}

final class JMDictStore {
    static let shared = JMDictStore()

    private var dbQueue: DatabaseQueue?

    private init() {
        openDatabaseIfNeeded()
    }

    private func openDatabaseIfNeeded() {
        guard dbQueue == nil else { return }
        guard
            let url = Bundle.main.url(forResource: "jmdict", withExtension: "sqlite")
        else {
            print("JMDictStore: jmdict.sqlite not found in bundle")
            return
        }
        var config = Configuration()
        config.readonly = true
        do {
            dbQueue = try DatabaseQueue(path: url.path, configuration: config)
        } catch {
            print("JMDictStore: failed to open DB: \(error)")
        }
    }

    /// Looks up entries for a surface string: inflected-form → lemma (when recognized), exact match, lemma again, tail trim, expression prefix.
    func entries(forSurface surface: String) -> [JMDictEntry] {
        lookup(forSurface: surface).entries
    }

    func lookup(forSurface surface: String) -> JMDictLookupResult {
        let trimmed = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return JMDictLookupResult(surface: trimmed, entries: [])
        }

        openDatabaseIfNeeded()
        guard let dbQueue else {
            return JMDictLookupResult(surface: trimmed, entries: [])
        }

        var result: [JMDictEntry] = []
        do {
            try dbQueue.read { db in
                if Self.looksInflectedForLemmaGuess(trimmed),
                   let rows = try bestLemmaGuessExactMatch(in: db, surface: trimmed), !rows.isEmpty {
                    result = rows
                    return
                }
                if let rows = try exactMatch(in: db, surface: trimmed), !rows.isEmpty {
                    result = rows
                    return
                }
                if let rows = try bestLemmaGuessExactMatch(in: db, surface: trimmed), !rows.isEmpty {
                    result = rows
                    return
                }
                // Tail trim: conjugated forms
                var shortened = trimmed
                while shortened.count > 1 {
                    shortened = String(shortened.dropLast())
                    if let rows = try exactMatch(in: db, surface: shortened), !rows.isEmpty {
                        if Self.shouldRejectSpuriousSingleKanjiTailMatch(trimmed: shortened, original: trimmed) {
                            continue
                        }
                        result = rows
                        return
                    }
                }
                result = try prefixMatchExpression(in: db, surface: trimmed, limit: 20)
            }
        } catch {
            print("JMDictStore: query error: \(error)")
        }
        return JMDictLookupResult(surface: trimmed, entries: result)
    }

    /// True when some row has `expression`, `reading`, or `primary_reading` equal to `surface` (no prefix/tail heuristics).
    func hasExactLexicalMatch(for surface: String) -> Bool {
        openDatabaseIfNeeded()
        guard let dbQueue, !surface.isEmpty else { return false }
        do {
            return try dbQueue.read { db in
                try Self.hasExactLexicalMatch(in: db, surface: surface)
            }
        } catch {
            print("JMDictStore: query error: \(error)")
            return false
        }
    }

    /// Only these `X+は` runs may merge to a single lookup surface. Everything else (e.g. 今日+は as topic) stays split,
    /// so a trailing topic は never joins the previous token unless the whole string is a known compound (not 今日+は).
    private static let mergeCompoundWithTrailingHa: Set<String> = [
        "では", "には", "からは", "とは", "ならは", "までは", "までには", "にしては", "としては",
    ]

    /// Two surface tokens (e.g. いい + 天気) may both be in JMdict as one phrase; we keep them separate for tap/highlight
    /// so each word can be looked up and underlined on its own.
    private static let doNotMergeConsecutiveTokenSurfaces: Set<String> = [
        "いい天気", "良い天気",
    ]

    /// Consecutive tokens that were split for intentional lookup/UI must not be merged back (tokenizer + lookup).
    static func mustKeepSplit(mergedSurface: String) -> Bool {
        doNotMergeConsecutiveTokenSurfaces.contains(mergedSurface)
    }

    /// When MeCab/IPADic picks a low-frequency or non-dictionary reading for an ambiguous kanji
    /// headword, prefer the highest-scored JMdict reading (e.g. 柵 → さく, not しがらみ;
    /// 一人 → ひとり, not いちにん).
    func preferredFuriganaReading(forExpression expression: String, mecabReading: String) -> String {
        preferredKanjiRubyReading(
            wordSurface: expression,
            wordReading: mecabReading,
            rubySurface: expression,
            rubyReading: mecabReading,
            in: expression
        )
    }

    /// Refines kanji-only ruby using the parent MeCab token (e.g. 辛 + つら ← 辛い/つらい → 辛 + から).
    func preferredKanjiRubyReading(
        wordSurface: String,
        wordReading: String,
        rubySurface: String,
        rubyReading: String,
        in sentence: String,
        at range: Range<String.Index>? = nil,
        wordDictionaryForm: String? = nil
    ) -> String {
        let trimmedWord = wordSurface.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRuby = rubySurface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRuby.isEmpty else { return rubyReading }

        if let corrected = Self.correctOclockRubyReading(
            rubySurface: trimmedRuby,
            rubyReading: rubyReading,
            range: range,
            in: sentence
        ) {
            return corrected
        }

        if let corrected = Self.correctKataHouRubyReading(
            rubySurface: trimmedRuby,
            rubyReading: rubyReading,
            range: range,
            in: sentence
        ) {
            return corrected
        }

        // MeCab may emit a lone kanji stem (行こう → 行 + こう); trust its kanji-only ruby for that token.
        if trimmedWord == trimmedRuby,
           Self.isSingleUnifiedKanjiExpression(trimmedRuby) {
            return rubyReading
        }

        openDatabaseIfNeeded()
        guard let dbQueue else { return rubyReading }

        guard let lookupExpression = furiganaLookupExpression(
            wordSurface: trimmedWord,
            wordDictionaryForm: wordDictionaryForm,
            rubySurface: trimmedRuby
        ) else {
            return rubyReading
        }

        do {
            let rows = try dbQueue.read { db in
                try JMDictEntry.fetchAll(
                    db,
                    sql: """
                        SELECT * FROM entries
                        WHERE expression = ?
                        ORDER BY score DESC, id ASC
                        """,
                    arguments: [lookupExpression]
                )
            }
            guard !rows.isEmpty else { return rubyReading }

            let topRow = rows.max(by: { ($0.score ?? 0) < ($1.score ?? 0) }) ?? rows[0]
            let compareReading = lookupExpression == trimmedWord ? wordReading : rubyReading
            let chosenLemmaReading = Self.preferredReadingAmongAlternates(
                forExpression: lookupExpression,
                mecabReading: compareReading,
                rows: rows,
                in: sentence
            )
            let inflectionSurface = trimmedWord.isEmpty ? trimmedRuby : trimmedWord
            // Ruby narrower than the word (食 inside token 食べ): the only reading we may emit is the
            // lemma reading minus the lemma's own okurigana (食べる/たべる − べる → た). If that alignment
            // fails, MeCab's kanji-only ruby is safer than a full dictionary reading whose kana would
            // duplicate the okurigana already visible after the ruby range.
            if trimmedRuby != inflectionSurface {
                if lookupExpression.hasPrefix(trimmedRuby),
                   let lemmaTail = Self.kanaSuffixAfterLastKanji(in: lookupExpression),
                   String(lookupExpression.dropFirst(trimmedRuby.count)) == lemmaTail,
                   chosenLemmaReading.hasSuffix(lemmaTail),
                   chosenLemmaReading.count > lemmaTail.count {
                    return String(chosenLemmaReading.dropLast(lemmaTail.count))
                }
                return rubyReading
            }
            let fullReading: String
            if !trimmedWord.isEmpty, trimmedWord != lookupExpression,
               let contextual = Self.contextualReadingFromLemma(
                   surface: trimmedWord,
                   lemmaExpression: lookupExpression,
                   lemmaReading: chosenLemmaReading,
                   tags: topRow.tags
               ) {
                fullReading = contextual
            } else {
                fullReading = chosenLemmaReading
            }
            return Self.readingForKanjiRubyOnly(
                surface: inflectionSurface,
                fullReading: fullReading,
                entry: topRow
            )
        } catch {
            print("JMDictStore: preferredKanjiRubyReading error: \(error)")
            return rubyReading
        }
    }

    /// Avoid resolving lone kanji ruby against a different headword when the parent token has okurigana
    /// (e.g. 食べましょう → 食 must not map to noun 食/しょく).
    private func furiganaLookupExpression(
        wordSurface: String,
        wordDictionaryForm: String?,
        rubySurface: String
    ) -> String? {
        if !wordSurface.isEmpty, hasExactLexicalMatch(for: wordSurface) {
            if Self.isSingleUnifiedKanjiExpression(wordSurface),
               let form = wordDictionaryForm?.trimmingCharacters(in: .whitespacesAndNewlines),
               !form.isEmpty,
               form != wordSurface,
               hasExactLexicalMatch(for: form) {
                return form
            }
            return wordSurface
        }

        if !wordSurface.isEmpty,
           wordSurface.hasPrefix(rubySurface),
           rubySurface.count < wordSurface.count,
           String(wordSurface.dropFirst(rubySurface.count)).allSatisfy(Self.isExtendedKana),
           let form = wordDictionaryForm?.trimmingCharacters(in: .whitespacesAndNewlines),
           !form.isEmpty,
           hasExactLexicalMatch(for: form) {
            return form
        }

        if Self.shouldRejectSpuriousSingleKanjiTailMatch(trimmed: rubySurface, original: wordSurface) {
            if let form = wordDictionaryForm?.trimmingCharacters(in: .whitespacesAndNewlines),
               !form.isEmpty,
               hasExactLexicalMatch(for: form) {
                return form
            }
            if let lemma = bestLemmaGuessExpression(for: wordSurface) {
                return lemma
            }
            return nil
        }

        if hasExactLexicalMatch(for: rubySurface) {
            return rubySurface
        }

        if !wordSurface.isEmpty, let lemma = bestLemmaGuessExpression(for: wordSurface) {
            return lemma
        }

        return rubySurface
    }

    private func bestLemmaGuessExpression(for surface: String) -> String? {
        openDatabaseIfNeeded()
        guard let dbQueue, !surface.isEmpty else { return nil }
        do {
            return try dbQueue.read { db in
                try bestLemmaGuessExactMatch(in: db, surface: surface)?.first?.expression
            }
        } catch {
            print("JMDictStore: bestLemmaGuessExpression error: \(error)")
            return nil
        }
    }

    /// Reading for a run of adjacent MeCab tokens merged into a single JMdict headword
    /// (一+人 → 一人/ひとり). Returns nil when the merged surface is not a headword; keeps
    /// `mecabReading` when the dictionary agrees with it (same ranking as other refinements).
    func compoundMergedReading(forSurface surface: String, mecabReading: String) -> String? {
        openDatabaseIfNeeded()
        guard let dbQueue, !surface.isEmpty else { return nil }
        do {
            let rows = try dbQueue.read { db in
                try JMDictEntry.fetchAll(
                    db,
                    sql: """
                        SELECT * FROM entries
                        WHERE expression = ?
                        ORDER BY score DESC, id ASC
                        """,
                    arguments: [surface]
                )
            }
            guard !rows.isEmpty else { return nil }
            return Self.preferredReadingAmongAlternates(
                forExpression: surface,
                mecabReading: mecabReading,
                rows: rows,
                in: surface
            )
        } catch {
            print("JMDictStore: compoundMergedReading error: \(error)")
            return nil
        }
    }

    private static func preferredReadingAmongAlternates(
        forExpression expression: String,
        mecabReading: String,
        rows: [JMDictEntry],
        in sentence: String
    ) -> String {
        var bestScoreByReading: [String: Int] = [:]
        for row in rows {
            let reading = row.displayReading.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reading.isEmpty else { continue }
            let score = row.score ?? 0
            bestScoreByReading[reading] = max(bestScoreByReading[reading] ?? Int.min, score)
        }
        guard !bestScoreByReading.isEmpty else { return mecabReading }

        if expression == "辛い" || expression.hasSuffix("辛い") {
            if Self.sentenceHintsTsuraiReading(sentence),
               bestScoreByReading.keys.contains("つらい") {
                return "つらい"
            }
            if bestScoreByReading.keys.contains("からい") {
                return "からい"
            }
        }

        guard let top = bestScoreByReading.max(by: { $0.value < $1.value }) else { return mecabReading }
        // MeCab reading absent from JMdict (e.g. 一人 → いちにん): prefer the top dictionary reading.
        guard let mecabScore = bestScoreByReading[mecabReading] else { return top.key }
        if top.key != mecabReading, top.value >= mecabScore + 1000 {
            return top.key
        }
        return mecabReading
    }

    private static let tsuraiContextSubstrings = [
        "思い出", "世知", "別れ", "運命", "経験", "人生", "状況", "時期", "厳しい", "つらい",
    ]

    private static let oclockNumericScalars: CharacterSet = {
        var set = CharacterSet(charactersIn: "0123456789")
        set.insert(charactersIn: "０１２３４５６７８９")
        set.insert(charactersIn: "〇零一二三四五六七八九十百千万")
        return set
    }()

    private static func sentenceHintsTsuraiReading(_ sentence: String) -> Bool {
        tsuraiContextSubstrings.contains(where: sentence.contains)
    }

    /// MeCab/IPADic often reads clock-hour 時 as とき; after a numeral it should be じ (三時 → さんじ).
    private static func correctOclockRubyReading(
        rubySurface: String,
        rubyReading: String,
        range: Range<String.Index>?,
        in sentence: String
    ) -> String? {
        if rubySurface == "時" {
            guard isOclockJiContext(in: sentence, at: range) else { return nil }
            return "じ"
        }

        guard rubySurface.count > 1, rubySurface.hasSuffix("時") else { return nil }
        let numericPrefix = String(rubySurface.dropLast())
        guard isNumericTimePrefix(numericPrefix), !numericPrefix.hasPrefix("何") else { return nil }
        return oclockJiReading(from: rubyReading)
    }

    /// Prefixes after 方 that favor direction/comparison ほう over person-honorific かた.
    private static let houReadingAfterKataCues = [
        "がいい", "が良い", "がよい", "がよか", "が良かっ", "が良さ",
        "へ", "へと", "向き",
    ]

    /// Prefixes after 〜の方 that confidently mark honorific person かた.
    private static let kataReadingAfterNoCues = [
        "です", "だ", "でござ", "でした", "だった",
        "も", "を", "と", "から", "まで", "ね", "よ", "わ", "さ",
        "、", "。", "！", "？", "!", "?", "\n",
        "が来", "がいら", "がおっしゃ", "が言", "が教え",
    ]

    /// MeCab/IPADic defaults lone 方 to ほう; honorific person 〜の方 should be かた
    /// (転勤の方) unless comparison/direction cues favor ほう (の方がいい, 右の方へ, より〜の方).
    private static func correctKataHouRubyReading(
        rubySurface: String,
        rubyReading: String,
        range: Range<String.Index>?,
        in sentence: String
    ) -> String? {
        guard rubySurface == "方" else { return nil }
        if rubyReading == "かた" || rubyReading == "がた" { return nil }
        guard let range, range.lowerBound > sentence.startIndex else { return nil }
        let before = sentence[sentence.index(before: range.lowerBound)]
        guard before == "の" else { return nil }

        let after = String(sentence[range.upperBound...])
        if houReadingAfterKataCues.contains(where: { after.hasPrefix($0) }) {
            return nil
        }
        if sentence[sentence.startIndex..<range.lowerBound].contains("より") {
            return nil
        }
        if after.isEmpty || kataReadingAfterNoCues.contains(where: { after.hasPrefix($0) }) {
            return "かた"
        }
        return nil
    }

    private static func isOclockJiContext(in sentence: String, at range: Range<String.Index>?) -> Bool {
        guard let range, range.lowerBound > sentence.startIndex else { return false }
        let before = sentence[sentence.index(before: range.lowerBound)]
        if before == "何" { return false }
        return isNumericTimeCharacter(before)
    }

    private static func isNumericTimePrefix(_ prefix: String) -> Bool {
        guard !prefix.isEmpty else { return false }
        return prefix.allSatisfy(isNumericTimeCharacter)
    }

    private static func isNumericTimeCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { oclockNumericScalars.contains($0) }
    }

    private static func oclockJiReading(from reading: String) -> String {
        if reading.hasSuffix("とき") {
            return String(reading.dropLast(2)) + "じ"
        }
        if reading.hasSuffix("どき") {
            return String(reading.dropLast(2)) + "じ"
        }
        return reading
    }

    /// Hiragana aligned with **kanji only** (ruby-style): drops kana already written as okurigana on `surface`
    /// (e.g. 歩いて → **ある**, not あるいて).
    func readingForSurface(_ surface: String, matching entry: JMDictEntry) -> String {
        let expr = entry.expression
        let reading = entry.displayReading.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextual: String
        if surface == expr {
            contextual = reading
        } else if let ctx = Self.contextualReadingFromLemma(
            surface: surface,
            lemmaExpression: expr,
            lemmaReading: reading,
            tags: entry.tags
        ) {
            contextual = ctx
        } else {
            contextual = reading
        }
        return Self.readingForKanjiRubyOnly(surface: surface, fullReading: contextual, entry: entry)
    }

    /// Longest-first endings we can drop from **both** surface and reading together (ます / て) before okurigana trimming.
    private static let rubyParallelInflectionSuffixes: [String] = [
        "ませんでした",
        "ましょう",
        "ました",
        "ません",
        "ます",
        "いで",
        "いて",
        "って",
        "んで",
        "よう",
        "ろう",
        "もう",
        "ぼう",
        "のう",
        "とう",
        "そう",
        "ごう",
        "こう",
        "おう",
        "て",
        "だ",
    ]

    /// Strip a trailing kana suffix shared by `surface` and `fullReading` so the subtitle only covers readings for **kanji**:
    /// removes inflection first; then trims okurigana that is either a strict prefix of the lemma tail (食べ/べる → た)
    /// or the godan **連用形** kana already shown after the kanji (行く → **行**き +… → reading line **い**, not **いき**).
    private static func readingForKanjiRubyOnly(surface: String, fullReading: String, entry: JMDictEntry) -> String {
        let (s, r) = stripSharedInflectionSuffix(surface: surface, reading: fullReading)
        let kanjiCount = s.filter { isKanjiCharacter($0) }.count
        guard kanjiCount == 1,
              let oku = okuriganaAfterOnlyKanjiBlock(surface: s),
              !oku.isEmpty,
              r.hasSuffix(oku),
              let lemmaTail = kanaSuffixAfterLastKanji(in: entry.expression),
              shouldStripSurfaceOkuriganaFromReading(
                  oku: oku,
                  stemReading: r,
                  lemmaExpression: entry.expression,
                  lemmaKanaTail: lemmaTail,
                  tags: entry.tags
              )
        else {
            return r
        }
        return String(r.dropLast(oku.count))
    }

    private static func shouldStripSurfaceOkuriganaFromReading(
        oku: String,
        stemReading: String,
        lemmaExpression: String,
        lemmaKanaTail: String,
        tags: String?
    ) -> Bool {
        guard stemReading.hasSuffix(oku), let lemmaExprLast = lemmaExpression.last else { return false }

        // e.g. 行き (n.): surface tail equals lemma tail — keep full いき.
        if oku == lemmaKanaTail {
            return false
        }

        if lemmaKanaTail.hasPrefix(oku), oku.count < lemmaKanaTail.count {
            return true
        }

        guard oku.count == 1, let o = oku.first else { return false }
        if isIchidanVerbTag(tags), lemmaExprLast == "る" {
            return false
        }
        if let stemK = godanRenyoOkuriganaKana(dictionaryFinalKana: lemmaExprLast), o == stemK {
            return true
        }
        return false
    }

    /// Godan dictionary-final kana → 連用形 kana often spelled immediately after the kanji (行く → 行**き**).
    private static func godanRenyoOkuriganaKana(dictionaryFinalKana: Character) -> Character? {
        let map: [Character: Character] = [
            "く": "き", "ぐ": "ぎ", "す": "し", "つ": "ち", "ぬ": "に", "ぶ": "び", "む": "み", "る": "り", "う": "い",
        ]
        return map[dictionaryFinalKana]
    }

    private static func stripSharedInflectionSuffix(surface: String, reading: String) -> (String, String) {
        guard surface.unicodeScalars.contains(where: isKanjiOrIterationMark) else {
            return (surface, reading)
        }
        for suf in rubyParallelInflectionSuffixes {
            guard suf.count < surface.count,
                  surface.hasSuffix(suf),
                  reading.hasSuffix(suf),
                  String(surface.dropLast(suf.count)).unicodeScalars.contains(where: isKanjiOrIterationMark)
            else { continue }
            return (String(surface.dropLast(suf.count)), String(reading.dropLast(suf.count)))
        }
        return (surface, reading)
    }

    /// Kana in `expression` written after its last kanji (e.g. 食べる → べる, 行く → く).
    private static func kanaSuffixAfterLastKanji(in expression: String) -> String? {
        var j = expression.endIndex
        while j > expression.startIndex {
            let p = expression.index(before: j)
            if isKanjiCharacter(expression[p]) {
                let after = String(expression[expression.index(after: p)..<expression.endIndex])
                guard !after.isEmpty, after.allSatisfy(isExtendedKana) else { return nil }
                return after
            }
            j = p
        }
        return nil
    }

    /// Kana written after the last kanji (e.g. 歩**いて**), only when the surface has no other kanji to the right of the first kanji block.
    private static func okuriganaAfterOnlyKanjiBlock(surface: String) -> String? {
        var j = surface.endIndex
        while j > surface.startIndex {
            let p = surface.index(before: j)
            let ch = surface[p]
            if isKanjiCharacter(ch) {
                let after = String(surface[surface.index(after: p)..<surface.endIndex])
                guard !after.isEmpty, after.allSatisfy(isExtendedKana) else { return nil }
                return after
            }
            j = p
        }
        return nil
    }

    private static func isKanjiCharacter(_ c: Character) -> Bool {
        c.unicodeScalars.contains(where: isKanjiOrIterationMark)
    }

    private static func isExtendedKana(_ c: Character) -> Bool {
        for s in c.unicodeScalars {
            let v = s.value
            if (0x3040...0x309F).contains(v) { return true }
            if (0x30A0...0x30FF).contains(v) { return true }
            if (0xFF66...0xFF9D).contains(v) { return true }
            if v == 0x30FC { return true }
        }
        return false
    }

    private static func isKanjiOrIterationMark(_ scalar: UnicodeScalar) -> Bool {
        let v = scalar.value
        return (0x3400...0x4DBF).contains(v) || (0x4E00...0x9FFF).contains(v) || v == 0x3005
    }

    private static func contextualReadingFromLemma(
        surface: String,
        lemmaExpression: String,
        lemmaReading: String,
        tags: String?
    ) -> String? {
        if surface.hasSuffix("ましょう"), surface.count > 4,
           let stem = stemReadingForMasuForms(lemmaExpression: lemmaExpression, lemmaReading: lemmaReading, tags: tags) {
            return stem + "ましょう"
        }
        if surface.hasSuffix("ました"), surface.count > 3,
           let stem = stemReadingForMasuForms(lemmaExpression: lemmaExpression, lemmaReading: lemmaReading, tags: tags) {
            return stem + "ました"
        }
        if surface.hasSuffix("ません"), !surface.hasSuffix("ませんでした"), surface.count > 3,
           let stem = stemReadingForMasuForms(lemmaExpression: lemmaExpression, lemmaReading: lemmaReading, tags: tags) {
            return stem + "ません"
        }
        if surface.hasSuffix("ます"), !surface.hasSuffix("ました"), surface.count > 2,
           let stem = stemReadingForMasuForms(lemmaExpression: lemmaExpression, lemmaReading: lemmaReading, tags: tags) {
            return stem + "ます"
        }
        if surface.hasSuffix("いて"), lemmaExpression.hasSuffix("く"), lemmaReading.hasSuffix("く") {
            return String(lemmaReading.dropLast()) + "いて"
        }
        if surface.hasSuffix("いで"), lemmaExpression.hasSuffix("ぐ"), lemmaReading.hasSuffix("ぐ") {
            return String(lemmaReading.dropLast()) + "いで"
        }
        if surface.hasSuffix("って"), lemmaReading.count >= 2,
           let last = lemmaExpression.last, "うつる".contains(last) {
            return String(lemmaReading.dropLast()) + "って"
        }
        if surface.hasSuffix("んで"), lemmaExpression.count >= 2,
           let last = lemmaExpression.last, "むぶぬ".contains(last) {
            return String(lemmaReading.dropLast()) + "んで"
        }
        if surface.hasSuffix("して"), lemmaExpression.hasSuffix("する"), lemmaReading.hasSuffix("する") {
            return String(lemmaReading.dropLast(2)) + "して"
        }
        if surface.hasSuffix("して"), lemmaExpression.hasSuffix("す"), !lemmaExpression.hasSuffix("する"), lemmaReading.hasSuffix("す") {
            return String(lemmaReading.dropLast()) + "して"
        }
        if surface.hasSuffix("て"), surface.count > 1,
           !surface.hasSuffix("いて"),
           !surface.hasSuffix("って"),
           !surface.hasSuffix("んで"),
           !surface.hasSuffix("して"),
           !surface.hasSuffix("いで"),
           !surface.hasSuffix("くて"),
           !surface.hasSuffix("ぐて"),
           lemmaExpression.hasSuffix("る"),
           lemmaReading.hasSuffix("る"),
           isIchidanRuLemma(lemmaExpression: lemmaExpression, tags: tags) {
            return String(lemmaReading.dropLast()) + "て"
        }
        if surface.hasSuffix("よう"), surface.count > 2,
           lemmaExpression.hasSuffix("る"),
           lemmaReading.hasSuffix("る"),
           isIchidanRuLemma(lemmaExpression: lemmaExpression, tags: tags) {
            return String(lemmaReading.dropLast()) + "よう"
        }
        if surface.hasSuffix("う"), surface.count > 2,
           let volitional = godanVolitionalReading(surface: surface, lemmaExpression: lemmaExpression, lemmaReading: lemmaReading) {
            return volitional
        }
        return nil
    }

    /// Godan volitional (行**こう**, 読**もう**) → inflected reading from dictionary form (行く/いく → いこう).
    private static func godanVolitionalReading(
        surface: String,
        lemmaExpression: String,
        lemmaReading: String
    ) -> String? {
        let stem = String(surface.dropLast())
        guard let last = stem.last, godanVolitionalStemKana.contains(last) else { return nil }
        guard let dictFinal = godanVolitionalStemToDictFinal[last],
              lemmaExpression.hasSuffix(String(dictFinal)),
              lemmaReading.hasSuffix(String(dictFinal))
        else { return nil }
        return String(lemmaReading.dropLast()) + String(last) + "う"
    }

    private static let godanVolitionalStemKana: Set<Character> = ["お", "こ", "ご", "そ", "と", "の", "ぼ", "も", "ろ"]

    private static let godanVolitionalStemToDictFinal: [Character: Character] = [
        "お": "う", "こ": "く", "ご": "ぐ", "そ": "す", "と": "つ", "の": "ぬ", "ぼ": "ぶ", "も": "む", "ろ": "る",
    ]

    private static func stemReadingForMasuForms(lemmaExpression: String, lemmaReading: String, tags: String?) -> String? {
        if lemmaExpression.hasSuffix("する"), lemmaReading.hasSuffix("する") {
            return String(lemmaReading.dropLast(2)) + "し"
        }
        if lemmaExpression.hasSuffix("る") {
            if isIchidanRuLemma(lemmaExpression: lemmaExpression, tags: tags) {
                guard lemmaReading.hasSuffix("る") else { return nil }
                return String(lemmaReading.dropLast())
            }
            return godanRenyoReading(fromDictionaryReading: lemmaReading)
        }
        return godanRenyoReading(fromDictionaryReading: lemmaReading)
    }

    /// JMdict uses **v1** for ichidan (一段), **v5*** for godan (五段).
    private static func isIchidanVerbTag(_ tags: String?) -> Bool {
        guard let tags else { return false }
        return tags.split(whereSeparator: { $0 == " " || $0 == "\t" }).contains("v1")
    }

    private static func isGodanVerbTag(_ tags: String?) -> Bool {
        guard let tags else { return false }
        return tags.split(whereSeparator: { $0 == " " || $0 == "\t" }).contains { $0.hasPrefix("v5") }
    }

    private static let ichidanRuFallbackExpressions: Set<String> = [
        "見る", "寝る", "居る", "炒る", "煎る", "堪る", "為る", "射る",
    ]

    private static func isLikelyIchidanRuByOrthography(expression: String) -> Bool {
        if ichidanRuFallbackExpressions.contains(expression) { return true }
        guard expression.hasSuffix("る"), expression.count >= 2 else { return false }
        let chars = Array(expression)
        return isHiraganaCharacter(chars[chars.count - 2])
    }

    private static func isIchidanRuLemma(lemmaExpression: String, tags: String?) -> Bool {
        if isIchidanVerbTag(tags) { return true }
        if isGodanVerbTag(tags) { return false }
        return isLikelyIchidanRuByOrthography(expression: lemmaExpression)
    }

    private static func isHiraganaCharacter(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { (0x3040...0x309F).contains($0.value) }
    }

    /// Dictionary-form reading → 連用形 (い段) used before ます・て (godan).
    private static func godanRenyoReading(fromDictionaryReading r: String) -> String? {
        guard let last = r.last else { return nil }
        let map: [Character: Character] = [
            "く": "き", "ぐ": "ぎ", "す": "し", "つ": "ち", "ぬ": "に", "ぶ": "び", "む": "み", "る": "り", "う": "い",
        ]
        guard let i = map[last] else { return nil }
        return String(r.dropLast()) + String(i)
    }

    // MARK: - Compounds (other words sharing a kanji)

    /// Other dictionary entries whose `expression` contains one of `surface`'s kanji.
    /// Excludes `surface` itself; sorted by score so common words surface first. One row per sequence.
    func compounds(forSurface surface: String, limit: Int = 30) -> [JMDictEntry] {
        let trimmed = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let kanji = trimmed.filter { Self.isKanjiCharacter($0) }
        guard !kanji.isEmpty else { return [] }

        openDatabaseIfNeeded()
        guard let dbQueue else { return [] }

        // One LIKE clause per distinct kanji; an expression matches if it contains any of them.
        var seenKanji = Set<Character>()
        var clauses: [String] = []
        var args: [DatabaseValueConvertible] = []
        for k in kanji where seenKanji.insert(k).inserted {
            clauses.append("expression LIKE ? ESCAPE '\\'")
            args.append("%\(Self.escapeLike(String(k)))%")
        }
        guard !clauses.isEmpty else { return [] }
        args.append(trimmed)

        let sql = """
            SELECT * FROM entries
            WHERE (\(clauses.joined(separator: " OR ")))
                AND expression <> ?
                AND length(expression) > 1
            ORDER BY score DESC, id ASC
            """

        do {
            let rows = try dbQueue.read { db in
                try JMDictEntry.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            }
            // Collapse to one entry per sequence (highest score), preserving order.
            var seenSequence = Set<Int>()
            var out: [JMDictEntry] = []
            for row in rows where seenSequence.insert(row.sequence).inserted {
                out.append(row)
                if out.count >= limit { break }
            }
            return out
        } catch {
            print("JMDictStore: compounds query error: \(error)")
            return []
        }
    }

    /// Candidate two- or three-character, kanji-only expressions (e.g. 電球, 自動車),
    /// sorted by score. Cheap SQL-side filter only — callers still need to confirm every
    /// character is a real kanji (e.g. via `KanjidicStore`) since this excludes kana
    /// but not punctuation.
    func kanjiCompounds(characterCounts: [Int] = [2, 3], limit: Int = 400) -> [JMDictEntry] {
        openDatabaseIfNeeded()
        guard let dbQueue else { return [] }
        guard !characterCounts.isEmpty else { return [] }

        let placeholders = characterCounts.map { _ in "?" }.joined(separator: ", ")
        let sql = """
            SELECT * FROM entries
            WHERE length(expression) IN (\(placeholders))
                AND expression NOT GLOB '*[ぁ-んァ-ヶー]*'
            ORDER BY score DESC, id ASC
            LIMIT ?
            """

        do {
            return try dbQueue.read { db in
                var arguments: [DatabaseValueConvertible] = characterCounts.map { $0 }
                arguments.append(limit)
                return try JMDictEntry.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            }
        } catch {
            print("JMDictStore: kanjiCompounds query error: \(error)")
            return []
        }
    }

    /// Candidate two-character, kanji-only expressions (e.g. 電球), sorted by score.
    /// Cheap SQL-side filter only — callers still need to confirm both characters are
    /// real kanji (e.g. via `KanjidicStore`) since this excludes kana but not punctuation.
    func twoCharacterKanjiCompounds(limit: Int = 400) -> [JMDictEntry] {
        kanjiCompounds(characterCounts: [2], limit: limit)
    }

    private static func escapeLike(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    // MARK: - FTS search

    /// Full-text search over expression, reading, romaji, and glossary via the FTS5 index.
    /// Input is matched against all indexed columns; romaji input (e.g. "taberu") hits the
    /// pre-computed romaji column automatically. Results are sorted by score DESC.
    func search(query rawQuery: String, limit: Int = 40) -> [JMDictEntry] {
        let q = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        openDatabaseIfNeeded()
        guard let dbQueue else { return [] }

        do {
            return try dbQueue.read { db in
                // Build an FTS5 query: "term*" for prefix matching on the last token.
                let ftsQuery = Self.buildFTSQuery(q)
                return try JMDictEntry.fetchAll(
                    db,
                    sql: """
                        SELECT e.*
                        FROM entries e
                        JOIN entries_fts f ON f.rowid = e.id
                        WHERE entries_fts MATCH ?
                        ORDER BY e.score DESC, rank, e.id ASC
                        LIMIT ?
                        """,
                    arguments: [ftsQuery, limit]
                )
            }
        } catch {
            // FTS query syntax error (e.g. user typed a bare operator) — fall back to prefix LIKE
            return searchFallback(query: q, limit: limit)
        }
    }

    private func searchFallback(query: String, limit: Int) -> [JMDictEntry] {
        guard let dbQueue else { return [] }
        let pattern = query + "%"
        do {
            return try dbQueue.read { db in
                try JMDictEntry.fetchAll(
                    db,
                    sql: """
                        SELECT * FROM entries
                        WHERE expression LIKE ? OR reading LIKE ?
                        ORDER BY score DESC, id ASC
                        LIMIT ?
                        """,
                    arguments: [pattern, pattern, limit]
                )
            }
        } catch {
            return []
        }
    }

    private static func buildFTSQuery(_ input: String) -> String {
        // Split on whitespace, quote each token, append * for prefix match on the last token.
        var tokens = input.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return "\"\"" }
        let last = tokens.removeLast()
        let quoted = tokens.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        let lastQ = "\"\(last.replacingOccurrences(of: "\"", with: "\"\""))\""
        return (quoted + [lastQ + "*"]).joined(separator: " ")
    }

    /// One lookup string per token: merge forward into the **longest** prefix whose concatenation is an exact lexical match.
    ///
    /// Greedy pair-merge fails when tokenizer emits お, 釣, り: お+釣 matches お釣 first and leaves り separate. Longest match yields お釣り for all three.
    ///
    /// Two-token `X+は` only merges if `Xは` is a listed compound; otherwise the lookup surface stays `X` and `は` (topic marker
    /// is not glued to the noun for JMdict, even when `Xは` is a headword like the greeting 今日は).
    func effectiveLookupSurfaces(for tokens: [JapaneseToken]) -> [String] {
        openDatabaseIfNeeded()
        guard let dbQueue, !tokens.isEmpty else {
            return tokens.map(\.text)
        }
        let maxPhraseTokens = 12
        do {
            return try dbQueue.read { db in
                var surfaces: [String] = []
                surfaces.reserveCapacity(tokens.count)
                var cache: [String: Bool] = [:]
                func hasExact(_ surface: String) throws -> Bool {
                    if let hit = cache[surface] { return hit }
                    let v = try Self.hasExactLexicalMatch(in: db, surface: surface)
                    cache[surface] = v
                    return v
                }

                var i = tokens.startIndex
                while i < tokens.endIndex {
                    let remaining = tokens.distance(from: i, to: tokens.endIndex)
                    let maxLen = min(maxPhraseTokens, remaining)
                    var runLength = 1
                    var surface = tokens[i].text
                    if maxLen >= 2 {
                        for len in (2...maxLen).reversed() {
                            let end = tokens.index(i, offsetBy: len)
                            let merged = tokens[i..<end].map(\.text).joined()
                            if len == 2, Self.mustKeepSplit(mergedSurface: merged) {
                                continue
                            }
                            if len == 2, tokens[i + 1].text == "は",
                               !Self.mergeCompoundWithTrailingHa.contains(merged) {
                                continue
                            }
                            if try hasExact(merged) {
                                runLength = len
                                surface = merged
                                break
                            }
                        }
                    }
                    for _ in 0..<runLength {
                        surfaces.append(surface)
                    }
                    i = tokens.index(i, offsetBy: runLength)
                }
                return surfaces
            }
        } catch {
            print("JMDictStore: query error: \(error)")
            return tokens.map(\.text)
        }
    }

    private static func hasExactLexicalMatch(in db: Database, surface: String) throws -> Bool {
        guard !surface.isEmpty else { return false }
        return try Int.fetchOne(
            db,
            sql: """
                SELECT 1 FROM entries
                WHERE expression = ? OR reading = ?
                    OR (primary_reading IS NOT NULL AND primary_reading = ?)
                LIMIT 1
                """,
            arguments: [surface, surface, surface]
        ) != nil
    }

    private func exactMatch(in db: Database, surface: String) throws -> [JMDictEntry]? {
        let rows = try JMDictEntry.fetchAll(
            db,
            sql: """
                SELECT * FROM entries
                WHERE expression = ? OR reading = ?
                    OR (primary_reading IS NOT NULL AND primary_reading = ?)
                ORDER BY score DESC, id ASC
                """,
            arguments: [surface, surface, surface]
        )
        return rows
    }

    private func prefixMatchExpression(in db: Database, surface: String, limit: Int) throws -> [JMDictEntry] {
        // LIKE 'surface%'
        let pattern = surface + "%"
        return try JMDictEntry.fetchAll(
            db,
            sql: """
                SELECT * FROM entries
                WHERE expression LIKE ?
                ORDER BY score DESC, id ASC
                LIMIT ?
                """,
            arguments: [pattern, limit]
        )
    }

    /// `NLTokenizer` surfaces like 歩いて tail-trim to the lone kanji 歩, which is a separate JMdict headword (e.g. reading ほ)
    /// and often outranks the intended lemma 歩く. Skip that hit when the user’s surface clearly has okurigana.
    private static func shouldRejectSpuriousSingleKanjiTailMatch(trimmed: String, original: String) -> Bool {
        guard trimmed != original, isSingleUnifiedKanjiExpression(trimmed), containsHiragana(original) else {
            return false
        }
        return true
    }

    private static func containsHiragana(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x3040...0x309F).contains($0.value) }
    }

    private static func isSingleUnifiedKanjiExpression(_ s: String) -> Bool {
        guard s.count == 1, let u = s.unicodeScalars.first else { return false }
        let v = u.value
        return (0x3400...0x4DBF).contains(v) || (0x4E00...0x9FFF).contains(v)
    }

    /// True when `buildInflectionLemmaCandidates` would try at least one dictionary-form rewrite (e.g. 歩いて → 歩く).
    private static func looksInflectedForLemmaGuess(_ surface: String) -> Bool {
        !buildInflectionLemmaCandidates(surface: surface).isEmpty
    }

    /// Map common inflected endings to dictionary-form guesses (best matching row wins on `score`).
    private func bestLemmaGuessExactMatch(in db: Database, surface: String) throws -> [JMDictEntry]? {
        let guesses = Self.buildInflectionLemmaCandidates(surface: surface)
        let mustBeVerb = Self.surfaceRequiresVerbLemma(surface)
        var bestRows: [JMDictEntry]?
        var bestScore = Int.min
        for g in guesses {
            guard var rows = try exactMatch(in: db, surface: g), !rows.isEmpty else {
                print("JMDict bestLemma: candidate '\(g)' — no match")
                continue
            }
            if mustBeVerb {
                let verbRows = rows.filter { Self.isVerbEntry($0) }
                guard !verbRows.isEmpty else { continue }
                rows = verbRows
            }
            let top = rows.first?.score ?? Int.min
            if top > bestScore {
                bestScore = top
                bestRows = rows
            }
        }
        return bestRows
    }

    /// True when the surface ending unambiguously indicates a verb conjugation,
    /// so only verb lemma candidates should be considered.
    private static func surfaceRequiresVerbLemma(_ surface: String) -> Bool {
        let verbEndings = [
            "って", "んで", "いて", "いで", "して",
            "ました", "ます", "ません", "ましょう",
            "なかった", "なくて", "なければ", "なきゃ", "なくちゃ",
            "ない", "て",
            "よう", "ろう", "もう", "ぼう", "のう", "とう", "そう", "ごう", "こう", "おう",
        ]
        return verbEndings.contains { surface.hasSuffix($0) && surface.count > $0.count }
    }

    private static func isVerbEntry(_ entry: JMDictEntry) -> Bool {
        guard let tags = entry.tags else { return false }
        return tags.split(whereSeparator: { $0 == " " || $0 == "\t" }).contains {
            $0.hasPrefix("v") && $0 != "vs"
        }
    }

    private static func godanUFromIRenyoStem(_ stem: String) -> String? {
        guard let last = stem.last else { return nil }
        let map: [Character: Character] = [
            "き": "く", "ぎ": "ぐ", "し": "す", "ち": "つ", "に": "ぬ", "び": "ぶ", "み": "む", "り": "る", "い": "う",
        ]
        guard let u = map[last] else { return nil }
        return String(stem.dropLast()) + String(u)
    }

    /// Godan volitional stem (行**こ**, 読**も**) → dictionary う-form (行**く**, 読**む**).
    private static func godanUFromVolitionalStem(_ stem: String) -> String? {
        guard let last = stem.last, let dictFinal = godanVolitionalStemToDictFinal[last] else { return nil }
        return String(stem.dropLast()) + String(dictFinal)
    }

    /// Godan negative stem (行**か**, 飲**ま**) → dictionary う-form (行**く**, 飲**む**).
    private static func godanUFromNegativeStem(_ stem: String) -> String? {
        guard let last = stem.last else { return nil }
        let map: [Character: Character] = [
            "わ": "う", "あ": "う",
            "か": "く", "が": "ぐ", "さ": "す", "た": "つ", "な": "ぬ", "ば": "ぶ", "ま": "む", "ら": "る",
        ]
        guard let u = map[last] else { return nil }
        return String(stem.dropLast()) + String(u)
    }

    private static func addVerbLemmaCandidates(fromNegativeStem stem: String, add: (String) -> Void) {
        guard !stem.isEmpty else { return }
        if stem == "し" {
            add("する")
            return
        }
        if stem.last == "し" {
            add(String(stem.dropLast()) + "する")
        }
        add(stem + "る")
        if let g = godanUFromNegativeStem(stem) { add(g) }
    }

    private static func buildInflectionLemmaCandidates(surface: String) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        func add(_ s: String) {
            guard !s.isEmpty, !seen.contains(s) else { return }
            seen.insert(s)
            out.append(s)
        }

        if surface.hasSuffix("ましょう"), surface.count > 4 {
            let stem = String(surface.dropLast(4))
            add(stem + "る")
            if let g = godanUFromIRenyoStem(stem) { add(g) }
        }
        if surface.hasSuffix("ました"), surface.count > 3 {
            let stem = String(surface.dropLast(3))
            add(stem + "る")
            if let g = godanUFromIRenyoStem(stem) { add(g) }
        }
        if surface.hasSuffix("ません"), surface.count > 3 {
            let stem = String(surface.dropLast(3))
            add(stem + "る")
            if let g = godanUFromIRenyoStem(stem) { add(g) }
        }
        if surface.hasSuffix("ます"), surface.count > 2 {
            let stem = String(surface.dropLast(2))
            add(stem + "る")
            if let g = godanUFromIRenyoStem(stem) { add(g) }
        }
        if surface.hasSuffix("なくちゃいけない"), surface.count > 7 {
            addVerbLemmaCandidates(fromNegativeStem: String(surface.dropLast(7)), add: add)
        }
        if surface.hasSuffix("なきゃいけない"), surface.count > 6 {
            addVerbLemmaCandidates(fromNegativeStem: String(surface.dropLast(6)), add: add)
        }
        if surface.hasSuffix("なくちゃ"), surface.count > 4 {
            addVerbLemmaCandidates(fromNegativeStem: String(surface.dropLast(4)), add: add)
        }
        if surface.hasSuffix("なきゃ"), surface.count > 3 {
            addVerbLemmaCandidates(fromNegativeStem: String(surface.dropLast(3)), add: add)
        }
        if surface.hasSuffix("なければ"), surface.count > 4 {
            addVerbLemmaCandidates(fromNegativeStem: String(surface.dropLast(4)), add: add)
        }
        if surface.hasSuffix("なかった"), surface.count > 4 {
            addVerbLemmaCandidates(fromNegativeStem: String(surface.dropLast(4)), add: add)
        }
        if surface.hasSuffix("なくて"), surface.count > 3 {
            addVerbLemmaCandidates(fromNegativeStem: String(surface.dropLast(3)), add: add)
        }
        if surface.hasSuffix("ない"), surface.count > 2,
           !surface.hasSuffix("くない"),
           !surface.hasSuffix("くなかった"),
           !surface.hasSuffix("くなくて"),
           !surface.hasSuffix("ではない"),
           !surface.hasSuffix("じゃない")
        {
            addVerbLemmaCandidates(fromNegativeStem: String(surface.dropLast(2)), add: add)
        }
        if surface.hasSuffix("いて"), surface.count > 2 {
            add(String(surface.dropLast(2)) + "く")
        }
        if surface.hasSuffix("いで"), surface.count > 2 {
            add(String(surface.dropLast(2)) + "ぐ")
        }
        if surface.hasSuffix("って"), surface.count > 2 {
            let stem = String(surface.dropLast(2))
            // Try verb endings first so verb lemmas win score ties over nouns (e.g. やって→やる not やつ)
            add(stem + "る")
            add(stem + "う")
            add(stem + "つ")
        }
        // Tokenizer splits mid-contraction: 残ってる → 残っ + てる. The bare っ-final
        // stem is the godan 連用形 double-consonant form; try つ and う endings.
        if surface.hasSuffix("っ"), surface.count > 1 {
            let stem = String(surface.dropLast())
            add(stem + "つ")
            add(stem + "う")
            add(stem + "る")
        }
        if surface.hasSuffix("んで"), surface.count > 2 {
            let b = String(surface.dropLast(2))
            if b.last == "ん", b.count >= 2 {
                let h = String(b.dropLast())
                add(h + "む")
                add(h + "ぶ")
                add(h + "ぬ")
            }
        }
        if surface.hasSuffix("して"), surface.count > 2 {
            let stem = String(surface.dropLast(2))
            if stem.last == "し" {
                let h = String(stem.dropLast())
                add(h + "する")
                add(h + "す")
            }
        }

        if surface.hasSuffix("よう"), surface.count > 2 {
            add(String(surface.dropLast(2)) + "る")
        }
        if surface.hasSuffix("う"), surface.count > 2 {
            let stem = String(surface.dropLast())
            if let dict = godanUFromVolitionalStem(stem) { add(dict) }
        }

        if surface.hasSuffix("て"), surface.count > 1,
           !surface.hasSuffix("いて"),
           !surface.hasSuffix("って"),
           !surface.hasSuffix("んで"),
           !surface.hasSuffix("して"),
           !surface.hasSuffix("いで"),
           !surface.hasSuffix("くて"),
           !surface.hasSuffix("ぐて")
        {
            add(String(surface.dropLast()) + "る")
        }

        return out
    }
}
