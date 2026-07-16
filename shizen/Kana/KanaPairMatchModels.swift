//
//  KanaPairMatchModels.swift
//  shizen
//
//  Tap-to-match rounds: hiragana ↔ romaji pairs (single glyphs and short words).
//

import Foundation

struct KanaPairMatchPair: Equatable, Hashable {
    let kana: String
    let romaji: String
    /// Hiragana (or display kana) passed to the pronunciation player.
    let speaksKana: String
    /// Spelling-bank key when this pair comes from a vocabulary word.
    let spellingWordKey: String?

    init(
        kana: String,
        romaji: String,
        speaksKana: String? = nil,
        spellingWordKey: String? = nil
    ) {
        self.kana = kana
        self.romaji = romaji
        self.speaksKana = speaksKana ?? kana
        self.spellingWordKey = spellingWordKey
    }

    var pairID: String { "\(speaksKana)|\(romaji)" }
}

enum KanaPairMatchSideLayout {
    case kanaOnLeft
    case romajiOnLeft
}

struct KanaPairMatchRound {
    let sideLayout: KanaPairMatchSideLayout
    let pairs: [KanaPairMatchPair]
    /// Kana strings recorded in progress when the step completes.
    let progressKana: [String]

    static let preferredPairCount = 4

    init(sideLayout: KanaPairMatchSideLayout, pairs: [KanaPairMatchPair]) {
        self.sideLayout = sideLayout
        self.pairs = pairs
        self.progressKana = pairs.flatMap { pair in
            let normalized = KanaScript.detecting(in: pair.speaksKana) == .katakana
                ? KanaCurriculum.katakanaToHiragana(pair.speaksKana)
                : pair.speaksKana
            return HiraganaRomaji.syllables(in: normalized, script: .hiragana)
        }
    }
}

enum KanaPairMatchRoundBank {
    static let rounds: [KanaPairMatchRound] = [
        KanaPairMatchRound(
            sideLayout: .kanaOnLeft,
            pairs: [
                KanaPairMatchPair(kana: "か", romaji: "ka"),
                KanaPairMatchPair(kana: "さ", romaji: "sa"),
                KanaPairMatchPair(kana: "ね", romaji: "ne"),
                KanaPairMatchPair(kana: "み", romaji: "mi"),
            ]
        ),
        KanaPairMatchRound(
            sideLayout: .romajiOnLeft,
            pairs: [
                KanaPairMatchPair(kana: "た", romaji: "ta"),
                KanaPairMatchPair(kana: "の", romaji: "no"),
                KanaPairMatchPair(kana: "き", romaji: "ki"),
                KanaPairMatchPair(kana: "れ", romaji: "re"),
            ]
        ),
        KanaPairMatchRound(
            sideLayout: .kanaOnLeft,
            pairs: [
                KanaPairMatchPair(kana: "あめ", romaji: "ame"),
                KanaPairMatchPair(kana: "うみ", romaji: "umi"),
                KanaPairMatchPair(kana: "いぬ", romaji: "inu"),
                KanaPairMatchPair(kana: "ねこ", romaji: "neko"),
            ]
        ),
        KanaPairMatchRound(
            sideLayout: .romajiOnLeft,
            pairs: [
                KanaPairMatchPair(kana: "あお", romaji: "ao"),
                KanaPairMatchPair(kana: "かお", romaji: "kao"),
                KanaPairMatchPair(kana: "そら", romaji: "sora"),
                KanaPairMatchPair(kana: "みず", romaji: "mizu"),
            ]
        ),
    ]
}
