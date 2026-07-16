//
//  RealtimeService.swift
//  shizen
//
//  WebSocket client for OpenAI Realtime (gpt-realtime-2) with mic capture and PCM playback.
//

import AVFoundation
import Foundation

enum RealtimeConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

/// Who should be speaking in the conversation right now.
enum RealtimeConversationTurn: Equatable {
    case connecting
    case yourTurn
    case tutorTurn
    case paused
    case stopped
}

protocol RealtimeServiceDelegate: AnyObject {
    func realtimeService(_ service: RealtimeService, didChangeConnectionState state: RealtimeConnectionState)
    func realtimeService(_ service: RealtimeService, didChangeTurn turn: RealtimeConversationTurn)
    func realtimeService(_ service: RealtimeService, didReceiveUserTranscriptDelta delta: String)
    func realtimeService(
        _ service: RealtimeService,
        didReceiveUserTranscript text: String,
        audioClip: RealtimeAudioClip?
    )
    func realtimeService(_ service: RealtimeService, didReceiveAssistantTranscriptDelta delta: String)
    func realtimeService(
        _ service: RealtimeService,
        didCompleteAssistantTranscript text: String,
        sentenceClips: [(sentence: String, clip: RealtimeAudioClip)]
    )
    func realtimeService(_ service: RealtimeService, didUpdateUsage usage: RealtimeTokenUsage)
    func realtimeService(_ service: RealtimeService, didEncounterError error: Error)
    func realtimeServiceDidDetectSpeechStarted(_ service: RealtimeService)
    /// RMS level in [0, 1] from the microphone while the session is active.
    func realtimeService(_ service: RealtimeService, didUpdateInputLevel level: Float)
    /// RMS level in [0, 1] from assistant audio playback.
    func realtimeService(_ service: RealtimeService, didUpdateOutputLevel level: Float)
    func realtimeService(_ service: RealtimeService, didChangeMicMuted isMuted: Bool)
}

final class RealtimeService: NSObject {

    static let sampleRate: Double = 24_000

    weak var delegate: RealtimeServiceDelegate?

    private(set) var connectionState: RealtimeConnectionState = .disconnected {
        didSet {
            guard oldValue != connectionState else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.realtimeService(self, didChangeConnectionState: self.connectionState)
            }
        }
    }

    private(set) var cumulativeUsage = RealtimeTokenUsage()

    private(set) var isSessionPaused = false
    private(set) var isMicMuted = false

    private(set) var conversationTurn: RealtimeConversationTurn = .connecting {
        didSet {
            guard oldValue != conversationTurn else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.realtimeService(self, didChangeTurn: self.conversationTurn)
            }
        }
    }

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var receiveLoopActive = false

    /// Single engine so iOS voice-processing / AEC can correlate playback with capture.
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    private var targetPCMFormat: AVAudioFormat!
    private var audioConverter: AVAudioConverter?

    private var assistantTranscriptBuffer = ""
    /// Transcript text held until `response.done` so all output audio deltas are recorded first.
    private var pendingAssistantTranscript: String?
    /// Set on `response.done`; transcript delivery waits for both this and pendingAssistantTranscript.
    private var isAssistantResponseFinished = false
    private var isCapturingMic = false
    private var outputMeterTapInstalled = false

    /// Drop mic chunks while assistant audio is playing (prevents speaker→mic feedback loop).
    private let playbackGateLock = NSLock()
    private var scheduledPlaybackBuffers = 0
    private var suppressMicWhileAssistantSpeaks = false

    private let sendQueue = DispatchQueue(label: "RealtimeService.send")
    private let conversationRecorder = RealtimeConversationRecorder()

    // MARK: - Lifecycle

    func connect() {
        switch connectionState {
        case .disconnected:
            break
        case .failed:
            break
        default:
            return
        }

        connectionState = .connecting
        conversationTurn = .connecting
        isMicMuted = false
        cumulativeUsage = RealtimeTokenUsage()
        assistantTranscriptBuffer = ""
        pendingAssistantTranscript = nil
        isAssistantResponseFinished = false
        conversationRecorder.reset()

        guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-realtime-2") else {
            connectionState = .failed("Invalid WebSocket URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(OpenAIAppKey.resolved)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
        urlSession = session
        let task = session.webSocketTask(with: request)
        webSocket = task
        receiveLoopActive = true
        task.resume()
        startReceiveLoop()
    }

    func disconnect() {
        receiveLoopActive = false
        isSessionPaused = false
        isMicMuted = false
        stopMicCapture()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        connectionState = .disconnected
        pendingAssistantTranscript = nil
        isAssistantResponseFinished = false
        conversationRecorder.reset()
        setTurn(.stopped)
    }

    /// Replays a recorded clip through the tutor engine (avoids a second AVAudioEngine while connected).
    func replayRecordedClip(_ clip: RealtimeAudioClip) {
        guard !clip.pcmData.isEmpty else { return }
        schedulePassivePlaybackPCM(clip.pcmData)
    }

    func pauseSession() {
        guard connectionState == .connected, !isSessionPaused else { return }
        isSessionPaused = true
        stopPlaybackImmediately()
        clearPlaybackGate()
        playbackGateLock.lock()
        let shouldCancelResponse = scheduledPlaybackBuffers > 0 || conversationTurn == .tutorTurn
        playbackGateLock.unlock()
        if shouldCancelResponse {
            sendJSON(["type": "response.cancel"])
        }
        stopMicCapture()
        setTurn(.paused)
    }

    func resumeSession() {
        guard connectionState == .connected, isSessionPaused else { return }
        isSessionPaused = false
        setTurn(.yourTurn)
        startMicCapture()
    }

    func setMicMuted(_ muted: Bool) {
        guard isMicMuted != muted else { return }
        isMicMuted = muted
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.realtimeService(self, didChangeMicMuted: muted)
        }
    }

    private func setTurn(_ turn: RealtimeConversationTurn) {
        conversationTurn = turn
    }

    // MARK: - WebSocket receive

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
                self.connectionState = .failed(error.localizedDescription)
                DispatchQueue.main.async {
                    self.delegate?.realtimeService(self, didEncounterError: error)
                }
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
            if connectionState == .connecting {
                sendSessionUpdate()
            }

        case "session.updated":
            if connectionState == .connecting {
                connectionState = .connected
                isSessionPaused = false
                setTurn(.yourTurn)
                startMicCapture()
            }

        case "conversation.item.input_audio_transcription.delta":
            if let delta = json["delta"] as? String, !delta.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.realtimeService(self, didReceiveUserTranscriptDelta: delta)
                }
            }

        case "conversation.item.input_audio_transcription.completed":
            if let transcript = json["transcript"] as? String, !transcript.isEmpty {
                let clip = conversationRecorder.finalizeUserUtterance()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.realtimeService(self, didReceiveUserTranscript: transcript, audioClip: clip)
                }
            }
            if let usage = json["usage"] as? [String: Any] {
                accumulateTranscriptionUsage(usage)
            }

        case "conversation.item.input_audio_transcription.failed":
            let message = Self.errorMessage(from: json) ?? "Input transcription failed"
            reportFailure(message)

        case "response.output_audio_transcript.delta", "response.audio_transcript.delta":
            setTurn(.tutorTurn)
            if let delta = json["delta"] as? String {
                assistantTranscriptBuffer += delta
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.realtimeService(self, didReceiveAssistantTranscriptDelta: delta)
                }
            }

        case "response.output_audio_transcript.done", "response.audio_transcript.done":
            let transcript = (json["transcript"] as? String) ?? assistantTranscriptBuffer
            assistantTranscriptBuffer = ""
            if !transcript.isEmpty {
                pendingAssistantTranscript = transcript
            }
            deliverPendingAssistantTranscriptIfNeeded()

        case "response.output_audio.delta", "response.audio.delta":
            if let deltaB64 = json["delta"] as? String,
               let pcmData = Data(base64Encoded: deltaB64)
            {
                conversationRecorder.ensureAssistantCaptureStarted()
                conversationRecorder.appendAssistantPCM(pcmData)
                schedulePlaybackPCM(pcmData)
            }

        case "response.done":
            if let response = json["response"] as? [String: Any],
               let usage = response["usage"] as? [String: Any]
            {
                cumulativeUsage.accumulate(from: usage)
                let snapshot = cumulativeUsage
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.realtimeService(self, didUpdateUsage: snapshot)
                }
            }
            isAssistantResponseFinished = true
            deliverPendingAssistantTranscriptIfNeeded()
            assistantTranscriptBuffer = ""
            // Mic unblocks when scheduled playback buffers finish (see playbackBufferCompleted).

        case "input_audio_buffer.speech_started":
            conversationRecorder.userSpeechStarted()
            stopPlaybackImmediately()
            clearPlaybackGate()
            setTurn(.yourTurn)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.realtimeServiceDidDetectSpeechStarted(self)
            }

        case "response.created":
            isAssistantResponseFinished = false
            pendingAssistantTranscript = nil
            // Audio deltas may arrive before response.created; do not wipe an early buffer.
            conversationRecorder.ensureAssistantCaptureStarted()
            setTurn(.tutorTurn)

        case "response.cancelled":
            conversationRecorder.cancelAssistantCapture()
            pendingAssistantTranscript = nil
            isAssistantResponseFinished = false
            stopPlaybackImmediately()
            clearPlaybackGate()
            assistantTranscriptBuffer = ""

        case "error":
            if shouldSilentlyIgnoreServerError(json) {
                return
            }
            let message = Self.errorMessage(from: json) ?? "Realtime API error"
            reportFailure(message)

        default:
            break
        }
    }

    private func shouldSilentlyIgnoreServerError(_ json: [String: Any]) -> Bool {
        if isSessionPaused { return true }

        let code: String = {
            if let error = json["error"] as? [String: Any],
               let c = error["code"] as? String {
                return c.lowercased()
            }
            return ""
        }()
        let message = (Self.errorMessage(from: json) ?? "").lowercased()

        if code.contains("cancel") { return true }
        if code.contains("active_response") { return true }
        if message.contains("no active response") { return true }
        if message.contains("response_cancel") { return true }
        if message.contains("already cancelled") { return true }
        return false
    }

    private func reportFailure(_ message: String) {
        connectionState = .failed(message)
        stopMicCapture()
        let err = NSError(
            domain: "RealtimeService",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.realtimeService(self, didEncounterError: err)
        }
    }

    private static func errorMessage(from json: [String: Any]) -> String? {
        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty
        {
            if let code = error["code"] as? String {
                return "\(message) (\(code))"
            }
            return message
        }
        if let error = json["error"] as? String, !error.isEmpty {
            return error
        }
        return nil
    }

    private func accumulateTranscriptionUsage(_ usage: [String: Any]) {
        // Input transcription uses a separate model; map into our aggregate counters.
        var mapped: [String: Any] = [:]
        if let total = usage["total_tokens"] as? Int {
            mapped["input_tokens"] = total
        }
        if let input = usage["input_tokens"] as? Int {
            mapped["input_tokens"] = input
        }
        if let output = usage["output_tokens"] as? Int {
            mapped["output_tokens"] = output
        }
        if let details = usage["input_token_details"] as? [String: Any] {
            mapped["input_token_details"] = details
        }
        cumulativeUsage.accumulate(from: mapped)
        let snapshot = cumulativeUsage
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.realtimeService(self, didUpdateUsage: snapshot)
        }
    }

    // MARK: - Client events

    private func sendSessionUpdate() {
        let payload: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "realtime",
                "output_modalities": ["audio"],
                "instructions": RealtimeTutorPrompt.sessionInstructions,
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": Int(Self.sampleRate),
                        ],
                        "turn_detection": [
                            "type": "semantic_vad",
                        ],
                        "transcription": [
                            "model": "gpt-realtime-whisper",
                            "language": "ja",
                        ],
                    ],
                    "output": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": Int(Self.sampleRate),
                        ],
                        "voice": "marin",
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
            self?.webSocket?.send(.string(text)) { error in
                if let error {
                    DispatchQueue.main.async {
                        guard let self, !self.isSessionPaused else { return }
                        self.delegate?.realtimeService(self, didEncounterError: error)
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

    // MARK: - Audio session

    private func configurePlayAndRecordSession() throws {
        let session = AVAudioSession.sharedInstance()
        // voiceChat enables built-in echo cancellation for simultaneous play + record.
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setActive(true, options: [])
        // Hints only — hardware may reject unsupported rates/buffer sizes (`SessionCore` '!pri').
        try? session.setPreferredSampleRate(Self.sampleRate)
        try? session.setPreferredIOBufferDuration(0.02)
    }

    // MARK: - Audio engine (capture + playback)

    private func startMicCapture() {
        guard !isCapturingMic else { return }
        do {
            try configurePlayAndRecordSession()
            try setupAudioEngine()
            isCapturingMic = true
        } catch {
            connectionState = .failed(error.localizedDescription)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.realtimeService(self, didEncounterError: error)
            }
        }
    }

    private func stopMicCapture() {
        guard isCapturingMic else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        removeOutputLevelTap()
        stopPlaybackImmediately()
        clearPlaybackGate()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        isCapturingMic = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func setupAudioEngine() throws {
        targetPCMFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: true
        )

        let playbackFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        )!

        if !audioEngine.attachedNodes.contains(playerNode) {
            audioEngine.attach(playerNode)
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playbackFormat)
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        audioConverter = AVAudioConverter(from: inputFormat, to: targetPCMFormat)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            self?.processMicBuffer(buffer)
        }

        installOutputLevelTap()

        audioEngine.prepare()
        if !audioEngine.isRunning {
            try audioEngine.start()
        }
    }

    private func shouldTransmitMic() -> Bool {
        guard !isMicMuted else { return false }
        playbackGateLock.lock()
        let allow = !suppressMicWhileAssistantSpeaks
        playbackGateLock.unlock()
        return allow
    }

    private func beginAssistantPlayback() {
        playbackGateLock.lock()
        suppressMicWhileAssistantSpeaks = true
        playbackGateLock.unlock()
        setTurn(.tutorTurn)
    }

    private func clearPlaybackGate() {
        playbackGateLock.lock()
        scheduledPlaybackBuffers = 0
        suppressMicWhileAssistantSpeaks = false
        playbackGateLock.unlock()
        if connectionState == .connected {
            setTurn(.yourTurn)
        }
    }

    private func playbackBufferCompleted() {
        playbackGateLock.lock()
        scheduledPlaybackBuffers = max(0, scheduledPlaybackBuffers - 1)
        let shouldOpenMic = scheduledPlaybackBuffers == 0
        if shouldOpenMic {
            suppressMicWhileAssistantSpeaks = false
        }
        playbackGateLock.unlock()
        if shouldOpenMic, connectionState == .connected {
            setTurn(.yourTurn)
        }
    }

    private func installOutputLevelTap() {
        guard !outputMeterTapInstalled else { return }
        let mixer = audioEngine.mainMixerNode
        let format = mixer.outputFormat(forBus: 0)
        mixer.removeTap(onBus: 0)
        mixer.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            guard let self, !self.isSessionPaused, self.connectionState == .connected else { return }
            self.playbackGateLock.lock()
            let isPlaying = self.playerNode.isPlaying || self.scheduledPlaybackBuffers > 0
            self.playbackGateLock.unlock()
            guard isPlaying else { return }
            let level = Self.rmsLevel(from: buffer)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.realtimeService(self, didUpdateOutputLevel: level)
            }
        }
        outputMeterTapInstalled = true
    }

    private func removeOutputLevelTap() {
        guard outputMeterTapInstalled else { return }
        audioEngine.mainMixerNode.removeTap(onBus: 0)
        outputMeterTapInstalled = false
    }

    private func processMicBuffer(_ buffer: AVAudioPCMBuffer) {
        guard !isSessionPaused, connectionState == .connected else { return }

        let level = Self.rmsInputLevel(from: buffer)
        if !isMicMuted {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.realtimeService(self, didUpdateInputLevel: level)
            }
        }

        guard shouldTransmitMic(),
              let targetPCMFormat,
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

        guard let pcmData = pcm16Data(from: outBuffer) else { return }
        conversationRecorder.appendUserPCM(pcmData)
        let b64 = pcmData.base64EncodedString()
        sendInputAudioAppend(base64PCM: b64)
    }

    private static func rmsLevel(from buffer: AVAudioPCMBuffer) -> Float {
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return 0 }

        var sum: Float = 0
        var sampleCount = 0

        if let channels = buffer.floatChannelData {
            for ch in 0..<channelCount {
                let channel = channels[ch]
                for i in 0..<frameLength {
                    let s = channel[i]
                    sum += s * s
                    sampleCount += 1
                }
            }
        } else if let channels = buffer.int16ChannelData {
            let scale: Float = 1.0 / 32_768.0
            for ch in 0..<channelCount {
                let channel = channels[ch]
                for i in 0..<frameLength {
                    let s = Float(channel[i]) * scale
                    sum += s * s
                    sampleCount += 1
                }
            }
        } else {
            return 0
        }

        guard sampleCount > 0 else { return 0 }
        let rms = sqrtf(sum / Float(sampleCount))
        // Map typical speech RMS into a visible 0…1 range for the live meter.
        return min(1, rms * 6)
    }

    /// Higher gain for mic capture — voiceChat AEC keeps raw tap levels very quiet.
    private static func rmsInputLevel(from buffer: AVAudioPCMBuffer) -> Float {
        min(1, rmsLevel(from: buffer) * 18)
    }

    private func pcm16Data(from buffer: AVAudioPCMBuffer) -> Data? {
        guard buffer.format.commonFormat == .pcmFormatInt16,
              let channel = buffer.int16ChannelData
        else { return nil }
        let frameLength = Int(buffer.frameLength)
        let byteCount = frameLength * MemoryLayout<Int16>.size
        return Data(bytes: channel[0], count: byteCount)
    }

    // MARK: - Playback

    private func stopPlaybackImmediately() {
        playerNode.stop()
        playerNode.reset()
    }

    private func deliverPendingAssistantTranscriptIfNeeded() {
        guard isAssistantResponseFinished else { return }
        let transcript = pendingAssistantTranscript?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !transcript.isEmpty else { return }

        pendingAssistantTranscript = nil
        isAssistantResponseFinished = false

        let sentenceClips = conversationRecorder.finalizeAssistantUtterance(transcript: transcript)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.realtimeService(
                self,
                didCompleteAssistantTranscript: transcript,
                sentenceClips: sentenceClips
            )
        }
    }

    private func makePlaybackBuffer(from data: Data) -> AVAudioPCMBuffer? {
        var chunk = data
        if chunk.count % 2 == 1 {
            chunk = chunk.dropLast()
        }
        guard !chunk.isEmpty else { return nil }

        let sampleCount = chunk.count / 2
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        )!
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(sampleCount)
        ) else { return nil }

        buffer.frameLength = AVAudioFrameCount(sampleCount)
        guard let channel = buffer.floatChannelData?[0] else { return nil }

        chunk.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            let scale: Float = 1.0 / 32_768.0
            for i in 0..<sampleCount {
                channel[i] = Float(base[i]) * scale
            }
        }
        return buffer
    }

    private func schedulePlaybackPCM(_ data: Data) {
        guard let buffer = makePlaybackBuffer(from: data) else { return }

        beginAssistantPlayback()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.playbackGateLock.lock()
            self.scheduledPlaybackBuffers += 1
            self.playbackGateLock.unlock()

            if !self.audioEngine.isRunning {
                try? self.audioEngine.start()
            }

            self.playerNode.scheduleBuffer(buffer) { [weak self] in
                self?.playbackBufferCompleted()
            }
            if !self.playerNode.isPlaying {
                self.playerNode.play()
            }
        }
    }

    private func schedulePassivePlaybackPCM(_ data: Data) {
        guard let buffer = makePlaybackBuffer(from: data) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.audioEngine.isRunning {
                try? self.audioEngine.start()
            }

            self.playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts) { }
            if !self.playerNode.isPlaying {
                self.playerNode.play()
            }
        }
    }
}
