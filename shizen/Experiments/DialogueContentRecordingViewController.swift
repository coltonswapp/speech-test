//
//  DialogueContentRecordingViewController.swift
//  shizen
//
//  Full-screen 9:16 stage for Control Center screen recording. Shared chrome
//  (hook, glass bubbles, watermark, record mode) with conversation, two-pass,
//  and response-quiz directors.
//

import TTSCore
import UIKit

final class DialogueContentRecordingViewController: UIViewController, DialogueContentDirectorDelegate {

    private var session: DialogueContentSession

    private let stageView = UIView()
    private let rollView = UIView()
    private let hookStack = UIStackView()
    private let hookLabel = UILabel()
    private let beatCaptionLabel = UILabel()
    private let watermarkLabel = UILabel()
    private let optionsStack = UIStackView()
    private var optionRows: [DialogueContentOptionRow] = []

    private var bubbleRows: [DialogueContentStackRow] = []
    private var activePlaybackLines: [DialogueContentSpokenLine] = []

    private let audioPlayer = GrammarAudioPlayer()
    private var audioGeneration = 0
    private var fullDirector: DialogueContentFullConversationDirector?
    private var responseDirector: DialogueContentResponseQuizDirector?

    private var isRecordMode = false {
        didSet {
            guard isRecordMode != oldValue else { return }
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()
            navigationController?.setNavigationBarHidden(isRecordMode, animated: true)
        }
    }

    private enum Phase {
        case idle
        case armed
        case playing
        case finished
    }

    private var phase: Phase = .idle
    private var playButton: UIBarButtonItem?
    private var overflowButton: UIBarButtonItem?
    private var introGeneration = 0
    private var conversationPass: ConversationPass = .single
    private var showsEnglishSubtitles = false
    private var conversationPlaybackRate: Float = 1
    private var watermarkPulseLink: CADisplayLink?
    private var lastKaraokeTime: TimeInterval = 0

    private enum ConversationPass {
        case single
        case first
        case second
    }

    private static let japaneseFont = UIFont.systemFont(ofSize: 22, weight: .medium)
    /// Clear of TikTok/Reels like/comment rails, but keep bubbles wide.
    private static let horizontalGutter: CGFloat = 36
    /// Extra inset on the inner edge so left/right bubbles don’t share a leading line.
    private static let conversationInset: CGFloat = 44
    private static let bottomGutter: CGFloat = 64
    private static let bubbleSpacing: CGFloat = 14
    /// Stack gap before/after a stage row — matches live Dialogue.
    private static let stageLineRowSpacing: CGFloat = 52
    /// Extra stack gap opened while a stage line is focused.
    private static let stageLineFocusExtraSpacing: CGFloat = 24
    private static let incomingOffset: CGFloat = 88
    private static let watermarkPulseHz: Double = 0.45
    private static let watermarkPulseTravel: CGFloat = 10

    init(session: DialogueContentSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var prefersStatusBarHidden: Bool { isRecordMode }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }

    override var prefersHomeIndicatorAutoHidden: Bool { isRecordMode }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = session.format.title
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground
        configureNavigation()
        configureStage()
        resetStage(animated: false)
        let tap = UITapGestureRecognizer(target: self, action: #selector(stageTapped))
        stageView.addGestureRecognizer(tap)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopWatermarkPulse(reset: false)
        if isMovingFromParent || isBeingDismissed {
            stopPlayback()
            if isRecordMode {
                isRecordMode = false
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if isRecordMode {
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        PlaybackAudioSession.prewarm()
        if let url = GrammarAudioCatalog.resolveLocalURL(
            publishedAudioUrl: session.example.publishedAudioUrl,
            audioKey: session.example.audioKey,
            cacheMetadata: session.example.remoteAudioCacheMetadata
        ) {
            DialogueAlignmentMetadata.prewarmPayload(from: url)
        }
    }

    // MARK: - Chrome

    private func configureNavigation() {
        let play = UIBarButtonItem(
            image: UIImage(systemName: "play.fill"),
            style: .plain,
            target: self,
            action: #selector(playTapped)
        )
        play.accessibilityLabel = "Play"
        playButton = play

        let record = UIBarButtonItem(
            title: "Record",
            style: .plain,
            target: self,
            action: #selector(recordTapped)
        )

        let overflow = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: makeOverflowMenu()
        )
        overflow.accessibilityLabel = "More"
        overflowButton = overflow
        navigationItem.rightBarButtonItems = [overflow, record, play]
    }

    private func makeOverflowMenu() -> UIMenu {
        let selectedStyle = ExperimentSettings.dialogueContentBubbleStyle
        let styleActions = DialogueContentBubbleStyle.allCases.map { style in
            UIAction(
                title: style.title,
                subtitle: style.subtitle,
                image: UIImage(systemName: style.symbolName),
                state: style == selectedStyle ? .on : .off
            ) { [weak self] _ in
                self?.setBubbleStyle(style)
            }
        }
        let styleMenu = UIMenu(
            title: "Bubble style",
            options: [.displayInline, .singleSelection],
            children: styleActions
        )
        let selectedRate = ExperimentSettings.dialogueContentSecondPassRate
        let rateActions = DialogueContentSecondPassRate.allCases.map { rate in
            UIAction(
                title: rate.title,
                state: rate == selectedRate ? .on : .off
            ) { [weak self] _ in
                self?.setSecondPassRate(rate)
            }
        }
        let rateMenu = UIMenu(
            title: "Second pass speed",
            options: [.displayInline, .singleSelection],
            children: rateActions
        )
        return UIMenu(children: [
            UIAction(title: "Restart", image: UIImage(systemName: "arrow.counterclockwise")) { [weak self] _ in
                self?.restartTapped()
            },
            UIAction(
                title: "Edit title",
                subtitle: session.displayHookText,
                image: UIImage(systemName: "textformat")
            ) { [weak self] _ in
                self?.editTitleTapped()
            },
            UIAction(title: "Edit lines", image: UIImage(systemName: "list.bullet")) { [weak self] _ in
                self?.editLinesTapped()
            },
            UIAction(title: "Hashtags", image: UIImage(systemName: "number")) { [weak self] _ in
                self?.presentHashtags()
            },
            UIAction(
                title: "Stage directions",
                subtitle: "Captions between lines",
                image: UIImage(systemName: "text.aligncenter"),
                state: ExperimentSettings.dialogueContentShowsStageLines ? .on : .off
            ) { [weak self] _ in
                self?.toggleStageLines()
            },
            UIAction(
                title: "Token sync",
                subtitle: "Highlight on the spoken word",
                image: UIImage(systemName: "highlighter"),
                state: ExperimentSettings.dialogueShowsTokenSync ? .on : .off
            ) { [weak self] _ in
                self?.toggleTokenSync()
            },
            makeTokenSyncHighlightStyleMenu(),
            UIAction(
                title: "Highlight colors",
                subtitle: highlightColorsSubtitle(),
                image: UIImage(systemName: "paintpalette")
            ) { [weak self] _ in
                self?.presentHighlightColors()
            },
            styleMenu,
            rateMenu,
        ])
    }

    private func highlightColorsSubtitle() -> String {
        if let preset = DialogueHighlightColorPreset.matching(
            leading: ExperimentSettings.dialogueHighlightLeadingColor,
            trailing: ExperimentSettings.dialogueHighlightTrailingColor
        ) {
            return preset.title
        }
        let leading = ExperimentSettings.dialogueHighlightLeadingColor.title
        let trailing = ExperimentSettings.dialogueHighlightTrailingColor.title
        return "\(leading) · \(trailing)"
    }

    private func presentHighlightColors() {
        let picker = DialogueHighlightColorPickerViewController()
        picker.onChange = { [weak self] in
            self?.overflowButton?.menu = self?.makeOverflowMenu()
            self?.refreshHighlightColors()
        }
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    private func refreshHighlightColors() {
        for row in bubbleRows {
            (row as? DialogueContentBubbleRow)?.refreshUnderglow()
        }
        refreshTokenKaraokeDisplay()
    }

    private func toggleTokenSync() {
        ExperimentSettings.dialogueShowsTokenSync.toggle()
        overflowButton?.menu = makeOverflowMenu()
        refreshTokenKaraokeDisplay()
    }

    private func makeTokenSyncHighlightStyleMenu() -> UIMenu {
        let selected = ExperimentSettings.dialogueTokenSyncHighlightStyle
        let actions = DialogueTokenSyncHighlightStyle.allCases.map { style in
            UIAction(
                title: style.title,
                subtitle: style.subtitle,
                state: style == selected ? .on : .off
            ) { [weak self] _ in
                self?.setTokenSyncHighlightStyle(style)
            }
        }
        return UIMenu(
            title: "Token highlight",
            image: UIImage(systemName: "paintbrush.pointed"),
            options: .singleSelection,
            children: actions
        )
    }

    private func setTokenSyncHighlightStyle(_ style: DialogueTokenSyncHighlightStyle) {
        ExperimentSettings.dialogueTokenSyncHighlightStyle = style
        overflowButton?.menu = makeOverflowMenu()
        refreshTokenKaraokeDisplay()
    }

    private func refreshTokenKaraokeDisplay() {
        for row in bubbleRows {
            (row as? DialogueContentBubbleRow)?.invalidateKaraoke()
        }
        applyTokenKaraoke(at: lastKaraokeTime)
    }

    private func toggleStageLines() {
        ExperimentSettings.dialogueContentShowsStageLines.toggle()
        overflowButton?.menu = makeOverflowMenu()
    }

    private func setSecondPassRate(_ rate: DialogueContentSecondPassRate) {
        ExperimentSettings.dialogueContentSecondPassRate = rate
        overflowButton?.menu = makeOverflowMenu()
        beatCaptionLabel.text = rate.beatCaption
    }

    private func setBubbleStyle(_ style: DialogueContentBubbleStyle) {
        ExperimentSettings.dialogueContentBubbleStyle = style
        overflowButton?.menu = makeOverflowMenu()
        let bubbleWidth = maxBubbleTextWidth()
        let captionWidth = maxCaptionTextWidth()
        for row in bubbleRows {
            row.applyStyle(style)
            if row is DialogueContentCaptionRow {
                row.setPreferredTextWidth(captionWidth)
            } else {
                row.setPreferredTextWidth(bubbleWidth)
            }
        }
        restackBubbles(animated: true, completion: nil)
        refreshTokenKaraokeDisplay()
    }

    private func maxBubbleTextWidth() -> CGFloat {
        view.bounds.width - Self.horizontalGutter * 2 - Self.conversationInset
    }

    private func maxCaptionTextWidth() -> CGFloat {
        view.bounds.width - Self.horizontalGutter * 2
    }

    private func bringStageOverlayToFront() {
        rollView.bringSubviewToFront(optionsStack)
        rollView.bringSubviewToFront(hookStack)
        stageView.bringSubviewToFront(watermarkLabel)
    }

    private func updatePlayButton() {
        let playing = phase == .playing
        playButton?.image = UIImage(systemName: playing ? "pause.fill" : "play.fill")
        playButton?.accessibilityLabel = playing ? "Pause" : "Play"
    }

    // MARK: - Stage

    private func configureStage() {
        stageView.translatesAutoresizingMaskIntoConstraints = false
        stageView.backgroundColor = ExperimentPalette.pageBackground
        stageView.clipsToBounds = true
        view.addSubview(stageView)

        rollView.translatesAutoresizingMaskIntoConstraints = false
        rollView.backgroundColor = .clear
        rollView.isUserInteractionEnabled = false
        stageView.addSubview(rollView)

        hookLabel.translatesAutoresizingMaskIntoConstraints = false
        hookLabel.text = session.displayHookText
        hookLabel.font = UIFontMetrics(forTextStyle: .title2)
            .scaledFont(for: .systemFont(ofSize: 26, weight: .bold))
        hookLabel.textColor = .label
        hookLabel.textAlignment = .center
        hookLabel.numberOfLines = 0
        hookLabel.adjustsFontForContentSizeCategory = true

        beatCaptionLabel.translatesAutoresizingMaskIntoConstraints = false
        beatCaptionLabel.font = UIFontMetrics(forTextStyle: .callout)
            .scaledFont(for: .systemFont(ofSize: 16, weight: .medium))
        beatCaptionLabel.textColor = .secondaryLabel
        beatCaptionLabel.textAlignment = .center
        beatCaptionLabel.numberOfLines = 1
        beatCaptionLabel.adjustsFontForContentSizeCategory = true
        beatCaptionLabel.text = ExperimentSettings.dialogueContentSecondPassRate.beatCaption
        beatCaptionLabel.isHidden = true

        hookStack.axis = .vertical
        hookStack.alignment = .center
        hookStack.spacing = 8
        hookStack.translatesAutoresizingMaskIntoConstraints = false
        hookStack.addArrangedSubview(hookLabel)
        hookStack.addArrangedSubview(beatCaptionLabel)
        rollView.addSubview(hookStack)

        optionsStack.axis = .vertical
        optionsStack.spacing = 10
        optionsStack.translatesAutoresizingMaskIntoConstraints = false
        optionsStack.alpha = 0
        optionsStack.isHidden = true
        optionsStack.isUserInteractionEnabled = false
        rollView.addSubview(optionsStack)

        watermarkLabel.text = "shizenapp.com"
        watermarkLabel.font = .systemFont(ofSize: 11, weight: .medium)
        watermarkLabel.textColor = .secondaryLabel
        watermarkLabel.alpha = 0.65
        watermarkLabel.textAlignment = .center
        watermarkLabel.translatesAutoresizingMaskIntoConstraints = false
        stageView.addSubview(watermarkLabel)

        NSLayoutConstraint.activate([
            stageView.topAnchor.constraint(equalTo: view.topAnchor),
            stageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            rollView.topAnchor.constraint(equalTo: stageView.topAnchor),
            rollView.leadingAnchor.constraint(equalTo: stageView.leadingAnchor),
            rollView.trailingAnchor.constraint(equalTo: stageView.trailingAnchor),
            rollView.bottomAnchor.constraint(equalTo: stageView.bottomAnchor),

            hookStack.centerXAnchor.constraint(equalTo: rollView.centerXAnchor),
            hookStack.centerYAnchor.constraint(equalTo: rollView.centerYAnchor),
            hookStack.leadingAnchor.constraint(
                greaterThanOrEqualTo: rollView.leadingAnchor,
                constant: Self.horizontalGutter
            ),
            hookStack.trailingAnchor.constraint(
                lessThanOrEqualTo: rollView.trailingAnchor,
                constant: -Self.horizontalGutter
            ),

            optionsStack.centerXAnchor.constraint(equalTo: rollView.centerXAnchor),
            optionsStack.topAnchor.constraint(equalTo: rollView.centerYAnchor, constant: 28),
            optionsStack.leadingAnchor.constraint(equalTo: rollView.leadingAnchor, constant: Self.horizontalGutter),
            optionsStack.trailingAnchor.constraint(equalTo: rollView.trailingAnchor, constant: -Self.horizontalGutter),

            watermarkLabel.centerXAnchor.constraint(equalTo: stageView.centerXAnchor),
            watermarkLabel.bottomAnchor.constraint(
                equalTo: view.bottomAnchor,
                constant: -Self.bottomGutter
            ),
        ])
    }

    private func resetStage(animated: Bool) {
        stopPlayback()
        phase = isRecordMode ? .armed : .idle
        updatePlayButton()

        let rows = bubbleRows
        bubbleRows = []
        let resetHook = {
            self.hookLabel.text = self.session.displayHookText
            self.hookLabel.textColor = .label
            self.beatCaptionLabel.isHidden = true
            self.hookStack.transform = .identity
            self.optionsStack.alpha = 0
            self.optionsStack.isHidden = true
            self.optionRows.forEach { $0.removeFromSuperview() }
            self.optionRows = []
        }

        let clearRows = {
            rows.forEach { $0.removeFromSuperview() }
        }

        if animated {
            UIView.animate(withDuration: 0.3, animations: {
                resetHook()
                rows.forEach { $0.alpha = 0 }
                self.hookStack.alpha = 1
                self.hookStack.isHidden = false
            }, completion: { _ in
                clearRows()
            })
        } else {
            resetHook()
            clearRows()
            hookStack.alpha = 1
            hookStack.isHidden = false
        }
    }

    private func prepareGrayStage() {
        stopPlayback()
        bubbleRows.forEach { $0.removeFromSuperview() }
        bubbleRows = []
        optionRows.forEach { $0.removeFromSuperview() }
        optionRows = []
        optionsStack.alpha = 0
        optionsStack.isHidden = true
        hookLabel.text = session.displayHookText
        hookLabel.textColor = .label
        beatCaptionLabel.isHidden = true
        hookStack.transform = .identity
        hookStack.alpha = 0
        hookStack.isHidden = true
    }

    // MARK: - Actions

    @objc private func playTapped() {
        switch phase {
        case .playing:
            pausePlayback()
        case .idle, .armed, .finished:
            beginPlayback(skipHolds: !isRecordMode)
        }
    }

    @objc private func recordTapped() {
        isRecordMode = true
        prepareGrayStage()
        introGeneration += 1
        let generation = introGeneration
        phase = .armed
        updatePlayButton()
        startWatermarkPulse()
        DispatchQueue.main.asyncAfter(deadline: .now() + DialogueContentPlaybackTiming.recordStartDelay) { [weak self] in
            guard let self, self.introGeneration == generation, self.isRecordMode else { return }
            self.beginPlayback(skipHolds: false)
        }
    }

    @objc private func restartTapped() {
        isRecordMode = false
        resetStage(animated: true)
    }

    private func editTitleTapped() {
        let alert = UIAlertController(
            title: "Title",
            message: "Hook shown at the start of the replay.",
            preferredStyle: .alert
        )
        alert.addTextField { [weak self] field in
            field.text = self?.session.displayHookText
            field.placeholder = self?.session.format.defaultHookText
            field.autocapitalizationType = .sentences
            field.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self else { return }
            let typed = alert.textFields?.first?.text ?? ""
            self.session.hookText = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            self.hookLabel.text = self.session.displayHookText
            self.overflowButton?.menu = self.makeOverflowMenu()
        })
        present(alert, animated: true)
    }

    @objc private func stageTapped() {
        switch phase {
        case .armed:
            beginPlayback(skipHolds: false)
        case .playing:
            pausePlayback()
        case .idle:
            break
        case .finished:
            if isRecordMode {
                isRecordMode = false
                phase = .idle
                updatePlayButton()
            }
        }
    }

    private func pausePlayback() {
        stopPlayback()
        isRecordMode = false
        phase = .idle
        updatePlayButton()
    }

    private func editLinesTapped() {
        stopPlayback()
        isRecordMode = false
        let picker = DialogueContentLinePickerViewController(
            collection: session.collection,
            scenario: session.scenario,
            format: session.format,
            mode: .editExisting(session)
        )
        picker.onSessionReady = { [weak self] session in
            self?.session = session
            self?.title = session.format.title
            self?.overflowButton?.menu = self?.makeOverflowMenu()
            self?.isRecordMode = false
            self?.resetStage(animated: false)
        }
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    private func presentHashtags() {
        let picker = DialogueContentHashtagPickerViewController()
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    // MARK: - Playback

    private func beginPlayback(skipHolds: Bool) {
        let keepRecordMode = isRecordMode
        prepareGrayStage()
        introGeneration += 1
        let generation = introGeneration
        isRecordMode = keepRecordMode
        phase = .playing
        updatePlayButton()
        configureConversationPassForStart()
        startWatermarkPulse()
        PlaybackAudioSession.activateForPlayback { _ in }

        runHookIntro(generation: generation) { [weak self] in
            guard let self, self.introGeneration == generation else { return }
            self.startDirector(skipHolds: skipHolds)
        }
    }

    private func configureConversationPassForStart() {
        switch session.format {
        case .twoPassReplay:
            conversationPass = .first
            showsEnglishSubtitles = false
            conversationPlaybackRate = 1
        case .fullConversation, .responseQuiz:
            conversationPass = .single
            showsEnglishSubtitles = false
            conversationPlaybackRate = 1
        }
    }

    private func runHookIntro(generation: Int, then continuePlayback: @escaping () -> Void) {
        hookLabel.text = session.displayHookText
        beatCaptionLabel.isHidden = true
        hookStack.isHidden = false
        hookStack.alpha = 0
        hookStack.transform = CGAffineTransform(translationX: 0, y: 18)
        bringStageOverlayToFront()
        DispatchQueue.main.asyncAfter(deadline: .now() + DialogueContentPlaybackTiming.hookPreEnterPause) {
            guard self.introGeneration == generation else { return }
            UIView.animate(
                withDuration: DialogueContentPlaybackTiming.hookEnterDuration,
                delay: 0,
                usingSpringWithDamping: 0.88,
                initialSpringVelocity: 0.4
            ) {
                self.hookStack.alpha = 1
                self.hookStack.transform = .identity
            } completion: { _ in
                guard self.introGeneration == generation else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + DialogueContentPlaybackTiming.hookHold) {
                    guard self.introGeneration == generation else { return }
                    UIView.animate(
                        withDuration: DialogueContentPlaybackTiming.hookFadeToGray,
                        delay: 0,
                        options: [.curveEaseInOut]
                    ) {
                        self.hookStack.alpha = 0
                        self.hookLabel.textColor = .secondaryLabel
                    } completion: { _ in
                        guard self.introGeneration == generation else { return }
                        self.hookStack.isHidden = true
                        self.hookLabel.textColor = .label
                        continuePlayback()
                    }
                }
            }
        }
    }

    private func startDirector(skipHolds: Bool) {
        switch session.format {
        case .fullConversation, .twoPassReplay:
            let lines = session.playbackLines(
                includingStageLines: ExperimentSettings.dialogueContentShowsStageLines
            )
            activePlaybackLines = lines
            let director = DialogueContentFullConversationDirector(lines: lines)
            director.delegate = self
            fullDirector = director
            director.start()
        case .responseQuiz:
            guard let prompt = session.prompt, let correct = session.correct else {
                phase = .idle
                updatePlayButton()
                return
            }
            let director = DialogueContentResponseQuizDirector(
                prompt: prompt,
                correct: correct,
                options: session.shuffledResponseOptions()
            )
            director.delegate = self
            responseDirector = director
            director.start(skipHolds: skipHolds)
        }
    }

    private func stopPlayback() {
        introGeneration += 1
        audioGeneration += 1
        audioPlayer.stop()
        fullDirector?.stop()
        fullDirector = nil
        responseDirector?.stop()
        responseDirector = nil
        stopWatermarkPulse(reset: true)
    }

    private func startWatermarkPulse() {
        applyWatermarkRestAppearance()
        guard watermarkPulseLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(handleWatermarkPulseTick))
        link.add(to: .main, forMode: .common)
        watermarkPulseLink = link
    }

    private func stopWatermarkPulse(reset: Bool) {
        watermarkPulseLink?.invalidate()
        watermarkPulseLink = nil
        if reset {
            applyWatermarkRestAppearance()
        }
    }

    private func applyWatermarkRestAppearance() {
        watermarkLabel.textColor = .secondaryLabel
        watermarkLabel.alpha = 0.65
        watermarkLabel.transform = .identity
    }

    @objc private func handleWatermarkPulseTick(_ link: CADisplayLink) {
        let wave = 0.5 + 0.5 * sin(link.timestamp * 2 * Double.pi * Self.watermarkPulseHz)
        let flash = CGFloat(pow(wave, 2))
        watermarkLabel.alpha = 0.48 + 0.32 * flash
        watermarkLabel.transform = CGAffineTransform(
            translationX: 0,
            y: Self.watermarkPulseTravel * flash
        )
    }

    private func playAudio(for line: DialogueContentSpokenLine) {
        guard session.canPlayAudio(for: line) else {
            notifyAudioFinished()
            return
        }
        audioGeneration += 1
        let generation = audioGeneration
        audioPlayer.stop()
        audioPlayer.playDialogueLine(
            at: line.spokenIndex,
            publishedAudioUrl: session.example.publishedAudioUrl,
            audioKey: session.example.audioKey,
            cacheMetadata: session.example.remoteAudioCacheMetadata,
            dialogueLines: session.spokenTextsForClip,
            fallbackText: line.japanese,
            onTime: { [weak self] time in
                self?.applyTokenKaraoke(at: time, spokenIndex: line.spokenIndex)
            }
        ) { [weak self] in
            guard let self, self.audioGeneration == generation else { return }
            self.notifyAudioFinished()
        }
    }

    private func notifyAudioFinished() {
        fullDirector?.noteAudioFinished()
        responseDirector?.noteAudioFinished()
    }

    // MARK: - Director

    func directorDismissHook() {
        // Hook intro/outro is owned by the stage so Record can loop gray → hook → gray.
    }

    func directorPlaySpokenRun(_ lines: [DialogueContentSpokenLine]) {
        audioGeneration += 1
        let generation = audioGeneration
        let catalog = activePlaybackLines
        audioPlayer.playDialogueSequence(
            spokenIndices: lines.map(\.spokenIndex),
            publishedAudioUrl: session.example.publishedAudioUrl,
            audioKey: session.example.audioKey,
            cacheMetadata: session.example.remoteAudioCacheMetadata,
            dialogueLines: session.spokenTextsForClip,
            fallbackText: lines.first(where: { !$0.isStageLine })?.japanese ?? session.example.japanese,
            rate: conversationPlaybackRate,
            onSpokenIndexStart: { [weak self] spokenIndex in
                guard let self, self.audioGeneration == generation else { return }
                guard let lineIndex = catalog.firstIndex(where: {
                    !$0.isStageLine && $0.spokenIndex == spokenIndex
                }) else { return }
                self.fullDirector?.noteConversationLine(lineIndex)
            },
            onTime: { [weak self] time in
                guard let self, self.audioGeneration == generation else { return }
                self.applyTokenKaraoke(at: time)
            },
            onFinished: { [weak self] in
                guard let self, self.audioGeneration == generation else { return }
                self.fullDirector?.noteConversationAudioFinished()
            }
        )
    }

    func directorPresentLine(_ line: DialogueContentSpokenLine, parkingPrevious: Bool) {
        presentLine(line, parkingPrevious: parkingPrevious) { [weak self] in
            guard let self else { return }
            if line.id == self.session.prompt?.id {
                self.responseDirector?.noteLinePresented()
            }
        }
    }

    private func applyTokenKaraoke(at time: TimeInterval, spokenIndex: Int? = nil) {
        lastKaraokeTime = time
        let tokenSync = ExperimentSettings.dialogueShowsTokenSync ? session.example.tokenSync : nil
        let activeSpoken: Int?
        if let spokenIndex {
            activeSpoken = spokenIndex
        } else if let last = bubbleRows.last as? DialogueContentBubbleRow {
            activeSpoken = last.line.spokenIndex
        } else {
            activeSpoken = nil
        }
        for row in bubbleRows {
            guard let bubble = row as? DialogueContentBubbleRow else { continue }
            bubble.applyKaraoke(
                tokenSync: tokenSync,
                time: time,
                isActive: activeSpoken == bubble.line.spokenIndex
            )
        }
    }

    func directorPlayLine(_ line: DialogueContentSpokenLine) {
        playAudio(for: line)
    }

    func directorPresentOptions(_ options: [DialogueContentSpokenLine], correctID: String) {
        parkActiveIfNeeded(animated: true)
        installOptions(options, correctID: correctID)
        optionsStack.isHidden = false
        optionsStack.alpha = 0
        optionsStack.transform = CGAffineTransform(translationX: 0, y: 24)
        UIView.animate(
            withDuration: DialogueContentPlaybackTiming.lineAnimationDuration,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.4
        ) {
            self.optionsStack.alpha = 1
            self.optionsStack.transform = .identity
        } completion: { _ in
            self.responseDirector?.noteOptionsPresented()
        }
    }

    func directorRevealCorrectOption() {
        for row in optionRows {
            if row.isCorrect {
                row.applySuccess()
            } else {
                row.applyDimmed()
            }
        }
        responseDirector?.noteCorrectRevealed()
    }

    func directorPresentCorrectBubble(_ line: DialogueContentSpokenLine) {
        UIView.animate(withDuration: 0.28, animations: {
            self.optionsStack.alpha = 0
            self.optionsStack.transform = CGAffineTransform(translationX: 0, y: 20)
        }, completion: { _ in
            self.optionsStack.isHidden = true
            self.presentLine(line, parkingPrevious: false) { [weak self] in
                self?.responseDirector?.noteCorrectBubblePresented()
            }
        })
    }

    func directorDidFinish() {
        if session.format == .twoPassReplay, conversationPass == .first {
            beginSecondPass()
            return
        }
        fadeStageToGray { [weak self] in
            guard let self else { return }
            self.phase = .finished
            self.updatePlayButton()
        }
    }

    private func beginSecondPass() {
        fullDirector?.stop()
        fullDirector = nil
        audioGeneration += 1
        audioPlayer.stop()

        let generation = introGeneration
        UIView.animate(
            withDuration: DialogueContentPlaybackTiming.twoPassFadeOut,
            delay: 0,
            options: [.curveEaseInOut]
        ) {
            self.bubbleRows.forEach { $0.alpha = 0 }
        } completion: { _ in
            guard self.introGeneration == generation else { return }
            self.bubbleRows.forEach { $0.removeFromSuperview() }
            self.bubbleRows = []
            self.runInterstitial(
                text: DialogueContentPlaybackTiming.twoPassBeatText,
                generation: generation
            ) { [weak self] in
                guard let self, self.introGeneration == generation else { return }
                self.conversationPass = .second
                self.showsEnglishSubtitles = true
                self.conversationPlaybackRate = ExperimentSettings.dialogueContentSecondPassRate.value
                self.startDirector(skipHolds: true)
            }
        }
    }

    private func runInterstitial(text: String, generation: Int, then continuePlayback: @escaping () -> Void) {
        hookLabel.text = text
        hookLabel.textColor = .label
        beatCaptionLabel.text = ExperimentSettings.dialogueContentSecondPassRate.beatCaption
        beatCaptionLabel.isHidden = false
        hookStack.isHidden = false
        hookStack.alpha = 0
        hookStack.transform = CGAffineTransform(translationX: 0, y: 18)
        bringStageOverlayToFront()
        DispatchQueue.main.asyncAfter(deadline: .now() + DialogueContentPlaybackTiming.twoPassBeatPreEnterPause) {
            guard self.introGeneration == generation else { return }
            UIView.animate(
                withDuration: DialogueContentPlaybackTiming.hookEnterDuration,
                delay: 0,
                usingSpringWithDamping: 0.88,
                initialSpringVelocity: 0.4
            ) {
                self.hookStack.alpha = 1
                self.hookStack.transform = .identity
            } completion: { _ in
                guard self.introGeneration == generation else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + DialogueContentPlaybackTiming.twoPassBeatHold) {
                    guard self.introGeneration == generation else { return }
                    UIView.animate(
                        withDuration: DialogueContentPlaybackTiming.hookFadeToGray,
                        delay: 0,
                        options: [.curveEaseInOut]
                    ) {
                        self.hookStack.alpha = 0
                        self.hookLabel.textColor = .secondaryLabel
                    } completion: { _ in
                        guard self.introGeneration == generation else { return }
                        self.hookStack.isHidden = true
                        self.beatCaptionLabel.isHidden = true
                        self.hookLabel.textColor = .label
                        self.hookLabel.text = self.session.displayHookText
                        continuePlayback()
                    }
                }
            }
        }
    }

    private func fadeStageToGray(completion: @escaping () -> Void) {
        let generation = introGeneration
        UIView.animate(
            withDuration: DialogueContentPlaybackTiming.outroFadeToGray,
            delay: 0,
            options: [.curveEaseInOut]
        ) {
            self.bubbleRows.forEach { $0.alpha = 0 }
            self.optionsStack.alpha = 0
            self.hookStack.alpha = 0
        } completion: { _ in
            guard self.introGeneration == generation else { return }
            self.bubbleRows.forEach { $0.removeFromSuperview() }
            self.bubbleRows = []
            self.optionsStack.isHidden = true
            self.hookStack.isHidden = true
            self.beatCaptionLabel.isHidden = true
            completion()
        }
    }

    // MARK: - Bubbles

    private func presentLine(
        _ line: DialogueContentSpokenLine,
        parkingPrevious: Bool,
        completion: @escaping () -> Void
    ) {
        if line.isStageLine {
            presentCaption(line, completion: completion)
        } else {
            presentBubble(line, parkingPrevious: parkingPrevious, completion: completion)
        }
    }

    private func presentCaption(
        _ line: DialogueContentSpokenLine,
        completion: @escaping () -> Void
    ) {
        let row = DialogueContentCaptionRow(text: line.japanese)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.alpha = 1
        rollView.addSubview(row)
        bringStageOverlayToFront()

        let maxWidth = maxCaptionTextWidth()
        row.setPreferredTextWidth(maxWidth)
        row.centerYConstraint = row.centerYAnchor.constraint(
            equalTo: rollView.centerYAnchor,
            constant: Self.incomingOffset
        )
        NSLayoutConstraint.activate([
            row.centerYConstraint,
            row.centerXAnchor.constraint(equalTo: rollView.centerXAnchor),
            row.leadingAnchor.constraint(
                greaterThanOrEqualTo: rollView.leadingAnchor,
                constant: Self.horizontalGutter
            ),
            row.trailingAnchor.constraint(
                lessThanOrEqualTo: rollView.trailingAnchor,
                constant: -Self.horizontalGutter
            ),
            row.widthAnchor.constraint(lessThanOrEqualToConstant: max(0, maxWidth)),
        ])
        bubbleRows.append(row)
        rollView.layoutIfNeeded()
        restackBubbles(animated: true, completion: completion)
    }

    private func presentBubble(
        _ line: DialogueContentSpokenLine,
        parkingPrevious _: Bool,
        completion: @escaping () -> Void
    ) {
        let row = DialogueContentBubbleRow(
            line: line,
            font: Self.japaneseFont,
            showsEnglish: showsEnglishSubtitles
        )
        row.translatesAutoresizingMaskIntoConstraints = false
        row.alpha = 1
        rollView.addSubview(row)
        bringStageOverlayToFront()

        let maxWidth = maxBubbleTextWidth()
        row.setPreferredTextWidth(maxWidth)
        row.centerYConstraint = row.centerYAnchor.constraint(
            equalTo: rollView.centerYAnchor,
            constant: Self.incomingOffset
        )

        var constraints: [NSLayoutConstraint] = [
            row.centerYConstraint,
            row.widthAnchor.constraint(lessThanOrEqualToConstant: max(0, maxWidth)),
        ]
        switch line.speakerSide {
        case .leading:
            constraints.append(row.leadingAnchor.constraint(equalTo: rollView.leadingAnchor, constant: Self.horizontalGutter))
            constraints.append(
                row.trailingAnchor.constraint(
                    lessThanOrEqualTo: rollView.trailingAnchor,
                    constant: -(Self.horizontalGutter + Self.conversationInset)
                )
            )
        case .trailing:
            constraints.append(row.trailingAnchor.constraint(equalTo: rollView.trailingAnchor, constant: -Self.horizontalGutter))
            constraints.append(
                row.leadingAnchor.constraint(
                    greaterThanOrEqualTo: rollView.leadingAnchor,
                    constant: Self.horizontalGutter + Self.conversationInset
                )
            )
        }
        NSLayoutConstraint.activate(constraints)
        bubbleRows.append(row)
        rollView.layoutIfNeeded()
        applyTokenKaraoke(at: lastKaraokeTime, spokenIndex: line.spokenIndex)
        restackBubbles(animated: true, completion: completion)
    }

    private func parkActiveIfNeeded(animated: Bool) {
        restackBubbles(animated: animated, completion: nil)
    }

    private func restackBubbles(animated: Bool, completion: (() -> Void)?) {
        rollView.layoutIfNeeded()
        var y: CGFloat = 0
        var previousHeight: CGFloat = 0
        var targets: [ObjectIdentifier: CGFloat] = [:]
        var focusByID: [ObjectIdentifier: CGFloat] = [:]
        var alphaByID: [ObjectIdentifier: CGFloat] = [:]

        for (stepsFromActive, row) in bubbleRows.reversed().enumerated() {
            let height = max(row.bounds.height, 1)
            let focus = max(0, 1 - CGFloat(stepsFromActive) * 0.28)
            if stepsFromActive == 0 {
                y = 0
            } else {
                let newer = bubbleRows[bubbleRows.count - stepsFromActive]
                let newerFocus = focusByID[ObjectIdentifier(newer)] ?? 0
                y -= (previousHeight / 2 + height / 2 + spacingAfter(
                    older: row,
                    newer: newer,
                    olderFocus: focus,
                    newerFocus: newerFocus
                ))
            }
            targets[ObjectIdentifier(row)] = y
            focusByID[ObjectIdentifier(row)] = focus
            // Fully opaque until a row leaves the frame. Semi-transparent
            // "preview" bubbles are what TikTok's encoder blends across time.
            let offscreenFade = y + height / 2 < -self.rollView.bounds.height / 2 + 8
            alphaByID[ObjectIdentifier(row)] = offscreenFade ? 0 : 1
            previousHeight = height
        }

        let updates = {
            for row in self.bubbleRows {
                let id = ObjectIdentifier(row)
                row.centerYConstraint.constant = targets[id] ?? 0
                row.alpha = alphaByID[id] ?? 1
                row.setFocus(focusByID[id] ?? 0)
            }
            self.rollView.layoutIfNeeded()
        }

        if animated {
            UIView.animate(
                withDuration: DialogueContentPlaybackTiming.lineAnimationDuration,
                delay: 0,
                usingSpringWithDamping: 0.86,
                initialSpringVelocity: 0.4,
                animations: updates,
                completion: { _ in
                    self.removeBubblesScrolledOffTop()
                    completion?()
                }
            )
        } else {
            updates()
            removeBubblesScrolledOffTop()
            completion?()
        }
    }

    private func spacingAfter(
        older: DialogueContentStackRow,
        newer: DialogueContentStackRow,
        olderFocus: CGFloat,
        newerFocus: CGFloat
    ) -> CGFloat {
        guard older.isStageCaption || newer.isStageCaption else { return Self.bubbleSpacing }
        let emphasis = max(
            older.isStageCaption ? olderFocus : 0,
            newer.isStageCaption ? newerFocus : 0
        )
        return Self.stageLineRowSpacing + Self.stageLineFocusExtraSpacing * emphasis
    }

    private func removeBubblesScrolledOffTop() {
        let cutoff = -rollView.bounds.height / 2
        bubbleRows.removeAll { row in
            let offTop = row.centerYConstraint.constant + row.bounds.height / 2 <= cutoff
            if offTop {
                row.removeFromSuperview()
            }
            return offTop
        }
    }

    private func installOptions(_ options: [DialogueContentSpokenLine], correctID: String) {
        optionRows.forEach { $0.removeFromSuperview() }
        optionRows = []
        for (index, line) in options.enumerated() {
            let row = DialogueContentOptionRow(
                number: index + 1,
                line: line,
                isCorrect: line.id == correctID
            )
            optionsStack.addArrangedSubview(row)
            optionRows.append(row)
        }
        bringStageOverlayToFront()
    }
}

// MARK: - Stack row

private class DialogueContentStackRow: UIView {
    var centerYConstraint: NSLayoutConstraint!
    var isStageCaption: Bool { false }

    func setFocus(_ amount: CGFloat) {}
    func setPreferredTextWidth(_ width: CGFloat) {}
    func applyStyle(_ style: DialogueContentBubbleStyle) {}
}

private final class DialogueContentCaptionRow: DialogueContentStackRow {
    private let captionLabel = UILabel()

    override var isStageCaption: Bool { true }

    init(text: String) {
        super.init(frame: .zero)
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        captionLabel.numberOfLines = 0
        captionLabel.textAlignment = .center
        captionLabel.textColor = .secondaryLabel
        let base = UIFont.systemFont(ofSize: 17, weight: .regular)
        if let italic = base.fontDescriptor.withSymbolicTraits(.traitItalic) {
            captionLabel.font = UIFont(descriptor: italic, size: 17)
        } else {
            captionLabel.font = base
        }
        captionLabel.text = text
        addSubview(captionLabel)
        NSLayoutConstraint.activate([
            captionLabel.topAnchor.constraint(
                equalTo: topAnchor,
                constant: Self.verticalPadding
            ),
            captionLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            captionLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            captionLabel.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -Self.verticalPadding
            ),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func setFocus(_ amount: CGFloat) {
        let clamped = max(0, min(1, amount))
        let scale = 1 + 0.04 * clamped
        captionLabel.transform = abs(scale - 1) > 0.001
            ? CGAffineTransform(scaleX: scale, y: scale)
            : .identity
        captionLabel.textColor = clamped > 0.85 ? .label : .secondaryLabel
    }

    override func setPreferredTextWidth(_ width: CGFloat) {
        captionLabel.preferredMaxLayoutWidth = max(0, width)
        captionLabel.invalidateIntrinsicContentSize()
        invalidateIntrinsicContentSize()
    }

    private static let verticalPadding: CGFloat = 24
}

// MARK: - Bubble row

private final class DialogueContentBubbleRow: DialogueContentStackRow {
    let line: DialogueContentSpokenLine
    private let font: UIFont
    private let bubble: DialogueJapaneseBubbleView
    private let englishLabel: UILabel?
    // centerYConstraint inherited from DialogueContentStackRow

    init(line: DialogueContentSpokenLine, font: UIFont, showsEnglish: Bool) {
        self.line = line
        self.font = font
        let label = FuriganaTranscriptLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.clipsToBounds = false
        label.numberOfLines = 0
        JapaneseFuriganaBuilder.applyDialogueBubbleDisplay(
            to: label,
            text: line.japanese,
            font: font,
            textColor: .label
        )
        DialogueContentLineWrap.applyOrphanGlue(to: label)
        bubble = DialogueJapaneseBubbleView(label: label)

        let englishText = line.english?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if showsEnglish, !englishText.isEmpty {
            let caption = UILabel()
            caption.font = UIFont.systemFont(ofSize: 15, weight: .regular)
            caption.textColor = .secondaryLabel
            caption.numberOfLines = 0
            caption.textAlignment = line.speakerSide == .trailing ? .right : .left
            caption.text = englishText
            caption.setContentHuggingPriority(.required, for: .vertical)
            caption.setContentCompressionResistancePriority(.required, for: .vertical)
            englishLabel = caption
        } else {
            englishLabel = nil
        }
        super.init(frame: .zero)

        bubble.setUnderglowConfiguration(.forSpeaker(line.speakerSide))

        let speakerLabel = UILabel()
        speakerLabel.font = GrammarJapaneseTypography.scenarioSpeakerFont
        speakerLabel.textColor = .secondaryLabel
        speakerLabel.text = line.speakerPrefix
        speakerLabel.textAlignment = line.speakerSide == .trailing ? .right : .left
        speakerLabel.setContentHuggingPriority(.required, for: .horizontal)
        speakerLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let speakerWrap = Self.insetSpeakerLabel(speakerLabel, side: line.speakerSide)

        let column = UIStackView(arrangedSubviews: [speakerWrap, bubble])
        column.axis = .vertical
        column.spacing = 8
        column.alignment = line.speakerSide == .leading ? .leading : .trailing
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        var constraints: [NSLayoutConstraint] = [
            column.topAnchor.constraint(equalTo: topAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
        ]
        if let englishLabel {
            englishLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(englishLabel)
            constraints += [
                englishLabel.topAnchor.constraint(equalTo: bubble.bottomAnchor, constant: 8),
                englishLabel.leadingAnchor.constraint(equalTo: bubble.label.leadingAnchor),
                englishLabel.trailingAnchor.constraint(equalTo: bubble.label.trailingAnchor),
                englishLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            ]
        } else {
            constraints.append(column.bottomAnchor.constraint(equalTo: bottomAnchor))
        }
        NSLayoutConstraint.activate(constraints)
        applyStyle(ExperimentSettings.dialogueContentBubbleStyle)
        bubble.setEmphasis(0)
    }

    private static func insetSpeakerLabel(_ label: UILabel, side: DialogueSpeakerSide) -> UIView {
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(label)
        let inset: CGFloat = 16
        var constraints: [NSLayoutConstraint] = [
            label.topAnchor.constraint(equalTo: wrapper.topAnchor),
            label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ]
        switch side {
        case .leading:
            constraints += [
                label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: inset),
                label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            ]
        case .trailing:
            constraints += [
                label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -inset),
                label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        return wrapper
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func applyStyle(_ style: DialogueContentBubbleStyle) {
        switch style {
        case .glass:
            bubble.setTailEdge(.none)
            bubble.setSolidFillStaysVisible(false)
            bubble.setBackgroundStyle(.glass)
            applyLabelColor(.label)
        case .messages:
            let isLeading = line.speakerSide == .leading
            bubble.setBackgroundStyle(.solid)
            bubble.setSolidFillStaysVisible(true)
            bubble.setSolidFillColor(isLeading ? .secondarySystemFill : .systemBlue)
            bubble.setTailEdge(isLeading ? .leading : .trailing)
            applyLabelColor(isLeading ? .label : .white)
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func applyLabelColor(_ color: UIColor) {
        labelColor = color
        appliedKaraokeToken = -2
        JapaneseFuriganaBuilder.applyDialogueBubbleDisplay(
            to: bubble.label,
            text: line.japanese,
            font: font,
            textColor: color
        )
        DialogueContentLineWrap.applyOrphanGlue(to: bubble.label)
    }

    override func setPreferredTextWidth(_ width: CGFloat) {
        let textWidth = max(0, width - bubble.layoutHorizontalContentPadding)
        bubble.label.preferredMaxLayoutWidth = textWidth
        bubble.label.setNeedsLayout()
        bubble.invalidateIntrinsicContentSize()
        englishLabel?.preferredMaxLayoutWidth = textWidth
        englishLabel?.invalidateIntrinsicContentSize()
        invalidateIntrinsicContentSize()
    }

    private var labelColor: UIColor = .label
    private var appliedKaraokeToken = -2

    override func setFocus(_ amount: CGFloat) {
        let clamped = max(0, min(1, amount))
        bubble.setEmphasis(clamped)
        let scale = 1 + 0.04 * clamped
        bubble.transform = CGAffineTransform(scaleX: scale, y: scale)
    }

    func invalidateKaraoke() {
        appliedKaraokeToken = -2
    }

    func refreshUnderglow() {
        bubble.setUnderglowConfiguration(.forSpeaker(line.speakerSide))
        invalidateKaraoke()
    }

    private var tokenHighlightColor: UIColor {
        if ExperimentSettings.dialogueContentBubbleStyle == .messages {
            return FuriganaTranscriptLabel.tokenSyncHighlightColorOnBlueBubble
        }
        return bubble.tokenHighlightColor
    }

    func applyKaraoke(tokenSync: DialogueTokenSync?, time: TimeInterval, isActive: Bool) {
        let tokenIndex = isActive ? tokenSync?.tokenIndex(lineIndex: line.spokenIndex, at: time) : nil
        let fullHeightBit = ExperimentSettings.dialogueTokenSyncHighlightStyle == .full ? 10_000 : 0
        let key = (tokenIndex ?? -1) + fullHeightBit
        guard key != appliedKaraokeToken else { return }
        appliedKaraokeToken = key
        if let tokenIndex,
           let range = tokenSync?.utf16Range(
            lineIndex: line.spokenIndex,
            tokenIndex: tokenIndex,
            inDisplay: bubble.label.attributedText?.string ?? ""
           ) {
            bubble.label.setTokenHighlightPreservingLayout(
                foregroundColor: labelColor,
                highlightedRange: range,
                fullHeight: ExperimentSettings.dialogueTokenSyncHighlightStyle == .full,
                highlightColor: tokenHighlightColor
            )
        } else {
            bubble.label.setForegroundColorPreservingLayout(labelColor)
        }
    }

    func setActive(_ active: Bool) {
        setFocus(active ? 1 : 0)
    }
}

// MARK: - Option row

private final class DialogueContentOptionRow: UIView {
    let line: DialogueContentSpokenLine
    let isCorrect: Bool

    init(number: Int, line: DialogueContentSpokenLine, isCorrect: Bool) {
        self.line = line
        self.isCorrect = isCorrect
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = ExperimentPalette.cardSurface
        layer.cornerRadius = ExperimentCardStroke.choiceCornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = ExperimentCardStroke.normalWidth
        layer.borderColor = ExperimentPalette.cardBorder.cgColor
        isUserInteractionEnabled = false

        let numberLabel = UILabel()
        numberLabel.text = "\(number)"
        numberLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        numberLabel.textColor = .secondaryLabel
        numberLabel.setContentHuggingPriority(.required, for: .horizontal)
        numberLabel.translatesAutoresizingMaskIntoConstraints = false

        let japaneseLabel = FuriganaTranscriptLabel()
        japaneseLabel.translatesAutoresizingMaskIntoConstraints = false
        japaneseLabel.numberOfLines = 0
        let optionFont = UIFont.systemFont(ofSize: 18, weight: .medium)
        JapaneseFuriganaBuilder.applyDialogueBubbleDisplay(
            to: japaneseLabel,
            text: line.japanese,
            font: optionFont,
            textColor: .label
        )
        DialogueContentLineWrap.applyOrphanGlue(to: japaneseLabel)

        addSubview(numberLabel)
        addSubview(japaneseLabel)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            numberLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            numberLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            numberLabel.widthAnchor.constraint(equalToConstant: 22),

            japaneseLabel.leadingAnchor.constraint(equalTo: numberLabel.trailingAnchor, constant: 8),
            japaneseLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            japaneseLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            japaneseLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applySuccess() {
        backgroundColor = ExperimentPalette.successFill
        layer.borderWidth = ExperimentCardStroke.emphasisWidth
        layer.borderColor = ExperimentPalette.successBorder.cgColor
    }

    func applyDimmed() {
        alpha = 0.35
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection),
           abs(alpha - 1) < 0.01,
           layer.borderWidth == ExperimentCardStroke.normalWidth {
            layer.borderColor = ExperimentPalette.cardBorder.cgColor
        }
    }
}
