//
//  ClipPayload.swift
//  shizen
//
//  Word-synced YouTube clip (Studio Experiments → Clip transcripts), served
//  from `/api/public/clips`. All times are seconds on the video's timeline.
//

import Foundation

/// Video shape from Studio: "portrait" = 9:16 YouTube Short. Missing = landscape.
nonisolated enum ClipOrientation: String, Decodable, Sendable {
    case landscape
    case portrait

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ClipOrientation(rawValue: raw) ?? .landscape
    }
}

nonisolated struct ClipSummary: Decodable, Hashable, Sendable {
    let clipID: String
    let videoID: String
    let startSec: Double
    let endSec: Double
    let sentenceCount: Int
    let previewJP: String
    let orientation: ClipOrientation?
    /// 5 = N5 … 1 = N1, matching GrammarPoint.jlptLevel. Nil until rated in Studio.
    let jlptLevel: Int?
    /// The video's YouTube title and channel. Nil until Studio has fetched them.
    let title: String?
    let channelName: String?

    var isPortrait: Bool { orientation == .portrait }

    enum CodingKeys: String, CodingKey {
        case clipID = "clip_id"
        case videoID = "video_id"
        case startSec = "start_sec"
        case endSec = "end_sec"
        case sentenceCount = "sentence_count"
        case previewJP = "preview_jp"
        case orientation
        case jlptLevel = "jlpt_level"
        case title
        case channelName = "channel_name"
    }
}

nonisolated struct ClipPayload: Decodable, Sendable {
    let clipID: String
    let media: Media
    let sentences: [Sentence]
    let tokens: [Token]
    /// Lesson-style highlights (camelCase, same as a scene's `highlights`).
    let highlights: Highlights?
    /// Pattern library cards for grammar highlights with a `patternId`.
    let patterns: [TeachingPattern]?
    /// 5 = N5 … 1 = N1. Nil until rated in Studio.
    let jlptLevel: Int?
    /// Set on a retired clip: it is out of the clip list and its video may be
    /// gone, so don't play it. The transcript is still here for saved items.
    let deprecated: Deprecation?

    var isDeprecated: Bool { deprecated != nil }

    nonisolated struct Deprecation: Decodable, Sendable {
        let at: String?
        let reason: String?
    }

    nonisolated struct Highlights: Decodable, Sendable {
        let vocabulary: [String]?
        let grammarPatterns: [GrammarPattern]?
        let contextNotes: [String]?
    }

    /// A plain label string, or an object with label / patternId / grammar point / source lines.
    nonisolated struct GrammarPattern: Decodable, Sendable {
        let label: String
        let patternId: String?
        let grammarPointID: String?
        let sourceSpokenStart: Int?
        let sourceSpokenEnd: Int?

        private enum CodingKeys: String, CodingKey {
            case label, patternId, grammarPointID, sourceSpokenStart, sourceSpokenEnd
        }

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer(),
               let string = try? single.decode(String.self) {
                label = string.trimmingCharacters(in: .whitespacesAndNewlines)
                patternId = nil
                grammarPointID = nil
                sourceSpokenStart = nil
                sourceSpokenEnd = nil
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let decodedLabel = try container.decodeIfPresent(String.self, forKey: .label)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            patternId = try container.decodeIfPresent(String.self, forKey: .patternId)
            grammarPointID = try container.decodeIfPresent(String.self, forKey: .grammarPointID)
            sourceSpokenStart = try container.decodeIfPresent(Int.self, forKey: .sourceSpokenStart)
            sourceSpokenEnd = try container.decodeIfPresent(Int.self, forKey: .sourceSpokenEnd)
            label = decodedLabel.isEmpty ? (patternId ?? "") : decodedLabel
        }
    }

    nonisolated struct TeachingPattern: Decodable, Sendable {
        let id: String
        let label: String
        let description: String?
        let shortMeaning: String?
        let formNote: String?
    }

    nonisolated struct Media: Decodable, Sendable {
        let source: String
        let videoID: String
        let startSec: Double
        let endSec: Double
        let orientation: ClipOrientation?
        /// The video's YouTube title and channel. Nil until Studio has fetched them.
        let title: String?
        let channelName: String?
        let channelURL: String?
        let thumbnailURL: String?

        var isPortrait: Bool { orientation == .portrait }

        enum CodingKeys: String, CodingKey {
            case source
            case videoID = "video_id"
            case startSec = "start_sec"
            case endSec = "end_sec"
            case orientation
            case title
            case channelName = "channel_name"
            case channelURL = "channel_url"
            case thumbnailURL = "thumbnail_url"
        }
    }

    nonisolated struct Sentence: Decodable, Sendable {
        let index: Int
        let startSec: Double
        let endSec: Double
        let textJP: String
        let textEN: String?

        enum CodingKeys: String, CodingKey {
            case index
            case startSec = "start_sec"
            case endSec = "end_sec"
            case textJP = "text_jp"
            case textEN = "text_en"
        }
    }

    nonisolated struct Token: Decodable, Sendable {
        let position: Int
        let sentenceIndex: Int
        let surface: String
        let reading: String?
        let startSec: Double
        let endSec: Double

        enum CodingKeys: String, CodingKey {
            case position
            case sentenceIndex = "sentence_index"
            case surface
            case reading
            case startSec = "start_sec"
            case endSec = "end_sec"
        }
    }

    enum CodingKeys: String, CodingKey {
        case clipID = "clip_id"
        case media
        case sentences
        case tokens
        case highlights
        case patterns
        case jlptLevel = "jlpt_level"
        case deprecated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clipID = try container.decode(String.self, forKey: .clipID)
        media = try container.decode(Media.self, forKey: .media)
        sentences = try container.decode([Sentence].self, forKey: .sentences)
        tokens = try container.decode([Token].self, forKey: .tokens)
        // Optional extras must never stop the clip from loading.
        highlights = try? container.decodeIfPresent(Highlights.self, forKey: .highlights)
        patterns = try? container.decodeIfPresent([TeachingPattern].self, forKey: .patterns)
        jlptLevel = try? container.decodeIfPresent(Int.self, forKey: .jlptLevel)
        // Any `deprecated` value counts, even one we can't read: never play a retired clip.
        if container.contains(.deprecated), (try? container.decodeNil(forKey: .deprecated)) != true {
            deprecated = (try? container.decode(Deprecation.self, forKey: .deprecated))
                ?? Deprecation(at: nil, reason: nil)
        } else {
            deprecated = nil
        }
    }
}

extension ClipPayload {
    /// App model for the shared highlights view; empty when the clip has none.
    var learningHighlights: DialogueLearningHighlights {
        let grammar = (highlights?.grammarPatterns ?? []).compactMap { pattern -> DialogueGrammarPatternRef? in
            guard !pattern.label.isEmpty else { return nil }
            return DialogueGrammarPatternRef(
                label: pattern.label,
                patternId: pattern.patternId,
                grammarPointID: pattern.grammarPointID,
                sourceSpokenStart: pattern.sourceSpokenStart,
                sourceSpokenEnd: pattern.sourceSpokenEnd
            )
        }
        let trimmed: ([String]?) -> [String] = { values in
            (values ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        return DialogueLearningHighlights(
            vocabulary: trimmed(highlights?.vocabulary),
            grammarPatterns: grammar,
            contextNotes: trimmed(highlights?.contextNotes)
        )
    }

    /// Pattern card for a grammar highlight: by patternId, then grammar point id.
    func teachingPattern(for pattern: DialogueGrammarPatternRef) -> DialogueTeachingPattern? {
        let cards = patterns ?? []
        let match = pattern.patternId.flatMap { id in cards.first { $0.id == id } }
            ?? pattern.grammarPointID.flatMap { id in cards.first { $0.id == id } }
        guard let match else { return nil }
        let description = match.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return DialogueTeachingPattern(
            id: match.id,
            label: match.label,
            description: (description?.isEmpty ?? true) ? nil : description,
            shortMeaning: match.shortMeaning,
            formNote: match.formNote
        )
    }

    /// Sentences as spoken scenario lines (for grammar detail + usage lookup).
    var scenarioLines: [GrammarScenarioLine] {
        sentences.map { GrammarScenarioLine(speaker: "", japanese: $0.textJP, english: $0.textEN) }
    }
}

extension ContentCMSClient {
    private nonisolated struct ClipListResponse: Decodable, Sendable {
        let clips: [ClipSummary]
    }

    /// `learnerLevel` (5 = N5 … 1 = N1): only clips rated at that level or
    /// easier; unrated clips are left out. Nil = every clip.
    static func fetchClipList(learnerLevel: Int? = nil) async throws -> [ClipSummary] {
        let query = learnerLevel.map { [URLQueryItem(name: "level", value: String($0))] } ?? []
        let data = try await fetchPublicClipData(path: ["clips"], query: query)
        return try JSONDecoder().decode(ClipListResponse.self, from: data).clips
    }

    static func fetchClip(id: String) async throws -> ClipPayload {
        let data = try await fetchPublicClipData(path: ["clips", id])
        return try JSONDecoder().decode(ClipPayload.self, from: data)
    }

    private static func fetchPublicClipData(
        path: [String],
        query: [URLQueryItem] = []
    ) async throws -> Data {
        guard let baseURL else { throw CMSClientError.notConfigured }
        var url = baseURL.appendingPathComponent("api").appendingPathComponent("public")
        for component in path {
            url = url.appendingPathComponent(component)
        }
        if !query.isEmpty {
            url.append(queryItems: query)
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CMSClientError.invalidResponse }
        guard (200 ... 299).contains(http.statusCode) else {
            throw CMSClientError.httpStatus(http.statusCode)
        }
        return data
    }
}
