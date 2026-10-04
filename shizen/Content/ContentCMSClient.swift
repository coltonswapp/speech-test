//
//  ContentCMSClient.swift
//  shizen
//
//  Fetches published dialogue lessons from the Content Studio public API.
//

import Foundation

struct CMSDialogueLessonSummary: Hashable, Sendable {
    let id: String
    /// Curriculum unit (grammar band) this lesson belongs to; nil = unfiled.
    let unitId: String?
    let title: String
    let subtitle: String?
    let sceneImage: String?
    let thumbnailUrl: String?
    let thumbnailSmallUrl: String?
    let orderIndex: Int
    let updatedAt: String?
    let scenarioCount: Int
    /// Scene ids in lesson order. Empty on indexes cached before this field existed.
    let scenarioIDs: [String]
}

struct CMSCurriculumUnit: Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    /// 5 = N5 … 1 = N1, matching GrammarPoint.jlptLevel.
    let jlptLevel: Int
    let orderIndex: Int
}

/// Full lesson index: curriculum units in display order plus every lesson.
/// Lessons whose `unitId` is nil (or references an unknown unit) are unfiled.
struct CMSDialogueLessonIndex: Sendable {
    let units: [CMSCurriculumUnit]
    let lessons: [CMSDialogueLessonSummary]
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

    /// Studio lesson editor URL for content QA notes. Path-only when no CMS base URL is set.
    static func studioLessonEditorLink(collectionId: String) -> String {
        let path = "/content/dialogues/\(collectionId)"
        guard let baseURL else { return path }
        return baseURL.appendingPathComponent("content/dialogues/\(collectionId)").absoluteString
    }

    /// Studio scenario editor URL for content QA notes. Path-only when no CMS base URL is set.
    static func studioScenarioEditorLink(collectionId: String, slug: String) -> String {
        let path = "/content/dialogues/\(collectionId)/\(slug)"
        guard let baseURL else { return path }
        return baseURL.appendingPathComponent("content/dialogues/\(collectionId)/\(slug)").absoluteString
    }

    enum QANoteSource: String, Encodable {
        case dialogue
        case quiz
    }

    struct QANote: Encodable {
        struct Metadata: Encodable {
            let url: String
            let createdAt: Date

            private enum CodingKeys: String, CodingKey {
                case url
                case createdAt = "created_at"
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(url, forKey: .url)
                try container.encode(ISO8601DateFormatter().string(from: createdAt), forKey: .createdAt)
            }
        }

        let source: QANoteSource
        let sourceId: String
        let title: String?
        let note: String
        let metadata: Metadata

        private enum CodingKeys: String, CodingKey {
            case source
            case sourceId = "source_id"
            case title
            case note
            case metadata
        }
    }

    /// Sends a QA note to Shohei through Studio. Returns the accepted job id.
    /// `agent` is omitted so the note always starts with Shohei.
    static func sendQANote(
        _ note: QANote,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let baseURL else {
            completion(.failure(CMSClientError.notConfigured))
            return
        }
        let token = ContentQAClientToken.resolved
        guard !token.isEmpty else {
            completion(.failure(CMSClientError.missingContentQAToken))
            return
        }
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("client")
            .appendingPathComponent("content-qa")
            .appendingPathComponent("notes")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(note)
        } catch {
            completion(.failure(error))
            return
        }
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(CMSClientError.invalidResponse))
                return
            }
            guard http.statusCode == 202, let data else {
                let reason = data.flatMap { String(data: $0, encoding: .utf8) }?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if (400 ..< 500).contains(http.statusCode), !reason.isEmpty {
                    completion(.failure(CMSClientError.rejected(reason)))
                } else {
                    completion(.failure(CMSClientError.httpStatus(http.statusCode)))
                }
                return
            }
            struct Accepted: Decodable {
                let jobId: String
                private enum CodingKeys: String, CodingKey { case jobId = "job_id" }
            }
            guard let accepted = try? JSONDecoder().decode(Accepted.self, from: data) else {
                completion(.failure(CMSClientError.invalidResponse))
                return
            }
            completion(.success(accepted.jobId))
        }.resume()
    }

    /// Lists every dialogue lesson (collection) from the CMS, grouped under
    /// curriculum units. Does not require per-lesson URLs — only the CMS base URL.
    static func fetchDialogueLessonIndex(
        completion: @escaping (Result<CMSDialogueLessonIndex, Error>) -> Void
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
                let index = try parseLessonIndex(data)
                writeCachedLessonIndex(data)
                completion(.success(index))
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
        request.cachePolicy = .reloadIgnoringLocalCacheData
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

    /// Marks one scene checked off in Studio content QA.
    /// Public lesson fetches stay unauthenticated; this write sends `Authorization: Bearer`.
    static func checkOffScene(
        collectionId: String,
        slug: String,
        reviewNote: String? = nil,
        reviewedBy: String? = nil,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        guard let baseURL else {
            completion(.failure(CMSClientError.notConfigured))
            return
        }
        let token = ContentQAClientToken.resolved
        guard !token.isEmpty else {
            completion(.failure(CMSClientError.missingContentQAToken))
            return
        }
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("client")
            .appendingPathComponent("content-qa")
            .appendingPathComponent("dialogues")
            .appendingPathComponent(collectionId)
            .appendingPathComponent("scenarios")
            .appendingPathComponent(slug)
            .appendingPathComponent("check-off")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: String] = [:]
        if let reviewNote {
            body["reviewNote"] = reviewNote
        }
        if let reviewedBy {
            body["reviewedBy"] = reviewedBy
        }
        request.httpBody = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
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
            completion(.success(data))
        }.resume()
    }

    static func cachedDialogueLessonIndex() -> CMSDialogueLessonIndex? {
        guard let data = readCachedLessonIndexData() else { return nil }
        return try? parseLessonIndex(data)
    }

    private static func parseLessonIndex(_ data: Data) throws -> CMSDialogueLessonIndex {
        let decoded = try JSONDecoder().decode(LessonListPayload.self, from: data)
        let lessons = decoded.collections
            .map { $0.asSummary }
            .sorted {
                if $0.orderIndex != $1.orderIndex {
                    return $0.orderIndex < $1.orderIndex
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        let units = (decoded.units ?? [])
            .map { $0.asUnit }
            .sorted {
                if $0.orderIndex != $1.orderIndex {
                    return $0.orderIndex < $1.orderIndex
                }
                return $0.id < $1.id
            }
        return CMSDialogueLessonIndex(units: units, lessons: lessons)
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
        writeCachedData(data, fileName: "\(id).json")
    }

    private static func readCachedLessonIndexData() -> Data? {
        try? Data(contentsOf: cacheDirectory().appendingPathComponent("index.json"))
    }

    private static func writeCachedLessonIndex(_ data: Data) {
        writeCachedData(data, fileName: "index.json")
    }

    private static func writeCachedData(_ data: Data, fileName: String) {
        let directory = cacheDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    private struct LessonListPayload: Decodable {
        // `units` is absent on older CMS deployments.
        let units: [UnitRecord]?
        let collections: [LessonSummaryRecord]
    }

    private struct UnitRecord: Decodable {
        let id: String
        let title: String
        let subtitle: String?
        let jlptLevel: Int
        let orderIndex: Int

        var asUnit: CMSCurriculumUnit {
            CMSCurriculumUnit(
                id: id,
                title: title,
                subtitle: subtitle,
                jlptLevel: jlptLevel,
                orderIndex: orderIndex
            )
        }
    }

    private struct LessonSummaryRecord: Decodable {
        let id: String
        let unitId: String?
        let title: String
        let subtitle: String?
        let sceneImage: String?
        let thumbnailUrl: String?
        let thumbnailSmallUrl: String?
        let orderIndex: Int
        let updatedAt: String?
        let scenarioCount: Int
        let scenarioIds: [String]?

        var asSummary: CMSDialogueLessonSummary {
            CMSDialogueLessonSummary(
                id: id,
                unitId: unitId,
                title: title,
                subtitle: subtitle,
                sceneImage: sceneImage,
                thumbnailUrl: thumbnailUrl,
                thumbnailSmallUrl: thumbnailSmallUrl,
                orderIndex: orderIndex,
                updatedAt: updatedAt,
                scenarioCount: scenarioCount,
                scenarioIDs: scenarioIds ?? []
            )
        }
    }

    enum CMSClientError: LocalizedError {
        case notConfigured
        case missingContentQAToken
        case invalidResponse
        case httpStatus(Int)
        case rejected(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "SHIZEN_CMS_BASE_URL is not configured."
            case .missingContentQAToken:
                return "CONTENT_QA_CLIENT_TOKEN is missing."
            case .invalidResponse:
                return "Invalid CMS response."
            case .httpStatus(let code):
                return "CMS request failed with status \(code)."
            case .rejected(let reason):
                return reason
            }
        }
    }
}
