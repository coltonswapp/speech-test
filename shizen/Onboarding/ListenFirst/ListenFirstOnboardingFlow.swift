//
//  ListenFirstOnboardingFlow.swift
//  shizen
//
//  Listening-first v2: payoff first, setup second. One shared conversation
//  (Mika talking Kaito into tomorrow's drinks) built around the three phrases from
//  "Textbooks vs. real life", so the first blind listen lands on screen 3.
//
//  Level is asked in the welcome chat. Commitment and send-off are the shared Natural steps.
//  Resume is switched off for now (`resumesProgress`): every visit starts at screen 1.
//  With it on, answers are saved on-device as each screen is finished; relaunching resumes
//  at the next unfinished screen. Sign-in already happened on the splash, so the flow doesn't ask.
//  After the ready step: Hana's team note, then the compact paywall, with no way back from either.
//
//  Audio (11 clips; any missing one falls back to on-device TTS):
//    listenfirst-conversation           the whole conversation as one M4A with line switch times
//                                       embedded (`DialogueAlignmentMetadata`), or no line plays
//    listenfirst-gap-{1,2,3}-textbook   分かりません。 / 何をしているのですか？ / 行かなければなりません。
//    listenfirst-gap-{1,2,3}-real       わかんない。 / 何してんの？ / 行かなきゃ。
//    listenfirst-unsquash-1-step-{1,2}  何してるの？ / 何をしているの？
//    listenfirst-unsquash-2-step-1      行かなければならない。
//    listenfirst-callout-wakaranai      分からない
//

import UIKit

enum ListenFirstOnboardingFlow {
    static func makeSteps(session: ListenFirstSession = ListenFirstSession()) -> [OnboardingViewController] {
        NaturalVoicePlayer.prewarm(ListenFirstContent.lineClip(at: 0))
        // Step ids are the analytics `step_name`s; keep them stable once shipped.
        return [
            NaturalIntroStepViewController(session: session).withStepId("intro"),
            ListenFirstGapStepViewController(session: session).withStepId("gap"),
            ListenFirstListenStepViewController(session: session).withStepId("listen"),
            ListenFirstBreakdownStepViewController(session: session).withStepId("breakdown"),
            ListenFirstPracticeStepViewController(session: session).withStepId("practice"),
            ListenFirstPlanStepViewController(session: session).withStepId("plan"),
            NaturalCommitStepViewController(session: session).withStepId("commit"),
            NaturalReadyStepViewController(session: session).withStepId("ready"),
            NaturalTeamNoteHanaStepViewController(session: session).withStepId(NaturalOnboardingFlow.teamNoteStepId),
            makePaywallStep(),
        ]
    }

    static func makePaywallStep() -> OnboardingViewController {
        ListenFirstPaywallStepViewController().withStepId("paywall")
    }
}

/// The compact glass paywall as an onboarding step. The only way past it is access: a trial,
/// purchase, or restore writes the entitlement, then finishes setup into the app.
final class ListenFirstPaywallStepViewController: OnboardingViewController {

    override var hidesOnboardingBackButton: Bool { true }
    override var locksOnboardingBack: Bool { true }
    override var hidesOnboardingProgress: Bool { true }

    /// Access moves on to the next step instead of finishing setup (the immersion flow's
    /// getting-ready screen comes after it).
    var continuesToNextStep = false

    private let paywall = PaywallBoldHeroGlassViewController(
        provider: MockPaywallProvider(),
        headline: .compact,
        showsClose: false
    )

    override func setupContent() {
        paywall.onAccessGranted = { [weak self] package in
            guard let coordinator = self?.coordinator else { return }
            if !coordinator.isPreviewMode {
                ProMembership.recordAccess(for: package)
            }
            if self?.continuesToNextStep == true {
                coordinator.next()
            } else {
                coordinator.finishSetup()
            }
        }
        addChild(paywall)
        paywall.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(paywall.view)
        NSLayoutConstraint.activate([
            paywall.view.topAnchor.constraint(equalTo: view.topAnchor),
            paywall.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            paywall.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            paywall.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        paywall.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if coordinator?.isPreviewMode == false {
            OnboardingStore.markLessonStepsFinishedForCurrentUser()
        }
    }

    func trackAbandoned() {
        paywall.trackAbandoned()
    }
}

/// Full-screen modal that owns the coordinator, restores saved answers, and resumes mid-flow.
final class ListenFirstOnboardingHostController: UINavigationController, AuthenticationDelegate {

    enum Mode {
        /// Playground: writes nothing and isn't the gate.
        case preview
        /// The production gate, from the intro.
        case fullFlow
        /// The production gate once the lesson steps are done.
        case paywallOnly
    }

    /// Off while the flow is being tuned: every visit restarts at screen 1. Flip on to save
    /// answers per screen and resume at the next unfinished one.
    private static let resumesProgress = false

    private let session = ListenFirstSession()
    private let coordinator = OnboardingCoordinator(flow: .listenFirst)

    init(mode: Mode = .preview) {
        super.init(nibName: nil, bundle: nil)
        if !Self.resumesProgress {
            // Every visit starts from the top; drop anything an older build saved.
            ListenFirstSession.clearSaved()
        }
        let resumeIndex = Self.resumesProgress ? session.restore() : 0
        if mode == .preview {
            coordinator.enablePreviewMode()
        }
        coordinator.authenticationDelegate = self
        coordinator.injectedSteps = mode == .paywallOnly
            ? [ListenFirstOnboardingFlow.makePaywallStep()]
            : ListenFirstOnboardingFlow.makeSteps(session: session)
        coordinator.initialStepIndex = resumeIndex
        if Self.resumesProgress {
            coordinator.stepCompletionHandler = { [session] index in
                session.save(completedStep: index)
            }
        }
        setViewControllers([coordinator.start()], animated: false)
        setNavigationBarHidden(true, animated: false)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        session.hanaStage?.install(in: view)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        session.hanaStage?.bringToFront()
    }

    func signUpComplete() {
        ListenFirstSession.clearSaved()
        dismiss(animated: true)
    }
}

/// The Natural session plus on-device persistence and named tracks (no N5 / N4 / N3 in the UI).
final class ListenFirstSession: NaturalOnboardingSession {

    private static let storageKey = "onboarding.listenFirst.progress"

    private struct Snapshot: Codable {
        var completedStep: Int
        var name: String
        var level: Int
        var minutesPerDay: Int
        var caughtGist: Bool?
        var promised: Bool
    }

    enum Track {
        case beginner
        case kaitoAndMika

        var title: String {
            switch self {
            case .beginner: return "Beginner"
            case .kaitoAndMika: return "Kaito & Mika"
            }
        }
    }

    var trackKind: Track {
        switch level {
        case .brandNew, .kana: return .beginner
        case .someKanji, .conversational: return .kaitoAndMika
        }
    }

    override var track: String { trackKind.title }

    override var showsMascot: Bool { true }

    private let stage = OnboardingHanaStage()
    override var hanaStage: OnboardingHanaStage? { stage }

    override func breakdown(for japanese: String) -> SentenceScrubScript? {
        ListenFirstContent.breakdowns[japanese]
    }

    override var dissectsEveryLine: Bool { true }

    /// Lines always show kanji with furigana; the level doesn't change them yet.
    func defaultText(_ line: ListenFirstLine) -> String {
        line.japanese
    }

    func save(completedStep: Int) {
        let snapshot = Snapshot(
            completedStep: completedStep,
            name: name,
            level: level.rawValue,
            minutesPerDay: minutesPerDay,
            caughtGist: caughtGist,
            promised: promised
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    /// Loads saved answers into the session and returns the step index to resume on.
    func restore() -> Int {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return 0 }
        name = snapshot.name
        level = TutorLevel(rawValue: snapshot.level) ?? .brandNew
        minutesPerDay = snapshot.minutesPerDay
        caughtGist = snapshot.caughtGist
        promised = snapshot.promised
        return snapshot.completedStep + 1
    }

    static func clearSaved() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

// MARK: - Content

struct ListenFirstLine {
    /// 0 is Kaito (leading, blue), 1 is Mika (trailing, yellow).
    let speaker: Int
    let japanese: String
    let english: String
}

/// One form on the unsquash ladder, from spoken back to textbook.
struct ListenFirstForm {
    let text: String
    /// Substrings that changed from the previous form; they're highlighted.
    let changed: [String]
    let change: String?
    let note: String?
    let clip: NaturalClip
}

struct ListenFirstChunk {
    let line: Int
    let meaning: String
    let tiles: [NaturalPiece]
    /// `forms[0]` is the spoken form; the last is the textbook form.
    let forms: [ListenFirstForm]
}

/// One "Textbooks vs. real life" pair, cut into pieces for the squash animation.
struct ListenFirstSquash {

    struct Piece {
        let textbook: String
        /// Empty when the piece drops out of speech.
        let real: String

        init(_ textbook: String, _ real: String) {
            self.textbook = textbook
            self.real = real
        }

        var drops: Bool { real.isEmpty }
        var changes: Bool { !real.isEmpty && real != textbook }
    }

    /// Index into `NaturalContrast.all`.
    let contrast: Int
    let pieces: [Piece]

    var textbook: String { pieces.map(\.textbook).joined() }
    var real: String { pieces.map(\.real).joined() }
    var english: String { NaturalContrast.all[contrast].english }

    init(contrast: Int, pieces: [Piece]) {
        self.contrast = contrast
        self.pieces = pieces
        assert(real == NaturalContrast.all[contrast].real, "Squash pieces don't spell \(NaturalContrast.all[contrast].real)")
    }
}

/// The "same trick" strip: another word where a sound melts into ん.
struct ListenFirstCallout {
    let from: ListenFirstForm
    let to: ListenFirstForm
    let caption: String
}

enum ListenFirstContent {

    static let speakers = ["Kaito", "Mika"]
    static let sceneTitle = "🍻 Drinks tomorrow"

    // Needs native-speaker review before it ships, like all content.
    static let conversation = [
        ListenFirstLine(speaker: 1, japanese: "何してんの？", english: "What are you doing?"),
        ListenFirstLine(speaker: 0, japanese: "明日の飲み会、行くか迷ってる。", english: "Trying to decide whether to go to drinks tomorrow."),
        ListenFirstLine(speaker: 1, japanese: "え、行かなきゃ！サキちゃん来るよ。", english: "You have to go! Saki's coming."),
        ListenFirstLine(speaker: 0, japanese: "…マジで？何着ればいいかわかんない。", english: "...Seriously? I don't know what to wear."),
    ]

    static func lineClip(at index: Int) -> NaturalClip {
        let line = conversation[index]
        return NaturalClip(text: line.japanese, voice: line.speaker, audioName: "listenfirst-conversation", segment: index)
    }

    /// "Textbooks vs. real life", one squash per `NaturalContrast` pair: the textbook line cut
    /// into pieces, and what each piece becomes when spoken. An empty `real` drops out; a
    /// different one changes. The reals joined must spell the contrast's real line.
    static let squashes: [ListenFirstSquash] = [
        // Written in kana so the squash is about sound, not 分 turning into わ.
        ListenFirstSquash(contrast: 0, pieces: [
            .init("わか", "わか"),
            .init("り", "ん"),
            .init("ません", "ない"),
            .init("。", "。"),
        ]),
        ListenFirstSquash(contrast: 1, pieces: [
            .init("何", "何"),
            .init("を", ""),
            .init("して", "して"),
            .init("い", ""),
            .init("る", "ん"),
            .init("の", "の"),
            .init("ですか", ""),
            .init("？", "？"),
        ]),
        ListenFirstSquash(contrast: 2, pieces: [
            .init("行かな", "行かな"),
            .init("ければなりません", "きゃ"),
            .init("。", "。"),
        ]),
    ]

    static func gapClip(at index: Int, textbook: Bool) -> NaturalClip {
        let contrast = NaturalContrast.all[index]
        return NaturalClip(
            text: textbook ? contrast.textbook : contrast.real,
            voice: textbook ? 0 : 1,
            audioName: "listenfirst-gap-\(index + 1)-\(textbook ? "textbook" : "real")"
        )
    }

    /// The gap slider's detents: what each step down from the textbook takes away.
    static let gapStages: [(title: String, hint: String)] = [
        ("Textbook", "Polite and complete, like a textbook."),
        ("Casual", "Drop the politeness. Every sound stays."),
        ("Real life", "Squash the sounds. What people say."),
    ]

    /// Each `NaturalContrast` pair at every gap stage, textbook first. The casual forms reuse
    /// the unsquash and callout recordings. One voice for all three, so the only thing that
    /// changes as you slide is the line itself.
    static let gapForms: [[NaturalClip]] = [
        [
            // In kana, like the squash, so the slide is about sound and not 分 turning into わ.
            NaturalClip(text: "わかりません。", voice: 1, audioName: "listenfirst-gap-1-textbook"),
            NaturalClip(text: "わからない。", voice: 1, audioName: "listenfirst-callout-wakaranai"),
            gapClip(at: 0, textbook: false),
        ],
        [
            gapClip(at: 1, textbook: true),
            NaturalClip(text: "何をしているの？", voice: 1, audioName: "listenfirst-unsquash-1-step-2"),
            gapClip(at: 1, textbook: false),
        ],
        [
            gapClip(at: 2, textbook: true),
            NaturalClip(text: "行かなければならない。", voice: 1, audioName: "listenfirst-unsquash-2-step-1"),
            gapClip(at: 2, textbook: false),
        ],
    ].map { forms in forms.map { NaturalClip(text: $0.text, voice: 1, audioName: $0.audioName) } }

    static let gist = NaturalGist(
        question: "What's going on?",
        options: [
            "Someone's unsure about going out, until they hear who'll be there",
            "Two friends are deciding where to eat dinner",
            "Someone is asking for directions",
        ],
        answer: 0
    )

    static let chunks = [
        ListenFirstChunk(
            line: 0,
            meaning: "What are you up to?",
            tiles: [
                NaturalPiece(japanese: "何", gloss: "what"),
                NaturalPiece(japanese: "して", gloss: "doing"),
                NaturalPiece(japanese: "ん", gloss: "is"),
                NaturalPiece(japanese: "の", gloss: "?"),
            ],
            forms: [
                ListenFirstForm(text: "何してんの？", changed: [], change: nil, note: nil, clip: gapClip(at: 1, textbook: false)),
                ListenFirstForm(
                    text: "何してるの？",
                    changed: ["る"],
                    change: "ん → る",
                    note: "る gets squashed into ん before の.",
                    clip: NaturalClip(text: "何してるの？", voice: 1, audioName: "listenfirst-unsquash-1-step-1")
                ),
                ListenFirstForm(
                    text: "何をしているの？",
                    changed: ["を", "い"],
                    change: "を and い come back",
                    note: "Little words drop out because you can guess them.",
                    clip: NaturalClip(text: "何をしているの？", voice: 1, audioName: "listenfirst-unsquash-1-step-2")
                ),
                ListenFirstForm(
                    text: "何をしているのですか？",
                    changed: ["のですか"],
                    change: "のですか added",
                    note: "Textbook: complete, polite, and slow.",
                    clip: gapClip(at: 1, textbook: true)
                ),
            ]
        ),
        ListenFirstChunk(
            line: 2,
            meaning: "You have to go.",
            tiles: [
                NaturalPiece(japanese: "行か", gloss: "go"),
                NaturalPiece(japanese: "なきゃ", gloss: "must"),
            ],
            forms: [
                ListenFirstForm(text: "行かなきゃ。", changed: [], change: nil, note: nil, clip: gapClip(at: 2, textbook: false)),
                ListenFirstForm(
                    text: "行かなければならない。",
                    changed: ["なければならない"],
                    change: "なきゃ → なければならない",
                    note: "なきゃ is なければならない with the end cut off.",
                    clip: NaturalClip(text: "行かなければならない。", voice: 1, audioName: "listenfirst-unsquash-2-step-1")
                ),
                ListenFirstForm(
                    text: "行かなければなりません。",
                    changed: ["りません"],
                    change: "ない → ません",
                    note: "Textbook polite.",
                    clip: gapClip(at: 2, textbook: true)
                ),
            ]
        ),
    ]

    /// Shown under chunk 1 once it reaches the textbook form.
    static let callout = ListenFirstCallout(
        from: ListenFirstForm(
            text: "分からない",
            changed: ["ら"],
            change: nil,
            note: nil,
            clip: NaturalClip(text: "分からない", voice: 0, audioName: "listenfirst-callout-wakaranai")
        ),
        to: ListenFirstForm(text: "わかんない", changed: ["ん"], change: nil, note: nil, clip: gapClip(at: 0, textbook: false)),
        caption: "Same trick. A sudden ん where you expected る or ら is usually this."
    )

    /// Lesson thumbnails in the asset catalog (`lesson-thumbnails`). Scenes don't have
    /// their own art yet, so the path carousel picks from these at random.
    static let sceneThumbnails = ["train-station", "at-the-library", "at-the-convenient-store", "asking-directions"]

    /// The real first lesson for each track, shown on the path card.
    static func firstLesson(for track: ListenFirstSession.Track) -> (title: String, scenes: [String]) {
        switch track {
        case .beginner:
            // Unit A, Lesson 1. PLACEHOLDER scene titles so the path carousel has cards;
            // swap in the real ones when they're written.
            return ("🏡 Emi arrives", ["At the door", "Saying hello", "Settling in"])
        case .kaitoAndMika:
            return ("🍵 First Hello", ["Shizuoka tea", "Nine o'clock", "Which mailbox"])
        }
    }
}
