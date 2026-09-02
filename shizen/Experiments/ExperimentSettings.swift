//
//  ExperimentSettings.swift
//  shizen
//
//  User-facing toggles for debug experiments.
//

import Foundation
import UIKit.UIColor

enum RepeatAfterMeReplyLimit: String, CaseIterable {
    case instant
    case threeTries

    var title: String {
        switch self {
        case .instant: return "Instant"
        case .threeTries: return "3 Tries"
        }
    }

    /// How many tutor replies to allow before the session ends.
    var responseCount: Int {
        switch self {
        case .instant: return 1
        case .threeTries: return 3
        }
    }
}

enum RolePlaySpeechRecognizerBackend: String, CaseIterable {
    case onDevice
    case gptRealtimeWhisper
    case compare

    var title: String {
        switch self {
        case .onDevice: return "On Device"
        case .gptRealtimeWhisper: return "GPT Whisper"
        case .compare: return "Compare Both"
        }
    }

    var symbolName: String {
        switch self {
        case .onDevice: return "iphone"
        case .gptRealtimeWhisper: return "cloud"
        case .compare: return "rectangle.split.2x1"
        }
    }

    var usesWhisper: Bool {
        self == .gptRealtimeWhisper || self == .compare
    }

    var usesOnDevice: Bool {
        self == .onDevice || self == .compare
    }
}

enum DialogueContentBubbleStyle: String, CaseIterable {
    case glass
    case messages

    var title: String {
        switch self {
        case .glass: return "Glass"
        case .messages: return "Messages"
        }
    }

    var subtitle: String? {
        switch self {
        case .glass: return nil
        case .messages: return "Blue and gray with tails"
        }
    }

    var symbolName: String {
        switch self {
        case .glass: return "rectangle.fill"
        case .messages: return "bubble.left.and.bubble.right.fill"
        }
    }
}

enum DialogueContentSecondPassRate: String, CaseIterable {
    case one
    case onePointTwoFive
    case onePointFive
    case two

    var value: Float {
        switch self {
        case .one: return 1
        case .onePointTwoFive: return 1.25
        case .onePointFive: return 1.5
        case .two: return 2
        }
    }

    var title: String {
        switch self {
        case .one: return "1×"
        case .onePointTwoFive: return "1.25×"
        case .onePointFive: return "1.5×"
        case .two: return "2×"
        }
    }

    var beatCaption: String {
        "\(title) playback"
    }
}

enum DialogueTokenSyncHighlightStyle: String, CaseIterable {
    case compact
    case full

    var title: String {
        switch self {
        case .compact: return "Underline"
        case .full: return "Full height"
        }
    }

    var subtitle: String {
        switch self {
        case .compact: return "Small marker on the baseline"
        case .full: return "Box behind the word"
        }
    }
}

enum ExperimentSettings {
    private static let soundsEnabledKey = "ExperimentSoundsEnabled"
    private static let sentenceScrubGlossOverlayEnabledKey = "ExperimentSentenceScrubGlossOverlayEnabled"
    private static let repeatAfterMeReplyLimitKey = "ExperimentRepeatAfterMeReplyLimit"
    private static let repeatAfterMeHarshModeKey = "ExperimentRepeatAfterMeHarshMode"
    private static let rolePlaySpeechRecognizerBackendKey = "ExperimentRolePlaySpeechRecognizerBackend"
    private static let dialogueContentBubbleStyleKey = "ExperimentDialogueContentBubbleStyle"
    private static let dialogueContentSecondPassRateKey = "ExperimentDialogueContentSecondPassRate"
    private static let dialogueContentShowsStageLinesKey = "ExperimentDialogueContentShowsStageLines"
    private static let dialogueShowsTokenSyncKey = "ExperimentDialogueShowsTokenSync"
    private static let dialogueTokenSyncHighlightStyleKey = "ExperimentDialogueTokenSyncHighlightStyle"
    private static let dialogueHighlightLeadingColorKey = "ExperimentDialogueHighlightLeadingColor"
    private static let dialogueHighlightTrailingColorKey = "ExperimentDialogueHighlightTrailingColor"

    /// Success chimes, selection clicks, and incorrect feedback in experiment flows.
    static var soundsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: soundsEnabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: soundsEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: soundsEnabledKey) }
    }

    /// Gloss callout shown while panning across the sentence scrub experiment.
    static var sentenceScrubGlossOverlayEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: sentenceScrubGlossOverlayEnabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: sentenceScrubGlossOverlayEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: sentenceScrubGlossOverlayEnabledKey) }
    }

    /// How many tutor replies before Repeat After Me ends the session.
    static var repeatAfterMeReplyLimit: RepeatAfterMeReplyLimit {
        get {
            guard let raw = UserDefaults.standard.string(forKey: repeatAfterMeReplyLimitKey),
                  let value = RepeatAfterMeReplyLimit(rawValue: raw)
            else { return .instant }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: repeatAfterMeReplyLimitKey) }
    }

    /// Rudely strict Repeat After Me tutor that underscores scores for comedy.
    static var repeatAfterMeHarshMode: Bool {
        get { UserDefaults.standard.bool(forKey: repeatAfterMeHarshModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: repeatAfterMeHarshModeKey) }
    }

    /// Role Play speech recognition: Apple on-device ASR or OpenAI gpt-realtime-whisper.
    static var rolePlaySpeechRecognizerBackend: RolePlaySpeechRecognizerBackend {
        get {
            guard let raw = UserDefaults.standard.string(forKey: rolePlaySpeechRecognizerBackendKey),
                  let value = RolePlaySpeechRecognizerBackend(rawValue: raw)
            else { return .onDevice }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: rolePlaySpeechRecognizerBackendKey) }
    }

    /// Dialogue Replay chrome: glass bubbles or Messages-style colored tails.
    static var dialogueContentBubbleStyle: DialogueContentBubbleStyle {
        get {
            guard let raw = UserDefaults.standard.string(forKey: dialogueContentBubbleStyleKey),
                  let value = DialogueContentBubbleStyle(rawValue: raw)
            else { return .glass }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: dialogueContentBubbleStyleKey) }
    }

    /// Two-pass Dialogue Replay: how fast the subtitled second listen plays.
    static var dialogueContentSecondPassRate: DialogueContentSecondPassRate {
        get {
            guard let raw = UserDefaults.standard.string(forKey: dialogueContentSecondPassRateKey),
                  let value = DialogueContentSecondPassRate(rawValue: raw)
            else { return .onePointTwoFive }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: dialogueContentSecondPassRateKey) }
    }

    /// Dialogue Replay: insert Content Studio stage directions between bubbles.
    static var dialogueContentShowsStageLines: Bool {
        get {
            if UserDefaults.standard.object(forKey: dialogueContentShowsStageLinesKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: dialogueContentShowsStageLinesKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: dialogueContentShowsStageLinesKey) }
    }

    /// Yellow marker behind the currently spoken token during dialogue playback.
    static var dialogueShowsTokenSync: Bool {
        get {
            if UserDefaults.standard.object(forKey: dialogueShowsTokenSyncKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: dialogueShowsTokenSyncKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: dialogueShowsTokenSyncKey) }
    }

    /// Full glyph-box highlight vs a small baseline marker.
    static var dialogueTokenSyncHighlightStyle: DialogueTokenSyncHighlightStyle {
        get {
            guard let raw = UserDefaults.standard.string(forKey: dialogueTokenSyncHighlightStyleKey),
                  let value = DialogueTokenSyncHighlightStyle(rawValue: raw)
            else { return .compact }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: dialogueTokenSyncHighlightStyleKey) }
    }

    /// Underglow / token karaoke color for the leading (left) speaker.
    static var dialogueHighlightLeadingColor: DialogueBubbleUnderglowColor {
        get {
            guard let raw = UserDefaults.standard.string(forKey: dialogueHighlightLeadingColorKey),
                  let value = DialogueBubbleUnderglowColor(storageKey: raw)
            else { return .blue }
            return value
        }
        set { UserDefaults.standard.set(newValue.storageKey, forKey: dialogueHighlightLeadingColorKey) }
    }

    /// Underglow / token karaoke color for the trailing (right) speaker.
    static var dialogueHighlightTrailingColor: DialogueBubbleUnderglowColor {
        get {
            guard let raw = UserDefaults.standard.string(forKey: dialogueHighlightTrailingColorKey),
                  let value = DialogueBubbleUnderglowColor(storageKey: raw)
            else { return .yellow }
            return value
        }
        set { UserDefaults.standard.set(newValue.storageKey, forKey: dialogueHighlightTrailingColorKey) }
    }

    static func dialogueHighlightColor(for side: DialogueSpeakerSide) -> DialogueBubbleUnderglowColor {
        switch side {
        case .leading: return dialogueHighlightLeadingColor
        case .trailing: return dialogueHighlightTrailingColor
        }
    }

    static func applyDialogueHighlightPreset(_ preset: DialogueHighlightColorPreset) {
        dialogueHighlightLeadingColor = preset.leading
        dialogueHighlightTrailingColor = preset.trailing
    }
}
