//
//  RemoteAudioCache.swift
//  shizen
//
//  Downloads published lesson audio from HTTPS CDN URLs and caches on disk.
//

import CryptoKit
import Foundation

nonisolated struct RemoteAudioCacheMetadata: Codable, Equatable, Hashable, Sendable {
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

nonisolated enum RemoteAudioCache {

    /// How urgently a download is needed. `.high` is a scene the learner is opening or
    /// about to open. `.low` is look-ahead: low URLSession priority, Wi-Fi or other
    /// unmetered networks only, and cancellable with `cancelPrefetches(owner:)`.
    nonisolated enum Priority: Sendable {
        case low
        case high

        fileprivate var taskPriority: Float {
            switch self {
            case .low: URLSessionTask.lowPriority
            case .high: URLSessionTask.highPriority
            }
        }

        fileprivate var allowsMeteredNetworks: Bool { self == .high }
    }

    /// Dedicated session so lesson audio does not queue behind `URLSession.shared`
    /// traffic. Files are cached on disk by this type, so the URL cache is off.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    private static let downloads = DownloadTable()

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

    static func cachedBedFileURL(id: String) -> URL? {
        let destination = bedCacheFileURL(id: id)
        guard FileManager.default.fileExists(atPath: destination.path) else { return nil }
        return destination
    }

    static func ensureLocalBed(
        id: String,
        remoteURL: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        loadBed(id: id, remoteURL: remoteURL, priority: .high, owner: nil, completion: completion)
    }

    static func ensureLocalFile(
        for remoteURL: URL,
        metadata: RemoteAudioCacheMetadata? = nil,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        loadFile(for: remoteURL, metadata: metadata, priority: .high, owner: nil, completion: completion)
    }

    /// Warms the cache for a scene clip without a caller waiting on it.
    static func prefetchFile(
        for remoteURL: URL,
        metadata: RemoteAudioCacheMetadata? = nil,
        priority: Priority,
        owner: UUID
    ) {
        loadFile(for: remoteURL, metadata: metadata, priority: priority, owner: owner) { _ in }
    }

    /// Warms the cache for an ambience bed without a caller waiting on it.
    static func prefetchBed(id: String, remoteURL: URL, priority: Priority, owner: UUID) {
        loadBed(id: id, remoteURL: remoteURL, priority: priority, owner: owner) { _ in }
    }

    /// Stops `.low` prefetches started by `owner` that nobody else needs.
    static func cancelPrefetches(owner: UUID) {
        Task { await downloads.cancelPrefetches(owner: owner) }
    }

    private static func loadBed(
        id: String,
        remoteURL: URL,
        priority: Priority,
        owner: UUID?,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let trimmed = sanitizedBedId(id)
        guard !trimmed.isEmpty else {
            completion(.failure(CacheError.downloadFailed))
            return
        }
        if let cached = cachedBedFileURL(id: trimmed) {
            completion(.success(cached))
            return
        }

        let destination = bedCacheFileURL(id: trimmed)
        Task {
            let result: Result<URL, Error>
            do {
                result = .success(try await downloads.file(at: destination, priority: priority, owner: owner) { priority in
                    let tempURL = try await download(from: remoteURL, priority: priority)
                    defer { try? FileManager.default.removeItem(at: tempURL) }
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                })
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private static func loadFile(
        for remoteURL: URL,
        metadata: RemoteAudioCacheMetadata?,
        priority: Priority,
        owner: UUID?,
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

        let destination = cacheFileURL(for: remoteURL)
        Task {
            let result: Result<URL, Error>
            do {
                result = .success(try await downloads.file(at: destination, priority: priority, owner: owner) { priority in
                    let tempURL = try await download(from: remoteURL, priority: priority)
                    defer { try? FileManager.default.removeItem(at: tempURL) }
                    invalidateCachedFile(for: remoteURL)
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    if let metadata, metadata.requiresValidation {
                        try writeMetadata(metadata, for: remoteURL)
                    }
                })
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// Downloads to a temp file the caller must move or delete.
    private static func download(from url: URL, priority: Priority) async throws -> URL {
        try FileManager.default.createDirectory(
            at: cacheDirectoryURL(),
            withIntermediateDirectories: true
        )
        var request = URLRequest(url: url)
        request.allowsExpensiveNetworkAccess = priority.allowsMeteredNetworks
        request.allowsConstrainedNetworkAccess = priority.allowsMeteredNetworks
        let (tempURL, response) = try await session.download(
            for: request,
            delegate: PriorityDelegate(priority: priority.taskPriority)
        )
        // A cancelled prefetch must not move a file under a download that replaced it.
        guard !Task.isCancelled,
              let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: tempURL)
            throw Task.isCancelled ? CancellationError() : CacheError.downloadFailed
        }
        return tempURL
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

    private static func sanitizedBedId(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
    }

    private static func bedCacheFileURL(id: String) -> URL {
        cacheDirectoryURL()
            .appendingPathComponent("ambience-\(sanitizedBedId(id))")
            .appendingPathExtension("m4a")
    }

    private static func cacheKey(for remoteURL: URL) -> String {
        let digest = SHA256.hash(data: Data(remoteURL.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated enum CacheError: LocalizedError {
        case downloadFailed

        var errorDescription: String? {
            "Failed to download remote audio."
        }
    }
}

/// Downloads already in progress, keyed by the cache file they fill. A repeat
/// request joins the running download. A `.high` request never joins a `.low` one,
/// since that may be held to Wi-Fi; it replaces it instead.
private actor DownloadTable {
    private final class Job {
        let task: Task<Void, Error>
        let priority: RemoteAudioCache.Priority
        /// Prefetch owners waiting on this job. Only `.low` jobs are cancelled by owner.
        var owners: Set<UUID>

        init(task: Task<Void, Error>, priority: RemoteAudioCache.Priority, owners: Set<UUID>) {
            self.task = task
            self.priority = priority
            self.owners = owners
        }
    }

    private var jobs: [URL: Job] = [:]

    func file(
        at destination: URL,
        priority: RemoteAudioCache.Priority,
        owner: UUID?,
        install: @escaping @Sendable (RemoteAudioCache.Priority) async throws -> Void
    ) async throws -> URL {
        if let job = jobs[destination], job.priority == .high || priority == .low {
            if let owner {
                job.owners.insert(owner)
            }
            try await job.task.value
            return destination
        }
        jobs[destination]?.task.cancel()
        // Detached so the download and file move run off this actor.
        let job = Job(
            task: Task.detached { try await install(priority) },
            priority: priority,
            owners: owner.map { [$0] } ?? []
        )
        jobs[destination] = job
        defer {
            if jobs[destination] === job {
                jobs[destination] = nil
            }
        }
        try await job.task.value
        return destination
    }

    func cancelPrefetches(owner: UUID) {
        for (destination, job) in jobs where job.priority == .low {
            job.owners.remove(owner)
            if job.owners.isEmpty {
                job.task.cancel()
                jobs[destination] = nil
            }
        }
    }
}

/// Sets the URLSession task priority once the async API creates the task.
private nonisolated final class PriorityDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let priority: Float

    init(priority: Float) {
        self.priority = priority
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        task.priority = priority
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
