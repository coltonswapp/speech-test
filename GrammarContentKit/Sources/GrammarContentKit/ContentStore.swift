//
//  ContentStore.swift
//  GrammarContentKit
//

import Foundation

public struct GrammarPointSummary: Identifiable, Hashable, Sendable {
    public let id: String
    public let orderIndex: Int
    public let title: String
    public let headlineEnglish: String
    public let status: ContentStatus

    public init(record: GrammarPointRecord) {
        id = record.id
        orderIndex = record.orderIndex
        title = record.title
        headlineEnglish = record.headlineEnglish
        status = record.status
    }
}

public enum ContentStoreError: Error, LocalizedError {
    case invalidRoot
    case pointNotFound(String)
    case couldNotDecode(String)
    case couldNotEncode(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRoot: return "Content root directory is invalid."
        case .pointNotFound(let id): return "Point not found: \(id)"
        case .couldNotDecode(let id): return "Could not decode \(id).json"
        case .couldNotEncode(let id): return "Could not encode \(id).json"
        case .writeFailed(let message): return message
        }
    }
}

public final class ContentStore: @unchecked Sendable {

    public static let defaultRelativePath = "content/n5"

    public let rootDirectory: URL
    private let fileManager: FileManager

    public var pointsDirectory: URL {
        rootDirectory.appendingPathComponent("points", isDirectory: true)
    }

    public var checkpointsURL: URL {
        rootDirectory.appendingPathComponent("checkpoints.json")
    }

    public init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        JSONDecoder()
    }

    public func ensureDirectories() throws {
        try fileManager.createDirectory(at: pointsDirectory, withIntermediateDirectories: true)
    }

    public func pointURL(id: String) -> URL {
        pointsDirectory.appendingPathComponent("\(id).json")
    }

    public func listSummaries(status: ContentStatus? = nil) throws -> [GrammarPointSummary] {
        try ensureDirectories()
        guard fileManager.fileExists(atPath: pointsDirectory.path) else { return [] }

        let urls = try fileManager.contentsOfDirectory(
            at: pointsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var summaries: [GrammarPointSummary] = []
        for url in urls where url.pathExtension == "json" {
            guard let point = try? loadPoint(id: url.deletingPathExtension().lastPathComponent) else { continue }
            if let status, point.status != status { continue }
            summaries.append(GrammarPointSummary(record: point))
        }

        return summaries.sorted { $0.orderIndex < $1.orderIndex }
    }

    public func loadPoint(id: String) throws -> GrammarPointRecord {
        let url = pointURL(id: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw ContentStoreError.pointNotFound(id)
        }
        let data = try Data(contentsOf: url)
        do {
            return try Self.decoder().decode(GrammarPointRecord.self, from: data)
        } catch {
            throw ContentStoreError.couldNotDecode(id)
        }
    }

    public func savePoint(_ point: GrammarPointRecord) throws {
        try ensureDirectories()
        let url = pointURL(id: point.id)
        let data: Data
        do {
            data = try Self.encoder().encode(point)
        } catch {
            throw ContentStoreError.couldNotEncode(point.id)
        }
        try writeAtomically(data: data, to: url)
    }

    public func updateStatus(id: String, status: ContentStatus, reviewNotes: String?) throws -> GrammarPointRecord {
        var point = try loadPoint(id: id)
        point.status = status
        point.reviewNotes = reviewNotes
        try savePoint(point)
        return point
    }

    public func loadCheckpoints() throws -> GrammarCheckpointsFile {
        guard fileManager.fileExists(atPath: checkpointsURL.path) else {
            return GrammarCheckpointsFile(jlptLevel: 5, checkpoints: [])
        }
        let data = try Data(contentsOf: checkpointsURL)
        return try Self.decoder().decode(GrammarCheckpointsFile.self, from: data)
    }

    public func saveCheckpoints(_ file: GrammarCheckpointsFile) throws {
        try ensureDirectories()
        let data = try Self.encoder().encode(file)
        try writeAtomically(data: data, to: checkpointsURL)
    }

    public func approvedGoldExamples(limit: Int = 3) throws -> [GrammarPointRecord] {
        let approved = try listSummaries(status: .approved)
        return try approved.prefix(limit).map { try loadPoint(id: $0.id) }
    }

    private func writeAtomically(data: Data, to url: URL) throws {
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp")
        do {
            try data.write(to: tempURL, options: .atomic)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try fileManager.moveItem(at: tempURL, to: url)
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw ContentStoreError.writeFailed(error.localizedDescription)
        }
    }
}
