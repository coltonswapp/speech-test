//
//  HiraganaRomaji.swift
//  shizen
//
//  Hepburn-style romanization for hiragana vocabulary display (DEBUG).
//


import Foundation

enum HiraganaRomaji {

    /// Splits kana into display syllables (e.g. ありがとう → ["あ", "り", "が", "と", "う"]).
    static func syllables(in text: String, script: KanaScript = .hiragana) -> [String] {
        let normalized = script == .katakana ? KanaCurriculum.katakanaToHiragana(text) : text
        let hiraSyllables = syllablesInHiragana(normalized)
        guard script == .katakana else { return hiraSyllables }
        return hiraSyllables.map { KanaCurriculum.hiraganaToKatakana($0) }
    }

    /// All glyphs usable as spelling-grid distractors for the given script.
    static func allGlyphs(script: KanaScript = .hiragana) -> [String] {
        switch script {
        case .hiragana: allKanaGlyphs
        case .katakana: allKanaGlyphs.map { KanaCurriculum.hiraganaToKatakana($0) }
        }
    }

    /// Splits hiragana into display syllables.
    private static func syllablesInHiragana(_ text: String) -> [String] {
        var result: [String] = []
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            if chars[index] == "っ" {
                result.append("っ")
                index += 1
                continue
            }
            if let syllable = readSyllable(chars, from: index) {
                let slice = String(chars[index ..< index + syllable.length])
                result.append(slice)
                index += syllable.length
                continue
            }
            result.append(String(chars[index]))
            index += 1
        }
        return result
    }

    /// All hiragana glyphs usable as spelling-grid distractors.
    static var allKanaGlyphs: [String] {
        var glyphs = kana.keys.map { String($0) }
        glyphs.append(contentsOf: yoon.keys)
        return glyphs
    }

    /// Romanizes hiragana or katakana strings for detail list lines (e.g. あさ / アサ → asa).
    static func romanize(_ text: String) -> String {
        let normalized = KanaScript.detecting(in: text) == .katakana
            ? KanaCurriculum.katakanaToHiragana(text)
            : text
        var result = ""
        let chars = Array(normalized)
        var index = 0
        while index < chars.count {
            let ch = chars[index]
            if ch == "っ" {
                if let next = peekSyllable(chars, from: index + 1)?.consonant {
                    result += next
                }
                index += 1
                continue
            }
            if let syllable = readSyllable(chars, from: index) {
                result += syllable.romaji
                index += syllable.length
                continue
            }
            result += String(ch)
            index += 1
        }
        return result
    }

    private struct Syllable {
        let romaji: String
        let length: Int
        var consonant: String? {
            guard let first = romaji.first else { return nil }
            return String(first)
        }
    }

    private static let yoon: [String: String] = [
        "きゃ": "kya", "きゅ": "kyu", "きょ": "kyo",
        "ぎゃ": "gya", "ぎゅ": "gyu", "ぎょ": "gyo",
        "しゃ": "sha", "しゅ": "shu", "しょ": "sho",
        "じゃ": "ja", "じゅ": "ju", "じょ": "jo",
        "ちゃ": "cha", "ちゅ": "chu", "ちょ": "cho",
        "にゃ": "nya", "にゅ": "nyu", "にょ": "nyo",
        "ひゃ": "hya", "ひゅ": "hyu", "ひょ": "hyo",
        "びゃ": "bya", "びゅ": "byu", "びょ": "byo",
        "ぴゃ": "pya", "ぴゅ": "pyu", "ぴょ": "pyo",
        "みゃ": "mya", "みゅ": "myu", "みょ": "myo",
        "りゃ": "rya", "りゅ": "ryu", "りょ": "ryo",
    ]

    private static let kana: [Character: String] = [
        "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
        "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
        "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
        "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
        "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
        "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
        "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
        "や": "ya", "ゆ": "yu", "よ": "yo",
        "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
        "わ": "wa", "を": "wo", "ん": "n",
        "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
        "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
        "だ": "da", "ぢ": "ji", "づ": "zu", "で": "de", "ど": "do",
        "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
        "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
        "ー": "-",
    ]

    private static func readSyllable(_ chars: [Character], from index: Int) -> Syllable? {
        guard index < chars.count else { return nil }
        if index + 1 < chars.count {
            let pair = String(chars[index...index + 1])
            if let romaji = yoon[pair] {
                return Syllable(romaji: romaji, length: 2)
            }
        }
        let one = chars[index]
        if let romaji = kana[one] {
            return Syllable(romaji: romaji, length: 1)
        }
        return nil
    }

    private static func peekSyllable(_ chars: [Character], from index: Int) -> Syllable? {
        readSyllable(chars, from: index)
    }
}

