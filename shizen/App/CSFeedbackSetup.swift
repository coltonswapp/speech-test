//
//  CSFeedbackSetup.swift
//  shizen
//
//  Wires CSFeedbackKit (github.com/coltonswapp/CSFeedbackKit) with config shizen/CSFeedback.json.
//  CSFeedback.json: notes go to Studio's existing QA note endpoint in the "shizenNote"
//  format (ShizenNoteFormat.swift), so Studio → R2 → Shohei works exactly as before.
//  CSFeedback.OpenBot.json: layered on only when OPENBOT_WEBHOOK_URL / _SECRET are in
//  Secrets.plist. The screenshot is uploaded once via Studio's signer
//  (/api/client/feedback-uploads) and OpenBot gets the download link.
//  Xcode builds only for now. A screenshot offers the composer; screens add context through
//  FeedbackContextProvider (lesson picker, lesson player, sentence breakdown, clip feed/player,
//  clip details). The old QA note
//  still opens from the QA menus. Notes that fail wait in Settings → Debug → Feedback queue.
//

import UIKit
import CSFeedbackKitUI

enum CSFeedbackSetup {
    @MainActor
    static func start() {
        var layers = ["CSFeedback"]
        var variables: [String: String] = [:]
        if let url = SecretsPlist.value(for: "OPENBOT_WEBHOOK_URL"),
           let secret = SecretsPlist.value(for: "OPENBOT_WEBHOOK_SECRET") {
            layers.append("CSFeedback.OpenBot")
            variables["OPENBOT_WEBHOOK_URL"] = url
            variables["OPENBOT_WEBHOOK_SECRET"] = secret
        }

        Feedback.start(
            config: .merged(layers),
            variables: variables,
            auth: [
                // Same bearer as the old QA note: DEBUG QA token, else the staff ID token.
                "staff": {
                    let token: String? = await withCheckedContinuation { continuation in
                        Task { @MainActor in
                            StaffAccess.studioClientBearer { continuation.resume(returning: $0) }
                        }
                    }
                    guard let token, !token.isEmpty else { throw URLError(.userAuthenticationRequired) }
                    return ["Authorization": "Bearer \(token)"]
                },
            ],
            checks: [
                "staffAccess": { StaffAccess.canUseStudioClientAPI },
            ],
            formats: [
                "shizenNote": { ShizenNoteBody($0) },
            ]
        )
        // Screenshot → "QA this screen?" → composer (CSFeedback.json "triggers").
        Feedback.installTriggers()
        // Not over the old QA note sheet, which still opens from the QA menus.
        Feedback.shouldOfferScreenshotPrompt = { screen in
            !(screen is DialogueContentQANoteViewController)
                && !(screen.navigationController?.viewControllers.contains { $0 is DialogueContentQANoteViewController } ?? false)
        }

        Feedback.appearance = FeedbackAppearance(
            pageBackground: ExperimentPalette.pageBackground,
            sendButton: .yellow,
            configureSheet: { sheet in
                sheet.applySolidNonLargeBackground(ExperimentPalette.pageBackground)
            },
            showToast: { presenter, toast in
                presenter.showToast(text: toast.text, sentiment: toast.kind == .error ? .negative : .positive)
            }
        )
    }
}
