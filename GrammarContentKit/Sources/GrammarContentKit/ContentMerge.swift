//
//  ContentMerge.swift
//  GrammarContentKit
//

import Foundation

public struct ContentMergeResult: Sendable {
    public let curriculum: GrammarCurriculumBundleFile
    public let updatedPointIDs: [String]
    public let addedPointIDs: [String]
    public let preservedPointCount: Int
    public let patchedExistingBundle: Bool

    public init(
        curriculum: GrammarCurriculumBundleFile,
        updatedPointIDs: [String],
        addedPointIDs: [String],
        preservedPointCount: Int,
        patchedExistingBundle: Bool
    ) {
        self.curriculum = curriculum
        self.updatedPointIDs = updatedPointIDs
        self.addedPointIDs = addedPointIDs
        self.preservedPointCount = preservedPointCount
        self.patchedExistingBundle = patchedExistingBundle
    }
}

public enum ContentMerge {

    public static func existingBundlePointCount(
        at outputURL: URL,
        fileManager: FileManager = .default
    ) -> Int? {
        guard fileManager.fileExists(atPath: outputURL.path),
              let data = try? Data(contentsOf: outputURL),
              let bundle = try? ContentStore.decoder().decode(GrammarCurriculumBundleFile.self, from: data)
        else {
            return nil
        }
        return bundle.points.count
    }

    @discardableResult
    public static func backupExistingFile(
        at outputURL: URL,
        to backupDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> URL? {
        guard fileManager.fileExists(atPath: outputURL.path) else { return nil }
        let data = try Data(contentsOf: outputURL)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let backupURL = backupDirectory.appendingPathComponent("n5.grammar.backup.json")
        try data.write(to: backupURL, options: .atomic)
        return backupURL
    }

    public static func loadExistingBundle(
        at outputURL: URL,
        fileManager: FileManager = .default
    ) throws -> GrammarCurriculumBundleFile? {
        guard fileManager.fileExists(atPath: outputURL.path) else { return nil }
        let data = try Data(contentsOf: outputURL)
        return try ContentStore.decoder().decode(GrammarCurriculumBundleFile.self, from: data)
    }

    public static func mergeApprovedPoints(
        from contentRoot: URL,
        to outputURL: URL,
        fileManager: FileManager = .default
    ) throws -> ContentMergeResult {
        let store = ContentStore(rootDirectory: contentRoot, fileManager: fileManager)
        let checkpointsFile = try store.loadCheckpoints()
        let allSummaries = try store.listSummaries()

        var approvedPoints: [GrammarPointRecord] = []
        for summary in allSummaries {
            let point = try store.loadPoint(id: summary.id)
            guard point.status == .approved else { continue }
            approvedPoints.append(point.shippingRecord())
        }

        approvedPoints.sort { $0.orderIndex < $1.orderIndex }

        let issues = ContentValidator.validateStagingForMerge(
            approvedPoints: approvedPoints,
            checkpoints: checkpointsFile.checkpoints
        )
        if !issues.isEmpty {
            let messages = issues.map(\.message).joined(separator: "\n")
            throw ContentStoreError.writeFailed("Merge validation failed:\n\(messages)")
        }

        let approvedIDs = Set(approvedPoints.map(\.id))
        let existingBundle = try loadExistingBundle(at: outputURL, fileManager: fileManager)

        let pointMerge = mergePointsByID(
            existing: existingBundle?.points ?? [],
            approved: approvedPoints.map(\.bundleRecord)
        )
        let mergedPointIDs = Set(pointMerge.points.map(\.id))
        let mergedCheckpoints = mergeCheckpointsByID(
            existing: existingBundle?.checkpoints,
            content: checkpointsFile.checkpoints,
            approvedPointIDs: approvedIDs,
            mergedPointIDs: mergedPointIDs
        )

        let curriculum = GrammarCurriculumBundleFile(
            formatVersion: GrammarCurriculumFile.currentFormatVersion,
            jlptLevel: checkpointsFile.jlptLevel,
            checkpoints: mergedCheckpoints,
            points: pointMerge.points
        )

        let data = try ContentStore.encoder().encode(curriculum)
        let parent = outputURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try data.write(to: outputURL, options: .atomic)

        return ContentMergeResult(
            curriculum: curriculum,
            updatedPointIDs: pointMerge.updatedPointIDs,
            addedPointIDs: pointMerge.addedPointIDs,
            preservedPointCount: pointMerge.preservedPointCount,
            patchedExistingBundle: existingBundle != nil
        )
    }

    static func mergePointsByID(
        existing: [GrammarPointBundleRecord],
        approved: [GrammarPointBundleRecord]
    ) -> (
        points: [GrammarPointBundleRecord],
        updatedPointIDs: [String],
        addedPointIDs: [String],
        preservedPointCount: Int
    ) {
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let existingIDs = Set(byID.keys)
        let approvedIDs = Set(approved.map(\.id))
        var updatedPointIDs: [String] = []
        var addedPointIDs: [String] = []

        for point in approved {
            if existingIDs.contains(point.id) {
                updatedPointIDs.append(point.id)
            } else {
                addedPointIDs.append(point.id)
            }
            byID[point.id] = point
        }

        let preservedPointCount = existing.filter { !approvedIDs.contains($0.id) }.count
        let points = byID.values.sorted {
            if $0.orderIndex == $1.orderIndex {
                return $0.id < $1.id
            }
            return $0.orderIndex < $1.orderIndex
        }

        return (points, updatedPointIDs, addedPointIDs, preservedPointCount)
    }

    static func mergeCheckpointsByID(
        existing: [GrammarCheckpointRecord]?,
        content: [GrammarCheckpointRecord],
        approvedPointIDs: Set<String>,
        mergedPointIDs: Set<String>
    ) -> [GrammarCheckpointRecord] {
        var byID = Dictionary(uniqueKeysWithValues: (existing ?? []).map { ($0.id, $0) })

        for contentCheckpoint in content {
            let existingCheckpoint = byID[contentCheckpoint.id]
            let existingPointIDs = existingCheckpoint?.pointIDs ?? []
            var mergedPointIDList = existingPointIDs.filter { mergedPointIDs.contains($0) }
            let mergedSet = Set(mergedPointIDList)

            for pointID in contentCheckpoint.pointIDs where approvedPointIDs.contains(pointID) {
                if !mergedSet.contains(pointID) {
                    mergedPointIDList.append(pointID)
                }
            }

            let touchesApproved = contentCheckpoint.pointIDs.contains { approvedPointIDs.contains($0) }
            if touchesApproved || existingCheckpoint == nil {
                byID[contentCheckpoint.id] = GrammarCheckpointRecord(
                    id: contentCheckpoint.id,
                    orderIndex: contentCheckpoint.orderIndex,
                    title: contentCheckpoint.title,
                    subtitle: contentCheckpoint.subtitle,
                    pointIDs: mergedPointIDList
                )
            } else if let existingCheckpoint {
                byID[contentCheckpoint.id] = GrammarCheckpointRecord(
                    id: existingCheckpoint.id,
                    orderIndex: existingCheckpoint.orderIndex,
                    title: existingCheckpoint.title,
                    subtitle: existingCheckpoint.subtitle,
                    pointIDs: mergedPointIDList
                )
            }
        }

        for checkpoint in existing ?? [] where byID[checkpoint.id] == nil {
            let pointIDs = checkpoint.pointIDs.filter { mergedPointIDs.contains($0) }
            guard !pointIDs.isEmpty else { continue }
            byID[checkpoint.id] = GrammarCheckpointRecord(
                id: checkpoint.id,
                orderIndex: checkpoint.orderIndex,
                title: checkpoint.title,
                subtitle: checkpoint.subtitle,
                pointIDs: pointIDs
            )
        }

        return byID.values.sorted {
            if $0.orderIndex == $1.orderIndex {
                return $0.id < $1.id
            }
            return $0.orderIndex < $1.orderIndex
        }
    }
}
