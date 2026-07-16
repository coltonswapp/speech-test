//
//  DialogueAlignmentMetadata.swift
//  TTSCore
//
//  Embeds dialogue line switch times in M4A/MP4 container metadata.
//

import AVFoundation
import Foundation

public enum DialogueAlignmentMetadata {

    public static let formatVersion = 1
    /// Decimal places stored in exported M4A comment tags (millisecond resolution).
    public static let switchTimeDecimalPlaces = 3
    /// Prefix on the iTunes/QuickTime comment tag (`©cmt`).
    public static let commentPrefix = "shizen.dialogue.v1:"
    /// Legacy QuickTime identifier (first implementation).
    public static let metadataIdentifierRawValue = "mdta/com.shizen.dialogue.alignment"

    public struct Payload: Codable, Sendable, Equatable {
        public var version: Int
        public var lineSwitchSeconds: [TimeInterval]

        public init(version: Int = DialogueAlignmentMetadata.formatVersion, lineSwitchSeconds: [TimeInterval]) {
            self.version = version
            self.lineSwitchSeconds = DialogueAlignmentMetadata.roundedSwitchTimes(lineSwitchSeconds)
        }
    }

    /// Rounds switch times for compact, stable metadata (default: millisecond precision).
    public static func roundedSwitchTimes(_ seconds: [TimeInterval]) -> [TimeInterval] {
        guard switchTimeDecimalPlaces >= 0 else { return seconds }
        let scale = pow(10.0, Double(switchTimeDecimalPlaces))
        return seconds.map { ($0 * scale).rounded() / scale }
    }

    public enum MetadataError: Error, LocalizedError {
        case invalidPayload
        case exportFailed(String)
        case couldNotWrite
        case verificationFailed

        public var errorDescription: String? {
            switch self {
            case .invalidPayload: return "Dialogue alignment metadata is invalid."
            case let .exportFailed(message): return "Could not embed alignment metadata: \(message)"
            case .couldNotWrite: return "Could not write the audio file."
            case .verificationFailed: return "Exported M4A did not retain dialogue alignment metadata."
            }
        }
    }

    // MARK: - Encode / decode

    public static func encode(_ payload: Payload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    public static func decode(from data: Data) -> Payload? {
        try? JSONDecoder().decode(Payload.self, from: data)
    }

    public static func decode(from string: String) -> Payload? {
        guard let data = string.data(using: .utf8) else { return nil }
        return decode(from: data)
    }

    public static func commentTagValue(for payload: Payload) throws -> String {
        let json = try encode(payload)
        guard let body = String(data: json, encoding: .utf8) else { throw MetadataError.invalidPayload }
        return commentPrefix + body
    }

    // MARK: - Read

    /// Reads embedded switch times from an M4A/MP4 URL. Returns `nil` when absent or invalid.
    public static func readLineSwitchSeconds(from url: URL) -> [TimeInterval]? {
        readPayload(from: url)?.lineSwitchSeconds
    }

    public static func readPayload(from url: URL) -> Payload? {
        if Thread.isMainThread {
            return DispatchQueue.global(qos: .utility).sync {
                readPayloadBlocking(from: url)
            }
        }
        return readPayloadBlocking(from: url)
    }

    private static func readPayloadBlocking(from url: URL) -> Payload? {
        let asset = AVURLAsset(url: url)
        let key = "metadata"
        let sem = DispatchSemaphore(value: 0)
        asset.loadValuesAsynchronously(forKeys: [key]) {
            sem.signal()
        }
        sem.wait()

        var error: NSError?
        guard asset.statusOfValue(forKey: key, error: &error) == .loaded else { return nil }

        var items = asset.metadata
        for format in [AVMetadataFormat.iTunesMetadata, .quickTimeMetadata] {
            items.append(contentsOf: asset.metadata(forFormat: format))
        }

        for item in items {
            if let payload = payload(from: item) { return payload }
        }
        return nil
    }

    private static func payload(from item: AVMetadataItem) -> Payload? {
        if let string = item.stringValue, let payload = payload(fromPrefixedString: string) {
            return payload
        }
        if let value = item.value as? String, let payload = payload(fromPrefixedString: value) {
            return payload
        }
        if let data = item.dataValue, let payload = decode(from: data) {
            return validated(payload)
        }
        if let value = item.value as? Data, let payload = decode(from: value) {
            return validated(payload)
        }
        if let raw = item.identifier?.rawValue,
           raw.contains("com.shizen.dialogue.alignment"),
           let string = item.stringValue ?? item.value as? String,
           let payload = decode(from: string) {
            return validated(payload)
        }
        return nil
    }

    private static func payload(fromPrefixedString string: String) -> Payload? {
        guard string.hasPrefix(commentPrefix) else { return nil }
        let json = String(string.dropFirst(commentPrefix.count))
        guard let payload = decode(from: json) else { return nil }
        return validated(payload)
    }

    private static func validated(_ payload: Payload) -> Payload? {
        guard payload.version > 0, !payload.lineSwitchSeconds.isEmpty else { return nil }
        let sorted = payload.lineSwitchSeconds.sorted()
        guard sorted == payload.lineSwitchSeconds else { return nil }
        guard sorted.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        for index in 1..<sorted.count where sorted[index] <= sorted[index - 1] {
            return nil
        }
        return payload
    }

    // MARK: - Write

    /// Writes AAC audio, then attaches alignment metadata via re-export.
    public static func writeM4A(
        samples: [Float],
        sampleRange: Range<Int>,
        sampleRate: Double,
        lineSwitchSeconds: [TimeInterval],
        to url: URL
    ) throws {
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent("dialogue-m4a-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: tmp) }

        try writeRawM4A(samples: samples, sampleRange: sampleRange, sampleRate: sampleRate, to: tmp)

        let payload = Payload(lineSwitchSeconds: lineSwitchSeconds)
        try attachPayload(payload, toM4AAt: tmp, outputURL: url)

        guard let verified = readPayloadBlocking(from: url) else {
            throw MetadataError.verificationFailed
        }
        guard verified.lineSwitchSeconds == payload.lineSwitchSeconds else {
            throw MetadataError.verificationFailed
        }
    }

    /// Embeds alignment metadata into an existing M4A.
    public static func attachPayload(_ payload: Payload, toM4AAt inputURL: URL, outputURL: URL) throws {
        guard let validated = validated(payload) else { throw MetadataError.invalidPayload }
        let asset = AVURLAsset(url: inputURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw MetadataError.exportFailed("export session unavailable")
        }

        let tmpOut = outputURL.deletingLastPathComponent()
            .appendingPathComponent("dialogue-meta-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: tmpOut) }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        session.outputURL = tmpOut
        session.outputFileType = .m4a
        session.metadata = [try makeCommentMetadataItem(validated)]

        let sem = DispatchSemaphore(value: 0)
        session.exportAsynchronously { sem.signal() }
        sem.wait()

        guard session.status == .completed else {
            let message = session.error?.localizedDescription ?? "status \(session.status.rawValue)"
            throw MetadataError.exportFailed(message)
        }

        try FileManager.default.moveItem(at: tmpOut, to: outputURL)
    }

    private static func makeCommentMetadataItem(_ payload: Payload) throws -> AVMetadataItem {
        let tagged = try commentTagValue(for: payload)
        let item = AVMutableMetadataItem()
        item.keySpace = AVMetadataKeySpace(rawValue: "itsk")
        item.key = "\u{00A9}cmt" as (NSCopying & NSObjectProtocol)?
        item.value = tagged as NSString
        item.extendedLanguageTag = "und"
        return item
    }

    private static func writeRawM4A(
        samples: [Float],
        sampleRange: Range<Int>,
        sampleRate: Double,
        to url: URL
    ) throws {
        guard !sampleRange.isEmpty,
              sampleRange.lowerBound >= 0,
              sampleRange.upperBound <= samples.count
        else { throw MetadataError.couldNotWrite }

        let frameCount = AVAudioFrameCount(sampleRange.count)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { throw MetadataError.couldNotWrite }

        buffer.frameLength = frameCount
        let slice = samples[sampleRange]
        slice.withUnsafeBufferPointer { src in
            guard let dst = buffer.floatChannelData?[0], let base = src.baseAddress else { return }
            dst.update(from: base, count: slice.count)
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }

    // MARK: - Segment building

    /// Builds aligned line ranges from explicit switch times (count must be `lines - 1`).
    public static func segmentTimeRanges(
        lineTexts: [String],
        duration: TimeInterval,
        lineSwitchSeconds: [TimeInterval],
        tailPad: TimeInterval = 0.06
    ) -> [AlignedTimeLine]? {
        let trimmed = lineTexts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmed.isEmpty, duration > 0 else { return nil }
        guard trimmed.count == lineSwitchSeconds.count + 1 else { return nil }
        guard validated(Payload(lineSwitchSeconds: lineSwitchSeconds)) != nil else { return nil }
        guard lineSwitchSeconds.allSatisfy({ $0 < duration }) else { return nil }

        let starts: [TimeInterval] = [0] + lineSwitchSeconds
        return trimmed.enumerated().map { index, text in
            let start = starts[index]
            let end: TimeInterval
            if index + 1 < starts.count {
                end = min(duration, starts[index + 1] + tailPad)
            } else {
                end = duration
            }
            return AlignedTimeLine(text: text, timeRange: start..<max(start, end))
        }
    }
}
