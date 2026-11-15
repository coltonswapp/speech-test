//
//  KanaRomanizer.swift
//  shizen
//
//  Hepburn-style romaji for hiragana, katakana, or mixed kana (e.g. ウォーターパーク → wootaapaaku).
//  Pure Foundation so RomajiTests can compile this file directly (symlinked there).
//

import Foundation

enum KanaRomanizer {

    /// Romanizes kana. Katakana is folded to hiragana per character, so mixed strings work.
    ///
    /// - Long vowel ー repeats the previous vowel (コーヒー → koohii), matching the app's
    ///   long-vowel convention. With no vowel before it, ー stays `-`.
    /// - Small ッ / っ doubles the next consonant (キップ → kippu).
    /// - Loanword digraphs (ウォ, ティ, ファ, ヴァ, …) read as one syllable.
    /// - Small kana are never left in the output; a stray one reads as its full-size vowel.
    static func romanize(_ text: String) -> String {
        let chars = Array(foldKatakanaToHiragana(text))
        var result = ""
        var index = 0
        while index < chars.count {
            let ch = chars[index]
            if ch == "っ" {
                if let next = readSyllable(chars, from: index + 1),
                   let first = next.romaji.first,
                   !vowels.contains(first) {
                    result.append(first)
                }
                index += 1
                continue
            }
            if ch == "ー" {
                if let last = result.last, vowels.contains(last) {
                    result.append(last)
                } else {
                    result += "-"
                }
                index += 1
                continue
            }
            if ch == "・" {
                result += " "
                index += 1
                continue
            }
            if let syllable = readSyllable(chars, from: index) {
                result += syllable.romaji
                index += syllable.length
                continue
            }
            result.append(ch)
            index += 1
        }
        return result
    }

    // MARK: - Internals

    private static let vowels: Set<Character> = ["a", "i", "u", "e", "o"]

    /// Katakana ァ…ヶ (U+30A1–U+30F6) map to hiragana by a fixed offset. ー and ・ are left
    /// alone so `romanize` can handle them. ICU's transform would expand ー into a vowel kana,
    /// which also breaks ウォー (うぉお) into separate syllables.
    private static func foldKatakanaToHiragana(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if (0x30A1...0x30F6).contains(scalar.value),
               let hira = Unicode.Scalar(scalar.value - 0x60) {
                scalars.append(hira)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    private struct Syllable {
        let romaji: String
        let length: Int
    }

    private static func readSyllable(_ chars: [Character], from index: Int) -> Syllable? {
        guard index < chars.count else { return nil }
        if index + 1 < chars.count {
            let pair = String(chars[index...index + 1])
            if let romaji = yoon[pair] ?? loanwordDigraphs[pair] {
                return Syllable(romaji: romaji, length: 2)
            }
        }
        if let romaji = kana[chars[index]] {
            return Syllable(romaji: romaji, length: 1)
        }
        return nil
    }

    private static let yoon: [String: String] = [
        "きゃ": "kya", "きゅ": "kyu", "きょ": "kyo",
        "ぎゃ": "gya", "ぎゅ": "gyu", "ぎょ": "gyo",
        "しゃ": "sha", "しゅ": "shu", "しょ": "sho",
        "じゃ": "ja", "じゅ": "ju", "じょ": "jo",
        "ちゃ": "cha", "ちゅ": "chu", "ちょ": "cho",
        "ぢゃ": "ja", "ぢゅ": "ju", "ぢょ": "jo",
        "にゃ": "nya", "にゅ": "nyu", "にょ": "nyo",
        "ひゃ": "hya", "ひゅ": "hyu", "ひょ": "hyo",
        "びゃ": "bya", "びゅ": "byu", "びょ": "byo",
        "ぴゃ": "pya", "ぴゅ": "pyu", "ぴょ": "pyo",
        "みゃ": "mya", "みゅ": "myu", "みょ": "myo",
        "りゃ": "rya", "りゅ": "ryu", "りょ": "ryo",
    ]

    /// Gairaigo combinations (written in hiragana after folding).
    private static let loanwordDigraphs: [String: String] = [
        "うぁ": "wa", "うぃ": "wi", "うぇ": "we", "うぉ": "wo",
        "ゔぁ": "va", "ゔぃ": "vi", "ゔぇ": "ve", "ゔぉ": "vo", "ゔゅ": "vyu",
        "ふぁ": "fa", "ふぃ": "fi", "ふぇ": "fe", "ふぉ": "fo", "ふゅ": "fyu",
        "てぃ": "ti", "でぃ": "di", "てゅ": "tyu", "でゅ": "dyu",
        "とぅ": "tu", "どぅ": "du",
        "ちぇ": "che", "しぇ": "she", "じぇ": "je",
        "つぁ": "tsa", "つぃ": "tsi", "つぇ": "tse", "つぉ": "tso",
        "くぁ": "kwa", "くぃ": "kwi", "くぇ": "kwe", "くぉ": "kwo",
        "ぐぁ": "gwa",
        "いぇ": "ye",
        "すぃ": "si", "ずぃ": "zi",
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
        "わ": "wa", "ゐ": "i", "ゑ": "e", "を": "wo", "ん": "n",
        "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
        "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
        "だ": "da", "ぢ": "ji", "づ": "zu", "で": "de", "ど": "do",
        "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
        "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
        "ゔ": "vu",
        // Small kana with no digraph partner: read as the full-size sound, never pass through.
        "ぁ": "a", "ぃ": "i", "ぅ": "u", "ぇ": "e", "ぉ": "o",
        "ゃ": "ya", "ゅ": "yu", "ょ": "yo", "ゎ": "wa",
        "ゕ": "ka", "ゖ": "ke",
    ]
}
