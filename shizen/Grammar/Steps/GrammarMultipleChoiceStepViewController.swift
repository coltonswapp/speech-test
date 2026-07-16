//
//  GrammarMultipleChoiceStepViewController.swift
//  shizen
//

import UIKit
import GrammarContentKit

enum GrammarChoiceLayout {
    case grid
    case list
}

/// Shared multiple-choice drill shell for grammar Form / Meaning / Sentence / Contrast drills.
final class GrammarMultipleChoiceStepViewController: LessonStepViewController {

    var onStepResult: ((Bool) -> Void)?

    private let drill: GrammarDrill
    private let choiceLabelStyle: KanaChoiceButtonLabelStyle
    private let choiceLayout: GrammarChoiceLayout
    private let scrubbableSentenceView = ScrubbableSentenceView()
    private let promptLabel = UILabel()
    private let choicesStack = UIStackView()
    private var choiceButtons: [KanaChoiceButton] = []
    private var checkState: LessonMultipleChoiceCheckState!

    init(
        drill: GrammarDrill,
        choiceLabelStyle: KanaChoiceButtonLabelStyle,
        choiceLayout: GrammarChoiceLayout
    ) {
        self.drill = drill
        self.choiceLabelStyle = choiceLabelStyle
        self.choiceLayout = choiceLayout
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scrubbableSentenceView.dismissCalloutOnly(animated: false)
    }

    private func buildUI() {
        configureInstruction(drill.instruction)

        var promptViews: [UIView] = []

        if let japanese = drill.exampleJapanese, !japanese.isEmpty {
            scrubbableSentenceView.showCalloutOnScrub = true
            scrubbableSentenceView.sentenceLineView.textAlignment = .center
            scrubbableSentenceView.onRequestDictionaryDetail = { [weak self] surface, sentence in
                guard let self else { return }
                WordDictionaryDetailSheetPresenter.present(surface: surface, sentence: sentence, from: self)
            }
            scrubbableSentenceView.configure(
                sentence: japanese,
                font: GrammarJapaneseTypography.drillPromptFont,
                showsFurigana: true
            )
            scrubbableSentenceView.bindDismissOnTap(view)
            promptViews.append(scrubbableSentenceView)
        } else if let prompt = drill.prompt, !prompt.isEmpty {
            if drill.kind == .formChoice {
                promptViews.append(GrammarFormChoicePromptView(
                    prompt: prompt,
                    correctChoice: drill.correctChoice
                ))
            } else {
                configureTextPrompt(promptLabel, text: prompt)
                promptViews.append(promptLabel)
            }
        }

        choicesStack.axis = .vertical
        choicesStack.spacing = choiceLayout == .list ? 10 : 8

        let shuffled = drill.choices.shuffled()
        switch choiceLayout {
        case .grid:
            choiceButtons = LessonChoiceGrid.rebuild(
                in: choicesStack,
                choices: shuffled,
                labelStyle: choiceLabelStyle,
                spacing: 8,
                target: self,
                action: #selector(choiceTapped(_:))
            )
        case .list:
            choiceButtons = LessonChoiceList.rebuild(
                in: choicesStack,
                choices: shuffled,
                labelStyle: choiceLabelStyle,
                spacing: 10,
                target: self,
                action: #selector(choiceTapped(_:))
            )
        }

        checkState = LessonMultipleChoiceCheckState(
            choices: choiceButtons,
            correctValue: drill.correctChoice,
            successExercise: .kanaDiscovery
        )
        checkState.onResult = { [weak self] success in
            self?.onStepResult?(success)
        }

        let stack = makeLessonContentStack(
            belowInstruction: promptViews + [choicesStack],
            spacing: 20
        )
        if let firstPrompt = promptViews.first {
            stack.setCustomSpacing(promptToChoicesSpacing, after: firstPrompt)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        installLessonContent(stack, pinsBelowLessonHeader: true)
        updateCheckButtonState()
    }

    @objc private func choiceTapped(_ sender: KanaChoiceButton) {
        checkState.select(sender)
        updateCheckButtonState()
    }

    @objc private func checkTapped() {
        checkState.check { [weak self] in
            guard let self else { return }
            self.configureCTA(.continue_(), target: self, action: #selector(self.continueTapped))
            self.updateCheckButtonState()
        }
    }

    @objc private func continueTapped() {
        advanceToNextStep()
    }

    private func updateCheckButtonState() {
        checkState.updateCheckButton(primaryButton)
    }

    private var promptToChoicesSpacing: CGFloat {
        switch drill.kind {
        case .sentenceChoice: return 32
        case .formChoice: return 24
        default: return 14
        }
    }

    private func configureTextPrompt(_ label: UILabel, text: String) {
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = text

        switch drill.kind {
        case .sentenceChoice:
            label.font = GrammarJapaneseTypography.drillEnglishPromptFont
            label.textColor = .label
        case .contrastChoice:
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.textColor = .secondaryLabel
        default:
            label.font = .preferredFont(forTextStyle: .title3)
            label.textColor = .label
        }
    }
}
