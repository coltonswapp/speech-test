//
//  ListenFirstPracticeStep.swift
//  shizen
//
//  Screen 5 · The whole conversation, every line swipeable and nothing prompted. Once they've
//  tried a swipe, the replay appears: same audio as the blind listen, so they can hear how much
//  more they catch now.
//

import NNKit
import UIKit

final class ListenFirstPracticeStepViewController: ListenFirstStepViewController {

    override var progressBeatCount: Int { 3 }

    private static let idleLineAlpha: CGFloat = 0.35

    private let voice = NaturalVoicePlayer()
    private let playButton = GlassIconButton(
        symbolName: "play.fill",
        pointSize: 22,
        glyphDimension: 26,
        tintColor: .systemYellow,
        accessibilityLabel: "Play conversation"
    )
    private var chat: TutorChatView?
    private var lines: [TutorSwipeLine] = []
    private var isPlaying = false
    private var hasTriedSwipe = false
    private var hasHeardOnce = false

    override func buildStage() {
        setupOnboarding(title: "Now try the whole thing.", subtitle: ListenFirstContent.sceneTitle)
        isPlaying = false
        hasTriedSwipe = false
        hasHeardOnce = false

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

        lines = ListenFirstContent.conversation.map { makeLine($0, in: chat) }

        playButton.setSymbol("play.fill")
        playButton.removeTarget(nil, action: nil, for: .allEvents)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        playButton.translatesAutoresizingMaskIntoConstraints = false
    }

    private func makeLine(_ conversationLine: ListenFirstLine, in chat: TutorChatView) -> TutorSwipeLine {
        let line = TutorLine(listen.defaultText(conversationLine), conversationLine.english)
        let swipeLine = TutorSwipeLine(line: line, side: conversationLine.speaker == 1 ? .trailing : .leading)
        swipeLine.hostScrollView = chat.scrollContainer
        swipeLine.isRevealEnabled = true
        swipeLine.onFirstReveal = { [weak self] in self?.didTrySwipe() }
        if let open = breakdownAction(for: line, onDismiss: { [weak self] in self?.didTrySwipe() }) {
            swipeLine.onBreakdown = { [weak self] in
                self?.stopPlayback()
                open()
            }
        }
        return swipeLine
    }

    override func play() {
        guard let chat else { return }
        timeline.after(0.3) { [weak self] in
            chat.play([
                .tutorText("Here's the whole conversation. Left for the English, right to take a line apart."),
            ]) { [weak self] in
                guard let self else { return }
                let rows = zip(ListenFirstContent.conversation, self.lines).map { conversationLine, swipeLine in
                    conversationLine.speaker == 1
                        ? TutorChatView.userRow(content: swipeLine)
                        : TutorChatView.tutorRow(content: swipeLine, avatar: .none)
                }
                chat.appendCustom(rows, stagger: 0.08, scrollDuration: 0.5)
                self.hintUntilTried(attempt: 0)
            }
        }
    }

    override func resetStage() {
        stopPlayback()
        super.resetStage()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPlayback()
    }

    /// Tugs the first line left, then right, until they've tried either swipe on any line.
    private func hintUntilTried(attempt: Int) {
        timeline.after(attempt == 0 ? 1.0 : 2.5) { [weak self] in
            guard let self, !self.hasTriedSwipe, let line = self.lines.first else { return }
            if self.presentedViewController == nil {
                line.playHint(attempt.isMultiple(of: 2) ? .revealEnglish : .breakdown, strength: 0.85)
                HapticsHelper.superLightHaptic()
            }
            self.hintUntilTried(attempt: attempt + 1)
        }
    }

    private func didTrySwipe() {
        guard !hasTriedSwipe else { return }
        hasTriedSwipe = true
        advanceProgressBeat(to: 1)
        timeline.after(0.4) { [weak self] in
            self?.chat?.play([
                .tutorText("That's it. Now hear it again and see how much more you catch."),
            ]) { [weak self] in
                self?.showPlayButton()
            }
        }
    }

    private func showPlayButton() {
        let row = UIView()
        row.addSubview(playButton)
        NSLayoutConstraint.activate([
            playButton.widthAnchor.constraint(equalToConstant: 56),
            playButton.heightAnchor.constraint(equalToConstant: 56),
            playButton.centerXAnchor.constraint(equalTo: row.centerXAnchor),
            playButton.topAnchor.constraint(equalTo: row.topAnchor),
            playButton.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        chat?.appendCustom(row)
        slideIn([row])
    }

    // MARK: Replay

    @objc private func playTapped() {
        HapticsHelper.lightHaptic()
        guard !isPlaying else {
            stopPlayback()
            return
        }
        isPlaying = true
        playButton.setSymbol("stop.fill")
        playLine(0)
    }

    private func playLine(_ index: Int) {
        guard isPlaying, ListenFirstContent.conversation.indices.contains(index) else {
            finishPlayback()
            return
        }
        focus(on: index)
        voice.play(ListenFirstContent.lineClip(at: index)) { [weak self] in
            self?.timeline.after(0.15) { [weak self] in
                self?.playLine(index + 1)
            }
        }
    }

    private func focus(on index: Int?) {
        UIView.animate(withDuration: AnimationDefaults.fastDuration) {
            for (offset, line) in self.lines.enumerated() {
                line.alpha = index == nil || offset == index ? 1 : Self.idleLineAlpha
            }
        }
    }

    private func stopPlayback() {
        isPlaying = false
        voice.stop()
        focus(on: nil)
        playButton.setSymbol(hasHeardOnce ? "arrow.counterclockwise" : "play.fill")
    }

    private func finishPlayback() {
        let isFirstListen = !hasHeardOnce
        hasHeardOnce = true
        stopPlayback()
        guard isFirstListen else { return }
        advanceProgressBeat(to: 2)
        chat?.play([
            .tutorText("That's how every lesson works: listen, take it apart, listen again."),
        ]) { [weak self] in
            self?.revealCTA("Next")
        }
    }
}
