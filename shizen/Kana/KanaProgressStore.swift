//
//  KanaProgressStore.swift
//  shizen
//
//  Kana lesson progress, row unlock state, and SRS mastery for the signed-in user.
//

import FirebaseFirestore
import Foundation

enum KanaRowProgressState: Equatable, Hashable, Sendable {
    case locked
    case available
    case lessonCompleted
    case completed
}

struct KanaProgressSnapshot: Codable, Equatable {
    var glyphMastery: [String: KanaGlyphMastery]
    var completedLessonRowIDs: Set<String>
    var completedReviewRowIDs: Set<String>
    var lastOpenedRowID: String?

    static let empty = KanaProgressSnapshot(
        glyphMastery: [:],
        completedLessonRowIDs: [],
        completedReviewRowIDs: [],
        lastOpenedRowID: nil
    )
}

enum KanaStudyProgress {

    /// Successful recalls needed for full tile / chart-bar saturation.
    static let masteryCorrectCount = 15

    static func progressFraction(for correctCount: Int) -> CGFloat {
        guard correctCount > 0 else { return 0 }
        return min(1.0, CGFloat(min(correctCount, masteryCorrectCount)) / CGFloat(masteryCorrectCount))
    }
}

final class KanaProgressStore {

    /// Maximum rows with a completed lesson but no completed review before further rows stay locked.
    static let maxRowsAheadWithoutReview = 3

    static let shared = KanaProgressStore(
        documentID: LearnerFirestore.progressKanaHiragana,
        rows: KanaCurriculum.hiraganaSeionRows
    )

    static let katakanaShared = KanaProgressStore(
        documentID: LearnerFirestore.progressKanaKatakana,
        rows: KanaCurriculum.katakanaSeionRows
    )

    static let didChange = Notification.Name("KanaProgressStore.didChange")

    private(set) var snapshot: KanaProgressSnapshot

    private let rows: [KanaRow]
    private let connection: LearnerProgressConnection
    private var pendingGlyphs: [String: KanaGlyphMastery] = [:]
    private var pendingOpenedRowID: String?

    init(documentID: String, rows: [KanaRow]) {
        self.rows = rows
        snapshot = .empty
        let callbacks = LearnerProgressCallbacks()
        connection = LearnerProgressConnection(
            documentID: documentID,
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

    // MARK: - Row progress

    func rowState(_ row: KanaRow) -> KanaRowProgressState {
        if snapshot.completedReviewRowIDs.contains(row.id) {
            return .completed
        }
        if snapshot.completedLessonRowIDs.contains(row.id) {
            return .lessonCompleted
        }
        if isRowUnlocked(row) {
            return .available
        }
        return .locked
    }

    /// Rows whose lesson is done but row review is still pending.
    var pendingReviewRowCount: Int {
        snapshot.completedLessonRowIDs.subtracting(snapshot.completedReviewRowIDs).count
    }

    var isBlockedByReviewBacklog: Bool {
        pendingReviewRowCount >= Self.maxRowsAheadWithoutReview
    }

    func isRowUnlocked(_ row: KanaRow) -> Bool {
        if row.orderIndex == 0 { return true }
        guard let previous = rows.first(where: { $0.orderIndex == row.orderIndex - 1 }) else { return false }
        guard snapshot.completedLessonRowIDs.contains(previous.id) else { return false }
        return !isBlockedByReviewBacklog
    }

    /// True when the previous row's lesson is done but the review backlog prevents unlocking this row.
    func isRowBlockedByReviewBacklog(_ row: KanaRow) -> Bool {
        guard row.orderIndex > 0 else { return false }
        guard let previous = rows.first(where: { $0.orderIndex == row.orderIndex - 1 }) else { return false }
        return snapshot.completedLessonRowIDs.contains(previous.id) && isBlockedByReviewBacklog
    }

    func markLessonCompleted(for row: KanaRow) {
        let inserted = snapshot.completedLessonRowIDs.insert(row.id).inserted
        snapshot.lastOpenedRowID = row.id
        if inserted {
            pendingOpenedRowID = row.id
        }
        for glyph in row.glyphs {
            ensureMastery(for: glyph.kana)
            KanaSRSEngine.recordExposure(&snapshot.glyphMastery[glyph.kana]!)
        }
        if inserted {
            connection.enqueue([
                "completedLessonRowIDs": FieldValue.arrayUnion([row.id]),
                "lastLessonRowId": row.id,
                "lastOpenedRowID": row.id,
            ])
        }
        for glyph in row.glyphs {
            enqueueGlyph(glyph.kana)
        }
        notify()
    }

    func markReviewCompleted(for row: KanaRow) {
        let inserted = snapshot.completedReviewRowIDs.insert(row.id).inserted
        snapshot.lastOpenedRowID = row.id
        guard inserted else {
            notify()
            return
        }
        pendingOpenedRowID = row.id
        connection.enqueue([
            "completedReviewRowIDs": FieldValue.arrayUnion([row.id]),
            "lastReviewRowId": row.id,
            "lastOpenedRowID": row.id,
        ])
        notify()
    }

    /// Glyphs visible on the learning chart (lesson completed for their row).
    var unlockedGlyphs: Set<String> {
        Set(
            rows
                .filter { snapshot.completedLessonRowIDs.contains($0.id) }
                .flatMap(\.glyphs)
                .map(\.kana)
        )
    }

    /// Glyphs from rows whose review has passed — used for spelling word eligibility.
    var spellingEligibleGlyphs: Set<String> {
        Set(
            rows
                .filter { snapshot.completedReviewRowIDs.contains($0.id) }
                .flatMap(\.glyphs)
                .map(\.kana)
        )
    }

    var dueGlyphCount: Int {
        KanaSRSEngine.dueGlyphs(from: snapshot.glyphMastery).count
    }

    func dueGlyphs(at date: Date = Date()) -> [String] {
        KanaSRSEngine.dueGlyphs(from: snapshot.glyphMastery, at: date)
    }

    /// Whether the learner has been introduced to this glyph (discovery or prior lesson).
    func hasBeenIntroduced(to kana: String) -> Bool {
        snapshot.glyphMastery[kana] != nil
    }

    // MARK: - SRS

    func recordExposure(for kana: String) {
        ensureMastery(for: kana)
        KanaSRSEngine.recordExposure(&snapshot.glyphMastery[kana]!)
        enqueueGlyph(kana)
        notify()
    }

    func recordPracticeSuccess(for kana: String) {
        ensureMastery(for: kana)
        KanaSRSEngine.recordPracticeSuccess(&snapshot.glyphMastery[kana]!)
        enqueueGlyph(kana)
        notify()
    }

    func recordPracticeFailure(for kana: String) {
        ensureMastery(for: kana)
        KanaSRSEngine.recordPracticeFailure(&snapshot.glyphMastery[kana]!)
        enqueueGlyph(kana)
        notify()
    }

    func recordSuccess(for kana: String) {
        ensureMastery(for: kana)
        KanaSRSEngine.recordSuccess(&snapshot.glyphMastery[kana]!)
        enqueueGlyph(kana)
        notify()
    }

    func recordFailure(for kana: String) {
        ensureMastery(for: kana)
        KanaSRSEngine.recordFailure(&snapshot.glyphMastery[kana]!)
        enqueueGlyph(kana)
        notify()
    }

    /// Successful lesson, review, and SRS recalls tracked for tile/chart progress.
    func studyCount(for kana: String) -> Int {
        snapshot.glyphMastery[kana]?.practiceCorrectCount ?? 0
    }

    func inProgressGlyphCount(script: KanaScript) -> Int {
        let masteryThreshold = KanaStudyProgress.masteryCorrectCount
        return KanaCurriculum.allGlyphs(script: script).filter { glyph in
            let count = studyCount(for: glyph.kana)
            return count > 0 && count < masteryThreshold
        }.count
    }

    func masteredGlyphCount(script: KanaScript) -> Int {
        let masteryThreshold = KanaStudyProgress.masteryCorrectCount
        return KanaCurriculum.allGlyphs(script: script).filter { glyph in
            studyCount(for: glyph.kana) >= masteryThreshold
        }.count
    }

    func learnedGlyphCount(in rows: [KanaRow] = KanaCurriculum.hiraganaSeionRows) -> Int {
        unlockedGlyphs.intersection(Set(rows.flatMap(\.glyphs).map(\.kana))).count
    }

    func totalGlyphCount(in rows: [KanaRow] = KanaCurriculum.hiraganaSeionRows) -> Int {
        rows.flatMap(\.glyphs).count
    }

    private func ensureMastery(for kana: String) {
        if snapshot.glyphMastery[kana] == nil {
            snapshot.glyphMastery[kana] = .fresh()
        }
    }

    private func enqueueGlyph(_ kana: String) {
        guard let mastery = snapshot.glyphMastery[kana] else { return }
        pendingGlyphs[kana] = mastery
        connection.enqueue([
            "lastGlyph": kana,
            "glyphMastery.\(kana)": glyphPayload(mastery),
        ])
    }

    private func clearLocal() {
        pendingGlyphs.removeAll()
        pendingOpenedRowID = nil
        guard snapshot != .empty else { return }
        snapshot = .empty
        notify()
    }

    private func apply(_ document: DocumentSnapshot?) {
        if document == nil, snapshot != .empty { return }
        let remote = decode(document?.data())
        var next = remote
        next.completedLessonRowIDs.formUnion(snapshot.completedLessonRowIDs)
        next.completedReviewRowIDs.formUnion(snapshot.completedReviewRowIDs)

        var glyphs = remote.glyphMastery
        for (kana, local) in pendingGlyphs {
            if let remoteGlyph = remote.glyphMastery[kana], sameProgress(remoteGlyph, local) {
                pendingGlyphs[kana] = nil
                glyphs[kana] = remoteGlyph
            } else {
                glyphs[kana] = local
            }
        }
        next.glyphMastery = glyphs

        if let pendingOpenedRowID {
            if remote.lastOpenedRowID == pendingOpenedRowID {
                self.pendingOpenedRowID = nil
            } else {
                next.lastOpenedRowID = pendingOpenedRowID
            }
        }

        guard next != snapshot else { return }
        snapshot = next
        notify()
    }

    private func sameProgress(_ lhs: KanaGlyphMastery, _ rhs: KanaGlyphMastery) -> Bool {
        lhs.easeFactor == rhs.easeFactor
            && lhs.intervalDays == rhs.intervalDays
            && lhs.repetitions == rhs.repetitions
            && lhs.practiceCorrectCount == rhs.practiceCorrectCount
    }

    private func decode(_ data: [String: Any]?) -> KanaProgressSnapshot {
        guard let data else { return .empty }
        var glyphs: [String: KanaGlyphMastery] = [:]
        for (kana, value) in LearnerSnapshotValue.map(data["glyphMastery"]) {
            guard let mastery = glyph(from: value) else { continue }
            glyphs[kana] = mastery
        }
        return KanaProgressSnapshot(
            glyphMastery: glyphs,
            completedLessonRowIDs: Set(LearnerSnapshotValue.stringList(data["completedLessonRowIDs"])),
            completedReviewRowIDs: Set(LearnerSnapshotValue.stringList(data["completedReviewRowIDs"])),
            lastOpenedRowID: LearnerSnapshotValue.string(data["lastOpenedRowID"])
        )
    }

    private func glyph(from value: Any) -> KanaGlyphMastery? {
        let map = LearnerSnapshotValue.map(value)
        guard let easeFactor = LearnerSnapshotValue.double(map["easeFactor"]),
              let intervalDays = LearnerSnapshotValue.int(map["intervalDays"]),
              let repetitions = LearnerSnapshotValue.int(map["repetitions"]),
              let practiceCorrectCount = LearnerSnapshotValue.int(map["practiceCorrectCount"]),
              let nextReviewDate = LearnerSnapshotValue.date(map["nextReviewDate"])
        else { return nil }
        return KanaGlyphMastery(
            easeFactor: easeFactor,
            intervalDays: intervalDays,
            repetitions: repetitions,
            practiceCorrectCount: practiceCorrectCount,
            nextReviewDate: nextReviewDate,
            lastReviewDate: LearnerSnapshotValue.date(map["lastReviewDate"])
        )
    }

    private func glyphPayload(_ mastery: KanaGlyphMastery) -> [String: Any] {
        [
            "easeFactor": mastery.easeFactor,
            "intervalDays": mastery.intervalDays,
            "repetitions": mastery.repetitions,
            "practiceCorrectCount": mastery.practiceCorrectCount,
            "nextReviewDate": Timestamp(date: mastery.nextReviewDate),
            "lastReviewDate": mastery.lastReviewDate.map { Timestamp(date: $0) } ?? NSNull(),
        ]
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    private static func emptyShell() -> [String: Any] {
        [
            "schemaVersion": 1,
            "updatedAt": FieldValue.serverTimestamp(),
            "glyphMastery": [:],
            "completedLessonRowIDs": [],
            "completedReviewRowIDs": [],
            "lastOpenedRowID": NSNull(),
            "lastGlyph": NSNull(),
            "lastLessonRowId": NSNull(),
            "lastReviewRowId": NSNull(),
        ]
    }
}
