//
//  RealtimeTutorViewController.swift
//  shizen
//
//  Conversation view with bottom dock (level meter + controls) and live transcript.
//

import TTSCore
import UIKit

final class RealtimeTutorViewController: UIViewController {

    private enum Speaker {
        case user
        case assistant
    }

    private struct LineItem {
        let id: UUID
        let speaker: Speaker
        let text: String
        let audioClip: RealtimeAudioClip?
    }

    private let realtimeService = RealtimeService()

    // MARK: - UI

    private let transcriptScrollView = UIScrollView()
    private let transcriptContentStack = UIStackView()
    private let transcriptEmptyLabel = UILabel()

    private let bottomDock = UIView()
    private let turnStatusLabel = UILabel()
    private let levelMeterView = AudioLevelBarsView()
    private let pauseButton = UIButton(type: .system)
    private let pauseGlyphView = UIImageView()
    private let micIndicatorButton = UIButton(type: .system)
    private let micGlyphView = UIImageView()
    private let usageLabel = UILabel()

    private var lineRows: [UIStackView] = []
    private var lineLabels: [UILabel] = []
    private var lineItems: [LineItem] = []

    private var streamingLineID: UUID?
    private var streamingSpeaker: Speaker?

    private var lastTurnForHaptic: RealtimeConversationTurn?

    private let turnHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let saveHaptic = UINotificationFeedbackGenerator()

    // MARK: - Init

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Realtime Tutor"
        navigationItem.largeTitleDisplayMode = .never
        configureNavigationItems()
        realtimeService.delegate = self

        configureBottomDock()
        configureTranscript()
        updatePauseControlUI()
        updateTurnUI(realtimeService.conversationTurn)
        lastTurnForHaptic = realtimeService.conversationTurn
        turnHaptic.prepare()
        saveHaptic.prepare()
        view.bringSubviewToFront(bottomDock)
    }

    private var furiganaToggleButton: UIBarButtonItem?

    private func configureNavigationItems() {
        let furiganaToggle = UIBarButtonItem(
            title: "あ",
            style: .plain,
            target: self,
            action: #selector(toggleFuriganaTapped)
        )
        furiganaToggleButton = furiganaToggle
        updateFuriganaToggleAppearance()

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                image: UIImage(systemName: "square.and.arrow.down"),
                style: .plain,
                target: self,
                action: #selector(saveConversationTapped)
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "clock.arrow.circlepath"),
                style: .plain,
                target: self,
                action: #selector(openSavedConversations)
            ),
            furiganaToggle,
        ]
    }

    @objc private func toggleFuriganaTapped() {
        JapaneseFuriganaSettings.showInTutorTranscripts.toggle()
        updateFuriganaToggleAppearance()
        refreshAllTranscriptLabels()
    }

    private func updateFuriganaToggleAppearance() {
        let on = JapaneseFuriganaSettings.showInTutorTranscripts
        furiganaToggleButton?.title = on ? "あ" : "文"
        furiganaToggleButton?.tintColor = on ? view.tintColor : .secondaryLabel
    }

    private func refreshAllTranscriptLabels() {
        for (idx, item) in lineItems.enumerated() {
            guard lineLabels.indices.contains(idx) else { continue }
            let label = lineLabels[idx]
            let color: UIColor = item.speaker == .user ? .systemBlue : .label
            applyTranscriptDisplay(to: label, text: item.text, textColor: color)
        }
    }

    private func applyTranscriptDisplay(to label: UILabel, text: String, textColor: UIColor) {
        if text == "…" {
            if let furiganaLabel = label as? FuriganaTranscriptLabel {
                furiganaLabel.textInsets = .zero
            }
            label.attributedText = nil
            label.font = Self.lyricFont
            label.text = text
            label.textColor = textColor
            return
        }
        JapaneseFuriganaBuilder.apply(to: label, text: text, font: Self.lyricFont, textColor: textColor)
    }

    @objc private func saveConversationTapped() {
        do {
            _ = try TutorConversationStore.shared.save(lines: exportableSaveLines())
            saveHaptic.notificationOccurred(.success)
        } catch {
            let alert = UIAlertController(
                title: "Couldn’t save",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    @objc private func openSavedConversations() {
        navigationController?.pushViewController(TutorConversationsViewController(), animated: true)
    }

    private func exportableSaveLines() -> [TutorConversationSaveLine] {
        lineItems.compactMap { item in
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text != "…" else { return nil }
            let speaker: TutorConversationLine.Speaker = item.speaker == .user ? .user : .assistant
            return TutorConversationSaveLine(
                speaker: speaker,
                text: text,
                audioClip: item.audioClip
            )
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if case .disconnected = realtimeService.connectionState {
            realtimeService.connect()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            realtimeService.disconnect()
        }
    }


    // MARK: - Bottom dock

    private static let controlButtonSize: CGFloat = 75
    private static let controlGlyphSize: CGFloat = 30
    private static let micHighlightColor = UIColor.systemYellow
    private static let micIdleColor = UIColor.label
    private static let pauseGlyphColor = UIColor.label

    private static let userMeterColor = UIColor.systemBlue
    private static let tutorMeterColor = UIColor.label

    private func configureBottomDock() {
        bottomDock.translatesAutoresizingMaskIntoConstraints = false
        bottomDock.backgroundColor = .clear
        view.addSubview(bottomDock)

        turnStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        turnStatusLabel.font = Self.turnStatusFont
        turnStatusLabel.textAlignment = .center
        turnStatusLabel.numberOfLines = 1
        turnStatusLabel.textColor = UIColor.black.withAlphaComponent(0.35)

        levelMeterView.translatesAutoresizingMaskIntoConstraints = false

        configureGlassControlButton(
            pauseButton,
            glyphView: pauseGlyphView,
            symbolName: "pause.fill",
            glyphColor: Self.pauseGlyphColor,
            accessibilityLabel: "Pause session"
        )
        pauseButton.addAction(UIAction { [weak self] _ in
            self?.pauseButtonTapped()
        }, for: .primaryActionTriggered)

        configureGlassControlButton(
            micIndicatorButton,
            glyphView: micGlyphView,
            symbolName: "mic.fill",
            glyphColor: Self.micIdleColor,
            accessibilityLabel: "Mute microphone"
        )
        micIndicatorButton.addAction(UIAction { [weak self] _ in
            self?.micButtonTapped()
        }, for: .primaryActionTriggered)
        updateMicButtonUI()

        usageLabel.translatesAutoresizingMaskIntoConstraints = false
        usageLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        usageLabel.textColor = .tertiaryLabel
        usageLabel.textAlignment = .center
        usageLabel.numberOfLines = 2
        usageLabel.text = "Tokens: —"

        let statusStack = UIStackView(arrangedSubviews: [turnStatusLabel, levelMeterView])
        statusStack.axis = .vertical
        statusStack.alignment = .center
        statusStack.spacing = 8
        statusStack.translatesAutoresizingMaskIntoConstraints = false

        let controlRow = UIView()
        controlRow.translatesAutoresizingMaskIntoConstraints = false
        controlRow.addSubview(pauseButton)
        controlRow.addSubview(statusStack)
        controlRow.addSubview(micIndicatorButton)

        let dockStack = UIStackView(arrangedSubviews: [controlRow, usageLabel])
        dockStack.axis = .vertical
        dockStack.spacing = 10
        dockStack.alignment = .fill
        dockStack.translatesAutoresizingMaskIntoConstraints = false
        bottomDock.addSubview(dockStack)

        NSLayoutConstraint.activate([
            bottomDock.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomDock.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomDock.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            dockStack.topAnchor.constraint(equalTo: bottomDock.topAnchor, constant: 16),
            dockStack.leadingAnchor.constraint(equalTo: bottomDock.leadingAnchor, constant: 24),
            dockStack.trailingAnchor.constraint(equalTo: bottomDock.trailingAnchor, constant: -24),
            dockStack.bottomAnchor.constraint(equalTo: bottomDock.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            controlRow.heightAnchor.constraint(equalToConstant: Self.controlButtonSize),

            pauseButton.leadingAnchor.constraint(equalTo: controlRow.leadingAnchor),
            pauseButton.centerYAnchor.constraint(equalTo: controlRow.centerYAnchor),
            pauseButton.widthAnchor.constraint(equalToConstant: Self.controlButtonSize),
            pauseButton.heightAnchor.constraint(equalToConstant: Self.controlButtonSize),

            micIndicatorButton.trailingAnchor.constraint(equalTo: controlRow.trailingAnchor),
            micIndicatorButton.centerYAnchor.constraint(equalTo: controlRow.centerYAnchor),
            micIndicatorButton.widthAnchor.constraint(equalToConstant: Self.controlButtonSize),
            micIndicatorButton.heightAnchor.constraint(equalToConstant: Self.controlButtonSize),

            statusStack.centerXAnchor.constraint(equalTo: controlRow.centerXAnchor),
            statusStack.centerYAnchor.constraint(equalTo: controlRow.centerYAnchor),
            levelMeterView.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    private func configureGlassControlButton(
        _ button: UIButton,
        glyphView: UIImageView,
        symbolName: String,
        glyphColor: UIColor,
        accessibilityLabel: String
    ) {
        var config = UIButton.Configuration.glass()
        config.cornerStyle = .capsule
        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = accessibilityLabel

        let symbolConfig = UIImage.SymbolConfiguration(
            pointSize: Self.controlGlyphSize,
            weight: .semibold
        )
        glyphView.image = UIImage(systemName: symbolName, withConfiguration: symbolConfig)?
            .withRenderingMode(.alwaysTemplate)
        glyphView.tintColor = glyphColor
        glyphView.preferredSymbolConfiguration = symbolConfig
        glyphView.contentMode = .scaleAspectFit
        glyphView.isUserInteractionEnabled = false
        glyphView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(glyphView)

        NSLayoutConstraint.activate([
            glyphView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            glyphView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            glyphView.widthAnchor.constraint(equalToConstant: Self.controlGlyphSize),
            glyphView.heightAnchor.constraint(equalToConstant: Self.controlGlyphSize),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pauseButton.bringSubviewToFront(pauseGlyphView)
        micIndicatorButton.bringSubviewToFront(micGlyphView)
        updateTranscriptContentInsets()
    }

    private func updateTranscriptContentInsets() {
        let bottomInset = max(0, view.bounds.maxY - bottomDock.frame.minY)
        guard transcriptScrollView.contentInset.bottom != bottomInset else { return }
        transcriptScrollView.contentInset.bottom = bottomInset
        var indicatorInsets = transcriptScrollView.verticalScrollIndicatorInsets
        indicatorInsets.bottom = bottomInset
        transcriptScrollView.verticalScrollIndicatorInsets = indicatorInsets
    }

    // MARK: - Transcript

    private static let lineSpacing = JapaneseFuriganaBuilder.transcriptLineSpacing
    private static let transcriptTopPadding: CGFloat = 12
    private static let transcriptBottomPadding: CGFloat = 24
    private static let transcriptHorizontalInset: CGFloat = 24

    private func configureTranscript() {
        transcriptEmptyLabel.translatesAutoresizingMaskIntoConstraints = false
        transcriptEmptyLabel.font = .preferredFont(forTextStyle: .body)
        transcriptEmptyLabel.textColor = .tertiaryLabel
        transcriptEmptyLabel.textAlignment = .center
        transcriptEmptyLabel.numberOfLines = 0
        transcriptEmptyLabel.text = "Your conversation will appear here.\nSpeak with the tutor to get started."

        transcriptScrollView.translatesAutoresizingMaskIntoConstraints = false
        transcriptScrollView.alwaysBounceVertical = true

        transcriptContentStack.translatesAutoresizingMaskIntoConstraints = false
        transcriptContentStack.axis = .vertical
        transcriptContentStack.alignment = .fill
        transcriptContentStack.spacing = Self.lineSpacing
        transcriptContentStack.clipsToBounds = false

        transcriptScrollView.addSubview(transcriptContentStack)
        view.addSubview(transcriptScrollView)
        view.addSubview(transcriptEmptyLabel)

        let guide = view.safeAreaLayoutGuide
        let content = transcriptScrollView.contentLayoutGuide
        let frame = transcriptScrollView.frameLayoutGuide

        NSLayoutConstraint.activate([
            transcriptScrollView.topAnchor.constraint(equalTo: guide.topAnchor),
            transcriptScrollView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            transcriptScrollView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            transcriptScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            transcriptContentStack.topAnchor.constraint(
                equalTo: content.topAnchor,
                constant: Self.transcriptTopPadding + JapaneseFuriganaBuilder.transcriptRubyTopInset(for: Self.lyricFont)
            ),
            transcriptContentStack.bottomAnchor.constraint(
                equalTo: content.bottomAnchor,
                constant: -Self.transcriptBottomPadding
            ),
            transcriptContentStack.leadingAnchor.constraint(
                equalTo: content.leadingAnchor,
                constant: Self.transcriptHorizontalInset
            ),
            transcriptContentStack.trailingAnchor.constraint(
                equalTo: content.trailingAnchor,
                constant: -Self.transcriptHorizontalInset
            ),
            transcriptContentStack.widthAnchor.constraint(
                equalTo: frame.widthAnchor,
                constant: -2 * Self.transcriptHorizontalInset
            ),

            transcriptEmptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            transcriptEmptyLabel.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
            transcriptEmptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 32),
            transcriptEmptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -32),
        ])
    }

    // MARK: - Session + turn UI

    private func micButtonTapped() {
        realtimeService.setMicMuted(!realtimeService.isMicMuted)
    }

    private func updateMicButtonUI() {
        let symbolConfig = UIImage.SymbolConfiguration(
            pointSize: Self.controlGlyphSize,
            weight: .semibold
        )

        if realtimeService.isMicMuted {
            micGlyphView.image = UIImage(systemName: "mic.slash.fill", withConfiguration: symbolConfig)?
                .withRenderingMode(.alwaysTemplate)
            micGlyphView.tintColor = .secondaryLabel
            micIndicatorButton.accessibilityLabel = "Unmute microphone"
            levelMeterView.fadeToMinimum()
        } else {
            micGlyphView.image = UIImage(systemName: "mic.fill", withConfiguration: symbolConfig)?
                .withRenderingMode(.alwaysTemplate)
            micIndicatorButton.accessibilityLabel = "Mute microphone"
            switch realtimeService.conversationTurn {
            case .yourTurn:
                micGlyphView.tintColor = Self.micHighlightColor
            default:
                micGlyphView.tintColor = Self.micIdleColor
            }
        }

        micIndicatorButton.isEnabled = realtimeService.connectionState == .connected
        micIndicatorButton.alpha = micIndicatorButton.isEnabled ? 1 : 0.45
    }

    private func pauseButtonTapped() {
        switch realtimeService.connectionState {
        case .connected:
            if realtimeService.isSessionPaused {
                realtimeService.resumeSession()
            } else {
                realtimeService.pauseSession()
            }
        case .connecting:
            realtimeService.disconnect()
        case .disconnected, .failed:
            realtimeService.connect()
        }
        updatePauseControlUI()
    }

    private func updatePauseControlUI() {
        usageLabel.text = realtimeService.cumulativeUsage.summaryLine

        let symbolConfig = UIImage.SymbolConfiguration(
            pointSize: Self.controlGlyphSize,
            weight: .semibold
        )

        switch realtimeService.connectionState {
        case .disconnected, .failed:
            pauseGlyphView.image = UIImage(systemName: "play.fill", withConfiguration: symbolConfig)?
                .withRenderingMode(.alwaysTemplate)
            pauseButton.isEnabled = true
            pauseButton.alpha = 1
        case .connecting:
            pauseGlyphView.image = UIImage(systemName: "pause.fill", withConfiguration: symbolConfig)?
                .withRenderingMode(.alwaysTemplate)
            pauseButton.isEnabled = false
            pauseButton.alpha = 0.45
        case .connected:
            pauseButton.isEnabled = true
            pauseButton.alpha = 1
            let symbol = realtimeService.isSessionPaused ? "play.fill" : "pause.fill"
            pauseGlyphView.image = UIImage(systemName: symbol, withConfiguration: symbolConfig)?
                .withRenderingMode(.alwaysTemplate)
        }
    }

    private func updateTurnUI(_ turn: RealtimeConversationTurn) {
        switch turn {
        case .connecting:
            turnStatusLabel.text = "Connecting…"
            levelMeterView.barColor = Self.userMeterColor
            levelMeterView.reset()
        case .yourTurn:
            turnStatusLabel.text = "Connected"
            levelMeterView.barColor = Self.userMeterColor
        case .tutorTurn:
            turnStatusLabel.text = "Connected"
            levelMeterView.barColor = Self.tutorMeterColor
            levelMeterView.fadeToMinimum()
        case .paused:
            turnStatusLabel.text = "Paused"
            levelMeterView.reset()
        case .stopped:
            turnStatusLabel.text = "Disconnected"
            levelMeterView.reset()
        }
        updateMicButtonUI()
    }

    private func pushMeterLevel(_ level: Float) {
        let clamped = max(0, min(1, level))
        let eased = clamped * clamped * (3 - 2 * clamped)
        levelMeterView.setLevel(eased)
    }

    private func updateTranscriptEmptyState() {
        transcriptEmptyLabel.isHidden = !lineItems.isEmpty
    }

    private static let speakerTurnSpacing = JapaneseFuriganaBuilder.transcriptSpeakerTurnSpacing
    private static let transcriptColumnWidthMultiplier: CGFloat = 0.75

    private func splitIntoDisplayLines(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let sentences = TextToSpeechService.splitIntoSentences(trimmed)
        return sentences.isEmpty ? [trimmed] : sentences
    }

    private func label(in row: UIStackView) -> UILabel? {
        for subview in row.arrangedSubviews {
            guard let textColumn = subview as? UIStackView else { continue }
            for arranged in textColumn.arrangedSubviews {
                if let label = arranged as? UILabel { return label }
            }
        }
        return nil
    }

    private func addLineRow(_ row: UIStackView, speaker: Speaker) {
        if lineItems.count > 1,
           let previousRow = lineRows.last,
           lineItems[lineItems.count - 2].speaker != speaker {
            transcriptContentStack.setCustomSpacing(Self.speakerTurnSpacing, after: previousRow)
        }
        transcriptContentStack.addArrangedSubview(row)
        lineRows.append(row)
        if let label = label(in: row) {
            lineLabels.append(label)
        }
    }

    private func removeStreamingPlaceholder() {
        guard let id = streamingLineID,
              let idx = lineItems.firstIndex(where: { $0.id == id })
        else {
            streamingLineID = nil
            streamingSpeaker = nil
            return
        }
        let row = lineRows[idx]
        transcriptContentStack.removeArrangedSubview(row)
        row.removeFromSuperview()
        lineRows.remove(at: idx)
        lineLabels.remove(at: idx)
        lineItems.remove(at: idx)
        streamingLineID = nil
        streamingSpeaker = nil
        updateTranscriptEmptyState()
    }

    private func appendLines(
        speaker: Speaker,
        text: String,
        wholeClip: RealtimeAudioClip? = nil
    ) {
        let sentences = splitIntoDisplayLines(text)
        guard !sentences.isEmpty else { return }

        let clips: [RealtimeAudioClip?]
        if let wholeClip, !wholeClip.pcmData.isEmpty {
            clips = RealtimeConversationRecorder.splitPCM(
                wholeClip.pcmData,
                across: sentences,
                speaker: wholeClip.speaker
            )
        } else {
            clips = Array(repeating: nil, count: sentences.count)
        }

        for (offset, sentence) in sentences.enumerated() {
            let clip = clips.indices.contains(offset) ? clips[offset] : nil
            let item = LineItem(id: UUID(), speaker: speaker, text: sentence, audioClip: clip)
            lineItems.append(item)
            let row = makeLineRow(item: item)
            addLineRow(row, speaker: speaker)
        }
        updateTranscriptEmptyState()
        scrollTranscriptToBottom(animated: true)
    }

    private func makeLineRow(item: LineItem) -> UIStackView {
        let label = JapaneseFuriganaBuilder.makeTranscriptLabel(font: Self.lyricFont)
        label.textAlignment = item.speaker == .user ? .right : .left
        applyTranscriptDisplay(
            to: label,
            text: item.text,
            textColor: item.speaker == .user ? .systemBlue : .label
        )
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let textColumn = UIStackView(arrangedSubviews: [label])
        textColumn.axis = .vertical
        textColumn.alignment = item.speaker == .user ? .trailing : .leading
        textColumn.clipsToBounds = false
        textColumn.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textColumn.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let marginSpacer = UIView()
        marginSpacer.translatesAutoresizingMaskIntoConstraints = false
        marginSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        marginSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .top
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        row.clipsToBounds = false
        row.isUserInteractionEnabled = true
        row.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(handleLineTap(_:)))
        )

        if item.speaker == .user {
            row.addArrangedSubview(marginSpacer)
            row.addArrangedSubview(textColumn)
        } else {
            row.addArrangedSubview(textColumn)
            row.addArrangedSubview(marginSpacer)
        }

        NSLayoutConstraint.activate([
            marginSpacer.widthAnchor.constraint(
                equalTo: row.widthAnchor,
                multiplier: 1 - Self.transcriptColumnWidthMultiplier
            ),
        ])

        return row
    }

    @objc private func handleLineTap(_ gesture: UITapGestureRecognizer) {
        guard let row = gesture.view as? UIStackView,
              let index = lineRows.firstIndex(where: { $0 === row }),
              lineItems.indices.contains(index)
        else { return }
        let item = lineItems[index]
        let scrub = SentenceScrubExperimentViewController(
            sentence: item.text,
            recordedClip: item.audioClip,
            onReplayClip: { [weak self] clip in
                self?.realtimeService.replayRecordedClip(clip)
            }
        )
        navigationController?.pushViewController(scrub, animated: true)
    }

    private func ensureUserStreamingLine() -> UILabel {
        if streamingLineID != nil, streamingSpeaker == .user,
           let id = streamingLineID,
           let idx = lineItems.firstIndex(where: { $0.id == id })
        {
            updateTranscriptEmptyState()
            return lineLabels[idx]
        }

        removeStreamingPlaceholder()
        streamingSpeaker = .user

        let item = LineItem(id: UUID(), speaker: .user, text: "…", audioClip: nil)
        streamingLineID = item.id
        lineItems.append(item)

        let row = makeLineRow(item: item)
        addLineRow(row, speaker: .user)
        guard let label = label(in: row) else { return UILabel() }
        label.textColor = .systemBlue
        updateTranscriptEmptyState()
        return label
    }

    private func finalizeUserStreamingLine(text: String, audioClip: RealtimeAudioClip?) {
        removeStreamingPlaceholder()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appendLines(speaker: .user, text: trimmed, wholeClip: audioClip)
    }

    private func scrollTranscriptToBottom(animated: Bool) {
        view.layoutIfNeeded()
        let inset = transcriptScrollView.adjustedContentInset
        let visibleHeight = transcriptScrollView.bounds.height - inset.top - inset.bottom
        let bottomOffset = transcriptScrollView.contentSize.height - visibleHeight
        let y = max(-inset.top, bottomOffset + inset.bottom)
        transcriptScrollView.setContentOffset(CGPoint(x: 0, y: y), animated: animated)
    }

    private static let lyricFont: UIFont = {
        let base = UIFont.systemFont(ofSize: 32, weight: .heavy)
        return UIFontMetrics(forTextStyle: .title1).scaledFont(for: base)
    }()

    private static let turnStatusFont: UIFont = {
        let base = UIFont.systemFont(ofSize: 13, weight: .medium)
        return UIFontMetrics(forTextStyle: .caption1).scaledFont(for: base)
    }()

}

// MARK: - RealtimeServiceDelegate

extension RealtimeTutorViewController: RealtimeServiceDelegate {

    func realtimeService(_ service: RealtimeService, didChangeConnectionState state: RealtimeConnectionState) {
        updatePauseControlUI()
        updateMicButtonUI()
    }

    func realtimeService(_ service: RealtimeService, didChangeTurn turn: RealtimeConversationTurn) {
        if turn != lastTurnForHaptic, turn == .yourTurn || turn == .tutorTurn {
            turnHaptic.impactOccurred()
        }
        lastTurnForHaptic = turn
        updateTurnUI(turn)
        updatePauseControlUI()
    }

    func realtimeService(_ service: RealtimeService, didReceiveUserTranscriptDelta delta: String) {
        let label = ensureUserStreamingLine()
        label.text = (label.text == "…") ? delta : (label.text ?? "") + delta
        scrollTranscriptToBottom(animated: false)
    }

    func realtimeService(
        _ service: RealtimeService,
        didReceiveUserTranscript text: String,
        audioClip: RealtimeAudioClip?
    ) {
        finalizeUserStreamingLine(text: text, audioClip: audioClip)
    }

    func realtimeService(_ service: RealtimeService, didReceiveAssistantTranscriptDelta delta: String) {}

    func realtimeService(
        _ service: RealtimeService,
        didCompleteAssistantTranscript text: String,
        sentenceClips: [(sentence: String, clip: RealtimeAudioClip)]
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if sentenceClips.isEmpty {
            appendLines(speaker: .assistant, text: trimmed)
            return
        }
        for pair in sentenceClips {
            let item = LineItem(
                id: UUID(),
                speaker: .assistant,
                text: pair.sentence,
                audioClip: pair.clip.pcmData.isEmpty ? nil : pair.clip
            )
            lineItems.append(item)
            let row = makeLineRow(item: item)
            addLineRow(row, speaker: .assistant)
        }
        updateTranscriptEmptyState()
        scrollTranscriptToBottom(animated: true)
    }

    func realtimeService(_ service: RealtimeService, didUpdateUsage usage: RealtimeTokenUsage) {
        usageLabel.text = usage.summaryLine
    }

    func realtimeService(_ service: RealtimeService, didEncounterError error: Error) {
        updatePauseControlUI()
        guard !realtimeService.isSessionPaused else { return }

        let message = error.localizedDescription.lowercased()
        if message.contains("no active response") || message.contains("cancel") {
            return
        }
        guard case .failed = realtimeService.connectionState else { return }

        let alert = UIAlertController(
            title: "Realtime error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    func realtimeServiceDidDetectSpeechStarted(_ service: RealtimeService) {
        if streamingSpeaker == .user { removeStreamingPlaceholder() }
    }

    func realtimeService(_ service: RealtimeService, didUpdateInputLevel level: Float) {
        guard !realtimeService.isMicMuted,
              realtimeService.conversationTurn == .yourTurn else { return }
        pushMeterLevel(level)
    }

    func realtimeService(_ service: RealtimeService, didUpdateOutputLevel level: Float) {
        guard realtimeService.conversationTurn == .tutorTurn else { return }
        pushMeterLevel(level)
    }

    func realtimeService(_ service: RealtimeService, didChangeMicMuted isMuted: Bool) {
        updateMicButtonUI()
    }
}
