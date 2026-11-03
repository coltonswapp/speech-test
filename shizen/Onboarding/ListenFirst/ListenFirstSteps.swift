//
//  ListenFirstSteps.swift
//  shizen
//
//  Screens unique to listening-first v2: the gap (a slider from textbook to real life),
//  the shared Mika/Kaito listen, the unsquash ladder, plus style and path
//  steps that reuse the Natural flow with v2 content.
//

import AVFoundation
import NNKit
import UIKit

/// Base for v2-only steps; keeps a typed handle on the persisted session.
class ListenFirstStepViewController: TutorStepViewController {

    let listen: ListenFirstSession

    init(session: ListenFirstSession) {
        listen = session
        super.init(session: session)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// A pink badge that pops above `anchor`, bursts, and floats away.
    func popBadge(_ text: String, above anchor: UIView) {
        let badge = EncouragementBadgeView(text: text, fillColor: TutorPalette.sakura, textColor: .white)
        view.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.centerXAnchor.constraint(equalTo: anchor.centerXAnchor),
            badge.bottomAnchor.constraint(equalTo: anchor.topAnchor, constant: -8),
        ])
        view.layoutIfNeeded()
        badge.prepareForCascadeEntry()
        let pop = UIViewPropertyAnimator(
            duration: 0.5,
            controlPoint1: AnimationDefaults.overshootControlPoint1,
            controlPoint2: AnimationDefaults.overshootControlPoint2
        ) {
            badge.alpha = 1
            badge.transform = .identity
        }
        pop.addCompletion { _ in badge.playEntryShimmer() }
        pop.startAnimation()
        timeline.after(1.1) {
            UIView.animate(withDuration: 0.25, animations: {
                badge.alpha = 0
                badge.transform = CGAffineTransform(translationX: 0, y: -16)
            }, completion: { _ in
                badge.removeFromSuperview()
            })
        }
    }
}

// MARK: - 2 · Textbooks vs. real life

/// One line at three detents: textbook, casual, real life. The slider walks the line down
/// the carousel and each settle plays that version, so it audibly shrinks under your thumb.
/// A demo walks it once and hands it back at "Textbook"; the CTA waits for the user to reach
/// "Real life" themselves (or a few seconds, so nobody gets stuck). The arrows either side of
/// the dots switch between the three lines (a sideways swipe on a bubble opens its breakdown);
/// tapping the line replays it.
final class ListenFirstGapStepViewController: ListenFirstStepViewController {

    override var progressBeatCount: Int { 2 }

    private static let lineFont = UIFont.systemFont(ofSize: 26, weight: .semibold)
    private static let realLife = ListenFirstContent.gapStages.count - 1

    private let voice = NaturalVoicePlayer()
    private let lineBlock = UIView()
    private let carousel = OnboardingLineCarousel()
    private let englishLabel = UILabel()
    private let dots = UIPageControl()
    private let previousButton = GlassIconButton(symbolName: "chevron.left", pointSize: 14, tintColor: .label, accessibilityLabel: "Previous example")
    private let nextButton = GlassIconButton(symbolName: "chevron.right", pointSize: 14, tintColor: .label, accessibilityLabel: "Next example")
    private let lineNav = UIStackView()
    private let stageTitleLabel = UILabel()
    private let hintLabel = UILabel()
    private let lowLabel = UILabel()
    private let highLabel = UILabel()
    /// Plain wrapper so the fade animates a normal view, not the glass slider's alpha.
    private let sliderGroup = UIView()
    private var slider: OnboardingDetentSliderView?
    /// Where the floating Hana sits, under the slider.
    private let hanaSpot = UIView()

    private var lineIndex = 0
    private var stageIndex = 0
    private var isDemoing = false
    private var hasRevealedCTA = false
    /// Bumps whenever playback is abandoned, so a late audio callback does nothing.
    private var playGeneration = 0

    override func buildStage() {
        setupOnboarding(title: "Textbooks vs. real life", subtitle: "Same meaning. Slide it and hear what goes.")
        lineIndex = 0
        stageIndex = 0
        isDemoing = false
        hasRevealedCTA = false

        englishLabel.font = .preferredFont(forTextStyle: .subheadline)
        englishLabel.textColor = .secondaryLabel
        englishLabel.textAlignment = .center

        dots.numberOfPages = ListenFirstContent.gapForms.count
        dots.pageIndicatorTintColor = .tertiaryLabel
        dots.currentPageIndicatorTintColor = .label
        dots.currentPage = 0
        dots.isUserInteractionEnabled = false

        if lineNav.arrangedSubviews.isEmpty {
            for button in [previousButton, nextButton] {
                NSLayoutConstraint.activate([
                    button.widthAnchor.constraint(equalToConstant: 36),
                    button.heightAnchor.constraint(equalToConstant: 36),
                ])
            }
            previousButton.addTarget(self, action: #selector(previousTapped), for: .touchUpInside)
            nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
            [previousButton, dots, nextButton].forEach { lineNav.addArrangedSubview($0) }
            lineNav.axis = .horizontal
            lineNav.alignment = .center
            lineNav.spacing = 4
        }

        stageTitleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        stageTitleLabel.textColor = .label
        stageTitleLabel.textAlignment = .center

        hintLabel.font = .preferredFont(forTextStyle: .subheadline)
        hintLabel.textColor = .secondaryLabel
        hintLabel.numberOfLines = 1
        hintLabel.adjustsFontSizeToFitWidth = true
        hintLabel.minimumScaleFactor = 0.8
        hintLabel.textAlignment = .center

        for (label, text) in [(lowLabel, ListenFirstContent.gapStages[0].title), (highLabel, ListenFirstContent.gapStages[Self.realLife].title)] {
            label.text = text
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = .tertiaryLabel
        }

        let slider = OnboardingDetentSliderView(detentCount: ListenFirstContent.gapStages.count)
        // The line follows the knob live; the audio waits for it to settle.
        slider.onIndexChanged = { [weak self] index in
            self?.userTookOver()
            self?.select(stage: index)
        }
        slider.onRelease = { [weak self] index in
            self?.userTookOver()
            self?.select(stage: index)
            self?.playCurrent()
        }
        slider.onKnobMoved = { [weak self] in self?.hanaWatchKnob() }
        self.slider = slider

        sliderGroup.subviews.forEach { $0.removeFromSuperview() }
        for subview in [slider, lowLabel, highLabel] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            sliderGroup.addSubview(subview)
        }

        carousel.layoutRoot = stage
        carousel.onSelect = { [weak self] index in
            guard let self else { return }
            self.userTookOver()
            self.playSelectionHaptic()
            self.slider?.setSelectedIndex(index, animated: true)
            self.select(stage: index)
            self.playCurrent()
        }
        carousel.onTapFocused = { [weak self] in
            HapticsHelper.lightHaptic()
            self?.playCurrent()
        }
        loadLine(0)

        lineBlock.subviews.forEach { $0.removeFromSuperview() }
        for subview in [carousel, englishLabel, lineNav] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            lineBlock.addSubview(subview)
        }

        for subview in [lineBlock, stageTitleLabel, hintLabel, sliderGroup] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            subview.alpha = 0
            stage.addSubview(subview)
        }

        // Stage label and slider sit around the middle; the line floats centered in the room above them.
        let lineRoom = UILayoutGuide()
        stage.addLayoutGuide(lineRoom)

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

            hintLabel.topAnchor.constraint(equalTo: stageTitleLabel.bottomAnchor, constant: 6),
            hintLabel.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: 32),
            hintLabel.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -32),

            stageTitleLabel.topAnchor.constraint(equalTo: stage.centerYAnchor, constant: -8),
            stageTitleLabel.centerXAnchor.constraint(equalTo: stage.centerXAnchor),

            lineRoom.topAnchor.constraint(equalTo: stage.topAnchor),
            lineRoom.bottomAnchor.constraint(equalTo: stageTitleLabel.topAnchor, constant: -16),

            lineBlock.centerYAnchor.constraint(equalTo: lineRoom.centerYAnchor),
            lineBlock.topAnchor.constraint(greaterThanOrEqualTo: lineRoom.topAnchor),
            lineBlock.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: 24),
            lineBlock.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -24),

            carousel.topAnchor.constraint(equalTo: lineBlock.topAnchor),
            carousel.leadingAnchor.constraint(equalTo: lineBlock.leadingAnchor),
            carousel.trailingAnchor.constraint(equalTo: lineBlock.trailingAnchor),

            englishLabel.topAnchor.constraint(equalTo: carousel.bottomAnchor, constant: 8),
            englishLabel.leadingAnchor.constraint(equalTo: lineBlock.leadingAnchor),
            englishLabel.trailingAnchor.constraint(equalTo: lineBlock.trailingAnchor),

            lineNav.topAnchor.constraint(equalTo: englishLabel.bottomAnchor, constant: 12),
            lineNav.centerXAnchor.constraint(equalTo: lineBlock.centerXAnchor),
            lineNav.bottomAnchor.constraint(equalTo: lineBlock.bottomAnchor),
        ])

        if hanaStage != nil {
            installHanaSpot()
        }
        applyStageLabels(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        carousel.placeIfNeeded()
    }

    override func play() {
        slideIn([lineBlock], initialDelay: 0.15)
        slideIn([stageTitleLabel, hintLabel], stagger: 0.07, initialDelay: 0.3)
        timeline.after(0.4) { [weak self] in
            guard let self else { return }
            UIView.animate(withDuration: AnimationDefaults.standardDuration) {
                self.sliderGroup.alpha = 1
            }
        }
        timeline.after(0.9) { [weak self] in self?.playDemo() }
    }

    override func resetStage() {
        stopPlayback()
        super.resetStage()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPlayback()
    }

    // MARK: Hana

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

    /// Hana's eyes follow the slider knob, including the demo.
    private func hanaWatchKnob() {
        guard let hanaStage, let point = slider?.knobCenterInWindow() else { return }
        hanaStage.look(atWindowPoint: point)
    }

    // MARK: Demo

    /// Plays the textbook line, then slides through casual to real life, waiting on each
    /// clip, and hands the knob back at "Textbook". Any touch ends it.
    private func playDemo() {
        isDemoing = true
        playCurrent { [weak self] in
            self?.demoStep(to: 1)
        }
    }

    private func demoStep(to index: Int) {
        guard isDemoing else { return }
        guard ListenFirstContent.gapStages.indices.contains(index) else {
            finishDemo()
            return
        }
        timeline.after(0.35) { [weak self] in
            guard let self, self.isDemoing else { return }
            self.slider?.setSelectedIndex(index, animated: true)
            self.select(stage: index)
            self.playCurrent { [weak self] in
                self?.demoStep(to: index + 1)
            }
        }
    }

    private func finishDemo() {
        timeline.after(0.9) { [weak self] in
            guard let self, self.isDemoing else { return }
            self.isDemoing = false
            self.slider?.setSelectedIndex(0, animated: true)
            self.select(stage: 0)
            self.hintLabel.text = "Your turn. Slide it."
            self.timeline.after(5) { [weak self] in self?.revealGapCTA() }
        }
    }

    /// The user touched something: the demo stops where it is.
    private func userTookOver() {
        guard isDemoing else { return }
        isDemoing = false
        stopPlayback()
        timeline.after(5) { [weak self] in self?.revealGapCTA() }
    }

    private func revealGapCTA() {
        guard !hasRevealedCTA else { return }
        hasRevealedCTA = true
        advanceProgressBeat(to: 1)
        revealCTA("Now try it")
    }

    // MARK: Selection

    private func select(stage index: Int) {
        guard index != stageIndex, ListenFirstContent.gapStages.indices.contains(index) else { return }
        stageIndex = index
        carousel.select(index, animated: true)
        applyStageLabels(animated: true)
        explodeForDetent(index)
        if index == Self.realLife, !isDemoing {
            if !hasRevealedCTA, lineIndex + 1 < ListenFirstContent.gapForms.count {
                pulseNextButton()
            }
            revealGapCTA()
        }
    }

    private func explodeForDetent(_ index: Int) {
        guard index > 0, let slider, let point = slider.knobCenterInWindow() else { return }
        OnboardingCelebration.burst(index == Self.realLife ? .small : .tiny, from: slider, at: slider.convert(point, from: nil))
    }

    private func applyStageLabels(animated: Bool) {
        let stage = ListenFirstContent.gapStages[stageIndex]
        let update = {
            self.stageTitleLabel.text = stage.title
            self.hintLabel.text = stage.hint
        }
        guard animated else {
            update()
            return
        }
        UIView.transition(with: stageTitleLabel, duration: 0.25, options: [.transitionCrossDissolve, .allowUserInteraction], animations: update)
        UIView.transition(with: hintLabel, duration: 0.25, options: [.transitionCrossDissolve, .allowUserInteraction], animations: nil)
    }

    // MARK: Lines

    private func loadLine(_ index: Int) {
        lineIndex = index
        dots.currentPage = index
        previousButton.isEnabled = index > 0
        nextButton.isEnabled = index + 1 < ListenFirstContent.gapForms.count
        previousButton.alpha = previousButton.isEnabled ? 1 : 0.35
        nextButton.alpha = nextButton.isEnabled ? 1 : 0.35
        englishLabel.text = NaturalContrast.all[index].english
        let views = ListenFirstContent.gapForms[index].map { makeLineView($0.text, english: NaturalContrast.all[index].english) }
        carousel.setLines(views, selectedIndex: stageIndex)
        view.setNeedsLayout()
    }

    private func makeLineView(_ text: String, english: String) -> UIView {
        let bubble = OnboardingChrome.makeDialogueBubble(text: text, font: Self.lineFont, side: .trailing, showsTail: true)
        let breakdown = breakdownAction(for: TutorLine(text, english)).map { action -> () -> Void in
            { [weak self] in
                self?.userTookOver()
                self?.stopPlayback()
                action()
            }
        }
        let target = breakdown.map { TutorChatView.dissectible(bubble, onBreakdown: $0) }
        let column = UIStackView(arrangedSubviews: [target ?? bubble])
        column.axis = .vertical
        column.alignment = .center
        return column
    }

    /// Fades the line out, swaps in `index` at the same stage, and plays it.
    private func showLine(_ index: Int) {
        guard index != lineIndex, ListenFirstContent.gapForms.indices.contains(index) else { return }
        userTookOver()
        stopPlayback()
        HapticsHelper.superLightHaptic()
        let direction: CGFloat = index > lineIndex ? 1 : -1
        let distance = Self.slideDistance(40)
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn]) {
            self.carousel.alpha = 0
            self.englishLabel.alpha = 0
            self.carousel.transform = CGAffineTransform(translationX: -direction * distance, y: 0)
        } completion: { _ in
            self.loadLine(index)
            self.view.layoutIfNeeded()
            self.carousel.transform = CGAffineTransform(translationX: direction * distance, y: 0)
            UIView.animate(springDuration: 0.45, bounce: 0.2) {
                self.carousel.alpha = 1
                self.englishLabel.alpha = 1
                self.carousel.transform = .identity
            }
            self.playCurrent()
        }
    }

    @objc private func previousTapped() {
        showLine(lineIndex - 1)
    }

    @objc private func nextTapped() {
        showLine(lineIndex + 1)
    }

    /// The first time someone lands on "Real life", point them at the other examples.
    private func pulseNextButton() {
        guard !Self.reducesMotion else { return }
        nextButton.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
        UIView.animate(springDuration: 0.5, bounce: 0.5, initialSpringVelocity: 0, delay: 0.3, options: [.allowUserInteraction]) {
            self.nextButton.transform = .identity
        }
    }

    // MARK: Audio

    private func playCurrent(_ completion: (() -> Void)? = nil) {
        playGeneration += 1
        let generation = playGeneration
        voice.stop()
        voice.play(ListenFirstContent.gapForms[lineIndex][stageIndex]) { [weak self] in
            guard let self, self.playGeneration == generation else { return }
            completion?()
        }
    }

    private func stopPlayback() {
        playGeneration += 1
        voice.stop()
    }
}

// MARK: - 3 · Just listen

final class ListenFirstListenStepViewController: ListenFirstStepViewController {

    override var progressBeatCount: Int { 3 }

    private let voice = NaturalVoicePlayer()
    private let meters = NaturalMeterDriver()
    private let scrollView = UIScrollView()
    private let content = UIStackView()
    private var lines: [NaturalDialogueLineView] = []
    private let playButton = GlassIconButton(
        symbolName: "play.fill",
        pointSize: 22,
        glyphDimension: 26,
        tintColor: .systemYellow,
        accessibilityLabel: "Play conversation"
    )
    /// Hana's lines: the brief, then the gist question, then her reaction to the answer.
    private var hintRow = UIView()
    private var questionRow = UIView()
    private var options: [NaturalGistOption] = []
    private var activeLine: Int?
    private var isPlaying = false
    private var hasHeardOnce = false
    private var hasAnswered = false

    override func buildStage() {
        setupOnboarding(title: "Just listen. No transcript.", subtitle: ListenFirstContent.sceneTitle)
        isPlaying = false
        hasHeardOnce = false
        hasAnswered = false
        activeLine = nil

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        stage.addSubview(scrollView)

        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        content.axis = .vertical
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        lines = ListenFirstContent.conversation.map { line in
            let view = NaturalDialogueLineView(
                speaker: ListenFirstContent.speakers[line.speaker],
                side: line.speaker == 0 ? .leading : .trailing,
                japanese: listen.defaultText(line),
                english: line.english
            )
            view.alpha = 0
            return view
        }
        lines.forEach { content.addArrangedSubview($0) }

        playButton.setSymbol("play.fill")
        playButton.removeTarget(nil, action: nil, for: .allEvents)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.alpha = 0
        let playRow = UIView()
        playRow.addSubview(playButton)
        NSLayoutConstraint.activate([
            playButton.widthAnchor.constraint(equalToConstant: 56),
            playButton.heightAnchor.constraint(equalToConstant: 56),
            playButton.centerXAnchor.constraint(equalTo: playRow.centerXAnchor),
            playButton.topAnchor.constraint(equalTo: playRow.topAnchor),
            playButton.bottomAnchor.constraint(equalTo: playRow.bottomAnchor),
        ])
        content.addArrangedSubview(playRow)
        if let last = lines.last {
            content.setCustomSpacing(24, after: last)
        }

        hintRow = hanaRow("Listen for the three lines you just met. Just get the gist.")
        hintRow.alpha = 0
        content.addArrangedSubview(hintRow)
        // Room under the play button, whether the hint or the gist question sits below it.
        content.setCustomSpacing(28, after: playRow)
        content.setCustomSpacing(24, after: hintRow)

        questionRow = hanaRow(ListenFirstContent.gist.question)
        questionRow.isHidden = true
        content.addArrangedSubview(questionRow)
        content.setCustomSpacing(16, after: questionRow)

        options = ListenFirstContent.gist.options.enumerated().map { index, text in
            let option = NaturalGistOption(text: text)
            option.tag = index
            option.isHidden = true
            option.addTarget(self, action: #selector(optionTapped(_:)), for: .touchUpInside)
            return option
        }
        options.forEach { content.addArrangedSubview($0) }

        let frame = scrollView.frameLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: stage.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: stage.bottomAnchor),

            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -12),
            content.leadingAnchor.constraint(equalTo: frame.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: frame.trailingAnchor, constant: -20),
        ])
        scrollUnderHeader(scrollView, scrollView: scrollView)
    }

    override func play() {
        slideIn(lines, stagger: 0.06, initialDelay: 0.15)
        slideIn([playButton, hintRow], stagger: 0.08, initialDelay: 0.5)
    }

    override func resetStage() {
        stopPlayback()
        super.resetStage()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPlayback()
    }

    @objc private func playTapped() {
        HapticsHelper.lightHaptic()
        guard !isPlaying else {
            stopPlayback()
            return
        }
        isPlaying = true
        playButton.setSymbol("stop.fill")
        // Reduce Motion: meters stay still; focus alone marks the speaker.
        if !Self.reducesMotion {
            meters.start { [weak self] in
                guard let self, let index = self.activeLine else { return }
                self.lines[index].push(level: self.voice.level)
            }
        }
        playLine(0)
    }

    private func playLine(_ index: Int) {
        guard isPlaying, ListenFirstContent.conversation.indices.contains(index) else {
            finishPlayback()
            return
        }
        focus(on: index)
        voice.play(ListenFirstContent.lineClip(at: index)) { [weak self] in
            self?.lines[index].rest()
            self?.timeline.after(0.15) { [weak self] in
                self?.playLine(index + 1)
            }
        }
    }

    private func focus(on index: Int?) {
        activeLine = index
        for (offset, line) in lines.enumerated() {
            line.setFocused(index == nil || offset == index, animated: true)
        }
    }

    private func stopPlayback() {
        isPlaying = false
        voice.stop()
        meters.stop()
        lines.forEach { $0.rest() }
        focus(on: nil)
        playButton.setSymbol(hasHeardOnce ? "arrow.counterclockwise" : "play.fill")
    }

    private func finishPlayback() {
        let isFirstListen = !hasHeardOnce
        hasHeardOnce = true
        stopPlayback()
        guard isFirstListen else { return }
        advanceProgressBeat(to: 1)
        // Small-phone rule: the question replaces the hint rather than stacking under it.
        hintRow.isHidden = true
        let revealed: [UIView] = [questionRow] + options
        revealed.forEach { $0.isHidden = false }
        slideIn(revealed, stagger: 0.07)
        scrollToBottom()
    }

    @objc private func optionTapped(_ option: NaturalGistOption) {
        guard !hasAnswered else { return }
        hasAnswered = true
        let gist = ListenFirstContent.gist
        let isRight = option.tag == gist.answer
        let result: String
        listen.caughtGist = isRight
        playSelectionHaptic()

        if isRight {
            option.mark = .right
            HapticsHelper.successHaptic()
            explodeEmoji(from: option)
            popBadge("聞き取れた！", above: option)
            result = "You caught it, without reading a single word."
        } else {
            option.mark = .wrong
            options[gist.answer].mark = .right
            HapticsHelper.lightHaptic()
            result = "Close! Missing it the first time is normal. That's why we replay."
        }
        options.filter { $0.mark == .idle }.forEach { other in
            UIView.animate(withDuration: AnimationDefaults.fastDuration) { other.alpha = 0.4 }
        }
        let resultRow = hanaRow(result)
        content.setCustomSpacing(20, after: options.last ?? resultRow)
        content.addArrangedSubview(resultRow)
        slideIn([resultRow])
        scrollToBottom()
        advanceProgressBeat(to: 2)
        timeline.after(0.8) { [weak self] in
            self?.revealCTA("Show me the words")
        }
    }

    private func scrollToBottom(animated: Bool = true) {
        scrollToBottom(of: scrollView, animated: animated)
    }

    /// One of Hana's lines in the chat style, with her beside it.
    private func hanaRow(_ text: String) -> UIView {
        TutorChatView.tutorRow(
            content: TutorChatView.textBubble(text, side: .leading),
            avatar: session.showsMascot ? .mascot : .emoji
        )
    }
}

// MARK: - 4 · Now take it apart
// The screen itself is in ListenFirstTakeApartStep.swift. The unsquash ladder views below
// (panel and callout strip) are no longer shown anywhere.

/// A spoken chunk that splits into tiles, then steps back toward its textbook form on each tap.
final class ListenFirstUnsquashPanel: UIView {

    var onTap: (() -> Void)?

    let noteLabel = UILabel()
    private(set) var formIndex = 0
    private let chunk: ListenFirstChunk
    private let splitStage = UIView()
    private let bubbleHost = UIView()
    private var bubble: UIView?
    private let tilesRow = UIStackView()
    private var tiles: [UIView] = []
    private var joiners: [UIView] = []
    private let changeLabel = UILabel()
    private let hintLabel = UILabel()
    private var showsTiles = false

    private static let formFont = UIFont.systemFont(ofSize: 26, weight: .semibold)

    init(chunk: ListenFirstChunk, step: String) {
        self.chunk = chunk
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.borderWidth = ExperimentCardStroke.normalWidth

        let eyebrow = UILabel()
        eyebrow.text = "SPOKEN · \(step)"
        eyebrow.font = .systemFont(ofSize: 11, weight: .heavy)
        eyebrow.textColor = .systemYellow

        let meaning = UILabel()
        meaning.text = "“\(chunk.meaning)”"
        meaning.font = .preferredFont(forTextStyle: .subheadline)
        meaning.textColor = .secondaryLabel
        meaning.textAlignment = .center

        tilesRow.axis = .horizontal
        tilesRow.alignment = .top
        tilesRow.spacing = 4
        tilesRow.translatesAutoresizingMaskIntoConstraints = false
        for (index, piece) in chunk.tiles.enumerated() {
            if index > 0 {
                let plus = UILabel()
                plus.text = "+"
                plus.font = .systemFont(ofSize: 14, weight: .bold)
                plus.textColor = .tertiaryLabel
                plus.alpha = 0
                plus.translatesAutoresizingMaskIntoConstraints = false
                let wrap = UIView()
                wrap.addSubview(plus)
                NSLayoutConstraint.activate([
                    plus.centerXAnchor.constraint(equalTo: wrap.centerXAnchor),
                    plus.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 14),
                    wrap.widthAnchor.constraint(equalToConstant: 10),
                ])
                joiners.append(plus)
                tilesRow.addArrangedSubview(wrap)
            }
            let tile = Self.tile(for: piece)
            tile.alpha = 0
            tiles.append(tile)
            tilesRow.addArrangedSubview(tile)
        }

        bubbleHost.translatesAutoresizingMaskIntoConstraints = false
        bubbleHost.isUserInteractionEnabled = false
        splitStage.translatesAutoresizingMaskIntoConstraints = false
        splitStage.addSubview(bubbleHost)
        splitStage.addSubview(tilesRow)
        splitStage.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(stageTapped)))
        splitStage.isAccessibilityElement = true
        splitStage.accessibilityHint = "Steps it toward the textbook form"
        splitStage.accessibilityTraits = .button

        changeLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        changeLabel.textColor = .systemOrange
        changeLabel.textAlignment = .center
        changeLabel.isHidden = true

        noteLabel.font = .preferredFont(forTextStyle: .subheadline)
        noteLabel.textColor = .label
        noteLabel.textAlignment = .center
        noteLabel.numberOfLines = 0

        hintLabel.text = "Tap to unsquash"
        hintLabel.font = .preferredFont(forTextStyle: .caption1)
        hintLabel.textColor = .tertiaryLabel
        hintLabel.textAlignment = .center
        hintLabel.alpha = 0

        let stack = UIStackView(arrangedSubviews: [eyebrow, splitStage, meaning, changeLabel, noteLabel, hintLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(14, after: eyebrow)
        stack.setCustomSpacing(12, after: meaning)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            bubbleHost.centerXAnchor.constraint(equalTo: splitStage.centerXAnchor),
            bubbleHost.centerYAnchor.constraint(equalTo: splitStage.centerYAnchor),
            bubbleHost.leadingAnchor.constraint(greaterThanOrEqualTo: splitStage.leadingAnchor),
            bubbleHost.topAnchor.constraint(greaterThanOrEqualTo: splitStage.topAnchor),

            tilesRow.centerXAnchor.constraint(equalTo: splitStage.centerXAnchor),
            tilesRow.centerYAnchor.constraint(equalTo: splitStage.centerYAnchor),
            tilesRow.leadingAnchor.constraint(greaterThanOrEqualTo: splitStage.leadingAnchor),
            tilesRow.topAnchor.constraint(greaterThanOrEqualTo: splitStage.topAnchor),
        ])
        setBubble(for: chunk.forms[0], animated: false)
        applyChrome()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (panel: ListenFirstUnsquashPanel, _) in
            panel.applyChrome()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func tile(for piece: NaturalPiece) -> UIView {
        let japanese = UILabel()
        japanese.text = piece.japanese
        japanese.font = .systemFont(ofSize: 20, weight: .semibold)
        japanese.textColor = .label
        japanese.textAlignment = .center
        japanese.adjustsFontSizeToFitWidth = true
        japanese.minimumScaleFactor = 0.6

        let gloss = UILabel()
        gloss.text = piece.gloss
        gloss.font = .preferredFont(forTextStyle: .caption1)
        gloss.textColor = .secondaryLabel
        gloss.textAlignment = .center
        gloss.numberOfLines = 2

        let stack = UIStackView(arrangedSubviews: [japanese, gloss])
        stack.axis = .vertical
        stack.spacing = 2
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        stack.backgroundColor = ExperimentPalette.highlightFill
        stack.layer.cornerRadius = 12
        stack.layer.cornerCurve = .continuous
        return stack
    }

    @objc private func stageTapped() {
        guard showsTiles || formIndex > 0 else { return }
        onTap?()
    }

    func setPlaying(_ playing: Bool) {
        guard let bubble = bubble as? DialogueJapaneseBubbleView else { return }
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            bubble.setEmphasis(playing ? 1.25 : 1)
        }
    }

    /// The spoken form, split into its pieces.
    func showTiles(animated: Bool) {
        guard !showsTiles else { return }
        showsTiles = true
        hintLabel.text = "Tap to unsquash"
        UIView.animate(withDuration: 0.3) { self.hintLabel.alpha = 1 }
        splitStage.layoutIfNeeded()

        let center = CGPoint(x: splitStage.bounds.midX, y: splitStage.bounds.midY)
        let fly = !UIAccessibility.isReduceMotionEnabled && animated
        if fly {
            for tile in tiles {
                let tileCenter = splitStage.convert(CGPoint(x: tile.bounds.midX, y: tile.bounds.midY), from: tile)
                tile.transform = CGAffineTransform(translationX: center.x - tileCenter.x, y: 0).scaledBy(x: 0.55, y: 0.55)
            }
        }
        UIView.animate(withDuration: animated ? 0.3 : 0) {
            self.bubble?.alpha = 0
            self.joiners.forEach { $0.alpha = 1 }
        }
        for (index, tile) in tiles.enumerated() {
            UIView.animate(
                withDuration: animated ? 0.55 : 0,
                delay: fly ? Double(index) * 0.05 : 0,
                usingSpringWithDamping: 0.72,
                initialSpringVelocity: 0.4,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                tile.alpha = 1
                tile.transform = .identity
            }
        }
    }

    /// Moves to `index` on the ladder (0 = spoken, which shows the tiles again).
    func show(formAt index: Int, animated: Bool) {
        formIndex = index
        let form = chunk.forms[index]
        let isTextbook = index == chunk.forms.count - 1
        hintLabel.text = isTextbook ? "Tap to squeeze it back together" : "Tap to unsquash"
        changeLabel.text = form.change.map { "What changed: \($0)" }
        changeLabel.isHidden = form.change == nil
        if index == 0 {
            noteLabel.text = nil
            setBubble(for: form, animated: animated)
            showsTiles = false
            timelineFreeDelay(0.35) { [weak self] in self?.showTiles(animated: animated) }
            return
        }
        hideTiles(animated: animated)
        setBubble(for: form, animated: animated)
    }

    private func hideTiles(animated: Bool) {
        guard showsTiles else { return }
        showsTiles = false
        UIView.animate(withDuration: animated ? 0.25 : 0) {
            self.tiles.forEach { $0.alpha = 0 }
            self.joiners.forEach { $0.alpha = 0 }
        }
    }

    /// Cross-fades to a new bubble whose changed characters are highlighted.
    private func setBubble(for form: ListenFirstForm, animated: Bool) {
        let incoming = OnboardingChrome.makeDialogueBubble(text: form.text, font: Self.formFont, side: nil)
        Self.highlight(form.changed, in: incoming.label)
        incoming.translatesAutoresizingMaskIntoConstraints = false
        let outgoing = bubble
        bubble = incoming
        splitStage.accessibilityLabel = form.text

        bubbleHost.addSubview(incoming)
        NSLayoutConstraint.activate([
            incoming.topAnchor.constraint(equalTo: bubbleHost.topAnchor),
            incoming.bottomAnchor.constraint(equalTo: bubbleHost.bottomAnchor),
            incoming.leadingAnchor.constraint(equalTo: bubbleHost.leadingAnchor),
            incoming.trailingAnchor.constraint(equalTo: bubbleHost.trailingAnchor),
        ])
        guard animated, let outgoing else {
            outgoing?.removeFromSuperview()
            return
        }
        incoming.alpha = 0
        let grow = !UIAccessibility.isReduceMotionEnabled
        if grow {
            incoming.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }
        UIView.animate(withDuration: 0.2, animations: {
            outgoing.alpha = 0
        }, completion: { _ in
            outgoing.removeFromSuperview()
        })
        UIView.animate(withDuration: 0.45, delay: 0.08, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.3, options: [.allowUserInteraction]) {
            incoming.alpha = 1
            incoming.transform = .identity
            self.superview?.layoutIfNeeded()
        }
    }

    /// Recolors the changed characters inside the furigana-built text.
    private static func highlight(_ substrings: [String], in label: UILabel) {
        guard !substrings.isEmpty, let attributed = label.attributedText else { return }
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let text = mutable.string as NSString
        for substring in substrings {
            let range = text.range(of: substring)
            guard range.location != NSNotFound else { continue }
            mutable.addAttribute(.foregroundColor, value: UIColor.systemOrange, range: range)
        }
        label.attributedText = mutable
    }

    private func timelineFreeDelay(_ delay: TimeInterval, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func applyChrome() {
        backgroundColor = ExperimentPalette.cardSurface
        layer.borderColor = ExperimentPalette.cardBorder.cgColor
    }
}

/// "Same trick" strip: 分からない → わかんない, each side playable, the melted sound highlighted.
final class ListenFirstCalloutStrip: UIView {

    var onPlay: ((ListenFirstForm) -> Void)?
    private let callout: ListenFirstCallout

    init(callout: ListenFirstCallout) {
        self.callout = callout
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous

        let from = Self.formButton(callout.from)
        from.addTarget(self, action: #selector(fromTapped), for: .touchUpInside)
        let to = Self.formButton(callout.to)
        to.addTarget(self, action: #selector(toTapped), for: .touchUpInside)
        let arrow = UIImageView(image: UIImage(systemName: "arrow.right"))
        arrow.tintColor = .tertiaryLabel
        arrow.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [from, arrow, to])
        row.spacing = 10
        row.alignment = .center
        row.distribution = .equalCentering

        let caption = UILabel()
        caption.text = callout.caption
        caption.font = .preferredFont(forTextStyle: .footnote)
        caption.textColor = .secondaryLabel
        caption.numberOfLines = 0
        caption.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [row, caption])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
        ])
        backgroundColor = ExperimentPalette.highlightFill
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (strip: ListenFirstCalloutStrip, _) in
            strip.backgroundColor = ExperimentPalette.highlightFill
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func formButton(_ form: ListenFirstForm) -> UIButton {
        let text = NSMutableAttributedString(string: form.text, attributes: [
            .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: UIColor.label,
        ])
        for changed in form.changed {
            let range = (form.text as NSString).range(of: changed)
            if range.location != NSNotFound {
                text.addAttribute(.foregroundColor, value: UIColor.systemOrange, range: range)
            }
        }
        var config = UIButton.Configuration.plain()
        config.attributedTitle = AttributedString(text)
        config.image = UIImage(systemName: "speaker.wave.2.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12))
        config.imagePlacement = .trailing
        config.imagePadding = 6
        config.baseForegroundColor = .tertiaryLabel
        let button = UIButton(configuration: config)
        button.accessibilityLabel = form.text
        button.accessibilityHint = "Plays it"
        return button
    }

    @objc private func fromTapped() {
        HapticsHelper.lightHaptic()
        onPlay?(callout.from)
    }

    @objc private func toTapped() {
        HapticsHelper.lightHaptic()
        onPlay?(callout.to)
    }
}

// MARK: - 6 · Whose Japanese

final class ListenFirstStyleStepViewController: NaturalRegisterStepViewController {
    override func phrases(for register: NaturalRegister) -> [TutorLine] {
        ListenFirstContent.phrases(for: register)
    }

    override func breakdown(for phrase: TutorLine) -> SentenceScrubScript? {
        ListenFirstContent.breakdowns[phrase.japanese]
    }
}

// MARK: - 8 · Your path

final class ListenFirstPlanStepViewController: NaturalPlanStepViewController {

    private var listen: ListenFirstSession? { natural as? ListenFirstSession }

    /// Where the floating Hana sits while you pick and while the path builds: the empty CTA area.
    private let hanaSpot = UIView()
    private var isPicking = true
    private static let hanaSize: CGFloat = 120
    /// Looking up at the options.
    private static let hanaWatchingOptions = MascotExpression([.lookY: -0.85])

    override var planGeneratingTitle: String { "Building your path…" }

    override func buildStage() {
        super.buildStage()
        isPicking = true
        // On `view`, below the clipped stage. Re-added each build so constraints don't pile up.
        hanaSpot.removeFromSuperview()
        hanaSpot.translatesAutoresizingMaskIntoConstraints = false
        hanaSpot.isUserInteractionEnabled = false
        view.addSubview(hanaSpot)
        NSLayoutConstraint.activate([
            hanaSpot.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hanaSpot.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            hanaSpot.widthAnchor.constraint(equalToConstant: Self.hanaSize),
            hanaSpot.heightAnchor.constraint(equalToConstant: Self.hanaSize),
        ])
    }

    /// Glides in from the level screen's spot. Once the path is built she lives in the chat.
    override func hanaStageDidAppear(firstTime: Bool) {
        guard let hanaStage else { return }
        if isPicking {
            hanaStage.dock(at: hanaSpot, expression: Self.hanaWatchingOptions)
        } else {
            hanaStage.hide()
        }
    }

    /// Bigger commitment, bigger reaction. She looks at the card you picked, then stays put
    /// until the stat chat starts and she flies into it.
    override func playInterlude(clearing options: UIView, proceed: @escaping () -> Void) {
        isPicking = false
        if let hanaStage {
            let minutes = natural.minutesPerDay
            hanaStage.mascot.play(minutes >= 20 ? .excited : minutes >= 10 ? .happy : .pleased)
            if let chosen = options.subviews.compactMap({ $0 as? OnboardingSummaryCard }).first(where: { $0.isChosen }) {
                hanaStage.look(atWindowPoint: chosen.convert(CGPoint(x: chosen.bounds.midX, y: chosen.bounds.midY), to: nil))
            }
        }
        super.playInterlude(clearing: options, proceed: proceed)
    }

    /// She steps out of the stat chat and gets to work at the bottom while the checklist runs.
    override func willGeneratePlan() {
        guard let hanaStage else { return }
        if let frame = interludeChat?.detachMascot() {
            hanaStage.appear(at: frame)
        }
        hanaStage.dock(at: hanaSpot, expression: MascotPreset.working.expression)
    }

    private func continueInterlude(clearing options: UIView, proceed: @escaping () -> Void) {
        super.playInterlude(clearing: options, proceed: proceed)
    }

    /// A swipeable card per scene of the first lesson, with Hana pointing it out underneath.
    /// The beginner track has no scene titles yet, so it keeps the plain plan card.
    override func showPlan(done: @escaping () -> Void) {
        let lesson = ListenFirstContent.firstLesson(for: listen?.trackKind ?? .kaitoAndMika)
        guard !lesson.scenes.isEmpty else {
            super.showPlan(done: done)
            return
        }
        HapticsHelper.successHaptic()

        let eyebrow = UILabel()
        eyebrow.text = "\(natural.track.uppercased()) · LESSON 1"
        eyebrow.font = .systemFont(ofSize: 12, weight: .bold)
        eyebrow.textColor = .secondaryLabel
        let title = UILabel()
        title.text = lesson.title
        title.font = .systemFont(ofSize: 22, weight: .bold)
        let header = UIStackView(arrangedSubviews: [eyebrow, title])
        header.axis = .vertical
        header.alignment = .center
        header.spacing = 2

        // Only a handful of thumbnails exist yet; shuffle so neighbors don't repeat.
        var thumbnails = ListenFirstContent.sceneThumbnails.shuffled()
        let scenes = lesson.scenes.enumerated().map { index, scene in
            if thumbnails.isEmpty { thumbnails = ListenFirstContent.sceneThumbnails.shuffled() }
            return ListenFirstSceneCarousel.Scene(label: "Scene \(index + 1)", title: scene, thumbnail: thumbnails.removeLast())
        }
        let carousel = ListenFirstSceneCarousel(scenes: scenes)
        carousel.onFocusChanged = { _ in HapticsHelper.superLightHaptic() }

        let chat = makeChat()
        for subview in [header, carousel, chat] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
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

            chat.topAnchor.constraint(equalTo: carousel.bottomAnchor),
            chat.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            chat.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            chat.bottomAnchor.constraint(equalTo: stage.bottomAnchor),
        ])
        slideIn([header, carousel], stagger: 0.1, initialDelay: 0.15)

        timeline.after(0.9) { [weak self] in
            guard let self else { return }
            chat.play(self.pathReadyLines.map { .tutorJapanese($0) }, completion: done)
        }
    }

    /// Four rows, each tied to a setting the answers actually change.
    override var planChecklist: [String] {
        let gentleStart = natural.level == .brandNew || natural.level == .kana
        return [
            "Starting you on the \(natural.track) track",
            "Setting transcripts to “\(natural.level.title)”",
            gentleStart ? "Easing playback a touch slower to start" : "Keeping playback at natural speed",
            "Flagging \(natural.register.focus)",
        ]
    }

    override var planCard: TutorPlanCard.Content {
        let lesson = ListenFirstContent.firstLesson(for: listen?.trackKind ?? .kaitoAndMika)
        return TutorPlanCard.Content(
            eyebrow: "\(natural.track.uppercased()) · LESSON 1",
            title: lesson.title,
            rows: lesson.scenes.enumerated().map { index, scene in
                TutorPlanCard.Row(label: "Scene \(index + 1)", title: scene, detail: nil)
            }
        )
    }

    override var statUnit: String { "listens" }

    override var statFootnote: String? {
        "Total listening at \(natural.minutesPerDay) min a day, every day. A listen is one scene start to finish, replays included."
    }

    override var statReactions: [TutorLine] {
        [
            TutorLine("うわー！8週間でこんなに聞けるの？", "Whoa, you'll hear this much in 8 weeks?"),
            TutorLine("毎日ちょっとずつで大丈夫。", "A little every day is all it takes."),
            TutorLine("頑張ろうね！", "Let's do this!"),
        ]
    }

    /// One line under the scene carousel, pointing at it. Needs native review like all content.
    override var pathReadyLines: [TutorLine] {
        [
            TutorLine("最初のレッスンだよ。スワイプして見てみて！", "Here's your first lesson. Swipe through it!"),
        ]
    }
}

// MARK: - Scene carousel

/// Horizontally paging scene cards. The centered card is full size; its neighbors shrink and dim.
final class ListenFirstSceneCarousel: UIView, UICollectionViewDataSource {

    struct Scene {
        let label: String
        let title: String
        let thumbnail: String
    }

    static let height: CGFloat = 250
    private static let cardHeight: CGFloat = 230
    private static let restingScale: CGFloat = 0.86
    private static let cardSpacing: CGFloat = 4

    /// The index of the card that just became centered.
    var onFocusChanged: ((Int) -> Void)?

    private let scenes: [Scene]
    private var focusedIndex = 0
    private var collectionView: UICollectionView!

    init(scenes: [Scene]) {
        self.scenes = scenes
        super.init(frame: .zero)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = false
        collectionView.isScrollEnabled = false   // the section pages on its own
        collectionView.dataSource = self
        collectionView.register(Cell.self, forCellWithReuseIdentifier: Cell.reuseIdentifier)
        addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .fractionalHeight(1)
        ))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(0.62),
                heightDimension: .absolute(Self.cardHeight)
            ),
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .groupPagingCentered
        section.interGroupSpacing = Self.cardSpacing
        let verticalInset = (Self.height - Self.cardHeight) / 2
        section.contentInsets = NSDirectionalEdgeInsets(top: verticalInset, leading: 0, bottom: verticalInset, trailing: 0)
        // Scale and dim each card by its distance from the center; report the new center card.
        section.visibleItemsInvalidationHandler = { [weak self] items, offset, environment in
            guard let self else { return }
            let center = offset.x + environment.container.contentSize.width / 2
            var nearest: (index: Int, distance: CGFloat)?
            for item in items where item.representedElementCategory == .cell {
                let distance = abs(item.frame.midX - center)
                let t = min(1, distance / (item.frame.width + Self.cardSpacing))
                let scale = 1 - (1 - Self.restingScale) * t
                item.transform = CGAffineTransform(scaleX: scale, y: scale)
                item.alpha = 1 - 0.35 * t
                if distance < nearest?.distance ?? .greatestFiniteMagnitude {
                    nearest = (item.indexPath.item, distance)
                }
            }
            if let index = nearest?.index, index != self.focusedIndex {
                self.focusedIndex = index
                self.onFocusChanged?(index)
            }
        }
        return UICollectionViewCompositionalLayout(section: section)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        scenes.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Cell.reuseIdentifier, for: indexPath)
        (cell as? Cell)?.configure(with: scenes[indexPath.item])
        return cell
    }

    /// Thumbnail filling the card, with the scene number and title over a bottom scrim.
    private final class Cell: UICollectionViewCell {

        static let reuseIdentifier = "ListenFirstSceneCell"

        private let imageView = UIImageView()
        private let scrim = CAGradientLayer()
        private let sceneLabel = UILabel()
        private let titleLabel = UILabel()

        override init(frame: CGRect) {
            super.init(frame: frame)
            contentView.layer.cornerRadius = 22
            contentView.layer.cornerCurve = .continuous
            contentView.layer.borderWidth = 3
            contentView.layer.borderColor = UIColor.white.cgColor
            contentView.clipsToBounds = true
            contentView.backgroundColor = ExperimentPalette.cardSurface

            imageView.contentMode = .scaleAspectFill
            imageView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(imageView)

            scrim.colors = [UIColor.black.withAlphaComponent(0).cgColor, UIColor.black.withAlphaComponent(0.6).cgColor]
            scrim.locations = [0.45, 1]
            contentView.layer.addSublayer(scrim)

            sceneLabel.font = .systemFont(ofSize: 12, weight: .bold)
            sceneLabel.textColor = UIColor.white.withAlphaComponent(0.85)
            titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
            titleLabel.textColor = .white
            titleLabel.numberOfLines = 2
            let text = UIStackView(arrangedSubviews: [sceneLabel, titleLabel])
            text.axis = .vertical
            text.spacing = 2
            text.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(text)

            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
                imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

                text.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
                text.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
                text.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            ])
            isAccessibilityElement = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            scrim.frame = contentView.bounds
            CATransaction.commit()
        }

        func configure(with scene: Scene) {
            imageView.image = UIImage(named: scene.thumbnail)
            sceneLabel.text = scene.label.uppercased()
            titleLabel.text = scene.title
            accessibilityLabel = "\(scene.label): \(scene.title)"
        }
    }
}
