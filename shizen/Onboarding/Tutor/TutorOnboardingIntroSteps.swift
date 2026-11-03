//
//  TutorOnboardingIntroSteps.swift
//  shizen
//
//  Hana says hello and gets a name, the goal grid collapses into the chosen
//  scene, and the level slider morphs one sample line in place.
//

import NNKit
import UIKit

// MARK: - Hello

final class TutorIntroStepViewController: TutorStepViewController {

    override var progressBeatCount: Int { 2 }

    private var chat: TutorChatView?
    private let composer = TutorNameComposer()

    override func buildStage() {
        setupOnboarding(title: "Meet Hana", subtitle: "Your speaking partner for Japanese.")

        let chat = makeChat()
        stage.addSubview(chat)
        NSLayoutConstraint.activate([
            chat.topAnchor.constraint(equalTo: stage.topAnchor),
            chat.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            chat.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            chat.bottomAnchor.constraint(equalTo: stage.bottomAnchor),
        ])
        self.chat = chat
        scrollUnderHeader(chat, scrollView: chat.scrollContainer)

        composer.install(in: view, above: stage)
        composer.onSubmit = { [weak self] name in self?.submitName(name) }
        composer.reset()
    }

    override func play() {
        timeline.after(0.35) { [weak self] in
            self?.chat?.play([.tutorJapanese(TutorLine("こんにちは！", "Hi there!"))]) { [weak self] in
                self?.showSkipHintIfFirstRun()
                self?.chat?.play([
                    .tutorText("I'm Hana. I'll get you speaking Japanese out loud, starting today."),
                    .tutorText("First things first: what should I call you?"),
                ]) { [weak self] in
                    self?.composer.open()
                }
            }
        }
    }

    override func resetStage() {
        composer.dismissKeyboard()
        super.resetStage()
    }

    private func submitName(_ submitted: String) {
        session.name = submitted
        composer.close(in: view)

        let name = session.displayName
        advanceProgressBeat(to: 1)
        chat?.play([
            .userText(name),
            .tutorJapanese(TutorLine("\(name)さん、よろしくね！", "Nice to meet you, \(name)!")),
            .tutorText("Four quick questions, then I'll write a first conversation just for you."),
        ]) { [weak self] in
            self?.revealCTA("Let's go")
        }
    }
}

// MARK: - Goal

struct TutorGoalChoice {
    let emoji: String
    let title: String
}

/// What the guide says once a card settles at the top: header, chat beats, then phrase bubbles.
struct TutorGoalPreview {
    let title: String
    let subtitle: String
    let messages: [TutorChatView.Message]
    let phrases: [TutorLine]
    /// Phrases show Japanese only; a left swipe reveals each one's English, and the top one demos it.
    var hidesEnglishUntilSwipe = false
    /// Scripted breakdowns behind a right swipe on each phrase, where there are any.
    var breakdown: (TutorLine) -> SentenceScrubScript? = { _ in nil }
}

class TutorGoalStepViewController: TutorStepViewController {

    override var progressBeatCount: Int { 2 }

    // MARK: Content hooks (the grid, hero settle, and preview choreography stay shared)

    var choiceHeader: (title: String, subtitle: String) {
        ("Where do you want to speak first?", "Hana writes your first scene around it.")
    }

    var choices: [TutorGoalChoice] {
        TutorGoal.allCases.map { TutorGoalChoice(emoji: $0.emoji, title: $0.title) }
    }

    func choose(at index: Int) {
        session.goal = TutorGoal.allCases[index]
    }

    var preview: TutorGoalPreview {
        let goal = session.goal
        return TutorGoalPreview(
            title: "\(goal.sceneTitle), it is.",
            subtitle: "Tap the card to pick again.",
            messages: [
                .tutorJapanese(goal.reaction),
                .tutorText("By the end of it, you'll be saying things like:"),
            ],
            phrases: goal.phrases
        )
    }

    private static let heroHeight: CGFloat = 88

    private var cards: [TutorGoalCard] = []
    private var isLocked = false

    override func buildStage() {
        setupOnboarding(title: choiceHeader.title, subtitle: choiceHeader.subtitle)
        isLocked = false

        cards = choices.enumerated().map { index, choice in
            let card = TutorGoalCard(emoji: choice.emoji, title: choice.title)
            card.tag = index
            card.addTarget(self, action: #selector(cardTapped(_:)), for: .touchUpInside)
            card.heightAnchor.constraint(equalToConstant: 96).isActive = true
            card.alpha = 0
            return card
        }

        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false
        for start in stride(from: 0, to: cards.count, by: 2) {
            let row = UIStackView(arrangedSubviews: Array(cards[start..<min(start + 2, cards.count)]))
            row.axis = .horizontal
            row.spacing = 12
            row.distribution = .fillEqually
            grid.addArrangedSubview(row)
        }
        stage.addSubview(grid)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: stage.topAnchor, constant: 12),
            grid.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -24),
        ])
    }

    override func play() {
        slideIn(cards, stagger: 0.05, initialDelay: 0.15)
    }

    @objc private func cardTapped(_ card: TutorGoalCard) {
        guard !isLocked else { return }
        isLocked = true
        choose(at: card.tag)
        card.isChosen = true
        playSelectionHaptic()
        explodeEmoji(from: card)
        advanceProgressBeat(to: 1)
        timeline.after(0.3) { [weak self] in
            self?.focus(on: card)
        }
    }

    @objc private func heroTapped() {
        playSelectionHaptic()
        restart()
    }

    /// Lifts the chosen card out of the grid and settles it at the top as the scene's title card.
    private func focus(on card: TutorGoalCard) {
        stage.layoutIfNeeded()
        let choice = choices[card.tag]
        let hero = TutorGoalCard(emoji: choice.emoji, title: choice.title)
        hero.isChosen = true
        hero.translatesAutoresizingMaskIntoConstraints = true
        hero.frame = card.convert(card.bounds, to: stage)
        hero.accessibilityHint = "Pick a different goal"
        hero.addTarget(self, action: #selector(heroTapped), for: .touchUpInside)
        stage.addSubview(hero)
        card.alpha = 0

        UIView.animate(withDuration: AnimationDefaults.fastDuration) {
            for other in self.cards where other !== card {
                other.alpha = 0
                other.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            }
        }

        let target = CGRect(x: 24, y: 12, width: stage.bounds.width - 48, height: Self.heroHeight)
        let settle = UIViewPropertyAnimator(
            duration: 0.6,
            controlPoint1: AnimationDefaults.overshootControlPoint1,
            controlPoint2: AnimationDefaults.overshootControlPoint2
        ) {
            hero.frame = target
            hero.layoutIfNeeded()
        }
        settle.startAnimation()

        let preview = preview
        transitionHeader(title: preview.title, subtitle: preview.subtitle)
        showPreview(preview, top: target.maxY + 8)
    }

    private func showPreview(_ preview: TutorGoalPreview, top: CGFloat) {
        let chat = makeChat()
        stage.addSubview(chat)
        NSLayoutConstraint.activate([
            chat.topAnchor.constraint(equalTo: stage.topAnchor, constant: top),
            chat.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            chat.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            chat.bottomAnchor.constraint(equalTo: stage.bottomAnchor),
        ])

        timeline.after(0.35) { [weak self] in
            chat.play(preview.messages) {
                // Without a guide line above them, phrases sit flush instead of under an avatar.
                let indent = preview.messages.isEmpty ? 0 : TutorAvatarView.size + 8
                self?.appendPhrases(
                    preview.phrases,
                    to: chat,
                    indent: indent,
                    hidesEnglish: preview.hidesEnglishUntilSwipe,
                    breakdown: preview.breakdown
                )
            }
        }
    }

    private func appendPhrases(
        _ phrases: [TutorLine],
        to chat: TutorChatView,
        indent: CGFloat,
        hidesEnglish: Bool,
        breakdown: @escaping (TutorLine) -> SentenceScrubScript?
    ) {
        for (offset, phrase) in phrases.enumerated() {
            timeline.after(TimeInterval(offset) * 0.18) { [weak self] in
                let row = UIView()
                let column: UIView
                if hidesEnglish {
                    let line = TutorSwipeLine(line: phrase, side: nil)
                    line.hostScrollView = chat.scrollContainer
                    line.isRevealEnabled = true
                    if let script = breakdown(phrase) {
                        line.onBreakdown = { [weak self] in self?.presentBreakdown(of: phrase, script: script) }
                    }
                    if offset == 0 {
                        self?.nudge(line, toward: .revealEnglish, after: 0.4 + TimeInterval(phrases.count) * 0.18)
                    }
                    column = line
                } else {
                    column = TutorChatView.japaneseColumn(phrase, side: nil)
                }
                row.addSubview(column)
                NSLayoutConstraint.activate([
                    column.topAnchor.constraint(equalTo: row.topAnchor),
                    column.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                    column.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: indent),
                    column.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),
                ])
                chat.appendCustom(row)
                HapticsHelper.superLightHaptic()
            }
        }
        timeline.after(TimeInterval(phrases.count) * 0.18 + 0.3) { [weak self] in
            self?.revealCTA("Next")
        }
    }
}

final class TutorGoalCard: UIControl {

    var isChosen = false {
        didSet { applyChrome() }
    }

    init(emoji emojiText: String, title titleText: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        accessibilityLabel = titleText
        accessibilityTraits = .button

        let emoji = UILabel()
        emoji.text = emojiText
        emoji.font = .systemFont(ofSize: 30)

        let title = UILabel()
        title.text = titleText
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .label
        title.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [emoji, title])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])
        applyChrome()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (card: TutorGoalCard, _) in
            card.applyChrome()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            }
        }
    }

    private func applyChrome() {
        layer.borderWidth = isChosen ? ExperimentCardStroke.emphasisWidth : ExperimentCardStroke.normalWidth
        layer.borderColor = (isChosen ? ExperimentPalette.highlightBorder : ExperimentPalette.cardBorder).cgColor
        backgroundColor = isChosen ? ExperimentPalette.highlightFill : ExperimentPalette.cardSurface
    }
}

// MARK: - Level

/// One line as the level step shows it: the bubble, an optional reading under it, and the English.
struct TutorLevelSample {
    let japanese: String
    let reading: String?
    let english: String
}

class TutorLevelStepViewController: TutorStepViewController {

    // MARK: Content hooks

    var levelHeader: (title: String, subtitle: String) {
        ("How much Japanese do you know?", "Slide it. Hana changes how every line is shown.")
    }

    var levelCaption: String {
        "\(session.goal.emoji)  \(session.goal.sceneTitle)"
    }

    /// The line shown at `level`. The tutor flow morphs one line's script; subclasses can curate a different line per level.
    func levelSample(for level: TutorLevel) -> TutorLevelSample {
        let sample = session.goal.sample
        return TutorLevelSample(japanese: sample.text(for: level), reading: nil, english: sample.english)
    }

    func levelHint(for level: TutorLevel) -> String {
        level.hint
    }

    private static let sampleFont = UIFont.systemFont(ofSize: 24, weight: .medium)

    private var level: TutorLevel = .brandNew
    private var userMovedSlider = false

    private let sampleBlock = UIView()
    private let sceneLabel = UILabel()
    /// One prebuilt line per level, top to bottom. The slider scrolls it; nothing is rebuilt.
    private let sampleHost = OnboardingLineCarousel()
    private let levelTitleLabel = UILabel()
    private let hintLabel = UILabel()
    private let lowLabel = UILabel()
    private let highLabel = UILabel()
    /// Plain wrapper so the fade animates a normal view, not the glass slider's alpha.
    private let sliderGroup = UIView()
    private var slider: OnboardingDetentSliderView?
    /// Where the floating Hana sits, under the slider, when the flow has one.
    private let hanaSpot = UIView()

    override func buildStage() {
        setupOnboarding(title: levelHeader.title, subtitle: levelHeader.subtitle)
        level = session.level
        userMovedSlider = false

        sceneLabel.text = levelCaption
        sceneLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        sceneLabel.textColor = .secondaryLabel
        sceneLabel.textAlignment = .center

        levelTitleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        levelTitleLabel.textColor = .label
        levelTitleLabel.textAlignment = .center

        hintLabel.font = .preferredFont(forTextStyle: .subheadline)
        hintLabel.textColor = .secondaryLabel
        hintLabel.numberOfLines = 1
        hintLabel.adjustsFontSizeToFitWidth = true
        hintLabel.minimumScaleFactor = 0.8
        hintLabel.textAlignment = .center

        for (label, text) in [(lowLabel, "New"), (highLabel, "Chatting")] {
            label.text = text
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = .tertiaryLabel
        }

        let slider = OnboardingDetentSliderView(detentCount: TutorLevel.allCases.count, selectedIndex: level.rawValue)
        slider.onIndexChanged = { [weak self] index in
            self?.userMovedSlider = true
            self?.select(TutorLevel(rawValue: index) ?? .brandNew)
            self?.explodeForDetent(index)
        }
        slider.onKnobMoved = { [weak self] in self?.hanaWatchKnob() }
        self.slider = slider

        sliderGroup.subviews.forEach { $0.removeFromSuperview() }
        for subview in [slider, lowLabel, highLabel] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            sliderGroup.addSubview(subview)
        }

        sampleBlock.subviews.forEach { $0.removeFromSuperview() }
        sampleHost.layoutRoot = stage
        sampleHost.onSelect = { [weak self] index in self?.moveFromCarousel(to: index) }
        sampleHost.setLines(TutorLevel.allCases.map { makeSampleView(levelSample(for: $0), for: $0) }, selectedIndex: level.rawValue)
        for subview in [sceneLabel, sampleHost] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            sampleBlock.addSubview(subview)
        }

        let fadedIn: [UIView] = [sampleBlock, levelTitleLabel, hintLabel, sliderGroup]
        for subview in fadedIn {
            subview.translatesAutoresizingMaskIntoConstraints = false
            subview.alpha = 0
            stage.addSubview(subview)
        }

        // Level label and slider sit around the middle; the sample floats centered in the room above them.
        let sampleRoom = UILayoutGuide()
        stage.addLayoutGuide(sampleRoom)

        NSLayoutConstraint.activate([
            sliderGroup.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: 24),
            sliderGroup.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -24),
            sliderGroup.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 24),
            sliderGroup.bottomAnchor.constraint(lessThanOrEqualTo: stage.bottomAnchor, constant: -8),
            slider.topAnchor.constraint(equalTo: sliderGroup.topAnchor),
            slider.leadingAnchor.constraint(equalTo: sliderGroup.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: sliderGroup.trailingAnchor),
            lowLabel.bottomAnchor.constraint(equalTo: sliderGroup.bottomAnchor),
            highLabel.bottomAnchor.constraint(equalTo: sliderGroup.bottomAnchor),
            lowLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 6),
            lowLabel.leadingAnchor.constraint(equalTo: slider.leadingAnchor, constant: 12),
            highLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 6),
            highLabel.trailingAnchor.constraint(equalTo: slider.trailingAnchor, constant: -12),

            hintLabel.topAnchor.constraint(equalTo: levelTitleLabel.bottomAnchor, constant: 6),
            hintLabel.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: 32),
            hintLabel.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -32),

            levelTitleLabel.topAnchor.constraint(equalTo: stage.centerYAnchor, constant: -8),
            levelTitleLabel.centerXAnchor.constraint(equalTo: stage.centerXAnchor),

            sampleRoom.topAnchor.constraint(equalTo: stage.topAnchor),
            sampleRoom.bottomAnchor.constraint(equalTo: levelTitleLabel.topAnchor, constant: -16),

            sampleBlock.centerYAnchor.constraint(equalTo: sampleRoom.centerYAnchor),
            sampleBlock.topAnchor.constraint(greaterThanOrEqualTo: sampleRoom.topAnchor),
            sampleBlock.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: 24),
            sampleBlock.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -24),

            sceneLabel.topAnchor.constraint(equalTo: sampleBlock.topAnchor),
            sceneLabel.leadingAnchor.constraint(equalTo: sampleBlock.leadingAnchor),
            sceneLabel.trailingAnchor.constraint(equalTo: sampleBlock.trailingAnchor),

            sampleHost.topAnchor.constraint(equalTo: sceneLabel.bottomAnchor, constant: 14),
            sampleHost.leadingAnchor.constraint(equalTo: sampleBlock.leadingAnchor),
            sampleHost.trailingAnchor.constraint(equalTo: sampleBlock.trailingAnchor),
            sampleHost.bottomAnchor.constraint(equalTo: sampleBlock.bottomAnchor),
        ])

        if hanaStage != nil {
            installHanaSpot()
        }

        applyLevelLabels(animated: false)
    }

    /// Centered in the room between the slider and the bottom of the stage.
    private func installHanaSpot() {
        let room = UILayoutGuide()
        stage.addLayoutGuide(room)
        hanaSpot.translatesAutoresizingMaskIntoConstraints = false
        hanaSpot.isUserInteractionEnabled = false
        stage.addSubview(hanaSpot)
        let preferredSize = hanaSpot.heightAnchor.constraint(equalToConstant: 104)
        preferredSize.priority = .defaultHigh
        NSLayoutConstraint.activate([
            room.topAnchor.constraint(equalTo: sliderGroup.bottomAnchor),
            room.bottomAnchor.constraint(equalTo: stage.bottomAnchor),
            hanaSpot.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            hanaSpot.centerYAnchor.constraint(equalTo: room.centerYAnchor),
            hanaSpot.heightAnchor.constraint(lessThanOrEqualTo: room.heightAnchor),
            preferredSize,
            hanaSpot.widthAnchor.constraint(equalTo: hanaSpot.heightAnchor),
        ])
    }

    override func hanaStageDidAppear(firstTime: Bool) {
        guard let hanaStage else { return }
        hanaStage.dock(at: hanaSpot, expression: MascotExpression())
        hanaWatchKnob()
    }

    /// Hana's eyes follow the slider knob, including the demo nudges.
    private func hanaWatchKnob() {
        guard let hanaStage, let point = slider?.knobCenterInWindow() else { return }
        hanaStage.look(atWindowPoint: point)
    }

    override func play() {
        slideIn([sampleBlock], initialDelay: 0.15)
        slideIn([levelTitleLabel, hintLabel], stagger: 0.07, initialDelay: 0.3)
        timeline.after(0.4) { [weak self] in
            guard let self else { return }
            UIView.animate(withDuration: AnimationDefaults.standardDuration) {
                self.sliderGroup.alpha = 1
            }
            self.revealCTA("Next")
        }
        guard level == .brandNew, !Self.reducesMotion else { return }
        timeline.after(1.6) { [weak self] in self?.nudge(to: .someKanji) }
        timeline.after(3.0) { [weak self] in self?.nudge(to: .brandNew) }
    }

    /// Bigger bursts the higher you go: tiny, tiny, small, medium (as in the slider onboarding experiment).
    private func explodeForDetent(_ index: Int) {
        guard let slider, let point = slider.knobCenterInWindow() else { return }
        let presets: [ExplosionPreset] = [.tiny, .tiny, .small, .medium]
        OnboardingCelebration.burst(presets[min(max(index, 0), presets.count - 1)], from: slider, at: slider.convert(point, from: nil))
    }

    /// Demonstrates the slider once so the morph is obvious before the user touches it.
    private func nudge(to target: TutorLevel) {
        guard !userMovedSlider else { return }
        slider?.setSelectedIndex(target.rawValue, animated: true)
        select(target)
    }

    private func select(_ newLevel: TutorLevel) {
        guard newLevel != level else { return }
        level = newLevel
        session.level = newLevel
        sampleHost.select(newLevel.rawValue, animated: true)
        applyLevelLabels(animated: true)
    }

    private func makeSampleView(_ sample: TutorLevelSample, for level: TutorLevel) -> UIView {
        let bubble = OnboardingChrome.makeDialogueBubble(
            text: sample.japanese,
            font: Self.sampleFont,
            side: .leading,
            showsTail: true
        )
        let line = TutorLine(sample.japanese, sample.english)
        let swipeTarget = breakdownAction(for: line).map { TutorChatView.dissectible(bubble, onBreakdown: $0) }

        let column = UIStackView(arrangedSubviews: [swipeTarget ?? bubble])
        column.axis = .vertical
        column.alignment = .center
        column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false

        if let reading = sample.reading {
            let label = UILabel()
            label.text = reading
            label.font = .systemFont(ofSize: 15, weight: .semibold)
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            label.numberOfLines = 0
            column.addArrangedSubview(label)
            column.setCustomSpacing(4, after: bubble)
        }

        let english = UILabel()
        english.font = .preferredFont(forTextStyle: .subheadline)
        english.numberOfLines = 0
        english.textAlignment = .center
        english.text = level.showsEnglish ? sample.english : "English hides until you tap the line."
        english.textColor = level.showsEnglish ? .secondaryLabel : .tertiaryLabel
        column.addArrangedSubview(english)
        return column
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sampleHost.placeIfNeeded()
    }

    private func moveFromCarousel(to index: Int) {
        guard let target = TutorLevel(rawValue: index), target != level else { return }
        userMovedSlider = true
        playSelectionHaptic()
        slider?.setSelectedIndex(index, animated: true)
        select(target)
    }

    private func applyLevelLabels(animated: Bool) {
        let update = {
            self.levelTitleLabel.text = self.level.title
            self.hintLabel.text = self.levelHint(for: self.level)
        }
        guard animated else {
            update()
            return
        }
        UIView.transition(
            with: levelTitleLabel,
            duration: 0.25,
            options: [.transitionCrossDissolve, .allowUserInteraction],
            animations: update
        )
        UIView.transition(with: hintLabel, duration: 0.25, options: [.transitionCrossDissolve, .allowUserInteraction], animations: nil)
    }
}
