//
//  NaturalOnboardingFlow.swift
//  shizen
//
//  Listening-first onboarding, guided by Hana. Same stage, timeline, and
//  step base as the tutor flow, but the core is hearing a real conversation
//  blind, catching the gist, then taking spoken forms apart.
//
//  Audio: every clip has a stable name (see `NaturalClip`). Drop a matching
//  .m4a/.mp3/.wav into the app bundle and it plays instead of on-device TTS.
//  Nothing is persisted and no auth runs.
//

import AVFoundation
import TTSCore
import UIKit

enum NaturalOnboardingFlow {
    static func makeSteps() -> [OnboardingViewController] {
        let session = NaturalOnboardingSession()
        // Step ids are the analytics `step_name`s; keep them stable once shipped.
        return [
            NaturalIntroStepViewController(session: session).withStepId("intro"),
            NaturalGapStepViewController(session: session).withStepId("gap"),
            NaturalRegisterStepViewController(session: session).withStepId("register"),
            NaturalLevelStepViewController(session: session).withStepId("level"),
            NaturalListenStepViewController(session: session).withStepId("listen"),
            NaturalDissectStepViewController(session: session).withStepId("dissect"),
            NaturalPlanStepViewController(session: session).withStepId("plan"),
            NaturalCommitStepViewController(session: session).withStepId("commit"),
            NaturalReadyStepViewController(session: session).withStepId("ready"),
            // TODO(SHZ-40): add the team-note screen here, right before the paywall, as
            // `.withStepId(teamNoteStepId)`. The coordinator reports it like every other step.
        ]
    }

    /// `step_name` for the team-note screen before the paywall (SHZ-40), once it lands.
    static let teamNoteStepId = "team_note"
}

/// Full-screen modal that owns the coordinator; the container dismisses it when backed out of step one.
final class NaturalOnboardingHostController: UINavigationController, AuthenticationDelegate {

    private let coordinator = OnboardingCoordinator(flow: .natural)

    init() {
        super.init(nibName: nil, bundle: nil)
        coordinator.enablePreviewMode()
        coordinator.authenticationDelegate = self
        setViewControllers([coordinator.start()], animated: false)
        setNavigationBarHidden(true, animated: false)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func signUpComplete() {
        dismiss(animated: true)
    }
}

/// Reuses the tutor session's name, level, and pacing answers; `register` replaces `goal`.
/// Subclassed by the listen-first v2 session, which persists answers and names tracks differently.
class NaturalOnboardingSession: TutorOnboardingSession {
    var register: NaturalRegister = .everything
    /// Whether the first blind listen caught the gist; nil until answered.
    var caughtGist: Bool?
    var promised = false

    /// Kana for the first two levels, kanji with furigana above that. Never romaji-only.
    func text(_ line: TutorSampleLine) -> String {
        switch level {
        case .brandNew, .kana: return line.kana
        case .someKanji, .conversational: return line.kanji
        }
    }

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

struct NaturalSpeaker {
    let name: String
}

struct NaturalLine {
    let speaker: Int
    let line: TutorSampleLine
}

struct NaturalPiece {
    let japanese: String
    let gloss: String
}

/// A spoken form worth dissecting: what it's built from, and what a textbook would print instead.
struct NaturalChunk {
    /// Index of the conversation line the chunk comes from.
    let line: Int
    let spoken: TutorSampleLine
    let pieces: [NaturalPiece]
    let textbook: String
    let note: String
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

/// Curated lines for the level slider: what a line actually looks like at each level.
enum NaturalLevelSamples {
    static func sample(for level: TutorLevel) -> TutorLevelSample {
        switch level {
        case .brandNew:
            return TutorLevelSample(japanese: "こんにちは！", reading: nil, english: "Hello!")
        case .kana:
            return TutorLevelSample(japanese: "おなまえは なんですか？", reading: nil, english: "What's your name?")
        case .someKanji:
            return TutorLevelSample(japanese: "週末は何をしていましたか？", reading: nil, english: "What did you do this weekend?")
        case .conversational:
            return TutorLevelSample(
                japanese: "週末なにしてた？めっちゃ天気よかったじゃん。",
                reading: nil,
                english: "What'd you get up to this weekend? The weather was amazing."
            )
        }
    }

    static func hint(for level: TutorLevel) -> String {
        switch level {
        case .brandNew: return "Short lines in kana, English underneath."
        case .kana: return "Kana only, English underneath."
        case .someKanji: return "Real Japanese, furigana over kanji."
        case .conversational: return "Natural speed, English on tap."
        }
    }

    static func planPhrase(for level: TutorLevel) -> String {
        switch level {
        case .brandNew, .kana: return "in kana with English underneath"
        case .someKanji: return "in real Japanese with furigana"
        case .conversational: return "in Japanese only"
        }
    }
}

/// Which kind of spoken Japanese Hana points out. Every lesson mixes settings;
/// this only changes the emphasis, not the track.
enum NaturalRegister: String, CaseIterable {
    case everything
    case casual
    case college
    case polite
    case travel
    case anime

    var emoji: String {
        switch self {
        case .everything: return "🗣️"
        case .casual: return "🤝"
        case .college: return "🎓"
        case .polite: return "🙇"
        case .travel: return "✈️"
        case .anime: return "🎌"
        }
    }

    var title: String {
        switch self {
        case .everything: return "A bit of everything"
        case .casual: return "Friends, casual"
        case .college: return "College & slang"
        case .polite: return "Polite & keigo"
        case .travel: return "Travel & service"
        case .anime: return "Anime & dramas"
        }
    }

    var sceneTitle: String {
        switch self {
        case .everything: return "Late night at the ramen counter"
        case .casual: return "Making weekend plans"
        case .college: return "Missing the last train"
        case .polite: return "Arriving for a meeting"
        case .travel: return "The hotel front desk"
        case .anime: return "After school on the rooftop"
        }
    }

    /// What Hana flags in every scene for this pick.
    var focus: String {
        switch self {
        case .everything: return "everyday contractions"
        case .casual: return "casual speech and dropped particles"
        case .college: return "slang and squashed verbs"
        case .polite: return "keigo and polite softeners"
        case .travel: return "the service keigo you hear at counters"
        case .anime: return "sentence endings and attitude"
        }
    }

    var speakers: [NaturalSpeaker] {
        switch self {
        case .everything: return [NaturalSpeaker(name: "Chef"), NaturalSpeaker(name: "Regular")]
        case .casual: return [NaturalSpeaker(name: "Yui"), NaturalSpeaker(name: "Kenta")]
        case .college: return [NaturalSpeaker(name: "Mei"), NaturalSpeaker(name: "Riku")]
        case .polite: return [NaturalSpeaker(name: "Receptionist"), NaturalSpeaker(name: "Yamada")]
        case .travel: return [NaturalSpeaker(name: "Clerk"), NaturalSpeaker(name: "Guest")]
        case .anime: return [NaturalSpeaker(name: "Haruto"), NaturalSpeaker(name: "Aoi")]
        }
    }

    /// Spoken forms the preview shows, glossed with what a textbook would say instead.
    var phrases: [TutorLine] {
        switch self {
        case .everything:
            return [
                TutorLine("いつものでいい？", "The usual?"),
                TutorLine("めっちゃ混んでんね", "It's packed, huh · textbook: 混んでいるね"),
                TutorLine("はいよ！", "You got it!"),
            ]
        case .casual:
            return [
                TutorLine("なにしてる？", "What're you up to? · textbook: 何をしている"),
                TutorLine("行かない？", "Wanna go?"),
                TutorLine("いいじゃん！", "Sounds good! · textbook: いいじゃないか"),
            ]
        case .college:
            return [
                TutorLine("やばい！", "Oh no! (or: amazing!)"),
                TutorLine("行っちゃった", "It's gone · textbook: 行ってしまった"),
                TutorLine("待とっか", "Shall we wait? · textbook: 待とうか"),
            ]
        case .polite:
            return [
                TutorLine("お待たせいたしました", "Sorry to keep you waiting"),
                TutorLine("ご案内いたします", "Let me show you in"),
                TutorLine("いただいてるんですが", "I've been given… (softened)"),
            ]
        case .travel:
            return [
                TutorLine("かしこまりました", "Certainly · textbook: わかりました"),
                TutorLine("よろしいですか？", "Is that all right?"),
                TutorLine("予約してるんですけど", "I have a booking, so…"),
            ]
        case .anime:
            return [
                TutorLine("マジで？", "Seriously?"),
                TutorLine("テストだって", "Apparently there's a test"),
                TutorLine("ダメでしょ！", "No way, you can't!"),
            ]
        }
    }

    var conversation: [NaturalLine] {
        switch self {
        case .everything:
            return [
                NaturalLine(speaker: 0, line: TutorSampleLine(
                    romaji: "Irasshai! Itsumo no de ii?",
                    kana: "いらっしゃい！いつものでいい？",
                    kanji: "いらっしゃい！いつものでいい？",
                    english: "Hey, welcome! The usual?"
                )),
                NaturalLine(speaker: 1, line: TutorSampleLine(
                    romaji: "Un, itsumo no de. A, men katame de!",
                    kana: "うん、いつもので。あ、めんかためで！",
                    kanji: "うん、いつもので。あ、麺かためで！",
                    english: "Yeah, the usual. Oh, firm noodles!"
                )),
                NaturalLine(speaker: 0, line: TutorSampleLine(
                    romaji: "Hai yo! Kyou meccha konden ne.",
                    kana: "はいよ！きょうめっちゃこんでんね。",
                    kanji: "はいよ！今日めっちゃ混んでんね。",
                    english: "You got it! It's packed today, huh."
                )),
                NaturalLine(speaker: 1, line: TutorSampleLine(
                    romaji: "Honto da. Mattete yokattaa.",
                    kana: "ほんとだ。まっててよかったー。",
                    kanji: "ほんとだ。待っててよかったー。",
                    english: "Seriously. So glad I waited."
                )),
            ]
        case .casual:
            return [
                NaturalLine(speaker: 0, line: TutorSampleLine(
                    romaji: "Nee, shuumatsu nani shiteru?",
                    kana: "ねえ、しゅうまつなにしてる？",
                    kanji: "ねえ、週末なにしてる？",
                    english: "Hey, what are you up to this weekend?"
                )),
                NaturalLine(speaker: 1, line: TutorSampleLine(
                    romaji: "Toku ni nanmo. Nande?",
                    kana: "とくになんも。なんで？",
                    kanji: "特になんも。なんで？",
                    english: "Nothing really. Why?"
                )),
                NaturalLine(speaker: 0, line: TutorSampleLine(
                    romaji: "Atarashii kafe ikanai? Meccha kawaii n datte.",
                    kana: "あたらしいカフェいかない？めっちゃかわいいんだって。",
                    kanji: "新しいカフェ行かない？めっちゃかわいいんだって。",
                    english: "Wanna try the new café? Apparently it's super cute."
                )),
                NaturalLine(speaker: 1, line: TutorSampleLine(
                    romaji: "Ii jan, iko iko!",
                    kana: "いいじゃん、いこいこ！",
                    kanji: "いいじゃん、行こ行こ！",
                    english: "Sounds good, let's go!"
                )),
            ]
        case .college:
            return [
                NaturalLine(speaker: 0, line: TutorSampleLine(
                    romaji: "Yabai, shuuden icchatta!",
                    kana: "やばい、しゅうでんいっちゃった！",
                    kanji: "やばい、終電行っちゃった！",
                    english: "Oh no, the last train just left!"
                )),
                NaturalLine(speaker: 1, line: TutorSampleLine(
                    romaji: "E, uso desho? Takushii de kaeru?",
                    kana: "え、うそでしょ？タクシーでかえる？",
                    kanji: "え、うそでしょ？タクシーで帰る？",
                    english: "Wait, no way. Take a taxi home?"
                )),
                NaturalLine(speaker: 0, line: TutorSampleLine(
                    romaji: "Takasugiru tte. Shihatsu made matokka.",
                    kana: "たかすぎるって。しはつまでまとっか。",
                    kanji: "高すぎるって。始発まで待とっか。",
                    english: "Way too expensive. Let's wait for the first train."
                )),
                NaturalLine(speaker: 1, line: TutorSampleLine(
                    romaji: "Jaa, karaoke demo ikou yo.",
                    kana: "じゃあ、カラオケでもいこうよ。",
                    kanji: "じゃあ、カラオケでも行こうよ。",
                    english: "Then let's go do karaoke or something."
                )),
            ]
        case .polite:
            return [
                NaturalLine(speaker: 0, line: TutorSampleLine(
                    romaji: "Irasshaimase. Goyouken o oukagai shimasu.",
                    kana: "いらっしゃいませ。ごようけんをおうかがいします。",
                    kanji: "いらっしゃいませ。ご用件をお伺いします。",
                    english: "Welcome. How may I help you?"
                )),
                NaturalLine(speaker: 1, line: TutorSampleLine(
                    romaji: "Sanji ni Tanaka-sama to oyakusoku o itadaiteru n desu ga…",
                    kana: "さんじにたなかさまとおやくそくをいただいてるんですが…",
                    kanji: "三時に田中様とお約束をいただいてるんですが…",
                    english: "I have a three o'clock appointment with Mr. Tanaka…"
                )),
                NaturalLine(speaker: 0, line: TutorSampleLine(
                    romaji: "Yamada-sama desu ne. Omatase itashimashita. Tadaima goannai itashimasu.",
                    kana: "やまださまですね。おまたせいたしました。ただいまごあんないいたします。",
                    kanji: "山田様ですね。お待たせいたしました。ただいまご案内いたします。",
                    english: "Ms. Yamada, of course. Sorry to keep you waiting. I'll show you in right away."
                )),
                NaturalLine(speaker: 1, line: TutorSampleLine(
                    romaji: "Arigatou gozaimasu.",
                    kana: "ありがとうございます。",
                    kanji: "ありがとうございます。",
                    english: "Thank you very much."
                )),
            ]
        case .travel:
            return [
                NaturalLine(speaker: 0, line: TutorSampleLine(
                    romaji: "Irasshaimase. Chekkuin de yoroshii desu ka?",
                    kana: "いらっしゃいませ。チェックインでよろしいですか？",
                    kanji: "いらっしゃいませ。チェックインでよろしいですか？",
                    english: "Welcome. Checking in?"
                )),
                NaturalLine(speaker: 1, line: TutorSampleLine(
                    romaji: "Hai, yoyaku shiteru n desu kedo…",
                    kana: "はい、よやくしてるんですけど…",
                    kanji: "はい、予約してるんですけど…",
                    english: "Yes, I have a reservation…"
                )),
                NaturalLine(speaker: 0, line: TutorSampleLine(
                    romaji: "Kashikomarimashita. Pasupooto o onegai dekimasu ka?",
                    kana: "かしこまりました。パスポートをおねがいできますか？",
                    kanji: "かしこまりました。パスポートをお願いできますか？",
                    english: "Certainly. May I see your passport?"
                )),
                NaturalLine(speaker: 1, line: TutorSampleLine(
                    romaji: "Hai, douzo.",
                    kana: "はい、どうぞ。",
                    kanji: "はい、どうぞ。",
                    english: "Here you go."
                )),
            ]
        case .anime:
            return [
                NaturalLine(speaker: 0, line: TutorSampleLine(
                    romaji: "Oi, kiita? Ashita tesuto datte.",
                    kana: "おい、きいた？あしたテストだって。",
                    kanji: "おい、聞いた？明日テストだって。",
                    english: "Yo, did you hear? Apparently there's a test tomorrow."
                )),
                NaturalLine(speaker: 1, line: TutorSampleLine(
                    romaji: "Ha? Maji de? Zenzen benkyou shitenai n da kedo.",
                    kana: "は？マジで？ぜんぜんべんきょうしてないんだけど。",
                    kanji: "は？マジで？全然勉強してないんだけど。",
                    english: "Huh? Seriously? I haven't studied at all."
                )),
                NaturalLine(speaker: 0, line: TutorSampleLine(
                    romaji: "Ore mo. Mou akirameyokka.",
                    kana: "おれも。もうあきらめよっか。",
                    kanji: "俺も。もう諦めよっか。",
                    english: "Same. Wanna just give up?"
                )),
                NaturalLine(speaker: 1, line: TutorSampleLine(
                    romaji: "Iya, dame desho!",
                    kana: "いや、だめでしょ！",
                    kanji: "いや、ダメでしょ！",
                    english: "No way, we can't!"
                )),
            ]
        }
    }

    func lineClip(at index: Int) -> NaturalClip {
        let line = conversation[index]
        return NaturalClip(text: line.line.kanji, voice: line.speaker, audioName: "natural-\(rawValue)-line-\(index + 1)")
    }

    func spokenClip(forChunk index: Int) -> NaturalClip {
        NaturalClip(text: chunks[index].spoken.kanji, voice: 1, audioName: "natural-\(rawValue)-chunk-\(index + 1)-real")
    }

    func textbookClip(forChunk index: Int) -> NaturalClip {
        NaturalClip(text: chunks[index].textbook, voice: 0, audioName: "natural-\(rawValue)-chunk-\(index + 1)-textbook")
    }

    var gist: NaturalGist {
        switch self {
        case .everything:
            return NaturalGist(
                question: "What's going on?",
                options: ["A regular orders their usual", "Someone asks for directions", "The shop is closing early"],
                answer: 0
            )
        case .casual:
            return NaturalGist(
                question: "What does Yui want?",
                options: ["To borrow some money", "To try a new café together", "To cancel their plans"],
                answer: 1
            )
        case .college:
            return NaturalGist(
                question: "What do they decide?",
                options: ["Take a taxi home", "Wait it out until the first train", "Walk home together"],
                answer: 1
            )
        case .polite:
            return NaturalGist(
                question: "What's happening?",
                options: ["Two coworkers gossiping", "Someone ordering lunch", "A visitor arriving for a meeting"],
                answer: 2
            )
        case .travel:
            return NaturalGist(
                question: "Where are we?",
                options: ["A hotel front desk", "A train ticket window", "A doctor's office"],
                answer: 0
            )
        case .anime:
            return NaturalGist(
                question: "What's the problem?",
                options: ["They missed the bus", "Surprise test, nobody studied", "Aoi lost a phone"],
                answer: 1
            )
        }
    }

    var chunks: [NaturalChunk] {
        switch self {
        case .everything:
            return [
                NaturalChunk(
                    line: 2,
                    spoken: TutorSampleLine(romaji: "konden ne", kana: "こんでんね", kanji: "混んでんね", english: "It's packed, huh"),
                    pieces: [
                        NaturalPiece(japanese: "混んで", gloss: "crowded"),
                        NaturalPiece(japanese: "いる", gloss: "is"),
                        NaturalPiece(japanese: "ね", gloss: "huh?"),
                    ],
                    textbook: "混んでいるね",
                    note: "In fast speech ている shrinks to てる, and before ね it squashes all the way down to ん."
                ),
                NaturalChunk(
                    line: 3,
                    spoken: TutorSampleLine(romaji: "mattete", kana: "まってて", kanji: "待ってて", english: "having waited"),
                    pieces: [
                        NaturalPiece(japanese: "待って", gloss: "wait"),
                        NaturalPiece(japanese: "いて", gloss: "kept on"),
                    ],
                    textbook: "待っていて",
                    note: "Same trick: the い disappears. You'll hear this in almost every conversation."
                ),
            ]
        case .casual:
            return [
                NaturalChunk(
                    line: 0,
                    spoken: TutorSampleLine(romaji: "nani shiteru", kana: "なにしてる", kanji: "なにしてる", english: "What're you up to?"),
                    pieces: [
                        NaturalPiece(japanese: "なに", gloss: "what"),
                        NaturalPiece(japanese: "を", gloss: "(object)"),
                        NaturalPiece(japanese: "して", gloss: "do"),
                        NaturalPiece(japanese: "いる", gloss: "-ing"),
                    ],
                    textbook: "なにをしている",
                    note: "Friends drop を entirely and swallow the い. Four pieces become one quick breath."
                ),
                NaturalChunk(
                    line: 3,
                    spoken: TutorSampleLine(romaji: "ii jan", kana: "いいじゃん", kanji: "いいじゃん", english: "Sounds good!"),
                    pieces: [
                        NaturalPiece(japanese: "いい", gloss: "good"),
                        NaturalPiece(japanese: "じゃない", gloss: "isn't it"),
                        NaturalPiece(japanese: "か", gloss: "?"),
                    ],
                    textbook: "いいじゃないか",
                    note: "じゃないか gets squashed into じゃん. Textbooks skip it; friends say it constantly."
                ),
            ]
        case .college:
            return [
                NaturalChunk(
                    line: 0,
                    spoken: TutorSampleLine(romaji: "icchatta", kana: "いっちゃった", kanji: "行っちゃった", english: "It's gone"),
                    pieces: [
                        NaturalPiece(japanese: "行って", gloss: "go"),
                        NaturalPiece(japanese: "しまった", gloss: "done (oops)"),
                    ],
                    textbook: "行ってしまった",
                    note: "てしまった melts into ちゃった. It carries the \"oh no\" feeling all on its own."
                ),
                NaturalChunk(
                    line: 2,
                    spoken: TutorSampleLine(romaji: "matokka", kana: "まとっか", kanji: "待とっか", english: "Shall we wait?"),
                    pieces: [
                        NaturalPiece(japanese: "待とう", gloss: "let's wait"),
                        NaturalPiece(japanese: "か", gloss: "shall we?"),
                    ],
                    textbook: "待とうか",
                    note: "The long う gets clipped, and か snaps on with a tiny stop: matokka."
                ),
            ]
        case .polite:
            return [
                NaturalChunk(
                    line: 1,
                    spoken: TutorSampleLine(
                        romaji: "itadaiteru n desu ga",
                        kana: "いただいてるんですが",
                        kanji: "いただいてるんですが",
                        english: "I've been given… (softened)"
                    ),
                    pieces: [
                        NaturalPiece(japanese: "いただいて", gloss: "receive (humble)"),
                        NaturalPiece(japanese: "いる", gloss: "have"),
                        NaturalPiece(japanese: "のです", gloss: "you see"),
                        NaturalPiece(japanese: "が", gloss: "but…"),
                    ],
                    textbook: "いただいているのですが",
                    note: "Even polite speech contracts. Trailing off on が lets the receptionist finish the thought for you."
                ),
                NaturalChunk(
                    line: 2,
                    spoken: TutorSampleLine(
                        romaji: "omatase itashimashita",
                        kana: "おまたせいたしました",
                        kanji: "お待たせいたしました",
                        english: "Sorry to keep you waiting"
                    ),
                    pieces: [
                        NaturalPiece(japanese: "お", gloss: "(honorific)"),
                        NaturalPiece(japanese: "待たせ", gloss: "make wait"),
                        NaturalPiece(japanese: "いたしました", gloss: "did (humble)"),
                    ],
                    textbook: "待たせました",
                    note: "Keigo stacks politeness on top of a plain verb. Hear it once and you'll catch it at every front desk."
                ),
            ]
        case .travel:
            return [
                NaturalChunk(
                    line: 1,
                    spoken: TutorSampleLine(
                        romaji: "yoyaku shiteru n desu kedo",
                        kana: "よやくしてるんですけど",
                        kanji: "予約してるんですけど",
                        english: "I have a booking, so…"
                    ),
                    pieces: [
                        NaturalPiece(japanese: "予約して", gloss: "reserve"),
                        NaturalPiece(japanese: "いる", gloss: "have"),
                        NaturalPiece(japanese: "のです", gloss: "you see"),
                        NaturalPiece(japanese: "けど", gloss: "so…"),
                    ],
                    textbook: "予約しているのですが",
                    note: "ている → てる, のです → んです, and けど trails off politely. Travelers say this at every desk."
                ),
                NaturalChunk(
                    line: 2,
                    spoken: TutorSampleLine(
                        romaji: "kashikomarimashita",
                        kana: "かしこまりました",
                        kanji: "かしこまりました",
                        english: "Certainly"
                    ),
                    pieces: [
                        NaturalPiece(japanese: "かしこまり", gloss: "understand (humble)"),
                        NaturalPiece(japanese: "ました", gloss: "did"),
                    ],
                    textbook: "わかりました",
                    note: "Staff never say わかりました to a guest. Listen for かしこまりました instead."
                ),
            ]
        case .anime:
            return [
                NaturalChunk(
                    line: 0,
                    spoken: TutorSampleLine(romaji: "tesuto datte", kana: "テストだって", kanji: "テストだって", english: "Apparently a test"),
                    pieces: [
                        NaturalPiece(japanese: "テスト", gloss: "test"),
                        NaturalPiece(japanese: "だ", gloss: "is"),
                        NaturalPiece(japanese: "って", gloss: "they say"),
                    ],
                    textbook: "テストだそうだ",
                    note: "って at the end means \"I heard.\" It's how gossip travels in every anime classroom."
                ),
                NaturalChunk(
                    line: 1,
                    spoken: TutorSampleLine(
                        romaji: "shitenai n da kedo",
                        kana: "してないんだけど",
                        kanji: "してないんだけど",
                        english: "I haven't, so…"
                    ),
                    pieces: [
                        NaturalPiece(japanese: "して", gloss: "do"),
                        NaturalPiece(japanese: "いない", gloss: "haven't"),
                        NaturalPiece(japanese: "のだ", gloss: "you see"),
                        NaturalPiece(japanese: "けど", gloss: "so…"),
                    ],
                    textbook: "していないのだけど",
                    note: "Trailing off on けど leaves the rest unsaid. Listeners fill it in: \"…so what do I do?\""
                ),
            ]
        }
    }

    var tip: String {
        switch self {
        case .everything: return "When you hear ん where a word should be, try putting いる back in. Most mystery sounds are just contractions."
        case .casual: return "Listen for rising tone. A plain verb with a lift at the end is usually an invitation."
        case .college: return "やばい can mean disaster or amazing. The voice tells you which, so replay and listen to the tone."
        case .polite: return "Keigo sounds long, but it's built from a few repeating pieces: お, いたします, ございます."
        case .travel: return "Counter staff speak in set phrases. Learn to hear five of them and most service talk clicks."
        case .anime: return "Sentence endings carry the mood: って for rumors, けど for trailing off, でしょ for \"come on.\""
        }
    }

    var farewell: TutorLine {
        switch self {
        case .everything: return TutorLine("また聞きに来てね！", "Come back and listen again soon!")
        case .casual: return TutorLine("じゃあ、またね！", "See you soon!")
        case .college: return TutorLine("終電、逃さないでね！", "Don't miss the last train!")
        case .polite: return TutorLine("お待ちしております。", "We look forward to seeing you.")
        case .travel: return TutorLine("いってらっしゃい！", "Have a great trip!")
        case .anime: return TutorLine("屋上で待ってるね！", "Meet me on the rooftop!")
        }
    }
}
