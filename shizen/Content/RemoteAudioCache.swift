//
//  RemoteAudioCache.swift
//  shizen
//
//  Downloads published lesson audio from HTTPS CDN URLs and caches on disk.
//

import CryptoKit
import Foundation

struct RemoteAudioCacheMetadata: Codable, Equatable, Hashable {
    let publishedVariantId: String?
    let publishedContentHash: String?
    let publishedAt: String?

    init(
        publishedVariantId: String? = nil,
        publishedContentHash: String? = nil,
        publishedAt: String? = nil
    ) {
        self.publishedVariantId = Self.normalized(publishedVariantId)
        self.publishedContentHash = Self.normalized(publishedContentHash)
        self.publishedAt = Self.normalized(publishedAt)
    }

    var requiresValidation: Bool {
        publishedVariantId != nil || publishedContentHash != nil || publishedAt != nil
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum RemoteAudioCache {

    private static let ioQueue = DispatchQueue(label: "shizen.remote-audio-cache", qos: .utility)

    static func cachedFileCount() -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectoryURL(),
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }
        return files.filter { $0.pathExtension == "m4a" }.count
    }

    @discardableResult
    static func clearAllCachedFiles() throws -> Int {
        let directory = cacheDirectoryURL()
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for url in files {
            try FileManager.default.removeItem(at: url)
        }
        return files.filter { $0.pathExtension == "m4a" }.count
    }

    static func cachedFileURL(
        for remoteURL: URL,
        expected metadata: RemoteAudioCacheMetadata? = nil
    ) -> URL? {
        let destination = cacheFileURL(for: remoteURL)
        guard FileManager.default.fileExists(atPath: destination.path) else { return nil }

        guard let metadata, metadata.requiresValidation else {
            return destination
        }

        guard let stored = readMetadata(for: remoteURL), stored == metadata else {
            invalidateCachedFile(for: remoteURL)
            return nil
        }

        return destination
    }

    static func ensureLocalFile(
        for remoteURL: URL,
        metadata: RemoteAudioCacheMetadata? = nil,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        if remoteURL.isFileURL {
            completion(.success(remoteURL))
            return
        }
        if let cached = cachedFileURL(for: remoteURL, expected: metadata) {
            completion(.success(cached))
            return
        }

        ioQueue.async {
            do {
                let destination = cacheFileURL(for: remoteURL)
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let (tempURL, response) = try syncDownload(from: remoteURL)
                defer { try? FileManager.default.removeItem(at: tempURL) }
                guard let http = response as? HTTPURLResponse,
                      (200 ... 299).contains(http.statusCode) else {
                    throw CacheError.downloadFailed
                }
                invalidateCachedFile(for: remoteURL)
                try FileManager.default.moveItem(at: tempURL, to: destination)
                if let metadata, metadata.requiresValidation {
                    try writeMetadata(metadata, for: remoteURL)
                }
                DispatchQueue.main.async {
                    completion(.success(destination))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    private static func syncDownload(from url: URL) throws -> (URL, URLResponse) {
        var result: Result<(URL, URLResponse), Error>?
        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            defer { semaphore.signal() }
            if let error {
                result = .failure(error)
                return
            }
            guard let tempURL, let response else {
                result = .failure(CacheError.downloadFailed)
                return
            }
            result = .success((tempURL, response))
        }
        task.resume()
        semaphore.wait()
        switch result {
        case .success(let pair):
            return pair
        case .failure(let error):
            throw error
        case .none:
            throw CacheError.downloadFailed
        }
    }

    private static func invalidateCachedFile(for remoteURL: URL) {
        let audioURL = cacheFileURL(for: remoteURL)
        try? FileManager.default.removeItem(at: audioURL)
        try? FileManager.default.removeItem(at: metadataFileURL(for: remoteURL))
    }

    private static func readMetadata(for remoteURL: URL) -> RemoteAudioCacheMetadata? {
        let url = metadataFileURL(for: remoteURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RemoteAudioCacheMetadata.self, from: data)
    }

    private static func writeMetadata(_ metadata: RemoteAudioCacheMetadata, for remoteURL: URL) throws {
        let url = metadataFileURL(for: remoteURL)
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: url, options: .atomic)
    }

    private static func cacheDirectoryURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioCache", isDirectory: true)
    }

    private static func cacheFileURL(for remoteURL: URL) -> URL {
        let key = cacheKey(for: remoteURL)
        return cacheDirectoryURL().appendingPathComponent(key).appendingPathExtension("m4a")
    }

    private static func metadataFileURL(for remoteURL: URL) -> URL {
        cacheFileURL(for: remoteURL).deletingPathExtension().appendingPathExtension("meta.json")
    }

    private static func cacheKey(for remoteURL: URL) -> String {
        let digest = SHA256.hash(data: Data(remoteURL.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private enum CacheError: LocalizedError {
        case downloadFailed

        var errorDescription: String? {
            "Failed to download remote audio."
        }
    }
}

extension GrammarExample {
    var remoteAudioCacheMetadata: RemoteAudioCacheMetadata {
        RemoteAudioCacheMetadata(
            publishedVariantId: publishedVariantId,
            publishedContentHash: publishedContentHash,
            publishedAt: publishedAt
        )
    }
}
