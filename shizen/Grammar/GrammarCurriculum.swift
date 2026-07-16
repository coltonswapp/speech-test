//
//  GrammarCurriculum.swift
//  shizen
//

import Foundation
import GrammarContentKit

enum GrammarCurriculum {

    private static let resourceName = "n5.grammar"

    private static let loaded: GrammarCurriculumBundleFile? = {
        guard let url = bundleJSONURL() else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GrammarCurriculumBundleFile.self, from: data)
    }()

    /// Xcode folder-sync layouts vary; try known paths, then scan the bundle.
    private static func bundleJSONURL() -> URL? {
        let subdirectories = [
            "Grammar",
            "Resources/Grammar",
            "shizen/Grammar",
            "shizen/Resources/Grammar",
        ]
        for subdirectory in subdirectories {
            if let url = Bundle.main.url(
                forResource: resourceName,
                withExtension: "json",
                subdirectory: subdirectory
            ) {
                return url
            }
        }
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "json") {
            return url
        }
        return findResourceInBundle(named: "\(resourceName).json")
    }

    private static func findResourceInBundle(named filename: String) -> URL? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        let root = URL(fileURLWithPath: resourcePath)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return nil }
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == filename {
                return fileURL
            }
        }
        return nil
    }

    static var jlptLevel: Int { loaded?.jlptLevel ?? 5 }

    static var n5Points: [GrammarPoint] {
        guard let file = loaded else { return [] }
        return file.points
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { GrammarPoint(bundle: $0, jlptLevel: file.jlptLevel) }
            .filter { !$0.examples.isEmpty }
    }

    static var n5Checkpoints: [GrammarCheckpoint] {
        guard let file = loaded else { return [] }
        let records = file.checkpoints ?? []
        return records
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { GrammarCheckpoint(record: $0, jlptLevel: file.jlptLevel) }
    }

    static func checkpoint(id: String) -> GrammarCheckpoint? {
        n5Checkpoints.first { $0.id == id }
    }

    static func points(for checkpoint: GrammarCheckpoint) -> [GrammarPoint] {
        checkpoint.points(from: n5Points)
    }

    static func point(id: String) -> GrammarPoint? {
        n5Points.first { $0.id == id }
    }

    static func point(at orderIndex: Int) -> GrammarPoint? {
        n5Points.first { $0.orderIndex == orderIndex }
    }

    #if DEBUG
    static func validateCurriculum() -> [String] {
        var errors: [String] = []
        let points = n5Points
        let checkpoints = n5Checkpoints
        let pointIDs = Set(points.map(\.id))

        if checkpoints.isEmpty {
            errors.append("No checkpoints defined")
            return errors
        }

        var assignedPointIDs: [String] = []
        var checkpointIndices: [Int] = []
        var checkpointIDs: Set<String> = []

        for checkpoint in checkpoints {
            if checkpointIDs.contains(checkpoint.id) {
                errors.append("Duplicate checkpoint id: \(checkpoint.id)")
            }
            checkpointIDs.insert(checkpoint.id)
            checkpointIndices.append(checkpoint.orderIndex)

            if checkpoint.pointIDs.isEmpty {
                errors.append("\(checkpoint.id): needs at least one point")
            }

            for pointID in checkpoint.pointIDs {
                if !pointIDs.contains(pointID) {
                    errors.append("\(checkpoint.id): unknown point \(pointID)")
                }
                assignedPointIDs.append(pointID)
            }
        }

        if checkpointIndices != checkpointIndices.sorted() {
            errors.append("Checkpoint orderIndex values are not sorted")
        }
        if Set(checkpointIndices).count != checkpointIndices.count {
            errors.append("Duplicate checkpoint orderIndex values")
        }

        let assignmentCounts = Dictionary(assignedPointIDs.map { ($0, 1) }, uniquingKeysWith: +)
        for (pointID, count) in assignmentCounts where count > 1 {
            errors.append("Point assigned to multiple checkpoints: \(pointID)")
        }

        for point in points where assignmentCounts[point.id] == nil {
            errors.append("Point not assigned to any checkpoint: \(point.id)")
        }

        return errors
    }
    #endif

}
