//
//  DialogueRolePlayViewController.swift
//  shizen
//
//  Pick a speaker, hear the other role, then say your lines in-transcript.
//  Isolated from DialogueExperimentViewController so role-play tweaks cannot
//  leak into the listen-along flow.
//

import AVFoundation
import Speech
import TTSCore
import UIKit

final class DialogueRolePlayViewController: DialogueExperimentViewController {

    private enum Phase: Equatable {
        case inactive
        case playingOther(lineIndex: Int)
        case awaitingLearner(lineIndex: Int)
        case finished
    }

    private var phase: Phase = .inactive
    private var learnerSpeaker: String?
    private var completedLearnerLineIndices = Set<Int>()
    private var matchedNormalizedCount = 0
    private var segmentEndTime: TimeInterval?
    private var hasStarted = false
    private var sttGeneration = 0
    private let onDeviceSpeechToText = JapaneseSpeechToText()
    private let whisperSpeechToText = RealtimeWhisperSpeechToText()
    private var isPreviewingLearnerAudio = false
    private var previewLineIndex: Int?
    private var highestRevealedIndex = -1
    private var lineRevealGeneration = 0
    private var advanceGeneration = 0
    private var completionFeedbackGeneration = 0
    private var pendingCheckmarkBounceIndex: Int?
    private var didRecordCompletion = false
    private var isPresentingSheet = false
    private var hasPresentedFirstLearnerLine = false
    private var pendingCloudRevealIndex: Int?
    private let turnHaptic = UIImpactFeedbackGenerator(style: .light)
    private let successHaptic = UINotificationFeedbackGenerator()

    private var speechRecognizerBackend: RolePlaySpeechRecognizerBackend {
        ExperimentSettings.rolePlaySpeechRecognizerBackend
    }

    private var isSpeechRecognitionRunning: Bool {
        onDeviceSpeechToText.isRunning || whisperSpeechToText.isListening
    }

    private weak var rolePlaySheet: DialogueRolePlaySheetViewController?

    private let compareCard = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let compareStack = UIStackView()
    private let compareOnDeviceLabel = UILabel()
    private let compareWhisperLabel = UILabel()
    private var compareOnDeviceText = ""
    private var compareWhisperText = ""
    private var compareTargetJapanese = ""
    private var compareTurnSnapshots: [RolePlayCompareTurnSnapshot] = []
    private let debugStack = UIStackView()
    private let usageLabel = UILabel()
    private var whisperListenHalted = false
    private var currentWhisperTurnCap: TimeInterval?
    private var whisperIdleWatchdog: DispatchWorkItem?
    private let speakingMeter = SpeakingMeterPillView()

    private static let linePlayGlyphColor = UIColor.systemYellow

    private static let successColor: UIColor = .systemBlue
    /// Let the standard follow-along animation finish before flipping the audio
    /// session to `.record`, which otherwise hitches the scroll.
    private static let listeningStartDelay: TimeInterval = 0.42
    private static let listeningRestartDelay: TimeInterval = 0.18
    /// Keep in lockstep with the parent's emphasis duration so fade and focus
    /// read as one motion.
    private static let lineRevealDuration: TimeInterval = 0.35
    /// Pause after a stage direction so the scene can land before the next line.
    private static let stageLineHold: TimeInterval = 0.75
    private static let completionFeedbackDelay: TimeInterval = 1.55

    override init(
        pointTitle: String,
        example: GrammarExample,
        presentationContext: DialoguePresentationContext = .standalone,
        scenarioID: String? = nil,
        grammarPointIDs: [String] = []
    ) {
        super.init(
            pointTitle: pointTitle,
            example: example,
            presentationContext: presentationContext,
            scenarioID: scenarioID,
            grammarPointIDs: grammarPointIDs
        )
        dialogueRebuildDisplayLines()
        title = "Role Play"
        transcriptDisplayMode = .full
        recordsCompletionOnPlaybackFinish = false
    }

    override func dialogueIncludesStageLineVisibility(_ visibility: DialogueStageLineVisibility) -> Bool {
        true
    }

    override func dialogueShowsScenarioChrome() -> Bool { false }

    override func dialogueShowsMetadataHeader() -> Bool { false }

    override func dialogueHeaderBottomSpacing() -> CGFloat { 12 }

    /// Mic / Hear sit above the bubble (bottom-aligned to the speaker label, or
    /// flush to the bubble top when the label is omitted). Same-speaker rows
    /// especially need clearance so chrome does not collide with the previous bubble.
    override func dialogueSpacingAfterLineRow(
        line: DialogueLineDisplay,
        nextLine: DialogueLineDisplay
    ) -> CGFloat {
        if line.isStageLine || nextLine.isStageLine {
            return super.dialogueSpacingAfterLineRow(line: line, nextLine: nextLine)
        }
        let chromeClearance = DialogueBubbleSwipeRevealContainer.accessoryChromeSize + 10
        if nextLine.speaker == line.speaker {
            return chromeClearance
        }
        return max(48, chromeClearance)
    }

    override func dialogueContentStackTopConstant() -> CGFloat {
        view.safeAreaInsets.top + 12
    }

    override func dialogueShouldSyncActiveLineFromPlayback() -> Bool {
        // Role Play owns the highlighted line from `phase`. Playback-time sync
        // can snap `setActiveLine` (sometimes unanimated) while a reveal is
        // still easing, which is the jitter on speaker A.
        false
    }

    override func dialogueShouldHoldForStageLinesDuringPlayback() -> Bool { false }

    override func dialogueShowsElapsedTime() -> Bool { false }

    override func dialogueHidesEnglishUntilSwipe() -> Bool { false }

    override func dialogueHidesSummaryUntilHeard() -> Bool { false }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        concealUnrevealedLines()
        configureDebugChrome()
        configureSpeakingMeter()
        configureOptionsBarButton()
        turnHaptic.prepare()
        successHaptic.prepare()
        whisperSpeechToText.onSessionReady = { [weak self] in
            self?.handleCloudSessionReady()
        }
        whisperSpeechToText.onSessionFailed = { [weak self] in
            guard let self, let index = self.pendingCloudRevealIndex else { return }
            self.presentFirstLearnerLineNow(index)
        }
        whisperSpeechToText.onSpeechActivity = { [weak self] in
            self?.noteWhisperListenActivity()
        }
        whisperSpeechToText.onAppendedBudgetExhausted = { [weak self] in
            self?.haltWhisperListening()
        }
        whisperSpeechToText.onAppendedAudio = { [weak self] _ in
            self?.updateUsageLabel()
        }
        if navigationController?.viewControllers.first === self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                systemItem: .close,
                primaryAction: UIAction { [weak self] _ in
                    self?.dismiss(animated: true)
                }
            )
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        dialogueWireBubbleSwipeContentPopDeferral()
        if !hasStarted {
            hasStarted = true
            presentRolePickerIfNeeded()
            return
        }
        if case .awaitingLearner(let index) = phase, !isPreviewingLearnerAudio, !isPresentingSheet {
            startListening(for: index)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        teardownSpeechRecognition()
        super.viewWillDisappear(animated)
    }

    deinit {
        onDeviceSpeechToText.stop()
        whisperSpeechToText.stop()
    }

    override func reloadScenario(
        pointTitle: String,
        example: GrammarExample,
        scenarioID: String? = nil,
        grammarPointIDs: [String]? = nil
    ) {
        teardownSpeechRecognition()
        phase = .inactive
        hasStarted = false
        isPreviewingLearnerAudio = false
        learnerSpeaker = nil
        didRecordCompletion = false
        clearHeldReplayAffordance(at: previewLineIndex, animated: false)
        previewLineIndex = nil
        completedLearnerLineIndices.removeAll()
        matchedNormalizedCount = 0
        compareTurnSnapshots.removeAll()
        compareOnDeviceText = ""
        compareWhisperText = ""
        whisperListenHalted = false
        currentWhisperTurnCap = nil
        cancelWhisperIdleWatchdog()
        super.reloadScenario(
            pointTitle: pointTitle,
            example: example,
            scenarioID: scenarioID,
            grammarPointIDs: grammarPointIDs
        )
        concealUnrevealedLines()
        restoreDefaultLineAppearance()
        let shouldOfferPicker = isViewLoaded && view.window != nil
        dismissRolePlaySheet(animated: false) { [weak self] in
            guard let self, shouldOfferPicker, self.view.window != nil else { return }
            self.hasStarted = true
            self.presentRolePickerIfNeeded()
        }
    }

    override func dialogueShowsOverflowButton() -> Bool { false }

    override func makeOverflowMenu() -> UIMenu {
        let switchRole = UIAction(
            title: "Switch role",
            image: UIImage(systemName: "person.2")
        ) { [weak self] _ in
            self?.presentRolePicker(animated: true)
        }
        return UIMenu(children: [
            makePlaybackSpeedMenu(),
            makeSpeechRecognizerMenu(),
            makeTokenSyncMenuAction(),
            makeTokenSyncHighlightStyleMenu(),
            switchRole,
        ])
    }

    override func dialogueRefreshOverflowMenu() {
        super.dialogueRefreshOverflowMenu()
        navigationItem.rightBarButtonItem?.menu = makeOverflowMenu()
    }

    private func configureOptionsBarButton() {
        let button = UIBarButtonItem(
            title: nil,
            image: UIImage(systemName: "ellipsis.circle"),
            primaryAction: nil,
            menu: makeOverflowMenu()
        )
        button.accessibilityLabel = "More"
        navigationItem.rightBarButtonItem = button
    }

    private func makeSpeechRecognizerMenu() -> UIMenu {
        let actions = RolePlaySpeechRecognizerBackend.allCases.map { backend in
            UIAction(
                title: backend.title,
                image: UIImage(systemName: backend.symbolName),
                state: backend == speechRecognizerBackend ? .on : .off
            ) { [weak self] _ in
                self?.selectSpeechRecognizerBackend(backend)
            }
        }
        return UIMenu(
            title: "Speech Recognition",
            image: UIImage(systemName: "waveform"),
            options: .singleSelection,
            children: actions
        )
    }

    private func selectSpeechRecognizerBackend(_ backend: RolePlaySpeechRecognizerBackend) {
        guard backend != speechRecognizerBackend else { return }
        ExperimentSettings.rolePlaySpeechRecognizerBackend = backend
        dialogueRefreshOverflowMenu()
        compareOnDeviceText = ""
        compareWhisperText = ""
        updateCompareCard()

        teardownSpeechRecognition()
        guard case .awaitingLearner(let index) = phase, !isPreviewingLearnerAudio else { return }
        startListening(for: index)
    }

    override func dialogueShouldInstallBubbleSwipe(isRevealMode: Bool, isListeningLineMeterRow: Bool) -> Bool {
        !isListeningLineMeterRow
    }

    override func dialogueDidInstallBubbleSwipe(
        _ container: DialogueBubbleSwipeRevealContainer,
        at index: Int,
        isRevealMode: Bool
    ) {
        // Swipe always focuses. Hear is trailing chrome on the active row;
        // Skip is the bottom checkmark.
        container.expandSymbolName = "magnifyingglass"
        container.expandResetsAfterCommit = false
        container.expandAccessibilityHint = "Swipe right to focus this sentence"
        container.onCommit = { [weak self] in
            self?.presentSentenceFocus(forLineAt: index)
        }
        container.allowsProgressiveReveal = false
        if dialogueDisplayLines.indices.contains(index) {
            container.chromeEdge = dialogueDisplayLines[index].speakerSide == .leading
                ? .trailing
                : .leading
        }
        container.leadingAccessoryActiveColor = Self.successColor
        container.trailingAccessoryActiveColor = Self.linePlayGlyphColor
        container.onTrailingAccessoryTap = { [weak self] in
            self?.replayLine(at: index)
        }
    }

    override func presentSentenceFocus(forLineAt index: Int) {
        isPreviewingLearnerAudio = false
        pauseLearnerListening()
        if dialoguePlaybackPhase == .playing {
            dialoguePausePlayback()
        }
        super.presentSentenceFocus(forLineAt: index)
    }

    override func togglePlayPause() {
        switch phase {
        case .awaitingLearner:
            completeLearnerTurn()
        case .playingOther:
            switch dialoguePlaybackPhase {
            case .playing:
                dialoguePausePlayback()
            case .paused:
                dialogueResumePlayback()
            default:
                break
            }
        case .finished:
            break
        case .inactive:
            presentRolePickerIfNeeded()
        }
    }

    override func restartTapped() {
        beginRolePlay()
    }

    override func handlePlaybackFinished() {
        if isPreviewingLearnerAudio {
            finishLearnerPreview(resumeListening: true)
            return
        }
        if case .playingOther(let index) = phase {
            if let end = segmentEndTime {
                let time = dialoguePlayerCurrentTime ?? 0
                if time + 0.05 < end {
                    return
                }
            }
            segmentEndTime = nil
            advance(to: index + 1)
            return
        }
        super.handlePlaybackFinished()
    }

    override func dialogueDidTickPlayback(at time: TimeInterval) {
        if isPreviewingLearnerAudio {
            guard let end = segmentEndTime else { return }
            if time + 0.05 >= end {
                finishLearnerPreview(resumeListening: true)
            }
            return
        }
        guard case .playingOther(let index) = phase, let end = segmentEndTime else { return }
        if time + 0.05 >= end {
            segmentEndTime = nil
            dialoguePausePlayback()
            advance(to: index + 1)
        }
    }

    override func dialogueShouldAllowLineTap(at index: Int) -> Bool {
        false
    }

    override func dialogueShouldApplyEmphasisTextColor(at index: Int) -> Bool {
        // Learner lines stay secondary (then match-blue) — the parent's
        // secondary → label emphasis would flash them primary until speech starts.
        !isLearnerLine(at: index)
    }

    override func dialogueReservesAccessoryChromeHeight() -> Bool { true }

    override func dialoguePlayPauseSymbolName(isPlaying: Bool) -> String {
        if isAwaitingLearner {
            return "checkmark"
        }
        return super.dialoguePlayPauseSymbolName(isPlaying: isPlaying)
    }

    override func dialoguePlayPauseAccessibilityLabel(isPlaying: Bool) -> String {
        if isAwaitingLearner {
            return "Skip line"
        }
        return super.dialoguePlayPauseAccessibilityLabel(isPlaying: isPlaying)
    }

    /// Skip (checkmark) stays available while awaiting speech even if this
    /// dialogue has no clip yet.
    override func dialogueShowsPlayButton() -> Bool {
        if isAwaitingLearner { return true }
        return super.dialogueShowsPlayButton()
    }

    // MARK: - Flow

    private var isAwaitingLearner: Bool {
        if case .awaitingLearner = phase { return true }
        return false
    }

    private func beginRolePlay() {
        guard learnerSpeaker != nil, !dialogueDisplayLines.isEmpty else {
            phase = .finished
            return
        }
        completedLearnerLineIndices.removeAll()
        matchedNormalizedCount = 0
        compareTurnSnapshots.removeAll()
        compareOnDeviceText = ""
        compareWhisperText = ""
        whisperListenHalted = false
        currentWhisperTurnCap = nil
        cancelWhisperIdleWatchdog()
        segmentEndTime = nil
        completionFeedbackGeneration += 1
        didRecordCompletion = false
        isPreviewingLearnerAudio = false
        hasPresentedFirstLearnerLine = false
        pendingCloudRevealIndex = nil
        dismissRolePlaySheet(animated: true)
        clearHeldReplayAffordance(at: previewLineIndex, animated: false)
        previewLineIndex = nil
        pauseLearnerListening()
        dialogueStopPlayback(resetPosition: true)
        restoreDefaultLineAppearance()
        concealUnrevealedLines()
        dialogueRefreshOverflowMenu()
        dialogueSetTransportBarHidden(false)
        preconnectCloudSTT(muted: true)
        advance(to: 0)
    }

    private func uniqueSpeakers() -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()
        for line in dialogueDisplayLines where !line.isStageLine && !seen.contains(line.speaker) {
            seen.insert(line.speaker)
            ordered.append(line.speaker)
        }
        return ordered
    }

    private func isLearnerLine(at index: Int) -> Bool {
        guard dialogueDisplayLines.indices.contains(index),
              !dialogueDisplayLines[index].isStageLine,
              let learner = learnerSpeaker else { return false }
        return dialogueDisplayLines[index].speaker == learner
    }

    private func advance(to index: Int) {
        advanceGeneration += 1
        let generation = advanceGeneration
        segmentEndTime = nil
        isPreviewingLearnerAudio = false
        clearHeldReplayAffordance(at: previewLineIndex, animated: true)
        previewLineIndex = nil
        pendingCloudRevealIndex = nil
        pauseLearnerListening()
        matchedNormalizedCount = 0

        guard dialogueDisplayLines.indices.contains(index) else {
            presentCompletion()
            return
        }

        if dialogueDisplayLines[index].isStageLine {
            revealLine(at: index, animated: true)
            dialogueSetActiveLine(index, animated: true)
            scrollRevealedLineIntoView(index)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.stageLineHold) { [weak self] in
                guard let self, self.advanceGeneration == generation else { return }
                self.advance(to: index + 1)
            }
            return
        }

        if isLearnerLine(at: index) {
            presentLearnerLine(index)
        } else {
            revealLine(at: index, animated: true)
            presentOtherLine(index)
        }
    }

    private func presentLearnerLine(_ index: Int) {
        if dialoguePlaybackPhase == .playing {
            dialoguePausePlayback()
        }
        phase = .awaitingLearner(lineIndex: index)

        let holdForCloud =
            speechRecognizerBackend.usesWhisper
            && !hasPresentedFirstLearnerLine
            && !whisperSpeechToText.isSessionReady
        if holdForCloud {
            pendingCloudRevealIndex = index
            preconnectCloudSTT(muted: true)
            dialogueRefreshOverflowMenu()
            dialogueUpdateTransportControls()
            updateLeadingAccessories()
            return
        }

        presentFirstLearnerLineNow(index)
    }

    private func presentFirstLearnerLineNow(_ index: Int) {
        pendingCloudRevealIndex = nil
        hasPresentedFirstLearnerLine = true
        turnHaptic.impactOccurred(intensity: 0.7)
        turnHaptic.prepare()
        revealLine(at: index, animated: true)
        dialogueSetActiveLine(index, animated: true)
        refreshLineAppearance()
        dialogueRefreshOverflowMenu()
        dialogueUpdateTransportControls()
        scrollRevealedLineIntoView(index)
        let delay = whisperSpeechToText.isSessionReady ? 0.08 : Self.listeningStartDelay
        let generation = sttGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.sttGeneration == generation else { return }
            guard case .awaitingLearner(let current) = self.phase, current == index else { return }
            self.startListening(for: index)
        }
    }

    private func preconnectCloudSTT(muted: Bool) {
        guard speechRecognizerBackend.usesWhisper else { return }
        do {
            try whisperSpeechToText.ensureConnected(muted: muted)
        } catch {
            if let index = pendingCloudRevealIndex {
                presentFirstLearnerLineNow(index)
            }
        }
    }

    private func handleCloudSessionReady() {
        guard let index = pendingCloudRevealIndex else { return }
        guard case .awaitingLearner(let current) = phase, current == index else { return }
        presentFirstLearnerLineNow(index)
    }

    /// Reveal, focus, and follow-along first — the same sequence as a learner
    /// line. Audio starts on the next turn so session activation and `play()`
    /// cannot hitch the fade.
    private func presentOtherLine(_ index: Int) {
        phase = .playingOther(lineIndex: index)
        prewarmPlaybackSessionIfNeeded(forLineAt: index)
        dialogueSetActiveLine(index, animated: true)
        refreshLineAppearance()
        dialogueRefreshOverflowMenu()
        dialogueUpdateTransportControls()
        scrollRevealedLineIntoView(index)
        DispatchQueue.main.async { [weak self] in
            guard let self, case .playingOther(let current) = self.phase, current == index else { return }
            self.playSegment(at: index)
        }
    }

    private func prewarmPlaybackSessionIfNeeded(forLineAt index: Int) {
        guard dialogueDisplayLines.indices.contains(index), !isLearnerLine(at: index) else { return }
        prewarmPlaybackSession()
    }

    private func prewarmPlaybackSession() {
        PlaybackAudioSession.activateForPlayback { _ in }
    }

    /// Seeks and starts the clip for the current non-learner line. Does not
    /// touch highlight or scroll — callers present the line first.
    private func playSegment(at index: Int, attempt: Int = 0) {
        guard case .playingOther(let current) = phase, current == index else { return }
        guard !dialogueDisplayLines[index].isStageLine,
              let spokenIndex = spokenIndex(forDisplayIndex: index),
              dialogueAlignedLines.indices.contains(spokenIndex),
              let player = dialogueMakePlayer() else {
            guard attempt < 12 else {
                advance(to: index + 1)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, case .playingOther(let current) = self.phase, current == index else { return }
                self.playSegment(at: index, attempt: attempt + 1)
            }
            return
        }
        let range = dialogueAlignedLines[spokenIndex].timeRange
        segmentEndTime = range.upperBound
        dialogueSeekTargetLineIndex = spokenIndex
        player.currentTime = range.lowerBound
        dialogueSetPlaybackPhase(.playing)
        dialogueUpdateTransportControls()
        dialogueUpdateElapsedLabel(currentTime: range.lowerBound)
        dialogueStartPlayerAfterSessionActivation(player)
    }

    private func completeLearnerTurn() {
        guard case .awaitingLearner(let index) = phase else { return }
        guard !completedLearnerLineIndices.contains(index) else { return }
        isPreviewingLearnerAudio = false
        let keepListeningForCompare = speechRecognizerBackend == .compare
        if !keepListeningForCompare {
            pauseLearnerListening()
        }
        if dialoguePlaybackPhase == .playing {
            dialoguePausePlayback()
        }
        clearHeldReplayAffordance(at: previewLineIndex, animated: true)
        previewLineIndex = nil
        completedLearnerLineIndices.insert(index)
        matchedNormalizedCount = 0
        pendingCheckmarkBounceIndex = index
        successHaptic.notificationOccurred(.success)
        successHaptic.prepare()
        refreshLineAppearance()
        pendingCheckmarkBounceIndex = nil
        prewarmPlaybackSessionIfNeeded(forLineAt: index + 1)

        let generation = completionFeedbackGeneration + 1
        completionFeedbackGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.completionFeedbackDelay) { [weak self] in
            guard let self, self.completionFeedbackGeneration == generation else { return }
            if keepListeningForCompare {
                self.recordCompareSnapshot(for: index)
                self.pauseLearnerListening()
            }
            self.advance(to: index + 1)
        }
    }

    private func replayLine(at index: Int) {
        guard dialogueDisplayLines.indices.contains(index),
              index <= highestRevealedIndex else { return }

        if isPreviewingLearnerAudio {
            segmentEndTime = nil
            if dialoguePlaybackPhase == .playing {
                dialoguePausePlayback()
            }
            isPreviewingLearnerAudio = false
        }
        if previewLineIndex != index {
            clearHeldReplayAffordance(at: previewLineIndex, animated: true)
        }
        previewLineIndex = index

        if case .playingOther(let current) = phase, current == index {
            playSegment(at: index)
            return
        }

        pauseLearnerListening()
        if dialoguePlaybackPhase == .playing {
            dialoguePausePlayback()
        }
        isPreviewingLearnerAudio = true
        prewarmPlaybackSession()
        if case .awaitingLearner(let current) = phase, current == index {
            matchedNormalizedCount = 0
        }
        updateLeadingAccessories()
        playLearnerPreview(at: index)
        if case .awaitingLearner(let current) = phase, current == index {
            refreshLineAppearance()
        }
        scrollRevealedLineIntoView(index)
    }

    private func clearHeldReplayAffordance(at index: Int?, animated: Bool) {
        guard let index, let container = bubbleSwipeContainer(atDisplayIndex: index) else { return }
        container.reset(animated: animated)
    }

    private func bubbleSwipeContainer(atDisplayIndex index: Int) -> DialogueBubbleSwipeRevealContainer? {
        guard dialogueDisplayLines.indices.contains(index),
              !dialogueDisplayLines[index].isStageLine else { return nil }
        let containerIndex = dialogueDisplayLines[..<index].filter { !$0.isStageLine }.count
        guard dialogueBubbleSwipeContainers.indices.contains(containerIndex) else { return nil }
        return dialogueBubbleSwipeContainers[containerIndex]
    }

    private func forEachBubbleSwipeContainer(
        _ body: (_ displayIndex: Int, _ container: DialogueBubbleSwipeRevealContainer) -> Void
    ) {
        var containerIndex = 0
        for displayIndex in dialogueDisplayLines.indices {
            guard !dialogueDisplayLines[displayIndex].isStageLine else { continue }
            guard dialogueBubbleSwipeContainers.indices.contains(containerIndex) else { return }
            body(displayIndex, dialogueBubbleSwipeContainers[containerIndex])
            containerIndex += 1
        }
    }

    // MARK: - Appearance

    private func refreshLineAppearance() {
        let awaitingIndex: Int? = {
            if case .awaitingLearner(let index) = phase { return index }
            return nil
        }()

        for index in dialogueJapaneseLabels.indices {
            guard dialogueDisplayLines.indices.contains(index),
                  !dialogueDisplayLines[index].isStageLine else { continue }
            let isLearner = isLearnerLine(at: index)
            if isLearner, completedLearnerLineIndices.contains(index) {
                applyLineAppearance(at: index, color: Self.successColor)
            } else if isLearner, awaitingIndex == index {
                applyLineAppearance(
                    at: index,
                    matchedNormalizedCount: matchedNormalizedCount,
                    matchedColor: Self.successColor,
                    remainderColor: Self.dialogueInactiveJapaneseColor
                )
            } else if isLearner {
                applyLineAppearance(at: index, color: Self.dialogueInactiveJapaneseColor)
            } else {
                applyLineAppearance(at: index, color: dialogueJapaneseColor(forLineAt: index))
            }
        }

        updateLeadingAccessories()
        updateSwipeAffordance()
    }

    private func restoreDefaultLineAppearance() {
        for index in dialogueJapaneseLabels.indices {
            guard dialogueDisplayLines.indices.contains(index),
                  !dialogueDisplayLines[index].isStageLine else { continue }
            applyLineAppearance(at: index, color: Self.dialogueInactiveJapaneseColor)
        }
        updateLeadingAccessories()
        updateSwipeAffordance()
    }

    private func concealUnrevealedLines() {
        lineRevealGeneration += 1
        highestRevealedIndex = -1
        for row in dialogueLineRows {
            row.layer.removeAllAnimations()
            row.alpha = 0
            row.isHidden = true
            row.isUserInteractionEnabled = false
        }
    }

    private func revealLine(at index: Int, animated: Bool) {
        guard dialogueLineRows.indices.contains(index) else { return }
        lineRevealGeneration += 1
        let generation = lineRevealGeneration

        for earlier in 0..<index {
            guard dialogueLineRows.indices.contains(earlier) else { continue }
            let row = dialogueLineRows[earlier]
            row.layer.removeAllAnimations()
            row.isHidden = false
            row.alpha = 1
            row.isUserInteractionEnabled = true
        }

        let row = dialogueLineRows[index]
        let alreadyRevealed = highestRevealedIndex >= index && !row.isHidden && row.alpha > 0.99
        highestRevealedIndex = max(highestRevealedIndex, index)
        guard !alreadyRevealed else { return }

        row.layer.removeAllAnimations()
        row.alpha = 0
        row.isHidden = false
        row.isUserInteractionEnabled = true
        view.setNeedsLayout()
        view.layoutIfNeeded()

        guard animated, view.window != nil else {
            row.alpha = 1
            return
        }

        UIView.animate(
            withDuration: Self.lineRevealDuration,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]
        ) {
            row.alpha = 1
        } completion: { _ in
            guard generation == self.lineRevealGeneration else { return }
            row.alpha = 1
        }
    }

    private func scrollRevealedLineIntoView(_ index: Int) {
        scrollLineIntoView(at: index, animated: true)
        DispatchQueue.main.async { [weak self] in
            self?.scrollLineIntoView(at: index, animated: true)
        }
    }

    private func applyLineAppearance(at index: Int, color: UIColor) {
        guard dialogueJapaneseLabels.indices.contains(index),
              dialogueDisplayLines.indices.contains(index) else { return }
        let font = Self.dialogueJapaneseFont
        JapaneseFuriganaBuilder.applyDialogueBubbleDisplay(
            to: dialogueJapaneseLabels[index],
            text: dialogueDisplayLines[index].japanese,
            font: font,
            textColor: color
        )
    }

    private func applyLineAppearance(
        at index: Int,
        matchedNormalizedCount: Int,
        matchedColor: UIColor,
        remainderColor: UIColor
    ) {
        guard dialogueJapaneseLabels.indices.contains(index),
              dialogueDisplayLines.indices.contains(index) else { return }
        let japanese = dialogueDisplayLines[index].japanese
        let font = Self.dialogueJapaneseFont
        let prefixUTF16 = RolePlaySpeechMatching.displayUTF16PrefixLength(
            in: japanese,
            matchedNormalizedCount: matchedNormalizedCount
        )
        JapaneseFuriganaBuilder.applyDialogueBubbleDisplay(
            to: dialogueJapaneseLabels[index],
            text: japanese,
            font: font,
            prefixUTF16Length: prefixUTF16,
            prefixColor: matchedColor,
            remainderColor: remainderColor
        )
    }

    private func updateLeadingAccessories() {
        let awaitingIndex: Int? = {
            if case .awaitingLearner(let index) = phase { return index }
            return nil
        }()
        let isListening = isSpeechRecognitionRunning && !isPreviewingLearnerAudio

        forEachBubbleSwipeContainer { index, container in
            let bounce = pendingCheckmarkBounceIndex == index
            if awaitingIndex == index {
                if completedLearnerLineIndices.contains(index) {
                    container.setLeadingAccessory(.checkmark, animated: true, bounce: bounce)
                } else {
                    container.setLeadingAccessory(
                        isPreviewingLearnerAudio || whisperListenHalted
                            ? .microphoneOff
                            : .microphone,
                        animated: true
                    )
                    container.setLeadingAccessoryPulse(isListening)
                }
            } else {
                container.setLeadingAccessory(.hidden, animated: true)
            }

            // Hear stays on revealed rows so the user can replay a line; hide
            // only after that learner turn is done.
            let showHear = index <= highestRevealedIndex
                && !completedLearnerLineIndices.contains(index)
            container.setTrailingAccessory(showHear ? .speaker : .hidden, animated: true)
        }
        updateSpeakingMeter()
    }

    private func configureSpeakingMeter() {
        speakingMeter.isUserInteractionEnabled = false
        speakingMeter.listeningBarColor = Self.successColor
        dialogueInstallTransportCenterView(speakingMeter)
        let preferredWidth = speakingMeter.widthAnchor.constraint(
            equalTo: nestedPagingTransportBarView.widthAnchor,
            multiplier: SpeakingMeterPillView.preferredWidthMultiplier
        )
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            speakingMeter.widthAnchor.constraint(
                lessThanOrEqualToConstant: SpeakingMeterPillView.maxWidth
            ),
            preferredWidth,
        ])

        whisperSpeechToText.onInputLevel = { [weak self] level in
            self?.handleSpeakingMeterLevel(level)
        }
        onDeviceSpeechToText.onInputLevel = { [weak self] level in
            self?.handleSpeakingMeterLevel(level)
        }
        updateSpeakingMeter()
    }

    /// Grown blue bars while the learner should be speaking.
    private var shouldDriveSpeakingMeter: Bool {
        guard case .awaitingLearner(let index) = phase else { return false }
        guard !completedLearnerLineIndices.contains(index) else { return false }
        guard pendingCloudRevealIndex == nil else { return false }
        guard !isPreviewingLearnerAudio, !isPresentingSheet, !whisperListenHalted else {
            return false
        }
        return true
    }

    private func updateSpeakingMeter() {
        if shouldDriveSpeakingMeter {
            speakingMeter.setMode(.listening)
        } else {
            speakingMeter.setMode(.idle)
        }
    }

    private func handleSpeakingMeterLevel(_ level: Float) {
        guard shouldDriveSpeakingMeter else { return }
        speakingMeter.setMode(.listening)
        speakingMeter.pushLevel(level)
    }

    private func updateSwipeAffordance() {
        forEachBubbleSwipeContainer { index, container in
            container.allowsExpand = index <= highestRevealedIndex
            container.allowsProgressiveReveal = false
        }
    }

    private func playLearnerPreview(at index: Int, attempt: Int = 0) {
        guard isPreviewingLearnerAudio else { return }
        guard let spokenIndex = spokenIndex(forDisplayIndex: index),
              dialogueAlignedLines.indices.contains(spokenIndex),
              let player = dialogueMakePlayer() else {
            guard attempt < 12 else {
                finishLearnerPreview(resumeListening: true)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self else { return }
                self.playLearnerPreview(at: index, attempt: attempt + 1)
            }
            return
        }
        let range = dialogueAlignedLines[spokenIndex].timeRange
        // Stop a hair before the next line so preview never bleeds forward.
        segmentEndTime = max(range.lowerBound + 0.08, range.upperBound - 0.06)
        dialogueSeekTargetLineIndex = spokenIndex
        player.currentTime = range.lowerBound
        dialogueSetPlaybackPhase(.playing)
        dialogueUpdateElapsedLabel(currentTime: range.lowerBound)
        dialogueSetActiveLine(index, animated: false)
        dialogueStartPlayerAfterSessionActivation(player)
    }

    private func finishLearnerPreview(resumeListening: Bool) {
        guard isPreviewingLearnerAudio else { return }
        segmentEndTime = nil
        if dialoguePlaybackPhase == .playing {
            dialoguePausePlayback()
        }
        isPreviewingLearnerAudio = false
        clearHeldReplayAffordance(at: previewLineIndex, animated: true)
        previewLineIndex = nil
        updateLeadingAccessories()
        guard resumeListening else { return }
        switch phase {
        case .awaitingLearner(let index):
            dialogueSetActiveLine(index, animated: true)
            scrollRevealedLineIntoView(index)
            let delay = whisperSpeechToText.isRunning ? 0.08 : Self.listeningStartDelay
            let generation = sttGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.sttGeneration == generation else { return }
                guard case .awaitingLearner(let current) = self.phase, current == index else { return }
                self.startListening(for: index)
            }
        case .playingOther(let index):
            dialogueSetActiveLine(index, animated: true)
            scrollRevealedLineIntoView(index)
            DispatchQueue.main.async { [weak self] in
                guard let self, case .playingOther(let current) = self.phase, current == index else { return }
                self.playSegment(at: index)
            }
        case .finished, .inactive:
            break
        }
    }

    // MARK: - Speech recognition

    /// Mute Whisper and stop on-device ASR without tearing down the Realtime socket.
    private func pauseLearnerListening() {
        sttGeneration += 1
        cancelWhisperIdleWatchdog()
        if onDeviceSpeechToText.isRunning {
            onDeviceSpeechToText.stop()
        }
        if whisperSpeechToText.isRunning {
            whisperSpeechToText.setMicMuted(true)
        }
        updateLeadingAccessories()
        updateCompareCard()
    }

    private func teardownSpeechRecognition() {
        sttGeneration += 1
        pendingCloudRevealIndex = nil
        whisperListenHalted = false
        currentWhisperTurnCap = nil
        cancelWhisperIdleWatchdog()
        if onDeviceSpeechToText.isRunning {
            onDeviceSpeechToText.stop()
        }
        if whisperSpeechToText.isRunning {
            whisperSpeechToText.stop()
        }
        updateLeadingAccessories()
        updateCompareCard()
    }

    private func ttsDurationForDisplayLine(_ index: Int) -> TimeInterval? {
        guard let spokenIndex = spokenIndex(forDisplayIndex: index),
              dialogueAlignedLines.indices.contains(spokenIndex)
        else { return nil }
        let range = dialogueAlignedLines[spokenIndex].timeRange
        let duration = range.upperBound - range.lowerBound
        return duration > 0 ? duration : nil
    }

    private func noteWhisperListenActivity() {
        guard speechRecognizerBackend.usesWhisper else { return }
        guard case .awaitingLearner = phase, !whisperListenHalted else { return }
        scheduleWhisperIdleWatchdog()
    }

    private func scheduleWhisperIdleWatchdog() {
        cancelWhisperIdleWatchdog()
        let generation = sttGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.sttGeneration == generation else { return }
            self.handleWhisperIdleTimeout()
        }
        whisperIdleWatchdog = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + RolePlayWhisperListenBudget.idleTimeout,
            execute: work
        )
    }

    private func cancelWhisperIdleWatchdog() {
        whisperIdleWatchdog?.cancel()
        whisperIdleWatchdog = nil
    }

    private func handleWhisperIdleTimeout() {
        guard speechRecognizerBackend.usesWhisper else { return }
        guard case .awaitingLearner = phase, !whisperListenHalted else { return }
        guard whisperSpeechToText.isListening || onDeviceSpeechToText.isRunning else { return }
        haltWhisperListening()
    }

    /// Mute without restarting. Hear-preview or a new `startListening` retries
    /// with a fresh billed-audio budget.
    private func haltWhisperListening() {
        guard !whisperListenHalted else { return }
        guard case .awaitingLearner = phase else { return }
        whisperListenHalted = true
        cancelWhisperIdleWatchdog()
        pauseLearnerListening()
        turnHaptic.impactOccurred(intensity: 0.45)
        updateUsageLabel()
    }

    private func startListening(for index: Int) {
        guard !isPreviewingLearnerAudio, !isPresentingSheet else { return }
        guard case .awaitingLearner(let current) = phase, current == index else { return }
        guard !completedLearnerLineIndices.contains(index) else { return }
        guard dialogueDisplayLines.indices.contains(index) else { return }

        let generation = sttGeneration + 1
        sttGeneration = generation
        let backend = speechRecognizerBackend

        Task { [weak self] in
            guard let self else { return }
            let micGranted = await Self.requestMicrophonePermission()
            let speechAuthorized: Bool
            if backend.usesOnDevice {
                speechAuthorized = await SpeechToTextAuthorization.request() == .authorized
            } else {
                speechAuthorized = true
            }
            await MainActor.run {
                guard self.sttGeneration == generation else { return }
                guard case .awaitingLearner(let current) = self.phase, current == index else { return }
                guard speechAuthorized, micGranted else {
                    self.updateLeadingAccessories()
                    return
                }
                self.beginSpeechRecognition(for: index, generation: generation, backend: backend)
            }
        }
    }

    private func beginSpeechRecognition(
        for index: Int,
        generation: Int,
        backend: RolePlaySpeechRecognizerBackend
    ) {
        guard sttGeneration == generation else { return }
        guard case .awaitingLearner(let current) = phase, current == index else { return }
        guard dialogueDisplayLines.indices.contains(index) else { return }

        let target = dialogueDisplayLines[index].japanese
        // Only hint the current line. Neighboring lines make ASR paste the
        // rest of the transcript (or the next line) after a short pause.
        // GPT Whisper / compare sessions do not accept contextual prompts.
        let contextual = backend == .onDevice ? [target] : []
        compareOnDeviceText = ""
        compareWhisperText = ""
        compareTargetJapanese = target
        whisperListenHalted = false
        currentWhisperTurnCap = backend.usesWhisper
            ? RolePlayWhisperListenBudget.turnCapSeconds(
                ttsDuration: ttsDurationForDisplayLine(index),
                japanese: target
            )
            : nil

        do {
            switch backend {
            case .onDevice:
                if whisperSpeechToText.isRunning { whisperSpeechToText.stop() }
                try startOnDeviceCapture(
                    contextualStrings: contextual,
                    lineIndex: index,
                    generation: generation
                )
            case .gptRealtimeWhisper:
                if onDeviceSpeechToText.isRunning { onDeviceSpeechToText.stop() }
                whisperSpeechToText.onNativeMicBuffer = nil
                try startWhisperSession(lineIndex: index, generation: generation)
            case .compare:
                whisperSpeechToText.onNativeMicBuffer = { [weak self] buffer in
                    self?.onDeviceSpeechToText.appendBuffer(buffer)
                }
                try startWhisperSession(lineIndex: index, generation: generation)
                try startOnDeviceBufferCapture(lineIndex: index, generation: generation)
            }
            updateLeadingAccessories()
            updateCompareCard()
            if backend.usesWhisper {
                noteWhisperListenActivity()
            }
            updateUsageLabel()
        } catch {
            scheduleListeningRestart(for: index, generation: generation)
        }
    }

    private func startWhisperSession(lineIndex: Int, generation: Int) throws {
        try whisperSpeechToText.start(
            contextualStrings: [],
            maxAppendedSeconds: currentWhisperTurnCap,
            onUpdate: { [weak self] text, isFinal in
                self?.handleTranscription(
                    text,
                    isFinal: isFinal,
                    lineIndex: lineIndex,
                    generation: generation,
                    source: .whisper
                )
            },
            onError: { [weak self] _ in
                self?.scheduleListeningRestart(for: lineIndex, generation: generation)
            },
            onFinish: {}
        )
    }

    private func startOnDeviceCapture(
        contextualStrings: [String],
        lineIndex: Int,
        generation: Int
    ) throws {
        try onDeviceSpeechToText.start(
            contextualStrings: contextualStrings,
            onUpdate: { [weak self] text, isFinal in
                self?.handleTranscription(
                    text,
                    isFinal: isFinal,
                    lineIndex: lineIndex,
                    generation: generation,
                    source: .onDevice
                )
            },
            onError: { [weak self] _ in
                self?.scheduleListeningRestart(for: lineIndex, generation: generation)
            },
            onFinish: { [weak self] in
                self?.scheduleListeningRestart(for: lineIndex, generation: generation)
            }
        )
    }

    private func startOnDeviceBufferCapture(lineIndex: Int, generation: Int) throws {
        try onDeviceSpeechToText.startReceivingBuffers(
            onUpdate: { [weak self] text, isFinal in
                self?.handleTranscription(
                    text,
                    isFinal: isFinal,
                    lineIndex: lineIndex,
                    generation: generation,
                    source: .onDevice
                )
            },
            onError: { [weak self] _ in
                self?.restartOnDeviceBufferCapture(for: lineIndex, generation: generation)
            },
            onFinish: { [weak self] in
                self?.restartOnDeviceBufferCapture(for: lineIndex, generation: generation)
            }
        )
    }

    private func restartOnDeviceBufferCapture(for index: Int, generation: Int) {
        guard speechRecognizerBackend == .compare else { return }
        guard sttGeneration == generation else { return }
        guard case .awaitingLearner(let current) = phase, current == index else { return }
        guard !completedLearnerLineIndices.contains(index) else { return }
        do {
            try startOnDeviceBufferCapture(lineIndex: index, generation: generation)
        } catch {
            scheduleListeningRestart(for: index, generation: generation)
        }
    }

    private func scheduleListeningRestart(for index: Int, generation: Int) {
        guard sttGeneration == generation else { return }
        guard case .awaitingLearner(let current) = phase, current == index else { return }
        guard !completedLearnerLineIndices.contains(index) else { return }
        updateLeadingAccessories()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.listeningRestartDelay) { [weak self] in
            guard let self, self.sttGeneration == generation else { return }
            guard case .awaitingLearner(let current) = self.phase, current == index else { return }
            self.startListening(for: index)
        }
    }

    private enum TranscriptionSource {
        case onDevice
        case whisper
    }

    private func handleTranscription(
        _ text: String,
        isFinal: Bool,
        lineIndex: Int,
        generation: Int,
        source: TranscriptionSource
    ) {
        guard sttGeneration == generation else { return }
        guard case .awaitingLearner(let current) = phase, current == lineIndex else { return }
        guard dialogueDisplayLines.indices.contains(lineIndex) else { return }

        let target = dialogueDisplayLines[lineIndex].japanese
        if speechRecognizerBackend == .compare {
            switch source {
            case .onDevice: compareOnDeviceText = text
            case .whisper: compareWhisperText = text
            }
            updateCompareCard()
        }

        if completedLearnerLineIndices.contains(lineIndex) {
            return
        }

        let scoredText: String
        if speechRecognizerBackend == .compare {
            let onDeviceMatch = RolePlaySpeechMatching.evaluate(
                heard: compareOnDeviceText,
                target: target,
                alreadyMatched: 0
            )
            let whisperMatch = RolePlaySpeechMatching.evaluate(
                heard: compareWhisperText,
                target: target,
                alreadyMatched: 0
            )
            let bestCount = max(onDeviceMatch.matchedNormalizedCount, whisperMatch.matchedNormalizedCount)
            if bestCount != matchedNormalizedCount {
                matchedNormalizedCount = bestCount
                noteWhisperListenActivity()
                refreshLineAppearance()
            } else {
                updateLeadingAccessories()
            }
            if onDeviceMatch.isSoftComplete || whisperMatch.isSoftComplete {
                completeLearnerTurn()
            }
            return
        }

        scoredText = text
        let previous = matchedNormalizedCount
        let match = RolePlaySpeechMatching.evaluate(
            heard: scoredText,
            target: target,
            alreadyMatched: previous
        )

        let targetNorm = RolePlaySpeechMatching.normalizeForMatch(target)
        let heardNorm = RolePlaySpeechMatching.normalizeForMatch(scoredText)
        let targetCount = max(targetNorm.count, 1)
        let jump = match.matchedNormalizedCount - previous
        // After a pause, Speech often replaces a partial with the full
        // contextual prompt. Ignore that leap unless the line was already close.
        let nearEnd = previous >= Int(ceil(0.78 * Double(targetCount)))
        let jumpLimit = isFinal ? max(2, targetCount / 8) : max(4, targetCount / 6)
        let looksLikePromptFill =
            source == .onDevice
            && previous > 0
            && !nearEnd
            && jump > jumpLimit
            && heardNorm.count <= targetNorm.count + max(2, targetNorm.count / 10)

        if !looksLikePromptFill, match.matchedNormalizedCount != previous {
            matchedNormalizedCount = match.matchedNormalizedCount
            noteWhisperListenActivity()
            refreshLineAppearance()
        } else {
            updateLeadingAccessories()
        }

        guard match.isSoftComplete, !looksLikePromptFill else { return }
        completeLearnerTurn()
    }

    private func configureDebugChrome() {
        usageLabel.translatesAutoresizingMaskIntoConstraints = false
        usageLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        usageLabel.textColor = .tertiaryLabel
        usageLabel.textAlignment = .center
        usageLabel.numberOfLines = 2
        usageLabel.text = WhisperTranscriptionUsage().debugLine(prefix: "Turn")
            + "\n"
            + WhisperTranscriptionUsage().debugLine(prefix: "Session")

        whisperSpeechToText.onUsage = { [weak self] _, _ in
            self?.updateUsageLabel()
        }

        compareCard.translatesAutoresizingMaskIntoConstraints = false
        compareCard.layer.cornerRadius = 16
        compareCard.clipsToBounds = true
        compareCard.isHidden = true

        compareStack.translatesAutoresizingMaskIntoConstraints = false
        compareStack.axis = .vertical
        compareStack.alignment = .fill
        compareStack.spacing = 6

        for label in [compareOnDeviceLabel, compareWhisperLabel] {
            label.font = .preferredFont(forTextStyle: .footnote)
            label.textColor = .label
            label.numberOfLines = 2
            compareStack.addArrangedSubview(label)
        }

        compareCard.contentView.addSubview(compareStack)
        NSLayoutConstraint.activate([
            compareStack.topAnchor.constraint(equalTo: compareCard.contentView.topAnchor, constant: 12),
            compareStack.leadingAnchor.constraint(equalTo: compareCard.contentView.leadingAnchor, constant: 14),
            compareStack.trailingAnchor.constraint(equalTo: compareCard.contentView.trailingAnchor, constant: -14),
            compareStack.bottomAnchor.constraint(equalTo: compareCard.contentView.bottomAnchor, constant: -12),
        ])

        debugStack.translatesAutoresizingMaskIntoConstraints = false
        debugStack.axis = .vertical
        debugStack.alignment = .fill
        debugStack.spacing = 8
        debugStack.addArrangedSubview(compareCard)
        debugStack.addArrangedSubview(usageLabel)
        view.addSubview(debugStack)

        NSLayoutConstraint.activate([
            debugStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            debugStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            debugStack.bottomAnchor.constraint(
                equalTo: nestedPagingTransportBarView.topAnchor,
                constant: -8
            ),
        ])
        updateCompareCard()
        updateUsageLabel()
    }

    private func updateUsageLabel() {
        let visible = speechRecognizerBackend.usesWhisper && !isPresentingSheet
        usageLabel.isHidden = !visible
        if visible {
            let cap = currentWhisperTurnCap
            let sent = whisperSpeechToText.appendedAudioSeconds
            let turnLine: String
            if let cap {
                let paused = whisperListenHalted ? " · paused" : ""
                turnLine = String(
                    format: "Turn  %.1fs / %.0fs cap · $%.4f%@",
                    sent,
                    cap,
                    whisperSpeechToText.turnUsage.estimatedCostUSD,
                    paused
                )
            } else {
                turnLine = whisperSpeechToText.turnUsage.debugLine(prefix: "Turn")
            }
            usageLabel.text =
                turnLine
                + "\n"
                + whisperSpeechToText.sessionUsage.debugLine(prefix: "Session")
            view.bringSubviewToFront(debugStack)
        }
        rolePlaySheet?.updateUsageText(completionUsageText())
    }

    private func completionUsageText() -> String? {
        guard speechRecognizerBackend.usesWhisper else { return nil }
        return whisperSpeechToText.sessionUsage.completionBreakdown()
    }

    private func updateCompareCard() {
        let visible = speechRecognizerBackend == .compare && !isPresentingSheet
        compareCard.isHidden = !visible
        updateUsageLabel()
        guard visible else { return }
        view.bringSubviewToFront(debugStack)
        compareOnDeviceLabel.attributedText = compareRow(
            title: "On Device",
            heard: compareOnDeviceText,
            targetIndex: {
                if case .awaitingLearner(let index) = phase { return index }
                return nil
            }()
        )
        compareWhisperLabel.attributedText = compareRow(
            title: "GPT Whisper",
            heard: compareWhisperText,
            targetIndex: {
                if case .awaitingLearner(let index) = phase { return index }
                return nil
            }()
        )
    }

    private func compareRow(title: String, heard: String, targetIndex: Int?) -> NSAttributedString {
        let target: String = {
            if let targetIndex, dialogueDisplayLines.indices.contains(targetIndex) {
                return dialogueDisplayLines[targetIndex].japanese
            }
            return compareTargetJapanese
        }()
        let percent: String = {
            guard !target.isEmpty else { return "—" }
            return "\(compareMatchPercent(heard: heard, target: target))%"
        }()
        let heardText = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = heardText.isEmpty ? "Listening…" : heardText

        let text = NSMutableAttributedString()
        text.append(NSAttributedString(
            string: "\(title)  \(percent)\n",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .caption1),
                .foregroundColor: UIColor.secondaryLabel,
            ]
        ))
        text.append(NSAttributedString(
            string: body,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .footnote),
                .foregroundColor: UIColor.label,
            ]
        ))
        return text
    }

    private func compareMatchPercent(heard: String, target: String) -> Int {
        guard !target.isEmpty else { return 0 }
        let match = RolePlaySpeechMatching.evaluate(heard: heard, target: target, alreadyMatched: 0)
        let total = max(RolePlaySpeechMatching.normalizeForMatch(target).count, 1)
        return Int((Double(match.matchedNormalizedCount) / Double(total) * 100).rounded())
    }

    private func recordCompareSnapshot(for index: Int) {
        guard dialogueDisplayLines.indices.contains(index) else { return }
        compareTurnSnapshots.append(
            RolePlayCompareTurnSnapshot(
                targetJapanese: dialogueDisplayLines[index].japanese,
                onDeviceText: compareOnDeviceText,
                whisperText: compareWhisperText
            )
        )
    }

    private static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Role picker & completion

    private func presentRolePickerIfNeeded() {
        let speakers = uniqueSpeakers()
        guard !speakers.isEmpty else {
            phase = .finished
            return
        }
        if speakers.count == 1 {
            learnerSpeaker = speakers[0]
            beginRolePlay()
            return
        }
        presentRolePicker(animated: view.window != nil)
    }

    private func presentRolePicker(animated: Bool) {
        teardownSpeechRecognition()
        isPreviewingLearnerAudio = false
        if dialoguePlaybackPhase == .playing {
            dialoguePausePlayback()
        }
        phase = .inactive
        completionFeedbackGeneration += 1
        concealUnrevealedLines()
        restoreDefaultLineAppearance()
        dialogueRefreshOverflowMenu()
        dialogueUpdateTransportControls()
        presentRolePlaySheet(.pickRole(speakers: uniqueSpeakers()), animated: animated)
    }

    private func presentCompletion() {
        phase = .finished
        // Commit the last utterance, but keep the socket up briefly so its
        // usage event can still land on the completion recap.
        pauseLearnerListening()
        if dialoguePlaybackPhase == .playing {
            dialoguePausePlayback()
        }
        refreshLineAppearance()
        dialogueRefreshOverflowMenu()
        dialogueUpdateTransportControls()
        if !didRecordCompletion {
            didRecordCompletion = true
            dialogueMarkScenarioCompleted()
        }
        ExperimentFeedbackSound.playLessonComplete()
        presentRolePlaySheet(
            .complete(
                usageText: completionUsageText(),
                compareSnapshots: compareTurnSnapshots
            ),
            animated: true
        )
    }

    private func presentRolePlaySheet(
        _ mode: DialogueRolePlaySheetViewController.Mode,
        animated: Bool
    ) {
        isPresentingSheet = true
        dialogueSetTransportBarHidden(true)
        updateCompareCard()
        updateSpeakingMeter()

        if let presented = presentedViewController {
            if let sheet = rolePlaySheet(from: presented) {
                rolePlaySheet = sheet
                sheet.apply(mode)
                return
            }
            presented.dismiss(animated: animated) { [weak self] in
                self?.presentRolePlaySheet(mode, animated: animated)
            }
            return
        }

        if let sheet = rolePlaySheet, sheet.presentingViewController != nil || sheet.navigationController?.presentingViewController != nil {
            sheet.apply(mode)
            return
        }

        let sheet = DialogueRolePlaySheetViewController(mode: mode)
        sheet.onSelectSpeaker = { [weak self] speaker in
            self?.selectLearnerSpeaker(speaker)
        }
        sheet.onReplay = { [weak self] in
            self?.beginRolePlay()
        }
        sheet.onSwitchRoles = { [weak self] in
            self?.presentRolePicker(animated: true)
        }
        sheet.onDone = { [weak self] in
            self?.dismissRolePlaySheet(animated: true) {
                self?.dismissRolePlay()
            }
        }
        sheet.onDismissed = { [weak self] in
            self?.handleSheetDismissed()
        }
        rolePlaySheet = sheet

        let nav = UINavigationController(rootViewController: sheet)
        nav.navigationBar.prefersLargeTitles = false
        nav.modalPresentationStyle = .pageSheet
        if case .pickRole = mode {
            nav.isModalInPresentation = true
        }
        if let presentation = nav.sheetPresentationController {
            presentation.prefersGrabberVisible = true
            presentation.prefersEdgeAttachedInCompactHeight = true
            presentation.delegate = sheet
            switch mode {
            case .pickRole:
                presentation.detents = [.medium()]
                presentation.prefersScrollingExpandsWhenScrolledToEdge = false
            case .complete:
                presentation.detents = [.medium(), .large()]
                presentation.prefersScrollingExpandsWhenScrolledToEdge = true
            }
        }
        nav.presentationController?.delegate = sheet
        present(nav, animated: animated)
    }

    private func rolePlaySheet(from presented: UIViewController) -> DialogueRolePlaySheetViewController? {
        if let sheet = presented as? DialogueRolePlaySheetViewController {
            return sheet
        }
        if let nav = presented as? UINavigationController {
            return nav.viewControllers.first as? DialogueRolePlaySheetViewController
        }
        return nil
    }

    private func dismissRolePlaySheet(animated: Bool, completion: (() -> Void)? = nil) {
        isPresentingSheet = false
        dialogueSetTransportBarHidden(false)
        updateCompareCard()
        updateSpeakingMeter()

        let presented = presentedViewController
        rolePlaySheet = nil
        guard let presented else {
            completion?()
            return
        }
        presented.dismiss(animated: animated, completion: completion)
    }

    private func handleSheetDismissed() {
        isPresentingSheet = false
        rolePlaySheet = nil
        dialogueSetTransportBarHidden(false)
        updateCompareCard()
        updateSpeakingMeter()
    }

    private func selectLearnerSpeaker(_ speaker: String) {
        learnerSpeaker = speaker
        beginRolePlay()
    }

    private func dismissRolePlay() {
        if navigationController?.viewControllers.first === self {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
}
