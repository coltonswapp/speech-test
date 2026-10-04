//
//  LessonFeedback.swift
//  shizen
//
//  1–5 ratings for a finished dialogue scene. Asked on a sample of
//  completions and sent once when the learner leaves the rating page.
//

import Foundation

enum LessonFeedbackDimension: String, CaseIterable {
    case audio
    case content
    case highlighting
    case quiz

    var title: String {
        switch self {
        case .audio: return "Audio quality"
        case .content: return "Content"
        case .highlighting: return "Word highlighting"
        case .quiz: return "Quiz"
        }
    }

    var prompt: String {
        switch self {
        case .audio: return "Was the voice clear and natural?"
        case .content: return "Was the conversation useful and realistic?"
        case .highlighting: return "Did the highlights keep up with the audio?"
        case .quiz: return "Were the questions fair?"
        }
    }
}

/// Which scene and take was rated, plus how the learner scored on it.
struct LessonFeedbackContext {
    let collectionId: String
    let scenarioId: String
    let publishedVariantId: String?
    let publishedContentHash: String?
    let correctCount: Int
    let questionCount: Int
    let starCount: Int
    let englishPeekedCount: Int
}

/// Asks on about every third completed attempt. A rated take is not asked again.
enum LessonFeedbackPrompt {
    private static let countKey = "lessonFeedbackOfferCount"
    private static let ratedKey = "lessonFeedbackRatedKeys"
    private static let askEvery = 3

    static func shouldOffer(_ context: LessonFeedbackContext) -> Bool {
        guard LLMGatewayClient.isAvailable, !hasRated(context) else { return false }
        let count = UserDefaults.standard.integer(forKey: countKey) + 1
        UserDefaults.standard.set(count, forKey: countKey)
        return count.isMultiple(of: askEvery)
    }

    static func markRated(_ context: LessonFeedbackContext) {
        var items = UserDefaults.standard.stringArray(forKey: ratedKey) ?? []
        let key = ratedKey(for: context)
        guard !items.contains(key) else { return }
        items.append(key)
        if items.count > 400 {
            items.removeFirst(items.count - 400)
        }
        UserDefaults.standard.set(items, forKey: ratedKey)
    }

    private static func hasRated(_ context: LessonFeedbackContext) -> Bool {
        let items = UserDefaults.standard.stringArray(forKey: ratedKey) ?? []
        return items.contains(ratedKey(for: context))
    }

    /// Includes the content hash so a re-recorded take can be asked about again.
    private static func ratedKey(for context: LessonFeedbackContext) -> String {
        "\(context.collectionId)/\(context.scenarioId)|\(context.publishedContentHash ?? "")"
    }
}

extension LLMGatewayClient {

    private struct LessonFeedbackBody: Encodable {
        struct Score: Encodable {
            let correct: Int
            let total: Int
            let stars: Int
        }

        let attemptId: String
        let collectionId: String
        let scenarioId: String
        let publishedVariantId: String?
        let publishedContentHash: String?
        let ratings: [String: Int]
        let score: Score
        let englishPeeks: Int
        let appVersion: String?
        let deviceId: String
    }

    /// Failures are swallowed. The attempt id makes a retry a no-op on the server.
    static func postLessonFeedback(
        _ context: LessonFeedbackContext,
        ratings: [LessonFeedbackDimension: Int]
    ) async {
        let clamped = ratings.filter { (1...5).contains($0.value) }
        guard !clamped.isEmpty else { return }
        let body = LessonFeedbackBody(
            attemptId: UUID().uuidString.lowercased(),
            collectionId: context.collectionId,
            scenarioId: context.scenarioId,
            publishedVariantId: context.publishedVariantId,
            publishedContentHash: context.publishedContentHash,
            ratings: Dictionary(uniqueKeysWithValues: clamped.map { ($0.key.rawValue, $0.value) }),
            score: .init(
                correct: context.correctCount,
                total: context.questionCount,
                stars: context.starCount
            ),
            englishPeeks: context.englishPeekedCount,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            deviceId: LLMFeedbackDevice.id
        )
        do {
            let _: LessonFeedbackAck = try await post("v1/lesson-feedback", body: body)
        } catch {
            print("[LessonFeedback] send failed: \(error)")
        }
    }

    private struct LessonFeedbackAck: Decodable {
        let ok: Bool
    }
}
