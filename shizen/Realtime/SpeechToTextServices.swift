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

    func start(
        contextualStrings: [String] = [],
        onUpdate: @escaping (String) -> Void,
        onError: @escaping (Error?) -> Void
    ) throws {
        stop()

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw NSError(
                domain: "SpeechToText",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is not available for \(locale.identifier)."]
            )
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if !contextualStrings.isEmpty {
            request.contextualStrings = contextualStrings
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    onUpdate(text)
                }
            }

            if let error {
                let benign = isBenignSpeechRecognitionError(error)
                DispatchQueue.main.async {
                    if !benign {
                        onError(error)
                    }
                    if self.isRunning || self.audioEngine.isRunning {
                        self.stop()
                    }
                }
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning || audioEngine.isRunning else {
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
            return
        }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRunning = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
        try engine.start(contextualStrings: contextualStrings, onUpdate: onUpdate, onError: onError)
    }

    func stop() {
        engine.stop()
    }
}

final class JapaneseSpeechToText: SpeechToTextService {
    private let engine = SpeechToTextEngine(localeIdentifier: "ja-JP")

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
        try engine.start(contextualStrings: contextualStrings, onUpdate: onUpdate, onError: onError)
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
