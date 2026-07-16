//
//  KanaListenIdentifyStepViewController.swift
//  shizen
//
//  Hear a single kana sound, then tap the matching hiragana from a four-choice grid.
//

import UIKit

private enum KanaListenIdentifyStyle {
    static let gridSpacing: CGFloat = 11
}

final class KanaListenIdentifyStepViewController: LessonStepViewController {

    var onStepResult: ((String, Bool) -> Void)?

    private let round: KanaListenIdentifyRound
    private var stepIndex: Int
    private var totalSteps: Int

    private let pronunciationPlayer = KanaPronunciationPlayer()
    private var didAutoPlay = false
    private let replayControl = LessonAudioReplayButton()
    private let gridStack = UIStackView()
    private var choiceButtons: [KanaChoiceButton] = []
    private var checkState: LessonMultipleChoiceCheckState!

    init(round: KanaListenIdentifyRound, stepIndex: Int = 0, totalSteps: Int = 1) {
        self.round = round
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
        rebuildGrid()
        checkState.updateCheckButton(primaryButton)
        installCantListenRightNowButton(target: self, action: #selector(cantListenRightNowTapped))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAutoPlay else { return }
        didAutoPlay = true
        playTargetSound()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pronunciationPlayer.stop()
    }

    private func buildUI() {
        configureInstruction("What character matches this sound?")
        configureCTA(.check(), target: self, action: #selector(primaryButtonTapped))

        gridStack.axis = .vertical
        gridStack.spacing = KanaListenIdentifyStyle.gridSpacing
        gridStack.alignment = .fill
        gridStack.distribution = .fill

        replayControl.addTarget(self, action: #selector(replayTapped))

        let replayRow = UIStackView(arrangedSubviews: [replayControl])
        replayRow.axis = .vertical
        replayRow.alignment = .center

        let contentStack = makeLessonContentStack(
            belowInstruction: [replayRow, gridStack],
            spacing: 28,
            afterInstructionSpacing: 12
        )
        installLessonContent(contentStack)
    }

    private func rebuildGrid() {
        choiceButtons = LessonChoiceGrid.rebuild(
            in: gridStack,
            choices: round.choices,
            labelStyle: .kana,
            spacing: KanaListenIdentifyStyle.gridSpacing,
            target: self,
            action: #selector(choiceTapped(_:))
        )
        checkState = LessonMultipleChoiceCheckState(
            choices: choiceButtons,
            correctValue: round.correctChoice,
            successExercise: .kanaListenIdentify
        )
        checkState.onResult = { [weak self] success in
            guard let self else { return }
            self.onStepResult?(self.round.targetKana, success)
        }
    }

    private func playTargetSound() {
        pronunciationPlayer.play(kana: round.targetKana)
    }

    @objc private func replayTapped() {
        playTargetSound()
    }

    @objc private func choiceTapped(_ sender: KanaChoiceButton) {
        checkState.select(sender)
        checkState.updateCheckButton(primaryButton)
    }

    @objc private func primaryButtonTapped() {
        checkState.check { [weak self] in
            guard let self else { return }
            self.checkState.updateCheckButton(self.primaryButton)
            self.scheduleAutoAdvance()
        }
        checkState.updateCheckButton(primaryButton)
    }

    @objc private func cantListenRightNowTapped() {
        cancelScheduledAdvance()
        pronunciationPlayer.stop()
        progressiveContainerCoordinator?.removeListeningStepsFromLesson(from: self)
    }
}
