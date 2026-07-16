//
//  KanaLessonEncouragementExperimentViewController.swift
//  shizen
//
//  DEBUG: preview the mid-lesson streak break screen without running a full lesson.
//

import UIKit

enum KanaLessonEncouragementExperimentPreview {

    static let demoGlyphs: [(kana: String, romaji: String)] = [
        ("あ", "a"),
        ("い", "i"),
    ]

    static func makeStep(
        comboStreak: Int = 5,
        clipIndex: Int = 0,
        praisePhrase: String = "天才だ！"
    ) -> KanaLessonEncouragementStepViewController {
        KanaLessonEncouragementStepViewController(
            comboStreak: comboStreak,
            clipIndex: clipIndex,
            glyphs: demoGlyphs,
            praisePhrase: praisePhrase
        )
    }
}
