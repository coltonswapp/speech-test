//
//  SavedGenerationStore.swift
//  shizen
//
//  Persists a TTS utterance as manifest.json + raw Float32 mono PCM (24 kHz).
//

import Foundation

public enum SavedGenerationError: Error, LocalizedError {
    case couldNotReadManifest
    case invalidAudioFile
    case invalidSentenceAlignment
    case notReadyToExport

    public var errorDescription: String? {
        switch self {
        case .couldNotReadManifest:
            return "Could not read the saved manifest."
        case .invalidAudioFile:
            return "Saved audio file is missing or corrupted."
        case .invalidSentenceAlignment:
            return "Saved sentence ranges do not match the audio length."
        case .notReadyToExport:
            return "Wait until every sentence is ready before saving."
        }
    }
}

/// On-disk format version for `manifest.json`.
public struct SavedTTSSnapshot: Codable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var createdAt: Date
    public var utteranceSourceText: String
    public var voice: String
    public var provider: String?
    public var sampleRate: Double
    public var sentences: [SavedSentenceRow]
}

public struct SavedSentenceRow: Codable {
    public var text: String
    public var sampleLower: Int
    public var sampleUpper: Int
    public var peaks: [Float]
}

public enum SavedGenerationFilenames {
    public static let manifest = "manifest.json"
    public static let audio = "audio.float32"
}

public struct SavedGenerationEntry {
    public let id: UUID
    public let directoryURL: URL
    public let createdAt: Date
    public let utterancePreview: String
    public let sentenceCount: Int
    public let durationSeconds: Double
    public var voice: String
}

/// File-backed store accessed from the main thread in shipped apps; marked unchecked for Swift 6 `shared` concurrency checks.
public final class SavedGenerationStore: @unchecked Sendable {
    public static let shared = SavedGenerationStore()

    private let rootDirectory: URL
    private let fileManager: FileManager

    /// Root folder for flat iOS-era SavedGenerations bundles (manifest.json + audio.float32).
    public var bundlesRootDirectory: URL { rootDirectory }

    /// Matches `TextToSpeechService.exportSavedBundle` (`JSONEncoder.dateEncodingStrategy = .iso8601`).
    private static func snapshotJSONDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        rootDirectory = base.appendingPathComponent("SavedGenerations", isDirectory: true)
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    /// Creates a new UUID-named folder ready for `TextToSpeechService.exportSavedBundle(to:)`.
    public func makeNewBundleDirectory() throws -> URL {
        let id = UUID()
        let dir = rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func listEntries() throws -> [SavedGenerationEntry] {
        let urls = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var entries: [SavedGenerationEntry] = []
        for url in urls where url.hasDirectoryPath {
            let manifestURL = url.appendingPathComponent(SavedGenerationFilenames.manifest)
            guard let data = try? Data(contentsOf: manifestURL),
                  let snap = try? Self.snapshotJSONDecoder().decode(SavedTTSSnapshot.self, from: data)
            else { continue }
            let id = UUID(uuidString: url.lastPathComponent) ?? UUID()
            let preview = snap.utteranceSourceText
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init) ?? snap.utteranceSourceText
            let trimmedPreview = preview.trimmingCharacters(in: .whitespacesAndNewlines)
            let audioURL = url.appendingPathComponent(SavedGenerationFilenames.audio)
            let byteCount = (try? fileManager.attributesOfItem(atPath: audioURL.path)[.size] as? NSNumber)?.intValue ?? 0
            let sampleCount = byteCount / MemoryLayout<Float>.size
            let duration = Double(sampleCount) / max(snap.sampleRate, 1)
            entries.append(
                SavedGenerationEntry(
                    id: id,
                    directoryURL: url,
                    createdAt: snap.createdAt,
                    utterancePreview: String(trimmedPreview.prefix(120)),
                    sentenceCount: snap.sentences.count,
                    durationSeconds: duration,
                    voice: snap.voice
                )
            )
        }
        return entries.sorted { $0.createdAt > $1.createdAt }
    }

    public func deleteEntry(at directoryURL: URL) throws {
        try fileManager.removeItem(at: directoryURL)
    }
}
