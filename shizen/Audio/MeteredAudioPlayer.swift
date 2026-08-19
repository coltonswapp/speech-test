//
//  MeteredAudioPlayer.swift
//  shizen
//
//  Loads each clip into PCM once, pre-analyzes its envelope, plays via
//  AVAudioPlayerNode, and drives visualizers from player-node playback
//  time plus a low-latency live output tap (level history + spectral bands).
//

import Accelerate
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

/// One display-link metering frame from ``MeteredAudioPlayer``.
struct PlaybackMeterFrame {
    let time: TimeInterval
    let envelope: PlaybackEnvelope
    let liveLevel: Float
    /// Recent live levels, oldest → newest (tap cadence).
    let liveHistory: [Float]
    /// Five spectral energy bands from the latest tap window, low → high.
    let bands: [Float]
}

final class MeteredAudioPlayer: NSObject {

    /// Main-thread updates driven by CADisplayLink.
    var onPlaybackUpdate: ((PlaybackMeterFrame) -> Void)?
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
    /// Output device tail after the PCM buffer ends — keeps live meters alive through the last audible samples.
    private let playbackTailPadding: TimeInterval = 0.15
    /// Invalidates in-flight session activation when play/stop races.
    private var playGeneration = 0

    private let meterLock = NSLock()
    private var lockedLiveLevel: Float = 0
    private var lockedLiveHistory: [Float] = []
    private var lockedBands: [Float] = Array(repeating: 0, count: MeteredAudioPlayer.bandCount)
    /// EMA state kept on the audio thread so published levels don't jump tap-to-tap.
    private var smoothedLiveLevel: Float = 0
    private var smoothedBands: [Float] = Array(repeating: 0, count: MeteredAudioPlayer.bandCount)
    private let liveHistoryCapacity = 24
    private let spectralAnalyzer = SpectralBandAnalyzer(bandCount: MeteredAudioPlayer.bandCount)

    static let bandCount = 5

    /// Asset catalog names for the encouragement tutor clips.
    static let encouragementClipNames: [String] = (1...6).map {
        "eleven_labs-encouragement3.\($0)"
    }

    func play(assetNamed name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = NSDataAsset(name: trimmed)?.data else { return }

        stop()
        playGeneration += 1
        let generation = playGeneration

        PlaybackAudioSession.activateForPlayback { [weak self] _ in
            guard let self, self.playGeneration == generation else { return }
            self.startPlayback(data: data)
        }
    }

    private func startPlayback(data: Data) {
        do {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("metered-\(UUID().uuidString).mp3")
            try data.write(to: tempURL)
            tempPlaybackURL = tempURL

            let loaded = try Self.loadClip(from: tempURL)
            currentEnvelope = loaded.envelope
            scheduledDuration = loaded.envelope.duration
            scheduledPCM = loaded.pcm
            resetMeterState()

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
        playGeneration += 1
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
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        syncDisplayLink = link
    }

    private func stopSyncDisplayLink() {
        syncDisplayLink?.invalidate()
        syncDisplayLink = nil
    }

    @objc private func syncTick() {
        guard isPlaying, let envelope = currentEnvelope else { return }

        let time = currentPlaybackTime()
        let snapshot = readMeterSnapshot()
        onPlaybackUpdate?(PlaybackMeterFrame(
            time: time,
            envelope: envelope,
            liveLevel: snapshot.level,
            liveHistory: snapshot.history,
            bands: snapshot.bands
        ))

        if let start = playbackHostStart,
           CACurrentMediaTime() - start >= scheduledDuration + playbackTailPadding {
            finishPlayback()
        }
    }

    private func currentPlaybackTime() -> TimeInterval {
        if let nodeTime = playerNode.lastRenderTime,
           nodeTime.isSampleTimeValid,
           let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
           playerTime.sampleRate > 0 {
            let seconds = Double(playerTime.sampleTime) / playerTime.sampleRate
            return min(max(0, seconds), scheduledDuration)
        }

        guard let start = playbackHostStart else { return 0 }
        return min(max(0, CACurrentMediaTime() - start), scheduledDuration)
    }

    private func finishPlayback() {
        guard isPlaying else { return }

        if let envelope = currentEnvelope {
            onPlaybackUpdate?(PlaybackMeterFrame(
                time: scheduledDuration,
                envelope: envelope,
                liveLevel: 0,
                liveHistory: [],
                bands: Array(repeating: 0, count: Self.bandCount)
            ))
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
        resetMeterState()
        scheduledPCM = nil
        currentEnvelope = nil
        removeTempFile()
    }

    private func resetMeterState() {
        meterLock.lock()
        lockedLiveLevel = 0
        lockedLiveHistory.removeAll(keepingCapacity: true)
        lockedBands = Array(repeating: 0, count: Self.bandCount)
        smoothedLiveLevel = 0
        smoothedBands = Array(repeating: 0, count: Self.bandCount)
        meterLock.unlock()
    }

    private struct MeterSnapshot {
        let level: Float
        let history: [Float]
        let bands: [Float]
    }

    private func readMeterSnapshot() -> MeterSnapshot {
        meterLock.lock()
        let snapshot = MeterSnapshot(
            level: lockedLiveLevel,
            history: lockedLiveHistory,
            bands: lockedBands
        )
        meterLock.unlock()
        return snapshot
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
        let analyzer = spectralAnalyzer
        let historyCapacity = liveHistoryCapacity
        // ~23ms tap windows at 44.1k / 1024. Light de-noise only — the bar views
        // own the perceptual attack/release, so heavy smoothing here just adds lag.
        let attack: Float = 0.7
        let release: Float = 0.35
        playerNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let rawLevel = Self.meterLevel(from: buffer)
            let rawBands = analyzer.bands(from: buffer)

            self.meterLock.lock()
            let levelAlpha = rawLevel > self.smoothedLiveLevel ? attack : release
            self.smoothedLiveLevel += (rawLevel - self.smoothedLiveLevel) * levelAlpha
            for i in 0..<Self.bandCount {
                let sample = i < rawBands.count ? rawBands[i] : 0
                let bandAlpha = sample > self.smoothedBands[i] ? attack : release
                self.smoothedBands[i] += (sample - self.smoothedBands[i]) * bandAlpha
            }

            let level = self.smoothedLiveLevel
            let bands = self.smoothedBands
            self.lockedLiveLevel = level
            self.lockedLiveHistory.append(level)
            if self.lockedLiveHistory.count > historyCapacity {
                self.lockedLiveHistory.removeFirst(self.lockedLiveHistory.count - historyCapacity)
            }
            self.lockedBands = bands
            self.meterLock.unlock()
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
        // RMS-led with a light peak hint — avoid slamming into the ceiling on every plosive.
        let blended = pow(max(0, rms) * 7.5, 0.92) * 0.78 + peak * 0.22
        return softKnee(blended)
    }

    private static func meterLevel(from buffer: AVAudioPCMBuffer) -> Float {
        shapedLevel(rms(in: buffer, start: 0, end: Int(buffer.frameLength)), peakIn: buffer, start: 0, end: Int(buffer.frameLength))
    }

    /// Compresses highs so meters live in the mid range instead of pinning at 1.
    fileprivate static func softKnee(_ value: Float) -> Float {
        let x = max(0, value)
        return min(1, x / (x + 0.85))
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

        return min(1, peak * 1.8)
    }

    fileprivate static func sampleValue(in buffer: AVAudioPCMBuffer, frame: Int, channel: Int) -> Float {
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

// MARK: - Spectral bands

/// Lightweight FFT meter that folds magnitude energy into a few speech-ish bands.
private final class SpectralBandAnalyzer {
    private let bandCount: Int
    private let fftLength = 1024
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup?
    private var window: [Float]
    private var mono: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var magnitudes: [Float]

    init(bandCount: Int) {
        let length = 1024
        self.bandCount = bandCount
        log2n = vDSP_Length(log2(Float(length)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        window = [Float](unsafeUninitializedCapacity: length) { buffer, count in
            vDSP_hann_window(buffer.baseAddress!, vDSP_Length(length), Int32(vDSP_HANN_NORM))
            count = length
        }
        mono = Array(repeating: 0, count: length)
        realp = Array(repeating: 0, count: length / 2)
        imagp = Array(repeating: 0, count: length / 2)
        magnitudes = Array(repeating: 0, count: length / 2)
    }

    deinit {
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    func bands(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let fftSetup else {
            return Array(repeating: 0, count: bandCount)
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            return Array(repeating: 0, count: bandCount)
        }

        let channelCount = Int(buffer.format.channelCount)
        let copyCount = min(frameCount, fftLength)
        for i in 0..<copyCount {
            var sum: Float = 0
            for channel in 0..<channelCount {
                sum += MeteredAudioPlayer.sampleValue(in: buffer, frame: i, channel: channel)
            }
            mono[i] = sum / Float(max(channelCount, 1))
        }
        if copyCount < fftLength {
            for i in copyCount..<fftLength {
                mono[i] = 0
            }
        }

        vDSP_vmul(mono, 1, window, 1, &mono, 1, vDSP_Length(fftLength))

        realp.withUnsafeMutableBufferPointer { realBuf in
            imagp.withUnsafeMutableBufferPointer { imagBuf in
                var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                mono.withUnsafeBufferPointer { monoBuf in
                    monoBuf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftLength / 2) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(fftLength / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(fftLength / 2))
            }
        }

        let sampleRate = max(1, buffer.format.sampleRate)
        let binHz = sampleRate / Double(fftLength)
        // Speech-oriented edges (Hz).
        let edges: [Double] = [80, 300, 800, 1_800, 4_000, min(sampleRate / 2, 12_000)]

        var bands = Array(repeating: Float(0), count: bandCount)
        for band in 0..<bandCount {
            let lo = max(1, Int((edges[band] / binHz).rounded(.down)))
            let hi = min(magnitudes.count - 1, Int((edges[band + 1] / binHz).rounded(.up)))
            guard hi > lo else { continue }

            var energy: Float = 0
            for bin in lo..<hi {
                energy += magnitudes[bin]
            }
            // Fixed gain + soft knee — no per-frame peak normalize (that made a band always hit 1).
            let mean = energy / Float(hi - lo)
            bands[band] = MeteredAudioPlayer.softKnee(pow(mean * 4.5, 0.55))
        }
        return bands
    }
}
