//
//  LessonIssueReport.swift
//  shizen
//
//  Learner "Report a problem" for a dialogue scene. Available from the lesson
//  menu at any point, and sent with whatever the learner was looking at.
//

import Foundation

enum LessonIssueCategory: String, CaseIterable {
    case audio
    case timing
    case translation
    case content
    case quiz
    case bug
    case other

    var title: String {
        switch self {
        case .audio: return "Wrong audio"
        case .timing: return "Timing"
        case .translation: return "Translation"
        case .content: return "Japanese text"
        case .quiz: return "Quiz"
        case .bug: return "Something broke"
        case .other: return "Other"
        }
    }
}

enum LessonIssuePage: String {
    case dialogue
    case quiz
    case highlights
}

enum LessonIssueTone {
    case reportProblem
    case feedback
}

/// The scene and spot the learner was on when they opened the report.
struct LessonIssueContext {
    let collectionId: String
    let scenarioId: String
    let publishedVariantId: String?
    let publishedContentHash: String?
    let page: LessonIssuePage
    let focusTitle: String
    let focusDetails: [String]
    let sessionMode: String
    let quizQuestionNumber: Int?
    let tone: LessonIssueTone

    init(
        collectionId: String,
        scenarioId: String,
        publishedVariantId: String?,
        publishedContentHash: String?,
        page: LessonIssuePage,
        focusTitle: String,
        focusDetails: [String],
        sessionMode: String,
        quizQuestionNumber: Int?,
        tone: LessonIssueTone = .reportProblem
    ) {
        self.collectionId = collectionId
        self.scenarioId = scenarioId
        self.publishedVariantId = publishedVariantId
        self.publishedContentHash = publishedContentHash
        self.page = page
        self.focusTitle = focusTitle
        self.focusDetails = focusDetails
        self.sessionMode = sessionMode
        self.quizQuestionNumber = quizQuestionNumber
        self.tone = tone
    }
}

extension LLMGatewayClient {

    private struct LessonReportBody: Encodable {
        let reportId: String
        let collectionId: String
        let scenarioId: String
        let publishedVariantId: String?
        let publishedContentHash: String?
        let page: String
        let focusTitle: String
        let focusDetails: [String]
        let sessionMode: String
        let quizQuestionNumber: Int?
        let categories: [String]
        let note: String?
        let appVersion: String?
        let osVersion: String
        let deviceId: String
    }

    private struct LessonReportAck: Decodable {
        let ok: Bool
    }

    /// Throws so the sheet can keep the learner's text on failure.
    static func postLessonReport(
        _ context: LessonIssueContext,
        categories: [LessonIssueCategory],
        note: String
    ) async throws {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = LessonReportBody(
            reportId: UUID().uuidString.lowercased(),
            collectionId: context.collectionId,
            scenarioId: context.scenarioId,
            publishedVariantId: context.publishedVariantId,
            publishedContentHash: context.publishedContentHash,
            page: context.page.rawValue,
            focusTitle: String(context.focusTitle.prefix(200)),
            focusDetails: context.focusDetails.prefix(20).map { String($0.prefix(300)) },
            sessionMode: context.sessionMode,
            quizQuestionNumber: context.quizQuestionNumber,
            categories: categories.map(\.rawValue),
            note: trimmedNote.isEmpty ? nil : String(trimmedNote.prefix(2000)),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            osVersion: osVersion,
            deviceId: LLMFeedbackDevice.id
        )
        let _: LessonReportAck = try await post("v1/lesson-report", body: body)
    }

    private static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
