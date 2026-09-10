//
//  DialogueQuiz.swift
//  shizen
//
//  Optional comprehension quiz attached to a dialogue scenario.
//

import Foundation

struct DialogueQuizQuestion: Hashable {
    enum Layout: String, Hashable, Decodable {
        case grid
        case list
    }

    let prompt: String
    /// Featured Japanese word or phrase; shown with furigana when present.
    let target: String?
    let choices: [String]
    let correctChoice: String
    let wrongAnswerExplanation: String
    let layout: Layout
    /// Spoken-only start index into the scenario's published take (TTS index space).
    /// Stage / caption / inline-question rows are never valid targets.
    let sourceSpokenStart: Int?
    /// Inclusive spoken-only end index for a multi-line evidence range.
    let sourceSpokenEnd: Int?

    /// Inclusive spoken indices to play / show as dialogue evidence, if authored.
    var sourceSpokenIndices: [Int]? {
        guard let start = sourceSpokenStart, start >= 0 else { return nil }
        let end = max(start, sourceSpokenEnd ?? start)
        return Array(start...end)
    }
}

/// Mid-listen checkpoint authored as `type: "inline-question"` in `lines[]`.
struct DialogueInlineQuestion: Hashable {
    let prompt: String
    let target: String?
    let choices: [String]
    let correctChoice: String
    let wrongAnswerExplanation: String
    let layout: DialogueQuizQuestion.Layout

    var asQuizQuestion: DialogueQuizQuestion {
        DialogueQuizQuestion(
            prompt: prompt,
            target: target,
            choices: choices,
            correctChoice: correctChoice,
            wrongAnswerExplanation: wrongAnswerExplanation,
            layout: layout,
            sourceSpokenStart: nil,
            sourceSpokenEnd: nil
        )
    }
}

/// One spoken line shown as quiz evidence after an answer.
struct DialogueQuizSourceLine: Hashable {
    let speaker: String
    let japanese: String
    let english: String?
}

/// Audio + spoken catalog used to play / render quiz evidence without leaving the quiz page.
struct DialogueQuizEvidenceContext {
    let publishedAudioUrl: String?
    let audioKey: String?
    let cacheMetadata: RemoteAudioCacheMetadata?
    let spokenLines: [DialogueQuizSourceLine]

    var spokenJapaneseTexts: [String] {
        spokenLines.map(\.japanese)
    }

    func sourceLines(for question: DialogueQuizQuestion) -> [DialogueQuizSourceLine] {
        guard let indices = question.sourceSpokenIndices else { return [] }
        return indices.compactMap { index in
            guard spokenLines.indices.contains(index) else { return nil }
            return spokenLines[index]
        }
    }

    func clampedSpokenIndices(for question: DialogueQuizQuestion) -> [Int]? {
        guard let indices = question.sourceSpokenIndices, !indices.isEmpty else { return nil }
        let valid = indices.filter { spokenLines.indices.contains($0) }
        return valid.isEmpty ? nil : valid
    }
}
