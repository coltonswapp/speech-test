//
//  ImmersionSteps.swift
//  shizen
//
//  The immersion flow's own screens. Intro, plan, commit, team note, and paywall build on
//  the Natural / listen-first steps; see `ImmersionOnboardingFlow` for the order.
//
//  Hana's Japanese lines need native-speaker review before they ship, like all content.
//

import NNKit
import UIKit

/// Base for the immersion screens; keeps a typed handle on the session.
class ImmersionStepViewController: TutorStepViewController {

    let immersion: ImmersionSession

    init(session: ImmersionSession) {
        immersion = session
        super.init(session: session)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// A chat filling the stage that scrolls up under the header.
    func installChat() -> TutorChatView {
        let chat = makeChat()
        stage.addSubview(chat)
        NSLayoutConstraint.activate([
            chat.topAnchor.constraint(equalTo: stage.topAnchor),
            chat.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            chat.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            chat.bottomAnchor.constraint(equalTo: stage.bottomAnchor),
        ])
        scrollUnderHeader(chat, scrollView: chat.scrollContainer)
        return chat
    }
}

// MARK: - Start · Hello

/// The Natural hello (name, level) with three plain-language levels, leading into why immersion works.
final class ImmersionIntroStepViewController: NaturalIntroStepViewController {

    override var levelOptions: [(level: TutorLevel, title: String)] {
        [
            (.brandNew, "🌱  Brand new"),
            (.kana, "🧩  I understand bits and pieces"),
            (.conversational, "💬  I can hold a conversation"),
        ]
    }

    override var ideaLines: [String] {
        [
            "Got it. Before we start, let me tell you how Shizen actually works.",
            "It's not flashcards, and it's not grammar drills.",
        ]
    }

    override var ideaCTA: String { "Tell me" }
}

// MARK: - Start · Why immersion

/// Comprehensible input in Hana's words, with what a little every day adds up to.
/// The numbers are this app's own math (`DailyMix` at 10 minutes), not research figures.
final class ImmersionWhyStepViewController: ImmersionStepViewController {

    override var progressBeatCount: Int { 2 }

    private var chat: TutorChatView?

    override func buildStage() {
        setupOnboarding(title: "How languages stick", subtitle: "Hint: it's not memorizing.")
        chat = installChat()
    }

    override func play() {
        timeline.after(0.35) { [weak self] in
            self?.chat?.play([
                .tutorText("Linguist Stephen Krashen calls it comprehensible input."),
                .tutorText("You pick up a language by understanding real messages, just a little above your level. The rules sink in on their own."),
                .tutorText("So the trick is simple: hear a lot of Japanese you can almost understand."),
            ]) { [weak self] in
                self?.showFacts()
            }
        }
    }

    private func showFacts() {
        guard let chat else { return }
        advanceProgressBeat(to: 1)
        let mix = ImmersionContent.DailyMix(minutes: 10)
        let yearlyHours = mix.minutes * 365 / 60
        let yearlyListens = (mix.scenes + mix.clips) * 365
        let card = ImmersionFactCard(
            facts: [
                ("\(yearlyHours)+ hrs", "of real Japanese a year"),
                ("\(yearlyListens.formatted())", "scenes and clips a year"),
            ],
            footnote: "At just 10 minutes a day, every day."
        )
        chat.appendCustom(card)
        HapticsHelper.lightHaptic()
        timeline.after(0.9) { [weak self] in
            self?.chat?.play([
                .tutorText("That's what Shizen is for. Lots of real Japanese, a little every day."),
                .tutorText("We do it two ways. Let me show you."),
            ]) { [weak self] in
                self?.revealCTA("Show me")
            }
        }
    }
}

/// Big numbers side by side on the stat card's surface.
final class ImmersionFactCard: UIView {

    init(facts: [(value: String, caption: String)], footnote: String?) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = ExperimentPalette.cardSurface
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.borderWidth = ExperimentCardStroke.normalWidth
        layer.borderColor = ExperimentPalette.cardBorder.cgColor

        let tiles = UIStackView(arrangedSubviews: facts.map { Self.tile(value: $0.value, caption: $0.caption) })
        tiles.distribution = .fillEqually
        tiles.spacing = 12

        let stack = UIStackView(arrangedSubviews: [tiles])
        stack.axis = .vertical
        stack.spacing = 14
        if let footnote {
            let label = UILabel()
            label.text = footnote
            label.font = .preferredFont(forTextStyle: .footnote)
            label.textColor = .secondaryLabel
            label.numberOfLines = 0
            stack.addArrangedSubview(label)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
        ])

        isAccessibilityElement = true
        accessibilityLabel = (facts.map { "\($0.value) \($0.caption)" } + [footnote].compactMap { $0 })
            .joined(separator: ". ")
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ImmersionFactCard, _) in
            view.layer.borderColor = ExperimentPalette.cardBorder.cgColor
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func tile(value: String, caption: String) -> UIView {
        let valueLabel = UILabel()
        valueLabel.text = value
        let base = UIFont.systemFont(ofSize: 28, weight: .bold)
        valueLabel.font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 28) } ?? base
        valueLabel.textColor = .label
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7

        let captionLabel = UILabel()
        captionLabel.text = caption
        captionLabel.font = .preferredFont(forTextStyle: .footnote)
        captionLabel.textColor = .secondaryLabel
        captionLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [valueLabel, captionLabel])
        stack.axis = .vertical
        stack.spacing = 2
        return stack
    }
}

// MARK: - Two ways · Story lessons

/// Way 1: their real first lesson as swipeable scene cards, and what every lesson has.
final class ImmersionLessonsStepViewController: ImmersionStepViewController {

    private static let features = [
        ("headphones", "Audio conversations, written for your level"),
        ("sparkles", "Highlights on the phrases that matter"),
        ("checkmark.circle", "Quick quizzes to check you caught it"),
    ]

    private var featureRows: [UIView] = []
    private var header: UIView?
    private var carousel: UIView?

    override func buildStage() {
        setupOnboarding(title: "Way 1 · Story lessons", subtitle: "Hand-crafted audio, made for listening.")

        let lesson = immersion.firstLesson
        let eyebrow = UILabel()
        eyebrow.text = "YOUR FIRST LESSON"
        eyebrow.font = .systemFont(ofSize: 12, weight: .bold)
        eyebrow.textColor = .secondaryLabel
        let title = UILabel()
        title.text = lesson.title
        title.font = .systemFont(ofSize: 22, weight: .bold)
        let header = UIStackView(arrangedSubviews: [eyebrow, title])
        header.axis = .vertical
        header.alignment = .center
        header.spacing = 2
        self.header = header

        // Only a handful of thumbnails exist yet; shuffle so neighbors don't repeat.
        var thumbnails = ListenFirstContent.sceneThumbnails.shuffled()
        let scenes = lesson.scenes.enumerated().map { index, scene in
            if thumbnails.isEmpty { thumbnails = ListenFirstContent.sceneThumbnails.shuffled() }
            return ListenFirstSceneCarousel.Scene(label: "Scene \(index + 1)", title: scene, thumbnail: thumbnails.removeLast())
        }
        let carousel = ListenFirstSceneCarousel(scenes: scenes)
        carousel.onFocusChanged = { _ in HapticsHelper.superLightHaptic() }
        self.carousel = carousel

        featureRows = Self.features.map { Self.featureRow(symbol: $0.0, text: $0.1) }
        let features = UIStackView(arrangedSubviews: featureRows)
        features.axis = .vertical
        features.spacing = 14

        for subview in [header, carousel, features] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            subview.alpha = 0
            stage.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: stage.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -24),

            carousel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            carousel.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            carousel.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            carousel.heightAnchor.constraint(equalToConstant: ListenFirstSceneCarousel.height),

            features.topAnchor.constraint(equalTo: carousel.bottomAnchor, constant: 20),
            features.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: 36),
            features.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -36),
            features.bottomAnchor.constraint(lessThanOrEqualTo: stage.bottomAnchor),
        ])
        features.alpha = 1
        featureRows.forEach { $0.alpha = 0 }
    }

    override func play() {
        guard let header, let carousel else { return }
        slideIn([header, carousel], stagger: 0.1, initialDelay: 0.15)
        HapticsHelper.lightHaptic()
        timeline.after(0.7) { [weak self] in
            guard let self else { return }
            self.slideIn(self.featureRows, stagger: 0.12)
            self.timeline.after(0.6) { [weak self] in self?.revealCTA("Next") }
        }
    }

    private static func featureRow(symbol: String, text: String) -> UIView {
        let icon = UIImageView(image: UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        ))
        icon.tintColor = .label
        icon.contentMode = .center
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 26).isActive = true

        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        label.numberOfLines = 0

        let row = UIStackView(arrangedSubviews: [icon, label])
        row.spacing = 14
        row.alignment = .center
        return row
    }
}

// MARK: - Two ways · Real clips

/// Way 2: real clips at their level, in the actual clip feed. Tap words, open a line's
/// breakdown (as a sheet here), swipe for the next. The CTA shows after a swipe or a
/// short watch, whichever comes first.
final class ImmersionClipsStepViewController: ImmersionStepViewController {

    /// Seconds on the first clip before the CTA shows without a swipe.
    private static let ctaDelay: TimeInterval = 12

    private var feed: ClipFeedViewController?
    private let spinner = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()
    private var loadTask: Task<Void, Never>?
    private var hasRevealedCTA = false

    override func buildStage() {
        setupOnboarding(title: "Way 2 · Real clips", subtitle: "Tap a word for its meaning, or open a line's breakdown. Swipe up for more.")
        removeFeed()
        loadTask?.cancel()
        hasRevealedCTA = false

        spinner.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = nil
        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        stage.addSubview(spinner)
        stage.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: stage.centerYAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: stage.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: 32),
            statusLabel.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -32),
        ])
        spinner.startAnimating()

        let level = immersion.jlptLevel
        loadTask = Task { [weak self] in
            let clips = await ImmersionContent.tasteClips(level: level)
            guard !Task.isCancelled, let self else { return }
            self.spinner.stopAnimating()
            if clips.isEmpty {
                self.statusLabel.text = "Couldn't load clips right now. You'll find them in the app."
                self.showCTA()
            } else {
                self.installFeed(clips)
            }
        }
    }

    override func play() {
        timeline.after(Self.ctaDelay) { [weak self] in self?.showCTA() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        feed?.setActive(true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        feed?.setActive(false)
    }

    /// Taps inside the feed are for the feed (words, transport), never tap-to-skip.
    override func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let feedView = feed?.view, let touched = touch.view, touched.isDescendant(of: feedView) {
            return false
        }
        return super.gestureRecognizer(gestureRecognizer, shouldReceive: touch)
    }

    private func installFeed(_ clips: [ClipSummary]) {
        let feed = ClipFeedViewController(clips: clips)
        feed.analyticsSource = ClipAnalytics.onboarding
        feed.allowsExploring = false
        // Onboarding's navigation stack isn't the feed's: a pushed breakdown would land in the flow.
        feed.presentsBreakdownAsSheet = true
        // Fires on swipes only, not the opening clip.
        feed.onClipChanged = { [weak self] in self?.showCTA() }
        self.feed = feed
        addChild(feed)
        feed.view.translatesAutoresizingMaskIntoConstraints = false
        feed.view.alpha = 0
        stage.addSubview(feed.view)
        NSLayoutConstraint.activate([
            feed.view.topAnchor.constraint(equalTo: stage.topAnchor),
            feed.view.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            feed.view.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            feed.view.bottomAnchor.constraint(equalTo: stage.bottomAnchor),
        ])
        feed.didMove(toParent: self)
        // Off screen (moved on already): don't start audio behind the next step.
        feed.setActive(view.window != nil && presentedViewController == nil)
        UIView.animate(withDuration: AnimationDefaults.standardDuration) {
            feed.view.alpha = 1
        }
    }

    private func removeFeed() {
        guard let feed else { return }
        feed.setActive(false)
        feed.willMove(toParent: nil)
        feed.view.removeFromSuperview()
        feed.removeFromParent()
        self.feed = nil
    }

    private func showCTA() {
        guard !hasRevealedCTA else { return }
        hasRevealedCTA = true
        revealCTA("Keep going")
    }

    override func ctaTapped() {
        feed?.setActive(false)
        super.ctaTapped()
    }
}

// MARK: - Commitment · Plan

/// Daily minutes, each shown as the lessons and clips it holds; the eight-week stat; a faux
/// "building your plan" checklist; then the day's mix.
final class ImmersionPlanStepViewController: NaturalPlanStepViewController {

    private var immersion: ImmersionSession { natural as! ImmersionSession }

    override var planPicker: (title: String, subtitle: String, options: [(minutes: Int, text: String)]) {
        let icons = ["☕️", "🍵", "🔥"]
        return (
            "How long do you want to learn each day?",
            "A scene takes about three minutes. Most clips, about one.",
            ImmersionContent.minuteOptions.enumerated().map { index, minutes in
                let icon = icons.indices.contains(index) ? icons[index] : "🎧"
                return (minutes, "\(icon)  \(minutes) min · \(ImmersionContent.DailyMix(minutes: minutes).summary)")
            }
        )
    }

    override var planGeneratingTitle: String { "Building your plan…" }
    override var planGeneratingSubtitle: String { "Hana is lining up what you'll hear." }

    override var planChecklist: [String] {
        let mix = immersion.dailyMix
        return [
            "Matching lessons and clips to \(natural.track) Japanese",
            "Starting you on \(immersion.firstLesson.title)",
            "Lining up \(mix.clips) clips a day at your level",
        ]
    }

    override var statUnit: String { "listens" }

    override var statFootnote: String? {
        "Total listening at \(natural.minutesPerDay) min a day, every day."
    }

    override var statReactions: [TutorLine] {
        [
            TutorLine("うわー！8週間でこんなに聞けるの？", "Whoa, you'll hear this much in 8 weeks?"),
            TutorLine("毎日ちょっとずつで大丈夫。", "A little every day is all it takes."),
            TutorLine("頑張ろうね！", "Let's do this!"),
        ]
    }

    override var planReadyHeader: (title: String, subtitle: String) {
        ("Your plan is ready.", "Set up for \(natural.displayName) · \(natural.minutesPerDay) min a day")
    }

    override var planCard: TutorPlanCard.Content {
        let mix = immersion.dailyMix
        return TutorPlanCard.Content(
            eyebrow: "\(natural.track) · YOUR DAILY MIX",
            title: "Every day",
            rows: [
                TutorPlanCard.Row(
                    label: "🎧",
                    title: "\(mix.scenes) \(mix.scenes == 1 ? "scene" : "scenes") from \(immersion.firstLesson.title)",
                    detail: nil
                ),
                TutorPlanCard.Row(
                    label: "📱",
                    title: "\(mix.clips) real \(mix.clips == 1 ? "clip" : "clips") at your level",
                    detail: nil
                ),
            ]
        )
    }

    override var planSummary: String {
        "Lessons build your ear. Clips put it to work. Both are immersion."
    }

    override var pathReadyLines: [TutorLine] {
        [
            TutorLine("プラン、できたよ！", "Your plan is ready!"),
            TutorLine("レッスンも動画も、毎日ちょっとずつね。", "Lessons and videos, a little each day."),
        ]
    }
}

// MARK: - Commitment · Promise

/// Slide to promise the daily minutes they just picked on the plan step.
final class ImmersionCommitStepViewController: NaturalCommitStepViewController {

    private var minutes: Int { natural.minutesPerDay }

    override var promiseCaption: String { "I'll immerse for \(minutes) minutes a day." }

    override var askLines: [TutorLine] {
        [
            TutorLine("ちょっと待って。", "Hold on a sec."),
            TutorLine("正直に言うね。一番大事なのは、毎日聞くこと。", "I'll be honest: what matters most is listening every day."),
            TutorLine("毎日\(minutes)分、日本語を聞くって約束できる？", "Can you promise \(minutes) minutes of Japanese a day?"),
        ]
    }

    override var dealSubtitle: String { "\(minutes) minutes a day of real Japanese." }

    override var dealLines: [TutorLine] {
        [
            TutorLine("約束だよ！", "It's a promise!"),
            TutorLine("毎日ちょっとずつ、一緒に頑張ろう！", "A little every day. Let's do this together!"),
        ]
    }
}

// MARK: - Hard sell · Welcome

/// The last screen, after the paywall: a warm welcome and what's waiting. The CTA closes the flow.
final class ImmersionWelcomeStepViewController: TutorReadyStepViewController {

    override var locksOnboardingBack: Bool { true }
    override var hidesOnboardingProgress: Bool { true }

    private let immersion: ImmersionSession

    init(session: ImmersionSession) {
        immersion = session
        super.init(session: session)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildStage() {
        super.buildStage()
        setupOnboarding(title: "We're so glad you're here, \(immersion.displayName).", subtitle: readySubtitle)
    }

    override var readySubtitle: String { "Your first lesson and clips are ready." }
    override var readyBadge: String { "ようこそ！" }
    override var readyBadgeEnglish: String { "Welcome!" }
    override var readyCapsules: [String] {
        [
            "🎧  \(immersion.firstLesson.title)",
            "📱  Clips at your level",
            "⏱️  \(immersion.minutesPerDay) min a day",
        ]
    }
    override var readyFarewell: TutorLine { TutorLine("これからよろしくね！", "I'm excited to learn with you!") }
    override var readyCTA: String { "Let's go" }
}
