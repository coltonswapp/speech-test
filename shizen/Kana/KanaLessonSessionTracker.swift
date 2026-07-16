//
//  KanaLessonSessionTracker.swift
//  shizen
//

import Foundation

struct KanaLessonSessionMetrics {
    let startedAt: Date
    var correctCount = 0
    var wrongCount = 0
    var currentStreak = 0
    var bestStreak = 0
    var livesRemaining = KanaLessonSessionMetrics.maxLives

    static let maxLives = 3

    var elapsed: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }

    var accuracy: Double? {
        let total = correctCount + wrongCount
        guard total > 0 else { return nil }
        return Double(correctCount) / Double(total)
    }

    func snapshot() -> KanaLessonSessionMetrics {
        var copy = self
        return copy
    }
}

enum KanaLessonEncouragementPolicy {
    /// Streak lengths that insert an encouragement screen (early + toward lesson end).
    static let streakMilestones = [5, 15]
    static let maxPerLesson = streakMilestones.count
}

final class KanaLessonSessionTracker {

    private(set) var metrics = KanaLessonSessionMetrics(startedAt: Date())
    private(set) var isActive = true
    private(set) var encouragementsPlayed = 0
    private(set) var shouldPlayEncouragement = false
    private(set) var pendingEncouragementStreak: Int?

    /// Returns `true` when the session should end because lives are exhausted.
    @discardableResult
    func recordAnswer(correct: Bool, encouragementEnabled: Bool = true) -> Bool {
        shouldPlayEncouragement = false
        guard isActive else { return false }

        if correct {
            metrics.correctCount += 1
            metrics.currentStreak += 1
            metrics.bestStreak = max(metrics.bestStreak, metrics.currentStreak)
            if encouragementEnabled {
                considerEncouragementForCurrentStreak()
            }
            return false
        }

        metrics.wrongCount += 1
        metrics.currentStreak = 0
        metrics.livesRemaining = max(0, metrics.livesRemaining - 1)

        if metrics.livesRemaining == 0 {
            isActive = false
            return true
        }
        return false
    }

    private func considerEncouragementForCurrentStreak() {
        guard KanaLessonEncouragementPolicy.streakMilestones.contains(metrics.currentStreak),
              encouragementsPlayed < KanaLessonEncouragementPolicy.maxPerLesson
        else { return }

        encouragementsPlayed += 1
        pendingEncouragementStreak = metrics.currentStreak
        shouldPlayEncouragement = true
    }

    func consumePendingEncouragementStreak() -> Int? {
        defer { pendingEncouragementStreak = nil }
        return pendingEncouragementStreak
    }

    func endSession() {
        isActive = false
    }
}
