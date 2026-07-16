//
//  ContentCMSClient.swift
//  shizen
//
//  Fetches published dialogue lessons from the Content Studio public API.
//

import Foundation

struct CMSDialogueLessonSummary: Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let sceneImage: String?
    let thumbnailUrl: String?
    let orderIndex: Int
    let updatedAt: String?
    let scenarioCount: Int
}

enum ContentCMSClient {

    /// Base URL for the Content Studio webapp (serves `/api/public/dialogues`).
    /// Not the CDN — audio/thumbnails use absolute `https://cdn.shizenapp.com/...` URLs from the API JSON.
    /// When unset, Shizen uses bundled JSON only (DEBUG falls back to local Next.js on the simulator).
    static var baseURL: URL? {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "SHIZEN_CMS_BASE_URL") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let url = URL(string: trimmed) {
                return url
            }
        }
        #if DEBUG
        return URL(string: "http://127.0.0.1:3000")
        #else
        return nil
        #endif
    }

    static var isConfigured: Bool { baseURL != nil }

    /// Lists every dialogue lesson (collection) from the CMS.
    /// Does not require per-lesson URLs — only the CMS base URL.
    static func fetchDialogueLessons(
        completion: @escaping (Result<[CMSDialogueLessonSummary], Error>) -> Void
    ) {
        guard let baseURL else {
            completion(.failure(CMSClientError.notConfigured))
            return
        }
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("public")
            .appendingPathComponent("dialogues")
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(CMSClientError.invalidResponse))
                return
            }
            guard (200 ... 299).contains(http.statusCode), let data else {
                completion(.failure(CMSClientError.httpStatus(http.statusCode)))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(LessonListPayload.self, from: data)
                let lessons = decoded.collections
                    .map { $0.asSummary }
                    .sorted {
                        if $0.orderIndex != $1.orderIndex {
                            return $0.orderIndex < $1.orderIndex
                        }
                        return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    }
                completion(.success(lessons))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    static func fetchDialogueCollection(
        id: String,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        guard let baseURL else {
            if let cached = readCachedCollectionData(id: id) {
                completion(.success(cached))
            } else {
                completion(.failure(CMSClientError.notConfigured))
            }
            return
        }
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("public")
            .appendingPathComponent("dialogues")
            .appendingPathComponent(id)
        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                if let cached = readCachedCollectionData(id: id) {
                    completion(.success(cached))
                } else {
                    completion(.failure(error))
                }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(CMSClientError.invalidResponse))
                return
            }
            guard (200 ... 299).contains(http.statusCode), let data else {
                if let cached = readCachedCollectionData(id: id) {
                    completion(.success(cached))
                } else {
                    completion(.failure(CMSClientError.httpStatus(http.statusCode)))
                }
                return
            }
            writeCachedCollectionData(data, id: id)
            completion(.success(data))
        }.resume()
    }

    private static func cacheDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ContentCache/dialogues", isDirectory: true)
    }

    private static func readCachedCollectionData(id: String) -> Data? {
        let url = cacheDirectory().appendingPathComponent("\(id).json")
        return try? Data(contentsOf: url)
    }

    private static func writeCachedCollectionData(_ data: Data, id: String) {
        let directory = cacheDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(id).json")
        try? data.write(to: url, options: .atomic)
    }

    private struct LessonListPayload: Decodable {
        let collections: [LessonSummaryRecord]
    }

    private struct LessonSummaryRecord: Decodable {
        let id: String
        let title: String
        let subtitle: String?
        let sceneImage: String?
        let thumbnailUrl: String?
        let orderIndex: Int
        let updatedAt: String?
        let scenarioCount: Int

        var asSummary: CMSDialogueLessonSummary {
            CMSDialogueLessonSummary(
                id: id,
                title: title,
                subtitle: subtitle,
                sceneImage: sceneImage,
                thumbnailUrl: thumbnailUrl,
                orderIndex: orderIndex,
                updatedAt: updatedAt,
                scenarioCount: scenarioCount
            )
        }
    }

    enum CMSClientError: LocalizedError {
        case notConfigured
        case invalidResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "SHIZEN_CMS_BASE_URL is not configured."
            case .invalidResponse:
                return "Invalid CMS response."
            case .httpStatus(let code):
                return "CMS request failed with status \(code)."
            }
        }
    }
}
