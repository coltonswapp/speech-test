//
//  KanaPronunciationPlayer.swift
//  shizen
//
//  Bundled kana recordings from the asset catalog, with TTS fallback.
//

import AVFoundation
import UIKit

/// Plays catalogued kana audio when available; otherwise uses ``WordUtteranceSpeaker``.
final class KanaPronunciationPlayer: NSObject, AVAudioPlayerDelegate {

    private var audioPlayer: AVAudioPlayer?
    private let fallbackSpeaker = WordUtteranceSpeaker()

    /// Kana glyph → `jpt_{romaji}` data set name in `Assets.xcassets/jpt_kana-audio`.
    private static let bundledAssetByKana: [String: String] = {
        var map: [String: String] = [:]
        for glyph in KanaCurriculum.allGlyphs(script: .hiragana) {
            let assetName = "jpt_\(glyph.romaji)"
            map[glyph.kana] = assetName
            if let katakana = (glyph.kana as NSString).applyingTransform(.hiraganaToKatakana, reverse: false) {
                map[katakana] = assetName
            }
        }
        return map
    }()

    /// Plays a bundled audio data set from the asset catalog by name (e.g. `arigatou_marin`).
    func play(assetNamed name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = NSDataAsset(name: trimmed)?.data else { return }

        performOnMain { [weak self] in
            guard let self else { return }
            if self.playBundled(data: data) {
                self.fallbackSpeaker.stop()
            }
        }
    }

    func play(kana: String, languageIdentifier: String = "ja-JP") {
        let trimmed = kana.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        performOnMain { [weak self] in
            guard let self else { return }

            if let assetName = Self.bundledAssetByKana[trimmed],
               let data = NSDataAsset(name: assetName)?.data,
               self.playBundled(data: data) {
                self.fallbackSpeaker.stop()
                return
            }

            self.stopBundled()
            self.fallbackSpeaker.speak(trimmed, languageIdentifier: languageIdentifier)
        }
    }

    func stop() {
        performOnMain { [weak self] in
            self?.stopBundled()
            self?.fallbackSpeaker.stop()
        }
    }

    // MARK: - Bundled audio

    @discardableResult
    private func playBundled(data: Data) -> Bool {
        stopBundled()
        do {
            try PlaybackAudioSession.activateForPlayback()
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            audioPlayer = player
            player.prepareToPlay()
            player.play()
            return true
        } catch {
            return false
        }
    }

    private func stopBundled() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    private func performOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if audioPlayer === player {
            audioPlayer = nil
        }
    }
}
