//
//  ImmersionOnboardingFlow.swift
//  shizen
//
//  Immersion-first onboarding (playground only for now). The pitch is "hear a lot of
//  real Japanese you can understand", and Shizen does it two ways, both for everyone:
//  hand-crafted story lessons and curated real clips. Listen-first v2's teaching beats
//  (gap slider, unsquash, practice) aren't in this flow; they stay in `ListenFirstOnboardingFlow`.
//
//    Start:       hello (name, level) → why immersion (comprehensible input)
//    Two ways:    story lessons → real clips (the live feed, breakdowns as sheets)
//    Commitment:  daily minutes + plan (the one faux "building your plan" checklist) → promise the minutes
//    Hard sell:   team note → paywall → welcome → done
//
//  Nothing is persisted; every visit starts at screen 1.
//

import UIKit

enum ImmersionOnboardingFlow {
    static func makeSteps(session: ImmersionSession = ImmersionSession()) -> [OnboardingViewController] {
        let paywall = ListenFirstPaywallStepViewController()
        paywall.continuesToNextStep = true
        // Step ids are the analytics `step_name`s; keep them stable once shipped.
        return [
            ImmersionIntroStepViewController(session: session).withStepId("intro"),
            ImmersionWhyStepViewController(session: session).withStepId("why"),
            ImmersionLessonsStepViewController(session: session).withStepId("lessons"),
            ImmersionClipsStepViewController(session: session).withStepId("clips"),
            ImmersionPlanStepViewController(session: session).withStepId("plan"),
            ImmersionCommitStepViewController(session: session).withStepId("commit"),
            NaturalTeamNoteHanaStepViewController(session: session).withStepId(NaturalOnboardingFlow.teamNoteStepId),
            paywall.withStepId("paywall"),
            ImmersionWelcomeStepViewController(session: session).withStepId("welcome"),
        ]
    }
}

/// Full-screen modal that owns the coordinator and the floating Hana.
final class ImmersionOnboardingHostController: UINavigationController, AuthenticationDelegate {

    private let session = ImmersionSession()
    private let coordinator = OnboardingCoordinator(flow: .immersion)

    /// `preview`: the playground; writes nothing and isn't the gate.
    init(preview: Bool = true) {
        super.init(nibName: nil, bundle: nil)
        if preview {
            coordinator.enablePreviewMode()
        }
        coordinator.authenticationDelegate = self
        coordinator.injectedSteps = ImmersionOnboardingFlow.makeSteps(session: session)
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
        dismiss(animated: true)
    }
}

/// Name, level, and daily minutes (from the tutor session), plus what those minutes hold.
final class ImmersionSession: NaturalOnboardingSession {

    override var showsMascot: Bool { true }

    private let stage = OnboardingHanaStage()
    override var hanaStage: OnboardingHanaStage? { stage }

    /// 5 = N5 … 1 = N1, for the clip API.
    var jlptLevel: Int {
        switch level {
        case .brandNew, .kana: return 5
        case .someKanji: return 4
        case .conversational: return 3
        }
    }

    /// The real first lesson for this level, as on listen-first v2's path card.
    var firstLesson: (title: String, scenes: [String]) {
        switch level {
        case .brandNew, .kana: return ListenFirstContent.firstLesson(for: .beginner)
        case .someKanji, .conversational: return ListenFirstContent.firstLesson(for: .kaitoAndMika)
        }
    }

    var dailyMix: ImmersionContent.DailyMix { ImmersionContent.DailyMix(minutes: minutesPerDay) }
}

// MARK: - Content

enum ImmersionContent {

    /// What a day's minutes hold: a scene is about three minutes, a clip about one.
    struct DailyMix {
        let minutes: Int
        let scenes: Int
        let clips: Int

        init(minutes: Int) {
            self.minutes = minutes
            switch minutes {
            case ..<10:
                scenes = 1
                clips = 2
            case 10:
                scenes = 2
                clips = 3
            default:
                scenes = max(1, minutes / 5)
                clips = max(1, minutes * 3 / 10)
            }
        }

        /// "2 scenes + 3 clips"
        var summary: String {
            "\(scenes) \(scenes == 1 ? "scene" : "scenes") + \(clips) \(clips == 1 ? "clip" : "clips")"
        }
    }

    /// The daily-minutes picks on the plan step.
    static let minuteOptions = [5, 10, 20]

    /// Clip ids to open the clips screen on, in order, when they're at the learner's level.
    /// Empty: any feed clip at the level, newest first. Curate in Studio, then pin here.
    static let pinnedTasteClipIDs: [String] = []

    /// Most clips the clips screen loads.
    static let tasteClipLimit = 6

    /// Feed clips for the clips screen: rated exactly at `level`, else at or below it.
    /// Pinned ids first. Empty when the server can't be reached.
    static func tasteClips(level: Int) async -> [ClipSummary] {
        var clips = (try? await ContentCMSClient.fetchClipList(jlptLevel: level, feedOnly: true)) ?? []
        // Servers that predate `jlpt` ignore it.
        clips = clips.filter { $0.jlptLevel == level && $0.isInFeed }
        if clips.isEmpty {
            clips = ((try? await ContentCMSClient.fetchClipList(learnerLevel: level, feedOnly: true)) ?? [])
                .filter(\.isInFeed)
        }
        let pinned = pinnedTasteClipIDs.compactMap { id in clips.first { $0.clipID == id } }
        let rest = clips.filter { !pinnedTasteClipIDs.contains($0.clipID) }
        return Array((pinned + rest).prefix(tasteClipLimit))
    }
}
