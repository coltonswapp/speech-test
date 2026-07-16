//
//  DialogueProgressStore.swift
//  shizen
//

import Foundation

struct DialogueDailyProgress: Codable, Equatable {
    var completedScenarioIDs: Set<String> = []
}

struct DialogueProgressSnapshot: Codable, Equatable {
    var completedScenarioIDs: Set<String>
    var dailyProgress: [String: DialogueDailyProgress]

    init(
        completedScenarioIDs: Set<String> = [],
        dailyProgress: [String: DialogueDailyProgress] = [:]
    ) {
        self.completedScenarioIDs = completedScenarioIDs
        self.dailyProgress = dailyProgress
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        completedScenarioIDs = try container.decodeIfPresent(Set<String>.self, forKey: .completedScenarioIDs) ?? []
        dailyProgress = try container.decodeIfPresent([String: DialogueDailyProgress].self, forKey: .dailyProgress) ?? [:]
    }
}

final class DialogueProgressStore {

    static let shared = DialogueProgressStore()

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

    func completedCountToday(date: Date = Date()) -> Int {
        completedCount(for: Self.dateKey(for: date, calendar: calendar))
    }

    func markCompleted(scenarioID: String, date: Date = Date()) {
        snapshot.completedScenarioIDs.insert(scenarioID)

        let key = Self.dateKey(for: date, calendar: calendar)
        var daily = snapshot.dailyProgress[key] ?? DialogueDailyProgress()
        daily.completedScenarioIDs.insert(scenarioID)
        snapshot.dailyProgress[key] = daily

        persist()
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
    }

    static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
