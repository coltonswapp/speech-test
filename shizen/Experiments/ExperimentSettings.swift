//
//  ExperimentSettings.swift
//  shizen
//
//  User-facing toggles for debug experiments.
//

import Foundation
import InteractionKit
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
        case .messages: return "Solid fills with tails"
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

/// How long playback waits on a stage direction before the next spoken line.
enum DialogueStageLinePause: String, CaseIterable {
    case auto
    case halfSecond
    case sevenTenths
    case oneSecond

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .halfSecond: return "0.5s"
        case .sevenTenths: return "0.7s"
        case .oneSecond: return "1.0s"
        }
    }

    var subtitle: String? {
        switch self {
        case .auto: return "Matches how long the line is"
        case .halfSecond, .sevenTenths, .oneSecond: return nil
        }
    }

    func duration(forStageLine text: String) -> TimeInterval {
        switch self {
        case .halfSecond: return 0.5
        case .sevenTenths: return 0.7
        case .oneSecond: return 1.0
        case .auto: return Self.autoDuration(for: text)
        }
    }

    /// Short captions stay near the 0.5s preset; longer ones stretch so they
    /// can be read, capped so a paragraph doesn't stall the dialogue.
    static func autoDuration(for text: String) -> TimeInterval {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0.5 }
        let duration = 0.4 + Double(trimmed.count) * 0.014
        return min(2.4, max(0.5, duration))
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
    private static let dialogueContentDelaysStageLinesKey = "ExperimentDialogueContentDelaysStageLines"
    private static let dialogueStageLinePauseKey = "ExperimentDialogueStageLinePause"
    private static let dialogueShowsTokenSyncKey = "ExperimentDialogueShowsTokenSync"
    private static let dialogueTokenSyncHighlightStyleKey = "ExperimentDialogueTokenSyncHighlightStyle"
    private static let dialogueHighlightLeadingColorKey = "ExperimentDialogueHighlightLeadingColor"
    private static let dialogueHighlightTrailingColorKey = "ExperimentDialogueHighlightTrailingColor"
    private static let dialogueMessageLeadingColorKey = "ExperimentDialogueMessageLeadingColor"
    private static let dialogueMessageTrailingColorKey = "ExperimentDialogueMessageTrailingColor"
    private static let kanjiSpotlightHighlightColorKey = "ExperimentKanjiSpotlightHighlightColor"
    private static let spanHighlightFillColorKey = "ExperimentSpanHighlightFillColor"
    private static let spanHighlightBandColorKey = "ExperimentSpanHighlightBandColor"
    private static let spanHighlightDarkTextKey = "ExperimentSpanHighlightDarkText"
    private static let spanHighlightBandHeightKey = "ExperimentSpanHighlightBandHeight"
    private static let spanHighlightCornerRadiusKey = "ExperimentSpanHighlightCornerRadius"
    private static let kanjiDecompositionFormatKey = "ExperimentKanjiDecompositionFormat"
    private static let explosionEmojisKey = "ExperimentExplosionEmojis"
    private static let llmServerUsageEnabledKey = "ExperimentLLMServerUsageEnabled"

    /// Palette shown in the explosion playground. Selected subset is persisted.
    static let explosionEmojiChoices = [
        "🎌", "🍱", "🍣", "🍙", "🍘", "🍥", "🍡", "🍜",
        "🍶", "🍵", "🥢", "⛩️", "🎎", "🎏", "🎐", "🧧",
        "👘", "🥋", "🀄", "⛄", "🍢", "🐉", "🐟", "🌸",
        "💮", "🗻", "🦊", "🐱", "⭐", "✨", "🎉", "🔥",
        "💯", "✅", "🎯", "💫", "🌟", "💪", "🫶", "🤩",
        "🌲", "🍀", "⚡",
    ]

    /// Loads `GET /v1/usage` and `/v1/usage/features` on the Gemini usage screen.
    /// Release builds always return false so product spend never ships.
    static var llmServerUsageEnabled: Bool {
        get {
            #if DEBUG
            if UserDefaults.standard.object(forKey: llmServerUsageEnabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: llmServerUsageEnabledKey)
            #else
            return false
            #endif
        }
        set { UserDefaults.standard.set(newValue, forKey: llmServerUsageEnabledKey) }
    }

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

    /// Dialogue Replay: hold 1.25s on each stage caption before the next spoken run.
    static var dialogueContentDelaysStageLines: Bool {
        get {
            if UserDefaults.standard.object(forKey: dialogueContentDelaysStageLinesKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: dialogueContentDelaysStageLinesKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: dialogueContentDelaysStageLinesKey) }
    }

    /// How long a dialogue waits on each stage direction.
    static var dialogueStageLinePause: DialogueStageLinePause {
        get {
            guard let raw = UserDefaults.standard.string(forKey: dialogueStageLinePauseKey),
                  let value = DialogueStageLinePause(rawValue: raw)
            else { return .auto }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: dialogueStageLinePauseKey) }
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

    /// Messages-style solid fill for the leading (left) speaker.
    static var dialogueMessageLeadingColor: DialogueBubbleUnderglowColor {
        get {
            guard let raw = UserDefaults.standard.string(forKey: dialogueMessageLeadingColorKey),
                  let value = DialogueBubbleUnderglowColor(storageKey: raw)
            else { return .gray }
            return value
        }
        set { UserDefaults.standard.set(newValue.storageKey, forKey: dialogueMessageLeadingColorKey) }
    }

    /// Messages-style solid fill for the trailing (right) speaker.
    static var dialogueMessageTrailingColor: DialogueBubbleUnderglowColor {
        get {
            guard let raw = UserDefaults.standard.string(forKey: dialogueMessageTrailingColorKey),
                  let value = DialogueBubbleUnderglowColor(storageKey: raw)
            else { return .blue }
            return value
        }
        set { UserDefaults.standard.set(newValue.storageKey, forKey: dialogueMessageTrailingColorKey) }
    }

    static func dialogueMessageColor(for side: DialogueSpeakerSide) -> DialogueBubbleUnderglowColor {
        switch side {
        case .leading: return dialogueMessageLeadingColor
        case .trailing: return dialogueMessageTrailingColor
        }
    }

    static func applyDialogueMessageColorPreset(_ preset: DialogueMessageColorPreset) {
        dialogueMessageLeadingColor = preset.leading
        dialogueMessageTrailingColor = preset.trailing
    }

    /// Full breakdown vs the 3-slide kanji decomposition cut.
    static var kanjiDecompositionFormat: KanjiDecompositionSlideshowFormat {
        get {
            guard let raw = UserDefaults.standard.string(forKey: kanjiDecompositionFormatKey),
                  let value = KanjiDecompositionSlideshowFormat(rawValue: raw)
            else { return .full }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: kanjiDecompositionFormatKey) }
    }

    /// Wash behind the subject kanji on Kanji Spotlight example slides.
    static var kanjiSpotlightHighlightColor: DialogueBubbleUnderglowColor {
        get {
            guard let raw = UserDefaults.standard.string(forKey: kanjiSpotlightHighlightColorKey),
                  let value = DialogueBubbleUnderglowColor(storageKey: raw)
            else { return .yellow }
            return value
        }
        set { UserDefaults.standard.set(newValue.storageKey, forKey: kanjiSpotlightHighlightColorKey) }
    }

    /// Background of the multi-word selection pill.
    static var spanHighlightFillColor: DialogueBubbleUnderglowColor {
        get {
            guard let raw = UserDefaults.standard.string(forKey: spanHighlightFillColorKey),
                  let value = DialogueBubbleUnderglowColor(storageKey: raw)
            else { return .blue }
            return value
        }
        set { UserDefaults.standard.set(newValue.storageKey, forKey: spanHighlightFillColorKey) }
    }

    /// Lower band on the multi-word selection pill.
    static var spanHighlightBandColor: DialogueBubbleUnderglowColor {
        get {
            guard let raw = UserDefaults.standard.string(forKey: spanHighlightBandColorKey),
                  let value = DialogueBubbleUnderglowColor(storageKey: raw)
            else { return .yellow }
            return value
        }
        set { UserDefaults.standard.set(newValue.storageKey, forKey: spanHighlightBandColorKey) }
    }

    /// Dark glyphs on a light fill. Otherwise the selection text is white.
    static var spanHighlightUsesDarkText: Bool {
        get { UserDefaults.standard.bool(forKey: spanHighlightDarkTextKey) }
        set { UserDefaults.standard.set(newValue, forKey: spanHighlightDarkTextKey) }
    }

    /// Fraction of the pill, from the bottom, covered by the secondary color.
    static var spanHighlightBandHeight: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: spanHighlightBandHeightKey)
            if stored == 0, UserDefaults.standard.object(forKey: spanHighlightBandHeightKey) == nil {
                return 0.15
            }
            return CGFloat(min(1, max(0.12, stored)))
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: spanHighlightBandHeightKey) }
    }

    static var spanHighlightCornerRadius: CGFloat {
        get {
            if UserDefaults.standard.object(forKey: spanHighlightCornerRadiusKey) == nil { return 2 }
            return CGFloat(min(16, max(0, UserDefaults.standard.double(forKey: spanHighlightCornerRadiusKey))))
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: spanHighlightCornerRadiusKey) }
    }

    static func applySpanHighlightStyle() {
        LyricsSpanHighlightStyle.current = LyricsSpanHighlightStyle(
            fillColor: spanHighlightFillColor.uiColor,
            bandColor: spanHighlightBandColor.uiColor,
            textColor: spanHighlightUsesDarkText ? .label : .white,
            bandHeightFraction: spanHighlightBandHeight,
            cornerRadius: spanHighlightCornerRadius
        )
    }

    static func resetSpanHighlightStyle() {
        let keys = [
            spanHighlightFillColorKey,
            spanHighlightBandColorKey,
            spanHighlightDarkTextKey,
            spanHighlightBandHeightKey,
            spanHighlightCornerRadiusKey,
        ]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        applySpanHighlightStyle()
    }

    /// Emojis currently in the NNKit explosion pool.
    static var explosionEmojis: [String] {
        get {
            let stored = UserDefaults.standard.stringArray(forKey: explosionEmojisKey) ?? []
            let allowed = stored.filter { explosionEmojiChoices.contains($0) }
            if !allowed.isEmpty { return allowed }
            return Array(explosionEmojiChoices.prefix(8))
        }
        set {
            let allowed = newValue.filter { explosionEmojiChoices.contains($0) }
            UserDefaults.standard.set(
                allowed.isEmpty ? Array(explosionEmojiChoices.prefix(8)) : allowed,
                forKey: explosionEmojisKey
            )
        }
    }
}
