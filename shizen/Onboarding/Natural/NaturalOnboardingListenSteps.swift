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

// MARK: - Listen

final class NaturalListenStepViewController: NaturalStepViewController {

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
    private let hintLabel = UILabel()
    private let questionLabel = UILabel()
    private var options: [NaturalGistOption] = []
    private var activeLine: Int?
    private var isPlaying = false
    private var hasHeardOnce = false
    private var hasAnswered = false

    override func buildStage() {
        let register = natural.register
        setupOnboarding(title: "Just listen. No transcript.", subtitle: "\(register.emoji) \(register.sceneTitle)")
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
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        let speakers = register.speakers
        lines = register.conversation.map { line in
            let view = NaturalDialogueLineView(
                speaker: speakers[line.speaker].name,
                side: line.speaker == 0 ? .leading : .trailing,
                japanese: natural.text(line.line),
                english: line.line.english
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
            content.setCustomSpacing(28, after: last)
        }

        hintLabel.text = "Don't chase every word. Just get the gist."
        hintLabel.font = .preferredFont(forTextStyle: .subheadline)
        hintLabel.textColor = .secondaryLabel
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.alpha = 0
        content.addArrangedSubview(hintLabel)
        content.setCustomSpacing(10, after: playRow)
        content.setCustomSpacing(28, after: hintLabel)

        let gist = register.gist
        questionLabel.text = gist.question
        questionLabel.font = .systemFont(ofSize: 20, weight: .bold)
        questionLabel.textColor = .label
        questionLabel.isHidden = true
        content.addArrangedSubview(questionLabel)

        options = gist.options.enumerated().map { index, text in
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

            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -12),
            content.leadingAnchor.constraint(equalTo: frame.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: frame.trailingAnchor, constant: -20),
        ])
        scrollUnderHeader(scrollView, scrollView: scrollView)
    }

    override func play() {
        slideIn(lines, stagger: 0.08, initialDelay: 0.15)
        slideIn([playButton, hintLabel], stagger: 0.08, initialDelay: 0.5)
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
        meters.start { [weak self] in
            guard let self, let index = self.activeLine else { return }
            self.lines[index].push(level: self.voice.level)
        }
        playLine(0)
    }

    private func playLine(_ index: Int) {
        let register = natural.register
        guard isPlaying, register.conversation.indices.contains(index) else {
            finishPlayback()
            return
        }
        focus(on: index)
        voice.play(register.lineClip(at: index)) { [weak self] in
            self?.lines[index].rest()
            self?.timeline.after(0.2) { [weak self] in
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
        let revealed: [UIView] = [questionLabel] + options
        revealed.forEach { $0.isHidden = false }
        slideIn(revealed, stagger: 0.07)
        scrollToBottom()
    }

    @objc private func optionTapped(_ option: NaturalGistOption) {
        guard !hasAnswered else { return }
        hasAnswered = true
        let gist = natural.register.gist
        playSelectionHaptic()
        natural.caughtGist = option.tag == gist.answer

        if option.tag == gist.answer {
            option.mark = .right
            celebrate(from: option)
            hintLabel.text = "You caught it, without reading a single word."
        } else {
            option.mark = .wrong
            options[gist.answer].mark = .right
            HapticsHelper.lightHaptic()
            hintLabel.text = "Close! Missing it the first time is normal. That's why we replay."
        }
        options.filter { $0.mark == .idle }.forEach { other in
            UIView.animate(withDuration: AnimationDefaults.fastDuration) { other.alpha = 0.4 }
        }
        hintLabel.prepareForSlideIn(slideDistance: 8)
        hintLabel.animateSlideIn(duration: 0.4)
        advanceProgressBeat(to: 2)
        timeline.after(0.8) { [weak self] in
            self?.revealCTA("Show me the words")
        }
    }

    private func celebrate(from option: UIView) {
        HapticsHelper.successHaptic()
        explodeEmoji(from: option)
        let badge = EncouragementBadgeView(text: "聞き取れた！", fillColor: TutorPalette.sakura, textColor: .white)
        view.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.centerXAnchor.constraint(equalTo: option.centerXAnchor),
            badge.bottomAnchor.constraint(equalTo: option.topAnchor, constant: -8),
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

    private func scrollToBottom(animated: Bool = true) {
        scrollToBottom(of: scrollView, animated: animated)
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

// MARK: - Dissect

/// The words reveal in place, then each spoken chunk splits into the pieces it's squashed from.
final class NaturalDissectStepViewController: NaturalStepViewController {

    override var progressBeatCount: Int { natural.register.chunks.count + 1 }

    private let voice = NaturalVoicePlayer()
    private let meters = NaturalMeterDriver()
    private let scrollView = UIScrollView()
    private let content = UIStackView()
    private var lines: [NaturalDialogueLineView] = []
    private var panel: NaturalDissectPanel?
    private var chunkIndex = 0
    private var playingLine: Int?

    override func buildStage() {
        let register = natural.register
        setupOnboarding(title: "Now take it apart.", subtitle: "Here are the words. Tap a line to hear it again.")
        chunkIndex = 0
        playingLine = nil
        panel = nil

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        stage.addSubview(scrollView)

        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        content.axis = .vertical
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        let speakers = register.speakers
        lines = register.conversation.enumerated().map { index, line in
            let view = NaturalDialogueLineView(
                speaker: speakers[line.speaker].name,
                side: line.speaker == 0 ? .leading : .trailing,
                japanese: natural.text(line.line),
                english: line.line.english
            )
            view.tag = index
            view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(lineTapped(_:))))
            return view
        }
        lines.forEach { content.addArrangedSubview($0) }

        let frame = scrollView.frameLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: stage.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: stage.bottomAnchor),

            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -12),
            content.leadingAnchor.constraint(equalTo: frame.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: frame.trailingAnchor, constant: -20),
        ])
        scrollUnderHeader(scrollView, scrollView: scrollView)
    }

    override func play() {
        revealLine(0)
    }

    override func resetStage() {
        stopPlayback()
        super.resetStage()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPlayback()
    }

    override func ctaTapped() {
        guard chunkIndex + 1 < natural.register.chunks.count else {
            super.ctaTapped()
            return
        }
        hideCTA(animated: true)
        chunkIndex += 1
        startChunk()
    }

    /// Flips each meter bubble to its words, one after another, like Dialogue's reveal mode.
    private func revealLine(_ index: Int) {
        guard lines.indices.contains(index) else {
            timeline.after(0.6) { [weak self] in self?.startChunk() }
            return
        }
        timeline.after(index == 0 ? 0.5 : 0.4) { [weak self] in
            guard let self else { return }
            self.lines[index].reveal(showsEnglish: self.natural.level.showsEnglish, animated: true)
            HapticsHelper.superLightHaptic()
            self.revealLine(index + 1)
        }
    }

    private func startChunk() {
        let register = natural.register
        let chunk = register.chunks[chunkIndex]
        for (offset, line) in lines.enumerated() {
            line.setFocused(offset == chunk.line, animated: true)
        }

        let incoming = NaturalDissectPanel(
            chunk: chunk,
            spokenText: natural.text(chunk.spoken),
            step: "\(chunkIndex + 1) of \(register.chunks.count)"
        )
        incoming.onToggle = { [weak self] apart in self?.panelToggled(apart: apart) }
        incoming.textbookRow.addTarget(self, action: #selector(textbookTapped), for: .touchUpInside)

        if let outgoing = panel {
            UIView.animate(withDuration: AnimationDefaults.fastDuration, animations: {
                outgoing.alpha = 0
            }, completion: { _ in
                outgoing.removeFromSuperview()
            })
        }
        panel = incoming
        content.addArrangedSubview(incoming)
        content.setCustomSpacing(24, after: lines.last ?? incoming)
        slideIn([incoming])
        timeline.after(0.1) { [weak self] in self?.scrollToBottom() }

        // Hear it whole, watch it split while the full textbook form plays slowly, then read why.
        timeline.after(0.7) { [weak self] in
            guard let self else { return }
            self.playSpoken {
                self.timeline.after(0.35) {
                    incoming.setApart(true, animated: true)
                    self.playTextbook(slow: true) {
                        incoming.showTextbook()
                        self.scrollToBottom()
                        self.stream(chunk.note, into: incoming.noteLabel, onTick: { [weak self] in
                            self?.scrollToBottom(animated: false)
                        }) { [weak self] in
                            self?.chunkFinished()
                        }
                    }
                }
            }
        }
    }

    private func chunkFinished() {
        advanceProgressBeat(to: chunkIndex + 1)
        let isLast = chunkIndex + 1 >= natural.register.chunks.count
        if isLast {
            lines.forEach { $0.setFocused(true, animated: true) }
        }
        revealCTA(isLast ? "Next" : "Next piece")
    }

    private func panelToggled(apart: Bool) {
        HapticsHelper.lightHaptic()
        if apart {
            playTextbook(slow: true)
        } else {
            playSpoken()
        }
    }

    @objc private func textbookTapped() {
        HapticsHelper.lightHaptic()
        playTextbook(slow: false)
    }

    private func playSpoken(_ completion: (() -> Void)? = nil) {
        stopPlayback()
        panel?.setPlaying(true)
        voice.play(natural.register.spokenClip(forChunk: chunkIndex)) { [weak self] in
            self?.panel?.setPlaying(false)
            completion?()
        }
    }

    private func playTextbook(slow: Bool, _ completion: (() -> Void)? = nil) {
        stopPlayback()
        let rate = slow ? AVSpeechUtteranceDefaultSpeechRate * 0.8 : AVSpeechUtteranceDefaultSpeechRate
        voice.play(natural.register.textbookClip(forChunk: chunkIndex), rate: rate) {
            completion?()
        }
    }

    @objc private func lineTapped(_ gesture: UITapGestureRecognizer) {
        guard let line = gesture.view as? NaturalDialogueLineView, line.isRevealed else { return }
        HapticsHelper.lightHaptic()
        stopPlayback()
        playingLine = line.tag
        meters.start { [weak self] in
            guard let self, let index = self.playingLine else { return }
            self.lines[index].push(level: self.voice.level)
        }
        voice.play(natural.register.lineClip(at: line.tag)) { [weak self] in
            self?.stopPlayback()
        }
    }

    private func stopPlayback() {
        voice.stop()
        meters.stop()
        panel?.setPlaying(false)
        playingLine = nil
    }

    private func scrollToBottom(animated: Bool = true) {
        scrollToBottom(of: scrollView, animated: animated)
    }
}

/// A spoken chunk in a glass bubble that splits into its pieces (and snaps back) on tap.
final class NaturalDissectPanel: UIView {

    /// Called with `true` when the chunk splits apart, `false` when it snaps back together.
    var onToggle: ((Bool) -> Void)?

    let noteLabel = UILabel()
    let textbookRow: NaturalContrastRow
    private let pill: DialogueJapaneseBubbleView
    private let tilesRow = UIStackView()
    private var tiles: [UIView] = []
    private var joiners: [UIView] = []
    private let splitStage = UIView()
    private let hintLabel = UILabel()
    private(set) var isApart = false

    init(chunk: NaturalChunk, spokenText: String, step: String) {
        pill = OnboardingChrome.makeDialogueBubble(
            text: spokenText,
            font: .systemFont(ofSize: 26, weight: .semibold),
            side: nil
        )
        textbookRow = NaturalContrastRow(
            tag: "TEXTBOOK",
            tagColor: .tertiaryLabel,
            line: chunk.textbook,
            english: nil,
            emphasized: false
        )
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
        meaning.text = "“\(chunk.spoken.english)”"
        meaning.font = .preferredFont(forTextStyle: .subheadline)
        meaning.textColor = .secondaryLabel
        meaning.textAlignment = .center

        tilesRow.axis = .horizontal
        tilesRow.alignment = .top
        tilesRow.spacing = 4
        tilesRow.translatesAutoresizingMaskIntoConstraints = false
        for (index, piece) in chunk.pieces.enumerated() {
            if index > 0 {
                let plus = UILabel()
                plus.text = "+"
                plus.font = .systemFont(ofSize: 14, weight: .bold)
                plus.textColor = .tertiaryLabel
                plus.setContentHuggingPriority(.required, for: .horizontal)
                plus.alpha = 0
                let plusWrap = UIView()
                plus.translatesAutoresizingMaskIntoConstraints = false
                plusWrap.addSubview(plus)
                NSLayoutConstraint.activate([
                    plus.centerXAnchor.constraint(equalTo: plusWrap.centerXAnchor),
                    plus.topAnchor.constraint(equalTo: plusWrap.topAnchor, constant: 14),
                    plusWrap.widthAnchor.constraint(equalToConstant: 10),
                    plus.bottomAnchor.constraint(lessThanOrEqualTo: plusWrap.bottomAnchor),
                ])
                joiners.append(plus)
                tilesRow.addArrangedSubview(plusWrap)
            }
            let tile = Self.tile(for: piece)
            tile.alpha = 0
            tiles.append(tile)
            tilesRow.addArrangedSubview(tile)
        }

        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.isUserInteractionEnabled = false
        splitStage.translatesAutoresizingMaskIntoConstraints = false
        splitStage.addSubview(pill)
        splitStage.addSubview(tilesRow)
        splitStage.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(stageTapped)))
        splitStage.isAccessibilityElement = true
        splitStage.accessibilityLabel = spokenText
        splitStage.accessibilityHint = "Splits it into parts"
        splitStage.accessibilityTraits = .button

        hintLabel.text = "Tap to split it apart"
        hintLabel.font = .preferredFont(forTextStyle: .caption1)
        hintLabel.textColor = .tertiaryLabel
        hintLabel.textAlignment = .center

        textbookRow.isHidden = true
        textbookRow.alpha = 0

        noteLabel.font = .preferredFont(forTextStyle: .subheadline)
        noteLabel.textColor = .label
        noteLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [eyebrow, splitStage, meaning, hintLabel, textbookRow, noteLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(14, after: eyebrow)
        stack.setCustomSpacing(4, after: meaning)
        stack.setCustomSpacing(14, after: hintLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            pill.centerXAnchor.constraint(equalTo: splitStage.centerXAnchor),
            pill.centerYAnchor.constraint(equalTo: splitStage.centerYAnchor),
            pill.leadingAnchor.constraint(greaterThanOrEqualTo: splitStage.leadingAnchor),
            pill.topAnchor.constraint(greaterThanOrEqualTo: splitStage.topAnchor),

            tilesRow.centerXAnchor.constraint(equalTo: splitStage.centerXAnchor),
            tilesRow.centerYAnchor.constraint(equalTo: splitStage.centerYAnchor),
            tilesRow.leadingAnchor.constraint(greaterThanOrEqualTo: splitStage.leadingAnchor),
            tilesRow.topAnchor.constraint(greaterThanOrEqualTo: splitStage.topAnchor),
        ])
        applyChrome()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (panel: NaturalDissectPanel, _) in
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
        stack.alignment = .fill
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        stack.backgroundColor = ExperimentPalette.highlightFill
        stack.layer.cornerRadius = 12
        stack.layer.cornerCurve = .continuous
        return stack
    }

    func setPlaying(_ playing: Bool) {
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.pill.setEmphasis(playing ? 1.25 : 1)
        }
    }

    @objc private func stageTapped() {
        setApart(!isApart, animated: true)
        onToggle?(isApart)
    }

    /// Splits the bubble into its pieces (they fly out from the bubble's center), or squeezes them back in.
    func setApart(_ apart: Bool, animated: Bool) {
        guard apart != isApart else { return }
        isApart = apart
        hintLabel.text = apart ? "Tap to squeeze it back together" : "Tap to split it apart"
        splitStage.layoutIfNeeded()

        let center = splitStage.convert(CGPoint(x: pill.bounds.midX, y: pill.bounds.midY), from: pill)
        let collapsed: (UIView) -> CGAffineTransform = { tile in
            let tileCenter = self.splitStage.convert(CGPoint(x: tile.bounds.midX, y: tile.bounds.midY), from: tile)
            return CGAffineTransform(translationX: center.x - tileCenter.x, y: 0).scaledBy(x: 0.55, y: 0.55)
        }

        if apart {
            tiles.forEach { $0.transform = collapsed($0) }
        }
        let apply = {
            self.pill.alpha = apart ? 0 : 1
            self.pill.transform = apart ? CGAffineTransform(scaleX: 1.08, y: 1.08) : .identity
            self.joiners.forEach { $0.alpha = apart ? 1 : 0 }
        }
        guard animated else {
            apply()
            tiles.forEach {
                $0.alpha = apart ? 1 : 0
                $0.transform = .identity
            }
            return
        }
        UIView.animate(withDuration: 0.3, delay: apart ? 0 : 0.18, options: [.beginFromCurrentState], animations: apply)
        for (index, tile) in tiles.enumerated() {
            UIView.animate(
                withDuration: 0.55,
                delay: Double(index) * 0.05,
                usingSpringWithDamping: apart ? 0.72 : 0.95,
                initialSpringVelocity: 0.4,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                tile.alpha = apart ? 1 : 0
                tile.transform = apart ? .identity : collapsed(tile)
            }
        }
    }

    func showTextbook() {
        textbookRow.isHidden = false
        textbookRow.prepareForSlideIn(slideDistance: 8)
        textbookRow.animateSlideIn(duration: 0.45)
    }

    private func applyChrome() {
        backgroundColor = ExperimentPalette.cardSurface
        layer.borderColor = ExperimentPalette.cardBorder.cgColor
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

    override var planChecklist: [String] {
        let register = natural.register
        let gentleStart = natural.level == .brandNew || natural.level == .kana
        let firstListen: String
        switch natural.caughtGist {
        case true?: firstListen = "Noting you caught the gist on your first listen"
        case false?: firstListen = "Adding extra replays where the gist slipped by"
        case nil: firstListen = "Remembering how your first listen went"
        }
        return [
            "Placing you on the \(natural.track) track",
            "Tuning transcripts to “\(natural.level.title)”",
            gentleStart ? "Easing playback a touch slower to start" : "Keeping playback at natural speed",
            "Flagging \(register.focus)",
            "Pinning “\(register.phrases[0].japanese)” and 2 more lines you'll hear first",
            firstListen,
            "Pacing it for \(natural.minutesPerDay) minutes a day",
        ]
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
        "Every lesson is a handful of real scenes. You'll start on \(natural.track), with transcripts "
            + "\(NaturalLevelSamples.planPhrase(for: natural.level)), and Hana will point out \(natural.register.focus) as they come up."
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
            "\(natural.register.emoji)  \(natural.register.title)",
            "📖  \(natural.track) · \(natural.level.title)",
            "🎧  \(natural.minutesPerDay) min a day",
        ]
    }
    override var readyFarewell: TutorLine { natural.register.farewell }
    override var readyCTA: String { "Start listening" }
}
