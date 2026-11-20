//
//  ShizenNoteFormat.swift
//  shizen
//
//  CSFeedbackKit format "shizenNote": the body Studio's existing QA note endpoint
//  (/api/client/content-qa/notes) takes, with the same note text the old QA sheet
//  built. Studio then stores the screenshot in R2 and delivers to Shohei as before.
//  Keep in sync with webapp/lib/shizen-notes/schema.ts.
//

import Foundation
import CSFeedbackKitUI

nonisolated struct ShizenNoteBody: Encodable, Sendable {
    nonisolated struct Metadata: Encodable, Sendable {
        let url: String
        let created_at: String
        let screenshot_jpeg: String?
    }

    /// dialogue | quiz | screen
    let source: String
    let source_id: String
    let title: String?
    let note: String
    /// shohei | vikram | hana. Studio defaults to shohei.
    let agent: String?
    let metadata: Metadata

    init(_ payload: FeedbackPayload) {
        let custom = payload.custom
        func text(_ key: String) -> String? {
            guard case .string(let value)? = custom[key] else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        let screen = payload.source?.screen ?? "Unknown"
        let qaSource = text("qaSource") ?? "screen"
        let focusTitle = text("focusTitle") ?? payload.source?.title ?? screen
        let studioLink = text("studioLink")

        // Same lines as DialogueContentQANoteViewController.contextLines().
        var context = ["Looking at: \(focusTitle)"]
        if case .strings(let focus)? = custom["focus"] {
            context += focus
        }
        if qaSource == "screen" {
            context.append("Type: \(screen)")
            // Screens with their own Studio page (e.g. Clip Details) still link it.
            if let studioLink {
                context.append("Studio: \(studioLink)")
            }
        } else {
            context.append("")
            if let lessonId = text("lessonId") {
                context.append("Lesson: \(text("lessonTitle") ?? lessonId) (\(lessonId))")
            }
            if let sceneTitle = text("sceneTitle"), let sceneSlug = text("sceneSlug") {
                context.append("Scene: \(sceneTitle) (\(sceneSlug))")
            }
            if let studioLink {
                context.append("Studio: \(studioLink)")
            }
        }
        var build = "Build: \(payload.app.version) (\(payload.app.build)), \(payload.app.environment.rawValue)"
        if let device = payload.device {
            build += ", \(device.model), \(device.os)"
        }
        context.append(build)

        // Same order as the old webhookNoteText(): tags, note, context.
        var lines: [String] = []
        if !payload.tags.isEmpty {
            lines += ["Tags: " + payload.tags.map(\.label).joined(separator: " "), ""]
        }
        lines += [payload.note, ""] + context

        source = qaSource
        source_id = text("sourceId") ?? text("lessonId") ?? text("clipId") ?? screen
        title = focusTitle
        note = lines.joined(separator: "\n")
        agent = text("agent")
        metadata = Metadata(
            url: studioLink ?? "screen/\(screen)",
            created_at: payload.createdAt,
            screenshot_jpeg: payload.attachments.first { $0.kind == .screenshot }?.data
        )
    }
}
