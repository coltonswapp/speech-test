//
//  RepeatAfterMeViewController.swift
//  shizen
//
//  Listen & Repeat: target sentence + play, then an embedded Realtime tutor
//  harness at the bottom for a single speaking turn.
//

import AVFoundation
import UIKit

final class RepeatAfterMeViewController: UIViewController {

    private enum Phase {
        case listen
        case speak
        case finished
    }

    private let sentence: String
    private let englishTranslation: String?
    private let recordedClip: RealtimeAudioClip?
    private let dialogueLineAudio: DialogueLineAudioReference?

    private let grammarAudioPlayer = GrammarAudioPlayer()
    private var fallbackSpeaker: RepeatAfterMeSpeechSpeaker?

    private let sentenceLabel = FuriganaTranscriptLabel()
    private lazy var sentenceBubble = DialogueJapaneseBubbleView(label: sentenceLabel)
    private let sentenceActionsContainer = UIView()
    /// Transform/alpha hosts so glass `UIButton` chrome doesn't swallow the motion.
    private let playMotionView = UIView()
    private let retryMotionView = UIView()
    private let playButton = UIButton(type: .system)
    private let playGlyphView = UIImageView()
    private let retryButton = UIButton(type: .system)
    private let retryGlyphView = UIImageView()
    private let englishLabel = UILabel()
    private var isRetryButtonVisible = false

    private let feedbackCard = UIView()
    private let attemptsStack = UIStackView()
    private var attemptEntries: [AttemptEntry] = []

    private lazy var tutorHarness = RealtimeTutorHarnessView(
        configuration: RealtimeTutorPrompt.repeatAfterMeConfiguration(targetSentence: sentence)
    )

    private var phase: Phase = .listen
    private var isPlayingReference = false
    private var showsTutorTranscript = true
    /// Session chrome + realtime connect stay off until the first play tap.
    private var hasStartedSession = false

    private static let actionButtonSize: CGFloat = 56
    private static let bubbleActionSpacing: CGFloat = 6
    private static let actionGlyphColor = UIColor.systemYellow
    private static let actionSlideDistance: CGFloat = 96
    private static let actionAnimationDuration: TimeInterval = 0.38
    private static let attemptBubbleMaxWidthRatio: CGFloat = 0.82

    private struct AttemptEntry {
        let container: UIStackView
        let feedbackLabel: UILabel
    }

    // MARK: - Init

    init(
        sentence: String,
        englishTranslation: String? = nil,
        recordedClip: RealtimeAudioClip? = nil,
        dialogueLineAudio: DialogueLineAudioReference? = nil
    ) {
        self.sentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEnglish = englishTranslation?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.englishTranslation = (trimmedEnglish?.isEmpty ?? true) ? nil : trimmedEnglish
        self.recordedClip = recordedClip
        self.dialogueLineAudio = dialogueLineAudio
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        title = "Listen & Repeat"
        navigationItem.subtitle = "Imitate what you hear & get feedback"

        tutorHarness.delegate = self
        configureHierarchy()
        configureOptionsMenu()
        refreshSentenceDisplay()
        setPhase(.listen, animated: false)
        setTutorHarnessVisible(false, animated: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || isBeingDismissed {
            stopReferenceAudio()
            tutorHarness.disconnect()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playButton.bringSubviewToFront(playGlyphView)
        retryButton.bringSubviewToFront(retryGlyphView)
    }

    // MARK: - Layout

    private func configureHierarchy() {
        sentenceLabel.translatesAutoresizingMaskIntoConstraints = false
        sentenceLabel.numberOfLines = 0
        sentenceLabel.textAlignment = .natural
        sentenceLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        sentenceLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        sentenceBubble.setBackgroundStyle(.glass)
        sentenceBubble.setEmphasis(1)
        sentenceBubble.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        sentenceBubble.setContentCompressionResistancePriority(.required, for: .horizontal)

        Self.configureGlassActionButton(
            playButton,
            glyphView: playGlyphView,
            symbolName: "play.fill",
            accessibilityLabel: "Play sentence"
        )
        playButton.addAction(UIAction { [weak self] _ in
            self?.playButtonTapped()
        }, for: .primaryActionTriggered)

        Self.configureGlassActionButton(
            retryButton,
            glyphView: retryGlyphView,
            symbolName: "arrow.counterclockwise",
            accessibilityLabel: "Try again"
        )
        retryButton.accessibilityHint = "Listen again and repeat the sentence"
        retryButton.addAction(UIAction { [weak self] _ in
            self?.retryButtonTapped()
        }, for: .primaryActionTriggered)

        playMotionView.translatesAutoresizingMaskIntoConstraints = false
        playMotionView.clipsToBounds = false
        playMotionView.addSubview(playButton)

        retryMotionView.translatesAutoresizingMaskIntoConstraints = false
        retryMotionView.clipsToBounds = false
        retryMotionView.alpha = 0
        retryMotionView.isUserInteractionEnabled = false
        retryMotionView.transform = CGAffineTransform(translationX: Self.actionSlideDistance, y: 0)
        retryMotionView.addSubview(retryButton)

        sentenceActionsContainer.translatesAutoresizingMaskIntoConstraints = false
        sentenceActionsContainer.clipsToBounds = false
        sentenceActionsContainer.addSubview(playMotionView)

        let sentenceRowSpacer = UIView()
        sentenceRowSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sentenceRowSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Bubble + play sit together on the leading side; spacer absorbs trailing slack.
        let sentenceRow = UIStackView(arrangedSubviews: [
            sentenceBubble,
            sentenceActionsContainer,
            sentenceRowSpacer,
        ])
        sentenceRow.axis = .horizontal
        sentenceRow.alignment = .center
        sentenceRow.spacing = Self.bubbleActionSpacing
        sentenceRow.clipsToBounds = false
        sentenceRow.translatesAutoresizingMaskIntoConstraints = false

        englishLabel.translatesAutoresizingMaskIntoConstraints = false
        englishLabel.font = .preferredFont(forTextStyle: .subheadline)
        englishLabel.textColor = .secondaryLabel
        englishLabel.textAlignment = .natural
        englishLabel.numberOfLines = 0
        englishLabel.text = englishTranslation
        englishLabel.isHidden = englishTranslation == nil

        configureFeedbackCard()

        let headerStack = UIStackView(arrangedSubviews: [
            sentenceRow,
            englishLabel,
            feedbackCard,
        ])
        headerStack.axis = .vertical
        headerStack.alignment = .fill
        headerStack.spacing = 10
        headerStack.clipsToBounds = false
        if englishTranslation == nil {
            headerStack.setCustomSpacing(22, after: sentenceRow)
        } else {
            headerStack.setCustomSpacing(10, after: sentenceRow)
            headerStack.setCustomSpacing(22, after: englishLabel)
        }
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerStack)
        view.addSubview(tutorHarness)
        tutorHarness.setTrailingAccessory(retryMotionView)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            headerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            sentenceActionsContainer.widthAnchor.constraint(equalToConstant: Self.actionButtonSize),
            sentenceActionsContainer.heightAnchor.constraint(equalToConstant: Self.actionButtonSize),

            playMotionView.topAnchor.constraint(equalTo: sentenceActionsContainer.topAnchor),
            playMotionView.leadingAnchor.constraint(equalTo: sentenceActionsContainer.leadingAnchor),
            playMotionView.trailingAnchor.constraint(equalTo: sentenceActionsContainer.trailingAnchor),
            playMotionView.bottomAnchor.constraint(equalTo: sentenceActionsContainer.bottomAnchor),

            playButton.topAnchor.constraint(equalTo: playMotionView.topAnchor),
            playButton.leadingAnchor.constraint(equalTo: playMotionView.leadingAnchor),
            playButton.trailingAnchor.constraint(equalTo: playMotionView.trailingAnchor),
            playButton.bottomAnchor.constraint(equalTo: playMotionView.bottomAnchor),

            retryButton.topAnchor.constraint(equalTo: retryMotionView.topAnchor),
            retryButton.leadingAnchor.constraint(equalTo: retryMotionView.leadingAnchor),
            retryButton.trailingAnchor.constraint(equalTo: retryMotionView.trailingAnchor),
            retryButton.bottomAnchor.constraint(equalTo: retryMotionView.bottomAnchor),

            tutorHarness.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            tutorHarness.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            tutorHarness.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -20
            ),
            tutorHarness.topAnchor.constraint(
                greaterThanOrEqualTo: headerStack.bottomAnchor,
                constant: 24
            ),
        ])
    }

    private func configureFeedbackCard() {
        feedbackCard.translatesAutoresizingMaskIntoConstraints = false
        feedbackCard.isHidden = true
        feedbackCard.clipsToBounds = false

        attemptsStack.axis = .vertical
        attemptsStack.alignment = .fill
        attemptsStack.spacing = 16
        attemptsStack.clipsToBounds = false
        attemptsStack.translatesAutoresizingMaskIntoConstraints = false
        feedbackCard.addSubview(attemptsStack)

        NSLayoutConstraint.activate([
            attemptsStack.topAnchor.constraint(equalTo: feedbackCard.topAnchor),
            attemptsStack.leadingAnchor.constraint(equalTo: feedbackCard.leadingAnchor),
            attemptsStack.trailingAnchor.constraint(equalTo: feedbackCard.trailingAnchor),
            attemptsStack.bottomAnchor.constraint(equalTo: feedbackCard.bottomAnchor),
        ])
    }

    private func configureOptionsMenu() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: nil,
            image: UIImage(systemName: "ellipsis.circle"),
            primaryAction: nil,
            menu: makeOptionsMenu()
        )
    }

    private func makeOptionsMenu() -> UIMenu {
        let transcriptToggle = UIAction(
            title: "Show tutor feedback",
            state: showsTutorTranscript ? .on : .off
        ) { [weak self] _ in
            guard let self else { return }
            self.showsTutorTranscript.toggle()
            self.refreshTutorTranscriptVisibility()
            self.refreshOptionsMenu()
        }

        let harshToggle = UIAction(
            title: "Harsh mode",
            state: ExperimentSettings.repeatAfterMeHarshMode ? .on : .off
        ) { [weak self] _ in
            guard let self else { return }
            ExperimentSettings.repeatAfterMeHarshMode.toggle()
            self.tutorHarness.applyConfiguration(
                RealtimeTutorPrompt.repeatAfterMeConfiguration(targetSentence: self.sentence)
            )
            self.refreshOptionsMenu()
        }

        let selectedLimit = ExperimentSettings.repeatAfterMeReplyLimit
        let replyLimitActions = RepeatAfterMeReplyLimit.allCases.map { limit in
            UIAction(
                title: limit.title,
                state: limit == selectedLimit ? .on : .off
            ) { [weak self] _ in
                guard let self else { return }
                ExperimentSettings.repeatAfterMeReplyLimit = limit
                self.tutorHarness.applyConfiguration(
                    RealtimeTutorPrompt.repeatAfterMeConfiguration(targetSentence: self.sentence)
                )
                self.refreshOptionsMenu()
            }
        }
        let replyLimitMenu = UIMenu(
            title: "Replies before end",
            options: .singleSelection,
            children: replyLimitActions
        )

        return UIMenu(children: [transcriptToggle, harshToggle, replyLimitMenu])
    }

    private func hasTutorFeedbackText(_ label: UILabel) -> Bool {
        !(label.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private func refreshOptionsMenu() {
        navigationItem.rightBarButtonItem?.menu = makeOptionsMenu()
    }

    private static func configureGlassActionButton(
        _ button: UIButton,
        glyphView: UIImageView,
        symbolName: String,
        accessibilityLabel: String
    ) {
        var config = UIButton.Configuration.glass()
        config.cornerStyle = .capsule
        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = accessibilityLabel

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        glyphView.image = UIImage(systemName: symbolName, withConfiguration: symbolConfig)?
            .withRenderingMode(.alwaysTemplate)
        glyphView.tintColor = actionGlyphColor
        glyphView.preferredSymbolConfiguration = symbolConfig
        glyphView.contentMode = .scaleAspectFit
        glyphView.isUserInteractionEnabled = false
        glyphView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(glyphView)

        NSLayoutConstraint.activate([
            glyphView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            glyphView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            glyphView.widthAnchor.constraint(equalToConstant: 28),
            glyphView.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    // MARK: - Action button motion

    private func showRetryButton(animated: Bool) {
        guard !isRetryButtonVisible else { return }
        isRetryButtonVisible = true

        retryMotionView.isHidden = false
        retryMotionView.isUserInteractionEnabled = false
        retryMotionView.transform = CGAffineTransform(translationX: Self.actionSlideDistance, y: 0)
        retryMotionView.alpha = 0

        let applyEndState = {
            self.retryMotionView.transform = .identity
            self.retryMotionView.alpha = 1
            self.retryMotionView.isUserInteractionEnabled = true
        }

        guard animated else {
            applyEndState()
            return
        }

        UIView.animate(
            withDuration: Self.actionAnimationDuration,
            delay: 0.02,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0.65,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.retryMotionView.transform = .identity
            self.retryMotionView.alpha = 1
        } completion: { _ in
            applyEndState()
        }
    }

    private func hideRetryButton(animated: Bool) {
        guard isRetryButtonVisible else {
            retryMotionView.alpha = 0
            retryMotionView.isUserInteractionEnabled = false
            retryMotionView.transform = CGAffineTransform(translationX: Self.actionSlideDistance, y: 0)
            return
        }
        isRetryButtonVisible = false
        retryMotionView.isUserInteractionEnabled = false

        let applyEndState = {
            self.retryMotionView.transform = CGAffineTransform(translationX: Self.actionSlideDistance, y: 0)
            self.retryMotionView.alpha = 0
        }

        guard animated else {
            applyEndState()
            return
        }

        UIView.animate(
            withDuration: Self.actionAnimationDuration,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0.45,
            options: [.curveEaseIn, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.retryMotionView.transform = CGAffineTransform(translationX: Self.actionSlideDistance, y: 0)
            self.retryMotionView.alpha = 0
        } completion: { _ in
            applyEndState()
        }
    }

    private func refreshSentenceDisplay() {
        var displayInsets = JapaneseFuriganaBuilder.dialogueBubbleDisplayInsets(for: Self.sentenceFont)
        displayInsets.top += 2
        JapaneseFuriganaBuilder.applyScrubDisplay(
            to: sentenceLabel,
            attributed: JapaneseFuriganaBuilder.dialogueBubbleAttributedString(
                for: sentence,
                font: Self.sentenceFont,
                textColor: .label
            ),
            contentInsets: displayInsets
        )
    }

    // MARK: - Feedback display

    private func refreshTutorTranscriptVisibility() {
        for entry in attemptEntries {
            entry.feedbackLabel.isHidden = !(showsTutorTranscript && hasTutorFeedbackText(entry.feedbackLabel))
        }
        refreshFeedbackCardVisibility()
    }

    private func refreshFeedbackCardVisibility() {
        feedbackCard.isHidden = attemptEntries.isEmpty
    }

    private func appendAttemptBubble(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let label = FuriganaTranscriptLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .natural
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        var displayInsets = JapaneseFuriganaBuilder.dialogueBubbleDisplayInsets(for: Self.attemptFont)
        displayInsets.top += 2
        JapaneseFuriganaBuilder.applyScrubDisplay(
            to: label,
            attributed: JapaneseFuriganaBuilder.dialogueBubbleAttributedString(
                for: trimmed,
                font: Self.attemptFont,
                textColor: .label
            ),
            contentInsets: displayInsets
        )

        let bubble = DialogueJapaneseBubbleView(label: label)
        bubble.setBackgroundStyle(.glass)
        var glow = DialogueBubbleUnderglowConfiguration.default
        glow.color = .blue
        bubble.setUnderglowConfiguration(glow)
        bubble.setEmphasis(1)
        bubble.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        bubble.setContentCompressionResistancePriority(.required, for: .horizontal)

        let leadingSpacer = UIView()
        leadingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        leadingSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let bubbleRow = UIStackView(arrangedSubviews: [leadingSpacer, bubble])
        bubbleRow.axis = .horizontal
        bubbleRow.alignment = .center
        bubbleRow.clipsToBounds = false

        let feedbackLabel = UILabel()
        feedbackLabel.translatesAutoresizingMaskIntoConstraints = false
        feedbackLabel.font = .preferredFont(forTextStyle: .body)
        feedbackLabel.textColor = .secondaryLabel
        feedbackLabel.numberOfLines = 0
        feedbackLabel.textAlignment = .natural
        feedbackLabel.isHidden = true

        let entryStack = UIStackView(arrangedSubviews: [bubbleRow, feedbackLabel])
        entryStack.axis = .vertical
        entryStack.alignment = .fill
        entryStack.spacing = 8
        entryStack.clipsToBounds = false
        entryStack.translatesAutoresizingMaskIntoConstraints = false

        attemptsStack.addArrangedSubview(entryStack)
        bubble.widthAnchor.constraint(
            lessThanOrEqualTo: attemptsStack.widthAnchor,
            multiplier: Self.attemptBubbleMaxWidthRatio
        ).isActive = true

        attemptEntries.append(AttemptEntry(container: entryStack, feedbackLabel: feedbackLabel))
        refreshFeedbackCardVisibility()
    }

    private func showUserAttempt(_ text: String) {
        appendAttemptBubble(text: text)
    }

    private func showTutorFeedback(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let entry = attemptEntries.last else { return }
        entry.feedbackLabel.text = trimmed
        entry.feedbackLabel.isHidden = !showsTutorTranscript
        refreshFeedbackCardVisibility()

        // Excellent scores end the session early, even in multi-try mode.
        if let score = Self.parseScore(from: trimmed), score >= 9 {
            tutorHarness.requestEndAfterCurrentTutorReply()
        }
    }

    private static func parseScore(from text: String) -> Int? {
        let patterns = [
            #"(\d{1,2})\s*(?:/|out of)\s*10"#,
            #"score\s*(?:is|:)?\s*(\d{1,2})\s*(?:/|out of)?\s*10?"#,
            #"(\d{1,2})\s*点"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range),
                  match.numberOfRanges > 1,
                  let scoreRange = Range(match.range(at: 1), in: text),
                  let value = Int(text[scoreRange]),
                  (0...10).contains(value)
            else { continue }
            return value
        }
        return nil
    }

    // MARK: - Phase

    private func setPhase(_ newPhase: Phase, animated: Bool) {
        phase = newPhase
        switch newPhase {
        case .listen:
            break
        case .speak:
            break
        case .finished:
            tutorHarness.setFinishedAppearance()
            showRetryButton(animated: animated)
        }
    }

    // MARK: - Reference audio

    @objc private func playButtonTapped() {
        guard !isPlayingReference else { return }
        playTargetSentence()
    }

    @objc private func retryButtonTapped() {
        guard phase == .finished, !isPlayingReference else { return }
        hideRetryButton(animated: true)
        startSpeakingSession(playReferenceFirst: false)
    }

    /// Plays the target sentence. The first tap starts the tutor session after audio finishes.
    private func playTargetSentence() {
        stopReferenceAudio()
        isPlayingReference = true

        let shouldBootstrapSession = !hasStartedSession && phase != .finished
        if shouldBootstrapSession {
            hasStartedSession = true
            setPhase(.listen, animated: true)
            setTutorHarnessVisible(true, animated: true)
            tutorHarness.applyConfiguration(
                RealtimeTutorPrompt.repeatAfterMeConfiguration(targetSentence: sentence)
            )
            tutorHarness.setIdleStatus("Listen…")
            tutorHarness.connect(startListening: false)
        } else if phase == .speak {
            tutorHarness.setMicMuted(true)
        }

        playReferenceAudio { [weak self] in
            guard let self else { return }
            self.isPlayingReference = false
            self.tutorHarness.setMicMuted(false)
            if shouldBootstrapSession {
                self.beginSpeakPhase()
            }
        }
    }

    private func startSpeakingSession(playReferenceFirst: Bool) {
        stopReferenceAudio()
        tutorHarness.disconnect()
        hideRetryButton(animated: false)
        hasStartedSession = true
        setTutorHarnessVisible(true, animated: false)
        tutorHarness.applyConfiguration(
            RealtimeTutorPrompt.repeatAfterMeConfiguration(targetSentence: sentence)
        )

        if playReferenceFirst {
            // Reset so playTargetSentence bootstraps connect + listen after audio.
            hasStartedSession = false
            setPhase(.listen, animated: true)
            playTargetSentence()
            return
        }

        setPhase(.speak, animated: true)
        tutorHarness.connect(startListening: true)
    }

    private func beginSpeakPhase() {
        setPhase(.speak, animated: true)
        tutorHarness.beginListening()
    }

    private func setTutorHarnessVisible(_ visible: Bool, animated: Bool) {
        let changes = {
            self.tutorHarness.alpha = visible ? 1 : 0
            self.tutorHarness.isUserInteractionEnabled = visible
        }
        tutorHarness.isHidden = false
        guard animated else {
            changes()
            tutorHarness.isHidden = !visible
            return
        }
        if visible {
            tutorHarness.isHidden = false
            tutorHarness.alpha = 0
        }
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            changes()
        } completion: { _ in
            if !visible {
                self.tutorHarness.isHidden = true
            }
        }
    }

    private func stopReferenceAudio() {
        isPlayingReference = false
        grammarAudioPlayer.stop()
        fallbackSpeaker?.stop()
        RealtimePCMPlayer.shared.stop()
    }

    private func playReferenceAudio(completion: @escaping () -> Void) {
        guard !sentence.isEmpty else {
            completion()
            return
        }

        if let recordedClip, !recordedClip.pcmData.isEmpty {
            RealtimePCMPlayer.shared.play(recordedClip)
            let duration = Double(recordedClip.pcmData.count / 2) / recordedClip.sampleRate
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.4, duration + 0.15)) {
                completion()
            }
            return
        }

        if canPlayDialogueLineAudio, let dialogueLineAudio {
            grammarAudioPlayer.playDialogueLine(
                at: dialogueLineAudio.lineIndex,
                publishedAudioUrl: dialogueLineAudio.publishedAudioUrl,
                audioKey: dialogueLineAudio.audioKey,
                cacheMetadata: dialogueLineAudio.cacheMetadata,
                dialogueLines: dialogueLineAudio.dialogueLines,
                fallbackText: sentence,
                onFinished: completion
            )
            return
        }

        let speaker = RepeatAfterMeSpeechSpeaker()
        fallbackSpeaker = speaker
        speaker.speak(sentence, completion: completion)
    }

    private var canPlayDialogueLineAudio: Bool {
        guard let dialogueLineAudio else { return false }
        guard dialogueLineAudio.dialogueLines.indices.contains(dialogueLineAudio.lineIndex) else {
            return false
        }
        let lineText = dialogueLineAudio.dialogueLines[dialogueLineAudio.lineIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !lineText.isEmpty && lineText == sentence
    }

    private static let sentenceFont: UIFont = {
        let base = UIFont.preferredFont(forTextStyle: .title2)
        return .systemFont(ofSize: base.pointSize, weight: .medium)
    }()

    private static let attemptFont: UIFont = {
        let base = UIFont.preferredFont(forTextStyle: .title3)
        return .systemFont(ofSize: base.pointSize, weight: .medium)
    }()
}

// MARK: - RealtimeTutorHarnessDelegate

extension RepeatAfterMeViewController: RealtimeTutorHarnessDelegate {

    func tutorHarness(
        _ harness: RealtimeTutorHarnessView,
        didReceiveUserTranscript text: String,
        audioClip: RealtimeAudioClip?
    ) {
        showUserAttempt(text)
    }

    func tutorHarness(
        _ harness: RealtimeTutorHarnessView,
        didCompleteAssistantTranscript text: String,
        sentenceClips: [(sentence: String, clip: RealtimeAudioClip)]
    ) {
        showTutorFeedback(text)
    }

    func tutorHarnessDidFinishSingleTurnSession(_ harness: RealtimeTutorHarnessView) {
        setPhase(.finished, animated: true)
    }

    func tutorHarness(_ harness: RealtimeTutorHarnessView, didEncounterError error: Error) {
        let alert = UIAlertController(
            title: "Realtime error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            guard let self else { return }
            self.setPhase(.finished, animated: true)
            self.tutorHarness.setIdleStatus(nil)
        })
        present(alert, animated: true)
    }
}

// MARK: - TTS with completion

private final class RepeatAfterMeSpeechSpeaker: NSObject, AVSpeechSynthesizerDelegate {

    private let synthesizer = AVSpeechSynthesizer()
    private var completion: (() -> Void)?

    func speak(_ text: String, completion: @escaping () -> Void) {
        self.completion = completion
        synthesizer.delegate = self

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = WordUtteranceSpeaker.resolvedVoice(identifier: "ja-JP")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        do {
            try PlaybackAudioSession.activateForPlayback()
        } catch {}

        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        completion = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        completion?()
        completion = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        completion?()
        completion = nil
    }
}
