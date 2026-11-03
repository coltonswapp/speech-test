//
//  DialogueLessonAnalytics.swift
//  shizen
//
//  Funnel events for one dialogue scene visit: started → listened → quiz → completed, plus
//  highlights and an abandon report. The nested lesson controller calls `begin` per scene
//  and `end` when it leaves, and reports milestones in between; each fires at most once.
//

import Foundation

final class DialogueLessonAnalytics {
    enum Page {
        case dialogue, quiz, highlights
    }

    /// Where the lesson was opened from, e.g. "home" or "picker".
    var source = "unknown"

    private var scenarioID: String?
    private var collectionID: String?
    private var mode: DialogueLessonSessionMode = .attempt
    private var startedAt = Date()
    private var listened = false
    private var quizStarted = false
    private var highlightsViewed = false
    private var completed = false

    /// Starts a scene visit; reports the previous one as abandoned if it never finished.
    func begin(scenarioID: String, collectionID: String?, mode: DialogueLessonSessionMode) {
        end()
        self.scenarioID = scenarioID
        self.collectionID = collectionID
        self.mode = mode
        startedAt = Date()
        listened = false
        quizStarted = false
        highlightsViewed = false
        completed = false
        Analytics.track(.lessonStarted, baseProperties)
    }

    func dialogueListened(hardcore: Bool) {
        guard scenarioID != nil, !listened else { return }
        listened = true
        var properties = baseProperties
        properties["hardcore"] = hardcore
        properties["seconds"] = secondsElapsed
        Analytics.track(.dialogueListened, properties)
    }

    func pageShown(_ page: Page) {
        guard scenarioID != nil else { return }
        switch page {
        case .dialogue:
            return
        case .quiz:
            guard !quizStarted, mode != .viewLesson else { return }
            quizStarted = true
            Analytics.track(.quizStarted, baseProperties)
        case .highlights:
            guard !highlightsViewed else { return }
            highlightsViewed = true
            Analytics.track(.highlightsViewed, baseProperties)
        }
    }

    func quizCompleted(_ tally: DialogueCompletionTally) {
        guard scenarioID != nil else { return }
        var properties = baseProperties
        properties["correct_count"] = tally.score.correctCount
        properties["question_count"] = tally.score.questionCount
        properties["star_count"] = tally.starCount
        properties["points"] = tally.total
        properties["english_peeked_count"] = tally.englishPeekedCount
        properties["hardcore"] = tally.isHardcore
        properties["seconds"] = secondsElapsed
        Analytics.track(.quizCompleted, properties)
        if mode == .attempt {
            lessonCompleted(extra: properties)
        } else {
            completed = true
        }
    }

    /// Scenes without a quiz finish when the dialogue does.
    func completedWithoutQuiz() {
        guard scenarioID != nil else { return }
        lessonCompleted(extra: ["seconds": secondsElapsed])
    }

    /// Ends the visit; an unfinished attempt or retake reports `lesson_abandoned`.
    func end() {
        guard scenarioID != nil else { return }
        if !completed, mode != .viewLesson {
            var properties = baseProperties
            properties["furthest_stage"] = furthestStage
            properties["seconds"] = secondsElapsed
            Analytics.track(.lessonAbandoned, properties)
        }
        scenarioID = nil
    }

    private func lessonCompleted(extra: [String: Any]) {
        guard !completed else { return }
        completed = true
        Analytics.track(.lessonCompleted, baseProperties.merging(extra) { _, new in new })
    }

    private var furthestStage: String {
        if quizStarted { return "quiz" }
        if listened { return "listened" }
        return "dialogue"
    }

    private var secondsElapsed: Int {
        Int(Date().timeIntervalSince(startedAt).rounded())
    }

    private var baseProperties: [String: Any] {
        var properties: [String: Any] = [
            "lesson_type": "dialogue",
            "lesson_id": scenarioID ?? "",
            "session_mode": Self.name(of: mode),
            "source": source,
        ]
        properties["collection_id"] = collectionID
        return properties
    }

    private static func name(of mode: DialogueLessonSessionMode) -> String {
        switch mode {
        case .attempt: return "attempt"
        case .viewLesson: return "view_lesson"
        case .retakeQuiz: return "retake_quiz"
        }
    }
}
