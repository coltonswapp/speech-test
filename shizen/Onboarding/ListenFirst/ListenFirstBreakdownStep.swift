//
//  ListenFirstBreakdownStep.swift
//  shizen
//
//  Screen 5 · Every line comes apart. One line from the conversation, Japanese only, and
//  the two lesson gestures in order: swipe left for the English, then swipe right to take
//  it apart in the lesson's real breakdown screen (scripted, so nothing calls the gateway).
//

import NNKit
import UIKit

final class ListenFirstBreakdownStepViewController: ListenFirstStepViewController {

    override var progressBeatCount: Int { 3 }

    /// Mika's "gotta go" line: new English, and なきゃ and ちゃう to dissect.
    private static let lineIndex = 2

    private var chat: TutorChatView?
    private var swipeLine: TutorSwipeLine?
    private var hasFinished = false

    private var line: TutorLine {
        let line = ListenFirstContent.conversation[Self.lineIndex]
        return TutorLine(listen.defaultText(line), line.english)
    }

    private var isTrailing: Bool {
        ListenFirstContent.conversation[Self.lineIndex].speaker == 1
    }

    override func buildStage() {
        setupOnboarding(title: "Every line comes apart.", subtitle: ListenFirstContent.sceneTitle)
        hasFinished = false

        let chat = makeChat()
        stage.addSubview(chat)
        NSLayoutConstraint.activate([
            chat.topAnchor.constraint(equalTo: stage.topAnchor),
            chat.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            chat.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            chat.bottomAnchor.constraint(equalTo: stage.bottomAnchor),
        ])
        self.chat = chat
        scrollUnderHeader(chat, scrollView: chat.scrollContainer)

        let swipeLine = TutorSwipeLine(line: line, side: isTrailing ? .trailing : .leading)
        swipeLine.hostScrollView = chat.scrollContainer
        swipeLine.onFirstReveal = { [weak self] in self?.askForBreakdown() }
        self.swipeLine = swipeLine
    }

    override func play() {
        guard let chat, let swipeLine else { return }
        timeline.after(0.3) { [weak self] in
            chat.play([
                .tutorText("Here's another line from that conversation. No English this time."),
            ]) { [weak self] in
                guard let self else { return }
                chat.appendCustom(self.isTrailing
                    ? TutorChatView.userRow(content: swipeLine)
                    : TutorChatView.tutorRow(content: swipeLine, avatar: .none))
                HapticsHelper.superLightHaptic()
                self.timeline.after(0.6) { [weak self] in self?.askForEnglish() }
            }
        }
    }

    private func askForEnglish() {
        chat?.play([.tutorText("Swipe left on it to see the English.")]) { [weak self] in
            guard let self, let swipeLine = self.swipeLine else { return }
            swipeLine.isRevealEnabled = true
            self.nudge(swipeLine, toward: .revealEnglish, after: 1.4)
        }
    }

    /// The right swipe only switches on once the English is out, so the two come in order.
    private func askForBreakdown() {
        advanceProgressBeat(to: 1)
        timeline.after(0.6) { [weak self] in
            self?.chat?.play([.tutorText("Now swipe right to take it apart.")]) { [weak self] in
                guard let self, let swipeLine = self.swipeLine,
                      let script = ListenFirstContent.breakdowns[self.line.japanese] else { return }
                let line = self.line
                swipeLine.onBreakdown = { [weak self] in
                    self?.presentBreakdown(of: line, script: script) { [weak self] in
                        self?.finish()
                    }
                }
                self.nudge(swipeLine, toward: .breakdown, after: 1.4)
            }
        }
    }

    /// After the first breakdown closes: one line of payoff, then on.
    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        advanceProgressBeat(to: 2)
        timeline.after(0.3) { [weak self] in
            self?.chat?.play([
                .tutorText("Left for the English, right to take it apart. Every line in a lesson works this way."),
            ]) { [weak self] in
                self?.revealCTA("Next")
            }
        }
    }
}
