//
//  RealtimeTutorHarnessView.swift
//  shizen
//
//  Embeddable Realtime tutor chrome: status label + glass meter pill.
//  Owns the WebSocket session so any screen can stub it in.
//

import UIKit

protocol RealtimeTutorHarnessDelegate: AnyObject {
    func tutorHarness(_ harness: RealtimeTutorHarnessView, didChangeConnectionState state: RealtimeConnectionState)
    func tutorHarness(_ harness: RealtimeTutorHarnessView, didChangeTurn turn: RealtimeConversationTurn)
    func tutorHarness(
        _ harness: RealtimeTutorHarnessView,
        didReceiveUserTranscript text: String,
        audioClip: RealtimeAudioClip?
    )
    func tutorHarness(
        _ harness: RealtimeTutorHarnessView,
        didCompleteAssistantTranscript text: String,
        sentenceClips: [(sentence: String, clip: RealtimeAudioClip)]
    )
    func tutorHarnessDidFinishSingleTurnSession(_ harness: RealtimeTutorHarnessView)
    func tutorHarness(_ harness: RealtimeTutorHarnessView, didEncounterError error: Error)
}

extension RealtimeTutorHarnessDelegate {
    func tutorHarness(_ harness: RealtimeTutorHarnessView, didChangeConnectionState state: RealtimeConnectionState) {}
    func tutorHarness(_ harness: RealtimeTutorHarnessView, didChangeTurn turn: RealtimeConversationTurn) {}
    func tutorHarness(
        _ harness: RealtimeTutorHarnessView,
        didReceiveUserTranscript text: String,
        audioClip: RealtimeAudioClip?
    ) {}
    func tutorHarness(
        _ harness: RealtimeTutorHarnessView,
        didCompleteAssistantTranscript text: String,
        sentenceClips: [(sentence: String, clip: RealtimeAudioClip)]
    ) {}
    func tutorHarnessDidFinishSingleTurnSession(_ harness: RealtimeTutorHarnessView) {}
    func tutorHarness(_ harness: RealtimeTutorHarnessView, didEncounterError error: Error) {}
}

/// Compact bottom chrome for a Realtime session — status copy + live meter pill.
final class RealtimeTutorHarnessView: UIView {

    weak var delegate: RealtimeTutorHarnessDelegate?

    private(set) var configuration: RealtimeTutorSessionConfiguration

    private let realtimeService = RealtimeService()

    private let statusLabel = UILabel()
    private let meterRow = UIView()
    private let pillContainer = UIView()
    private let pillBackground = LiquidGlassEffectView.makeLightPillContainer()
    private let levelMeterView = AudioLevelBarsView()
    private let trailingAccessoryContainer = UIView()

    private var shouldEndAfterTutorPlayback = false
    private var didNotifySingleTurnCompletion = false
    private var completedAssistantResponses = 0
    /// When true, the session is connected but mic capture is deferred until ``beginListening()``.
    private var isListeningDeferred = false
    private var lastTurnForHaptic: RealtimeConversationTurn?
    private let turnHaptic = UIImpactFeedbackGenerator(style: .medium)

    private static let activeMeterColor = UIColor.systemYellow
    private static let idleMeterColor = UIColor.tertiaryLabel
    private static let tutorMeterColor = UIColor.label
    private static let pillHeight: CGFloat = 64
    private static let trailingAccessorySize: CGFloat = 56
    private static let trailingAccessorySpacing: CGFloat = 12

    var isSessionActive: Bool {
        switch realtimeService.connectionState {
        case .connecting, .connected: return true
        case .disconnected, .failed: return false
        }
    }

    var connectionState: RealtimeConnectionState {
        realtimeService.connectionState
    }

    var conversationTurn: RealtimeConversationTurn {
        realtimeService.conversationTurn
    }

    // MARK: - Init

    init(configuration: RealtimeTutorSessionConfiguration = .openConversation) {
        self.configuration = configuration
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        realtimeService.delegate = self
        configureUI()
        applyIdleAppearance(status: nil)
        turnHaptic.prepare()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API

    func applyConfiguration(_ configuration: RealtimeTutorSessionConfiguration) {
        self.configuration = configuration
    }

    /// - Parameter startListening: Pass `false` to open the WebSocket while other audio plays;
    ///   call ``beginListening()`` when the student should speak.
    func connect(startListening: Bool = true) {
        shouldEndAfterTutorPlayback = false
        didNotifySingleTurnCompletion = false
        completedAssistantResponses = 0
        isListeningDeferred = !startListening
        applyStatus(startListening ? "Connecting…" : "Listen…", animated: true)
        realtimeService.connect(
            sessionInstructions: configuration.sessionInstructions,
            startListening: startListening
        )
    }

    func setMicMuted(_ muted: Bool) {
        realtimeService.setMicMuted(muted)
    }

    /// Opens the mic after a ``connect(startListening: false)`` prefetch.
    /// Safe to call before the socket finishes connecting — listening starts when ready.
    func beginListening() {
        guard isListeningDeferred else { return }
        isListeningDeferred = false
        applyStatus("Connecting…", animated: true)
        realtimeService.enableListeningWhenReady()
    }

    /// Ends the session after the tutor finishes the current reply (playback done).
    func requestEndAfterCurrentTutorReply() {
        guard !didNotifySingleTurnCompletion else { return }
        shouldEndAfterTutorPlayback = true
    }

    /// Immediately stops the session (e.g. user tapped the meter).
    func stopSession() {
        guard !didNotifySingleTurnCompletion else { return }
        shouldEndAfterTutorPlayback = false
        didNotifySingleTurnCompletion = true
        isListeningDeferred = false
        realtimeService.disconnect()
        setFinishedAppearance(status: "Stopped")
        delegate?.tutorHarnessDidFinishSingleTurnSession(self)
    }

    func disconnect() {
        shouldEndAfterTutorPlayback = false
        isListeningDeferred = false
        realtimeService.disconnect()
        applyIdleAppearance(status: nil)
    }

    func setIdleStatus(_ text: String?) {
        guard !isSessionActive || isListeningDeferred else { return }
        applyIdleAppearance(status: text)
    }

    func setFinishedAppearance(status: String = "Nice work!") {
        isListeningDeferred = false
        levelMeterView.releaseToRest()
        levelMeterView.barColor = Self.idleMeterColor
        applyStatus(status, animated: true)
    }

    /// Places a view to the right of the centered meter pill without shifting the pill.
    func setTrailingAccessory(_ view: UIView?) {
        trailingAccessoryContainer.subviews.forEach { $0.removeFromSuperview() }
        guard let view else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        trailingAccessoryContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: trailingAccessoryContainer.topAnchor),
            view.leadingAnchor.constraint(equalTo: trailingAccessoryContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAccessoryContainer.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: trailingAccessoryContainer.bottomAnchor),
        ])
    }

    // MARK: - UI

    private func configureUI() {
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        statusLabel.textColor = .tertiaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 1
        statusLabel.alpha = 0

        LiquidGlassEffectView.applyPillStyle(to: pillBackground, cornerRadius: Self.pillHeight / 2)
        pillBackground.isUserInteractionEnabled = false

        pillContainer.translatesAutoresizingMaskIntoConstraints = false
        pillContainer.isAccessibilityElement = true
        pillContainer.accessibilityTraits = .button
        pillContainer.accessibilityLabel = "Stop conversation"
        pillContainer.accessibilityHint = "Ends the current tutor session"
        pillContainer.addSubview(pillBackground)

        let meterTap = UITapGestureRecognizer(target: self, action: #selector(meterPillTapped))
        pillContainer.addGestureRecognizer(meterTap)

        levelMeterView.translatesAutoresizingMaskIntoConstraints = false
        levelMeterView.isUserInteractionEnabled = false
        levelMeterView.barWidth = 8
        levelMeterView.barSpacing = 10
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
        levelMeterView.barColor = Self.idleMeterColor
        pillContainer.addSubview(levelMeterView)

        meterRow.translatesAutoresizingMaskIntoConstraints = false
        meterRow.clipsToBounds = false
        meterRow.addSubview(pillContainer)

        trailingAccessoryContainer.translatesAutoresizingMaskIntoConstraints = false
        trailingAccessoryContainer.clipsToBounds = false
        meterRow.addSubview(trailingAccessoryContainer)

        let stack = UIStackView(arrangedSubviews: [statusLabel, meterRow])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 14
        stack.clipsToBounds = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),

            meterRow.heightAnchor.constraint(equalToConstant: Self.pillHeight),

            pillContainer.centerXAnchor.constraint(equalTo: meterRow.centerXAnchor),
            pillContainer.centerYAnchor.constraint(equalTo: meterRow.centerYAnchor),
            pillContainer.heightAnchor.constraint(equalToConstant: Self.pillHeight),
            pillContainer.widthAnchor.constraint(equalTo: meterRow.widthAnchor, multiplier: 0.52),
            pillContainer.widthAnchor.constraint(lessThanOrEqualToConstant: 220),

            trailingAccessoryContainer.leadingAnchor.constraint(
                equalTo: pillContainer.trailingAnchor,
                constant: Self.trailingAccessorySpacing
            ),
            trailingAccessoryContainer.centerYAnchor.constraint(equalTo: pillContainer.centerYAnchor),
            trailingAccessoryContainer.widthAnchor.constraint(equalToConstant: Self.trailingAccessorySize),
            trailingAccessoryContainer.heightAnchor.constraint(equalToConstant: Self.trailingAccessorySize),
            trailingAccessoryContainer.trailingAnchor.constraint(
                lessThanOrEqualTo: meterRow.trailingAnchor
            ),

            pillBackground.topAnchor.constraint(equalTo: pillContainer.topAnchor),
            pillBackground.leadingAnchor.constraint(equalTo: pillContainer.leadingAnchor),
            pillBackground.trailingAnchor.constraint(equalTo: pillContainer.trailingAnchor),
            pillBackground.bottomAnchor.constraint(equalTo: pillContainer.bottomAnchor),

            levelMeterView.centerXAnchor.constraint(equalTo: pillContainer.centerXAnchor),
            levelMeterView.centerYAnchor.constraint(equalTo: pillContainer.centerYAnchor),
            levelMeterView.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    private func applyIdleAppearance(status: String?) {
        levelMeterView.releaseToRest()
        levelMeterView.barColor = Self.idleMeterColor
        applyStatus(status, animated: false)
    }

    private func applyStatus(_ text: String?, animated: Bool) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = !(trimmed?.isEmpty ?? true)

        let apply = {
            self.statusLabel.text = trimmed
            self.statusLabel.alpha = visible ? 1 : 0
        }

        guard animated else {
            apply()
            return
        }

        UIView.animate(withDuration: 0.22, delay: 0, options: [.beginFromCurrentState]) {
            apply()
        }
    }

    private func updateTurnChrome(_ turn: RealtimeConversationTurn) {
        if isListeningDeferred {
            levelMeterView.barColor = Self.idleMeterColor
            levelMeterView.fadeToMinimum()
            switch turn {
            case .connecting:
                applyStatus("Connecting…", animated: true)
            case .paused, .yourTurn:
                // Session ready; still waiting for reference audio / beginListening().
                applyStatus("Listen…", animated: true)
            case .stopped:
                applyStatus(nil, animated: true)
            case .tutorTurn:
                break
            }
            return
        }

        switch turn {
        case .connecting:
            levelMeterView.barColor = Self.idleMeterColor
            levelMeterView.fadeToMinimum()
            applyStatus("Connecting…", animated: true)
        case .yourTurn:
            levelMeterView.barColor = Self.activeMeterColor
            applyStatus("Your turn to speak…", animated: true)
        case .tutorTurn:
            levelMeterView.barColor = Self.tutorMeterColor
            applyStatus("Tutor speaking…", animated: true)
        case .paused:
            levelMeterView.barColor = Self.idleMeterColor
            levelMeterView.fadeToMinimum()
            applyStatus("Paused", animated: true)
        case .stopped:
            levelMeterView.barColor = Self.idleMeterColor
            levelMeterView.reset()
            applyStatus(nil, animated: true)
        }
    }

    private func pushMeterLevel(_ level: Float) {
        let clamped = max(0, min(1, level))
        let eased = clamped * clamped * (3 - 2 * clamped)
        levelMeterView.setLevel(eased)
    }

    @objc private func meterPillTapped() {
        guard isSessionActive else { return }
        stopSession()
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
        setFinishedAppearance()
        delegate?.tutorHarnessDidFinishSingleTurnSession(self)
    }
}

// MARK: - RealtimeServiceDelegate

extension RealtimeTutorHarnessView: RealtimeServiceDelegate {

    func realtimeService(_ service: RealtimeService, didChangeConnectionState state: RealtimeConnectionState) {
        switch state {
        case .connecting:
            applyStatus("Connecting…", animated: true)
        case .connected:
            break
        case .disconnected, .failed:
            if !didNotifySingleTurnCompletion {
                levelMeterView.barColor = Self.idleMeterColor
                levelMeterView.releaseToRest()
            }
        }
        delegate?.tutorHarness(self, didChangeConnectionState: state)
    }

    func realtimeService(_ service: RealtimeService, didChangeTurn turn: RealtimeConversationTurn) {
        if turn != lastTurnForHaptic, turn == .yourTurn || turn == .tutorTurn {
            turnHaptic.impactOccurred()
        }
        lastTurnForHaptic = turn
        updateTurnChrome(turn)
        completeSingleTurnSessionIfReady(for: turn)
        delegate?.tutorHarness(self, didChangeTurn: turn)
    }

    func realtimeService(_ service: RealtimeService, didReceiveUserTranscriptDelta delta: String) {}

    func realtimeService(
        _ service: RealtimeService,
        didReceiveUserTranscript text: String,
        audioClip: RealtimeAudioClip?
    ) {
        delegate?.tutorHarness(self, didReceiveUserTranscript: text, audioClip: audioClip)
    }

    func realtimeService(_ service: RealtimeService, didReceiveAssistantTranscriptDelta delta: String) {}

    func realtimeService(
        _ service: RealtimeService,
        didCompleteAssistantTranscript text: String,
        sentenceClips: [(sentence: String, clip: RealtimeAudioClip)]
    ) {
        markSingleTurnEndIfNeeded()
        delegate?.tutorHarness(self, didCompleteAssistantTranscript: text, sentenceClips: sentenceClips)
    }

    func realtimeService(_ service: RealtimeService, didUpdateUsage usage: RealtimeTokenUsage) {}

    func realtimeService(_ service: RealtimeService, didEncounterError error: Error) {
        let message = error.localizedDescription.lowercased()
        if message.contains("no active response") || message.contains("cancel") {
            return
        }
        delegate?.tutorHarness(self, didEncounterError: error)
    }

    func realtimeServiceDidDetectSpeechStarted(_ service: RealtimeService) {}

    func realtimeService(_ service: RealtimeService, didUpdateInputLevel level: Float) {
        guard service.conversationTurn == .yourTurn,
              !service.isMicMuted else { return }
        pushMeterLevel(level)
    }

    func realtimeService(_ service: RealtimeService, didUpdateOutputLevel level: Float) {
        guard service.conversationTurn == .tutorTurn else { return }
        pushMeterLevel(level)
    }

    func realtimeService(_ service: RealtimeService, didChangeMicMuted isMuted: Bool) {
        if isMuted {
            levelMeterView.fadeToMinimum()
        }
    }
}
