//
//  GrammarPrecursorChoiceStepViewController.swift
//  shizen
//
//  Fill-in-the-blank drill: pick the verb precursor that completes the grammar pattern.
//

import InteractionKit
import UIKit

final class GrammarPrecursorChoiceStepViewController: LessonStepViewController {

    var onStepResult: ((Bool) -> Void)?

    private let drill: GrammarDrill
    private let blankedSentence: String
    private let scrubbableSentenceView = ScrubbableSentenceView(engine: JapaneseScrubSentenceEngine.shared)
    private let englishLabel = UILabel()
    private let choicesStack = UIStackView()
    private var choiceButtons: [KanaChoiceButton] = []
    private var checkState: LessonMultipleChoiceCheckState!
    private var prefix = ""
    private var suffix = ""
    private var prefixTokens: [JapaneseToken] = []
    private var suffixTokens: [JapaneseToken] = []
    private var exerciseTokensReady = false
    private var tokenizeTask: Task<Void, Never>?

    private let promptFont = GrammarJapaneseTypography.drillPromptFont

    init(drill: GrammarDrill) {
        self.drill = drill
        self.blankedSentence = Self.makeBlankedSentence(from: drill)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        prepareExerciseTokens()
        configureCTA(.check(), target: self, action: #selector(checkTapped))
        progressiveContainerCoordinator?.setLivesVisible(true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        tokenizeTask?.cancel()
        scrubbableSentenceView.dismissCalloutOnly(animated: false)
    }

    private static func makeBlankedSentence(from drill: GrammarDrill) -> String {
        guard
            let sentence = drill.exampleJapanese,
            let blanked = drill.targetSubstring,
            !sentence.isEmpty,
            !blanked.isEmpty,
            let range = sentence.range(of: blanked)
        else { return drill.prompt ?? "" }
        return sentence.replacingCharacters(in: range, with: "___")
    }

    private func buildUI() {
        configureInstruction(drill.instruction)

        scrubbableSentenceView.showCalloutOnScrub = true
        scrubbableSentenceView.sentenceLineView.textAlignment = .center
        scrubbableSentenceView.onRequestDictionaryDetail = { [weak self] surface, sentence in
            guard let self else { return }
            WordDictionaryDetailSheetPresenter.present(surface: surface, sentence: sentence, from: self)
        }
        updateSentencePreview(selectedChoice: nil)
        scrubbableSentenceView.bindDismissOnTap(view)

        englishLabel.font = .preferredFont(forTextStyle: .subheadline)
        englishLabel.textAlignment = .center
        englishLabel.numberOfLines = 0
        englishLabel.textColor = .secondaryLabel
        englishLabel.text = drill.english
        englishLabel.isHidden = drill.english?.isEmpty != false

        choicesStack.axis = .vertical
        choicesStack.spacing = 8

        let shuffled = drill.choices.shuffled()
        choiceButtons = LessonChoiceGrid.rebuild(
            in: choicesStack,
            choices: shuffled,
            labelStyle: .kana,
            spacing: 8,
            target: self,
            action: #selector(choiceTapped(_:))
        )

        checkState = LessonMultipleChoiceCheckState(
            choices: choiceButtons,
            correctValue: drill.correctChoice,
            successExercise: .kanaDiscovery
        )
        checkState.onResult = { [weak self] success in
            self?.onStepResult?(success)
        }

        let stack = makeLessonContentStack(
            belowInstruction: [scrubbableSentenceView, englishLabel, choicesStack],
            spacing: 20
        )
        stack.setCustomSpacing(14, after: scrubbableSentenceView)
        stack.translatesAutoresizingMaskIntoConstraints = false
        installLessonContent(stack, pinsBelowLessonHeader: true)
        updateCheckButtonState()
    }

    private func prepareExerciseTokens() {
        guard
            let sentence = drill.exampleJapanese,
            let target = drill.targetSubstring,
            let targetRange = sentence.range(of: target)
        else { return }

        prefix = String(sentence[..<targetRange.lowerBound])
        suffix = String(sentence[targetRange.upperBound...])

        tokenizeTask = Task { [weak self] in
            guard let self else { return }
            let baseTokens = await ScrubbableSentenceView.tokenize(sentence: sentence)
            guard !Task.isCancelled else { return }

            let prefixBounds = sentence.startIndex..<targetRange.lowerBound
            let suffixBounds = targetRange.upperBound..<sentence.endIndex
            let clippedPrefix = JapaneseTokenAssembly.clipTokens(baseTokens, within: prefixBounds, in: sentence)
            let clippedSuffix = JapaneseTokenAssembly.clipTokens(baseTokens, within: suffixBounds, in: sentence)

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.prefixTokens = clippedPrefix
                self.suffixTokens = clippedSuffix
                self.exerciseTokensReady = true
                self.updateSentencePreview(selectedChoice: self.checkState.selected?.value)
            }
        }
    }

    private func updateSentencePreview(selectedChoice: String?) {
        let insertText = selectedChoice ?? "___"
        let display = blankedSentence.replacingOccurrences(of: "___", with: insertText)

        guard exerciseTokensReady else {
            scrubbableSentenceView.configureWithTokens(
                sentence: display,
                font: promptFont,
                tokens: [],
                showsFurigana: true,
                accentSubstring: selectedChoice,
                accentColor: .systemBlue
            )
            return
        }

        let insertTokens = JapaneseTokenAssembly.singleToken(
            text: insertText,
            at: insertText.startIndex,
            in: insertText
        )
        let tokens = JapaneseTokenAssembly.assemble(
            display: display,
            parts: [
                (prefix, prefixTokens),
                (insertText, insertTokens),
                (suffix, suffixTokens),
            ]
        )
        scrubbableSentenceView.configureWithTokens(
            sentence: display,
            font: promptFont,
            tokens: tokens,
            showsFurigana: true,
            accentSubstring: selectedChoice,
            accentColor: .systemBlue
        )
    }

    @objc private func choiceTapped(_ sender: KanaChoiceButton) {
        checkState.select(sender)
        updateSentencePreview(selectedChoice: sender.value)
        updateCheckButtonState()
    }

    @objc private func checkTapped() {
        checkState.check { [weak self] in
            guard let self else { return }
            self.configureCTA(.continue_(), target: self, action: #selector(self.continueTapped))
            self.updateCheckButtonState()
        }
        updateSentencePreview(selectedChoice: checkState.selected?.value)
    }

    @objc private func continueTapped() {
        advanceToNextStep()
    }

    private func updateCheckButtonState() {
        checkState.updateCheckButton(primaryButton)
    }
}
