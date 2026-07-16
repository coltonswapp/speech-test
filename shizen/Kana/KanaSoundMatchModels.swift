//
//  KanaSoundMatchModels.swift
//  shizen
//

import Foundation

enum KanaSoundMatchDirection {
    case kanaToRomaji
    case romajiToKana
}

struct KanaSoundMatchRound {
    let direction: KanaSoundMatchDirection
    let draggedText: String
    let correctChoice: String
    let choices: [String]
}

struct KanaDiscoveryRound {
    let glyph: KanaGlyph
    let correctChoice: String
    let choices: [String]
}

struct KanaListenIdentifyRound {
    let targetKana: String
    let correctChoice: String
    let choices: [String]
}

enum KanaSoundMatchMetrics {
    static let kanaCardSide: CGFloat = 88
    static let kanaCardDragScale: CGFloat = 1.12
    static let placedCardScale: CGFloat = 1

    static let successBounceHeight: CGFloat = 25
    static let successBounceAnticipationDrop: CGFloat = 6
    static let successBounceDuration: TimeInterval = 0.43
    /// Keyframe time (0–1) in the success bounce when the chime should fire — launch after anticipation.
    static let successChimeKeyTime: TimeInterval = 0.12
    /// Pause on the green match state after the bounce, before auto-advancing.
    static let successAdvancePause: TimeInterval = 0.4
    /// Expand hit area before highlighting a new destination.
    static let hoverEnterExpansion: CGFloat = 10
    /// Shrink hit area before clearing highlight on the current destination.
    static let hoverExitContraction: CGFloat = 14
    static let kanaCardCornerRadius = ExperimentCardStroke.kanaDragCornerRadius
}

enum KanaSoundMatchRoundBank {
    static let rounds: [KanaSoundMatchRound] = [
        KanaSoundMatchRound(
            direction: .kanaToRomaji,
            draggedText: "か",
            correctChoice: "ka",
            choices: ["wa", "ka", "ga", "sa"]
        ),
        KanaSoundMatchRound(
            direction: .kanaToRomaji,
            draggedText: "さ",
            correctChoice: "sa",
            choices: ["ta", "sa", "chi", "tsu"]
        ),
        KanaSoundMatchRound(
            direction: .kanaToRomaji,
            draggedText: "ね",
            correctChoice: "ne",
            choices: ["na", "ne", "no", "ni"]
        ),
        KanaSoundMatchRound(
            direction: .romajiToKana,
            draggedText: "ka",
            correctChoice: "か",
            choices: ["た", "さ", "ち", "か"]
        ),
        KanaSoundMatchRound(
            direction: .romajiToKana,
            draggedText: "sa",
            correctChoice: "さ",
            choices: ["た", "さ", "ち", "つ"]
        ),
        KanaSoundMatchRound(
            direction: .romajiToKana,
            draggedText: "ne",
            correctChoice: "ね",
            choices: ["な", "ね", "の", "に"]
        ),
    ]
}
