//
//  TextToSpeechService.swift
//  shizen
//
//  Single OpenAI TTS request so prosody is preserved as one coherent utterance.
//  The streamed PCM is assembled into `assembledSamples`, played live as it arrives,
//  and — once the response finishes — segmented into per-sentence regions using a
//  local voice-activity detector (RMS + minimum-silence gating). Each row in the UI
//  therefore points at a contiguous sample slice of the *same* audio the user heard,
//  so replaying a row sounds identical to replaying the matching portion of the
//  full utterance (no seams, no retuning).
//
//  PCM format: 24 kHz, 16-bit signed, little-endian, mono (OpenAI `response_format=pcm`).
//

import AVFoundation
import Foundation
import NaturalLanguage

public enum OpenAITTSVoice: String, CaseIterable {
    case alloy, ash, ballad, coral, echo, fable, nova, onyx, sage, shimmer, verse, marin, cedar
}

public enum TextToSpeechError: Error, LocalizedError {
    case missingAPIKey(provider: TTSProvider)
    case invalidResponse(provider: TTSProvider, status: Int, body: String?)
    case audioEngineFailed(underlying: Error)
    case noSentencesParsed
    case noVoiceSelected

    public var errorDescription: String? {
        switch self {
        case let .missingAPIKey(provider):
            return "Missing \(provider.displayName) API key."
        case let .invalidResponse(provider, status, body):
            if let body, !body.isEmpty {
                return "\(provider.displayName) request failed (HTTP \(status)): \(body)"
            }
            return "\(provider.displayName) request failed (HTTP \(status))."
        case let .audioEngineFailed(underlying):
            return "Audio engine failed: \(underlying.localizedDescription)"
        case .noSentencesParsed:
            return "No sentences to synthesize."
        case .noVoiceSelected:
            return "Select an ElevenLabs voice."
        }
    }
}

/// One sentence-aligned row. `sampleRange` is a half-open slice into
/// `TextToSpeechService.assembledSamples` and is empty until alignment completes.
public struct SpeechSentence {
    public enum LoadState {
        case pending
        case streaming
        case ready
        case failed(String)
    }

    public let index: Int
    public let text: String
    public var state: LoadState
    public var sampleRange: Range<Int>
    public var peaks: [Float]
    public var sampleRate: Double

    public var sampleCount: Int { sampleRange.count }
    public var duration: TimeInterval { Double(sampleCount) / sampleRate }
}

public enum TTSPlaybackState {
    case idle
    case streaming
    case readyForReplay
    case playing
    case paused
}

/// UI surface. All callbacks fire on the main thread.
public protocol TextToSpeechServiceDelegate: AnyObject {
    func textToSpeechService(_ service: TextToSpeechService, didStartStreamingFor text: String)
    func textToSpeechService(_ service: TextToSpeechService, didUpdateSentenceAt index: Int)
    func textToSpeechService(_ service: TextToSpeechService, didChangeState state: TTSPlaybackState)
    func textToSpeechService(_ service: TextToSpeechService, didUpdateLevel level: Float)
    func textToSpeechService(_ service: TextToSpeechService, didFailWith error: Error)
    func textToSpeechServiceDidFinish(_ service: TextToSpeechService)
    /// Fires on every level-meter tick while `play(sentenceAt:)` or `replayAll()` audio is flowing.
    /// `sampleOffset` is the index into `assembledSamples` of the sample currently hitting the speaker.
    /// When playing a single sentence slice the offset lies within that sentence's `sampleRange`.
    func textToSpeechService(_ service: TextToSpeechService, didAdvancePlaybackTo sampleOffset: Int)
    func textToSpeechServiceDidRestoreSavedUtterance(_ service: TextToSpeechService)
}

public extension TextToSpeechServiceDelegate {
    func textToSpeechService(_ service: TextToSpeechService, didStartStreamingFor text: String) {}
    func textToSpeechService(_ service: TextToSpeechService, didUpdateSentenceAt index: Int) {}
    func textToSpeechService(_ service: TextToSpeechService, didChangeState state: TTSPlaybackState) {}
    func textToSpeechService(_ service: TextToSpeechService, didUpdateLevel level: Float) {}
    func textToSpeechService(_ service: TextToSpeechService, didFailWith error: Error) {}
    func textToSpeechServiceDidFinish(_ service: TextToSpeechService) {}
    func textToSpeechService(_ service: TextToSpeechService, didAdvancePlaybackTo sampleOffset: Int) {}
    func textToSpeechServiceDidRestoreSavedUtterance(_ service: TextToSpeechService) {}
}

public final class TextToSpeechService: NSObject {

    public static let sampleRate: Double = 24_000
    private static let channelCount: AVAudioChannelCount = 1
    private static let peakBucketCount = 40

    public weak var delegate: TextToSpeechServiceDelegate?

    private let credentials: TTSCredentials
    private var urlSession: URLSession!

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let pcmFormat: AVAudioFormat

    // Streaming request state (mutated on the delegate queue).
    private let delegateQueue: OperationQueue
    private var currentTask: URLSessionDataTask?
    private var conversationGenerationTask: Task<Void, Never>?
    private var errorBody = Data()
    private var leftoverByte: UInt8?
    private var hasStartedLivePlayback = false
    private var didFinishRequest = false
    private var onFinish: (@Sendable (Error?) -> Void)?

    // Incremental VAD state (main-thread only). Conservative thresholds scan newly-arrived
    // samples as they land so we can mark early sentence rows `.ready` before the HTTP
    // response ends. The final pass in `alignSentencesToAssembledAudio()` re-runs with
    // adaptive thresholds and may revise any rows this path committed.
    private var incSamplesScannedCount = 0
    private var incInSpeech = false
    private var incRegionStart = 0
    private var incSilenceRun = 0
    /// Closed speech regions discovered by the incremental scan.
    private var incCommittedRegions: [Range<Int>] = []
    /// Highest sentence index we've already transitioned to `.ready` via the incremental path.
    private var incHighestFinalizedIndex: Int = -1

    /// 20 ms windows at 24 kHz.
    private static var incWindowSamples: Int { max(1, Int(sampleRate * 0.020)) }
    /// Mid-stream minimum silence to declare a boundary. Matches the full-stream VAD.
    private static var incMinSilenceSamples: Int { max(1, Int(sampleRate * 0.180)) }
    /// Drop speech regions shorter than this (blip filter).
    private static var incMinSpeechSamples: Int { max(1, Int(sampleRate * 0.060)) }
    /// Fixed thresholds for incremental scan. We can't compute adaptive ones without the whole
    /// distribution, and it's fine to err on the side of "committing fewer boundaries" — the
    /// final pass will catch anything we miss.
    private static let incEnterThreshold: Float = 0.040
    private static let incExitThreshold: Float = 0.020

    private var activeSynthesisProvider: TTSProvider = .openAI

    /// Main-thread-only: the one long buffer of Float samples for this utterance.
    public private(set) var assembledSamples: [Float] = []

    /// Anchor that lets us convert `playerNode.playerTime` into an absolute sample offset
    /// inside `assembledSamples`. Set when we call `playerNode.play()`.
    private var playbackAnchorSample: AVAudioFramePosition = 0
    /// Absolute sample offset inside `assembledSamples` where the currently-scheduled slice begins.
    /// For `replayAll()` this is 0; for `play(sentenceAt:)` this is the sentence's `sampleRange.lowerBound`;
    /// for live streaming this is 0 (we accumulate from the start).
    private var playbackSliceStartInAssembled: Int = 0
    /// Half-open end of the active playback slice in `assembledSamples`.
    private var playbackSliceEndExclusive: Int = 0
    /// Latest estimated playhead in `assembledSamples` (-1 if unknown).
    private var lastReportedPlaybackSample: Int = -1
    /// Throttles level/playhead delegate callbacks so UI observers (e.g. a shared
    /// ObservableObject backing an entire window) don't re-publish at the raw
    /// ~43Hz tap-buffer rate, which forces SwiftUI to re-diff unrelated view trees
    /// (sidebars, lists) on every audio buffer instead of at a UI-visible cadence.
    private var lastLevelTapForwardTime: DispatchTime = .now()

    /// Main-thread-only: sentence rows for the current utterance. Populated with text + `.streaming`
    /// before the request starts, finalized with `sampleRange`/`peaks` after VAD alignment.
    public private(set) var sentences: [SpeechSentence] = []

    /// Trimmed text from the last `speak` call.
    public private(set) var utteranceSourceText: String = ""

    /// Provider used for the last successful `speak` (or restored snapshot).
    public private(set) var lastSynthesisProvider: TTSProvider = .openAI

    /// Voice identifier from the last successful `speak` (OpenAI voice name or ElevenLabs voice ID).
    public private(set) var lastSynthesisVoiceString: String = OpenAITTSVoice.coral.rawValue

    /// OpenAI voice when the last synthesis used OpenAI; otherwise `.coral`.
    public var lastSynthesisVoice: OpenAITTSVoice {
        OpenAITTSVoice(rawValue: lastSynthesisVoiceString) ?? .coral
    }

    public var totalDuration: TimeInterval {
        Double(assembledSamples.count) / Self.sampleRate
    }

    /// True when the full utterance is aligned and can be written to disk for offline replay.
    public var canExportSavedSnapshot: Bool {
        !assembledSamples.isEmpty
            && !sentences.isEmpty
            && sentences.allSatisfy {
                if case .ready = $0.state { return true }
                return false
            }
    }

    /// Which sentence row contains `sampleOffset`, preferring the row whose `sampleRange`
    /// covers it. Returns nil if no sentence row is `.ready` yet or the offset is out of range.
    public func sentenceIndex(forSampleOffset sampleOffset: Int) -> Int? {
        guard !sentences.isEmpty else { return nil }
        for s in sentences where !s.sampleRange.isEmpty {
            if sampleOffset >= s.sampleRange.lowerBound, sampleOffset < s.sampleRange.upperBound {
                return s.index
            }
        }
        if let last = sentences.last(where: { !$0.sampleRange.isEmpty }),
           sampleOffset >= last.sampleRange.upperBound {
            return last.index
        }
        return nil
    }

    private var assembledBuffer: AVAudioPCMBuffer?

    public private(set) var state: TTSPlaybackState = .idle {
        didSet {
            guard state != oldValue else { return }
            let newState = state
            let emit: () -> Void = { [weak self] in
                guard let self else { return }
                self.delegate?.textToSpeechService(self, didChangeState: newState)
            }
            if Thread.isMainThread { emit() } else { DispatchQueue.main.async(execute: emit) }
        }
    }

    public init(apiKey: String) {
        self.credentials = TTSCredentials(openAIKey: apiKey)
        self.delegateQueue = Self.makeDelegateQueue()
        self.pcmFormat = Self.makePCMFormat()
        super.init()
        configureAfterInit()
    }

    public init(credentials: TTSCredentials) {
        self.credentials = credentials
        self.delegateQueue = Self.makeDelegateQueue()
        self.pcmFormat = Self.makePCMFormat()
        super.init()
        configureAfterInit()
    }

    private static func makeDelegateQueue() -> OperationQueue {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "TextToSpeechService.delegateQueue"
        return queue
    }

    private static func makePCMFormat() -> AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        )!
    }

    private func configureAfterInit() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 30

        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)

        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: pcmFormat)
        installLevelMeterTap()
    }

    deinit {
        currentTask?.cancel()
        urlSession?.invalidateAndCancel()
        audioEngine.stop()
    }

    // MARK: - Public API

    public var isSpeaking: Bool {
        switch state {
        case .streaming, .playing: return true
        case .idle, .readyForReplay, .paused: return false
        }
    }

    /// Kick off a new utterance. Cancels any in-flight request. Splits the text into
    /// sentences immediately (so rows appear right away in a `.streaming` state), then
    /// fires ONE TTS request for the whole passage. On completion, a local VAD aligns
    /// each sentence to a sample slice of the assembled audio.
    public func speak(
        text: String,
        provider: TTSProvider = .openAI,
        voice: OpenAITTSVoice = .coral,
        elevenLabsVoiceID: String? = nil,
        instructions: String? = nil,
        model: String? = nil,
        completion: (@Sendable (Error?) -> Void)? = nil
    ) {
        stop()

        let apiKey = credentials.key(for: provider)
        guard !apiKey.isEmpty else {
            DispatchQueue.main.async { completion?(TextToSpeechError.missingAPIKey(provider: provider)) }
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = Self.splitIntoSentences(trimmed)
        guard !segments.isEmpty else {
            DispatchQueue.main.async { completion?(TextToSpeechError.noSentencesParsed) }
            return
        }

        activeSynthesisProvider = provider
        lastSynthesisProvider = provider

        switch provider {
        case .openAI:
            lastSynthesisVoiceString = voice.rawValue
        case .elevenLabs:
            guard let elevenLabsVoiceID, !elevenLabsVoiceID.isEmpty else {
                DispatchQueue.main.async { completion?(TextToSpeechError.noVoiceSelected) }
                return
            }
            lastSynthesisVoiceString = elevenLabsVoiceID
        case .gemini:
            DispatchQueue.main.async { completion?(GeminiTTSError.noDialogueLines) }
            return
        }

        didFinishRequest = false
        hasStartedLivePlayback = false
        leftoverByte = nil
        errorBody.removeAll()
        onFinish = completion

        assembledSamples.removeAll()
        assembledBuffer = nil
        utteranceSourceText = trimmed

        incSamplesScannedCount = 0
        incInSpeech = false
        incRegionStart = 0
        incSilenceRun = 0
        incCommittedRegions.removeAll()
        incHighestFinalizedIndex = -1

        sentences = segments.enumerated().map { i, t in
            SpeechSentence(
                index: i,
                text: t,
                state: .streaming,
                sampleRange: 0..<0,
                peaks: [],
                sampleRate: Self.sampleRate
            )
        }

        state = .idle

        do {
            try configureAudioSessionForPlayback()
            try startEngineIfNeeded()
        } catch {
            let wrapped = TextToSpeechError.audioEngineFailed(underlying: error)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.textToSpeechService(self, didFailWith: wrapped)
            }
            finish(with: wrapped)
            return
        }

        let request: URLRequest
        do {
            request = try makeSynthesisRequest(
                provider: provider,
                apiKey: apiKey,
                trimmedText: trimmed,
                openAIVoice: voice,
                elevenLabsVoiceID: elevenLabsVoiceID,
                instructions: instructions,
                model: model
            )
        } catch {
            finish(with: error)
            return
        }

        let notifyStart: () -> Void = { [weak self] in
            guard let self else { return }
            self.delegate?.textToSpeechService(self, didStartStreamingFor: trimmed)
        }
        if Thread.isMainThread { notifyStart() } else { DispatchQueue.main.sync(execute: notifyStart) }

        state = .streaming

        let task = urlSession.dataTask(with: request)
        currentTask = task
        task.resume()
    }

    /// Synthesize a multi-speaker conversation with Gemini TTS. Each dialogue line becomes
    /// one sentence row; alignment uses the same VAD pass as single-speaker synthesis.
    public func speakConversation(
        lines: [ConversationDialogueLine],
        speaker1Voice: GeminiTTSVoice = .zephyr,
        speaker2Voice: GeminiTTSVoice = .puck,
        model: String? = nil,
        temperature: Double = 1,
        completion: (@Sendable (Error?) -> Void)? = nil
    ) {
        stop()

        let apiKey = credentials.key(for: .gemini)
        guard !apiKey.isEmpty else {
            DispatchQueue.main.async { completion?(TextToSpeechError.missingAPIKey(provider: .gemini)) }
            return
        }

        let trimmedLines = lines.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !trimmedLines.isEmpty else {
            DispatchQueue.main.async { completion?(GeminiTTSError.noDialogueLines) }
            return
        }

        activeSynthesisProvider = .gemini
        lastSynthesisProvider = .gemini
        lastSynthesisVoiceString = "\(speaker1Voice.rawValue)/\(speaker2Voice.rawValue)"

        didFinishRequest = false
        hasStartedLivePlayback = false
        leftoverByte = nil
        errorBody.removeAll()
        onFinish = completion

        assembledSamples.removeAll()
        assembledBuffer = nil
        utteranceSourceText = GeminiConversationTTSClient.buildTranscript(from: trimmedLines)

        incSamplesScannedCount = 0
        incInSpeech = false
        incRegionStart = 0
        incSilenceRun = 0
        incCommittedRegions.removeAll()
        incHighestFinalizedIndex = -1

        sentences = trimmedLines.enumerated().map { i, line in
            SpeechSentence(
                index: i,
                text: line.text.trimmingCharacters(in: .whitespacesAndNewlines),
                state: .streaming,
                sampleRange: 0..<0,
                peaks: [],
                sampleRate: Self.sampleRate
            )
        }

        state = .idle

        do {
            try configureAudioSessionForPlayback()
            try startEngineIfNeeded()
        } catch {
            let wrapped = TextToSpeechError.audioEngineFailed(underlying: error)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.textToSpeechService(self, didFailWith: wrapped)
            }
            finish(with: wrapped)
            return
        }

        let notifyStart: () -> Void = { [weak self] in
            guard let self else { return }
            self.delegate?.textToSpeechService(self, didStartStreamingFor: self.utteranceSourceText)
        }
        if Thread.isMainThread { notifyStart() } else { DispatchQueue.main.sync(execute: notifyStart) }

        state = .streaming

        let resolvedModel = model ?? GeminiConversationTTSClient.defaultModel
        conversationGenerationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let pcmData = try await GeminiConversationTTSClient.generatePCM(
                    apiKey: apiKey,
                    lines: trimmedLines,
                    speaker1Voice: speaker1Voice,
                    speaker2Voice: speaker2Voice,
                    model: resolvedModel,
                    temperature: temperature
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.conversationGenerationTask = nil
                    self.ingestCompletePCM(pcmData)
                    self.finish(with: nil)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.conversationGenerationTask = nil
                    self.finish(with: error)
                }
            }
        }
    }

    private func ingestCompletePCM(_ pcmData: Data) {
        var data = pcmData
        if data.count % 2 == 1 {
            data = data.dropLast()
        }
        guard !data.isEmpty else { return }

        let sampleCount = data.count / 2
        var samples = [Float](repeating: 0, count: sampleCount)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            let int16Ptr = base.assumingMemoryBound(to: Int16.self)
            let scale: Float = 1.0 / 32768.0
            for i in 0..<sampleCount {
                samples[i] = Float(int16Ptr[i]) * scale
            }
        }

        assembledSamples = samples
        assembledBuffer = nil
        runIncrementalScan()

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: pcmFormat,
            frameCapacity: AVAudioFrameCount(sampleCount)
        ) else { return }
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        if let channel = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { src in
                guard let base = src.baseAddress else { return }
                channel.update(from: base, count: sampleCount)
            }
        }

        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        if !hasStartedLivePlayback {
            hasStartedLivePlayback = true
            playbackSliceStartInAssembled = 0
            lastReportedPlaybackSample = -1
            playerNode.play()
            playbackAnchorSample = playerNode.lastRenderTime.flatMap {
                playerNode.playerTime(forNodeTime: $0)?.sampleTime
            } ?? 0
        }
    }

    private func makeSynthesisRequest(
        provider: TTSProvider,
        apiKey: String,
        trimmedText: String,
        openAIVoice: OpenAITTSVoice,
        elevenLabsVoiceID: String?,
        instructions: String?,
        model: String?
    ) throws -> URLRequest {
        switch provider {
        case .openAI:
            let url = URL(string: "https://api.openai.com/v1/audio/speech")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            var payload: [String: Any] = [
                "model": model ?? "gpt-4o-mini-tts",
                "voice": openAIVoice.rawValue,
                "input": trimmedText,
                "response_format": "pcm",
            ]
            if let instructions, !instructions.isEmpty {
                payload["instructions"] = instructions
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            return request

        case .elevenLabs:
            guard let voiceID = elevenLabsVoiceID, !voiceID.isEmpty else {
                throw TextToSpeechError.noVoiceSelected
            }
            var components = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)/stream")!
            components.queryItems = [URLQueryItem(name: "output_format", value: "pcm_24000")]
            guard let url = components.url else {
                throw TextToSpeechError.noVoiceSelected
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let payload: [String: Any] = [
                "text": trimmedText,
                "model_id": model ?? "eleven_multilingual_v2",
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            return request

        case .gemini:
            throw TextToSpeechError.missingAPIKey(provider: .gemini)
        }
    }

    public func stop() {
        conversationGenerationTask?.cancel()
        conversationGenerationTask = nil
        currentTask?.cancel()
        currentTask = nil

        if playerNode.isPlaying { playerNode.stop() }
        playerNode.reset()
        lastReportedPlaybackSample = -1

        leftoverByte = nil
        hasStartedLivePlayback = false

        if let cb = onFinish {
            onFinish = nil
            if !didFinishRequest {
                didFinishRequest = true
                DispatchQueue.main.async { cb(nil) }
            }
        }

        if assembledSamples.isEmpty {
            state = .idle
        } else {
            state = .readyForReplay
        }
    }

    /// Drops loaded audio, the sentence map, and synthesis bookkeeping without starting a new utterance.
    public func clearLoadedUtterance() {
        conversationGenerationTask?.cancel()
        conversationGenerationTask = nil
        currentTask?.cancel()
        currentTask = nil

        if playerNode.isPlaying { playerNode.stop() }
        playerNode.reset()
        lastReportedPlaybackSample = -1

        leftoverByte = nil
        hasStartedLivePlayback = false
        onFinish = nil
        didFinishRequest = false
        errorBody.removeAll()

        assembledSamples.removeAll()
        assembledBuffer = nil
        sentences.removeAll()
        utteranceSourceText = ""

        incSamplesScannedCount = 0
        incInSpeech = false
        incRegionStart = 0
        incSilenceRun = 0
        incCommittedRegions.removeAll()
        incHighestFinalizedIndex = -1

        playbackSliceStartInAssembled = 0
        playbackSliceEndExclusive = 0

        state = .idle
    }

    // MARK: - Replay

    public func replayAll() {
        replay(fromSample: 0)
    }

    /// Replays from an absolute sample offset through the end of the assembled buffer.
    public func replay(fromSample sampleIndex: Int) {
        guard !assembledSamples.isEmpty else { return }
        let start = min(max(sampleIndex, 0), max(assembledSamples.count - 1, 0))
        let range = start..<assembledSamples.count
        guard !range.isEmpty else { return }

        playerNode.stop()
        playerNode.reset()
        do {
            try configureAudioSessionForPlayback()
            try startEngineIfNeeded()
        } catch {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.textToSpeechService(self, didFailWith: TextToSpeechError.audioEngineFailed(underlying: error))
            }
            return
        }
        guard let buffer = makeBuffer(sampleRange: range) else { return }
        playerNode.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.state == .playing { self.state = .readyForReplay }
            }
        }
        playbackSliceStartInAssembled = range.lowerBound
        playbackSliceEndExclusive = range.upperBound
        lastReportedPlaybackSample = -1
        playerNode.play()
        playbackAnchorSample = playerNode.lastRenderTime.flatMap {
            playerNode.playerTime(forNodeTime: $0)?.sampleTime
        } ?? 0
        state = .playing
    }

    /// Play the sample slice bound to a given sentence row.
    public func play(sentenceAt index: Int) {
        guard sentences.indices.contains(index) else { return }
        let range = sentences[index].sampleRange
        guard !range.isEmpty, range.upperBound <= assembledSamples.count else { return }

        playerNode.stop()
        playerNode.reset()
        do {
            try configureAudioSessionForPlayback()
            try startEngineIfNeeded()
        } catch {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.textToSpeechService(self, didFailWith: TextToSpeechError.audioEngineFailed(underlying: error))
            }
            return
        }
        guard let buffer = makeBuffer(sampleRange: range) else { return }
        playerNode.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.state == .playing { self.state = .readyForReplay }
            }
        }
        playbackSliceStartInAssembled = range.lowerBound
        playbackSliceEndExclusive = range.upperBound
        lastReportedPlaybackSample = -1
        playerNode.play()
        playbackAnchorSample = playerNode.lastRenderTime.flatMap {
            playerNode.playerTime(forNodeTime: $0)?.sampleTime
        } ?? 0
        state = .playing
    }

    public func pause() {
        guard case .playing = state else { return }
        playerNode.pause()
        state = .paused
    }

    public func resume() {
        guard case .paused = state else { return }
        playerNode.play()
        state = .playing
    }

    // MARK: - Save / restore

    /// Writes `manifest.json` and `audio.float32` into `directory` (typically from `SavedGenerationStore.makeNewBundleDirectory()`).
    public func exportSavedBundle(to directory: URL) throws {
        guard canExportSavedSnapshot else {
            throw SavedGenerationError.notReadyToExport
        }
        let rows: [SavedSentenceRow] = try sentences.map { s in
            let r = s.sampleRange
            guard !r.isEmpty,
                  r.lowerBound >= 0,
                  r.upperBound <= assembledSamples.count
            else { throw SavedGenerationError.invalidSentenceAlignment }
            return SavedSentenceRow(
                text: s.text,
                sampleLower: r.lowerBound,
                sampleUpper: r.upperBound,
                peaks: s.peaks
            )
        }
        let snapshot = SavedTTSSnapshot(
            formatVersion: SavedTTSSnapshot.currentFormatVersion,
            createdAt: Date(),
            utteranceSourceText: utteranceSourceText,
            voice: lastSynthesisVoiceString,
            provider: lastSynthesisProvider.rawValue,
            sampleRate: Self.sampleRate,
            sentences: rows
        )
        let manifestURL = directory.appendingPathComponent(SavedGenerationFilenames.manifest)
        let audioURL = directory.appendingPathComponent(SavedGenerationFilenames.audio)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(snapshot).write(to: manifestURL)
        let audioData = assembledSamples.withUnsafeBufferPointer { Data(buffer: $0) }
        try audioData.write(to: audioURL, options: .atomic)
    }

    /// Inserts a fixed-duration silent gap at `sampleIndex` for dialogue line-break markers.
    /// Main thread only. Shifts sentence sample ranges at/after the insertion point.
    public func insertMarkerSilence(
        at sampleIndex: Int,
        duration: TimeInterval = TTSAudioAlignmentMarker.silenceDuration
    ) throws {
        assert(Thread.isMainThread)
        let insertCount = TTSAudioAlignmentMarker.silenceSampleCount(sampleRate: Self.sampleRate)
        guard insertCount > 0 else { throw SavedGenerationError.invalidSentenceAlignment }
        guard sampleIndex >= 0, sampleIndex <= assembledSamples.count else {
            throw SavedGenerationError.invalidSentenceAlignment
        }

        if playerNode.isPlaying { playerNode.stop() }
        playerNode.reset()

        let gap = [Float](repeating: 0, count: insertCount)
        assembledSamples.insert(contentsOf: gap, at: sampleIndex)
        assembledBuffer = nil
        playbackSliceStartInAssembled = 0
        playbackSliceEndExclusive = assembledSamples.count
        lastReportedPlaybackSample = -1

        if !sentences.isEmpty {
            var updated: [SpeechSentence] = []
            updated.reserveCapacity(sentences.count)
            for sentence in sentences {
                let range = sentence.sampleRange
                guard !range.isEmpty else { continue }
                let shifted: Range<Int>
                if range.lowerBound >= sampleIndex {
                    shifted = (range.lowerBound + insertCount)..<(range.upperBound + insertCount)
                } else if range.upperBound <= sampleIndex {
                    shifted = range
                } else {
                    shifted = range.lowerBound..<(range.upperBound + insertCount)
                }
                guard shifted.upperBound <= assembledSamples.count else {
                    throw SavedGenerationError.invalidSentenceAlignment
                }
                let peaks = Self.peaks(
                    from: assembledSamples,
                    range: shifted,
                    bucketCount: Self.peakBucketCount
                )
                updated.append(
                    SpeechSentence(
                        index: updated.count,
                        text: sentence.text,
                        state: sentence.state,
                        sampleRange: shifted,
                        peaks: peaks,
                        sampleRate: sentence.sampleRate
                    )
                )
            }
            sentences = updated
        }

        state = assembledSamples.isEmpty ? .idle : .readyForReplay
    }

    /// Deletes a middle slice and closes the gap. Main thread only. Shifts sentence ranges after the removed span.
    public func removeSamples(in range: Range<Int>) throws {
        assert(Thread.isMainThread)
        guard !range.isEmpty,
              range.lowerBound >= 0,
              range.upperBound <= assembledSamples.count
        else { throw SavedGenerationError.invalidSentenceAlignment }

        if playerNode.isPlaying { playerNode.stop() }
        playerNode.reset()

        let removedCount = range.count
        assembledSamples.removeSubrange(range)
        assembledBuffer = nil
        playbackSliceStartInAssembled = 0
        playbackSliceEndExclusive = assembledSamples.count
        lastReportedPlaybackSample = -1

        if !sentences.isEmpty {
            var updated: [SpeechSentence] = []
            updated.reserveCapacity(sentences.count)
            for sentence in sentences {
                guard let shifted = Self.sampleRange(
                    sentence.sampleRange,
                    afterRemoving: range,
                    newTotal: assembledSamples.count
                ) else { continue }
                let peaks = Self.peaks(
                    from: assembledSamples,
                    range: shifted,
                    bucketCount: Self.peakBucketCount
                )
                updated.append(
                    SpeechSentence(
                        index: updated.count,
                        text: sentence.text,
                        state: sentence.state,
                        sampleRange: shifted,
                        peaks: peaks,
                        sampleRate: sentence.sampleRate
                    )
                )
            }
            sentences = updated
        }

        state = assembledSamples.isEmpty ? .idle : .readyForReplay
    }

    /// Maps a sample range after deleting `removed`; nil when the sentence falls entirely inside the cut.
    private static func sampleRange(
        _ range: Range<Int>,
        afterRemoving removed: Range<Int>,
        newTotal: Int
    ) -> Range<Int>? {
        let removedCount = removed.count
        if range.upperBound <= removed.lowerBound {
            return range
        }
        if range.lowerBound >= removed.upperBound {
            let shifted = (range.lowerBound - removedCount)..<(range.upperBound - removedCount)
            guard shifted.upperBound <= newTotal else { return nil }
            return shifted
        }
        if range.lowerBound >= removed.lowerBound, range.upperBound <= removed.upperBound {
            return nil
        }
        if range.lowerBound < removed.lowerBound, range.upperBound > removed.upperBound {
            let shifted = range.lowerBound..<(range.upperBound - removedCount)
            guard shifted.lowerBound >= 0, shifted.upperBound <= newTotal, shifted.upperBound > shifted.lowerBound else {
                return nil
            }
            return shifted
        }
        if range.lowerBound < removed.lowerBound {
            let end = min(range.upperBound, removed.lowerBound)
            guard end > range.lowerBound else { return nil }
            return range.lowerBound..<end
        }
        let start = removed.lowerBound
        let end = range.upperBound - removedCount
        guard end > start, end <= newTotal else { return nil }
        return start..<end
    }

    /// Permanently shortens `assembledSamples` to `range` and remaps sentence rows. Main thread only.
    public func applyPermanentTrim(keeping range: Range<Int>) throws {
        assert(Thread.isMainThread)
        guard !range.isEmpty,
              range.lowerBound >= 0,
              range.upperBound <= assembledSamples.count
        else { throw SavedGenerationError.invalidSentenceAlignment }

        if range.lowerBound == 0, range.upperBound == assembledSamples.count {
            return
        }

        if playerNode.isPlaying { playerNode.stop() }
        playerNode.reset()

        let sliced = Array(assembledSamples[range])
        var newSentences: [SpeechSentence] = []
        newSentences.reserveCapacity(sentences.count)

        for sentence in sentences {
            let lo = max(sentence.sampleRange.lowerBound, range.lowerBound)
            let hi = min(sentence.sampleRange.upperBound, range.upperBound)
            guard hi > lo else { continue }
            let shifted = (lo - range.lowerBound) ..< (hi - range.lowerBound)
            let peaks = Self.peaks(from: sliced, range: shifted, bucketCount: Self.peakBucketCount)
            newSentences.append(
                SpeechSentence(
                    index: newSentences.count,
                    text: sentence.text,
                    state: .ready,
                    sampleRange: shifted,
                    peaks: peaks,
                    sampleRate: sentence.sampleRate
                )
            )
        }

        assembledSamples = sliced
        sentences = newSentences
        assembledBuffer = nil
        playbackSliceStartInAssembled = 0
        lastReportedPlaybackSample = -1
        state = sliced.isEmpty ? .idle : .readyForReplay
    }

    /// Replaces the current utterance with data from a bundle folder. Call on the main thread only.
    public func loadSavedBundle(at directory: URL) throws {
        assert(Thread.isMainThread)
        currentTask?.cancel()
        currentTask = nil
        playerNode.stop()
        playerNode.reset()
        leftoverByte = nil
        hasStartedLivePlayback = false
        didFinishRequest = true
        onFinish = nil
        errorBody.removeAll()
        assembledBuffer = nil
        incSamplesScannedCount = 0
        incInSpeech = false
        incRegionStart = 0
        incSilenceRun = 0
        incCommittedRegions.removeAll()
        incHighestFinalizedIndex = -1
        playbackSliceStartInAssembled = 0
        lastReportedPlaybackSample = -1
        playbackAnchorSample = 0

        let manifestURL = directory.appendingPathComponent(SavedGenerationFilenames.manifest)
        let audioURL = directory.appendingPathComponent(SavedGenerationFilenames.audio)
        let manifestData = try Data(contentsOf: manifestURL)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let snapshot: SavedTTSSnapshot
        do {
            snapshot = try dec.decode(SavedTTSSnapshot.self, from: manifestData)
        } catch {
            throw SavedGenerationError.couldNotReadManifest
        }

        let audioData = try Data(contentsOf: audioURL)
        let floatCount = audioData.count / MemoryLayout<Float>.size
        guard audioData.count == floatCount * MemoryLayout<Float>.size, floatCount > 0 else {
            throw SavedGenerationError.invalidAudioFile
        }
        var samples = [Float](repeating: 0, count: floatCount)
        samples.withUnsafeMutableBytes { raw in
            audioData.copyBytes(to: raw)
        }

        for row in snapshot.sentences {
            guard row.sampleLower >= 0,
                  row.sampleUpper > row.sampleLower,
                  row.sampleUpper <= samples.count
            else { throw SavedGenerationError.invalidSentenceAlignment }
        }

        assembledSamples = samples
        utteranceSourceText = snapshot.utteranceSourceText
        lastSynthesisVoiceString = snapshot.voice
        lastSynthesisProvider = TTSProvider(rawValue: snapshot.provider ?? TTSProvider.openAI.rawValue) ?? .openAI
        sentences = snapshot.sentences.enumerated().map { i, row in
            SpeechSentence(
                index: i,
                text: row.text,
                state: .ready,
                sampleRange: row.sampleLower..<row.sampleUpper,
                peaks: row.peaks,
                sampleRate: snapshot.sampleRate > 0 ? snapshot.sampleRate : Self.sampleRate
            )
        }
        state = .readyForReplay
        delegate?.textToSpeechServiceDidRestoreSavedUtterance(self)
    }

    // MARK: - Sentence splitting

    /// Splits on linguistic sentence boundaries (not single characters). Keeps commas,
    /// decimals, and common abbreviations (`Dr.`, `3.50`, etc.) inside one sentence.
    public static func splitIntoSentences(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = trimmed
        var parts: [String] = []
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            let piece = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { parts.append(piece) }
            return true
        }

        if parts.isEmpty {
            return [trimmed]
        }
        return parts
    }

    // MARK: - Audio session / engine

    private func configureAudioSessionForPlayback() throws {
#if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try session.setActive(true, options: [])
#elseif os(macOS)
        // macOS has no AVAudioSession; playback uses AVAudioEngine’s default routing.
#else
        fatalError("Unsupported platform.")
#endif
    }

    private func startEngineIfNeeded() throws {
        if audioEngine.isRunning { return }
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func installLevelMeterTap() {
        let mixer = audioEngine.mainMixerNode
        let format = mixer.outputFormat(forBus: 0)
        mixer.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let now = DispatchTime.now()
            let elapsedNanos = now.uptimeNanoseconds - self.lastLevelTapForwardTime.uptimeNanoseconds
            guard elapsedNanos >= 50_000_000 else { return } // ~20Hz is plenty for a level meter/playhead.
            self.lastLevelTapForwardTime = now

            let level = Self.computeRMS(buffer)
            let offset = self.currentPlaybackSampleOffset()
            DispatchQueue.main.async {
                self.delegate?.textToSpeechService(self, didUpdateLevel: level)
                if let offset, offset != self.lastReportedPlaybackSample {
                    self.lastReportedPlaybackSample = offset
                    self.delegate?.textToSpeechService(self, didAdvancePlaybackTo: offset)
                }
            }
        }
    }

    /// Absolute sample offset into `assembledSamples` for the sample currently hitting the
    /// speakers, or nil if no playback is underway. Called from the audio thread.
    private func currentPlaybackSampleOffset() -> Int? {
        // `playerNode.isPlaying` can stay true after the scheduled buffer ends while
        // `playerTime` keeps advancing — gate on app playback state and slice bounds.
        guard state == .playing else { return nil }
        guard playerNode.isPlaying else { return nil }
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime)
        else { return nil }
        let elapsed = playerTime.sampleTime - playbackAnchorSample
        guard elapsed >= 0 else { return nil }
        let hostSRRatio = Self.sampleRate / max(playerTime.sampleRate, 1)
        let elapsedAtOurRate = Int(Double(elapsed) * hostSRRatio)
        let raw = playbackSliceStartInAssembled + elapsedAtOurRate
        let endExclusive = max(playbackSliceEndExclusive, playbackSliceStartInAssembled + 1)
        guard raw < endExclusive else { return nil }
        return raw
    }

    private static func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData else { return 0 }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        var sumSquares: Float = 0
        for ch in 0..<channelCount {
            let channel = data[ch]
            for i in 0..<frameLength {
                let sample = channel[i]
                sumSquares += sample * sample
            }
        }
        let meanSquare = sumSquares / Float(frameLength * max(channelCount, 1))
        return sqrtf(meanSquare)
    }

    // MARK: - Buffer construction

    private func makeBuffer(sampleRange range: Range<Int>) -> AVAudioPCMBuffer? {
        guard !range.isEmpty,
              range.lowerBound >= 0,
              range.upperBound <= assembledSamples.count,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: pcmFormat,
                frameCapacity: AVAudioFrameCount(range.count)
              )
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(range.count)
        if let channel = buffer.floatChannelData?[0] {
            assembledSamples.withUnsafeBufferPointer { src in
                guard let base = src.baseAddress else { return }
                channel.update(from: base.advanced(by: range.lowerBound), count: range.count)
            }
        }
        return buffer
    }

    private func makeAssembledBuffer() -> AVAudioPCMBuffer? {
        if let cached = assembledBuffer { return cached }
        guard !assembledSamples.isEmpty,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: pcmFormat,
                frameCapacity: AVAudioFrameCount(assembledSamples.count)
              )
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(assembledSamples.count)
        if let channel = buffer.floatChannelData?[0] {
            assembledSamples.withUnsafeBufferPointer { src in
                guard let base = src.baseAddress else { return }
                channel.update(from: base, count: assembledSamples.count)
            }
        }
        assembledBuffer = buffer
        return buffer
    }

    // MARK: - Streaming ingest

    /// Convert a streamed chunk of raw Int16 little-endian PCM bytes into Floats,
    /// append to `assembledSamples`, and schedule them for immediate playback.
    private func ingest(pcmData chunk: Data) {
        var data = chunk
        if let leftover = leftoverByte {
            var combined = Data([leftover])
            combined.append(data)
            data = combined
            leftoverByte = nil
        }
        if data.count % 2 == 1 {
            leftoverByte = data.last
            data = data.dropLast()
        }
        guard !data.isEmpty else { return }

        let sampleCount = data.count / 2
        var samples = [Float](repeating: 0, count: sampleCount)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            let int16Ptr = base.assumingMemoryBound(to: Int16.self)
            let scale: Float = 1.0 / 32768.0
            for i in 0..<sampleCount {
                samples[i] = Float(int16Ptr[i]) * scale
            }
        }

        let snapshot = samples
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.assembledSamples.append(contentsOf: snapshot)
            self.assembledBuffer = nil
            self.runIncrementalScan()
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: pcmFormat,
            frameCapacity: AVAudioFrameCount(sampleCount)
        ) else { return }
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        if let channel = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { src in
                guard let base = src.baseAddress else { return }
                channel.update(from: base, count: sampleCount)
            }
        }

        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        if !hasStartedLivePlayback {
            hasStartedLivePlayback = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.playbackSliceStartInAssembled = 0
                self.lastReportedPlaybackSample = -1
            }
            playerNode.play()
            let anchor = playerNode.lastRenderTime.flatMap {
                playerNode.playerTime(forNodeTime: $0)?.sampleTime
            } ?? 0
            DispatchQueue.main.async { [weak self] in
                self?.playbackAnchorSample = anchor
            }
        }
    }

    // MARK: - Incremental alignment (while streaming)

    /// Scan any new full 20 ms windows since the last call, using fixed thresholds.
    /// When a silence confirmed by the scan closes a speech region (i.e. we see new speech
    /// begin after ≥ minSilence samples of quiet), that region is committed. Every committed
    /// region can seed a sentence boundary in left-to-right order; we finalize sentences
    /// 0..<K as boundaries accumulate.
    ///
    /// Must run on the main thread.
    private func runIncrementalScan() {
        // Skip work if we've already finalized everything.
        if incHighestFinalizedIndex >= sentences.count - 1 { return }

        let window = Self.incWindowSamples
        let total = assembledSamples.count
        // Only scan complete windows; leave a partial tail for the next chunk.
        let scanUpTo = (total / window) * window
        guard scanUpTo > incSamplesScannedCount else { return }

        var k = incSamplesScannedCount / window
        let kEnd = scanUpTo / window
        while k < kEnd {
            let a = k * window
            let b = a + window
            var sum: Float = 0
            var j = a
            while j < b {
                let s = assembledSamples[j]
                sum += s * s
                j += 1
            }
            let rms = sqrtf(sum / Float(window))

            if incInSpeech {
                if rms < Self.incExitThreshold {
                    incSilenceRun += window
                    if incSilenceRun >= Self.incMinSilenceSamples {
                        // End of a speech region: everything from regionStart up to the sample
                        // where silence actually began.
                        let regionEnd = max(incRegionStart + 1, b - incSilenceRun)
                        let region = incRegionStart..<regionEnd
                        if region.count >= Self.incMinSpeechSamples {
                            incCommittedRegions.append(region)
                        }
                        incInSpeech = false
                        incSilenceRun = 0
                    }
                } else {
                    incSilenceRun = 0
                }
            } else {
                if rms >= Self.incEnterThreshold {
                    incRegionStart = a
                    incInSpeech = true
                    incSilenceRun = 0
                }
            }
            k += 1
        }
        incSamplesScannedCount = scanUpTo

        // We can finalize sentence boundaries only once a region is *closed*, i.e. a subsequent
        // region has started. That's what makes a silence "confirmed": we've seen speech on
        // both sides of it.
        //
        // `incCommittedRegions` only contains fully-closed regions (we don't append until a
        // speech→silence→speech transition). If we're currently inSpeech, we have one more
        // "open" region whose upper bound we don't know yet — skip it until it closes.
        let closedRegionCount = incCommittedRegions.count
        // Confirmed silences live between consecutive closed regions, so count is closedRegionCount - 1
        // unless we've also opened a new region after the last closed one (in which case it's
        // closedRegionCount, because we know there's silence between [last closed].upper and the
        // next region's start — we just don't know where the next region ends, but we know
        // where the silence ended).
        let confirmedSilenceCount: Int = {
            guard closedRegionCount >= 1 else { return 0 }
            // Between every pair of closed regions there's one confirmed silence.
            var count = max(0, closedRegionCount - 1)
            // If we've also already started a new (still-open) region after the last closed one,
            // the silence between them is confirmed too — its midpoint is known (between
            // last closed upperBound and current incRegionStart).
            if incInSpeech, incRegionStart >= (incCommittedRegions.last?.upperBound ?? 0) {
                count += 1
            }
            return count
        }()

        let N = sentences.count
        // We can finalize sentences 0..<confirmedSilenceCount (indices 0..confirmedSilenceCount - 1),
        // but never the final sentence — its upper bound is unknown until streaming ends.
        let maxFinalizable = min(confirmedSilenceCount, N - 1) - 1
        if maxFinalizable <= incHighestFinalizedIndex { return }

        // Build boundary sample positions for the confirmed silences.
        func silenceMidpoint(at silenceIndex: Int) -> Int {
            let prev = incCommittedRegions[silenceIndex]
            if silenceIndex + 1 < incCommittedRegions.count {
                let next = incCommittedRegions[silenceIndex + 1]
                return (prev.upperBound + next.lowerBound) / 2
            } else {
                // Silence between `prev` and the currently-open region that started at `incRegionStart`.
                return (prev.upperBound + incRegionStart) / 2
            }
        }

        for i in (incHighestFinalizedIndex + 1)...maxFinalizable {
            let loSample: Int
            if i == 0 {
                loSample = 0
            } else {
                loSample = silenceMidpoint(at: i - 1)
            }
            let hiSample = silenceMidpoint(at: i)
            let lo = max(0, min(assembledSamples.count, loSample))
            let hi = max(lo + 1, min(assembledSamples.count, hiSample))
            finalizeSentence(at: i, range: lo..<hi)
        }
        incHighestFinalizedIndex = maxFinalizable
    }

    // MARK: - Post-stream alignment
    private func alignSentencesToAssembledAudio() {
        let texts = sentences.map(\.text)
        guard !texts.isEmpty else { return }
        let total = assembledSamples.count
        guard total > 0 else {
            for i in sentences.indices {
                sentences[i].state = .failed("no audio")
            }
            return
        }

        let aligned = TTSAudioAlignment.align(
            lines: texts,
            samples: assembledSamples,
            sampleRate: Self.sampleRate
        )
        for (index, line) in aligned.enumerated() {
            finalizeSentence(at: index, range: line.sampleRange)
        }
        for index in aligned.count..<sentences.count {
            sentences[index].state = .failed("alignment mismatch")
        }
    }

    private func finalizeSentence(at index: Int, range: Range<Int>) {
        guard sentences.indices.contains(index) else { return }
        let peaks = Self.peaks(from: assembledSamples, range: range, bucketCount: Self.peakBucketCount)
        sentences[index].sampleRange = range
        sentences[index].peaks = peaks
        sentences[index].state = .ready
        delegate?.textToSpeechService(self, didUpdateSentenceAt: index)
    }

    /// Replaces sentence rows with one entry per conversation dialogue line (text only).
    public func setConversationSentences(from lines: [String]) {
        assert(Thread.isMainThread)
        let trimmed = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmed.isEmpty else {
            sentences = []
            return
        }
        let hasAudio = !assembledSamples.isEmpty
        sentences = trimmed.enumerated().map { index, text in
            SpeechSentence(
                index: index,
                text: text,
                state: hasAudio ? .streaming : .pending,
                sampleRange: 0..<0,
                peaks: [],
                sampleRate: Self.sampleRate
            )
        }
    }

    /// Builds one sentence row per dialogue line, then binds audio using line-switch marks when complete.
    public func applyConversationSentenceMap(lines: [String], lineSwitchSamples: [Int] = []) {
        assert(Thread.isMainThread)
        setConversationSentences(from: lines)
        guard !assembledSamples.isEmpty else { return }

        let trimmed = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return }

        if trimmed.count == 1 {
            finalizeSentence(at: 0, range: 0..<assembledSamples.count)
            return
        }

        if lineSwitchSamples.count == trimmed.count - 1 {
            realignSentences(usingLineSwitchSamples: lineSwitchSamples)
        } else {
            alignSentencesToAssembledAudio()
        }
    }

    /// Re-splits sentence rows using VAD (discards manual line-switch marks).
    public func refreshSentenceAlignmentFromVAD() {
        assert(Thread.isMainThread)
        alignSentencesToAssembledAudio()
    }

    /// Re-splits sentence rows at the given sample indices (count must be `sentences.count - 1`).
    /// Matches the boundaries embedded in exported M4A dialogue metadata.
    public func realignSentences(usingLineSwitchSamples marks: [Int]) {
        assert(Thread.isMainThread)
        let texts = sentences.map(\.text)
        guard texts.count >= 2, !assembledSamples.isEmpty else { return }
        guard marks.count == texts.count - 1 else { return }

        let sorted = marks.sorted()
        guard sorted == marks else { return }

        let total = assembledSamples.count
        guard sorted.allSatisfy({ $0 > 0 && $0 < total }) else { return }

        var boundaries = [0] + sorted + [total]
        for index in texts.indices {
            let lower = boundaries[index]
            let upper = boundaries[index + 1]
            guard upper > lower, upper <= total else {
                sentences[index].state = .failed("invalid line-break range")
                delegate?.textToSpeechService(self, didUpdateSentenceAt: index)
                continue
            }
            finalizeSentence(at: index, range: lower..<upper)
        }
    }

    // MARK: - VAD

    /// Silence/speech frame classification using short-window RMS with hysteresis and a
    /// minimum-silence length. Returns contiguous speech regions as half-open sample ranges.
    /// Tuned for synthesised speech at 24 kHz: 20 ms windows, ~180 ms minimum silence.
    static func vadSpeechRegions(samples: [Float], sampleRate: Double) -> [Range<Int>] {
        TTSAudioAlignment.vadSpeechRegions(samples: samples, sampleRate: sampleRate)
    }

    // MARK: - Peaks

    private static func peaks(from samples: [Float], range: Range<Int>, bucketCount: Int) -> [Float] {
        guard !range.isEmpty, bucketCount > 0,
              range.lowerBound >= 0, range.upperBound <= samples.count
        else { return [] }
        let total = range.count
        let perBucket = max(1, total / bucketCount)
        var result: [Float] = []
        result.reserveCapacity(bucketCount)
        var i = range.lowerBound
        while i < range.upperBound && result.count < bucketCount {
            let end = min(i + perBucket, range.upperBound)
            var peak: Float = 0
            var j = i
            while j < end {
                let s = abs(samples[j])
                if s > peak { peak = s }
                j += 1
            }
            result.append(peak)
            i = end
        }
        while result.count < bucketCount {
            result.append(result.last ?? 0)
        }
        return result
    }

    private func finish(with error: Error?) {
        guard !didFinishRequest else { return }
        didFinishRequest = true

        currentTask = nil

        let cb = onFinish
        onFinish = nil

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Align sentences to the finished assembled buffer.
            if error == nil, !self.assembledSamples.isEmpty, !self.sentences.isEmpty {
                self.alignSentencesToAssembledAudio()
            } else if error != nil {
                for i in self.sentences.indices {
                    if case .streaming = self.sentences[i].state {
                        self.sentences[i].state = .failed(error?.localizedDescription ?? "failed")
                    }
                    self.delegate?.textToSpeechService(self, didUpdateSentenceAt: i)
                }
            }

            if let error {
                self.delegate?.textToSpeechService(self, didFailWith: error)
            } else {
                self.delegate?.textToSpeechServiceDidFinish(self)
            }
            cb?(error)
        }

        if state == .streaming {
            state = assembledSamples.isEmpty ? .idle : .readyForReplay
        }
    }
}

// MARK: - URLSessionDataDelegate

extension TextToSpeechService: URLSessionDataDelegate {

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let http = dataTask.response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
            ingest(pcmData: data)
        } else {
            errorBody.append(data)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let http = task.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: errorBody, encoding: .utf8)
            errorBody.removeAll()
            finish(with: TextToSpeechError.invalidResponse(provider: activeSynthesisProvider, status: http.statusCode, body: body))
            return
        }

        if let error {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled {
                finish(with: nil)
                return
            }
            finish(with: error)
            return
        }

        // Schedule a zero-length sentinel so we know when live playback has drained.
        let doneBuffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: 1)
        doneBuffer?.frameLength = 0
        if let doneBuffer {
            playerNode.scheduleBuffer(doneBuffer) { [weak self] in
                DispatchQueue.main.async {
                    self?.finish(with: nil)
                }
            }
        } else {
            finish(with: nil)
        }
    }
}
