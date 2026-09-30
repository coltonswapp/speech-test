//
//  DialogueProgressStore.swift
//  shizen
//

import FirebaseFirestore
import Foundation

protocol LessonProgressProviding: AnyObject {
    var completedScenarioIDs: Set<String> { get }
    func completedCountToday() -> Int
}

struct DialogueDailyProgress: Codable, Equatable {
    var completedScenarioIDs: Set<String> = []
}

struct DialogueScenarioAttempt: Codable, Equatable {
    var id: String
    var at: Date
    var scenarioID: String
    var starCount: Int
    var points: Int
}

struct DialogueProgressSnapshot: Codable, Equatable {
    var completedScenarioIDs: Set<String>
    var dailyProgress: [String: DialogueDailyProgress]
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
}

final class DialogueProgressStore: LessonProgressProviding {

    static let shared = DialogueProgressStore()

    static let didChange = Notification.Name("DialogueProgressStore.didChange")

    static let scenariosPerDay = DialogueProgressSquareStyle.scenariosPerDay

    private var snapshot = DialogueProgressSnapshot()
    /// Exact `scenarioAttempts` elements from the last server snapshot, so a reset can delete those runs.
    private var remoteAttemptPayloads: [[String: Any]] = []
    /// Ids cleared locally whose delete has not shown up on the server yet.
    /// Incoming snapshots union remote into local, which would restore a stale copy.
    private var pendingRemovalIDs: Set<String> = []
    private let connection: LearnerProgressConnection

    init() {
        let callbacks = LearnerProgressCallbacks()
        connection = LearnerProgressConnection(
            documentID: LearnerFirestore.progressDialogue,
            shell: Self.emptyShell(),
            onSnapshot: { callbacks.onSnapshot?($0) },
            onSignedOut: { callbacks.onSignedOut?() }
        )
        callbacks.onSnapshot = { [weak self] snapshot in
            self?.apply(snapshot)
        }
        callbacks.onSignedOut = { [weak self] in
            self?.pendingRemovalIDs.removeAll()
            self?.remoteAttemptPayloads = []
            self?.replace(with: DialogueProgressSnapshot(), notify: true)
        }
        connection.start()
    }

    /// Day keys for new completions use the profile timezone. Stored keys are left as written.
    var progressCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        let identifier = UserProfileStore.shared.profile?.timezone ?? TimeZone.current.identifier
        calendar.timeZone = TimeZone(identifier: identifier) ?? .current
        return calendar
    }

    func reload() {}

    var completedScenarioIDs: Set<String> { snapshot.completedScenarioIDs }

    func isCompleted(scenarioID: String) -> Bool {
        snapshot.completedScenarioIDs.contains(scenarioID)
    }

    func isCompletedToday(scenarioID: String, date: Date = Date()) -> Bool {
        let key = Self.dateKey(for: date, calendar: progressCalendar)
        return snapshot.dailyProgress[key]?.completedScenarioIDs.contains(scenarioID) == true
    }

    func completedCount(for dateKey: String) -> Int {
        snapshot.dailyProgress[dateKey]?.completedScenarioIDs.count ?? 0
    }

    func completedCountToday() -> Int {
        completedCountToday(date: Date())
    }

    func completedCountToday(date: Date) -> Int {
        completedCount(for: Self.dateKey(for: date, calendar: progressCalendar))
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

    func hasRecordedProgress(scenarioID: String) -> Bool {
        if isCompleted(scenarioID: scenarioID) { return true }
        if !attempts(scenarioID: scenarioID).isEmpty { return true }
        return snapshot.dailyProgress.values.contains { $0.completedScenarioIDs.contains(scenarioID) }
    }

    /// Clears completion, daily credit, and recorded runs for these scenes.
    func resetScenarios(_ scenarioIDs: Set<String>) {
        let ids = Set(scenarioIDs.filter { !$0.isEmpty })
        guard !ids.isEmpty else { return }
        let fields = removalFields(for: ids)
        pendingRemovalIDs.formUnion(ids)
        var next = snapshot
        strip(ids, from: &next)
        replace(with: next, notify: true)
        guard !fields.isEmpty else { return }
        connection.enqueue(fields)
    }

    func markCompleted(
        scenarioID: String,
        starCount: Int? = nil,
        points: Int? = nil,
        date: Date = Date(),
        countsTowardDaily: Bool = true
    ) {
        guard !scenarioID.isEmpty else { return }
        pendingRemovalIDs.remove(scenarioID)
        var fields: [String: Any] = [:]

        if !snapshot.completedScenarioIDs.contains(scenarioID) {
            snapshot.completedScenarioIDs.insert(scenarioID)
            fields["completedScenarioIDs"] = FieldValue.arrayUnion([scenarioID])
            fields["lastCompletedScenarioId"] = scenarioID
        }

        if countsTowardDaily {
            let key = Self.dateKey(for: date, calendar: progressCalendar)
            var daily = snapshot.dailyProgress[key] ?? DialogueDailyProgress()
            if !daily.completedScenarioIDs.contains(scenarioID) {
                daily.completedScenarioIDs.insert(scenarioID)
                snapshot.dailyProgress[key] = daily
                fields["dailyProgress.\(key)"] = FieldValue.arrayUnion([scenarioID])
                fields["lastDayKey"] = key
                fields["lastDayScenarioId"] = scenarioID
            }
        }

        if let starCount {
            let attempt = DialogueScenarioAttempt(
                id: UUID().uuidString,
                at: date,
                scenarioID: scenarioID,
                starCount: min(max(starCount, 0), DialogueScoreRules.maxStars),
                points: min(max(points ?? 0, 0), 100_000)
            )
            snapshot.scenarioAttempts[scenarioID, default: []].append(attempt)
            let payload = attemptPayload(attempt)
            fields["scenarioAttempts"] = FieldValue.arrayUnion([payload])
            fields["lastAttempt"] = payload
        }

        guard !fields.isEmpty else { return }
        connection.enqueue(fields)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    func currentStreak(
        scenariosPerDay: Int = scenariosPerDay,
        date: Date = Date()
    ) -> Int {
        let calendar = progressCalendar
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
        replace(with: DialogueProgressSnapshot(), notify: true)
    }

    static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func apply(_ document: DocumentSnapshot?) {
        let data = document?.data()
        remoteAttemptPayloads = Self.attemptPayloads(from: data)
        let remote = decode(data)
        pendingRemovalIDs = pendingRemovalIDs.filter { remoteStillContains($0, remote) }
        var merged = DialogueProgressSnapshot()
        merged.completedScenarioIDs = remote.completedScenarioIDs.union(snapshot.completedScenarioIDs)
        merged.dailyProgress = mergedDaily(local: snapshot.dailyProgress, remote: remote.dailyProgress)
        merged.scenarioAttempts = mergedAttempts(local: snapshot.scenarioAttempts, remote: remote.scenarioAttempts)
        strip(pendingRemovalIDs, from: &merged)
        replace(with: merged, notify: true)
    }

    private func remoteStillContains(_ scenarioID: String, _ remote: DialogueProgressSnapshot) -> Bool {
        if remote.completedScenarioIDs.contains(scenarioID) { return true }
        if remote.scenarioAttempts[scenarioID]?.isEmpty == false { return true }
        return remote.dailyProgress.values.contains { $0.completedScenarioIDs.contains(scenarioID) }
    }

    private func strip(_ ids: Set<String>, from snapshot: inout DialogueProgressSnapshot) {
        guard !ids.isEmpty else { return }
        snapshot.completedScenarioIDs.subtract(ids)
        for key in snapshot.dailyProgress.keys {
            snapshot.dailyProgress[key]?.completedScenarioIDs.subtract(ids)
        }
        for id in ids {
            snapshot.scenarioAttempts[id] = nil
        }
    }

    private func removalFields(for ids: Set<String>) -> [String: Any] {
        guard !ids.isEmpty else { return [:] }
        var fields: [String: Any] = [
            "completedScenarioIDs": FieldValue.arrayRemove(Array(ids).sorted()),
        ]
        for (key, progress) in snapshot.dailyProgress {
            let matching = Array(progress.completedScenarioIDs.intersection(ids)).sorted()
            guard !matching.isEmpty else { continue }
            fields["dailyProgress.\(key)"] = FieldValue.arrayRemove(matching)
        }

        var attemptMaps = remoteAttemptPayloads.filter { map in
            guard let scenarioID = LearnerSnapshotValue.string(map["scenarioId"]) else { return false }
            return ids.contains(scenarioID)
        }
        let remoteAttemptIDs = Set(attemptMaps.compactMap { LearnerSnapshotValue.string($0["id"]) })
        for id in ids {
            for attempt in snapshot.scenarioAttempts[id] ?? [] where !remoteAttemptIDs.contains(attempt.id) {
                attemptMaps.append(attemptPayload(attempt))
            }
        }
        if !attemptMaps.isEmpty {
            fields["scenarioAttempts"] = FieldValue.arrayRemove(attemptMaps)
        }
        return fields
    }

    private static func attemptPayloads(from data: [String: Any]?) -> [[String: Any]] {
        guard let raw = data?["scenarioAttempts"] as? [Any] else { return [] }
        return raw.compactMap { $0 as? [String: Any] }
    }

    private func replace(with next: DialogueProgressSnapshot, notify: Bool) {
        guard next != snapshot else { return }
        snapshot = next
        guard notify else { return }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    private func mergedDaily(
        local: [String: DialogueDailyProgress],
        remote: [String: DialogueDailyProgress]
    ) -> [String: DialogueDailyProgress] {
        var merged = remote
        for (key, progress) in local {
            var day = merged[key] ?? DialogueDailyProgress()
            day.completedScenarioIDs.formUnion(progress.completedScenarioIDs)
            merged[key] = day
        }
        return merged
    }

    private func mergedAttempts(
        local: [String: [DialogueScenarioAttempt]],
        remote: [String: [DialogueScenarioAttempt]]
    ) -> [String: [DialogueScenarioAttempt]] {
        var byID: [String: DialogueScenarioAttempt] = [:]
        for attempt in remote.values.flatMap({ $0 }) + local.values.flatMap({ $0 }) {
            byID[attempt.id] = attempt
        }
        var grouped: [String: [DialogueScenarioAttempt]] = [:]
        for attempt in byID.values {
            grouped[attempt.scenarioID, default: []].append(attempt)
        }
        for key in grouped.keys {
            grouped[key]?.sort { $0.at < $1.at }
        }
        return grouped
    }

    private func decode(_ data: [String: Any]?) -> DialogueProgressSnapshot {
        guard let data else { return DialogueProgressSnapshot() }
        var attempts: [String: [DialogueScenarioAttempt]] = [:]
        for value in data["scenarioAttempts"] as? [Any] ?? [] {
            guard let map = value as? [String: Any],
                  let id = LearnerSnapshotValue.string(map["id"]),
                  let scenarioID = LearnerSnapshotValue.string(map["scenarioId"]),
                  let at = LearnerSnapshotValue.date(map["at"]),
                  let starCount = LearnerSnapshotValue.int(map["starCount"]),
                  let points = LearnerSnapshotValue.int(map["points"])
            else { continue }
            attempts[scenarioID, default: []].append(
                DialogueScenarioAttempt(
                    id: id,
                    at: at,
                    scenarioID: scenarioID,
                    starCount: starCount,
                    points: points
                )
            )
        }
        for key in attempts.keys {
            attempts[key]?.sort { $0.at < $1.at }
        }

        var daily: [String: DialogueDailyProgress] = [:]
        for (key, value) in LearnerSnapshotValue.map(data["dailyProgress"]) {
            daily[key] = DialogueDailyProgress(completedScenarioIDs: Set(LearnerSnapshotValue.stringList(value)))
        }

        return DialogueProgressSnapshot(
            completedScenarioIDs: Set(LearnerSnapshotValue.stringList(data["completedScenarioIDs"])),
            dailyProgress: daily,
            scenarioAttempts: attempts
        )
    }

    private func attemptPayload(_ attempt: DialogueScenarioAttempt) -> [String: Any] {
        [
            "id": attempt.id,
            "at": Timestamp(date: attempt.at),
            "scenarioId": attempt.scenarioID,
            "starCount": attempt.starCount,
            "points": attempt.points,
        ]
    }

    private static func emptyShell() -> [String: Any] {
        [
            "schemaVersion": 1,
            "updatedAt": FieldValue.serverTimestamp(),
            "completedScenarioIDs": [],
            "dailyProgress": [:],
            "scenarioAttempts": [],
            "lastCompletedScenarioId": NSNull(),
            "lastDayKey": NSNull(),
            "lastDayScenarioId": NSNull(),
            "lastAttempt": NSNull(),
        ]
    }
}
