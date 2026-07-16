//
//  KanaProgressStore.swift
//  shizen
//
//  Persists kana lesson progress, row unlock state, and SRS mastery.
//

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

extension KanaProgressSnapshot {
    fileprivate static let currentFormatVersion = 2

    fileprivate struct FileEnvelope: Codable {
        var formatVersion: Int
        var snapshot: KanaProgressSnapshot
    }
}

final class KanaProgressStore {

    /// Maximum rows with a completed lesson but no completed review before further rows stay locked.
    static let maxRowsAheadWithoutReview = 3

    static let shared = KanaProgressStore()

    static let katakanaShared = KanaProgressStore(
        rows: KanaCurriculum.katakanaSeionRows,
        progressFileName: "progress-katakana.json"
    )

    private(set) var snapshot: KanaProgressSnapshot

    private let fileURL: URL
    private let fileManager: FileManager
    private let rows: [KanaRow]

    init(
        fileManager: FileManager = .default,
        rows: [KanaRow] = KanaCurriculum.hiraganaSeionRows,
        progressFileName: String = "progress.json"
    ) {
        self.fileManager = fileManager
        self.rows = rows

        KanaProgressLegacyMigration.performIfNeeded(
            progressFileName: progressFileName,
            fileManager: fileManager,
            load: Self.load(from:),
            save: { snapshot, url in Self.persist(snapshot, to: url) }
        )

        fileURL = KanaProgressStorage.primaryFileURL(
            fileName: progressFileName,
            fileManager: fileManager
        )
        snapshot = Self.load(from: fileURL) ?? .empty
    }

    func reload() {
        snapshot = Self.load(from: fileURL) ?? .empty
    }

    func save() {
        Self.persist(snapshot, to: fileURL)
    }

    private static func persist(_ snapshot: KanaProgressSnapshot, to url: URL) {
        let envelope = KanaProgressSnapshot.FileEnvelope(
            formatVersion: KanaProgressSnapshot.currentFormatVersion,
            snapshot: snapshot
        )
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? data.write(to: url, options: .atomic)
    }

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
        snapshot.completedLessonRowIDs.insert(row.id)
        snapshot.lastOpenedRowID = row.id
        for glyph in row.glyphs {
            ensureMastery(for: glyph.kana)
            KanaSRSEngine.recordExposure(&snapshot.glyphMastery[glyph.kana]!)
        }
        save()
    }

    func markReviewCompleted(for row: KanaRow) {
        snapshot.completedReviewRowIDs.insert(row.id)
        snapshot.lastOpenedRowID = row.id
        save()
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
        save()
    }

    func recordPracticeSuccess(for kana: String) {
        ensureMastery(for: kana)
        KanaSRSEngine.recordPracticeSuccess(&snapshot.glyphMastery[kana]!)
        save()
    }

    func recordPracticeFailure(for kana: String) {
        ensureMastery(for: kana)
        KanaSRSEngine.recordPracticeFailure(&snapshot.glyphMastery[kana]!)
        save()
    }

    func recordSuccess(for kana: String) {
        ensureMastery(for: kana)
        KanaSRSEngine.recordSuccess(&snapshot.glyphMastery[kana]!)
        save()
    }

    func recordFailure(for kana: String) {
        ensureMastery(for: kana)
        KanaSRSEngine.recordFailure(&snapshot.glyphMastery[kana]!)
        save()
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

    private static func load(from url: URL) -> KanaProgressSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let envelope = try? JSONDecoder().decode(KanaProgressSnapshot.FileEnvelope.self, from: data) {
            return envelope.snapshot
        }
        return try? JSONDecoder().decode(KanaProgressSnapshot.self, from: data)
    }
}
