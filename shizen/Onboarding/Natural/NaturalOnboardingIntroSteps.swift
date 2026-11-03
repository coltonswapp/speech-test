//
//  NaturalOnboardingIntroSteps.swift
//  shizen
//
//  Hana says hello and gets a name, then the gap between textbook and spoken
//  Japanese (both sides playable), then the tutor flow's grid and slider with
//  register picks and curated level lines.
//
//  Type rule: chat bubbles carry English only (the hello). Japanese always
//  appears the Dialogue way: a glass bubble or display line, English under it.
//

import NNKit
import UIKit

// MARK: - Hello

final class NaturalIntroStepViewController: NaturalStepViewController {

    override var progressBeatCount: Int { 3 }

    private var chat: TutorChatView?
    private let composer = TutorNameComposer()
    /// Where the floating Hana (listen-first v2) peeks up from: sitting on the screen's bottom edge.
    private let hanaSpot = UIView()

    override func buildStage() {
        setupOnboarding(title: "Welcome to Shizen", subtitle: "Natural Japanese, one conversation at a time.")

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

        if hanaStage != nil {
            // On `view` so it can reach the very bottom edge. Re-added each build so constraints don't pile up.
            hanaSpot.removeFromSuperview()
            hanaSpot.translatesAutoresizingMaskIntoConstraints = false
            hanaSpot.isUserInteractionEnabled = false
            view.addSubview(hanaSpot)
            NSLayoutConstraint.activate([
                hanaSpot.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                hanaSpot.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                hanaSpot.widthAnchor.constraint(equalToConstant: 150),
                hanaSpot.heightAnchor.constraint(equalToConstant: 150),
            ])
        }
    }

    /// The peek runs from `play`; coming back to this screen, Hana is in the chat.
    override func hanaStageDidAppear(firstTime: Bool) {
        if !firstTime {
            hanaStage?.hide()
        }
    }

    override func play() {
        let chatDelay = playHanaPeek()
        timeline.after(chatDelay) { [weak self] in
            self?.chat?.play([.tutorText("Hi, I'm Hana.")]) { [weak self] in
                self?.showSkipHintIfFirstRun()
                self?.chat?.play([
                    .tutorText("I'll help you understand Japanese the way people actually speak it."),
                    .tutorText("What should I call you?"),
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

    /// Hana rises from below the bottom edge until just her eyes show, glances around,
    /// then hops up. Her first line starts typing right after, and she flies up into it.
    /// Returns when the chat should start.
    private func playHanaPeek() -> TimeInterval {
        guard let hanaStage else { return 0.35 }
        view.layoutIfNeeded()
        // Past full peek, so she starts completely out of sight below the edge.
        hanaStage.mascot.set(MascotExpression([.peek: 1.8, .lookY: -0.2]), animated: false)
        hanaStage.appear(at: hanaSpot.convert(hanaSpot.bounds, to: nil))

        // A touch short of full peek so both eyes clear the edge.
        var peeking = MascotPreset.peek.expression
        peeking[.peek] = 0.85
        var lookingLeft = peeking
        lookingLeft[.lookX] = -0.9
        var lookingRight = peeking
        lookingRight[.lookX] = 0.9
        let mascot = hanaStage.mascot
        timeline.after(0.5) { mascot.set(peeking) }
        timeline.after(1.3) { mascot.set(lookingLeft) }
        timeline.after(1.9) { mascot.set(lookingRight) }
        timeline.after(2.5) { mascot.set(MascotPreset.happy.expression) }
        return 3.1
    }

    private func submitName(_ submitted: String) {
        natural.name = submitted
        composer.close(in: view)

        let name = natural.displayName
        advanceProgressBeat(to: 1)
        chat?.play([
            .userText(name),
            .tutorText("Nice to meet you, \(name)."),
        ]) { [weak self] in
            self?.timeline.after(1.0) { [weak self] in
                self?.chat?.clear { [weak self] in
                    self?.playIdea()
                }
            }
        }
    }

    /// Second set, from a clean slate: the setup for Textbooks vs. real life.
    private func playIdea() {
        guard let chat else { return }
        advanceProgressBeat(to: 2)
        timeline.after(0.2) { [weak self] in
            chat.play([
                .tutorText("Here's something most apps won't tell you."),
                .tutorText("The Japanese in textbooks isn't the Japanese people speak. Real speech is squashed, shortened, and fast."),
                .tutorText("That's why real conversations sound like noise at first. Let me show you."),
            ]) { [weak self] in
                self?.revealCTA("Show me")
            }
        }
    }
}

// MARK: - The gap

/// Textbook line, struck through, then what people actually say. Both sides play.
final class NaturalGapStepViewController: NaturalStepViewController {

    private let voice = NaturalVoicePlayer()
    private var cards: [NaturalContrastCard] = []
    private let captionLabel = UILabel()
    private weak var playingRow: NaturalContrastRow?

    override func buildStage() {
        setupOnboarding(title: "Textbooks vs. real life", subtitle: "Same meaning. Different sound.")

        cards = NaturalContrast.all.enumerated().map { index, contrast in
            let card = NaturalContrastCard(contrast: contrast)
            card.textbookRow.tag = index
            card.realRow.tag = index
            card.textbookRow.addTarget(self, action: #selector(textbookTapped(_:)), for: .touchUpInside)
            card.realRow.addTarget(self, action: #selector(realTapped(_:)), for: .touchUpInside)
            card.alpha = 0
            return card
        }

        captionLabel.text = "Textbooks teach the top line. Japan speaks the bottom one. Tap either to hear the difference."
        captionLabel.font = .preferredFont(forTextStyle: .subheadline)
        captionLabel.textColor = .secondaryLabel
        captionLabel.textAlignment = .center
        captionLabel.numberOfLines = 0
        captionLabel.alpha = 0

        let stack = UIStackView(arrangedSubviews: cards + [captionLabel])
        stack.axis = .vertical
        stack.spacing = 12
        if let last = cards.last {
            stack.setCustomSpacing(24, after: last)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        stage.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: stage.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -20),
        ])
    }

    override func play() {
        slideIn(cards, stagger: 0.12, initialDelay: 0.2)
        for (index, card) in cards.enumerated() {
            timeline.after(1.0 + Double(index) * 0.75) {
                card.revealReal()
                HapticsHelper.superLightHaptic()
            }
        }
        let afterCards = 1.0 + Double(cards.count) * 0.75 + 0.3
        timeline.after(afterCards) { [weak self] in
            guard let self else { return }
            self.slideIn([self.captionLabel])
            self.timeline.after(0.6) { [weak self] in
                self?.revealCTA("Makes sense")
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPlayback()
    }

    @objc private func textbookTapped(_ row: NaturalContrastRow) {
        play(NaturalContrast.textbookClip(at: row.tag), on: row)
    }

    @objc private func realTapped(_ row: NaturalContrastRow) {
        play(NaturalContrast.realClip(at: row.tag), on: row)
    }

    private func play(_ clip: NaturalClip, on row: NaturalContrastRow) {
        guard row.isEnabled else { return }
        HapticsHelper.lightHaptic()
        stopPlayback()
        playingRow = row
        row.isPlaying = true
        voice.play(clip) { [weak self, weak row] in
            row?.isPlaying = false
            if self?.playingRow === row {
                self?.playingRow = nil
            }
        }
    }

    private func stopPlayback() {
        voice.stop()
        playingRow?.isPlaying = false
        playingRow = nil
    }
}

/// One side of a contrast: tag, line, optional English, and a speaker glyph that animates while it plays.
final class NaturalContrastRow: UIControl {

    var isPlaying = false {
        didSet {
            guard isPlaying != oldValue else { return }
            applyPlaying()
        }
    }

    let lineLabel = UILabel()
    private let speakerIcon = UIImageView(image: UIImage(systemName: "speaker.wave.2.fill"))

    init(tag tagText: String, tagColor: UIColor, line: String, english: String?, emphasized: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityLabel = [tagText, line, english].compactMap { $0 }.joined(separator: ", ")
        accessibilityHint = "Plays the line"
        accessibilityTraits = .button

        let tagLabel = UILabel()
        tagLabel.text = tagText
        tagLabel.font = .systemFont(ofSize: 11, weight: .heavy)
        tagLabel.textColor = tagColor
        tagLabel.setContentHuggingPriority(.required, for: .horizontal)
        tagLabel.widthAnchor.constraint(equalToConstant: 66).isActive = true

        lineLabel.text = line
        lineLabel.font = emphasized ? .systemFont(ofSize: 22, weight: .bold) : .systemFont(ofSize: 16, weight: .medium)
        lineLabel.textColor = emphasized ? .label : .secondaryLabel
        lineLabel.adjustsFontSizeToFitWidth = true
        lineLabel.minimumScaleFactor = 0.75
        lineLabel.setContentHuggingPriority(.required, for: .horizontal)

        let text = UIStackView(arrangedSubviews: [lineLabel])
        text.axis = .vertical
        text.alignment = .leading
        text.spacing = 2
        if let english {
            let englishLabel = UILabel()
            englishLabel.text = english
            englishLabel.font = .preferredFont(forTextStyle: .footnote)
            englishLabel.textColor = .secondaryLabel
            englishLabel.numberOfLines = 0
            text.addArrangedSubview(englishLabel)
        }

        speakerIcon.tintColor = .tertiaryLabel
        speakerIcon.contentMode = .scaleAspectFit
        speakerIcon.setContentHuggingPriority(.required, for: .horizontal)
        speakerIcon.widthAnchor.constraint(equalToConstant: 22).isActive = true

        let row = UIStackView(arrangedSubviews: [tagLabel, text, UIView(), speakerIcon])
        row.spacing = 8
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.alpha = self.isHighlighted ? 0.6 : 1
            }
        }
    }

    private func applyPlaying() {
        speakerIcon.tintColor = isPlaying ? .systemYellow : .tertiaryLabel
        if isPlaying {
            speakerIcon.addSymbolEffect(.variableColor.iterative.dimInactiveLayers)
        } else {
            speakerIcon.removeAllSymbolEffects()
        }
    }
}

final class NaturalContrastCard: UIView {

    let textbookRow: NaturalContrastRow
    let realRow: NaturalContrastRow
    private let strike = UIView()
    private var strikeCollapsed: NSLayoutConstraint?
    private var strikeFull: NSLayoutConstraint?
    private var isRevealed = false

    init(contrast: NaturalContrast) {
        textbookRow = NaturalContrastRow(
            tag: "TEXTBOOK",
            tagColor: .tertiaryLabel,
            line: contrast.textbook,
            english: nil,
            emphasized: false
        )
        realRow = NaturalContrastRow(
            tag: "REAL",
            tagColor: .systemYellow,
            line: contrast.real,
            english: contrast.english,
            emphasized: true
        )
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.borderWidth = ExperimentCardStroke.normalWidth

        let textbookLabel = textbookRow.lineLabel
        strike.backgroundColor = .tertiaryLabel
        strike.isUserInteractionEnabled = false
        strike.translatesAutoresizingMaskIntoConstraints = false
        textbookLabel.addSubview(strike)
        strikeCollapsed = strike.widthAnchor.constraint(equalToConstant: 0)
        strikeFull = strike.trailingAnchor.constraint(equalTo: textbookLabel.trailingAnchor, constant: 2)

        realRow.alpha = 0
        realRow.isEnabled = false

        let stack = UIStackView(arrangedSubviews: [textbookRow, realRow])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            strike.leadingAnchor.constraint(equalTo: textbookLabel.leadingAnchor, constant: -2),
            strikeCollapsed!,
            strike.centerYAnchor.constraint(equalTo: textbookLabel.centerYAnchor),
            strike.heightAnchor.constraint(equalToConstant: 1.5),
        ])
        applyChrome()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (card: NaturalContrastCard, _) in
            card.applyChrome()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Strikes the textbook line left to right, then drops the spoken version in under it.
    func revealReal() {
        guard !isRevealed else { return }
        isRevealed = true
        layoutIfNeeded()
        strikeCollapsed?.isActive = false
        strikeFull?.isActive = true
        realRow.isEnabled = true
        // Reduce Motion: the strike lands instantly and the real line cross-fades in.
        if UIAccessibility.isReduceMotionEnabled {
            layoutIfNeeded()
        } else {
            UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseOut]) {
                self.layoutIfNeeded()
            }
        }
        realRow.prepareForSlideIn(slideDistance: TutorStepViewController.slideDistance(10))
        realRow.animateSlideIn(duration: 0.5)
    }

    private func applyChrome() {
        backgroundColor = ExperimentPalette.cardSurface
        layer.borderColor = ExperimentPalette.cardBorder.cgColor
    }
}

// MARK: - Register

class NaturalRegisterStepViewController: TutorGoalStepViewController {

    let natural: NaturalOnboardingSession

    /// Example lines shown once a style is picked.
    func phrases(for register: NaturalRegister) -> [TutorLine] {
        register.phrases
    }

    /// A phrase's scripted breakdown, opened by a right swipe. None by default.
    func breakdown(for phrase: TutorLine) -> SentenceScrubScript? {
        nil
    }

    init(session: NaturalOnboardingSession) {
        natural = session
        super.init(session: session)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var choiceHeader: (title: String, subtitle: String) {
        ("Whose Japanese do you want to understand?", "Every lesson mixes settings. This tells Hana what to point out.")
    }

    override var choices: [TutorGoalChoice] {
        NaturalRegister.allCases.map { TutorGoalChoice(emoji: $0.emoji, title: $0.title) }
    }

    override func choose(at index: Int) {
        natural.register = NaturalRegister.allCases[index]
    }

    override var preview: TutorGoalPreview {
        let register = natural.register
        return TutorGoalPreview(
            title: "\(register.title), it is.",
            subtitle: "Tap the card to pick again.",
            messages: [.tutorText("Soon you'll catch lines like these at full speed:")],
            phrases: phrases(for: register),
            hidesEnglishUntilSwipe: true,
            breakdown: { [weak self] in self?.breakdown(for: $0) }
        )
    }
}

// MARK: - Level

final class NaturalLevelStepViewController: TutorLevelStepViewController {

    override var levelHeader: (title: String, subtitle: String) {
        ("How much Japanese do you know?", "Slide it. Every line is written for your level.")
    }

    override var levelCaption: String {
        "What a line looks like for you"
    }

    override func levelSample(for level: TutorLevel) -> TutorLevelSample {
        NaturalLevelSamples.sample(for: level)
    }

    override func levelHint(for level: TutorLevel) -> String {
        NaturalLevelSamples.hint(for: level)
    }
}
