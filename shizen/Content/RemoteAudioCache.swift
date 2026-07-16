//
//  RemoteAudioCache.swift
//  shizen
//
//  Downloads published lesson audio from HTTPS CDN URLs and caches on disk.
//

import CryptoKit
import Foundation

enum RemoteAudioCache {

    private static let ioQueue = DispatchQueue(label: "shizen.remote-audio-cache", qos: .utility)

    static func cachedFileURL(for remoteURL: URL) -> URL? {
        let destination = cacheFileURL(for: remoteURL)
        return FileManager.default.fileExists(atPath: destination.path) ? destination : nil
    }

    static func ensureLocalFile(
        for remoteURL: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        if remoteURL.isFileURL {
            completion(.success(remoteURL))
            return
        }
        if let cached = cachedFileURL(for: remoteURL) {
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
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)
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

    private static func cacheFileURL(for remoteURL: URL) -> URL {
        let cachesRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioCache", isDirectory: true)
        let key = cacheKey(for: remoteURL)
        return cachesRoot.appendingPathComponent(key).appendingPathExtension("m4a")
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
