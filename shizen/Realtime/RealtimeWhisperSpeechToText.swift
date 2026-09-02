//
//  RealtimeWhisperSpeechToText.swift
//  shizen
//
//  Streaming Japanese STT via OpenAI Realtime transcription (gpt-realtime-whisper).
//  Dedicated transcription session — no assistant audio. Whisper does not support
//  server VAD, so only speech plus a short hangover is uploaded; silence-based
//  client commits close each utterance. A per-turn appended-audio cap stops a
//  blast from sitting on the socket.
//

import AVFoundation
import Foundation

struct WhisperTranscriptionUsage: Equatable {
    var audioSeconds: Double = 0
    var eventCount = 0

    mutating func accumulate(from usage: [String: Any]) {
        eventCount += 1
        if let seconds = Self.doubleValue(usage["seconds"]) {
            audioSeconds += seconds
        } else if let duration = usage["duration"] as? [String: Any],
                  let seconds = Self.doubleValue(duration["seconds"]) {
            audioSeconds += seconds
        }
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        if let value = any as? Double { return value }
        if let value = any as? Int { return Double(value) }
        if let value = any as? NSNumber { return value.doubleValue }
        return nil
    }

    /// gpt-realtime-whisper is billed by audio duration, not tokens.
    static let dollarsPerAudioMinute = 0.017

    var estimatedCostUSD: Double {
        (audioSeconds / 60.0) * Self.dollarsPerAudioMinute
    }

    func debugLine(prefix: String) -> String {
        String(
            format: "%@  %.1fs · $%.4f",
            prefix,
            audioSeconds,
            estimatedCostUSD
        )
    }

    func completionBreakdown() -> String {
        [
            "GPT Whisper",
            String(format: "%.1fs audio · %d turns", audioSeconds, eventCount),
            String(format: "Est. $%.4f  at $%.3f/min", estimatedCostUSD, Self.dollarsPerAudioMinute),
        ].joined(separator: "\n")
    }
}

final class RealtimeWhisperSpeechToText: NSObject {

    static let sampleRate: Double = 24_000

    private(set) var isRunning = false
    private(set) var isMicMuted = false

    var isListening: Bool { isRunning && isSessionReady && !isMicMuted }

    var onNativeMicBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onUsage: ((WhisperTranscriptionUsage, WhisperTranscriptionUsage) -> Void)?
    /// Fired on the main queue with RMS in [0, 1] while the mic is unmuted.
    var onInputLevel: ((Float) -> Void)?
    /// Fired on the main queue when RMS crosses the speech threshold (throttled).
    var onSpeechActivity: (() -> Void)?
    /// Fired on the main queue when `maxAppendedSeconds` is reached this turn.
    var onAppendedBudgetExhausted: (() -> Void)?
    /// Fired on the main queue as PCM is uploaded (throttled).
    var onAppendedAudio: ((TimeInterval) -> Void)?

    private(set) var turnUsage = WhisperTranscriptionUsage()
    private(set) var sessionUsage = WhisperTranscriptionUsage()
    /// Seconds of PCM actually appended this unmute / listen turn.
    private(set) var appendedAudioSeconds: TimeInterval = 0
    /// Hard stop on uploaded audio for the current listen. `nil` = unlimited.
    var maxAppendedSeconds: TimeInterval?

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var receiveLoopActive = false
    private var isConnected = false
    private(set) var isSessionReady = false

    var onSessionReady: (() -> Void)?
    var onSessionFailed: (() -> Void)?

    private let audioEngine = AVAudioEngine()
    private var audioConverter: AVAudioConverter?
    private var targetPCMFormat: AVAudioFormat?

    private let sendQueue = DispatchQueue(label: "RealtimeWhisperSpeechToText.send")

    private var onUpdate: ((String, Bool) -> Void)?
    private var onError: ((Error?) -> Void)?
    private var onFinish: (() -> Void)?

    /// Transcript from completed commits in this listening session.
    private var committedTranscript = ""
    /// Live deltas for the current (uncommitted) buffer.
    private var liveDeltaTranscript = ""

    private var hasBufferedAudioSinceCommit = false
    private var isSpeechActive = false
    private var hasSeenSpeechThisUnmute = false
    private var lastSpeechTime: CFAbsoluteTime = 0
    private var lastSpeechActivityNotify: CFAbsoluteTime = 0
    private var lastAppendedAudioNotify: CFAbsoluteTime = 0
    private var silenceCommitWorkItem: DispatchWorkItem?
    private var didExhaustBudget = false

    private static let speechRMSThreshold: Float = 0.018
    private static let silenceCommitDelay: TimeInterval = 0.65
    /// Keep uploading a beat after RMS drops so word endings are not clipped.
    private static let sendHangover: TimeInterval = 0.25
    private static let speechActivityNotifyInterval: TimeInterval = 0.35
    private static let appendedAudioNotifyInterval: TimeInterval = 0.2

    // MARK: - Public

    func start(
        contextualStrings: [String] = [],
        maxAppendedSeconds: TimeInterval? = nil,
        onUpdate: @escaping (String, Bool) -> Void,
        onError: @escaping (Error?) -> Void,
        onFinish: @escaping () -> Void
    ) throws {
        _ = contextualStrings // Whisper GA sessions do not accept transcription prompts.
        self.maxAppendedSeconds = maxAppendedSeconds
        self.onUpdate = onUpdate
        self.onError = onError
        self.onFinish = onFinish
        resetUtterance()
        resetTurnUsage()
        resetAppendedAudio()
        try ensureConnected(muted: false)
    }

    /// Opens the transcription socket without requiring listen callbacks.
    /// Used so Role Play can connect during the other speaker's lines.
    func ensureConnected(muted: Bool) throws {
        if isRunning {
            if isSessionReady {
                setMicMuted(muted)
            } else {
                isMicMuted = muted
            }
            if !muted {
                clearInputAudioBuffer()
                resetUtterance()
                resetAppendedAudio()
            }
            return
        }

        isMicMuted = muted
        isSessionReady = false
        hasBufferedAudioSinceCommit = false
        isSpeechActive = false
        hasSeenSpeechThisUnmute = false
        lastSpeechTime = 0
        didExhaustBudget = false
        appendedAudioSeconds = 0
        sessionUsage = WhisperTranscriptionUsage()
        turnUsage = WhisperTranscriptionUsage()

        let apiKey = OpenAIAppKey.resolved
        guard !apiKey.isEmpty else {
            throw NSError(
                domain: "RealtimeWhisperSpeechToText",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "OPENAI_API_KEY is missing."]
            )
        }

        guard let url = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription") else {
            throw NSError(
                domain: "RealtimeWhisperSpeechToText",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Realtime transcription URL."]
            )
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
        )
        try session.setActive(true, options: [])
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try? session.setPreferredSampleRate(Self.sampleRate)
        try? session.setPreferredIOBufferDuration(0.02)

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let urlSession = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
        self.urlSession = urlSession
        let task = urlSession.webSocketTask(with: request)
        webSocket = task
        receiveLoopActive = true
        isRunning = true
        task.resume()
        startReceiveLoop()
    }

    func setMicMuted(_ muted: Bool) {
        guard isMicMuted != muted else { return }
        isMicMuted = muted
        if muted {
            silenceCommitWorkItem?.cancel()
            silenceCommitWorkItem = nil
            isSpeechActive = false
            hasSeenSpeechThisUnmute = false
            lastSpeechTime = 0
            // Commit so the server emits transcription.completed + usage.
            // Clearing instead discarded the turn and left the counter at —.
            commitInputAudioBufferIfNeeded()
            resetUtterance()
        } else {
            resetAppendedAudio()
            resetUtterance()
        }
    }

    func resetUtterance() {
        committedTranscript = ""
        liveDeltaTranscript = ""
    }

    private func resetTurnUsage() {
        turnUsage = WhisperTranscriptionUsage()
        emitUsage()
    }

    private func resetAppendedAudio() {
        appendedAudioSeconds = 0
        didExhaustBudget = false
        hasSeenSpeechThisUnmute = false
        lastSpeechTime = 0
        isSpeechActive = false
        lastSpeechActivityNotify = 0
        lastAppendedAudioNotify = 0
        emitAppendedAudio(force: true)
    }

    private func accumulateUsage(_ usage: [String: Any]) {
        turnUsage.accumulate(from: usage)
        sessionUsage.accumulate(from: usage)
        emitUsage()
    }

    private func emitUsage() {
        let turn = turnUsage
        let session = sessionUsage
        DispatchQueue.main.async { [weak self] in
            self?.onUsage?(turn, session)
        }
    }

    private func emitAppendedAudio(force: Bool) {
        let now = CFAbsoluteTimeGetCurrent()
        if !force, now - lastAppendedAudioNotify < Self.appendedAudioNotifyInterval {
            return
        }
        lastAppendedAudioNotify = now
        let seconds = appendedAudioSeconds
        DispatchQueue.main.async { [weak self] in
            self?.onAppendedAudio?(seconds)
        }
    }

    func stop() {
        silenceCommitWorkItem?.cancel()
        silenceCommitWorkItem = nil
        receiveLoopActive = false
        isSessionReady = false
        isConnected = false
        isMicMuted = false
        onNativeMicBuffer = nil

        stopMicCapture()

        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        onUpdate = nil
        onError = nil
        onFinish = nil
        committedTranscript = ""
        liveDeltaTranscript = ""
        hasBufferedAudioSinceCommit = false
        isSpeechActive = false
        hasSeenSpeechThisUnmute = false
        lastSpeechTime = 0
        didExhaustBudget = false
        appendedAudioSeconds = 0
        maxAppendedSeconds = nil
        isRunning = false
        turnUsage = WhisperTranscriptionUsage()
        sessionUsage = WhisperTranscriptionUsage()

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - WebSocket

    private func startReceiveLoop() {
        guard let webSocket, receiveLoopActive else { return }
        webSocket.receive { [weak self] result in
            guard let self, self.receiveLoopActive else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleServerMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleServerMessage(text)
                    }
                @unknown default:
                    break
                }
                self.startReceiveLoop()
            case .failure(let error):
                self.fail(error)
            }
        }
    }

    private func handleServerMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return }

        switch type {
        case "session.created":
            sendSessionUpdate()

        case "session.updated":
            guard !isSessionReady else { return }
            isSessionReady = true
            isConnected = true
            do {
                try startMicCapture()
                DispatchQueue.main.async { [weak self] in
                    self?.onSessionReady?()
                }
            } catch {
                fail(error)
            }

        case "conversation.item.input_audio_transcription.delta":
            if let delta = json["delta"] as? String, !delta.isEmpty {
                liveDeltaTranscript += delta
                emitUpdate(isFinal: false)
            }

        case "conversation.item.input_audio_transcription.completed":
            let transcript = (json["transcript"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !transcript.isEmpty {
                if committedTranscript.isEmpty {
                    committedTranscript = transcript
                } else {
                    committedTranscript += transcript
                }
            }
            liveDeltaTranscript = ""
            // Keep the socket open; Role Play only restarts on-device ASR on finish.
            emitUpdate(isFinal: true)
            if let usage = json["usage"] as? [String: Any] {
                accumulateUsage(usage)
            }

        case "conversation.item.input_audio_transcription.failed":
            let message = Self.errorMessage(from: json) ?? "Input transcription failed"
            fail(NSError(
                domain: "RealtimeWhisperSpeechToText",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: message]
            ))

        case "error":
            if Self.shouldIgnoreError(json) { return }
            let message = Self.errorMessage(from: json) ?? "Realtime transcription error"
            fail(NSError(
                domain: "RealtimeWhisperSpeechToText",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: message]
            ))

        default:
            if let usage = json["usage"] as? [String: Any] {
                accumulateUsage(usage)
            }
        }
    }

    private func sendSessionUpdate() {
        // turn_detection must be null — gpt-realtime-whisper rejects server VAD.
        let payload: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": Int(Self.sampleRate),
                        ],
                        "transcription": [
                            "model": "gpt-realtime-whisper",
                            "language": "ja",
                            "delay": "low",
                        ],
                        "turn_detection": NSNull(),
                    ],
                ],
            ],
        ]
        sendJSON(payload)
    }

    private func sendJSON(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8)
        else { return }
        sendQueue.async { [weak self] in
            self?.webSocket?.send(.string(text)) { [weak self] error in
                if let error {
                    DispatchQueue.main.async {
                        self?.fail(error)
                    }
                }
            }
        }
    }

    private func sendInputAudioAppend(base64PCM: String) {
        sendJSON([
            "type": "input_audio_buffer.append",
            "audio": base64PCM,
        ])
    }

    private func clearInputAudioBuffer() {
        hasBufferedAudioSinceCommit = false
        guard isSessionReady else { return }
        sendJSON(["type": "input_audio_buffer.clear"])
    }

    private func commitInputAudioBufferIfNeeded() {
        guard isSessionReady, hasBufferedAudioSinceCommit else { return }
        hasBufferedAudioSinceCommit = false
        isSpeechActive = false
        sendJSON(["type": "input_audio_buffer.commit"])
    }

    // MARK: - Mic

    private func startMicCapture() throws {
        targetPCMFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: true
        )

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard let targetPCMFormat else {
            throw NSError(
                domain: "RealtimeWhisperSpeechToText",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create PCM format."]
            )
        }
        audioConverter = AVAudioConverter(from: inputFormat, to: targetPCMFormat)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            self?.processMicBuffer(buffer)
        }

        audioEngine.prepare()
        if !audioEngine.isRunning {
            try audioEngine.start()
        }
    }

    private func stopMicCapture() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        audioConverter = nil
        targetPCMFormat = nil
    }

    private func processMicBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isSessionReady, isRunning, !isMicMuted, !didExhaustBudget else { return }

        onNativeMicBuffer?(buffer)

        let level = Self.rmsInputLevel(from: buffer)
        DispatchQueue.main.async { [weak self] in
            self?.onInputLevel?(level)
        }
        updateSpeechActivity(level: level)

        let now = CFAbsoluteTimeGetCurrent()
        let shouldSend =
            hasSeenSpeechThisUnmute
            && (now - lastSpeechTime) <= Self.sendHangover
        guard shouldSend else { return }

        guard let targetPCMFormat,
              let converter = audioConverter
        else { return }

        let ratio = targetPCMFormat.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetPCMFormat, frameCapacity: outCapacity) else {
            return
        }

        var error: NSError?
        var consumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
        guard error == nil, outBuffer.frameLength > 0 else { return }
        guard let pcmData = Self.pcm16Data(from: outBuffer) else { return }

        hasBufferedAudioSinceCommit = true
        appendedAudioSeconds += Double(outBuffer.frameLength) / targetPCMFormat.sampleRate
        sendInputAudioAppend(base64PCM: pcmData.base64EncodedString())
        emitAppendedAudio(force: false)

        if let cap = maxAppendedSeconds, appendedAudioSeconds >= cap {
            exhaustAppendedBudget()
        }
    }

    private func exhaustAppendedBudget() {
        guard !didExhaustBudget else { return }
        didExhaustBudget = true
        silenceCommitWorkItem?.cancel()
        silenceCommitWorkItem = nil
        commitInputAudioBufferIfNeeded()
        emitAppendedAudio(force: true)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.setMicMuted(true)
            self.onAppendedBudgetExhausted?()
        }
    }

    private func updateSpeechActivity(level: Float) {
        let now = CFAbsoluteTimeGetCurrent()
        if level >= Self.speechRMSThreshold {
            isSpeechActive = true
            hasSeenSpeechThisUnmute = true
            lastSpeechTime = now
            silenceCommitWorkItem?.cancel()
            silenceCommitWorkItem = nil
            notifySpeechActivityIfNeeded(at: now)
            return
        }

        guard isSpeechActive, hasBufferedAudioSinceCommit else { return }
        guard silenceCommitWorkItem == nil else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.silenceCommitWorkItem = nil
            guard self.isRunning, self.isSessionReady, !self.isMicMuted else { return }
            let quietFor = CFAbsoluteTimeGetCurrent() - self.lastSpeechTime
            guard quietFor >= Self.silenceCommitDelay else { return }
            self.commitInputAudioBufferIfNeeded()
        }
        silenceCommitWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.silenceCommitDelay, execute: work)
    }

    private func notifySpeechActivityIfNeeded(at now: CFAbsoluteTime) {
        guard now - lastSpeechActivityNotify >= Self.speechActivityNotifyInterval else { return }
        lastSpeechActivityNotify = now
        DispatchQueue.main.async { [weak self] in
            self?.onSpeechActivity?()
        }
    }

    // MARK: - Helpers

    private func emitUpdate(isFinal: Bool) {
        let heard = committedTranscript + liveDeltaTranscript
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(heard, isFinal)
        }
    }

    private func fail(_ error: Error) {
        let callbacks = (onError, onFinish)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let wasRunning = self.isRunning
            self.stop()
            if wasRunning {
                callbacks.0?(error)
                callbacks.1?()
                self.onSessionFailed?()
            }
        }
    }

    private static func shouldIgnoreError(_ json: [String: Any]) -> Bool {
        let code: String = {
            if let error = json["error"] as? [String: Any],
               let c = error["code"] as? String {
                return c.lowercased()
            }
            return ""
        }()
        let message = (errorMessage(from: json) ?? "").lowercased()
        if code.contains("input_audio_buffer_commit_empty") { return true }
        if message.contains("buffer is empty") { return true }
        if message.contains("commit_empty") { return true }
        if message.contains("input_audio_buffer.clear") { return true }
        return false
    }

    private static func errorMessage(from json: [String: Any]) -> String? {
        if let error = json["error"] as? [String: Any] {
            if let message = error["message"] as? String { return message }
        }
        return json["message"] as? String
    }

    private static func rmsInputLevel(from buffer: AVAudioPCMBuffer) -> Float {
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return 0 }

        var sum: Float = 0
        var sampleCount = 0

        if let channels = buffer.floatChannelData {
            for ch in 0..<channelCount {
                let channel = channels[ch]
                for i in 0..<frameLength {
                    let sample = channel[i]
                    sum += sample * sample
                    sampleCount += 1
                }
            }
        } else if let channels = buffer.int16ChannelData {
            let scale: Float = 1.0 / 32_768.0
            for ch in 0..<channelCount {
                let channel = channels[ch]
                for i in 0..<frameLength {
                    let sample = Float(channel[i]) * scale
                    sum += sample * sample
                    sampleCount += 1
                }
            }
        }

        guard sampleCount > 0 else { return 0 }
        return min(1, sqrt(sum / Float(sampleCount)) * 4)
    }

    private static func pcm16Data(from buffer: AVAudioPCMBuffer) -> Data? {
        guard buffer.format.commonFormat == .pcmFormatInt16,
              let channel = buffer.int16ChannelData
        else { return nil }
        let frameLength = Int(buffer.frameLength)
        let byteCount = frameLength * MemoryLayout<Int16>.size
        return Data(bytes: channel[0], count: byteCount)
    }
}
