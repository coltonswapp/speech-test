//
//  KanaSpellingModels.swift
//  shizen
//

import Foundation

struct KanaSpellingWord: Equatable {
    let hiragana: String
    let romaji: String
    /// Short English gloss shown while spelling for association.
    let meaning: String
}

/// Whether the learner sees the target romaji or only hears the word.
enum KanaSpellingPromptStyle {
    case romaji
    case audio
}

/// One spelling step in a row lesson or review session.
struct KanaLessonSpellingItem: Equatable {
    let word: KanaSpellingWord
    let promptStyle: KanaSpellingPromptStyle
}

/// Whether spelling word selection favors the current batch or previously learned glyphs.
enum KanaSpellingSelectionBias {
    case currentBatch
    case priorLearning
}

struct CurriculumSpellingWord: Equatable {
    let word: KanaSpellingWord
    let requiredGlyphs: Set<String>
    /// Prefer this word once the learner has at least this many glyphs unlocked.
    let minimumUnlockedGlyphCount: Int
}

enum KanaSpellingDifficulty {
    case easy
    case medium
    case hard

    var characterBankSize: Int {
        switch self {
        case .easy: 8
        case .medium: 12
        case .hard: 16
        }
    }

    static func forSyllableCount(_ count: Int) -> KanaSpellingDifficulty {
        switch count {
        case ...3: .easy
        case 4: .medium
        default: .hard
        }
    }
}

enum KanaSpellingWordBank {
    static let successAudioByHiragana: [String: String] = [
        "ありがとう": "arigatou-EL",
        "こんにちは": "konnichiwa-EL",
        "たべる": "taberu-EL",
    ]

    static let words: [KanaSpellingWord] = curriculumWords.map(\.word)

    static let curriculumWords: [CurriculumSpellingWord] = [
        entry("あい", romaji: "ai", meaning: "love", minUnlock: 2),
        entry("うえ", romaji: "ue", meaning: "above; up", minUnlock: 3),
        entry("いえ", romaji: "ie", meaning: "house; home", minUnlock: 5),
        entry("あお", romaji: "ao", meaning: "blue", minUnlock: 5),
        entry("あめ", romaji: "ame", meaning: "rain", minUnlock: 5),
        entry("うみ", romaji: "umi", meaning: "sea", minUnlock: 5),
        entry("うし", romaji: "ushi", meaning: "cow", minUnlock: 6),
        entry("かお", romaji: "kao", meaning: "face", minUnlock: 6),
        entry("あさ", romaji: "asa", meaning: "morning", minUnlock: 8),
        entry("きく", romaji: "kiku", meaning: "to listen; chrysanthemum", minUnlock: 8),
        entry("ここ", romaji: "koko", meaning: "here", minUnlock: 10),
        entry("くも", romaji: "kumo", meaning: "cloud", minUnlock: 10),
        entry("かさ", romaji: "kasa", meaning: "umbrella", minUnlock: 12),
        entry("さけ", romaji: "sake", meaning: "salmon; alcohol", minUnlock: 12),
        entry("そら", romaji: "sora", meaning: "sky", minUnlock: 14),
        entry("すし", romaji: "sushi", meaning: "sushi", minUnlock: 14),
        entry("かみ", romaji: "kami", meaning: "paper; god", minUnlock: 14),
        entry("いぬ", romaji: "inu", meaning: "dog", minUnlock: 15),
        entry("たこ", romaji: "tako", meaning: "octopus", minUnlock: 16),
        entry("いち", romaji: "ichi", meaning: "one", minUnlock: 16),
        entry("くち", romaji: "kuchi", meaning: "mouth", minUnlock: 17),
        entry("つき", romaji: "tsuki", meaning: "moon", minUnlock: 17),
        entry("たべる", romaji: "taberu", meaning: "to eat", minUnlock: 18),
        entry("かわ", romaji: "kawa", meaning: "river", minUnlock: 18),
        entry("みず", romaji: "mizu", meaning: "water", minUnlock: 18),
        entry("さかな", romaji: "sakana", meaning: "fish", minUnlock: 20),
        entry("ねこ", romaji: "neko", meaning: "cat", minUnlock: 20),
        entry("め", romaji: "me", meaning: "eye", minUnlock: 22),
        entry("はな", romaji: "hana", meaning: "flower; nose", minUnlock: 22),
        entry("ほし", romaji: "hoshi", meaning: "star", minUnlock: 24),
        entry("みみ", romaji: "mimi", meaning: "ear", minUnlock: 24),
        entry("もり", romaji: "mori", meaning: "forest", minUnlock: 26),
        entry("やま", romaji: "yama", meaning: "mountain", minUnlock: 28),
        entry("ゆき", romaji: "yuki", meaning: "snow", minUnlock: 28),
        entry("よる", romaji: "yoru", meaning: "night", minUnlock: 28),
        entry("やさい", romaji: "yasai", meaning: "vegetable", minUnlock: 32),
        entry("おはよう", romaji: "ohayou", meaning: "good morning", minUnlock: 30),
        entry("ありがとう", romaji: "arigatou", meaning: "thank you", minUnlock: 35),
        entry("こんにちは", romaji: "konnichiwa", meaning: "hello; good afternoon", minUnlock: 40),
        entry("すみません", romaji: "sumimasen", meaning: "excuse me; sorry", minUnlock: 42),
    ]

    static let katakanaCurriculumWords: [CurriculumSpellingWord] = [
        katakanaEntry("アイ", romaji: "ai", meaning: "love", minUnlock: 2),
        katakanaEntry("ウエ", romaji: "ue", meaning: "above; up", minUnlock: 3),
        katakanaEntry("イエ", romaji: "ie", meaning: "house; home", minUnlock: 5),
        katakanaEntry("アオ", romaji: "ao", meaning: "blue", minUnlock: 5),
        katakanaEntry("アメ", romaji: "ame", meaning: "rain; candy", minUnlock: 5),
        katakanaEntry("ウミ", romaji: "umi", meaning: "sea", minUnlock: 5),
        katakanaEntry("カオ", romaji: "kao", meaning: "face", minUnlock: 6),
        katakanaEntry("アサ", romaji: "asa", meaning: "morning", minUnlock: 8),
        katakanaEntry("ココ", romaji: "koko", meaning: "here", minUnlock: 10),
        katakanaEntry("クモ", romaji: "kumo", meaning: "cloud", minUnlock: 10),
        katakanaEntry("カサ", romaji: "kasa", meaning: "umbrella", minUnlock: 12),
        katakanaEntry("ソラ", romaji: "sora", meaning: "sky", minUnlock: 14),
        katakanaEntry("スシ", romaji: "sushi", meaning: "sushi", minUnlock: 14),
        katakanaEntry("イヌ", romaji: "inu", meaning: "dog", minUnlock: 15),
        katakanaEntry("タコ", romaji: "tako", meaning: "octopus", minUnlock: 16),
        katakanaEntry("イチ", romaji: "ichi", meaning: "one", minUnlock: 16),
        katakanaEntry("ツキ", romaji: "tsuki", meaning: "moon", minUnlock: 17),
        katakanaEntry("ミズ", romaji: "mizu", meaning: "water", minUnlock: 18),
        katakanaEntry("サカナ", romaji: "sakana", meaning: "fish", minUnlock: 20),
        katakanaEntry("ネコ", romaji: "neko", meaning: "cat", minUnlock: 20),
        katakanaEntry("メ", romaji: "me", meaning: "eye", minUnlock: 22),
        katakanaEntry("ハナ", romaji: "hana", meaning: "flower; nose", minUnlock: 22),
        katakanaEntry("ホシ", romaji: "hoshi", meaning: "star", minUnlock: 24),
        katakanaEntry("ヤマ", romaji: "yama", meaning: "mountain", minUnlock: 28),
        katakanaEntry("ユキ", romaji: "yuki", meaning: "snow", minUnlock: 28),
        katakanaEntry("パン", romaji: "pan", meaning: "bread", minUnlock: 18),
        katakanaEntry("ペン", romaji: "pen", meaning: "pen", minUnlock: 20),
        katakanaEntry("メニュー", romaji: "menyuu", meaning: "menu", minUnlock: 22),
        katakanaEntry("コーヒー", romaji: "koohii", meaning: "coffee", minUnlock: 24),
        katakanaEntry("テレビ", romaji: "terebi", meaning: "TV", minUnlock: 26),
        katakanaEntry("ラジオ", romaji: "rajio", meaning: "radio", minUnlock: 28),
        katakanaEntry("ケーキ", romaji: "keeki", meaning: "cake", minUnlock: 30),
        katakanaEntry("タクシー", romaji: "takushii", meaning: "taxi", minUnlock: 32),
        katakanaEntry("ホテル", romaji: "hoteru", meaning: "hotel", minUnlock: 34),
        katakanaEntry("カメラ", romaji: "kamera", meaning: "camera", minUnlock: 36),
    ]

    private static func entry(
        _ hiragana: String,
        romaji: String,
        meaning: String,
        minUnlock: Int
    ) -> CurriculumSpellingWord {
        CurriculumSpellingWord(
            word: KanaSpellingWord(hiragana: hiragana, romaji: romaji, meaning: meaning),
            requiredGlyphs: Set(HiraganaRomaji.syllables(in: hiragana, script: .hiragana)),
            minimumUnlockedGlyphCount: minUnlock
        )
    }

    private static func katakanaEntry(
        _ katakana: String,
        romaji: String,
        meaning: String,
        minUnlock: Int
    ) -> CurriculumSpellingWord {
        let syllables = HiraganaRomaji.syllables(in: katakana, script: .katakana)
            .filter { $0 != "ー" }
        return CurriculumSpellingWord(
            word: KanaSpellingWord(hiragana: katakana, romaji: romaji, meaning: meaning),
            requiredGlyphs: Set(syllables),
            minimumUnlockedGlyphCount: minUnlock
        )
    }
}
