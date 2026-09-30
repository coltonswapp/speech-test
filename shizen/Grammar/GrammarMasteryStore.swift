//
//  GrammarMasteryStore.swift
//  shizen
//

import FirebaseFirestore
import Foundation

struct GrammarMasterySnapshot: Equatable {
    var records: [String: GrammarMasteryRecord] = [:]
}

final class GrammarMasteryStore {

    static let shared = GrammarMasteryStore()

    static let didChange = Notification.Name("GrammarMasteryStore.didChange")

    private var snapshot = GrammarMasterySnapshot()
    private let connection: LearnerProgressConnection
    private var pendingRecords: [String: GrammarMasteryRecord] = [:]

    init() {
        let callbacks = LearnerProgressCallbacks()
        connection = LearnerProgressConnection(
            documentID: LearnerFirestore.progressGrammar,
            shell: Self.emptyShell(),
            onSnapshot: { callbacks.onSnapshot?($0) },
            onSignedOut: { callbacks.onSignedOut?() }
        )
        callbacks.onSnapshot = { [weak self] snapshot in
            self?.apply(snapshot)
        }
        callbacks.onSignedOut = { [weak self] in
            self?.clearLocal()
        }
        connection.start()
    }

    func reload() {}

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
        store(record)
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
        store(record)
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
        store(record)
    }

    func resetAll() {
        clearLocal()
    }

    /// Legacy lesson completion hook — marks a pattern as known.
    func markKnown(grammarID: String) {
        var record = record(for: grammarID)
        record.masteryState = .known
        store(record)
    }

    private func store(_ record: GrammarMasteryRecord) {
        snapshot.records[record.grammarId] = record
        pendingRecords[record.grammarId] = record
        connection.enqueue([
            "lastGrammarId": record.grammarId,
            "records.\(record.grammarId)": payload(record),
        ])
        notify()
    }

    private func clearLocal() {
        pendingRecords.removeAll()
        guard !snapshot.records.isEmpty else { return }
        snapshot = GrammarMasterySnapshot()
        notify()
    }

    private func apply(_ document: DocumentSnapshot?) {
        if document == nil, !snapshot.records.isEmpty { return }
        var remote = decode(document?.data())
        for (grammarID, local) in pendingRecords {
            if let remoteRecord = remote[grammarID], sameProgress(remoteRecord, local) {
                pendingRecords[grammarID] = nil
                remote[grammarID] = remoteRecord
            } else {
                remote[grammarID] = local
            }
        }
        guard remote != snapshot.records else { return }
        snapshot.records = remote
        notify()
    }

    private func sameProgress(_ lhs: GrammarMasteryRecord, _ rhs: GrammarMasteryRecord) -> Bool {
        lhs.masteryState == rhs.masteryState
            && lhs.timesEncountered == rhs.timesEncountered
            && lhs.correctStreak == rhs.correctStreak
            && lhs.firstSeenScenarioId == rhs.firstSeenScenarioId
    }

    private func decode(_ data: [String: Any]?) -> [String: GrammarMasteryRecord] {
        guard let data else { return [:] }
        var records: [String: GrammarMasteryRecord] = [:]
        for (key, value) in LearnerSnapshotValue.map(data["records"]) {
            guard let record = record(from: value, grammarID: key) else { continue }
            records[key] = record
        }
        return records
    }

    private func record(from value: Any, grammarID: String) -> GrammarMasteryRecord? {
        let map = LearnerSnapshotValue.map(value)
        guard let stateRaw = LearnerSnapshotValue.string(map["masteryState"]),
              let state = GrammarMasteryState(rawValue: stateRaw),
              let timesEncountered = LearnerSnapshotValue.int(map["timesEncountered"]),
              let correctStreak = LearnerSnapshotValue.int(map["correctStreak"])
        else { return nil }
        let grammarId = LearnerSnapshotValue.string(map["grammarId"]) ?? grammarID
        return GrammarMasteryRecord(
            grammarId: grammarId,
            masteryState: state,
            timesEncountered: timesEncountered,
            firstSeenScenarioId: LearnerSnapshotValue.string(map["firstSeenScenarioId"]),
            lastPracticedAt: LearnerSnapshotValue.date(map["lastPracticedAt"]),
            correctStreak: correctStreak
        )
    }

    private func payload(_ record: GrammarMasteryRecord) -> [String: Any] {
        [
            "grammarId": record.grammarId,
            "masteryState": record.masteryState.rawValue,
            "timesEncountered": record.timesEncountered,
            "firstSeenScenarioId": record.firstSeenScenarioId ?? NSNull(),
            "lastPracticedAt": record.lastPracticedAt.map { Timestamp(date: $0) } ?? NSNull(),
            "correctStreak": record.correctStreak,
        ]
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    private static func emptyShell() -> [String: Any] {
        [
            "schemaVersion": 1,
            "updatedAt": FieldValue.serverTimestamp(),
            "records": [:],
            "lastGrammarId": NSNull(),
        ]
    }
}
