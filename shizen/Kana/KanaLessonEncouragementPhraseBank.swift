//
//  KanaLessonEncouragementPhraseBank.swift
//  shizen
//
//  Short praise lines for the yellow encouragement badge (random per screen).
//

import Foundation

enum KanaLessonEncouragementPhraseBank {

    /// Display text for the praise pill — keep lines short for layout.
    static let phrases: [String] = [
        "天才だ！",
        "すごい！",
        "やった！",
        "最高！",
        "ナイス！",
        "いいね！",
        "完璧！",
        "さすが！",
        "うまい！",
        "神！",
    ]

    static func randomPhrase() -> String {
        phrases.randomElement() ?? phrases[0]
    }
}
