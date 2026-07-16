//
//  GrammarSentenceBuilderStepViewController.swift
//  shizen
//
//  Sentence-builder drill: tap phrase tiles into a spelling row (KanaSpelling-style).
//

import UIKit

final class GrammarSentenceBuilderStepViewController: LessonStepViewController {

    var onStepResult: ((Bool) -> Void)?

    private let drill: GrammarDrill
    private let englishLabel = UILabel()
    private let assemblyView = LessonPhraseSpellingAssemblyView()
    private var didSucceed = false

    private var requiredPieceCount: Int {
        let count = drill.buildComponents.count
        return count > 0 ? count : 1
    }

    init(drill: GrammarDrill) {
        self.drill = drill
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        configureCTA(.check(), target: self, action: #selector(checkTapped))
        progressiveContainerCoordinator?.setLivesVisible(true)
    }

    private func buildUI() {
        configureInstruction(drill.instruction)

        englishLabel.font = .preferredFont(forTextStyle: .subheadline)
        englishLabel.textAlignment = .center
        englishLabel.numberOfLines = 0
        englishLabel.textColor = .secondaryLabel
        englishLabel.text = drill.english
        englishLabel.isHidden = drill.english?.isEmpty != false

        assemblyView.configure(choices: drill.choices, slotCount: requiredPieceCount)
        assemblyView.onSelectionChanged = { [weak self] in
            self?.updateCheckButtonState()
        }

        let stack = makeLessonContentStack(
            belowInstruction: [englishLabel, assemblyView],
            spacing: 24
        )
        stack.setCustomSpacing(28, after: englishLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        installLessonContent(stack, pinsBelowLessonHeader: true)
        updateCheckButtonState()
    }

    private func updateCheckButtonState() {
        primaryButton.isEnabled = didSucceed || assemblyView.isFull
    }

    @objc private func checkTapped() {
        guard !didSucceed else { return }
        guard assemblyView.isFull else { return }

        let built = assemblyView.selectedPhrases
        let correct: Bool
        if !drill.buildComponents.isEmpty {
            correct = built == drill.buildComponents
        } else {
            correct = built.joined() == drill.correctChoice
        }

        if correct {
            didSucceed = true
            onStepResult?(true)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            assemblyView.playSuccess { [weak self] in
                guard let self else { return }
                self.configureCTA(.continue_(), target: self, action: #selector(self.continueTapped))
                self.updateCheckButtonState()
            }
            assemblyView.setInteractionEnabled(false)
        } else {
            onStepResult?(false)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            ExperimentFeedbackSound.playIncorrect()
            assemblyView.playIncorrectShake()
        }
        updateCheckButtonState()
    }

    @objc private func continueTapped() {
        advanceToNextStep()
    }
}
