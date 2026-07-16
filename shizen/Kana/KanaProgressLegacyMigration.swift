//
//  KanaProgressLegacyMigration.swift
//  shizen
//
//  Merges kana progress from legacy on-disk locations into the canonical store.
//  Progress lives in the app sandbox; changing the bundle ID creates a new container,
//  so we keep the original bundle identifier and consolidate files on first launch.
//

import Foundation

enum KanaProgressStorage {

    /// Shared container so progress survives bundle-ID / display-name changes when entitled.
    static let appGroupIdentifier = "group.com.Swappfunc.shizen"

    static let subdirectoryName = "KanaProgress"

    /// Pre–Shizen rebranding bundle id (same sandbox as earlier speech-test builds).
    static let legacyBundleIdentifier = "com.Swappfunc.speech-test"

    private static let migrationVersionKey = "KanaProgressStorage.migrationVersion"
    private static let completedMigrationVersion = 1

    static func primaryDirectory(fileManager: FileManager = .default) -> URL {
        if let groupDirectory = appGroupDirectory(fileManager: fileManager) {
            return groupDirectory
        }
        return applicationSupportDirectory(fileManager: fileManager)
    }

    static func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent(subdirectoryName, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func appGroupDirectory(fileManager: FileManager = .default) -> URL? {
        guard let base = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return nil
        }
        let directory = base.appendingPathComponent(subdirectoryName, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Every path that may still hold progress from an earlier install layout.
    static func candidateFileURLs(
        fileName: String,
        fileManager: FileManager = .default
    ) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()
        func append(_ url: URL) {
            let key = url.path
            guard seen.insert(key).inserted else { return }
            urls.append(url)
        }

        if let groupDirectory = appGroupDirectory(fileManager: fileManager) {
            append(groupDirectory.appendingPathComponent(fileName))
        }
        append(applicationSupportDirectory(fileManager: fileManager).appendingPathComponent(fileName))
        return urls
    }

    static func primaryFileURL(
        fileName: String,
        fileManager: FileManager = .default
    ) -> URL {
        primaryDirectory(fileManager: fileManager).appendingPathComponent(fileName)
    }

    static func migrationCompleted(fileManager: FileManager = .default) -> Bool {
        UserDefaults.standard.integer(forKey: migrationVersionKey) >= completedMigrationVersion
    }

    static func markMigrationCompleted() {
        UserDefaults.standard.set(completedMigrationVersion, forKey: migrationVersionKey)
    }
}

enum KanaProgressLegacyMigration {

    /// Loads every candidate file, merges into the richest snapshot, and writes the canonical copy.
    static func performIfNeeded(
        progressFileName: String,
        fileManager: FileManager = .default,
        load: (URL) -> KanaProgressSnapshot?,
        save: (KanaProgressSnapshot, URL) -> Void
    ) {
        guard !KanaProgressStorage.migrationCompleted(fileManager: fileManager) else { return }

        let candidates = KanaProgressStorage.candidateFileURLs(
            fileName: progressFileName,
            fileManager: fileManager
        )
        let snapshots = candidates.compactMap { load($0) }
        let anyFileExists = candidates.contains { fileManager.fileExists(atPath: $0.path) }

        var merged: KanaProgressSnapshot?
        for snapshot in snapshots {
            if let existing = merged {
                merged = merge(existing, snapshot)
            } else {
                merged = snapshot
            }
        }
        guard let merged else {
            if !anyFileExists {
                KanaProgressStorage.markMigrationCompleted()
            }
            return
        }

        let primaryURL = KanaProgressStorage.primaryFileURL(
            fileName: progressFileName,
            fileManager: fileManager
        )
        save(merged, primaryURL)
        KanaProgressStorage.markMigrationCompleted()
    }

    static func merge(
        _ lhs: KanaProgressSnapshot,
        _ rhs: KanaProgressSnapshot
    ) -> KanaProgressSnapshot {
        var merged = lhs
        merged.completedLessonRowIDs.formUnion(rhs.completedLessonRowIDs)
        merged.completedReviewRowIDs.formUnion(rhs.completedReviewRowIDs)
        if merged.lastOpenedRowID == nil {
            merged.lastOpenedRowID = rhs.lastOpenedRowID
        } else if rhs.lastOpenedRowID != nil,
                  richness(rhs) > richness(lhs) {
            merged.lastOpenedRowID = rhs.lastOpenedRowID
        }
        for (kana, mastery) in rhs.glyphMastery {
            if let existing = merged.glyphMastery[kana] {
                merged.glyphMastery[kana] = preferMastery(existing, mastery)
            } else {
                merged.glyphMastery[kana] = mastery
            }
        }
        return merged
    }

    private static func richness(_ snapshot: KanaProgressSnapshot) -> Int {
        snapshot.completedLessonRowIDs.count * 100
            + snapshot.completedReviewRowIDs.count * 50
            + snapshot.glyphMastery.values.reduce(0) { $0 + $1.practiceCorrectCount }
    }

    private static func preferMastery(
        _ lhs: KanaGlyphMastery,
        _ rhs: KanaGlyphMastery
    ) -> KanaGlyphMastery {
        if lhs.practiceCorrectCount != rhs.practiceCorrectCount {
            return lhs.practiceCorrectCount >= rhs.practiceCorrectCount ? lhs : rhs
        }
        if lhs.repetitions != rhs.repetitions {
            return lhs.repetitions >= rhs.repetitions ? lhs : rhs
        }
        let lhsReview = lhs.lastReviewDate ?? .distantPast
        let rhsReview = rhs.lastReviewDate ?? .distantPast
        return lhsReview >= rhsReview ? lhs : rhs
    }
}
