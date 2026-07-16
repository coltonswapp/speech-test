//
//  KanaCurriculum.swift
//  shizen
//
//  Canonical hiragana/katakana row and glyph definitions for charts and lessons.
//

import Foundation

enum KanaScript: String, Codable, Hashable {
    case hiragana
    case katakana

    var displayName: String {
        switch self {
        case .hiragana: "hiragana"
        case .katakana: "katakana"
        }
    }

    static func detecting(in text: String) -> KanaScript {
        for scalar in text.unicodeScalars {
            if (0x30A0...0x30FF).contains(scalar.value) { return .katakana }
            if (0x3040...0x309F).contains(scalar.value) { return .hiragana }
        }
        return .hiragana
    }
}

enum KanaSection: String, Codable, Hashable {
    case seion
    case voiced
    case yoon
}

struct KanaGlyph: Hashable {
    let kana: String
    let romaji: String
    let script: KanaScript
    let rowID: String
    let section: KanaSection
}

struct KanaRow {
    let id: String
    let displayName: String
    let rowSound: String
    /// Five chart slots; `(nil, nil)` = textbook gap.
    let cells: [(kana: String?, romaji: String?)]
    let glyphs: [KanaGlyph]
    let section: KanaSection
    let orderIndex: Int
    let script: KanaScript

    var kanaSet: Set<String> {
        Set(glyphs.map(\.kana))
    }
}

enum KanaCurriculum {

    static let sheetEmpty: (String?, String?) = (nil, nil)
    static let vowelSuffixes = ["-a", "-i", "-u", "-e", "-o"]
    static let yoonColumnHeaders = ["-ya", "-yu", "-yo", "", ""]

    // MARK: - Hiragana seion (lesson path v1)

    static let hiraganaSeionRows: [KanaRow] = {
        let specs: [(id: String, displayName: String, rowSound: String, k: [String], r: [String])] = [
            ("vowel", "あ row", "", ["あ", "い", "う", "え", "お"], ["a", "i", "u", "e", "o"]),
            ("k", "か row", "k-", ["か", "き", "く", "け", "こ"], ["ka", "ki", "ku", "ke", "ko"]),
            ("s", "さ row", "s-", ["さ", "し", "す", "せ", "そ"], ["sa", "shi", "su", "se", "so"]),
            ("t", "た row", "t-", ["た", "ち", "つ", "て", "と"], ["ta", "chi", "tsu", "te", "to"]),
            ("n", "な row", "n-", ["な", "に", "ぬ", "ね", "の"], ["na", "ni", "nu", "ne", "no"]),
            ("h", "は row", "h-", ["は", "ひ", "ふ", "へ", "ほ"], ["ha", "hi", "fu", "he", "ho"]),
            ("m", "ま row", "m-", ["ま", "み", "む", "め", "も"], ["ma", "mi", "mu", "me", "mo"]),
            ("y", "や row", "y-", ["や", "ゆ", "よ"], ["ya", "yu", "yo"]),
            ("r", "ら row", "r-", ["ら", "り", "る", "れ", "ろ"], ["ra", "ri", "ru", "re", "ro"]),
            ("w", "わ row", "w-", ["わ", "を"], ["wa", "wo"]),
            ("nStandalone", "ん", "", ["ん"], ["n"]),
        ]

        return specs.enumerated().map { index, spec in
            let cells = chartCells(kana: spec.k, romaji: spec.r, rowID: spec.id)
            let glyphs = zipKana(spec.k, spec.r).map { pair in
                KanaGlyph(
                    kana: pair.kana!,
                    romaji: pair.romaji!,
                    script: .hiragana,
                    rowID: spec.id,
                    section: .seion
                )
            }
            return KanaRow(
                id: spec.id,
                displayName: spec.displayName,
                rowSound: spec.rowSound,
                cells: cells,
                glyphs: glyphs,
                section: .seion,
                orderIndex: index,
                script: .hiragana
            )
        }
    }()

    // MARK: - Katakana seion (lesson path v1)

    static let katakanaSeionRows: [KanaRow] = hiraganaSeionRows.map { mapRowToKatakana($0) }

    static func row(id: String, script: KanaScript = .hiragana, section: KanaSection = .seion) -> KanaRow? {
        switch (script, section) {
        case (.hiragana, .seion):
            return hiraganaSeionRows.first { $0.id == id }
        case (.hiragana, .voiced):
            return hiraganaVoicedChartRows.first { $0.id == id }
        case (.hiragana, .yoon):
            return hiraganaYoonChartRows.first { $0.id == id }
        case (.katakana, .seion):
            return katakanaSeionRows.first { $0.id == id }
        case (.katakana, .voiced):
            return katakanaVoicedChartRows.first { $0.id == id }
        case (.katakana, .yoon):
            return katakanaYoonChartRows.first { $0.id == id }
        }
    }

    static func glyph(kana: String, script: KanaScript? = nil) -> KanaGlyph? {
        if let script {
            return allGlyphs(script: script).first { $0.kana == kana }
        }
        return allGlyphs(script: .hiragana).first { $0.kana == kana }
            ?? allGlyphs(script: .katakana).first { $0.kana == kana }
    }

    static func allGlyphs(script: KanaScript = .hiragana) -> [KanaGlyph] {
        switch script {
        case .hiragana:
            return hiraganaSeionRows.flatMap(\.glyphs)
                + hiraganaVoicedChartRows.flatMap(\.glyphs)
                + hiraganaYoonChartRows.flatMap(\.glyphs)
        case .katakana:
            return katakanaSeionRows.flatMap(\.glyphs)
                + katakanaVoicedChartRows.flatMap(\.glyphs)
                + katakanaYoonChartRows.flatMap(\.glyphs)
        }
    }

    static func seionLessonRows(script: KanaScript) -> [KanaRow] {
        switch script {
        case .hiragana: hiraganaSeionRows
        case .katakana: katakanaSeionRows
        }
    }

    /// Compact 10×10 grid ordering (92 glyphs): seion + voiced + core yōon rows (excludes g/j/b/p yōon).
    static func progressGridGlyphs(script: KanaScript = .hiragana) -> [KanaGlyph] {
        let hiragana = hiraganaSeionRows.flatMap(\.glyphs)
            + hiraganaVoicedChartRows.flatMap(\.glyphs)
            + hiraganaYoonChartRows.prefix(7).flatMap(\.glyphs)
        precondition(hiragana.count == 92, "Expected 92 progress-grid glyphs, got \(hiragana.count)")
        switch script {
        case .hiragana:
            return hiragana
        case .katakana:
            return hiragana.map { glyph in
                KanaGlyph(
                    kana: hiraganaToKatakana(glyph.kana),
                    romaji: glyph.romaji,
                    script: .katakana,
                    rowID: glyph.rowID,
                    section: glyph.section
                )
            }
        }
    }

    static func hiraganaToKatakana(_ text: String) -> String {
        (text as NSString).applyingTransform(.hiraganaToKatakana, reverse: false) as String? ?? text
    }

    static func katakanaToHiragana(_ text: String) -> String {
        (text as NSString).applyingTransform(.hiraganaToKatakana, reverse: true) as String? ?? text
    }

    // MARK: - Hiragana chart rows (reference + learning chart)

    static let hiraganaSeionChartRows: [KanaRow] = hiraganaSeionRows

    static let hiraganaVoicedChartRows: [KanaRow] = {
        let specs: [(id: String, rowSound: String, k: [String], r: [String])] = [
            ("g", "g-", ["が", "ぎ", "ぐ", "げ", "ご"], ["ga", "gi", "gu", "ge", "go"]),
            ("z", "z-", ["ざ", "じ", "ず", "ぜ", "ぞ"], ["za", "ji", "zu", "ze", "zo"]),
            ("d", "d-", ["だ", "ぢ", "づ", "で", "ど"], ["da", "ji", "zu", "de", "do"]),
            ("b", "b-", ["ば", "び", "ぶ", "べ", "ぼ"], ["ba", "bi", "bu", "be", "bo"]),
            ("p", "p-", ["ぱ", "ぴ", "ぷ", "ぺ", "ぽ"], ["pa", "pi", "pu", "pe", "po"]),
        ]
        return makeChartRows(specs: specs, section: .voiced, script: .hiragana)
    }()

    static let hiraganaYoonChartRows: [KanaRow] = {
        let specs: [(id: String, rowSound: String, k: [String], r: [String])] = [
            ("ky", "k-", ["きゃ", "きゅ", "きょ"], ["kya", "kyu", "kyo"]),
            ("sh", "sh-", ["しゃ", "しゅ", "しょ"], ["sha", "shu", "sho"]),
            ("ch", "ch-", ["ちゃ", "ちゅ", "ちょ"], ["cha", "chu", "cho"]),
            ("ny", "n-", ["にゃ", "にゅ", "にょ"], ["nya", "nyu", "nyo"]),
            ("hy", "h-", ["ひゃ", "ひゅ", "ひょ"], ["hya", "hyu", "hyo"]),
            ("my", "m-", ["みゃ", "みゅ", "みょ"], ["mya", "myu", "myo"]),
            ("ry", "r-", ["りゃ", "りゅ", "りょ"], ["rya", "ryu", "ryo"]),
            ("gy", "g-", ["ぎゃ", "ぎゅ", "ぎょ"], ["gya", "gyu", "gyo"]),
            ("j", "j-", ["じゃ", "じゅ", "じょ"], ["ja", "ju", "jo"]),
            ("by", "b-", ["びゃ", "びゅ", "びょ"], ["bya", "byu", "byo"]),
            ("py", "p-", ["ぴゃ", "ぴゅ", "ぴょ"], ["pya", "pyu", "pyo"]),
        ]
        return specs.enumerated().map { index, spec in
            let zipped = zipKana(spec.k, spec.r) + [sheetEmpty, sheetEmpty]
            let glyphs = zipKana(spec.k, spec.r).compactMap { pair -> KanaGlyph? in
                guard let kana = pair.kana, let romaji = pair.romaji else { return nil }
                return KanaGlyph(kana: kana, romaji: romaji, script: .hiragana, rowID: spec.id, section: .yoon)
            }
            return KanaRow(
                id: "yoon-\(spec.id)",
                displayName: spec.rowSound,
                rowSound: spec.rowSound,
                cells: zipped,
                glyphs: glyphs,
                section: .yoon,
                orderIndex: index,
                script: .hiragana
            )
        }
    }()

    static let katakanaSeionChartRows: [KanaRow] = katakanaSeionRows

    static let katakanaVoicedChartRows: [KanaRow] = hiraganaVoicedChartRows.map { mapRowToKatakana($0) }

    static let katakanaYoonChartRows: [KanaRow] = hiraganaYoonChartRows.map { mapRowToKatakana($0) }

    // MARK: - Helpers

    private static func mapRowToKatakana(_ row: KanaRow) -> KanaRow {
        let cells = row.cells.map { cell in
            (cell.kana.map(hiraganaToKatakana), cell.romaji)
        }
        let glyphs = row.glyphs.map { glyph in
            KanaGlyph(
                kana: hiraganaToKatakana(glyph.kana),
                romaji: glyph.romaji,
                script: .katakana,
                rowID: glyph.rowID,
                section: glyph.section
            )
        }
        let displayName: String
        if row.displayName.hasSuffix(" row"), let first = row.displayName.first {
            displayName = "\(hiraganaToKatakana(String(first))) row"
        } else {
            displayName = hiraganaToKatakana(row.displayName)
        }
        return KanaRow(
            id: row.id,
            displayName: displayName,
            rowSound: row.rowSound,
            cells: cells,
            glyphs: glyphs,
            section: row.section,
            orderIndex: row.orderIndex,
            script: .katakana
        )
    }

    static func zipKana(_ k: [String], _ r: [String]) -> [(kana: String?, romaji: String?)] {
        precondition(k.count == r.count && !r.isEmpty)
        return zip(k, r).map { (kana: $0.0, romaji: $0.1) }
    }

    private static func chartCells(kana: [String], romaji: [String], rowID: String) -> [(kana: String?, romaji: String?)] {
        switch rowID {
        case "y":
            return [("や", "ya"), sheetEmpty, ("ゆ", "yu"), sheetEmpty, ("よ", "yo")]
        case "w":
            return [("わ", "wa"), sheetEmpty, sheetEmpty, sheetEmpty, ("を", "wo")]
        case "nStandalone":
            return [sheetEmpty, sheetEmpty, ("ん", "n"), sheetEmpty, sheetEmpty]
        default:
            return zipKana(kana, romaji)
        }
    }

    private static func makeChartRows(
        specs: [(id: String, rowSound: String, k: [String], r: [String])],
        section: KanaSection,
        script: KanaScript
    ) -> [KanaRow] {
        specs.enumerated().map { index, spec in
            let cells = zipKana(spec.k, spec.r)
            let glyphs = zipKana(spec.k, spec.r).map { pair in
                KanaGlyph(
                    kana: pair.kana!,
                    romaji: pair.romaji!,
                    script: script,
                    rowID: spec.id,
                    section: section
                )
            }
            return KanaRow(
                id: spec.id,
                displayName: spec.rowSound,
                rowSound: spec.rowSound,
                cells: cells,
                glyphs: glyphs,
                section: section,
                orderIndex: index,
                script: script
            )
        }
    }
}
