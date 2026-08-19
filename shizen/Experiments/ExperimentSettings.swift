//
//  ExperimentSettings.swift
//  shizen
//
//  User-facing toggles for debug experiments.
//

import Foundation

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

enum ExperimentSettings {
    private static let soundsEnabledKey = "ExperimentSoundsEnabled"
    private static let sentenceScrubGlossOverlayEnabledKey = "ExperimentSentenceScrubGlossOverlayEnabled"
    private static let repeatAfterMeReplyLimitKey = "ExperimentRepeatAfterMeReplyLimit"
    private static let repeatAfterMeHarshModeKey = "ExperimentRepeatAfterMeHarshMode"

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
}
