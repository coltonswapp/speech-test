//
//  TutorConversationStore.swift
//  shizen
//
//  Persists realtime tutor transcripts as manifest.json bundles.
//

import Foundation

struct TutorConversationLine: Codable, Equatable {
    enum Speaker: String, Codable {
        case user
        case assistant
    }

    var speaker: Speaker
    var text: String
    var audioFilename: String?
}

struct TutorConversationManifest: Codable {
    static let currentFormatVersion = 2

    var formatVersion: Int
    var id: UUID
    var createdAt: Date
    var lines: [TutorConversationLine]
}

struct TutorConversationSaveLine {
    let speaker: TutorConversationLine.Speaker
    let text: String
    let audioClip: RealtimeAudioClip?
}

struct TutorConversationEntry: Equatable {
    let id: UUID
    let directoryURL: URL
    let createdAt: Date
    let preview: String
    let lineCount: Int
    let hasAudio: Bool
}

enum TutorConversationStoreError: Error, LocalizedError {
    case emptyConversation
    case couldNotReadManifest

    var errorDescription: String? {
        switch self {
        case .emptyConversation:
            return "Nothing to save yet."
        case .couldNotReadManifest:
            return "Could not read the saved conversation."
        }
    }
}

final class TutorConversationStore {

    static let shared = TutorConversationStore()

    private let rootDirectory: URL
    private let fileManager: FileManager

    private static let manifestFilename = "manifest.json"
    private static let audioDirectoryName = "audio"
    private static let maxConversationsWithAudio = 3

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootDirectory = appSupport.appendingPathComponent("TutorConversations", isDirectory: true)
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    func listEntries() throws -> [TutorConversationEntry] {
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return [] }

        let urls = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )

        return try urls.compactMap { url -> TutorConversationEntry? in
            let manifestURL = url.appendingPathComponent(Self.manifestFilename)
            guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }
            let manifest = try decodeManifest(at: manifestURL)
            return TutorConversationEntry(
                id: manifest.id,
                directoryURL: url,
                createdAt: manifest.createdAt,
                preview: Self.preview(from: manifest.lines),
                lineCount: manifest.lines.count,
                hasAudio: manifest.lines.contains { $0.audioFilename != nil }
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func save(lines: [TutorConversationSaveLine]) throws -> TutorConversationEntry {
        let trimmed = lines.compactMap { line -> TutorConversationSaveLine? in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text != "…" else { return nil }
            return TutorConversationSaveLine(
                speaker: line.speaker,
                text: text,
                audioClip: line.audioClip
            )
        }
        guard !trimmed.isEmpty else { throw TutorConversationStoreError.emptyConversation }

        let id = UUID()
        let directory = rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let audioDirectory = directory.appendingPathComponent(Self.audioDirectoryName, isDirectory: true)
        let hasAnyAudio = trimmed.contains { clipData($0.audioClip) != nil }
        if hasAnyAudio {
            try fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        }

        var manifestLines: [TutorConversationLine] = []
        manifestLines.reserveCapacity(trimmed.count)

        for (index, line) in trimmed.enumerated() {
            var audioFilename: String?
            if let pcm = clipData(line.audioClip) {
                let filename = String(format: "%03d.pcm", index)
                let relativePath = "\(Self.audioDirectoryName)/\(filename)"
                try pcm.write(
                    to: audioDirectory.appendingPathComponent(filename),
                    options: .atomic
                )
                audioFilename = relativePath
            }
            manifestLines.append(
                TutorConversationLine(
                    speaker: line.speaker,
                    text: line.text,
                    audioFilename: audioFilename
                )
            )
        }

        let manifest = TutorConversationManifest(
            formatVersion: TutorConversationManifest.currentFormatVersion,
            id: id,
            createdAt: Date(),
            lines: manifestLines
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: directory.appendingPathComponent(Self.manifestFilename), options: .atomic)

        try pruneAudioKeepingMostRecent(Self.maxConversationsWithAudio)

        return TutorConversationEntry(
            id: id,
            directoryURL: directory,
            createdAt: manifest.createdAt,
            preview: Self.preview(from: manifestLines),
            lineCount: manifestLines.count,
            hasAudio: manifestLines.contains { $0.audioFilename != nil }
        )
    }

    func load(at directoryURL: URL) throws -> TutorConversationManifest {
        let manifestURL = directoryURL.appendingPathComponent(Self.manifestFilename)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw TutorConversationStoreError.couldNotReadManifest
        }
        return try decodeManifest(at: manifestURL)
    }

    func audioClip(for line: TutorConversationLine, in directoryURL: URL) -> RealtimeAudioClip? {
        guard let audioFilename = line.audioFilename else { return nil }
        let url = directoryURL.appendingPathComponent(audioFilename)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        let speaker: RealtimeAudioSpeaker = line.speaker == .user ? .user : .assistant
        return RealtimeAudioClip(pcmData: data, speaker: speaker)
    }

    func deleteEntry(at directoryURL: URL) throws {
        try fileManager.removeItem(at: directoryURL)
    }

    private func pruneAudioKeepingMostRecent(_ keepCount: Int) throws {
        let entries = try listEntries()
        for entry in entries.dropFirst(keepCount) {
            try stripAudio(from: entry.directoryURL)
        }
    }

    private func stripAudio(from directoryURL: URL) throws {
        let audioDirectory = directoryURL.appendingPathComponent(Self.audioDirectoryName, isDirectory: true)
        if fileManager.fileExists(atPath: audioDirectory.path) {
            try fileManager.removeItem(at: audioDirectory)
        }

        var manifest = try load(at: directoryURL)
        guard manifest.lines.contains(where: { $0.audioFilename != nil }) else { return }

        manifest.lines = manifest.lines.map { line in
            var updated = line
            updated.audioFilename = nil
            return updated
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(
            to: directoryURL.appendingPathComponent(Self.manifestFilename),
            options: .atomic
        )
    }

    private func clipData(_ clip: RealtimeAudioClip?) -> Data? {
        guard let clip, !clip.pcmData.isEmpty else { return nil }
        return clip.pcmData
    }

    private func decodeManifest(at url: URL) throws -> TutorConversationManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TutorConversationManifest.self, from: Data(contentsOf: url))
    }

    private static func preview(from lines: [TutorConversationLine]) -> String {
        let first = lines.first(where: {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.text != "…"
        })
        guard let first else { return "Conversation" }
        let text = first.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count <= 80 { return text }
        return String(text.prefix(77)) + "…"
    }
}
