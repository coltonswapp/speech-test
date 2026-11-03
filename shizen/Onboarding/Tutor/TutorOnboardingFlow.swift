//
//  TutorOnboardingFlow.swift
//  shizen
//
//  Playground onboarding led by "Hana", a fake AI speaking partner. Answers
//  live only in TutorOnboardingSession for the life of the modal; nothing is
//  persisted and no auth runs (the coordinator stays in preview mode).
//

import UIKit

enum TutorOnboardingFlow {
    static func makeSteps() -> [OnboardingViewController] {
        let session = TutorOnboardingSession()
        // Step ids are the analytics `step_name`s; keep them stable once shipped.
        return [
            TutorIntroStepViewController(session: session).withStepId("intro"),
            TutorGoalStepViewController(session: session).withStepId("goal"),
            TutorLevelStepViewController(session: session).withStepId("level"),
            TutorRoleplayStepViewController(session: session).withStepId("roleplay"),
            TutorPlanStepViewController(session: session).withStepId("plan"),
            TutorReadyStepViewController(session: session).withStepId("ready"),
        ]
    }
}

/// Full-screen modal that owns the coordinator; the container dismisses it when backed out of step one.
final class TutorOnboardingHostController: UINavigationController, AuthenticationDelegate {

    private let coordinator = OnboardingCoordinator(flow: .tutor)

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

/// Subclassed by NaturalOnboardingSession, which reuses the name, level, and pacing answers.
class TutorOnboardingSession {
    var name = ""
    var goal: TutorGoal = .food
    var level: TutorLevel = .brandNew
    var minutesPerDay = 10

    /// Whether chats use the flower mascot instead of the 🌸 avatar. On for listen-first v2.
    var showsMascot: Bool { false }

    /// A Hana that floats above every screen and glides between them. Listen-first v2 only.
    var hanaStage: OnboardingHanaStage? { nil }

    /// The hand-written breakdown a right swipe opens for a Japanese line. None by default.
    func breakdown(for japanese: String) -> SentenceScrubScript? { nil }

    /// When true, every Japanese line shown must have a breakdown; a missing one asserts.
    var dissectsEveryLine: Bool { false }

    var displayName: String {
        name.isEmpty ? "friend" : name
    }

    func personalize(_ text: String) -> String {
        text.replacingOccurrences(of: "{name}", with: displayName)
    }
}

/// Cancellable timers for scripted beats, so popping a step never fires stale animations.
/// `fastForward()` runs every waiting beat immediately (tap-to-advance); beats those schedule wait as usual.
final class TutorTimeline {

    private struct Beat {
        let task: Task<Void, Never>
        let work: @MainActor () -> Void
    }

    private var tasks: [Task<Void, Never>] = []
    private var beats: [Int: Beat] = [:]
    private var nextBeatID = 0
    /// Bumps on every fast-forward; long-running work (typing, counters) jumps to its end state when it changes.
    private(set) var skipGeneration = 0

    var hasWaitingBeats: Bool { !beats.isEmpty }

    func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        let id = nextBeatID
        nextBeatID += 1
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.fire(id)
        }
        beats[id] = Beat(task: task, work: work)
    }

    func run(_ operation: @escaping @MainActor () async -> Void) {
        tasks.append(Task { @MainActor in await operation() })
    }

    /// Fires every waiting beat now, in the order they were scheduled.
    func fastForward() {
        skipGeneration += 1
        for id in beats.keys.sorted() {
            guard let beat = beats.removeValue(forKey: id) else { continue }
            beat.task.cancel()
            beat.work()
        }
    }

    func cancelAll() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        beats.values.forEach { $0.task.cancel() }
        beats.removeAll()
    }

    private func fire(_ id: Int) {
        beats.removeValue(forKey: id)?.work()
    }
}

// MARK: - Content

struct TutorLine {
    let japanese: String
    let english: String

    init(_ japanese: String, _ english: String) {
        self.japanese = japanese
        self.english = english
    }
}

struct TutorRound {
    let prompt: TutorLine
    let replies: [TutorLine]
    let praise: String
}

struct TutorSampleLine {
    let romaji: String
    let kana: String
    let kanji: String
    let english: String

    func text(for level: TutorLevel) -> String {
        switch level {
        case .brandNew: return romaji
        case .kana: return kana
        case .someKanji, .conversational: return kanji
        }
    }
}

enum TutorLevel: Int, CaseIterable {
    case brandNew
    case kana
    case someKanji
    case conversational

    var title: String {
        switch self {
        case .brandNew: return "Brand new"
        case .kana: return "I know kana"
        case .someKanji: return "Some kanji"
        case .conversational: return "I can hold a chat"
        }
    }

    var hint: String {
        switch self {
        case .brandNew: return "Romaji first, English right underneath."
        case .kana: return "Hiragana and katakana only. No kanji yet."
        case .someKanji: return "Real Japanese, furigana over the kanji."
        case .conversational: return "Japanese only. Translations hide until you ask."
        }
    }

    var showsEnglish: Bool {
        self != .conversational
    }
}

enum TutorGoal: CaseIterable {
    case food
    case directions
    case friends
    case work
    case anime
    case hotel

    var emoji: String {
        switch self {
        case .food: return "🍜"
        case .directions: return "🗺️"
        case .friends: return "🤝"
        case .work: return "💼"
        case .anime: return "🎌"
        case .hotel: return "🏨"
        }
    }

    var title: String {
        switch self {
        case .food: return "Ordering food"
        case .directions: return "Asking directions"
        case .friends: return "Making friends"
        case .work: return "At work"
        case .anime: return "Anime, no subs"
        case .hotel: return "Checking in"
        }
    }

    var sceneTitle: String {
        switch self {
        case .food: return "The ramen counter"
        case .directions: return "Lost in Shibuya"
        case .friends: return "Coffee with a new friend"
        case .work: return "Your first day at the office"
        case .anime: return "After school on the rooftop"
        case .hotel: return "The hotel front desk"
        }
    }

    var partnerRole: String {
        switch self {
        case .food: return "ramen chef"
        case .directions: return "friendly local"
        case .friends: return "new friend"
        case .work: return "new manager"
        case .anime: return "classmate"
        case .hotel: return "receptionist"
        }
    }

    var reaction: TutorLine {
        switch self {
        case .food: return TutorLine("ラーメン、いいね！", "Ramen? Great pick.")
        case .directions: return TutorLine("道案内ね、まかせて！", "Directions? I've got you.")
        case .friends: return TutorLine("友だち作り、楽しいよ！", "Making friends is the fun part!")
        case .work: return TutorLine("お仕事ですね。がんばりましょう！", "For work? Let's do this.")
        case .anime: return TutorLine("アニメ！最高だね！", "Anime? The best.")
        case .hotel: return TutorLine("旅行、いいなあ！", "Traveling? I'm jealous!")
        }
    }

    var phrases: [TutorLine] {
        switch self {
        case .food:
            return [
                TutorLine("これをください", "This one, please"),
                TutorLine("おすすめは？", "What do you recommend?"),
                TutorLine("おいしい！", "Delicious!"),
            ]
        case .directions:
            return [
                TutorLine("駅はどこですか？", "Where's the station?"),
                TutorLine("まっすぐ", "Straight ahead"),
                TutorLine("もう一度お願いします", "One more time, please"),
            ]
        case .friends:
            return [
                TutorLine("はじめまして", "Nice to meet you"),
                TutorLine("趣味は何ですか？", "What are your hobbies?"),
                TutorLine("また会おうね", "Let's hang out again"),
            ]
        case .work:
            return [
                TutorLine("よろしくお願いします", "Glad to be working with you"),
                TutorLine("お疲れ様です", "Thanks for your hard work"),
                TutorLine("確認します", "I'll check on it"),
            ]
        case .anime:
            return [
                TutorLine("マジで？", "Seriously?"),
                TutorLine("やばい！", "No way!"),
                TutorLine("行くぞ！", "Let's go!"),
            ]
        case .hotel:
            return [
                TutorLine("チェックインお願いします", "Check-in, please"),
                TutorLine("予約しています", "I have a reservation"),
                TutorLine("Wi-Fiはありますか？", "Is there Wi-Fi?"),
            ]
        }
    }

    var sample: TutorSampleLine {
        switch self {
        case .food:
            return TutorSampleLine(
                romaji: "Irasshaimase! Nanmei-sama desu ka?",
                kana: "いらっしゃいませ！なんめいさまですか？",
                kanji: "いらっしゃいませ！何名様ですか？",
                english: "Welcome! How many in your party?"
            )
        case .directions:
            return TutorSampleLine(
                romaji: "Sumimasen, eki wa doko desu ka?",
                kana: "すみません、えきはどこですか？",
                kanji: "すみません、駅はどこですか？",
                english: "Excuse me, where is the station?"
            )
        case .friends:
            return TutorSampleLine(
                romaji: "Hajimemashite! Onamae wa?",
                kana: "はじめまして！おなまえは？",
                kanji: "はじめまして！お名前は？",
                english: "Nice to meet you! What's your name?"
            )
        case .work:
            return TutorSampleLine(
                romaji: "Kyou kara yoroshiku onegaishimasu.",
                kana: "きょうからよろしくおねがいします。",
                kanji: "今日からよろしくお願いします。",
                english: "Looking forward to working with you, starting today."
            )
        case .anime:
            return TutorSampleLine(
                romaji: "Nee, kyou issho ni kaerou yo!",
                kana: "ねえ、きょういっしょにかえろうよ！",
                kanji: "ねえ、今日一緒に帰ろうよ！",
                english: "Hey, let's walk home together today!"
            )
        case .hotel:
            return TutorSampleLine(
                romaji: "Chekkuin onegaishimasu.",
                kana: "チェックインおねがいします。",
                kanji: "チェックインお願いします。",
                english: "I'd like to check in, please."
            )
        }
    }

    var rounds: [TutorRound] {
        switch self {
        case .food:
            return [
                TutorRound(
                    prompt: TutorLine("いらっしゃいませ！何名様ですか？", "Welcome! How many in your party?"),
                    replies: [TutorLine("一人です。", "Just me."), TutorLine("二人です。", "Two of us.")],
                    praise: "いいね！"
                ),
                TutorRound(
                    prompt: TutorLine("ご注文は？", "What would you like?"),
                    replies: [
                        TutorLine("味噌ラーメンをください。", "Miso ramen, please."),
                        TutorLine("おすすめは何ですか？", "What do you recommend?"),
                    ],
                    praise: "すごい！"
                ),
            ]
        case .directions:
            return [
                TutorRound(
                    prompt: TutorLine("どうしましたか？", "Can I help you?"),
                    replies: [TutorLine("駅はどこですか？", "Where's the station?"), TutorLine("道に迷いました。", "I'm lost.")],
                    praise: "いいね！"
                ),
                TutorRound(
                    prompt: TutorLine("まっすぐ行って、右です。", "Go straight, then turn right."),
                    replies: [
                        TutorLine("ありがとうございます！", "Thank you!"),
                        TutorLine("もう一度お願いします。", "One more time, please."),
                    ],
                    praise: "完璧！"
                ),
            ]
        case .friends:
            return [
                TutorRound(
                    prompt: TutorLine("はじめまして！お名前は？", "Nice to meet you! What's your name?"),
                    replies: [TutorLine("{name}です。", "I'm {name}."), TutorLine("{name}といいます。", "My name is {name}.")],
                    praise: "いいね！"
                ),
                TutorRound(
                    prompt: TutorLine("趣味は何ですか？", "What are your hobbies?"),
                    replies: [TutorLine("音楽が好きです。", "I like music."), TutorLine("料理が好きです。", "I like cooking.")],
                    praise: "すごい！"
                ),
            ]
        case .work:
            return [
                TutorRound(
                    prompt: TutorLine("今日からよろしくお願いします。", "Welcome aboard, starting today."),
                    replies: [
                        TutorLine("よろしくお願いします！", "Glad to be here!"),
                        TutorLine("こちらこそ、よろしくお願いします。", "The pleasure is mine."),
                    ],
                    praise: "完璧！"
                ),
                TutorRound(
                    prompt: TutorLine("この資料、確認できますか？", "Could you check this document?"),
                    replies: [TutorLine("はい、確認します。", "Sure, I'll check it."), TutorLine("少々お待ちください。", "One moment, please.")],
                    praise: "すごい！"
                ),
            ]
        case .anime:
            return [
                TutorRound(
                    prompt: TutorLine("ねえ、今日一緒に帰ろうよ！", "Hey, let's walk home together today!"),
                    replies: [TutorLine("うん、いいよ！", "Yeah, sure!"), TutorLine("ごめん、今日は無理。", "Sorry, can't today.")],
                    praise: "いいね！"
                ),
                TutorRound(
                    prompt: TutorLine("マジで？あの新作、見た？", "Wait, did you watch the new episode?"),
                    replies: [TutorLine("見た！やばかった！", "I did! It was insane!"), TutorLine("まだ見てない。", "Haven't seen it yet.")],
                    praise: "最高！"
                ),
            ]
        case .hotel:
            return [
                TutorRound(
                    prompt: TutorLine("いらっしゃいませ。ご予約はありますか？", "Welcome. Do you have a reservation?"),
                    replies: [
                        TutorLine("はい、{name}で予約しています。", "Yes, under {name}."),
                        TutorLine("いいえ、予約していません。", "No, I don't."),
                    ],
                    praise: "完璧！"
                ),
                TutorRound(
                    prompt: TutorLine("朝食は七時からです。", "Breakfast starts at seven."),
                    replies: [TutorLine("Wi-Fiはありますか？", "Is there Wi-Fi?"), TutorLine("ありがとうございます。", "Thank you.")],
                    praise: "いいね！"
                ),
            ]
        }
    }

    var closing: TutorLine {
        switch self {
        case .food: return TutorLine("かしこまりました！", "Coming right up!")
        case .directions: return TutorLine("気をつけてね！", "Take care!")
        case .friends: return TutorLine("また話そうね！", "Let's talk again soon!")
        case .work: return TutorLine("お疲れ様です！", "Great work today!")
        case .anime: return TutorLine("じゃあ、また明日！", "See you tomorrow!")
        case .hotel: return TutorLine("ごゆっくりどうぞ。", "Enjoy your stay.")
        }
    }

    var tip: String {
        switch self {
        case .food: return "Add お願いします to the end of any order and you'll sound instantly polite."
        case .directions: return "もう一度お願いします is your lifeline. Use it whenever someone talks too fast."
        case .friends: return "With close friends, swap です for だよ. Same meaning, way more relaxed."
        case .work: return "お疲れ様です works as hello, thanks, and goodbye around the office."
        case .anime: return "Anime Japanese is casual. Drop です and ます with friends, keep them with strangers."
        case .hotel: return "Your name + で予約しています is all the front desk needs to find you."
        }
    }

    var weekPlan: [String] {
        switch self {
        case .food: return ["Ordering at the counter", "Asking for recommendations", "Paying and saying thanks", "Small talk with the chef"]
        case .directions: return ["Finding the station", "Left, right, straight", "Buying a train ticket", "Asking how long it takes"]
        case .friends: return ["Introducing yourself", "Talking hobbies", "Making weekend plans", "Texting like a local"]
        case .work: return ["Self-introduction", "Polite requests", "Meetings and schedules", "Wrapping up the day"]
        case .anime: return ["Casual speech basics", "Reactions: マジ, やばい, すごい", "Talking about shows", "Catching lines without subs"]
        case .hotel: return ["Checking in", "Asking about the room", "Breakfast and Wi-Fi", "Checking out smoothly"]
        }
    }

    var farewell: TutorLine {
        switch self {
        case .food: return TutorLine("ラーメン屋で待ってるね！", "See you at the ramen shop!")
        case .directions: return TutorLine("渋谷駅で待ってるね！", "Meet you at Shibuya Station!")
        case .friends: return TutorLine("カフェで待ってるね！", "Save me a seat at the café!")
        case .work: return TutorLine("オフィスで待ってるね！", "See you at the office!")
        case .anime: return TutorLine("屋上で待ってるね！", "Meet me on the rooftop!")
        case .hotel: return TutorLine("フロントで待ってるね！", "See you at the front desk!")
        }
    }
}
