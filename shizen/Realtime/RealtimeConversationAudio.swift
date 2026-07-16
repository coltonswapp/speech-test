//
//  RealtimeConversationAudio.swift
//  shizen
//
//  Records PCM from the realtime session and plays clips without re-synthesis.
//

import AVFoundation
import Foundation
import TTSCore

enum RealtimeAudioSpeaker: Equatable {
    case user
    case assistant
}

/// Mono 16-bit PCM at 24 kHz (matches RealtimeService playback/capture).
struct RealtimeAudioClip: Equatable {
    let pcmData: Data
    let sampleRate: Double
    let speaker: RealtimeAudioSpeaker

    init(pcmData: Data, sampleRate: Double = RealtimeService.sampleRate, speaker: RealtimeAudioSpeaker) {
        self.pcmData = pcmData
        self.sampleRate = sampleRate
        self.speaker = speaker
    }
}

/// Accumulates mic and assistant PCM, then splits assistant audio by sentence proportionally.
final class RealtimeConversationRecorder {

    private var userBuffer = Data()
    private var isCapturingUser = false
    private var assistantBuffer = Data()
    private var isCapturingAssistant = false

    func reset() {
        userBuffer.removeAll(keepingCapacity: false)
        isCapturingUser = false
        assistantBuffer.removeAll(keepingCapacity: false)
        isCapturingAssistant = false
    }

    func userSpeechStarted() {
        userBuffer.removeAll(keepingCapacity: true)
        isCapturingUser = true
    }

    func appendUserPCM(_ data: Data) {
        guard isCapturingUser, !data.isEmpty else { return }
        userBuffer.append(data)
    }

    func finalizeUserUtterance() -> RealtimeAudioClip? {
        isCapturingUser = false
        guard !userBuffer.isEmpty else { return nil }
        let clip = RealtimeAudioClip(pcmData: userBuffer, speaker: .user)
        userBuffer.removeAll(keepingCapacity: true)
        return clip
    }

    func assistantResponseStarted() {
        assistantBuffer.removeAll(keepingCapacity: true)
        isCapturingAssistant = true
    }

    func ensureAssistantCaptureStarted() {
        guard !isCapturingAssistant else { return }
        assistantResponseStarted()
    }

    func appendAssistantPCM(_ data: Data) {
        guard isCapturingAssistant, !data.isEmpty else { return }
        assistantBuffer.append(data)
    }

    func cancelAssistantCapture() {
        isCapturingAssistant = false
        assistantBuffer.removeAll(keepingCapacity: false)
    }

    /// Splits one assistant response across display sentences (character-proportional PCM slices).
    func finalizeAssistantUtterance(transcript: String) -> [(sentence: String, clip: RealtimeAudioClip)] {
        isCapturingAssistant = false
        let pcm = assistantBuffer
        assistantBuffer.removeAll(keepingCapacity: true)
        guard !pcm.isEmpty else { return [] }

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let sentences = TextToSpeechService.splitIntoSentences(trimmed)
        let lines = sentences.isEmpty ? [trimmed] : sentences
        let clips = Self.splitPCM(pcm, across: lines, speaker: .assistant)
        return zip(lines, clips).map { ($0, $1) }
    }

    /// Splits one PCM buffer across lines by character count (approximate timing).
    static func splitPCM(
        _ pcm: Data,
        across lines: [String],
        speaker: RealtimeAudioSpeaker
    ) -> [RealtimeAudioClip] {
        guard !pcm.isEmpty, !lines.isEmpty else { return [] }
        if lines.count == 1 {
            return [RealtimeAudioClip(pcmData: pcm, speaker: speaker)]
        }

        let weights = lines.map { max(1, $0.count) }
        let totalWeight = weights.reduce(0, +)
        let totalBytes = pcm.count - (pcm.count % 2)
        var byteOffset = 0
        var results: [RealtimeAudioClip] = []

        for (index, _) in lines.enumerated() {
            let isLast = index == lines.count - 1
            let sliceEnd: Int
            if isLast {
                sliceEnd = totalBytes
            } else {
                let share = Int(Double(totalBytes) * Double(weights[index]) / Double(totalWeight))
                let evenShare = max(share - (share % 2), 2)
                sliceEnd = min(totalBytes, byteOffset + evenShare)
            }
            if sliceEnd > byteOffset {
                let slice = pcm.subdata(in: byteOffset..<sliceEnd)
                results.append(RealtimeAudioClip(pcmData: slice, speaker: speaker))
                byteOffset = sliceEnd
            } else {
                results.append(RealtimeAudioClip(pcmData: Data(), speaker: speaker))
            }
        }

        if byteOffset < totalBytes, !results.isEmpty {
            let remainder = pcm.subdata(in: byteOffset..<totalBytes)
            if let lastNonEmpty = results.lastIndex(where: { !$0.pcmData.isEmpty }) {
                var combined = results[lastNonEmpty].pcmData
                combined.append(remainder)
                results[lastNonEmpty] = RealtimeAudioClip(pcmData: combined, speaker: speaker)
            } else {
                results[results.count - 1] = RealtimeAudioClip(pcmData: remainder, speaker: speaker)
            }
        }

        return results
    }
}

/// Plays recorded realtime PCM clips.
final class RealtimePCMPlayer {

    static let shared = RealtimePCMPlayer()

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var connectedSampleRate: Double = 0

    private init() {}

    func play(_ clip: RealtimeAudioClip) {
        guard !clip.pcmData.isEmpty else { return }
        let work = { [self] in
            do {
                try activateSessionForPlayback()
                try ensureEngineConfigured(sampleRate: clip.sampleRate)
                guard let buffer = makeFloatBuffer(from: clip) else { return }

                if playerNode.isPlaying {
                    playerNode.stop()
                }
                playerNode.reset()
                playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts) { }
                if !engine.isRunning {
                    try engine.start()
                }
                playerNode.play()
            } catch {
                // Playback is best-effort for transcript replay.
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func stop() {
        let work = { [self] in
            playerNode.stop()
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func activateSessionForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        // Keep an active tutor capture session intact; output still routes to speaker.
        if session.category == .playAndRecord {
            try session.setActive(true, options: [])
            return
        }
        try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try session.setActive(true, options: [])
    }

    private func ensureEngineConfigured(sampleRate: Double) throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        guard connectedSampleRate != sampleRate || !engine.attachedNodes.contains(playerNode) else {
            return
        }

        if engine.attachedNodes.contains(playerNode) {
            engine.stop()
            engine.disconnectNodeOutput(playerNode)
        } else {
            engine.attach(playerNode)
        }

        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
        connectedSampleRate = sampleRate
    }

    private func makeFloatBuffer(from clip: RealtimeAudioClip) -> AVAudioPCMBuffer? {
        var pcm = clip.pcmData
        if pcm.count % 2 == 1 {
            pcm = pcm.dropLast()
        }
        guard !pcm.isEmpty else { return nil }

        let sampleCount = pcm.count / MemoryLayout<Int16>.size
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: clip.sampleRate,
            channels: 1,
            interleaved: false
        )!
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(sampleCount)
        ) else { return nil }

        buffer.frameLength = AVAudioFrameCount(sampleCount)
        guard let channel = buffer.floatChannelData?[0] else { return nil }

        pcm.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            let scale: Float = 1.0 / 32_768.0
            for i in 0..<sampleCount {
                channel[i] = Float(base[i]) * scale
            }
        }
        return buffer
    }
}
