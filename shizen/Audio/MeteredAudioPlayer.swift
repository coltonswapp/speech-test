//
//  MeteredAudioPlayer.swift
//  shizen
//
//  Loads each clip into PCM once, pre-analyzes its envelope, plays via
//  AVAudioPlayerNode, and drives visualizers from host-clock playback
//  time plus a live output tap.
//

import AVFoundation
import UIKit

/// RMS envelope for one audio clip, indexed by playback time.
struct PlaybackEnvelope {
    let levels: [Float]
    let interval: TimeInterval
    let peak: Float
    let duration: TimeInterval

    func level(at time: TimeInterval) -> Float {
        guard time >= 0, !levels.isEmpty else { return 0 }
        if time >= duration { return 0 }

        let position = time / interval
        let lower = Int(floor(position))
        if lower >= levels.count {
            return levels[levels.count - 1]
        }

        let upper = min(lower + 1, levels.count - 1)
        let fraction = Float(position - Double(lower))
        return levels[lower] * (1 - fraction) + levels[upper] * fraction
    }
}

final class MeteredAudioPlayer: NSObject {

    /// Main-thread updates: playback time, pre-analyzed envelope, live output level.
    var onPlaybackUpdate: ((_ time: TimeInterval, _ envelope: PlaybackEnvelope, _ liveLevel: Float) -> Void)?
    var onFinished: (() -> Void)?

    private(set) var isPlaying = false
    private(set) var currentEnvelope: PlaybackEnvelope?

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var isNodeAttached = false
    private var outputTapInstalled = false
    private var tempPlaybackURL: URL?
    private var scheduledPCM: AVAudioPCMBuffer?
    private var syncDisplayLink: CADisplayLink?

    private var playbackHostStart: CFTimeInterval?
    private var scheduledDuration: TimeInterval = 0
    private var currentLiveLevel: Float = 0
    /// Output device tail after the PCM buffer ends — keeps live meters alive through the last audible samples.
    private let playbackTailPadding: TimeInterval = 0.15

    /// Asset catalog names for the encouragement tutor clips.
    static let encouragementClipNames: [String] = (1...6).map {
        "eleven_labs-encouragement3.\($0)"
    }

    func play(assetNamed name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = NSDataAsset(name: trimmed)?.data else { return }

        stop()

        do {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("metered-\(UUID().uuidString).mp3")
            try data.write(to: tempURL)
            tempPlaybackURL = tempURL

            let loaded = try Self.loadClip(from: tempURL)
            currentEnvelope = loaded.envelope
            scheduledDuration = loaded.envelope.duration
            scheduledPCM = loaded.pcm
            currentLiveLevel = 0

            attachAndConnect(format: loaded.format)
            installOutputTap(format: loaded.format)

            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }

            playerNode.stop()
            playerNode.reset()
            playerNode.scheduleBuffer(loaded.pcm, at: nil, options: [])

            playbackHostStart = CACurrentMediaTime()
            playerNode.play()
            isPlaying = true
            startSyncDisplayLink()
        } catch {
            cleanupPlayback()
        }
    }

    func stop() {
        stopSyncDisplayLink()
        removeOutputTap()
        if playerNode.isPlaying {
            playerNode.stop()
        }
        playerNode.reset()
        if engine.isRunning {
            engine.stop()
        }
        cleanupPlayback()
    }

    // MARK: - Playback sync

    private func startSyncDisplayLink() {
        stopSyncDisplayLink()
        let link = CADisplayLink(target: self, selector: #selector(syncTick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        syncDisplayLink = link
    }

    private func stopSyncDisplayLink() {
        syncDisplayLink?.invalidate()
        syncDisplayLink = nil
    }

    @objc private func syncTick() {
        guard isPlaying, let envelope = currentEnvelope, let start = playbackHostStart else { return }

        let elapsed = CACurrentMediaTime() - start
        let time = min(max(0, elapsed), scheduledDuration)
        onPlaybackUpdate?(time, envelope, currentLiveLevel)

        if elapsed >= scheduledDuration + playbackTailPadding {
            finishPlayback()
        }
    }

    private func finishPlayback() {
        guard isPlaying else { return }

        if let envelope = currentEnvelope {
            onPlaybackUpdate?(scheduledDuration, envelope, 0)
        }

        playerNode.stop()
        cleanupPlayback()
        onFinished?()
    }

    private func cleanupPlayback() {
        isPlaying = false
        stopSyncDisplayLink()
        removeOutputTap()
        playbackHostStart = nil
        scheduledDuration = 0
        currentLiveLevel = 0
        scheduledPCM = nil
        currentEnvelope = nil
        removeTempFile()
    }

    // MARK: - Engine

    private func attachAndConnect(format: AVAudioFormat) {
        if !isNodeAttached {
            engine.attach(playerNode)
            isNodeAttached = true
        } else {
            engine.disconnectNodeOutput(playerNode)
            removeOutputTap()
        }
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

    private func installOutputTap(format: AVAudioFormat) {
        removeOutputTap()
        playerNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let level = Self.meterLevel(from: buffer)
            DispatchQueue.main.async {
                guard self.isPlaying else { return }
                self.currentLiveLevel = level
            }
        }
        outputTapInstalled = true
    }

    private func removeOutputTap() {
        guard outputTapInstalled else { return }
        playerNode.removeTap(onBus: 0)
        outputTapInstalled = false
    }

    private func removeTempFile() {
        guard let tempPlaybackURL else { return }
        try? FileManager.default.removeItem(at: tempPlaybackURL)
        self.tempPlaybackURL = nil
    }

    // MARK: - Load + analyze

    private struct LoadedClip {
        let pcm: AVAudioPCMBuffer
        let format: AVAudioFormat
        let envelope: PlaybackEnvelope
    }

    private static func loadClip(from url: URL) throws -> LoadedClip {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard file.length > 0 else {
            throw NSError(domain: "MeteredAudioPlayer", code: 1)
        }

        file.framePosition = 0
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw NSError(domain: "MeteredAudioPlayer", code: 2)
        }
        try file.read(into: pcm)
        guard pcm.frameLength > 0 else {
            throw NSError(domain: "MeteredAudioPlayer", code: 3)
        }

        let envelope = analyzeEnvelope(from: pcm)
        return LoadedClip(pcm: pcm, format: format, envelope: envelope)
    }

    private static func analyzeEnvelope(from pcm: AVAudioPCMBuffer) -> PlaybackEnvelope {
        let format = pcm.format
        let sampleRate = format.sampleRate
        let totalFrames = Int(pcm.frameLength)
        guard sampleRate > 0, totalFrames > 0 else {
            return PlaybackEnvelope(levels: [0], interval: 0.02, peak: 1, duration: 0)
        }

        let hop = max(64, min(512, totalFrames / 24))
        let window = min(totalFrames, max(hop * 2, 128))

        var levels: [Float] = []
        var peak: Float = 0
        levels.reserveCapacity(max(1, totalFrames / hop))

        var start = 0
        while start < totalFrames {
            let end = min(totalFrames, start + window)
            let shaped = shapedLevel(rms(in: pcm, start: start, end: end), peakIn: pcm, start: start, end: end)
            levels.append(shaped)
            peak = max(peak, shaped)
            start += hop
        }

        if levels.isEmpty {
            levels = [0]
        }

        if peak > 0.0001 {
            levels = levels.map { $0 / peak }
            peak = 1
        } else {
            peak = 1
        }

        let interval = Double(hop) / sampleRate
        let duration = Double(totalFrames) / sampleRate
        return PlaybackEnvelope(levels: levels, interval: interval, peak: peak, duration: duration)
    }

    private static func shapedLevel(_ rms: Float, peakIn buffer: AVAudioPCMBuffer, start: Int, end: Int) -> Float {
        let peak = peak(in: buffer, start: start, end: end)
        return min(1, pow(rms * 12, 0.78) * 0.55 + peak * 0.55)
    }

    private static func meterLevel(from buffer: AVAudioPCMBuffer) -> Float {
        shapedLevel(rms(in: buffer, start: 0, end: Int(buffer.frameLength)), peakIn: buffer, start: 0, end: Int(buffer.frameLength))
    }

    private static func rms(in buffer: AVAudioPCMBuffer, start: Int, end: Int) -> Float {
        let frameLength = end - start
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        var sampleCount = 0
        let channelCount = Int(buffer.format.channelCount)

        for channel in 0..<channelCount {
            for index in start..<end {
                let sample = sampleValue(in: buffer, frame: index, channel: channel)
                sum += sample * sample
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else { return 0 }
        return sqrtf(sum / Float(sampleCount))
    }

    private static func peak(in buffer: AVAudioPCMBuffer, start: Int, end: Int) -> Float {
        var peak: Float = 0
        let channelCount = Int(buffer.format.channelCount)

        for channel in 0..<channelCount {
            for index in start..<end {
                peak = max(peak, abs(sampleValue(in: buffer, frame: index, channel: channel)))
            }
        }

        return min(1, peak * 3.5)
    }

    private static func sampleValue(in buffer: AVAudioPCMBuffer, frame: Int, channel: Int) -> Float {
        if let channels = buffer.floatChannelData {
            return channels[channel][frame]
        }
        if let channels = buffer.int16ChannelData {
            return Float(channels[channel][frame]) / 32_768
        }
        if let channels = buffer.int32ChannelData {
            return Float(channels[channel][frame]) / 2_147_483_648
        }
        return 0
    }
}
