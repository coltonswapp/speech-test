//
//  ClipFeedback.swift
//  shizen
//
//  Learner feedback on a clip: thumbs (Clip Details) and "Report an issue"
//  (Clip Details, and a line's breakdown screen with that line attached).
//  Posts to Studio `POST /api/client/clips/{id}/feedback`, which takes any
//  signed-in learner's Firebase ID token.
//

import FirebaseAuth
import Foundation

enum ClipFeedbackReason: String, CaseIterable {
    case translation
    case tokenization
    case reading
    case timing
    case video
    case other

    var title: String {
        switch self {
        case .translation: return "Bad translation"
        case .tokenization: return "Words split wrong"
        case .reading: return "Wrong reading"
        case .timing: return "Subtitles out of sync"
        case .video: return "Video problem"
        case .other: return "Something else"
        }
    }

    /// Reasons that point at one word, so the report offers a word picker.
    var isAboutAWord: Bool { self == .tokenization || self == .reading }
}

/// The line as the learner saw it. The server keeps it, since clips get re-aligned.
struct ClipLineSnapshot: Encodable {
    struct Token: Encodable {
        let position: Int
        let surface: String
        let reading: String?
    }

    let index: Int
    let startSec: Double
    let endSec: Double
    let textJP: String
    let textEN: String?
    let tokens: [Token]

    init(sentence: ClipPayload.Sentence, tokens: [ClipPayload.Token]) {
        index = sentence.index
        startSec = sentence.startSec
        endSec = sentence.endSec
        textJP = sentence.textJP
        textEN = sentence.textEN
        self.tokens = tokens.map { Token(position: $0.position, surface: $0.surface, reading: $0.reading) }
    }
}

enum ClipFeedbackClient {
    enum SendError: LocalizedError {
        case notSignedIn
        case notConfigured
        case server(Int)

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Sign in to send feedback."
            case .notConfigured: return "Feedback isn't available in this build."
            case .server(429): return "You've sent a lot of feedback today. Try again tomorrow."
            case .server: return "Couldn't send feedback. Try again in a moment."
            }
        }
    }

    private struct Body: Encodable {
        struct App: Encodable {
            let version: String?
            let build: String?
        }

        let kind: String
        var rating: String?
        var reason: String?
        var note: String?
        var line: ClipLineSnapshot?
        var tokenPosition: Int?
        let app = App(
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        )
    }

    /// A signed-in learner (or a DEBUG build with the QA token) can send feedback.
    static var canSend: Bool {
        if let user = Auth.auth().currentUser, !user.isAnonymous { return true }
        return !ContentQAClientToken.resolved.isEmpty
    }

    static func sendRating(clipID: String, rating: LLMFeedbackRating, reason: ClipFeedbackReason?) async throws {
        var body = Body(kind: "rating")
        body.rating = rating.rawValue
        body.reason = reason?.rawValue
        try await post(clipID: clipID, body: body)
    }

    static func reportIssue(
        clipID: String,
        reason: ClipFeedbackReason,
        note: String?,
        line: ClipLineSnapshot?,
        tokenPosition: Int?
    ) async throws {
        var body = Body(kind: "flag")
        body.reason = reason.rawValue
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        body.note = (trimmed?.isEmpty ?? true) ? nil : trimmed
        body.line = line
        body.tokenPosition = line == nil ? nil : tokenPosition
        try await post(clipID: clipID, body: body)
    }

    /// Thumbs for Clip Details. A thumbs-down asks which reason, and that becomes
    /// an open issue in Studio. Remembered per clip so the thumbs aren't shown again.
    static func ratingSubject(clipID: String) -> FeedbackThumbsSubject {
        FeedbackThumbsSubject(
            id: "clip:\(clipID)",
            reasons: ClipFeedbackReason.allCases.map { .init(id: $0.rawValue, title: $0.title) }
        ) { rating, reasonID in
            let reason = reasonID.flatMap(ClipFeedbackReason.init(rawValue:))
            ClipRatingMemory.markRated(clipID)
            Task {
                do {
                    try await sendRating(clipID: clipID, rating: rating, reason: reason)
                    var properties: [String: Any] = [
                        "clip_id": clipID,
                        "rating": rating.rawValue,
                    ]
                    if let reason { properties["reason"] = reason.rawValue }
                    Analytics.track(.clipRated, properties)
                } catch {
                    print("[ClipFeedback] rating for \(clipID) failed: \(error)")
                }
            }
        }
    }

    private static func post(clipID: String, body: Body) async throws {
        guard let baseURL = ContentCMSClient.baseURL else { throw SendError.notConfigured }
        guard let bearer = await bearer() else { throw SendError.notSignedIn }
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("client")
            .appendingPathComponent("clips")
            .appendingPathComponent(clipID)
            .appendingPathComponent("feedback")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SendError.notSignedIn }
        guard (200 ... 299).contains(status) else { throw SendError.server(status) }
    }

    /// The learner's own ID token first, so feedback is attributed to them;
    /// the DEBUG QA token only when signed out.
    private static func bearer() async -> String? {
        if let user = Auth.auth().currentUser, !user.isAnonymous,
           let token = try? await user.getIDToken() {
            return token
        }
        let qa = ContentQAClientToken.resolved
        return qa.isEmpty ? nil : qa
    }
}

/// Clips this device already rated, so Clip Details doesn't ask twice.
enum ClipRatingMemory {
    private static let key = "clipFeedbackRatedClipIds"

    static func hasRated(_ clipID: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(clipID)
    }

    static func markRated(_ clipID: String) {
        var ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !ids.contains(clipID) else { return }
        ids.append(clipID)
        if ids.count > 500 { ids.removeFirst(ids.count - 500) }
        UserDefaults.standard.set(ids, forKey: key)
    }
}
