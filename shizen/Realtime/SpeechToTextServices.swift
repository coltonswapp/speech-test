//
//  SpeechToTextServices.swift
//  shizen
//

import AVFoundation
import Foundation
import Speech

/// `SFSpeechRecognitionTask` often finishes with an error after `cancel()`, `endAudio()`, or teardown — not a user-facing failure.
private func isBenignSpeechRecognitionError(_ error: Error) -> Bool {
    let ns = error as NSError
    if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled {
        return true
    }
    // Recognition canceled (user stopped, task replaced, etc.) — domain string as reported by `SFSpeechRecognizer`.
    if ns.domain == "kAFAssistantErrorDomain", ns.code == 216 {
        return true
    }
    return false
}

private final class SpeechToTextEngine: NSObject {
    private let locale: Locale
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    init(localeIdentifier: String) {
        locale = Locale(identifier: localeIdentifier)
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        super.init()
    }

    private(set) var isRunning = false
    var onInputLevel: ((Float) -> Void)?

    /// When false, callers feed PCM via ``append(_:)`` (e.g. a shared Whisper tap).
    private var ownsAudioCapture = true

    func start(
        contextualStrings: [String] = [],
        captureAudio: Bool = true,
        onUpdate: @escaping (String, Bool) -> Void,
        onError: @escaping (Error?) -> Void,
        onFinish: (() -> Void)? = nil
    ) throws {
        stop()
        ownsAudioCapture = captureAudio

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw NSError(
                domain: "SpeechToText",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is not available for \(locale.identifier)."]
            )
        }

        if captureAudio {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if !contextualStrings.isEmpty {
            request.contextualStrings = contextualStrings
        }
        recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                DispatchQueue.main.async {
                    onUpdate(text, isFinal)
                    if isFinal {
                        onFinish?()
                    }
                }
            }

            if let error {
                let benign = isBenignSpeechRecognitionError(error)
                DispatchQueue.main.async {
                    if !benign {
                        onError(error)
                    }
                    if self.isRunning, self.ownsAudioCapture, self.audioEngine.isRunning {
                        self.stop()
                    } else if self.isRunning, !self.ownsAudioCapture {
                        self.stopRecognitionTaskOnly()
                    }
                }
            }
        }

        if captureAudio {
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
                guard let onInputLevel = self?.onInputLevel else { return }
                let level = MicrophoneInputLevel.rms(from: buffer)
                DispatchQueue.main.async {
                    onInputLevel(level)
                }
            }
            audioEngine.prepare()
            try audioEngine.start()
        }
        isRunning = true
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    func stop() {
        if ownsAudioCapture {
            guard isRunning || audioEngine.isRunning else {
                stopRecognitionTaskOnly()
                return
            }
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            stopRecognitionTaskOnly()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        stopRecognitionTaskOnly()
    }

    private func stopRecognitionTaskOnly() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRunning = false
    }
}

// MARK: - Public POC types

protocol SpeechToTextService: AnyObject {
    var isRunning: Bool { get }
    func start(
        contextualStrings: [String],
        onUpdate: @escaping (String) -> Void,
        onError: @escaping (Error?) -> Void
    ) throws
    func stop()
}

final class EnglishSpeechToText: SpeechToTextService {
    private let engine = SpeechToTextEngine(localeIdentifier: "en-US")

    var isRunning: Bool { engine.isRunning }

    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    func start(
        contextualStrings: [String] = [],
        onUpdate: @escaping (String) -> Void,
        onError: @escaping (Error?) -> Void
    ) throws {
        try engine.start(contextualStrings: contextualStrings, onUpdate: { text, _ in onUpdate(text) }, onError: onError)
    }

    func stop() {
        engine.stop()
    }
}

final class JapaneseSpeechToText: SpeechToTextService {
    private let engine = SpeechToTextEngine(localeIdentifier: "ja-JP")

    var isRunning: Bool { engine.isRunning }

    var onInputLevel: ((Float) -> Void)? {
        get { engine.onInputLevel }
        set { engine.onInputLevel = newValue }
    }

    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    func start(
        contextualStrings: [String] = [],
        onUpdate: @escaping (String) -> Void,
        onError: @escaping (Error?) -> Void
    ) throws {
        try engine.start(contextualStrings: contextualStrings, onUpdate: { text, _ in onUpdate(text) }, onError: onError)
    }

    func start(
        contextualStrings: [String] = [],
        onUpdate: @escaping (String, Bool) -> Void,
        onError: @escaping (Error?) -> Void,
        onFinish: @escaping () -> Void
    ) throws {
        try engine.start(
            contextualStrings: contextualStrings,
            captureAudio: true,
            onUpdate: onUpdate,
            onError: onError,
            onFinish: onFinish
        )
    }

    /// Recognize from buffers supplied by another capture session (Whisper's mic tap).
    func startReceivingBuffers(
        contextualStrings: [String] = [],
        onUpdate: @escaping (String, Bool) -> Void,
        onError: @escaping (Error?) -> Void,
        onFinish: @escaping () -> Void
    ) throws {
        try engine.start(
            contextualStrings: contextualStrings,
            captureAudio: false,
            onUpdate: onUpdate,
            onError: onError,
            onFinish: onFinish
        )
    }

    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        engine.append(buffer)
    }

    func stop() {
        engine.stop()
    }
}

// MARK: - Authorization

enum SpeechToTextAuthorization {
    static func request() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
