//
//  ContentValidator.swift
//  GrammarContentKit
//

import Foundation

public struct ContentValidationIssue: Error, Sendable, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

public enum ContentValidator {

    public static func decodePoint(from data: Data) -> Result<GrammarPointRecord, ContentValidationIssue> {
        do {
            let point = try JSONDecoder().decode(GrammarPointRecord.self, from: data)
            return .success(point)
        } catch let error as DecodingError {
            return .failure(ContentValidationIssue("JSON decode failed: \(describe(error))"))
        } catch {
            return .failure(ContentValidationIssue("JSON decode failed: \(error.localizedDescription)"))
        }
    }

    /// Produces a human-readable description of a `DecodingError`, including the
    /// JSON key path so editors can pinpoint the offending field.
    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            let components = context.codingPath.map(\.stringValue)
            return components.isEmpty ? "(root)" : components.joined(separator: " → ")
        }

        switch error {
        case let .keyNotFound(key, context):
            return "Missing required field \"\(key.stringValue)\" at \(path(context))."
        case let .typeMismatch(type, context):
            return "Wrong type at \(path(context)): expected \(type). \(context.debugDescription)"
        case let .valueNotFound(type, context):
            return "Missing value at \(path(context)): expected \(type)."
        case let .dataCorrupted(context):
            if context.codingPath.isEmpty {
                return "Invalid JSON syntax (often a curly “smart” quote, trailing comma, or unescaped character). \(context.debugDescription)"
            }
            return "Malformed value at \(path(context)). \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    public static func decodePoint(from json: String) -> Result<GrammarPointRecord, ContentValidationIssue> {
        guard let data = json.data(using: .utf8) else {
            return .failure(ContentValidationIssue("Invalid UTF-8 text."))
        }
        return decodePoint(from: data)
    }

    public static func validatePoint(_ point: GrammarPointRecord) -> [ContentValidationIssue] {
        var issues: [ContentValidationIssue] = []

        if point.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(ContentValidationIssue("Point missing id"))
        }
        if point.resolvedPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(ContentValidationIssue("\(point.id): missing pattern/title"))
        }
        if point.resolvedShortDefinition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(ContentValidationIssue("\(point.id): missing shortDefinition/headlineEnglish"))
        }
        if point.examples.isEmpty {
            issues.append(ContentValidationIssue("\(point.id): needs at least one example"))
        }
        if point.examples.count > 10 {
            issues.append(ContentValidationIssue("\(point.id): too many examples (\(point.examples.count))"))
        }

        for (index, drill) in point.resolvedContrastDrills.enumerated() {
            if drill.correctChoice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(ContentValidationIssue("\(point.id): contrastDrill \(index) missing correctChoice"))
            }
            if !drill.choices.contains(drill.correctChoice) {
                issues.append(ContentValidationIssue("\(point.id): contrastDrill \(index) correctChoice not in choices"))
            }
        }

        for drill in point.drills where drill.kind != .contrastChoice {
            switch drill.kind {
            case .sentenceBuilder, .formChoice, .precursorChoice, .sentenceChoice, .meaningChoice:
                issues.append(ContentValidationIssue(
                    "\(point.id): deprecated drill kind \(drill.kind.rawValue) — remove before merge"
                ))
            case .contrastChoice:
                break
            }
        }

        return issues
    }

    public static func validateCurriculum(
        points: [GrammarPointRecord],
        checkpoints: [GrammarCheckpointRecord]
    ) -> [ContentValidationIssue] {
        var issues = validatePoints(points)

        if checkpoints.isEmpty {
            issues.append(ContentValidationIssue("No checkpoints defined"))
            return issues
        }

        let pointIDs = Set(points.map(\.id))
        var assignedPointIDs: [String] = []
        var checkpointIndices: [Int] = []
        var checkpointIDs: Set<String> = []

        for checkpoint in checkpoints {
            if checkpointIDs.contains(checkpoint.id) {
                issues.append(ContentValidationIssue("Duplicate checkpoint id: \(checkpoint.id)"))
            }
            checkpointIDs.insert(checkpoint.id)
            checkpointIndices.append(checkpoint.orderIndex)

            if checkpoint.pointIDs.isEmpty {
                issues.append(ContentValidationIssue("\(checkpoint.id): needs at least one point"))
            }

            for pointID in checkpoint.pointIDs where !pointIDs.contains(pointID) {
                issues.append(ContentValidationIssue("\(checkpoint.id): unknown point \(pointID)"))
            }
            assignedPointIDs.append(contentsOf: checkpoint.pointIDs)
        }

        if checkpointIndices != checkpointIndices.sorted() {
            issues.append(ContentValidationIssue("Checkpoint orderIndex values are not sorted"))
        }
        if Set(checkpointIndices).count != checkpointIndices.count {
            issues.append(ContentValidationIssue("Duplicate checkpoint orderIndex values"))
        }

        let assignmentCounts = Dictionary(assignedPointIDs.map { ($0, 1) }, uniquingKeysWith: +)
        for (pointID, count) in assignmentCounts where count > 1 {
            issues.append(ContentValidationIssue("Point assigned to multiple checkpoints: \(pointID)"))
        }

        for point in points where assignmentCounts[point.id] == nil {
            issues.append(ContentValidationIssue("Point not assigned to any checkpoint: \(point.id)"))
        }

        return issues
    }

    /// Validates an approved subset before merge. Does not require every checkpoint
    /// reference to be approved — only the staged points themselves.
    public static func validateStagingForMerge(
        approvedPoints: [GrammarPointRecord],
        checkpoints: [GrammarCheckpointRecord]
    ) -> [ContentValidationIssue] {
        var issues = validatePoints(approvedPoints)

        guard !checkpoints.isEmpty else {
            issues.append(ContentValidationIssue("No checkpoints defined"))
            return issues
        }

        let checkpointPointIDs = Set(checkpoints.flatMap(\.pointIDs))
        for point in approvedPoints where !checkpointPointIDs.contains(point.id) {
            issues.append(ContentValidationIssue("\(point.id) is not listed in checkpoints.json"))
        }

        let assignmentCounts = Dictionary(
            checkpoints.flatMap(\.pointIDs).map { ($0, 1) },
            uniquingKeysWith: +
        )
        for point in approvedPoints where (assignmentCounts[point.id] ?? 0) > 1 {
            issues.append(ContentValidationIssue("Point assigned to multiple checkpoints: \(point.id)"))
        }

        return issues
    }

    public static func checkpointsForApprovedPoints(
        _ checkpoints: [GrammarCheckpointRecord],
        approvedPointIDs: Set<String>
    ) -> [GrammarCheckpointRecord] {
        checkpoints.compactMap { checkpoint in
            let pointIDs = checkpoint.pointIDs.filter { approvedPointIDs.contains($0) }
            guard !pointIDs.isEmpty else { return nil }
            return GrammarCheckpointRecord(
                id: checkpoint.id,
                orderIndex: checkpoint.orderIndex,
                title: checkpoint.title,
                subtitle: checkpoint.subtitle,
                pointIDs: pointIDs
            )
        }
    }

    public static func validatePoints(_ points: [GrammarPointRecord]) -> [ContentValidationIssue] {
        var issues: [ContentValidationIssue] = []
        var ids: Set<String> = []
        var indices: [Int] = []

        for point in points {
            issues.append(contentsOf: validatePoint(point))

            if ids.contains(point.id) {
                issues.append(ContentValidationIssue("Duplicate id: \(point.id)"))
            }
            ids.insert(point.id)
            indices.append(point.orderIndex)
        }

        if indices != indices.sorted() {
            issues.append(ContentValidationIssue("orderIndex values are not sorted"))
        }
        if Set(indices).count != indices.count {
            issues.append(ContentValidationIssue("Duplicate orderIndex values"))
        }

        return issues
    }
}
