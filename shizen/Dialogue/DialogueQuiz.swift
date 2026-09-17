//
//  DialogueQuiz.swift
//  shizen
//
//  Optional comprehension quiz attached to a dialogue scenario.
//

import Foundation

struct DialogueQuizScore: Hashable {
    let correctCount: Int
    let questionCount: Int
}

enum DialogueScoreRules {
    static let pointsPerCorrectQuestion = 100
    static let pointsPerEnglishPeek = 15
    static let immersedBonus = 50
    static let maxStars = 3
}

enum DialogueLessonSessionMode: Equatable {
    case attempt
    case viewLesson
    case retakeQuiz
}

enum DialogueQuizSampler {
    static let maxQuestionCount = 6

    static func questions(
        from bank: [DialogueQuizQuestion],
        sample: Bool
    ) -> [DialogueQuizQuestion] {
        guard sample else { return bank }
        return Array(bank.shuffled().prefix(maxQuestionCount))
    }
}

struct DialogueCompletionTally: Hashable {
    struct Line: Hashable {
        enum Kind: Hashable {
            case credit
            case deduction
            case bonus
            case missed
        }

        let label: String
        let points: Int
        let kind: Kind
    }

    let score: DialogueQuizScore
    let englishPeekedCount: Int
    let awardsImmersedListen: Bool
    let lines: [Line]
    let total: Int

    var scoreSubtitle: String {
        Self.scoreSubtitle(for: score)
    }

    /// Clash-style grade: one star per objective, independent of question count.
    /// Always 1 for finishing, plus one for a clean quiz, plus one for no English peeks.
    var earnedAllCorrectStar: Bool {
        score.questionCount > 0 && score.correctCount == score.questionCount
    }

    var earnedImmersedStar: Bool {
        awardsImmersedListen && englishPeekedCount == 0
    }

    var starCount: Int {
        var stars = 1
        if earnedAllCorrectStar { stars += 1 }
        if earnedImmersedStar { stars += 1 }
        return min(DialogueScoreRules.maxStars, stars)
    }

    static func scoreSubtitle(for score: DialogueQuizScore) -> String {
        let totalQuestions = score.questionCount
        if totalQuestions == 1 {
            return score.correctCount == 1 ? "1 of 1 correct" : "0 of 1 correct"
        }
        return "\(score.correctCount) of \(totalQuestions) correct"
    }

    init(
        score: DialogueQuizScore,
        englishPeekedCount: Int,
        awardsImmersedListen: Bool = true
    ) {
        self.score = score
        self.englishPeekedCount = max(0, englishPeekedCount)
        self.awardsImmersedListen = awardsImmersedListen

        var lines: [Line] = []
        let quizPoints = score.correctCount * DialogueScoreRules.pointsPerCorrectQuestion
        lines.append(
            Line(label: "Quiz · \(Self.scoreSubtitle(for: score))", points: quizPoints, kind: .credit)
        )

        let missedCount = max(0, score.questionCount - score.correctCount)
        if missedCount > 0 {
            let missedLabel = missedCount == 1 ? "Missed · 1 question" : "Missed · \(missedCount) questions"
            lines.append(Line(label: missedLabel, points: 0, kind: .missed))
        }

        if awardsImmersedListen {
            if self.englishPeekedCount > 0 {
                let peekLabel = self.englishPeekedCount == 1
                    ? "English hints · 1 line"
                    : "English hints · \(self.englishPeekedCount) lines"
                lines.append(
                    Line(
                        label: peekLabel,
                        points: -(self.englishPeekedCount * DialogueScoreRules.pointsPerEnglishPeek),
                        kind: .deduction
                    )
                )
            } else {
                lines.append(
                    Line(
                        label: "Immersed listen",
                        points: DialogueScoreRules.immersedBonus,
                        kind: .bonus
                    )
                )
            }
        }

        self.lines = lines
        self.total = max(0, lines.reduce(0) { $0 + $1.points })
    }
}

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
    /// Spoken-only index into the scenario take (same space as `sourceSpokenStart`).
    let spokenIndex: Int
    /// Same leading/trailing assignment as the dialogue transcript.
    let speakerSide: DialogueSpeakerSide
}

/// Audio + spoken catalog used to play / render quiz evidence without leaving the quiz page.
struct DialogueQuizEvidenceContext {
    let publishedAudioUrl: String?
    let audioKey: String?
    let cacheMetadata: RemoteAudioCacheMetadata?
    let spokenLines: [DialogueQuizSourceLine]
    /// Validated against the spoken catalog; `nil` when the scenario has no sync.
    let tokenSync: DialogueTokenSync?

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
