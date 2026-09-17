//
//  DialogueProgressStore.swift
//  shizen
//

import Foundation

protocol LessonProgressProviding: AnyObject {
    var completedScenarioIDs: Set<String> { get }
    func completedCountToday() -> Int
}

struct DialogueDailyProgress: Codable, Equatable {
    var completedScenarioIDs: Set<String> = []
}

struct DialogueScenarioAttempt: Codable, Equatable {
    var starCount: Int
    var points: Int
}

struct DialogueProgressSnapshot: Codable, Equatable {
    var completedScenarioIDs: Set<String>
    var dailyProgress: [String: DialogueDailyProgress]
    /// Scored completions, keyed by scenario ID. Older files may only have star arrays.
    var scenarioAttempts: [String: [DialogueScenarioAttempt]]

    init(
        completedScenarioIDs: Set<String> = [],
        dailyProgress: [String: DialogueDailyProgress] = [:],
        scenarioAttempts: [String: [DialogueScenarioAttempt]] = [:]
    ) {
        self.completedScenarioIDs = completedScenarioIDs
        self.dailyProgress = dailyProgress
        self.scenarioAttempts = scenarioAttempts
    }

    enum CodingKeys: String, CodingKey {
        case completedScenarioIDs
        case dailyProgress
        case scenarioAttempts
        case scenarioStarCounts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        completedScenarioIDs = try container.decodeIfPresent(Set<String>.self, forKey: .completedScenarioIDs) ?? []
        dailyProgress = try container.decodeIfPresent([String: DialogueDailyProgress].self, forKey: .dailyProgress) ?? [:]
        if let attempts = try container.decodeIfPresent(
            [String: [DialogueScenarioAttempt]].self,
            forKey: .scenarioAttempts
        ) {
            scenarioAttempts = attempts
        } else if let starCounts = try container.decodeIfPresent(
            [String: [Int]].self,
            forKey: .scenarioStarCounts
        ) {
            scenarioAttempts = starCounts.mapValues { counts in
                counts.map { DialogueScenarioAttempt(starCount: $0, points: 0) }
            }
        } else {
            scenarioAttempts = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(completedScenarioIDs, forKey: .completedScenarioIDs)
        try container.encode(dailyProgress, forKey: .dailyProgress)
        try container.encode(scenarioAttempts, forKey: .scenarioAttempts)
    }
}

final class DialogueProgressStore: LessonProgressProviding {

    static let shared = DialogueProgressStore()

    static let didChange = Notification.Name("DialogueProgressStore.didChange")

    static let scenariosPerDay = DialogueProgressSquareStyle.scenariosPerDay

    private let calendar: Calendar
    private let fileURL: URL
    private var snapshot: DialogueProgressSnapshot

    init(
        fileManager: FileManager = .default,
        progressFileName: String = "dialogue-progress.json",
        calendar: Calendar = .current
    ) {
        self.calendar = calendar
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("shizen", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent(progressFileName)
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(DialogueProgressSnapshot.self, from: data) {
            snapshot = decoded
        } else {
            snapshot = DialogueProgressSnapshot()
        }
    }

    func reload() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(DialogueProgressSnapshot.self, from: data)
        else { return }
        snapshot = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    var completedScenarioIDs: Set<String> { snapshot.completedScenarioIDs }

    func isCompleted(scenarioID: String) -> Bool {
        snapshot.completedScenarioIDs.contains(scenarioID)
    }

    func isCompletedToday(scenarioID: String, date: Date = Date()) -> Bool {
        let key = Self.dateKey(for: date, calendar: calendar)
        return snapshot.dailyProgress[key]?.completedScenarioIDs.contains(scenarioID) == true
    }

    func completedCount(for dateKey: String) -> Int {
        snapshot.dailyProgress[dateKey]?.completedScenarioIDs.count ?? 0
    }

    func completedCountToday() -> Int {
        completedCountToday(date: Date())
    }

    func completedCountToday(date: Date) -> Int {
        completedCount(for: Self.dateKey(for: date, calendar: calendar))
    }

    func attempts(scenarioID: String) -> [DialogueScenarioAttempt] {
        snapshot.scenarioAttempts[scenarioID] ?? []
    }

    func bestStarCount(scenarioID: String) -> Int? {
        attempts(scenarioID: scenarioID).map(\.starCount).max()
    }

    func lastAttempt(scenarioID: String) -> DialogueScenarioAttempt? {
        attempts(scenarioID: scenarioID).last
    }

    func lastPoints(scenarioID: String) -> Int? {
        lastAttempt(scenarioID: scenarioID)?.points
    }

    /// Stars to render on the picker: best recorded run, or 1 for legacy completions.
    func displayedStarCount(scenarioID: String) -> Int {
        if let best = bestStarCount(scenarioID: scenarioID) { return best }
        return isCompleted(scenarioID: scenarioID) ? 1 : 0
    }

    func markCompleted(
        scenarioID: String,
        starCount: Int? = nil,
        points: Int? = nil,
        date: Date = Date(),
        countsTowardDaily: Bool = true
    ) {
        snapshot.completedScenarioIDs.insert(scenarioID)

        if countsTowardDaily {
            let key = Self.dateKey(for: date, calendar: calendar)
            var daily = snapshot.dailyProgress[key] ?? DialogueDailyProgress()
            daily.completedScenarioIDs.insert(scenarioID)
            snapshot.dailyProgress[key] = daily
        }

        if let starCount {
            let attempt = DialogueScenarioAttempt(
                starCount: min(max(starCount, 0), DialogueScoreRules.maxStars),
                points: max(points ?? 0, 0)
            )
            snapshot.scenarioAttempts[scenarioID, default: []].append(attempt)
        }

        persist()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    func currentStreak(
        scenariosPerDay: Int = scenariosPerDay,
        date: Date = Date()
    ) -> Int {
        var streak = 0
        var cursor = calendar.startOfDay(for: date)

        let todayKey = Self.dateKey(for: cursor, calendar: calendar)
        if completedCount(for: todayKey) < scenariosPerDay {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                return 0
            }
            cursor = yesterday
        }

        while completedCount(for: Self.dateKey(for: cursor, calendar: calendar)) >= scenariosPerDay {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return streak
    }

    func resetAll() {
        snapshot = DialogueProgressSnapshot()
        persist()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
