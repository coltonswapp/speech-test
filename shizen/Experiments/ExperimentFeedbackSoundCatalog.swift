//
//  ExperimentFeedbackSoundCatalog.swift
//  shizen
//
//  Single source of truth for which feedback sound plays in each exercise.
//  Edit note counts and assignments here as you tune the assets.
//

import Foundation

/// Bundled success chime in the asset catalog.
enum ExperimentSuccessChime: String, CaseIterable {
    case chime1 = "success_chime"
    case chime2 = "success_chime2"
    case chime3 = "success_chime3"
    case chime4 = "success_chime4"
    case chime5 = "success_chime5"

    var assetName: String { rawValue }

    /// Number of distinct notes in the chime — used to match spelling tile count.
    var noteCount: Int {
        switch self {
        case .chime1, .chime5: return 3
        case .chime2: return 2
        case .chime3, .chime4: return 4
        }
    }

    var displayName: String {
        "\(assetName) (\(noteCount) notes)"
    }
}

/// Exercise step that can play a success chime.
enum ExperimentFeedbackExercise: Hashable, CaseIterable {
    case kanaDiscovery
    case kanaListenIdentify
    case kanaSoundMatch
    case kanaSpelling
    case vocabSpeaking

    var title: String {
        switch self {
        case .kanaDiscovery: return "Kana discovery"
        case .kanaListenIdentify: return "Listen & identify"
        case .kanaSoundMatch: return "Kana sound match"
        case .kanaSpelling: return "Kana spelling"
        case .vocabSpeaking: return "Vocab speaking"
        }
    }
}

enum ExperimentFeedbackSoundCatalog {
    static let clickAsset = "click"
    /// UI click gain. The bundled clip is ~30 ms, so it needs more headroom than longer chimes
    /// to read as subtle rather than silent.
    static let clickVolume: Float = 0.5
    static let incorrectAsset = "incorrect_dong"
    static let lessonCompleteAsset = "lesson-complete"
    /// Lesson-complete trumpets on the summary screen (encouragement plays mid-lesson on streaks).
    static let lessonCompleteVolume: Float = 0.28

    // MARK: - Fixed exercise assignments

    /// Pick-one steps (discovery, listen) and drag-and-match.
    static let singleChoiceChime: ExperimentSuccessChime = .chime5

    static let discoveryChime: ExperimentSuccessChime = singleChoiceChime
    static let listenIdentifyChime: ExperimentSuccessChime = singleChoiceChime
    static let soundMatchChime: ExperimentSuccessChime = singleChoiceChime

    /// Speak the word correctly.
    static let vocabSpeakingChime: ExperimentSuccessChime = .chime5

    // MARK: - Spelling (syllable count → chime)

    /// Maps the number of kana tiles spelled to a chime whose note count matches when possible.
    static func spellingChime(syllableCount: Int) -> ExperimentSuccessChime {
        switch syllableCount {
        case 1: return .chime2
        case 2: return .chime2
        case 3: return .chime1
        case 4: return .chime3
        default: return .chime4
        }
    }

    /// Reference table for the debug screen.
    static let spellingSyllablePreviewCounts = [1, 2, 3, 4, 5]

    static func successChime(for exercise: ExperimentFeedbackExercise, spellingSyllableCount: Int? = nil) -> ExperimentSuccessChime {
        switch exercise {
        case .kanaDiscovery: return discoveryChime
        case .kanaListenIdentify: return listenIdentifyChime
        case .kanaSoundMatch: return soundMatchChime
        case .kanaSpelling:
            return spellingChime(syllableCount: spellingSyllableCount ?? 1)
        case .vocabSpeaking: return vocabSpeakingChime
        }
    }

    static func assignmentDescription(for exercise: ExperimentFeedbackExercise) -> String {
        switch exercise {
        case .kanaSpelling:
            return "Varies by tile count (see spelling table)"
        default:
            return successChime(for: exercise).displayName
        }
    }
}
