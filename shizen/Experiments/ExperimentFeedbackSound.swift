//
//  ExperimentFeedbackSound.swift
//  shizen
//
//  Plays bundled experiment feedback sounds using ``ExperimentFeedbackSoundCatalog``.
//

import AVFoundation
import UIKit

enum ExperimentFeedbackSound {
    private static let player = Player()
    private static let clickPlayer = ClickPlayer()
    private static let dragHoverClickEngine = DragHoverClickEngine()
    private static var durationCache: [String: TimeInterval] = [:]

    private static var canPlay: Bool { ExperimentSettings.soundsEnabled }

    struct PreparedSuccessSound: Equatable {
        let chime: ExperimentSuccessChime
        let assetName: String
        let duration: TimeInterval
    }

    /// All bundled feedback sounds, for debug preview.
    static var allAssetNames: [String] {
        ExperimentSuccessChime.allCases.map(\.assetName)
            + [
                ExperimentFeedbackSoundCatalog.clickAsset,
                ExperimentFeedbackSoundCatalog.incorrectAsset,
                ExperimentFeedbackSoundCatalog.lessonCompleteAsset,
            ]
    }

    static func prepareSuccess(
        for exercise: ExperimentFeedbackExercise,
        spellingSyllableCount: Int? = nil
    ) -> PreparedSuccessSound {
        let chime = ExperimentFeedbackSoundCatalog.successChime(
            for: exercise,
            spellingSyllableCount: spellingSyllableCount
        )
        return PreparedSuccessSound(
            chime: chime,
            assetName: chime.assetName,
            duration: duration(forAssetNamed: chime.assetName)
        )
    }

    static func playSuccess(
        for exercise: ExperimentFeedbackExercise,
        spellingSyllableCount: Int? = nil
    ) {
        playPreparedSuccessSound(prepareSuccess(for: exercise, spellingSyllableCount: spellingSyllableCount))
    }

    static func playPreparedSuccessSound(_ prepared: PreparedSuccessSound) {
        guard canPlay else { return }
        player.play(assetNamed: prepared.assetName)
    }

    static func playIncorrect() {
        guard canPlay else { return }
        player.play(assetNamed: ExperimentFeedbackSoundCatalog.incorrectAsset)
    }

    static func playLessonComplete(completion: (() -> Void)? = nil) {
        guard canPlay else {
            completion?()
            return
        }
        player.play(
            assetNamed: ExperimentFeedbackSoundCatalog.lessonCompleteAsset,
            volume: ExperimentFeedbackSoundCatalog.lessonCompleteVolume,
            completion: completion
        )
    }

    static func playClick() {
        guard canPlay else { return }
        clickPlayer.play(
            assetNamed: ExperimentFeedbackSoundCatalog.clickAsset,
            volume: ExperimentFeedbackSoundCatalog.clickVolume
        )
    }

    /// Warms the click player so the first tap is not lost to AVAudioPlayer startup latency.
    static func prepareClick() {
        clickPlayer.prepare(assetNamed: ExperimentFeedbackSoundCatalog.clickAsset)
    }

    /// Preloads a PCM buffer for drag-hover clicks (SystemSound only supports caf/wav/aiff, not m4a).
    static func prepareDragHoverClick() {
        dragHoverClickEngine.prepare(assetNamed: ExperimentFeedbackSoundCatalog.clickAsset)
    }

    static func playDragHoverClick() {
        guard canPlay else { return }
        dragHoverClickEngine.play(volume: ExperimentFeedbackSoundCatalog.clickVolume)
    }

    static func playPreview(assetNamed name: String) {
        guard canPlay else { return }
        player.play(assetNamed: name)
    }

    static func duration(forAssetNamed name: String) -> TimeInterval {
        if let cached = durationCache[name] {
            return cached
        }
        guard let data = NSDataAsset(name: name)?.data,
              let audioPlayer = try? AVAudioPlayer(data: data) else {
            return 0
        }
        let duration = audioPlayer.duration
        durationCache[name] = duration
        return duration
    }

    private static func clickAssetCacheURL() -> URL? {
        guard let data = NSDataAsset(name: ExperimentFeedbackSoundCatalog.clickAsset)?.data else {
            return nil
        }
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(ExperimentFeedbackSoundCatalog.clickAsset).m4a")
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                return nil
            }
        }
        return url
    }

    /// Preloaded AVAudioEngine path for rapid drag-hover clicks — lighter than AVAudioPlayer per crossing.
    private final class DragHoverClickEngine {
        private let engine = AVAudioEngine()
        private let playerNode = AVAudioPlayerNode()
        private var sourceBuffer: AVAudioPCMBuffer?
        private var playbackBuffer: AVAudioPCMBuffer?
        private var isRunning = false

        func prepare(assetNamed name: String) {
            guard sourceBuffer == nil else { return }
            guard let url = clickAssetCacheURL() else { return }

            do {
                let file = try AVAudioFile(forReading: url)
                let frameCount = AVAudioFrameCount(file.length)
                guard let pcmBuffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: frameCount
                ) else { return }
                try file.read(into: pcmBuffer)

                engine.attach(playerNode)
                engine.connect(playerNode, to: engine.mainMixerNode, format: file.processingFormat)

                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try engine.start()

                sourceBuffer = pcmBuffer
                playbackBuffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: frameCount
                )
                isRunning = true
            } catch {
                sourceBuffer = nil
                playbackBuffer = nil
                isRunning = false
            }
        }

        func play(volume: Float) {
            guard isRunning,
                  let sourceBuffer,
                  let playbackBuffer,
                  let scaled = Self.scaledCopy(
                    from: sourceBuffer,
                    into: playbackBuffer,
                    volume: volume
                  )
            else { return }

            if playerNode.isPlaying {
                playerNode.stop()
            }
            playerNode.scheduleBuffer(scaled, at: nil, options: .interrupts, completionHandler: nil)
            playerNode.play()
        }

        private static func scaledCopy(
            from source: AVAudioPCMBuffer,
            into destination: AVAudioPCMBuffer,
            volume: Float
        ) -> AVAudioPCMBuffer? {
            guard let sourceChannels = source.floatChannelData,
                  let destinationChannels = destination.floatChannelData
            else { return nil }

            let frameLength = Int(source.frameLength)
            let channelCount = Int(source.format.channelCount)
            guard frameLength > 0, channelCount > 0 else { return nil }

            destination.frameLength = source.frameLength
            for channel in 0 ..< channelCount {
                let input = sourceChannels[channel]
                let output = destinationChannels[channel]
                for frame in 0 ..< frameLength {
                    output[frame] = input[frame] * volume
                }
            }
            return destination
        }
    }

    private final class Player: NSObject, AVAudioPlayerDelegate {
        private var audioPlayer: AVAudioPlayer?
        private var playbackCompletion: (() -> Void)?

        func play(assetNamed name: String, volume: Float = 1, completion: (() -> Void)? = nil) {
            performOnMain { [weak self] in
                self?.playBundled(assetNamed: name, volume: volume, completion: completion)
            }
        }

        private func playBundled(assetNamed name: String, volume: Float, completion: (() -> Void)?) {
            guard let data = NSDataAsset(name: name)?.data else {
                completion?()
                return
            }

            if let oldPlayer = audioPlayer {
                oldPlayer.delegate = nil
                oldPlayer.stop()
            }
            audioPlayer = nil
            playbackCompletion = completion

            do {
                try activateSession()
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                player.volume = volume
                audioPlayer = player
                player.prepareToPlay()
                player.play()
            } catch {
                audioPlayer = nil
                playbackCompletion = nil
                completion?()
            }
        }

        private func activateSession() throws {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        }

        private func performOnMain(_ work: @escaping () -> Void) {
            if Thread.isMainThread {
                work()
            } else {
                DispatchQueue.main.async(execute: work)
            }
        }

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            if audioPlayer === player {
                audioPlayer = nil
                playbackCompletion?()
                playbackCompletion = nil
            }
        }
    }

    /// Keeps one prepared player for the short UI click so ~30 ms clips are not skipped.
    private final class ClickPlayer: NSObject, AVAudioPlayerDelegate {
        private var audioPlayer: AVAudioPlayer?
        private var loadedAssetName: String?
        private var didActivateSession = false

        func prepare(assetNamed name: String) {
            performOnMain { [weak self] in
                self?.ensureLoaded(assetNamed: name)
            }
        }

        func play(assetNamed name: String, volume: Float) {
            performOnMain { [weak self] in
                guard let self, self.ensureLoaded(assetNamed: name) else { return }
                audioPlayer?.volume = volume
                audioPlayer?.currentTime = 0
                audioPlayer?.play()
            }
        }

        @discardableResult
        private func ensureLoaded(assetNamed name: String) -> Bool {
            if loadedAssetName == name, audioPlayer != nil {
                return true
            }

            guard let data = NSDataAsset(name: name)?.data else { return false }

            do {
                try activateSessionIfNeeded()
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                player.volume = ExperimentFeedbackSoundCatalog.clickVolume
                player.prepareToPlay()
                audioPlayer = player
                loadedAssetName = name
                return true
            } catch {
                audioPlayer = nil
                loadedAssetName = nil
                return false
            }
        }

        private func activateSessionIfNeeded() throws {
            guard !didActivateSession else { return }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
            didActivateSession = true
        }

        private func performOnMain(_ work: @escaping () -> Void) {
            if Thread.isMainThread {
                work()
            } else {
                DispatchQueue.main.async(execute: work)
            }
        }

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            // Keep the prepared player around for the next tap.
        }
    }
}
