//
//  GrammarMasteryStore.swift
//  shizen
//

import Foundation

struct GrammarMasterySnapshot: Codable, Equatable {
    var records: [String: GrammarMasteryRecord] = [:]

    private enum CodingKeys: String, CodingKey {
        case records
        case completedPointIDs
    }

    init(records: [String: GrammarMasteryRecord] = [:]) {
        self.records = records
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let records = try container.decodeIfPresent([String: GrammarMasteryRecord].self, forKey: .records) {
            self.records = records
            return
        }
        let legacyCompleted = try container.decodeIfPresent(Set<String>.self, forKey: .completedPointIDs) ?? []
        records = Dictionary(
            uniqueKeysWithValues: legacyCompleted.map { id in
                var record = GrammarMasteryRecord.fresh(grammarId: id)
                record.masteryState = .known
                return (id, record)
            }
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(records, forKey: .records)
    }
}

final class GrammarMasteryStore {

    static let shared = GrammarMasteryStore()

    private let fileURL: URL
    private var snapshot: GrammarMasterySnapshot

    init(
        fileManager: FileManager = .default,
        progressFileName: String = "grammar-mastery.json",
        legacyProgressFileName: String = "grammar-progress.json"
    ) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("shizen", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent(progressFileName)
        let legacyURL = dir.appendingPathComponent(legacyProgressFileName)

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(GrammarMasterySnapshot.self, from: data) {
            snapshot = decoded
        } else if let legacyData = try? Data(contentsOf: legacyURL),
                  let legacy = try? JSONDecoder().decode(LegacyGrammarProgressFile.self, from: legacyData) {
            snapshot = GrammarMasterySnapshot(
                records: Dictionary(
                    uniqueKeysWithValues: legacy.completedPointIDs.map { id in
                        var record = GrammarMasteryRecord.fresh(grammarId: id)
                        record.masteryState = .known
                        return (id, record)
                    }
                )
            )
            if let migrated = try? JSONEncoder().encode(snapshot) {
                try? migrated.write(to: fileURL, options: .atomic)
            }
        } else {
            snapshot = GrammarMasterySnapshot()
        }
    }

    func reload() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(GrammarMasterySnapshot.self, from: data)
        else { return }
        snapshot = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    func record(for grammarID: String) -> GrammarMasteryRecord {
        snapshot.records[grammarID] ?? .fresh(grammarId: grammarID)
    }

    func masteryState(for grammarID: String) -> GrammarMasteryState {
        record(for: grammarID).masteryState
    }

    var knownCount: Int {
        snapshot.records.values.filter { $0.masteryState == .known }.count
    }

    var seenCount: Int {
        snapshot.records.values.filter { $0.masteryState == .seen || $0.masteryState == .known }.count
    }

    func recordEncounter(grammarID: String, scenarioID: String?) {
        var record = self.record(for: grammarID)
        record.timesEncountered += 1
        if record.firstSeenScenarioId == nil {
            record.firstSeenScenarioId = scenarioID
        }
        if record.masteryState == .new {
            record.masteryState = .seen
        }
        snapshot.records[grammarID] = record
        persist()
    }

    func recordEncounter(grammarIDs: [String], scenarioID: String?) {
        for grammarID in Set(grammarIDs) {
            recordEncounter(grammarID: grammarID, scenarioID: scenarioID)
        }
    }

    func recordPracticeResult(grammarID: String, wasCorrect: Bool, at date: Date = Date()) {
        var record = self.record(for: grammarID)
        record.lastPracticedAt = date
        if wasCorrect {
            record.correctStreak += 1
            if record.correctStreak >= 2 {
                record.masteryState = .known
            } else if record.masteryState == .new {
                record.masteryState = .seen
            }
        } else {
            record.correctStreak = 0
        }
        snapshot.records[grammarID] = record
        persist()
    }

    func finalizePracticeSession(grammarID: String, correctCount: Int, totalCount: Int, at date: Date = Date()) {
        guard totalCount > 0 else { return }
        var record = self.record(for: grammarID)
        record.lastPracticedAt = date
        if correctCount >= 2, Double(correctCount) / Double(totalCount) >= 0.6 {
            record.masteryState = .known
        } else if record.masteryState == .new, correctCount > 0 {
            record.masteryState = .seen
        }
        snapshot.records[grammarID] = record
        persist()
    }

    func resetAll() {
        snapshot = GrammarMasterySnapshot()
        persist()
    }

    /// Legacy lesson completion hook — marks a pattern as known.
    func markKnown(grammarID: String) {
        var record = record(for: grammarID)
        record.masteryState = .known
        snapshot.records[grammarID] = record
        persist()
    }
}

/// Decodes the pre-mastery `grammar-progress.json` file for one-time migration.
private struct LegacyGrammarProgressFile: Codable, Equatable {
    var completedPointIDs: Set<String> = []
}
