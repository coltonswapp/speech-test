//
//  NaturalOnboardingListenSteps.swift
//  shizen
//
//  The heart of the flow, styled like Dialogue: hear the conversation as glass
//  meter bubbles, guess the gist, then watch the words reveal in place and
//  split spoken chunks into the pieces they're squashed from. Plan and
//  send-off reuse the tutor steps with listening copy.
//

import AVFoundation
import InteractionKit
import NNKit
import UIKit

// MARK: - Dialogue line

/// One conversation line the way Dialogue draws it: speaker caption, glass bubble, English under it.
/// Starts audio-only (a speaker-tinted live meter in the bubble) and can reveal its Japanese in place.
final class NaturalDialogueLineView: UIView {

    static let japaneseFont: UIFont = {
        let base = UIFont.preferredFont(forTextStyle: .title2)
        return .systemFont(ofSize: base.pointSize, weight: .medium)
    }()

    private static let inactiveEmphasis: CGFloat = 0.4

    private let side: DialogueSpeakerSide
    private let japanese: String
    private let label = FuriganaTranscriptLabel()
    private let bubble: DialogueJapaneseBubbleView
    private let meter = NaturalDialogueLineView.makeMeter()
    private let englishLabel = UILabel()
    private var meterSizing: [NSLayoutConstraint] = []
    private(set) var isRevealed = false

    /// The Japanese once revealed, for measuring or marking individual words.
    var transcriptLabel: FuriganaTranscriptLabel { label }

    init(speaker: String, side: DialogueSpeakerSide, japanese: String, english: String?) {
        self.side = side
        self.japanese = japanese
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .natural
        label.alpha = 0
        bubble = DialogueJapaneseBubbleView(label: label)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityLabel = "\(speaker), audio only"

        let speakerLabel = UILabel()
        speakerLabel.text = "\(speaker):"
        speakerLabel.font = GrammarJapaneseTypography.scenarioSpeakerFont
        speakerLabel.textColor = .secondaryLabel
        let speakerWrapper = DialogueBubbleLayout.insetMetadataWrapper(around: speakerLabel, side: side)

        // Meter owns the bubble's size until the Japanese is revealed.
        bubble.setBackgroundStyle(.glass)
        bubble.setLabelContributesToLayout(false)
        bubble.setUnderglowConfiguration(.compactMeter(for: side))
        bubble.addSubview(meter)
        let meterSize = meter.intrinsicContentSize
        meterSizing = [
            bubble.widthAnchor.constraint(equalTo: meter.widthAnchor, constant: 56),
            bubble.heightAnchor.constraint(equalTo: meter.heightAnchor, constant: 24),
        ]

        englishLabel.text = english
        englishLabel.font = .preferredFont(forTextStyle: .subheadline)
        englishLabel.textColor = .secondaryLabel
        englishLabel.numberOfLines = 0
        englishLabel.textAlignment = side == .trailing ? .right : .left
        let englishWrapper = DialogueBubbleLayout.insetMetadataWrapper(around: englishLabel, side: side)
        englishWrapper.isHidden = true
        englishWrapper.alpha = 0

        let column = UIStackView(arrangedSubviews: [speakerWrapper, bubble, englishWrapper])
        column.axis = .vertical
        column.spacing = 6
        column.alignment = side == .leading ? .leading : .trailing
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        let horizontal: [NSLayoutConstraint] = side == .leading
            ? [
                column.leadingAnchor.constraint(equalTo: leadingAnchor),
                column.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -36),
            ]
            : [
                column.trailingAnchor.constraint(equalTo: trailingAnchor),
                column.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 36),
            ]
        NSLayoutConstraint.activate(horizontal + meterSizing + [
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            meter.centerXAnchor.constraint(equalTo: bubble.centerXAnchor),
            meter.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),
            meter.widthAnchor.constraint(equalToConstant: meterSize.width),
            meter.heightAnchor.constraint(equalToConstant: meter.meterHeight),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Mirrors Dialogue's listening meter (8pt bars, 6pt gaps, low wobble), tinted per speaker.
    static func makeMeter() -> AudioLevelBarsView {
        let meter = AudioLevelBarsView()
        meter.translatesAutoresizingMaskIntoConstraints = false
        meter.isUserInteractionEnabled = false
        meter.barWidth = 8
        meter.barSpacing = 6
        meter.meterHeight = 36
        meter.minBarHeight = 8
        meter.heightFill = 0.95
        meter.levelGain = 1.6
        meter.displayCurve = 1.05
        meter.smoothing = 0.66
        meter.wobbleAmount = 0.08
        meter.diamondFalloff = 0.25
        meter.springiness = 0.5
        meter.historyStride = 2
        return meter
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        meter.barColor = side == .leading ? .systemBlue : .systemYellow
    }

    func push(level: Float) {
        meter.setLevel(level)
    }

    func rest() {
        meter.releaseToRest()
    }

    /// Dims everyone but the speaker, the way Dialogue pulls focus.
    func setFocused(_ focused: Bool, animated: Bool) {
        let apply = {
            self.bubble.setEmphasis(focused ? 1 : Self.inactiveEmphasis)
            self.alpha = focused ? 1 : 0.55
        }
        guard animated else {
            apply()
            return
        }
        UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: apply)
    }

    /// Hands sizing from the meter to the label and fades the Japanese (and English) in.
    func reveal(showsEnglish: Bool, animated: Bool) {
        guard !isRevealed else { return }
        isRevealed = true
        accessibilityLabel = [japanese, englishLabel.text].compactMap { $0 }.joined(separator: ", ")

        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        JapaneseFuriganaBuilder.applyDialogueBubbleDisplay(to: label, text: japanese, font: Self.japaneseFont, textColor: .label)
        DialogueContentLineWrap.applyOrphanGlue(to: label)
        NSLayoutConstraint.deactivate(meterSizing)
        bubble.setLabelContributesToLayout(true)
        bubble.setUnderglowConfiguration(.forSpeaker(side))
        meter.releaseToRest()

        let englishWrapper = englishLabel.superview
        let showEnglish = showsEnglish && englishLabel.text != nil
        englishWrapper?.isHidden = !showEnglish

        let apply = {
            self.meter.alpha = 0
            self.label.alpha = 1
            englishWrapper?.alpha = showEnglish ? 1 : 0
            self.window?.layoutIfNeeded()
        }
        guard animated else {
            apply()
            meter.isHidden = true
            return
        }
        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: apply
        ) { _ in
            self.meter.isHidden = true
        }
    }
}

/// A gist answer on glass, like the chat bubbles around it. Marked right or wrong once picked.
final class NaturalGistOption: UIControl {

    enum Mark {
        case idle
        case right
        case wrong
    }

    var mark: Mark = .idle {
        didSet { applyChrome() }
    }

    private let glass = LiquidGlassEffectView.makeContainer()
    /// Green or red wash over the glass for a marked answer.
    private let markWash = UIView()
    private let label = UILabel()
    private let icon = UIImageView()

    init(text: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityLabel = text
        accessibilityTraits = .button

        LiquidGlassEffectView.applyBubbleStyle(to: glass, cornerRadius: 18)
        markWash.layer.cornerRadius = 18
        markWash.layer.cornerCurve = .continuous
        for chrome in [glass, markWash] as [UIView] {
            chrome.isUserInteractionEnabled = false
            chrome.translatesAutoresizingMaskIntoConstraints = false
            addSubview(chrome)
            NSLayoutConstraint.activate([
                chrome.topAnchor.constraint(equalTo: topAnchor),
                chrome.leadingAnchor.constraint(equalTo: leadingAnchor),
                chrome.trailingAnchor.constraint(equalTo: trailingAnchor),
                chrome.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        label.text = text
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 54),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(lessThanOrEqualTo: icon.leadingAnchor, constant: -10),
            icon.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
        ])
        applyChrome()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (option: NaturalGistOption, _) in
            option.applyChrome()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
            }
        }
    }

    private func applyChrome() {
        switch mark {
        case .idle:
            markWash.backgroundColor = .clear
            markWash.layer.borderWidth = 0
            icon.image = nil
        case .right:
            markWash.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.16)
            markWash.layer.borderColor = UIColor.systemGreen.cgColor
            markWash.layer.borderWidth = ExperimentCardStroke.emphasisWidth
            icon.image = UIImage(systemName: "checkmark.circle.fill")
            icon.tintColor = .systemGreen
        case .wrong:
            markWash.backgroundColor = UIColor.systemRed.withAlphaComponent(0.12)
            markWash.layer.borderColor = UIColor.systemRed.withAlphaComponent(0.7).cgColor
            markWash.layer.borderWidth = ExperimentCardStroke.emphasisWidth
            icon.image = UIImage(systemName: "xmark.circle.fill")
            icon.tintColor = .systemRed
        }
    }
}

// MARK: - Plan

class NaturalPlanStepViewController: TutorPlanStepViewController {

    let natural: NaturalOnboardingSession
    /// The chat under the listening stat, while it's on screen.
    private(set) weak var interludeChat: TutorChatView?

    // MARK: Listening-flow hooks

    var statUnit: String { "scenes heard" }
    var statFootnote: String? { nil }
    var statReactions: [TutorLine] {
        [
            TutorLine("うわー！8週間でこんなに聞けるの？", "Whoa, you'll hear this much in 8 weeks?"),
            TutorLine("毎日ちょっとずつで大丈夫。", "A little every day is all it takes."),
            TutorLine("頑張ろうぜ！", "Let's do this!"),
        ]
    }
    var pathReadyLines: [TutorLine] {
        [
            TutorLine("\(natural.displayName)さんの道、できたよ！", "Your path is ready, \(natural.displayName)!"),
            TutorLine("まずは駅のシーンから始めよう。", "We'll start at the train station."),
        ]
    }

    init(session: NaturalOnboardingSession) {
        natural = session
        super.init(session: session)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var planPicker: (title: String, subtitle: String, options: [(minutes: Int, text: String)]) {
        (
            "How much listening a day?",
            "One scene takes about three minutes.",
            [
                (5, "☕️  5 min a day · A scene or two"),
                (10, "🍵  10 min a day · A full lesson"),
                (20, "🎧  20 min a day · Deep listening"),
            ]
        )
    }

    override var planGeneratingSubtitle: String {
        "Hana is setting up your path."
    }

    /// Between the pick and the checklist: what this pace adds up to by week 1 and week 8.
    override func playInterlude(clearing options: UIView, proceed: @escaping () -> Void) {
        UIView.animate(withDuration: AnimationDefaults.standardDuration) {
            options.alpha = 0
            options.transform = CGAffineTransform(translationX: 0, y: -16)
        }
        let minutes = natural.minutesPerDay
        transitionHeader(title: "That adds up fast.", subtitle: "\(minutes) min a day of real, natural-speed Japanese.")

        // Graph and Hana's reactions share one scroll area, so the chat has room on small screens.
        let chat = makeChat()
        interludeChat = chat
        stage.addSubview(chat)
        NSLayoutConstraint.activate([
            chat.topAnchor.constraint(equalTo: stage.topAnchor),
            chat.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            chat.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            chat.bottomAnchor.constraint(equalTo: stage.bottomAnchor),
        ])
        scrollUnderHeader(chat, scrollView: chat.scrollContainer)

        let stat = NaturalListeningStatView(minutesPerDay: minutes, unit: statUnit, footnote: statFootnote)
        timeline.after(0.2) { [weak self] in
            guard let self else { return }
            chat.appendCustom(stat)
            self.timeline.after(0.35) { [weak self] in
                guard let self else { return }
                stat.play(on: self.timeline)
                HapticsHelper.lightHaptic()
            }
        }
        timeline.after(2.1) { [weak self] in
            chat.play(self?.statReactions.map { .tutorJapanese($0) } ?? []) { [weak self] in
                self?.continueOnCTA("Build my path") { [weak self] in
                    UIView.animate(withDuration: AnimationDefaults.standardDuration, animations: {
                        chat.alpha = 0
                        chat.transform = CGAffineTransform(translationX: 0, y: -16)
                    }, completion: { _ in
                        chat.removeFromSuperview()
                    })
                    self?.timeline.after(0.2) { proceed() }
                }
            }
        }
    }

    /// Hana chimes in under the finished path before the CTA appears.
    override func playAfterPlan(below card: UIView, done: @escaping () -> Void) {
        let chat = makeChat()
        stage.addSubview(chat)
        NSLayoutConstraint.activate([
            chat.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 4),
            chat.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            chat.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            chat.bottomAnchor.constraint(equalTo: stage.bottomAnchor),
        ])
        let lines = pathReadyLines.map { TutorChatView.Message.tutorJapanese($0) }
        timeline.after(0.4) {
            chat.play(lines, completion: done)
        }
    }

    override var planReadyHeader: (title: String, subtitle: String) {
        ("Your path is ready.", "Set up for \(natural.displayName) · \(natural.minutesPerDay) min a day")
    }

    override var planCard: TutorPlanCard.Content {
        TutorPlanCard.Content(
            eyebrow: "\(natural.track) · LESSON 1",
            title: "🚉 \(NaturalFirstLesson.title)",
            rows: NaturalFirstLesson.scenes.enumerated().map { index, scene in
                TutorPlanCard.Row(label: "Scene \(index + 1)", title: scene, detail: nil)
            }
        )
    }

    override var planSummary: String {
        "Every lesson is a handful of real scenes. You'll start on \(natural.track)."
    }
}

/// Week 1 and week 8 listening totals as two stat tiles over a cumulative eight-week bar strip.
/// Assumes every day at the chosen pace and about three minutes per scene.
final class NaturalListeningStatView: UIView {

    private static let minutesPerScene = 3
    private static let weeks = 8
    private static let chartHeight: CGFloat = 96

    private let minutesPerDay: Int
    private let weekOneValue = UILabel()
    private let weekEightValue = UILabel()
    private var bars: [UIView] = []
    private var barHeights: [NSLayoutConstraint] = []

    /// `unit` follows the "≈ N" count (e.g. "scenes heard", "listens"); `footnote` replaces the default one.
    init(minutesPerDay: Int, unit: String = "scenes heard", footnote footnoteText: String? = nil) {
        self.minutesPerDay = minutesPerDay
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = ExperimentPalette.cardSurface
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.borderWidth = ExperimentCardStroke.normalWidth
        layer.borderColor = ExperimentPalette.cardBorder.cgColor

        let weekOne = Self.tile(
            eyebrow: "AFTER WEEK 1",
            value: weekOneValue,
            detail: "≈ \(Self.scenes(afterWeeks: 1, minutesPerDay: minutesPerDay)) \(unit)"
        )
        let weekEight = Self.tile(
            eyebrow: "AFTER WEEK 8",
            value: weekEightValue,
            detail: "≈ \(Self.scenes(afterWeeks: Self.weeks, minutesPerDay: minutesPerDay)) \(unit)"
        )
        weekOneValue.text = Self.duration(minutes: 0)
        weekEightValue.text = Self.duration(minutes: 0)
        let tiles = UIStackView(arrangedSubviews: [weekOne, weekEight])
        tiles.distribution = .fillEqually
        tiles.spacing = 12

        let chart = UIView()
        chart.translatesAutoresizingMaskIntoConstraints = false
        chart.heightAnchor.constraint(equalToConstant: Self.chartHeight).isActive = true
        let barStack = UIStackView()
        barStack.axis = .horizontal
        barStack.alignment = .bottom
        barStack.distribution = .fillEqually
        barStack.spacing = 6
        barStack.translatesAutoresizingMaskIntoConstraints = false
        chart.addSubview(barStack)
        let baseline = UIView()
        baseline.backgroundColor = ExperimentPalette.cardBorder
        baseline.translatesAutoresizingMaskIntoConstraints = false
        chart.addSubview(baseline)

        let axis = UIStackView()
        axis.distribution = .fillEqually
        axis.spacing = 6
        for week in 1...Self.weeks {
            let bar = UIView()
            let isLabeled = week == 1 || week == Self.weeks
            bar.backgroundColor = isLabeled ? .systemYellow : UIColor.systemYellow.withAlphaComponent(0.45)
            bar.layer.cornerRadius = 4
            bar.layer.cornerCurve = .continuous
            bar.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            let height = bar.heightAnchor.constraint(equalToConstant: 2)
            height.isActive = true
            barHeights.append(height)
            bars.append(bar)
            barStack.addArrangedSubview(bar)

            let label = UILabel()
            label.text = isLabeled ? "Wk \(week)" : ""
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            axis.addArrangedSubview(label)
        }

        NSLayoutConstraint.activate([
            barStack.leadingAnchor.constraint(equalTo: chart.leadingAnchor),
            barStack.trailingAnchor.constraint(equalTo: chart.trailingAnchor),
            barStack.bottomAnchor.constraint(equalTo: chart.bottomAnchor),
            barStack.topAnchor.constraint(equalTo: chart.topAnchor),
            baseline.leadingAnchor.constraint(equalTo: chart.leadingAnchor),
            baseline.trailingAnchor.constraint(equalTo: chart.trailingAnchor),
            baseline.bottomAnchor.constraint(equalTo: chart.bottomAnchor),
            baseline.heightAnchor.constraint(equalToConstant: 1),
        ])

        let footnote = UILabel()
        footnote.text = footnoteText ?? "Total listening at \(minutesPerDay) min a day, every day."
        footnote.font = .preferredFont(forTextStyle: .footnote)
        footnote.textColor = .secondaryLabel
        footnote.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [tiles, chart, axis, footnote])
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(20, after: tiles)
        stack.setCustomSpacing(14, after: axis)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
        ])

        isAccessibilityElement = true
        accessibilityLabel = "After week 1: \(Self.duration(minutes: minutesPerDay * 7)) of listening. "
            + "After week 8: \(Self.duration(minutes: minutesPerDay * 7 * Self.weeks))."
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: NaturalListeningStatView, _) in
            view.layer.borderColor = ExperimentPalette.cardBorder.cgColor
            baseline.backgroundColor = ExperimentPalette.cardBorder
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func tile(eyebrow: String, value: UILabel, detail: String) -> UIView {
        let eyebrowLabel = UILabel()
        eyebrowLabel.text = eyebrow
        eyebrowLabel.font = .systemFont(ofSize: 12, weight: .medium)
        eyebrowLabel.textColor = .secondaryLabel

        value.font = Self.roundedFont(ofSize: 26, weight: .bold)
        value.textColor = .label
        value.adjustsFontSizeToFitWidth = true
        value.minimumScaleFactor = 0.7

        let detailLabel = UILabel()
        detailLabel.text = detail
        detailLabel.font = .preferredFont(forTextStyle: .footnote)
        detailLabel.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [eyebrowLabel, value, detailLabel])
        stack.axis = .vertical
        stack.spacing = 2
        return stack
    }

    private static func roundedFont(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: rounded, size: size)
    }

    static func duration(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    private static func scenes(afterWeeks weeks: Int, minutesPerDay: Int) -> Int {
        minutesPerDay * 7 * weeks / minutesPerScene
    }

    /// Grows the bars left to right and counts both totals up from zero.
    func play(on timeline: TutorTimeline) {
        layoutIfNeeded()
        let tallest = CGFloat(Self.weeks)
        for (index, height) in barHeights.enumerated() {
            let bar = bars[index]
            UIView.animate(
                withDuration: 0.6,
                delay: Double(index) * 0.07,
                usingSpringWithDamping: 0.8,
                initialSpringVelocity: 0.2,
                options: [.allowUserInteraction]
            ) {
                height.constant = max(4, Self.chartHeight * CGFloat(index + 1) / tallest)
                bar.superview?.layoutIfNeeded()
            }
        }

        // Celebrate as the week 8 bar lands.
        if let lastBar = bars.last {
            let landing = Double(bars.count - 1) * 0.07 + 0.35
            timeline.after(landing) {
                OnboardingCelebration.burst(.medium, from: lastBar, at: CGPoint(x: lastBar.bounds.midX, y: 0))
                HapticsHelper.successHaptic()
            }
        }

        let weekOneTotal = minutesPerDay * 7
        let weekEightTotal = weekOneTotal * Self.weeks
        let frames = 36
        let generation = timeline.skipGeneration
        timeline.run { [weak self] in
            for frame in 1...frames {
                // Tap-to-advance: jump straight to the final totals.
                let skipped = timeline.skipGeneration != generation
                let progress = skipped ? 1 : Double(frame) / Double(frames)
                let eased = 1 - pow(1 - progress, 3)
                self?.weekOneValue.text = Self.duration(minutes: Int((Double(weekOneTotal) * eased).rounded()))
                self?.weekEightValue.text = Self.duration(minutes: Int((Double(weekEightTotal) * eased).rounded()))
                if skipped { return }
                try? await Task.sleep(for: .milliseconds(28))
                if Task.isCancelled { return }
            }
        }
    }
}

// MARK: - Commit

/// Hana won't help quitters: a slide-to-promise that the first lesson gets finished.
final class NaturalCommitStepViewController: NaturalStepViewController {

    override var progressBeatCount: Int { 2 }

    private var chat: TutorChatView?
    private let sliderGroup = UIView()
    private var slider: OnboardingDetentSliderView?
    private let captionLabel = UILabel()
    private var hasCommitted = false
    /// Listen-first v2: Hana sits above the slider and watches the knob, instead of beside her lines.
    private var hana: MascotView?
    private var isWatchingSlider = false

    private static let hanaSize: CGFloat = 104
    /// Glancing up at the chat while she talks.
    private static let hanaTalking = MascotExpression([.lookY: -0.7, .lookX: -0.15])

    override func buildStage() {
        setupOnboarding(title: "One more thing.", subtitle: "Hana has a condition.")
        hasCommitted = false
        isWatchingSlider = false

        hana?.removeFromSuperview()
        hana = nil
        let chat: TutorChatView
        if session.showsMascot {
            chat = TutorChatView(timeline: timeline, avatars: .none)
            let hana = TutorChatView.makeMascot()
            hana.translatesAutoresizingMaskIntoConstraints = false
            hana.alpha = 0
            hana.set(Self.hanaTalking, animated: false)
            self.hana = hana
            chat.onTypingChanged = { [weak self] typing in
                guard let self, !self.isWatchingSlider, !self.hasCommitted else { return }
                self.hana?.set(typing ? MascotPreset.thinking.expression : Self.hanaTalking)
            }
        } else {
            chat = makeChat()
        }
        self.chat = chat

        let slider = OnboardingDetentSliderView(detentCount: 2)
        slider.showsTicks = false
        slider.rampsHaptics = true
        slider.trackTitle = "Slide to promise"
        slider.onRelease = { [weak self] index in
            guard index == 1 else { return }
            self?.commit()
        }
        slider.onKnobMoved = { [weak self] in self?.lookAtKnob() }
        self.slider = slider

        captionLabel.text = "I'll finish Lesson 1, start to end."
        captionLabel.font = .preferredFont(forTextStyle: .footnote)
        captionLabel.textColor = .secondaryLabel
        captionLabel.textAlignment = .center

        sliderGroup.removeFromSuperview()
        sliderGroup.subviews.forEach { $0.removeFromSuperview() }
        for subview in [slider, captionLabel] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            sliderGroup.addSubview(subview)
        }
        sliderGroup.translatesAutoresizingMaskIntoConstraints = false
        sliderGroup.alpha = 0
        sliderGroup.transform = .identity
        sliderGroup.isUserInteractionEnabled = false

        // The slider lives in the CTA slot, outside the clipped stage, so it must sit on `view` to receive touches.
        stage.addSubview(chat)
        view.addSubview(sliderGroup)
        let chatFillsStage = chat.bottomAnchor.constraint(equalTo: stage.bottomAnchor)
        chatFillsStage.priority = .defaultHigh
        NSLayoutConstraint.activate([
            chat.topAnchor.constraint(equalTo: stage.topAnchor),
            chat.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            chat.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            chat.bottomAnchor.constraint(lessThanOrEqualTo: stage.bottomAnchor),
            chat.bottomAnchor.constraint(lessThanOrEqualTo: sliderGroup.topAnchor, constant: -16),
            chatFillsStage,

            // Sits where the CTA will appear; the slider leaves before the CTA arrives.
            sliderGroup.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PrimaryButton.horizontalInset),
            sliderGroup.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PrimaryButton.horizontalInset),
            sliderGroup.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            captionLabel.topAnchor.constraint(equalTo: sliderGroup.topAnchor),
            captionLabel.leadingAnchor.constraint(equalTo: sliderGroup.leadingAnchor),
            captionLabel.trailingAnchor.constraint(equalTo: sliderGroup.trailingAnchor),
            slider.topAnchor.constraint(equalTo: captionLabel.bottomAnchor, constant: 10),
            slider.leadingAnchor.constraint(equalTo: sliderGroup.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: sliderGroup.trailingAnchor),
            slider.bottomAnchor.constraint(equalTo: sliderGroup.bottomAnchor),
        ])
        if let hana {
            // On `view` with the slider; the clipped stage would cut her off.
            view.addSubview(hana)
            NSLayoutConstraint.activate([
                hana.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                hana.bottomAnchor.constraint(equalTo: sliderGroup.topAnchor, constant: 4),
                hana.widthAnchor.constraint(equalToConstant: Self.hanaSize),
                hana.heightAnchor.constraint(equalToConstant: Self.hanaSize),
                chat.bottomAnchor.constraint(lessThanOrEqualTo: hana.topAnchor, constant: -4),
            ])
        }
        scrollUnderHeader(chat, scrollView: chat.scrollContainer)
    }

    /// Points Hana's eyes at the slider knob.
    private func lookAtKnob() {
        guard let hana, isWatchingSlider, !hasCommitted, let point = slider?.knobCenterInWindow() else { return }
        hana.look(at: hana.convert(point, from: nil))
    }

    override func play() {
        if let hana {
            hana.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            UIView.animate(springDuration: 0.5, bounce: 0.35) {
                hana.alpha = 1
                hana.transform = .identity
            }
        }
        timeline.after(0.35) { [weak self] in
            self?.chat?.play([
                .tutorJapanese(TutorLine("ちょっと待って。", "Hold on a sec.")),
                .tutorJapanese(TutorLine("正直に言うね。途中でやめる人は手伝わないよ。", "I'll be honest: I don't help quitters.")),
                .tutorJapanese(TutorLine("最初のレッスン、最後までやるって約束できる？", "Can you promise to finish your first lesson?")),
            ]) { [weak self] in
                guard let self else { return }
                self.sliderGroup.isUserInteractionEnabled = true
                self.slideIn([self.sliderGroup])
                self.timeline.after(0.25) { [weak self] in
                    self?.isWatchingSlider = true
                    self?.lookAtKnob()
                }
            }
        }
    }

    private func commit() {
        guard !hasCommitted, let slider else { return }
        hasCommitted = true
        natural.promised = true
        slider.lock()
        HapticsHelper.successHaptic()
        if let hana {
            hana.play(.excited)
            timeline.after(1.6) { hana.set(MascotPreset.happy.expression) }
        }
        if let point = slider.knobCenterInWindow() {
            OnboardingCelebration.burst(.large, from: slider, at: slider.convert(point, from: nil))
        }
        advanceProgressBeat(to: 1)
        // Long enough to see the knob land and the burst start, then the slider is done.
        timeline.after(0.45) { [weak self] in self?.hideSlider() }
        transitionHeader(title: "It's a deal.", subtitle: "Lesson 1, start to end.")
        // The first three messages slide away, then Hana answers from a clean slate.
        // (Readings checked: 約束ね parses as 約+束ね, so these lines avoid it.)
        timeline.after(0.5) { [weak self] in
            self?.chat?.clear { [weak self] in
                self?.chat?.play([
                    .tutorJapanese(TutorLine("約束だよ！", "It's a promise!")),
                    .tutorJapanese(TutorLine("じゃあ、さっそく始めよう！", "Then let's get started!")),
                ]) { [weak self] in
                    self?.revealCTA("Let's go")
                }
            }
        }
    }

    /// The slider and its caption bow out of the bottom slot, which the CTA rises into later.
    private func hideSlider() {
        sliderGroup.isUserInteractionEnabled = false
        UIView.animate(withDuration: AnimationDefaults.fastDuration, delay: 0, options: [.curveEaseIn]) {
            self.sliderGroup.alpha = 0
            self.sliderGroup.transform = CGAffineTransform(translationX: 0, y: 16)
        }
    }
}

// MARK: - Ready

final class NaturalReadyStepViewController: TutorReadyStepViewController {

    private let natural: NaturalOnboardingSession

    init(session: NaturalOnboardingSession) {
        natural = session
        super.init(session: session)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var readySubtitle: String { "Your first scene is queued up." }
    override var readyBadge: String { "聞いてみよう！" }
    override var readyBadgeEnglish: String { "Let's have a listen!" }
    override var readyCapsules: [String] {
        [
            "📖  \(natural.track) · \(natural.level.title)",
            "🎧  \(natural.minutesPerDay) min a day",
        ]
    }
    override var readyFarewell: TutorLine { TutorLine("また聞きに来てね！", "Come back and listen again soon!") }
    override var readyCTA: String { "Start listening" }
}
