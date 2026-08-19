//
//  WordUtteranceSpeaker.swift
//  shizen
//
//  On-device pronunciation via AVSpeechSynthesizer (no network).
//

import AVFoundation

/// On-device `AVSpeechSynthesizer`; stops any in-flight utterance before starting a new one.
///
/// Activates ``AVAudioSession`` for playback with ``.mixWithOthers`` so background audio
/// (podcasts, music) keeps playing. When a tutor capture session is already active
/// (``.playAndRecord``), only reactivates that session so the mic stays live.
final class WordUtteranceSpeaker: NSObject {

    /// Created on first speak — AVSpeechSynthesizer init blocks on a speech-service
    /// XPC handshake, which stalls push transitions on screens that construct
    /// speakers eagerly (sentence scrub builds three of them via nested views).
    private var loadedSynthesizer: AVSpeechSynthesizer?

    private var synthesizer: AVSpeechSynthesizer {
        if let loadedSynthesizer { return loadedSynthesizer }
        let created = AVSpeechSynthesizer()
        loadedSynthesizer = created
        return created
    }

    /// Only match **the same locale tag** (`ja‑JP`, `en‑US`, …). Treating everything with language `ja` as
    /// interchangeable can hand `speak(languageIdentifier: "ja‑JP")` a `ja‑CN`/other‑region premium voice —
    /// that often reads worse even though `quality == .premium`.
    private static func normalizedLocaleTag(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: "-")
    }

    private static func localeMatches(identifier: String, voice: AVSpeechSynthesisVoice) -> Bool {
        normalizedLocaleTag(voice.language) == normalizedLocaleTag(identifier)
    }

    /// Larger rank = fancier downloadable pack (`premium` / `enhanced`); unchanged entries stay `.default`.
    private static func qualityRank(_ voice: AVSpeechSynthesisVoice) -> Int {
        switch voice.quality {
        case .premium: return 3
        case .enhanced: return 2
        case .default: return 1
        @unknown default:
            let id = voice.identifier.lowercased()
            if id.contains("premium") { return 3 }
            if id.contains("enhanced") { return 2 }
            return 1
        }
    }

    /// Installed voices for this **exact** locale tag, best quality first.
    static func rankedVoices(languageIdentifier identifier: String) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { localeMatches(identifier: identifier, voice: $0) }
            .sorted {
                let dq = qualityRank($0) - qualityRank($1)
                if dq != 0 { return dq > 0 }
                return $0.identifier < $1.identifier
            }
    }

    /// Installed voices for this **exact** locale tag. Among them, prefers a higher `quality`
    /// (downloaded `.premium` / `.enhanced`). If there's no upgrade vs `AVSpeechSynthesisVoice(language:)`,
    /// keeps Apple's default voicing for that locale.
    static func resolvedVoice(identifier: String) -> AVSpeechSynthesisVoice? {
        let tiered = rankedVoices(languageIdentifier: identifier)
        let baseline = AVSpeechSynthesisVoice(language: identifier)
        guard let best = tiered.first else {
            return baseline ?? AVSpeechSynthesisVoice.speechVoices().first { localeMatches(identifier: identifier, voice: $0) }
        }
        guard let baseline else { return best }
        if qualityRank(best) > qualityRank(baseline) {
            return best
        }
        return baseline
    }

    private func performOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func stopImmediately() {
        guard let loadedSynthesizer, loadedSynthesizer.isSpeaking else { return }
        loadedSynthesizer.stopSpeaking(at: .immediate)
    }

    func speak(_ text: String, languageIdentifier: String = "ja-JP") {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        performOnMain { [weak self] in
            guard let self else { return }

            stopImmediately()

            do {
                try PlaybackAudioSession.activateForPlayback()
            } catch {
                // Session may already match; still enqueue speech.
            }

            let utterance = AVSpeechUtterance(string: trimmed)
            utterance.voice = Self.resolvedVoice(identifier: languageIdentifier)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate

            synthesizer.speak(utterance)
        }
    }

    func stop() {
        performOnMain { [weak self] in
            self?.stopImmediately()
        }
    }
}
