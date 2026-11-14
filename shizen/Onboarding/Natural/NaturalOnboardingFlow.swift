//
//  NaturalOnboardingFlow.swift
//  shizen
//
//  Session, audio, and shared content behind the listen-first flow's Hana steps.
//
//  Audio: every clip has a stable name (see `NaturalClip`). Drop a matching
//  .m4a/.mp3/.wav into the app bundle and it plays instead of on-device TTS.
//  Nothing is persisted and no auth runs.
//

import AVFoundation
import TTSCore
import UIKit

enum NaturalOnboardingFlow {
    /// `step_name` for the team-note screen before the paywall (SHZ-40).
    static let teamNoteStepId = "team_note"
}

/// Adds the gist result and the promise to the session's name, level, and pacing answers.
/// Subclassed by the listen-first v2 session, which persists answers and names tracks differently.
class NaturalOnboardingSession: TutorOnboardingSession {
    /// Whether the first blind listen caught the gist; nil until answered.
    var caughtGist: Bool?
    var promised = false

    var track: String { level.track }
}

/// Base for steps that aren't reused from the tutor flow; keeps a typed handle on the session.
class NaturalStepViewController: TutorStepViewController {

    let natural: NaturalOnboardingSession

    init(session: NaturalOnboardingSession) {
        natural = session
        super.init(session: session)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension TutorLevel {
    /// The real lesson track this answer starts someone on.
    var track: String {
        switch self {
        case .brandNew, .kana: return "N5"
        case .someKanji: return "N4"
        case .conversational: return "N3"
        }
    }
}

// MARK: - Audio

/// One playable line. `audioName` is the bundle resource a generated recording should use.
struct NaturalClip {
    let text: String
    /// 0 is the leading speaker's voice, 1 the trailing one.
    let voice: Int
    let audioName: String
    /// For a whole conversation generated as one file: which line to play. The file's embedded
    /// `DialogueAlignmentMetadata` switch times mark where each line starts and ends.
    var segment: Int?
}

/// Plays a bundled recording when one exists for the clip, otherwise two-voice on-device TTS.
/// `level` feeds the glass meters: real metering for recordings, a speech-shaped pulse for TTS.
/// Every TTS line also gets a timeout, so a missing voice can never stall the scripted beats.
final class NaturalVoicePlayer: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {

    private static let audioExtensions = ["m4a", "mp3", "wav"]

    private var loadedSynthesizer: AVSpeechSynthesizer?
    private var player: AVAudioPlayer?
    private var finishHandler: (() -> Void)?
    private var fallback: DispatchWorkItem?
    private var isSpeakingTTS = false
    private lazy var voices = WordUtteranceSpeaker.rankedVoices(languageIdentifier: "ja-JP")

    private var synthesizer: AVSpeechSynthesizer {
        if let loadedSynthesizer { return loadedSynthesizer }
        // Built on first use: AVSpeechSynthesizer init blocks on an XPC handshake.
        let created = AVSpeechSynthesizer()
        created.delegate = self
        loadedSynthesizer = created
        return created
    }

    var isPlaying: Bool {
        player?.isPlaying == true || isSpeakingTTS
    }

    /// Current loudness in [0, 1]; poll it from a display link while playing.
    var level: Float {
        if let player, player.isPlaying {
            player.updateMeters()
            let power = player.averagePower(forChannel: 0)
            return min(1, max(0, powf(10, power / 20) * 2.2))
        }
        guard isSpeakingTTS else { return 0 }
        let t = CACurrentMediaTime()
        let pulse = (sin(t * 9.2) + 1) / 2
        let chatter = (sin(t * 17.4) + 1) / 2
        return Float(0.28 + pulse * 0.45 + chatter * 0.2)
    }

    func play(_ clip: NaturalClip, rate: Float = AVSpeechUtteranceDefaultSpeechRate, onFinished: (() -> Void)? = nil) {
        stop()
        finishHandler = onFinished
        try? PlaybackAudioSession.activateForPlayback()

        if let url = Self.bundledURL(named: clip.audioName), let recording = try? AVAudioPlayer(contentsOf: url) {
            recording.delegate = self
            recording.isMeteringEnabled = true
            if let segment = clip.segment {
                guard let range = Self.segmentRange(segment, in: url, duration: recording.duration) else {
                    finish()
                    return
                }
                recording.currentTime = range.lowerBound
                let stopAtEnd = DispatchWorkItem { [weak self] in
                    self?.player?.stop()
                    self?.finish()
                }
                fallback = stopAtEnd
                DispatchQueue.main.asyncAfter(deadline: .now() + (range.upperBound - range.lowerBound), execute: stopAtEnd)
            }
            recording.play()
            player = recording
            return
        }

        let utterance = AVSpeechUtterance(string: clip.text)
        let voice = voices.isEmpty ? nil : voices[clip.voice % voices.count]
        utterance.voice = voice ?? WordUtteranceSpeaker.resolvedVoice(identifier: "ja-JP")
        utterance.rate = rate
        if voices.count < 2 {
            utterance.pitchMultiplier = clip.voice == 0 ? 0.92 : 1.15
        }
        isSpeakingTTS = true
        synthesizer.speak(utterance)

        let timeout = DispatchWorkItem { [weak self] in self?.finish() }
        fallback = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + Double(clip.text.count) * 0.2, execute: timeout)
    }

    func stop() {
        finishHandler = nil
        fallback?.cancel()
        fallback = nil
        player?.stop()
        player = nil
        isSpeakingTTS = false
        guard let loadedSynthesizer, loadedSynthesizer.isSpeaking else { return }
        loadedSynthesizer.stopSpeaking(at: .immediate)
    }

    private func finish() {
        fallback?.cancel()
        fallback = nil
        isSpeakingTTS = false
        player = nil
        let handler = finishHandler
        finishHandler = nil
        handler?()
    }

    /// Reads a conversation file's switch times in the background. On the main thread
    /// `segmentRange` only sees what's already loaded, so call this before a segment plays.
    static func prewarm(_ clip: NaturalClip) {
        guard clip.segment != nil, let url = bundledURL(named: clip.audioName) else { return }
        DialogueAlignmentMetadata.prewarmPayload(from: url)
    }

    /// Line `index`'s time range, from the switch times embedded in a generated conversation file.
    private static func segmentRange(_ index: Int, in url: URL, duration: TimeInterval) -> Range<TimeInterval>? {
        guard let switches = DialogueAlignmentMetadata.readLineSwitchSeconds(from: url) else { return nil }
        let starts = [0] + switches
        guard starts.indices.contains(index) else { return nil }
        let end = index + 1 < starts.count ? starts[index + 1] : duration
        return starts[index]..<max(starts[index], end)
    }

    private static func bundledURL(named name: String) -> URL? {
        audioExtensions.lazy.compactMap { Bundle.main.url(forResource: name, withExtension: $0) }.first
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in self?.finish() }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in self?.finish() }
    }
}

/// Drives a set of meters from a voice player while it plays.
final class NaturalMeterDriver {

    private var link: CADisplayLink?
    private var tick: (() -> Void)?

    func start(_ tick: @escaping () -> Void) {
        stop()
        self.tick = tick
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        tick = nil
    }

    @objc private func step() {
        tick?()
    }
}

// MARK: - Content

struct NaturalPiece {
    let japanese: String
    let gloss: String
}

struct NaturalGist {
    let question: String
    let options: [String]
    let answer: Int
}

/// The textbook-versus-real-life pairs on the gap step. Each side gets its own recording.
struct NaturalContrast {
    let textbook: String
    let real: String
    let english: String

    static let all = [
        NaturalContrast(textbook: "分かりません。", real: "わかんない。", english: "I don't get it."),
        NaturalContrast(textbook: "何をしているのですか？", real: "何してんの？", english: "What are you doing?"),
        NaturalContrast(textbook: "行かなければなりません。", real: "行かなきゃ。", english: "I've gotta go."),
    ]

    static func textbookClip(at index: Int) -> NaturalClip {
        NaturalClip(text: all[index].textbook, voice: 0, audioName: "natural-gap-\(index + 1)-textbook")
    }

    static func realClip(at index: Int) -> NaturalClip {
        NaturalClip(text: all[index].real, voice: 1, audioName: "natural-gap-\(index + 1)-real")
    }
}

/// The first lesson on the shared track (content/collections/train-station.json).
enum NaturalFirstLesson {
    static let title = "At the Train Station"
    static let scenes = [
        "Buying a ticket",
        "Asking the price & paying",
        "Which platform / directions",
        "Time & the next train",
        "A complication (missed train)",
    ]
}
