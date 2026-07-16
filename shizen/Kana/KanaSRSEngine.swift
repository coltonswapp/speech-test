//
//  KanaSRSEngine.swift
//  shizen
//
//  Simplified SM-2 scheduling for per-glyph kana reviews.
//

import Foundation

struct KanaGlyphMastery: Codable, Equatable {
    var easeFactor: Double
    var intervalDays: Int
    var repetitions: Int
    var practiceCorrectCount: Int
    var nextReviewDate: Date
    var lastReviewDate: Date?

    static func fresh(exposedAt: Date = Date()) -> KanaGlyphMastery {
        KanaGlyphMastery(
            easeFactor: 2.5,
            intervalDays: 0,
            repetitions: 0,
            practiceCorrectCount: 0,
            nextReviewDate: exposedAt,
            lastReviewDate: nil
        )
    }

    init(
        easeFactor: Double,
        intervalDays: Int,
        repetitions: Int,
        practiceCorrectCount: Int,
        nextReviewDate: Date,
        lastReviewDate: Date?
    ) {
        self.easeFactor = easeFactor
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.practiceCorrectCount = practiceCorrectCount
        self.nextReviewDate = nextReviewDate
        self.lastReviewDate = lastReviewDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        easeFactor = try container.decode(Double.self, forKey: .easeFactor)
        intervalDays = try container.decode(Int.self, forKey: .intervalDays)
        repetitions = try container.decode(Int.self, forKey: .repetitions)
        practiceCorrectCount = try container.decodeIfPresent(Int.self, forKey: .practiceCorrectCount) ?? 0
        nextReviewDate = try container.decode(Date.self, forKey: .nextReviewDate)
        lastReviewDate = try container.decodeIfPresent(Date.self, forKey: .lastReviewDate)
    }
}

enum KanaSRSEngine {

    private static let intervalLadder = [1, 3, 7, 14, 30, 60]

    static func recordExposure(_ mastery: inout KanaGlyphMastery, at date: Date = Date()) {
        if mastery.repetitions == 0, mastery.lastReviewDate == nil {
            mastery.nextReviewDate = date
        }
    }

    static func recordPracticeSuccess(_ mastery: inout KanaGlyphMastery) {
        mastery.practiceCorrectCount += 1
    }

    static func recordPracticeFailure(_ mastery: inout KanaGlyphMastery) {
        mastery.practiceCorrectCount = max(0, mastery.practiceCorrectCount - 1)
    }

    static func recordSuccess(_ mastery: inout KanaGlyphMastery, at date: Date = Date()) {
        mastery.practiceCorrectCount += 1
        mastery.repetitions += 1
        mastery.lastReviewDate = date

        if mastery.repetitions == 1 {
            mastery.intervalDays = intervalLadder[0]
        } else if mastery.repetitions - 2 < intervalLadder.count {
            mastery.intervalDays = intervalLadder[mastery.repetitions - 2]
        } else {
            mastery.intervalDays = max(
                mastery.intervalDays,
                Int((Double(mastery.intervalDays) * mastery.easeFactor).rounded())
            )
        }

        mastery.easeFactor = min(mastery.easeFactor + 0.05, 3.0)
        mastery.nextReviewDate = Calendar.current.date(
            byAdding: .day,
            value: max(mastery.intervalDays, 1),
            to: date
        ) ?? date.addingTimeInterval(86_400)
    }

    static func recordFailure(_ mastery: inout KanaGlyphMastery, at date: Date = Date()) {
        mastery.repetitions = 0
        mastery.intervalDays = 0
        mastery.easeFactor = max(mastery.easeFactor - 0.2, 1.3)
        mastery.lastReviewDate = date
        mastery.nextReviewDate = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
    }

    static func isDue(_ mastery: KanaGlyphMastery, at date: Date = Date()) -> Bool {
        mastery.nextReviewDate <= date
    }

    static func dueGlyphs(
        from mastery: [String: KanaGlyphMastery],
        at date: Date = Date()
    ) -> [String] {
        mastery
            .filter { isDue($0.value, at: date) && $0.value.repetitions > 0 }
            .sorted { $0.value.nextReviewDate < $1.value.nextReviewDate }
            .map(\.key)
    }
}
