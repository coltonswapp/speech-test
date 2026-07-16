//
//  KanaDiscoveryStepViewController.swift
//  shizen
//
//  Merged discovery intro: glyph reveal, mnemonic, manual audio, then tap-to-select romaji MC.
//

import UIKit

enum KanaDiscoveryPresentationMode {
    case introduction
    case review
}

private enum KanaDiscoveryStyle {
    static let gridSpacing: CGFloat = 4
    /// Pause after tapping play before pronunciation starts (introduction only).
    static let playResponseDelay: TimeInterval = 0.45
    /// Pause after tapping play before choices animate in (introduction only).
    static let choicesRevealDelay: TimeInterval = 1.15
}

private enum KanaDiscoveryIntroCopy {
    /// First line ends with punctuation; second line is always the tap prompt.
    private static let discoveryLeadTemplates: [String] = [
        "A new %@ has been found!",
        "You discovered a new %@!",
        "Look—a new %@ character!",
        "Here's a new %@ to learn!",
        "You've unlocked a new %@!",
        "A fresh %@ just appeared!",
    ]

    static func headline(script: KanaScript) -> String {
        let name = script.displayName
        let lead = discoveryLeadTemplates.randomElement()!
            .replacingOccurrences(of: "%@", with: name)
        return "\(lead)\nTap to hear the sound."
    }
}

final class KanaDiscoveryStepViewController: LessonStepViewController {

    var onDidExpose: ((String) -> Void)?
    var onStepResult: ((String, Bool) -> Void)?

    var recordsExposureOnAppear: Bool {
        presentationMode == .introduction
    }

    private let round: KanaDiscoveryRound
    private let presentationMode: KanaDiscoveryPresentationMode
    private let script: KanaScript
    private var stepIndex: Int
    private var totalSteps: Int

    private let pronunciationPlayer = KanaPronunciationPlayer()
    private var didRecordExposure = false
    private var hasRevealedChoices = false
    private var hasScheduledChoiceReveal = false
    private var playWorkItem: DispatchWorkItem?
    private var revealWorkItem: DispatchWorkItem?

    private let card = KanaCard()
    private let mnemonicLabel = UILabel()
    private let replayControl = LessonAudioReplayButton(size: 52, glyphPointSize: 22, glyphDimension: 26)
    private let choicesSection = UIStackView()
    private let gridStack = UIStackView()
    private var choiceButtons: [KanaChoiceButton] = []
    private var checkState: LessonMultipleChoiceCheckState!

    init(
        round: KanaDiscoveryRound,
        presentationMode: KanaDiscoveryPresentationMode = .introduction,
        script: KanaScript? = nil,
        stepIndex: Int = 0,
        totalSteps: Int = 1
    ) {
        self.round = round
        self.presentationMode = presentationMode
        self.script = script ?? round.glyph.script
        self.stepIndex = stepIndex
        self.totalSteps = totalSteps
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyStepIndex(_ stepIndex: Int, totalSteps: Int) {
        self.stepIndex = stepIndex
        self.totalSteps = totalSteps
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        ExperimentFeedbackSound.prepareClick()
        buildUI()
        rebuildChoices()
        configureInitialChoiceVisibility()
        updateCheckButtonState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if presentationMode == .introduction, !didRecordExposure {
            didRecordExposure = true
            onDidExpose?(round.glyph.kana)
        }
        if presentationMode == .review {
            pronunciationPlayer.play(kana: round.glyph.kana)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        playWorkItem?.cancel()
        revealWorkItem?.cancel()
        pronunciationPlayer.stop()
    }

    private func buildUI() {
        switch presentationMode {
        case .introduction:
            configureInstruction(KanaDiscoveryIntroCopy.headline(script: script))
        case .review:
            configureInstruction("Which sound matches this character?")
        }

        card.setPresentation(.detailHero)
        card.configure(kana: round.glyph.kana, romaji: nil)

        if presentationMode == .introduction {
            let detail = KanaDetailCatalog.item(kana: round.glyph.kana, romaji: round.glyph.romaji)
            mnemonicLabel.text = detail.soundsLike
            mnemonicLabel.font = .preferredFont(forTextStyle: .body)
            mnemonicLabel.textColor = .secondaryLabel
            mnemonicLabel.textAlignment = .center
            mnemonicLabel.numberOfLines = 0
            mnemonicLabel.isHidden = false
        } else {
            mnemonicLabel.isHidden = true
        }

        replayControl.addTarget(self, action: #selector(playTapped))

        gridStack.axis = .vertical
        gridStack.spacing = KanaDiscoveryStyle.gridSpacing
        gridStack.alignment = .fill
        gridStack.distribution = .fill

        choicesSection.axis = .vertical
        choicesSection.spacing = 16
        choicesSection.alignment = .fill
        choicesSection.addArrangedSubview(gridStack)

        configureCTA(.check(), target: self, action: #selector(primaryButtonTapped))

        var heroSubviews: [UIView] = [card]
        if presentationMode == .introduction {
            heroSubviews.append(mnemonicLabel)
        }
        heroSubviews.append(replayControl)

        let heroStack = UIStackView(arrangedSubviews: heroSubviews)
        heroStack.axis = .vertical
        heroStack.spacing = 16
        heroStack.alignment = .center

        let contentStack = makeLessonContentStack(
            belowInstruction: [heroStack, choicesSection],
            afterInstructionSpacing: 24
        )
        contentStack.setCustomSpacing(28, after: heroStack)

        installLessonContent(contentStack, horizontalInset: LessonStepLayout.instructionHeaderHorizontalInset)

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 118),
        ])
    }

    private func rebuildChoices() {
        choiceButtons = LessonChoiceGrid.rebuild(
            in: gridStack,
            choices: round.choices,
            labelStyle: .romaji,
            spacing: KanaDiscoveryStyle.gridSpacing,
            target: self,
            action: #selector(choiceTapped(_:))
        )
        checkState = LessonMultipleChoiceCheckState(
            choices: choiceButtons,
            correctValue: round.correctChoice,
            successExercise: .kanaDiscovery
        )
        checkState.onResult = { [weak self] success in
            guard let self else { return }
            self.onStepResult?(self.round.glyph.kana, success)
        }
        checkState.additionalCanCheck = { [weak self] in
            guard let self else { return false }
            return self.presentationMode == .review || self.hasRevealedChoices
        }
    }

    private func configureInitialChoiceVisibility() {
        guard presentationMode == .introduction else { return }
        choicesSection.isHidden = true
        choicesSection.alpha = 0
        primaryButton.alpha = 0
        primaryButton.isUserInteractionEnabled = false
    }

    private func revealChoicesIfNeeded() {
        guard presentationMode == .introduction, !hasRevealedChoices else { return }
        hasRevealedChoices = true
        configureInstruction("What sound do you hear?")

        choicesSection.isHidden = false
        choicesSection.alpha = 0
        choicesSection.transform = CGAffineTransform(translationX: 0, y: 12)
        primaryButton.alpha = 0
        updateCheckButtonState()

        UIView.animate(
            withDuration: 0.38,
            delay: 0.08,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.35,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.choicesSection.alpha = 1
            self.choicesSection.transform = .identity
            self.primaryButton.alpha = 1
        } completion: { _ in
            self.primaryButton.isUserInteractionEnabled = true
        }
    }

    private func scheduleIntroPlayAndReveal() {
        playWorkItem?.cancel()
        let playWork = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pronunciationPlayer.play(kana: self.round.glyph.kana)
        }
        playWorkItem = playWork
        DispatchQueue.main.asyncAfter(
            deadline: .now() + KanaDiscoveryStyle.playResponseDelay,
            execute: playWork
        )

        revealWorkItem?.cancel()
        let revealWork = DispatchWorkItem { [weak self] in
            self?.revealChoicesIfNeeded()
        }
        revealWorkItem = revealWork
        DispatchQueue.main.asyncAfter(
            deadline: .now() + KanaDiscoveryStyle.choicesRevealDelay,
            execute: revealWork
        )
    }

    @objc private func playTapped() {
        if presentationMode == .introduction, !hasRevealedChoices {
            if !hasScheduledChoiceReveal {
                hasScheduledChoiceReveal = true
                scheduleIntroPlayAndReveal()
            } else {
                pronunciationPlayer.play(kana: round.glyph.kana)
            }
            return
        }

        pronunciationPlayer.play(kana: round.glyph.kana)
    }

    @objc private func choiceTapped(_ sender: KanaChoiceButton) {
        checkState.select(sender)
        updateCheckButtonState()
    }

    @objc private func primaryButtonTapped() {
        checkState.check { [weak self] in
            guard let self else { return }
            self.updateCheckButtonState()
            self.scheduleAutoAdvance()
        }
        updateCheckButtonState()
    }

    private func updateCheckButtonState() {
        checkState.updateCheckButton(primaryButton)
    }
}
