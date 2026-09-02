//
//  RealtimeTutorViewController.swift
//  shizen
//
//  Live tutor conversation: plain transcript lines, tutor live meter with
//  streaming secondary text below, and a glass transport bar.
//

import TTSCore
import UIKit

protocol RealtimeTutorViewControllerDelegate: AnyObject {
    func realtimeTutorViewControllerDidFinishSingleTurnSession(_ viewController: RealtimeTutorViewController)
}

final class RealtimeTutorViewController: UIViewController {

    weak var sessionDelegate: RealtimeTutorViewControllerDelegate?

    private let configuration: RealtimeTutorSessionConfiguration

    private enum Speaker {
        case user
        case assistant
    }

    private enum SpeakerSide {
        case leading
        case trailing
    }

    private struct LineItem {
        let id: UUID
        let speaker: Speaker
        let text: String
        let audioClip: RealtimeAudioClip?
    }

    private struct TutorLiveMeterSlot {
        let row: UIView
        let column: UIStackView
        let meterBubble: DialogueJapaneseBubbleView
        let meter: AudioLevelBarsView
        let streamingLabel: FuriganaTranscriptLabel
    }

    private let realtimeService = RealtimeService()

    // MARK: - Transcript

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let emptyStateLabel = UILabel()

    private var lineRows: [UIView] = []
    private var lineItems: [LineItem] = []
    private var lineLabels: [FuriganaTranscriptLabel] = []
    private var lineEmphasis: [CGFloat] = []
    private var activeLineIndex: Int?

    private var streamingLineID: UUID?
    private var streamingSpeaker: Speaker?
    private var streamingText = ""

    private var tutorLiveMeterSlot: TutorLiveMeterSlot?
    private var tutorStreamingText = ""

    private var shouldEndAfterTutorPlayback = false
    private var didNotifySingleTurnCompletion = false
    private var completedAssistantResponses = 0

    /// Auto-scroll only while the reader is already pinned near the bottom.
    private var transcriptFollowsBottom = true

    // MARK: - Transport

    private let transportBarContainer = UIView()
    private let micButton = UIButton(type: .system)
    private let micGlyphView = UIImageView()
    private let playPauseButton = UIButton(type: .system)
    private let playGlyphView = UIImageView()
    private let turnStatusLabel = UILabel()
    private let levelMeterView = AudioLevelBarsView()
    private let usageLabel = UILabel()

    private let bottomScrollEdgeInteraction: UIScrollEdgeElementContainerInteraction = {
        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.edge = .bottom
        interaction.scrollView = nil
        return interaction
    }()

    private let topScrollEdgeInteraction: UIScrollEdgeElementContainerInteraction = {
        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.edge = .top
        interaction.scrollView = nil
        return interaction
    }()

    // MARK: - Feedback

    private var lastTurnForHaptic: RealtimeConversationTurn?
    private let turnHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let saveHaptic = UINotificationFeedbackGenerator()
    private let lineChangeHaptic = UIImpactFeedbackGenerator(style: .light)

    private var furiganaToggleButton: UIBarButtonItem?

    // MARK: - Init

    init(configuration: RealtimeTutorSessionConfiguration = .openConversation) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    init() {
        self.configuration = .openConversation
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = configuration.navigationTitle
        navigationItem.largeTitleDisplayMode = .never
        configureNavigationItems()
        realtimeService.delegate = self

        configureScrollView()
        configureTransportBar()
        configureEmptyState()

        bottomScrollEdgeInteraction.scrollView = scrollView
        scrollView.topEdgeEffect.style = .soft
        scrollView.topEdgeEffect.isHidden = false
        scrollView.bottomEdgeEffect.style = .soft
        scrollView.bottomEdgeEffect.isHidden = false
        topScrollEdgeInteraction.scrollView = scrollView
        navigationController?.navigationBar.addInteraction(topScrollEdgeInteraction)

        updateTransportControls()
        updateTurnUI(realtimeService.conversationTurn)
        lastTurnForHaptic = realtimeService.conversationTurn
        turnHaptic.prepare()
        saveHaptic.prepare()

        view.bringSubviewToFront(transportBarContainer)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if case .disconnected = realtimeService.connectionState {
            completedAssistantResponses = 0
            shouldEndAfterTutorPlayback = false
            didNotifySingleTurnCompletion = false
            realtimeService.connect(sessionInstructions: configuration.sessionInstructions)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.navigationBar.removeInteraction(topScrollEdgeInteraction)
        if isBeingDismissed || isMovingFromParent {
            realtimeService.disconnect()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        micButton.bringSubviewToFront(micGlyphView)
        playPauseButton.bringSubviewToFront(playGlyphView)
        applyScrollContentInsets()
        applyLineStylesFromEmphasis()
    }

    // MARK: - Navigation

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
        applyTutorStreamingDisplay(tutorStreamingText)
    }

    private func updateFuriganaToggleAppearance() {
        let on = JapaneseFuriganaSettings.showInTutorTranscripts
        furiganaToggleButton?.title = on ? "あ" : "文"
        furiganaToggleButton?.tintColor = on ? view.tintColor : .secondaryLabel
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

    // MARK: - Scroll + empty state

    private func configureScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = true
        scrollView.delaysContentTouches = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear
        scrollView.delegate = self
        view.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 48
        contentStack.layoutMargins = UIEdgeInsets(top: 0, left: 24, bottom: 24, right: 24)
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.insetsLayoutMarginsFromSafeArea = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    private func configureEmptyState() {
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.font = .preferredFont(forTextStyle: .body)
        emptyStateLabel.textColor = .tertiaryLabel
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.numberOfLines = 0
        emptyStateLabel.text = "Your conversation will appear here.\nSpeak with the tutor to get started."
        view.addSubview(emptyStateLabel)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 32),
            emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -32),
        ])
    }

    private func applyScrollContentInsets() {
        let topInset = view.safeAreaInsets.top + Self.scrollTopContentInsetExtra
        let transportInset = max(transportBarContainer.bounds.height, 0) + Self.scrollBottomContentInsetExtra
        scrollView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: transportInset, right: 0)
        scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(
            top: topInset,
            left: 0,
            bottom: transportInset,
            right: 0
        )
    }

    private func isNearTranscriptBottom(threshold: CGFloat = RealtimeTutorViewController.transcriptFollowThreshold) -> Bool {
        let inset = scrollView.adjustedContentInset
        let maxY = max(-inset.top, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
        return scrollView.contentOffset.y >= maxY - threshold
    }

    private func refreshTranscriptFollowState() {
        transcriptFollowsBottom = isNearTranscriptBottom()
    }

    private func followTranscriptBottomIfNeeded(animated: Bool) {
        guard transcriptFollowsBottom else { return }
        scrollTranscriptToBottom(animated: animated)
    }

    // MARK: - Transport bar

    private func configureTransportBar() {
        transportBarContainer.translatesAutoresizingMaskIntoConstraints = false
        transportBarContainer.backgroundColor = .clear
        transportBarContainer.addInteraction(bottomScrollEdgeInteraction)
        view.addSubview(transportBarContainer)

        turnStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        turnStatusLabel.font = Self.turnStatusFont
        turnStatusLabel.textAlignment = .center
        turnStatusLabel.numberOfLines = 1
        turnStatusLabel.textColor = UIColor.black.withAlphaComponent(0.35)

        levelMeterView.translatesAutoresizingMaskIntoConstraints = false
        levelMeterView.barWidth = 8
        levelMeterView.barSpacing = 6
        levelMeterView.meterHeight = 28
        levelMeterView.minBarHeight = 8
        levelMeterView.heightFill = 0.95
        levelMeterView.levelGain = 1.6
        levelMeterView.displayCurve = 1.05
        levelMeterView.smoothing = 0.66
        levelMeterView.wobbleAmount = 0.08
        levelMeterView.diamondFalloff = 0.25
        levelMeterView.springiness = 0.5
        levelMeterView.historyStride = 2

        usageLabel.translatesAutoresizingMaskIntoConstraints = false
        usageLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        usageLabel.textColor = .tertiaryLabel
        usageLabel.textAlignment = .center
        usageLabel.numberOfLines = 2
        usageLabel.text = "Tokens: —"

        Self.configureGlassTransportButton(
            micButton,
            glyphView: micGlyphView,
            symbolName: "mic.fill",
            glyphPointSize: Self.transportGlyphPointSize - 2,
            glyphColor: Self.micIdleColor,
            accessibilityLabel: "Mute microphone"
        )
        micButton.addAction(UIAction { [weak self] _ in
            self?.micButtonTapped()
        }, for: .primaryActionTriggered)

        Self.configureGlassTransportButton(
            playPauseButton,
            glyphView: playGlyphView,
            symbolName: "pause.fill",
            glyphPointSize: Self.transportGlyphPointSize,
            glyphColor: Self.transportGlyphColor,
            accessibilityLabel: "Pause session"
        )
        playPauseButton.addAction(UIAction { [weak self] _ in
            self?.playPauseButtonTapped()
        }, for: .primaryActionTriggered)

        let statusStack = UIStackView(arrangedSubviews: [turnStatusLabel, levelMeterView])
        statusStack.axis = .vertical
        statusStack.alignment = .center
        statusStack.spacing = 8
        statusStack.translatesAutoresizingMaskIntoConstraints = false

        let controlRow = UIView()
        controlRow.translatesAutoresizingMaskIntoConstraints = false
        controlRow.addSubview(micButton)
        controlRow.addSubview(statusStack)
        controlRow.addSubview(playPauseButton)

        let dockStack = UIStackView(arrangedSubviews: [controlRow, usageLabel])
        dockStack.axis = .vertical
        dockStack.spacing = 10
        dockStack.alignment = .fill
        dockStack.translatesAutoresizingMaskIntoConstraints = false
        transportBarContainer.addSubview(dockStack)

        let buttonSize = Self.transportButtonSize
        NSLayoutConstraint.activate([
            transportBarContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            transportBarContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            transportBarContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            dockStack.topAnchor.constraint(equalTo: transportBarContainer.topAnchor, constant: 8),
            dockStack.leadingAnchor.constraint(equalTo: transportBarContainer.leadingAnchor, constant: 20),
            dockStack.trailingAnchor.constraint(equalTo: transportBarContainer.trailingAnchor, constant: -20),
            dockStack.bottomAnchor.constraint(equalTo: transportBarContainer.safeAreaLayoutGuide.bottomAnchor, constant: -8),

            controlRow.heightAnchor.constraint(equalToConstant: buttonSize),

            micButton.leadingAnchor.constraint(equalTo: controlRow.leadingAnchor),
            micButton.centerYAnchor.constraint(equalTo: controlRow.centerYAnchor),
            micButton.widthAnchor.constraint(equalToConstant: buttonSize),
            micButton.heightAnchor.constraint(equalToConstant: buttonSize),

            playPauseButton.trailingAnchor.constraint(equalTo: controlRow.trailingAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: controlRow.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: buttonSize),
            playPauseButton.heightAnchor.constraint(equalToConstant: buttonSize),

            statusStack.centerXAnchor.constraint(equalTo: controlRow.centerXAnchor),
            statusStack.centerYAnchor.constraint(equalTo: controlRow.centerYAnchor),
            levelMeterView.heightAnchor.constraint(equalToConstant: 28),
        ])

        updateMicButtonUI()
    }

    private func micButtonTapped() {
        realtimeService.setMicMuted(!realtimeService.isMicMuted)
    }

    private func playPauseButtonTapped() {
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
            completedAssistantResponses = 0
            shouldEndAfterTutorPlayback = false
            didNotifySingleTurnCompletion = false
            realtimeService.connect(sessionInstructions: configuration.sessionInstructions)
        }
        updateTransportControls()
    }

    private func updateTransportControls() {
        usageLabel.text = realtimeService.cumulativeUsage.summaryLine

        let symbolConfig = UIImage.SymbolConfiguration(
            pointSize: Self.transportGlyphPointSize,
            weight: .semibold
        )

        switch realtimeService.connectionState {
        case .disconnected, .failed:
            playGlyphView.image = UIImage(systemName: "play.fill", withConfiguration: symbolConfig)?
                .withRenderingMode(.alwaysTemplate)
            playPauseButton.isEnabled = true
            playPauseButton.alpha = 1
        case .connecting:
            playGlyphView.image = UIImage(systemName: "pause.fill", withConfiguration: symbolConfig)?
                .withRenderingMode(.alwaysTemplate)
            playPauseButton.isEnabled = false
            playPauseButton.alpha = 0.45
        case .connected:
            playPauseButton.isEnabled = true
            playPauseButton.alpha = 1
            let symbol = realtimeService.isSessionPaused ? "play.fill" : "pause.fill"
            playGlyphView.image = UIImage(systemName: symbol, withConfiguration: symbolConfig)?
                .withRenderingMode(.alwaysTemplate)
        }
    }

    private func updateMicButtonUI() {
        let symbolConfig = UIImage.SymbolConfiguration(
            pointSize: Self.transportGlyphPointSize - 2,
            weight: .semibold
        )

        if realtimeService.isMicMuted {
            micGlyphView.image = UIImage(systemName: "mic.slash.fill", withConfiguration: symbolConfig)?
                .withRenderingMode(.alwaysTemplate)
            micGlyphView.tintColor = .secondaryLabel
            micButton.accessibilityLabel = "Unmute microphone"
            levelMeterView.fadeToMinimum()
        } else {
            micGlyphView.image = UIImage(systemName: "mic.fill", withConfiguration: symbolConfig)?
                .withRenderingMode(.alwaysTemplate)
            micButton.accessibilityLabel = "Mute microphone"
            switch realtimeService.conversationTurn {
            case .yourTurn:
                micGlyphView.tintColor = Self.micHighlightColor
            default:
                micGlyphView.tintColor = Self.micIdleColor
            }
        }

        micButton.isEnabled = realtimeService.connectionState == .connected
        micButton.alpha = micButton.isEnabled ? 1 : 0.45
    }

    private func updateTurnUI(_ turn: RealtimeConversationTurn) {
        switch turn {
        case .connecting:
            turnStatusLabel.text = "Connecting…"
            levelMeterView.barColor = Self.userMeterColor
            levelMeterView.reset()
        case .yourTurn:
            turnStatusLabel.text = "Your turn"
            levelMeterView.reset()
            levelMeterView.fadeToMinimum()
            removeTutorLiveMeter(animated: true)
        case .tutorTurn:
            turnStatusLabel.text = "Tutor"
            levelMeterView.barColor = Self.tutorMeterColor
            levelMeterView.fadeToMinimum()
            ensureTutorLiveMeter()
        case .paused:
            turnStatusLabel.text = "Paused"
            levelMeterView.reset()
            setActiveLine(nil, animated: true)
            removeTutorLiveMeter(animated: true)
        case .stopped:
            turnStatusLabel.text = "Disconnected"
            levelMeterView.reset()
            setActiveLine(nil, animated: false)
            removeTutorLiveMeter(animated: false)
        }
        updateMicButtonUI()
    }

    private func pushMeterLevel(_ level: Float) {
        let clamped = max(0, min(1, level))
        let eased = clamped * clamped * (3 - 2 * clamped)
        levelMeterView.setLevel(eased)
    }

    private func pushTutorLiveMeterLevel(_ level: Float) {
        guard let slot = tutorLiveMeterSlot else { return }
        let clamped = max(0, min(1, level))
        let eased = clamped * clamped * (3 - 2 * clamped)
        slot.meter.setLevel(eased)
    }

    // MARK: - Tutor live meter + streaming transcript

    private func ensureTutorLiveMeter() {
        tutorStreamingText = ""

        if let slot = tutorLiveMeterSlot {
            applyTutorLiveMeterEmphasis(animated: true)
            applyTutorStreamingDisplay("")
            return
        }

        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isUserInteractionEnabled = false

        let column = UIStackView()
        column.translatesAutoresizingMaskIntoConstraints = false
        column.axis = .vertical
        column.spacing = 10
        column.alignment = .leading

        let speakerLabel = UILabel()
        speakerLabel.font = GrammarJapaneseTypography.scenarioSpeakerFont
        speakerLabel.textColor = .secondaryLabel
        speakerLabel.text = speakerPrefix(for: .assistant)
        let speakerWrapper = Self.insetMetadataWrapper(around: speakerLabel, side: .leading)
        let showsLabel = lineItems.isEmpty || lineItems.last?.speaker != .assistant
        speakerWrapper.isHidden = !showsLabel

        let placeholderLabel = FuriganaTranscriptLabel()
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.alpha = 0

        let meterBubble = DialogueJapaneseBubbleView(label: placeholderLabel)
        meterBubble.setBackgroundStyle(.glass)
        var glowConfig = DialogueBubbleUnderglowConfiguration.default
        glowConfig.color = .blue
        glowConfig.horizontalInset = 12
        glowConfig.blurRadius = 8
        glowConfig.offsetX = 0
        meterBubble.setUnderglowConfiguration(glowConfig)

        let meter = makeTutorLiveMeterView()
        meterBubble.addSubview(meter)

        let streamingLabel = JapaneseFuriganaBuilder.makeTranscriptLabel(font: Self.secondaryTranscriptFont)
        streamingLabel.translatesAutoresizingMaskIntoConstraints = false
        streamingLabel.numberOfLines = 0
        streamingLabel.textAlignment = .left
        streamingLabel.isHidden = true
        streamingLabel.alpha = 0.88

        column.addArrangedSubview(speakerWrapper)
        column.addArrangedSubview(meterBubble)
        column.addArrangedSubview(streamingLabel)
        column.setCustomSpacing(14, after: meterBubble)

        row.addSubview(column)

        let maxWidth = column.widthAnchor.constraint(
            lessThanOrEqualTo: row.widthAnchor,
            multiplier: Self.messageColumnMaxWidthRatio
        )
        maxWidth.priority = .required

        NSLayoutConstraint.activate([
            meter.leadingAnchor.constraint(equalTo: meterBubble.leadingAnchor, constant: 36),
            meter.trailingAnchor.constraint(equalTo: meterBubble.trailingAnchor, constant: -36),
            meter.topAnchor.constraint(equalTo: meterBubble.topAnchor, constant: 16),
            meter.bottomAnchor.constraint(equalTo: meterBubble.bottomAnchor, constant: -16),

            column.topAnchor.constraint(equalTo: row.topAnchor),
            column.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            column.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),
            maxWidth,
        ])

        if let previousRow = lineRows.last {
            let spacing: CGFloat = lineItems.last?.speaker == .user ? 48 : 20
            contentStack.setCustomSpacing(spacing, after: previousRow)
        }

        contentStack.addArrangedSubview(row)
        tutorLiveMeterSlot = TutorLiveMeterSlot(
            row: row,
            column: column,
            meterBubble: meterBubble,
            meter: meter,
            streamingLabel: streamingLabel
        )

        setActiveLine(nil, animated: false)
        applyTutorLiveMeterEmphasis(animated: false)
        animateLineEntrance(for: row, speaker: .assistant, delay: 0)
        updateTranscriptEmptyState()
        followTranscriptBottomIfNeeded(animated: true)
    }

    private func applyTutorStreamingDisplay(_ text: String) {
        guard let slot = tutorLiveMeterSlot else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        slot.streamingLabel.isHidden = trimmed.isEmpty
        guard !trimmed.isEmpty else { return }

        JapaneseFuriganaBuilder.apply(
            to: slot.streamingLabel,
            text: trimmed,
            font: Self.secondaryTranscriptFont,
            textColor: .secondaryLabel
        )
    }

    private func removeTutorLiveMeter(animated: Bool, completion: (() -> Void)? = nil) {
        guard let slot = tutorLiveMeterSlot else {
            completion?()
            return
        }

        tutorLiveMeterSlot = nil
        tutorStreamingText = ""
        let row = slot.row
        slot.meter.releaseToRest()

        let removeFromHierarchy = {
            self.contentStack.removeArrangedSubview(row)
            row.removeFromSuperview()
            completion?()
        }

        guard animated else {
            removeFromHierarchy()
            return
        }

        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: [.allowUserInteraction, .curveEaseIn]
        ) {
            slot.column.alpha = 0
            slot.column.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        } completion: { _ in
            removeFromHierarchy()
        }
    }

    private func applyTutorLiveMeterEmphasis(animated: Bool) {
        guard let slot = tutorLiveMeterSlot else { return }

        let apply = {
            slot.meterBubble.setEmphasis(1)
        }

        guard animated else {
            apply()
            return
        }

        UIView.animate(
            withDuration: Self.emphasisAnimationDuration,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: apply
        )
    }

    private func makeTutorLiveMeterView() -> AudioLevelBarsView {
        let meter = AudioLevelBarsView()
        meter.translatesAutoresizingMaskIntoConstraints = false
        meter.barWidth = 8
        meter.barSpacing = 6
        meter.meterHeight = 52
        meter.minBarHeight = 8
        meter.heightFill = 0.95
        meter.levelGain = 1.6
        meter.displayCurve = 1.05
        meter.smoothing = 0.66
        meter.wobbleAmount = 0.08
        meter.diamondFalloff = 0.25
        meter.springiness = 0.5
        meter.historyStride = 2
        meter.barColor = .systemBlue
        return meter
    }

    private func finalizeTutorLiveTranscript(
        text: String,
        sentenceClips: [(sentence: String, clip: RealtimeAudioClip)]
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            removeTutorLiveMeter(animated: true)
            return
        }

        let pairs: [(text: String, clip: RealtimeAudioClip?)]
        if sentenceClips.isEmpty {
            pairs = splitIntoDisplayLines(trimmed).map { ($0, nil) }
        } else {
            pairs = sentenceClips.map { pair in
                (pair.sentence, pair.clip.pcmData.isEmpty ? nil : pair.clip)
            }
        }
        guard !pairs.isEmpty else {
            removeTutorLiveMeter(animated: true)
            return
        }

        guard let slot = tutorLiveMeterSlot else {
            appendAssistantLines(pairs)
            return
        }

        tutorLiveMeterSlot = nil
        tutorStreamingText = ""
        slot.meter.releaseToRest()

        slot.column.removeArrangedSubview(slot.meterBubble)
        slot.meterBubble.removeFromSuperview()

        if pairs.count == 1 {
            let pair = pairs[0]
            let item = LineItem(
                id: UUID(),
                speaker: .assistant,
                text: pair.text,
                audioClip: pair.clip
            )
            let index = lineItems.count
            lineItems.append(item)
            lineLabels.append(slot.streamingLabel)
            lineRows.append(slot.row)
            lineEmphasis.append(1)
            slot.row.tag = index
            slot.row.isUserInteractionEnabled = true
            slot.row.addGestureRecognizer(
                UITapGestureRecognizer(target: self, action: #selector(handleLineTap(_:)))
            )
            applyTranscriptDisplay(
                to: slot.streamingLabel,
                text: item.text,
                speaker: .assistant,
                emphasis: 1
            )
            updateTranscriptEmptyState()
            setActiveLine(index, animated: true)
            followTranscriptBottomIfNeeded(animated: true)
            markSingleTurnEndIfNeeded()
            return
        }

        slot.column.removeArrangedSubview(slot.streamingLabel)
        slot.streamingLabel.removeFromSuperview()
        contentStack.removeArrangedSubview(slot.row)
        slot.row.removeFromSuperview()
        appendAssistantLines(pairs)
    }

    private func appendAssistantLines(_ pairs: [(text: String, clip: RealtimeAudioClip?)]) {
        for (offset, pair) in pairs.enumerated() {
            let item = LineItem(
                id: UUID(),
                speaker: .assistant,
                text: pair.text,
                audioClip: pair.clip
            )
            let index = lineItems.count
            lineItems.append(item)
            let row = makeLineRow(item: item, index: index)
            appendLineRow(
                row,
                at: index,
                entranceDelay: TimeInterval(offset) * Self.multiLineEntranceStagger
            )
        }

        updateTranscriptEmptyState()
        setActiveLine(lineItems.count - 1, animated: true)
        followTranscriptBottomIfNeeded(animated: true)
        markSingleTurnEndIfNeeded()
    }

    private func markSingleTurnEndIfNeeded() {
        guard let limit = configuration.endAfterAssistantResponseCount else { return }
        completedAssistantResponses += 1
        if completedAssistantResponses >= limit {
            shouldEndAfterTutorPlayback = true
        }
    }

    private func completeSingleTurnSessionIfReady(for turn: RealtimeConversationTurn) {
        guard shouldEndAfterTutorPlayback,
              turn == .yourTurn,
              !didNotifySingleTurnCompletion else { return }
        shouldEndAfterTutorPlayback = false
        didNotifySingleTurnCompletion = true
        realtimeService.disconnect()
        sessionDelegate?.realtimeTutorViewControllerDidFinishSingleTurnSession(self)
    }

    // MARK: - Plain transcript lines

    private func speakerSide(for speaker: Speaker) -> SpeakerSide {
        switch speaker {
        case .assistant: return .leading
        case .user: return .trailing
        }
    }

    private func showsSpeakerLabel(at index: Int) -> Bool {
        guard lineItems.indices.contains(index) else { return true }
        if index == 0 { return true }
        return lineItems[index].speaker != lineItems[index - 1].speaker
    }

    private func speakerPrefix(for speaker: Speaker) -> String {
        switch speaker {
        case .assistant: return "Tutor:"
        case .user: return "You:"
        }
    }

    private func textColor(for speaker: Speaker, emphasis: CGFloat) -> UIColor {
        switch speaker {
        case .user:
            let alpha = 0.62 + 0.38 * emphasis
            return UIColor.systemBlue.withAlphaComponent(alpha)
        case .assistant:
            let alpha = 0.7 + 0.3 * emphasis
            return UIColor.secondaryLabel.withAlphaComponent(alpha)
        }
    }

    private static func font(for speaker: Speaker) -> UIFont {
        switch speaker {
        case .user: return transcriptFont
        case .assistant: return secondaryTranscriptFont
        }
    }

    private func makeLineRow(item: LineItem, index: Int) -> UIView {
        let side = speakerSide(for: item.speaker)
        let lineContainer = UIView()
        lineContainer.translatesAutoresizingMaskIntoConstraints = false
        lineContainer.tag = index
        lineContainer.isUserInteractionEnabled = true
        lineContainer.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(handleLineTap(_:)))
        )

        let column = UIStackView()
        column.translatesAutoresizingMaskIntoConstraints = false
        column.axis = .vertical
        column.spacing = 6
        column.alignment = side == .leading ? .leading : .trailing

        let speakerLabel = UILabel()
        speakerLabel.font = GrammarJapaneseTypography.scenarioSpeakerFont
        speakerLabel.textColor = .secondaryLabel
        speakerLabel.text = speakerPrefix(for: item.speaker)
        let speakerWrapper = Self.insetMetadataWrapper(around: speakerLabel, side: side)
        speakerWrapper.isHidden = !showsSpeakerLabel(at: index)

        let label = JapaneseFuriganaBuilder.makeTranscriptLabel(font: Self.font(for: item.speaker))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = side == .leading ? .left : .right
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        applyTranscriptDisplay(to: label, text: item.text, speaker: item.speaker, emphasis: 0)

        column.addArrangedSubview(speakerWrapper)
        column.addArrangedSubview(label)

        lineContainer.addSubview(column)
        lineLabels.append(label)

        let maxWidth = column.widthAnchor.constraint(
            lessThanOrEqualTo: lineContainer.widthAnchor,
            multiplier: Self.messageColumnMaxWidthRatio
        )
        maxWidth.priority = .required

        var constraints: [NSLayoutConstraint] = [
            column.topAnchor.constraint(equalTo: lineContainer.topAnchor),
            column.bottomAnchor.constraint(equalTo: lineContainer.bottomAnchor),
            maxWidth,
        ]

        switch side {
        case .leading:
            constraints += [
                column.leadingAnchor.constraint(equalTo: lineContainer.leadingAnchor),
                column.trailingAnchor.constraint(lessThanOrEqualTo: lineContainer.trailingAnchor),
            ]
        case .trailing:
            constraints += [
                column.trailingAnchor.constraint(equalTo: lineContainer.trailingAnchor),
                column.leadingAnchor.constraint(greaterThanOrEqualTo: lineContainer.leadingAnchor),
            ]
        }

        NSLayoutConstraint.activate(constraints)
        return lineContainer
    }

    private func appendLineRow(
        _ row: UIView,
        at index: Int,
        animateEntrance: Bool = true,
        entranceDelay: TimeInterval = 0
    ) {
        if index > 0 {
            let currentSpeaker = lineItems[index].speaker
            let previousSpeaker = lineItems[index - 1].speaker
            let spacing: CGFloat = currentSpeaker == previousSpeaker ? 20 : 48
            if let previousRow = lineRows.last {
                contentStack.setCustomSpacing(spacing, after: previousRow)
            }
        }
        contentStack.addArrangedSubview(row)
        lineRows.append(row)
        lineEmphasis.append(0)

        guard animateEntrance, lineItems.indices.contains(index) else { return }
        animateLineEntrance(
            for: row,
            speaker: lineItems[index].speaker,
            delay: entranceDelay
        )
    }

    private func animateLineEntrance(for row: UIView, speaker: Speaker, delay: TimeInterval) {
        guard let column = row.subviews.first else { return }

        let side = speakerSide(for: speaker)
        let slideDistance = Self.lineEntranceSlideDistance
        let startTranslationX = side == .leading ? -slideDistance : slideDistance

        column.alpha = 0
        column.transform = CGAffineTransform(translationX: startTranslationX, y: Self.lineEntranceVerticalOffset)
            .scaledBy(x: Self.lineEntranceInitialScale, y: Self.lineEntranceInitialScale)

        view.layoutIfNeeded()

        UIView.animate(
            withDuration: Self.lineEntranceDuration,
            delay: delay,
            usingSpringWithDamping: Self.lineEntranceDamping,
            initialSpringVelocity: 0.35,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            column.alpha = 1
            column.transform = .identity
        }
    }

    private func splitIntoDisplayLines(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let sentences = TextToSpeechService.splitIntoSentences(trimmed)
        return sentences.isEmpty ? [trimmed] : sentences
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
            let index = lineItems.count
            lineItems.append(item)
            let row = makeLineRow(item: item, index: index)
            appendLineRow(
                row,
                at: index,
                entranceDelay: TimeInterval(offset) * Self.multiLineEntranceStagger
            )
        }

        updateTranscriptEmptyState()
        setActiveLine(lineItems.count - 1, animated: true)
        followTranscriptBottomIfNeeded(animated: true)
    }

    private func removeStreamingPlaceholder() {
        guard let id = streamingLineID,
              let idx = lineItems.firstIndex(where: { $0.id == id })
        else {
            streamingLineID = nil
            streamingSpeaker = nil
            streamingText = ""
            return
        }

        let row = lineRows[idx]
        contentStack.removeArrangedSubview(row)
        row.removeFromSuperview()

        lineRows.remove(at: idx)
        lineItems.remove(at: idx)
        lineLabels.remove(at: idx)
        lineEmphasis.remove(at: idx)

        if let activeLineIndex, activeLineIndex == idx {
            self.activeLineIndex = nil
        } else if let activeLineIndex, activeLineIndex > idx {
            self.activeLineIndex = activeLineIndex - 1
        }

        reindexLineTags(from: idx)
        streamingLineID = nil
        streamingSpeaker = nil
        streamingText = ""
        updateTranscriptEmptyState()
    }

    private func reindexLineTags(from startIndex: Int) {
        guard startIndex < lineRows.count else { return }
        for index in startIndex..<lineRows.count {
            lineRows[index].tag = index
        }
    }

    private func ensureUserStreamingLine() -> FuriganaTranscriptLabel {
        if streamingLineID != nil, streamingSpeaker == .user,
           let id = streamingLineID,
           let idx = lineItems.firstIndex(where: { $0.id == id }),
           lineLabels.indices.contains(idx)
        {
            updateTranscriptEmptyState()
            setActiveLine(idx, animated: false)
            return lineLabels[idx]
        }

        removeStreamingPlaceholder()
        streamingSpeaker = .user
        streamingText = ""

        let item = LineItem(id: UUID(), speaker: .user, text: "…", audioClip: nil)
        streamingLineID = item.id
        let index = lineItems.count
        lineItems.append(item)

        let row = makeLineRow(item: item, index: index)
        appendLineRow(row, at: index, entranceDelay: 0)
        setActiveLine(index, animated: false)
        updateTranscriptEmptyState()
        followTranscriptBottomIfNeeded(animated: false)
        return lineLabels[index]
    }

    private func finalizeUserStreamingLine(text: String, audioClip: RealtimeAudioClip?) {
        removeStreamingPlaceholder()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appendLines(speaker: .user, text: trimmed, wholeClip: audioClip)
    }

    private func updateTranscriptEmptyState() {
        emptyStateLabel.isHidden = !lineItems.isEmpty || tutorLiveMeterSlot != nil
    }

    private func refreshAllTranscriptLabels() {
        for (idx, item) in lineItems.enumerated() {
            guard lineLabels.indices.contains(idx) else { continue }
            let emphasis = lineEmphasis.indices.contains(idx) ? lineEmphasis[idx] : 0
            applyTranscriptDisplay(to: lineLabels[idx], text: item.text, speaker: item.speaker, emphasis: emphasis)
        }
    }

    private func applyTranscriptDisplay(
        to label: FuriganaTranscriptLabel,
        text: String,
        speaker: Speaker,
        emphasis: CGFloat
    ) {
        if text == "…" {
            label.textInsets = .zero
            label.attributedText = nil
            label.font = Self.font(for: speaker)
            label.text = text
            label.textColor = textColor(for: speaker, emphasis: emphasis)
            return
        }

        JapaneseFuriganaBuilder.apply(
            to: label,
            text: text,
            font: Self.font(for: speaker),
            textColor: textColor(for: speaker, emphasis: emphasis)
        )
    }

    // MARK: - Active line emphasis

    private func setActiveLine(_ newIndex: Int?, animated: Bool) {
        guard newIndex != activeLineIndex else { return }
        if newIndex != nil {
            lineChangeHaptic.impactOccurred()
        }
        activeLineIndex = newIndex

        if lineEmphasis.count != lineLabels.count {
            lineEmphasis = Array(repeating: 0, count: lineLabels.count)
        }

        let target = lineLabels.indices.map { idx in
            activeLineIndex == idx ? CGFloat(1) : CGFloat(0)
        }

        guard animated else {
            lineEmphasis = target
            applyLineStylesFromEmphasis()
            return
        }

        UIView.animate(
            withDuration: Self.emphasisAnimationDuration,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.lineEmphasis = target
            self.applyLineStylesFromEmphasis()
        }
    }

    private func applyLineStylesFromEmphasis() {
        for (index, label) in lineLabels.enumerated() {
            guard lineItems.indices.contains(index) else { continue }
            let emphasis: CGFloat
            if tutorLiveMeterSlot != nil {
                emphasis = 0
            } else {
                emphasis = lineEmphasis.indices.contains(index) ? lineEmphasis[index] : 0
            }
            let item = lineItems[index]
            applyTranscriptDisplay(to: label, text: item.text, speaker: item.speaker, emphasis: emphasis)
        }
    }

    // MARK: - Scrolling

    private func scrollTranscriptToBottom(animated: Bool) {
        view.layoutIfNeeded()
        let inset = scrollView.adjustedContentInset
        let visibleHeight = scrollView.bounds.height - inset.top - inset.bottom
        let bottomOffset = scrollView.contentSize.height - visibleHeight
        let y = max(-inset.top, bottomOffset + inset.bottom)
        scrollView.setContentOffset(CGPoint(x: 0, y: y), animated: animated)
    }

    // MARK: - Actions

    private func presentSentenceFocus(forLineAt index: Int) {
        guard lineItems.indices.contains(index) else { return }
        let item = lineItems[index]
        let contextLines = lineItems.map { line -> DialogueNuanceContext.Line in
            let speaker: String
            switch line.speaker {
            case .user: speaker = "You"
            case .assistant: speaker = "Tutor"
            }
            return DialogueNuanceContext.Line(speaker: speaker, japanese: line.text, english: nil)
        }
        let scrub = SentenceScrubExperimentViewController(
            sentence: item.text,
            recordedClip: item.audioClip,
            onReplayClip: { [weak self] clip in
                self?.realtimeService.replayRecordedClip(clip)
            },
            dialogueContext: DialogueNuanceContext.around(lines: contextLines, focusedIndex: index)
        )
        navigationController?.pushViewController(scrub, animated: true)
    }

    @objc private func handleLineTap(_ gesture: UITapGestureRecognizer) {
        guard let row = gesture.view else { return }
        presentSentenceFocus(forLineAt: row.tag)
    }

    // MARK: - Styling helpers

    private static func insetMetadataWrapper(around label: UILabel, side: SpeakerSide) -> UIView {
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(label)

        switch side {
        case .leading:
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: wrapper.topAnchor),
                label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: metadataHorizontalInset),
                label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
                label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            ])
        case .trailing:
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: wrapper.topAnchor),
                label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -metadataHorizontalInset),
                label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            ])
        }
        return wrapper
    }

    private static func configureGlassTransportButton(
        _ button: UIButton,
        glyphView: UIImageView,
        symbolName: String,
        glyphPointSize: CGFloat,
        glyphColor: UIColor,
        accessibilityLabel: String
    ) {
        var config = UIButton.Configuration.glass()
        config.cornerStyle = .capsule
        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = accessibilityLabel

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: glyphPointSize, weight: .semibold)
        glyphView.image = UIImage(systemName: symbolName, withConfiguration: symbolConfig)?
            .withRenderingMode(.alwaysTemplate)
        glyphView.tintColor = glyphColor
        glyphView.preferredSymbolConfiguration = symbolConfig
        glyphView.contentMode = .scaleAspectFit
        glyphView.isUserInteractionEnabled = false
        glyphView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(glyphView)

        let glyphDimension = glyphPointSize + 4
        NSLayoutConstraint.activate([
            glyphView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            glyphView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            glyphView.widthAnchor.constraint(equalToConstant: glyphDimension),
            glyphView.heightAnchor.constraint(equalToConstant: glyphDimension),
        ])
    }

    private static let transcriptFont: UIFont = {
        let base = UIFont.systemFont(ofSize: 32, weight: .heavy)
        return UIFontMetrics(forTextStyle: .title1).scaledFont(for: base)
    }()

    private static let secondaryTranscriptFont: UIFont = {
        let base = UIFont.preferredFont(forTextStyle: .subheadline)
        return .systemFont(ofSize: base.pointSize, weight: .regular)
    }()

    private static let turnStatusFont: UIFont = {
        let base = UIFont.systemFont(ofSize: 13, weight: .medium)
        return UIFontMetrics(forTextStyle: .caption1).scaledFont(for: base)
    }()

    private static let transportButtonSize: CGFloat = 50
    private static let transportGlyphPointSize: CGFloat = 22
    private static let transportGlyphColor = UIColor.systemYellow
    private static let micHighlightColor = UIColor.systemYellow
    private static let micIdleColor = UIColor.label
    private static let userMeterColor = UIColor.systemBlue
    private static let tutorMeterColor = UIColor.label
    private static let messageColumnMaxWidthRatio: CGFloat = 0.82
    private static let metadataHorizontalInset: CGFloat = 20
    private static let emphasisAnimationDuration: TimeInterval = 0.35
    private static let scrollTopContentInsetExtra: CGFloat = 12
    private static let scrollBottomContentInsetExtra: CGFloat = 16
    private static let transcriptFollowThreshold: CGFloat = 96
    private static let lineEntranceSlideDistance: CGFloat = 26
    private static let lineEntranceVerticalOffset: CGFloat = 10
    private static let lineEntranceInitialScale: CGFloat = 0.93
    private static let lineEntranceDuration: TimeInterval = 0.44
    private static let lineEntranceDamping: CGFloat = 0.84
    private static let multiLineEntranceStagger: TimeInterval = 0.07
}

// MARK: - RealtimeServiceDelegate

extension RealtimeTutorViewController: RealtimeServiceDelegate {

    func realtimeService(_ service: RealtimeService, didChangeConnectionState state: RealtimeConnectionState) {
        updateTransportControls()
        updateMicButtonUI()
    }

    func realtimeService(_ service: RealtimeService, didChangeTurn turn: RealtimeConversationTurn) {
        if turn != lastTurnForHaptic, turn == .yourTurn || turn == .tutorTurn {
            turnHaptic.impactOccurred()
        }
        lastTurnForHaptic = turn
        updateTurnUI(turn)
        updateTransportControls()
        completeSingleTurnSessionIfReady(for: turn)
    }

    func realtimeService(_ service: RealtimeService, didReceiveUserTranscriptDelta delta: String) {
        let label = ensureUserStreamingLine()
        if streamingText.isEmpty {
            streamingText = delta
        } else {
            streamingText += delta
        }
        applyTranscriptDisplay(to: label, text: streamingText, speaker: .user, emphasis: 1)
    }

    func realtimeService(
        _ service: RealtimeService,
        didReceiveUserTranscript text: String,
        audioClip: RealtimeAudioClip?
    ) {
        finalizeUserStreamingLine(text: text, audioClip: audioClip)
    }

    func realtimeService(_ service: RealtimeService, didReceiveAssistantTranscriptDelta delta: String) {
        tutorStreamingText += delta
        applyTutorStreamingDisplay(tutorStreamingText)
    }

    func realtimeService(
        _ service: RealtimeService,
        didCompleteAssistantTranscript text: String,
        sentenceClips: [(sentence: String, clip: RealtimeAudioClip)]
    ) {
        finalizeTutorLiveTranscript(text: text, sentenceClips: sentenceClips)
    }

    func realtimeService(_ service: RealtimeService, didUpdateUsage usage: RealtimeTokenUsage) {
        usageLabel.text = usage.summaryLine
    }

    func realtimeService(_ service: RealtimeService, didEncounterError error: Error) {
        updateTransportControls()
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
        // User speech is plain transcript only — no live meter in the dock or scroll view.
    }

    func realtimeService(_ service: RealtimeService, didUpdateOutputLevel level: Float) {
        guard realtimeService.conversationTurn == .tutorTurn else { return }
        pushTutorLiveMeterLevel(level)
    }

    func realtimeService(_ service: RealtimeService, didChangeMicMuted isMuted: Bool) {
        updateMicButtonUI()
    }
}

// MARK: - UIScrollViewDelegate

extension RealtimeTutorViewController: UIScrollViewDelegate {

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        transcriptFollowsBottom = false
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            refreshTranscriptFollowState()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        refreshTranscriptFollowState()
    }
}
