//
//  GrammarAudioPlayer.swift
//  shizen
//
//  Plays lesson audio from published CDN URLs or bundled clips; TTS fallback otherwise.
//  A single conversation clip can be split into per-line playback via proportional timing.
//

import AVFoundation
import QuartzCore
import TTSCore

enum GrammarAudioCatalog {

    /// Resolves `audioKey` (e.g. `n5-cha-ikenai/ex-0-scenario` or `train-station/buying-a-ticket`) to a bundled `.m4a` URL.
    static func bundledURL(for audioKey: String) -> URL? {
        let trimmed = audioKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let components = trimmed.split(separator: "/").map(String.init)
        guard components.count >= 2 else { return nil }

        let clipName = components[components.count - 1]
        let pointID = components.dropLast().joined(separator: "/")
        let levelFolder = pointID.split(separator: "-", maxSplits: 1).first.map(String.init) ?? "n5"

        let subdirectories = [
            "Resources/Grammar/Audio/\(levelFolder)/\(pointID)",
            "Grammar/Audio/\(levelFolder)/\(pointID)",
            "shizen/Resources/Grammar/Audio/\(levelFolder)/\(pointID)",
            "Audio/\(levelFolder)/\(pointID)",
            "Resources/Dialogue/Audio/\(pointID)",
            "Dialogue/Audio/\(pointID)",
            "shizen/Resources/Dialogue/Audio/\(pointID)",
        ]

        for subdirectory in subdirectories {
            if let url = Bundle.main.url(
                forResource: clipName,
                withExtension: "m4a",
                subdirectory: subdirectory
            ) {
                return url
            }
        }

        if let url = Bundle.main.url(forResource: clipName, withExtension: "m4a") {
            return url
        }

        return findResourceInBundle(clipName: clipName, pointID: pointID)
    }

    /// Returns a locally playable URL when already cached or bundled.
    static func resolveLocalURL(
        publishedAudioUrl: String?,
        audioKey: String?,
        cacheMetadata: RemoteAudioCacheMetadata? = nil
    ) -> URL? {
        if let remote = trimmedRemoteURL(from: publishedAudioUrl),
           let cached = RemoteAudioCache.cachedFileURL(for: remote, expected: cacheMetadata) {
            return cached
        }
        if let key = audioKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty,
           let bundled = bundledURL(for: key) {
            return bundled
        }
        return nil
    }

    /// Prefers published CDN audio, then bundled `audioKey`.
    static func ensureLocalURL(
        publishedAudioUrl: String?,
        audioKey: String?,
        cacheMetadata: RemoteAudioCacheMetadata? = nil,
        completion: @escaping (URL?) -> Void
    ) {
        if let local = resolveLocalURL(
            publishedAudioUrl: publishedAudioUrl,
            audioKey: audioKey,
            cacheMetadata: cacheMetadata
        ) {
            completion(local)
            return
        }
        guard let remote = trimmedRemoteURL(from: publishedAudioUrl) else {
            completion(nil)
            return
        }
        RemoteAudioCache.ensureLocalFile(for: remote, metadata: cacheMetadata) { result in
            switch result {
            case .success(let url):
                completion(url)
            case .failure:
                if let key = audioKey?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !key.isEmpty,
                   let bundled = bundledURL(for: key) {
                    completion(bundled)
                } else {
                    completion(nil)
                }
            }
        }
    }

    static func playbackCacheKey(publishedAudioUrl: String?, audioKey: String?) -> String {
        if let remote = trimmedRemoteURL(from: publishedAudioUrl) {
            return "remote:\(remote.absoluteString)"
        }
        return audioKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func trimmedRemoteURL(from publishedAudioUrl: String?) -> URL? {
        guard let raw = publishedAudioUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              url.scheme?.hasPrefix("http") == true else {
            return nil
        }
        return url
    }

    private static func findResourceInBundle(clipName: String, pointID: String) -> URL? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        let target = "\(clipName).m4a"
        let root = URL(fileURLWithPath: resourcePath)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return nil }

        var matches: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.lastPathComponent == target {
            matches.append(fileURL)
        }

        if matches.count == 1 {
            return matches[0]
        }
        if let preferred = matches.first(where: { $0.path.contains(pointID) }) {
            return preferred
        }
        return matches.first
    }
}

enum GrammarExampleDialogueLines {
    static func lines(for example: GrammarExample) -> [String] {
        guard let scenario = example.scenario, !scenario.lines.isEmpty else { return [] }
        return scenario.lines.filter(\.isSpokenLine).map(\.japanese)
    }
}

/// Plays lesson `.m4a` clips from CDN or bundle, referenced by `publishedAudioUrl` / `audioKey`.
final class GrammarAudioPlayer: NSObject, AVAudioPlayerDelegate {

    private struct PreparedClip {
        let url: URL
        let lines: [AlignedTimeLine]
    }

    private let fallbackSpeaker = WordUtteranceSpeaker()
    private var audioPlayer: AVAudioPlayer?
    private var preparedClip: PreparedClip?
    private var preparedCacheKey: String?
    private var clipPrepareGeneration = 0
    private var lineStopTimer: Timer?
    private var sequenceDisplayLink: CADisplayLink?
    private var sequenceStarts: [(index: Int, time: TimeInterval)] = []
    private var sequenceAnnounced: Set<Int> = []
    private var sequenceLineHandler: ((Int) -> Void)?
    private var timeHandler: ((TimeInterval) -> Void)?
    private var playbackCompletion: (() -> Void)?
    private var playbackRate: Float = 1

    func play(
        publishedAudioUrl: String? = nil,
        audioKey: String?,
        cacheMetadata: RemoteAudioCacheMetadata? = nil,
        dialogueLines: [String] = [],
        playLineIndex: Int? = nil,
        fallbackText: String,
        languageIdentifier: String = "ja-JP",
        onTime: ((TimeInterval) -> Void)? = nil,
        onFinished: (() -> Void)? = nil
    ) {
        playbackRate = 1
        timeHandler = onTime
        playbackCompletion = onFinished
        withLocalURLReadyForPlayback(
            publishedAudioUrl: publishedAudioUrl,
            audioKey: audioKey,
            cacheMetadata: cacheMetadata,
            dialogueLines: dialogueLines
        ) { [weak self] url, cacheKey in
            guard let self else { return }
            guard let url else {
                self.playFallback(fallbackText, languageIdentifier: languageIdentifier)
                return
            }

            if !dialogueLines.isEmpty,
               self.prepareClipIfNeeded(cacheKey: cacheKey, url: url, dialogueLines: dialogueLines),
               let clip = self.preparedClip {
                if let playLineIndex, clip.lines.indices.contains(playLineIndex) {
                    self.playTimeRange(clip.lines[playLineIndex].timeRange, url: url)
                    return
                }
                self.playTimeRange(0..<self.playerDuration(for: url), url: url)
                return
            }

            if self.playWholeFile(url: url) {
                self.fallbackSpeaker.stop()
            } else {
                self.playFallback(fallbackText, languageIdentifier: languageIdentifier)
            }
        }
    }

    func playDialogueLine(
        at index: Int,
        publishedAudioUrl: String? = nil,
        audioKey: String?,
        cacheMetadata: RemoteAudioCacheMetadata? = nil,
        dialogueLines: [String],
        fallbackText: String,
        onTime: ((TimeInterval) -> Void)? = nil,
        onFinished: (() -> Void)? = nil
    ) {
        play(
            publishedAudioUrl: publishedAudioUrl,
            audioKey: audioKey,
            cacheMetadata: cacheMetadata,
            dialogueLines: dialogueLines,
            playLineIndex: index,
            fallbackText: fallbackText,
            onTime: onTime,
            onFinished: onFinished
        )
    }

    /// Plays selected spoken lines as one continuous clip span — native gaps only,
    /// matching live Dialogue. Line callbacks follow `AVAudioPlayer.currentTime`.
    func playDialogueSequence(
        spokenIndices: [Int],
        publishedAudioUrl: String? = nil,
        audioKey: String?,
        cacheMetadata: RemoteAudioCacheMetadata? = nil,
        dialogueLines: [String],
        fallbackText: String,
        rate: Float = 1,
        onSpokenIndexStart: @escaping (Int) -> Void,
        onTime: ((TimeInterval) -> Void)? = nil,
        onFinished: (() -> Void)? = nil
    ) {
        playbackRate = rate
        timeHandler = onTime
        playbackCompletion = onFinished
        withLocalURLReadyForPlayback(
            publishedAudioUrl: publishedAudioUrl,
            audioKey: audioKey,
            cacheMetadata: cacheMetadata,
            dialogueLines: dialogueLines
        ) { [weak self] url, cacheKey in
            guard let self else { return }
            guard let url else {
                onSpokenIndexStart(spokenIndices.first ?? 0)
                self.playFallback(fallbackText, languageIdentifier: "ja-JP")
                return
            }
            guard !dialogueLines.isEmpty,
                  self.prepareClipIfNeeded(cacheKey: cacheKey, url: url, dialogueLines: dialogueLines),
                  let clip = self.preparedClip
            else {
                onSpokenIndexStart(spokenIndices.first ?? 0)
                self.playFallback(fallbackText, languageIdentifier: "ja-JP")
                return
            }

            let items: [(index: Int, range: Range<TimeInterval>)] = spokenIndices.compactMap { index in
                guard clip.lines.indices.contains(index) else { return nil }
                return (index, clip.lines[index].timeRange)
            }
            guard let first = items.first, let last = items.last else {
                onSpokenIndexStart(spokenIndices.first ?? 0)
                self.playFallback(fallbackText, languageIdentifier: "ja-JP")
                return
            }

            self.sequenceLineHandler = onSpokenIndexStart
            self.sequenceStarts = items.map { ($0.index, $0.range.lowerBound) }
            self.sequenceAnnounced = []
            self.playTimeRange(
                first.range.lowerBound..<last.range.upperBound,
                url: url,
                stopWhenDone: true
            )
            self.announceSequenceLines(at: self.audioPlayer?.currentTime ?? first.range.lowerBound)
            self.startTimeTicksIfNeeded()
        }
    }

    func stop() {
        clipPrepareGeneration += 1
        performOnMain { [weak self] in
            guard let self else { return }
            self.lineStopTimer?.invalidate()
            self.lineStopTimer = nil
            self.clearSequenceTracking()
            self.audioPlayer?.stop()
            self.audioPlayer = nil
            self.fallbackSpeaker.stop()
            self.playbackCompletion = nil
            self.timeHandler = nil
            self.playbackRate = 1
        }
    }

    private func clearSequenceTracking() {
        sequenceDisplayLink?.invalidate()
        sequenceDisplayLink = nil
        sequenceStarts = []
        sequenceAnnounced = []
        sequenceLineHandler = nil
    }

    @objc private func handleSequenceTick() {
        guard let player = audioPlayer else { return }
        announceSequenceLines(at: player.currentTime)
        timeHandler?(player.currentTime)
    }

    private func startTimeTicksIfNeeded() {
        guard sequenceDisplayLink == nil else { return }
        guard timeHandler != nil || sequenceLineHandler != nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(handleSequenceTick))
        link.add(to: .main, forMode: .common)
        sequenceDisplayLink = link
    }

    private func announceSequenceLines(at time: TimeInterval) {
        for item in sequenceStarts where !sequenceAnnounced.contains(item.index) && time + 0.03 >= item.time {
            sequenceAnnounced.insert(item.index)
            sequenceLineHandler?(item.index)
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        notifyPlaybackFinished()
    }

    private func notifyPlaybackFinished() {
        clearSequenceTracking()
        guard let completion = playbackCompletion else { return }
        playbackCompletion = nil
        completion()
    }

    // MARK: - Segmented playback

    /// Resolves the file, then waits for alignment metadata without blocking main.
    /// `body` always runs on the main queue.
    private func withLocalURLReadyForPlayback(
        publishedAudioUrl: String?,
        audioKey: String?,
        cacheMetadata: RemoteAudioCacheMetadata?,
        dialogueLines: [String],
        body: @escaping (_ url: URL?, _ cacheKey: String) -> Void
    ) {
        clipPrepareGeneration += 1
        let generation = clipPrepareGeneration
        let cacheKey = GrammarAudioCatalog.playbackCacheKey(
            publishedAudioUrl: publishedAudioUrl,
            audioKey: audioKey
        )
        GrammarAudioCatalog.ensureLocalURL(
            publishedAudioUrl: publishedAudioUrl,
            audioKey: audioKey,
            cacheMetadata: cacheMetadata
        ) { [weak self] url in
            guard let self, self.clipPrepareGeneration == generation else { return }
            self.performOnMain {
                guard self.clipPrepareGeneration == generation else { return }
                self.clearSequenceTracking()

                let finish = {
                    guard self.clipPrepareGeneration == generation else { return }
                    body(url, cacheKey)
                }

                guard let url, !dialogueLines.isEmpty,
                      !self.isClipPrepared(cacheKey: cacheKey, url: url, dialogueLines: dialogueLines)
                else {
                    finish()
                    return
                }

                DialogueAlignmentMetadata.readPayload(from: url) { _ in
                    finish()
                }
            }
        }
    }

    private func isClipPrepared(cacheKey: String, url: URL, dialogueLines: [String]) -> Bool {
        let normalizedDialogue = dialogueLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return preparedCacheKey == cacheKey
            && preparedClip?.url == url
            && preparedClip?.lines.map(\.text) == normalizedDialogue
    }

    @discardableResult
    private func prepareClipIfNeeded(cacheKey: String, url: URL, dialogueLines: [String]) -> Bool {
        if isClipPrepared(cacheKey: cacheKey, url: url, dialogueLines: dialogueLines) {
            return true
        }

        let duration = playerDuration(for: url)
        guard duration > 0 else { return false }

        let aligned: [AlignedTimeLine]
        if let embedded = DialogueAlignmentMetadata.readLineSwitchSeconds(from: url),
           let fromMetadata = DialogueAlignmentMetadata.segmentTimeRanges(
               lineTexts: dialogueLines,
               duration: duration,
               lineSwitchSeconds: embedded
           ) {
            aligned = fromMetadata
        } else {
            let pcm = try? TTSAudioFileLoader.loadMonoFloatSamples(from: url)
            aligned = TTSAudioAlignment.segmentTimeRanges(
                lineTexts: dialogueLines,
                duration: duration,
                samples: pcm?.samples,
                sampleRate: pcm?.sampleRate ?? 24_000
            )
        }
        guard !aligned.isEmpty else { return false }

        preparedCacheKey = cacheKey
        preparedClip = PreparedClip(url: url, lines: aligned)
        return true
    }

    private func playerDuration(for url: URL) -> TimeInterval {
        if let audioPlayer, audioPlayer.url == url, audioPlayer.duration > 0 {
            return audioPlayer.duration
        }
        guard let player = makePlayer(url: url), player.duration > 0 else { return 0 }
        return player.duration
    }

    private func playTimeRange(
        _ range: Range<TimeInterval>,
        url: URL,
        stopWhenDone: Bool = true
    ) {
        lineStopTimer?.invalidate()
        lineStopTimer = nil
        fallbackSpeaker.stop()

        guard let player = makePlayer(url: url) else { return }

        do {
            try PlaybackAudioSession.activateForPlayback()
        } catch {
            return
        }

        let start = max(0, range.lowerBound)
        let end = min(player.duration, range.upperBound)
        guard end > start else { return }

        player.enableRate = true
        let rate = max(0.5, min(2.0, playbackRate))
        player.rate = rate
        player.currentTime = start
        player.play()
        startTimeTicksIfNeeded()

        let wallDuration = (end - start) / TimeInterval(rate)
        lineStopTimer = Timer.scheduledTimer(withTimeInterval: wallDuration, repeats: false) { [weak self] _ in
            if stopWhenDone {
                player.stop()
            }
            self?.lineStopTimer = nil
            self?.notifyPlaybackFinished()
        }
    }

    // MARK: - Whole-file playback

    @discardableResult
    private func playWholeFile(url: URL) -> Bool {
        lineStopTimer?.invalidate()
        lineStopTimer = nil
        fallbackSpeaker.stop()

        guard let player = makePlayer(url: url) else { return false }

        do {
            try PlaybackAudioSession.activateForPlayback()
            player.enableRate = true
            player.rate = 1
            player.currentTime = 0
            player.play()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    private func makePlayer(url: URL) -> AVAudioPlayer? {
        if let audioPlayer, audioPlayer.url == url {
            audioPlayer.enableRate = true
            return audioPlayer
        }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.delegate = self
        player.enableRate = true
        player.prepareToPlay()
        audioPlayer = player
        return player
    }

    private func playFallback(_ text: String, languageIdentifier: String) {
        lineStopTimer?.invalidate()
        lineStopTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        fallbackSpeaker.speak(text, languageIdentifier: languageIdentifier)
        // AVSpeechSynthesizer has no completion here — approximate so Listen & Repeat can proceed.
        let estimated = max(0.8, Double(text.count) * 0.12)
        DispatchQueue.main.asyncAfter(deadline: .now() + estimated) { [weak self] in
            self?.notifyPlaybackFinished()
        }
    }

    private func performOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
