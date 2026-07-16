//
//  DialogueQuizContentView.swift
//  shizen
//
//  Optional comprehension quiz shown between dialogue and highlights pages.
//

import UIKit

// MARK: - Motion (mirrors KanaSpellingViewController success cascade)

private enum DialogueQuizMotion {
    static let successCheckDelay: TimeInterval = 0.22
    static let successCascadeStagger: TimeInterval = 0.09
    static let spellingTwoTileChimeLead: TimeInterval = 0.04

    static func successChimeKeyTime(forSyllableCount count: Int) -> TimeInterval {
        KanaSoundMatchMetrics.successChimeKeyTime
    }

    static func successChimeLead(forSyllableCount count: Int) -> TimeInterval {
        count == 2 ? spellingTwoTileChimeLead : 0
    }
}

// MARK: - DialogueQuizContentView

final class DialogueQuizContentView: UIView {

    private static let choiceHeight: CGFloat = 45

    private let contentStack = UIStackView()
    private var questionViews: [DialogueQuizQuestionView] = []
    private var successCascadeGeneration = 0

    private(set) var hasCheckedAnswers = false
    var onSelectionChanged: (() -> Void)?

    var canCheckAnswers: Bool {
        !hasCheckedAnswers && !questionViews.isEmpty && questionViews.allSatisfy(\.hasSelection)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 36
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(questions: [DialogueQuizQuestion]) {
        successCascadeGeneration += 1
        hasCheckedAnswers = false
        questionViews.forEach { $0.removeFromSuperview() }
        questionViews.removeAll()

        for (index, question) in questions.enumerated() {
            let questionView = DialogueQuizQuestionView(
                questionNumber: index + 1,
                question: question,
                choiceHeight: Self.choiceHeight
            )
            questionView.onSelectionChanged = { [weak self] in
                self?.onSelectionChanged?()
            }
            contentStack.addArrangedSubview(questionView)
            questionViews.append(questionView)
        }
    }

    func checkAnswers() {
        guard canCheckAnswers else { return }
        hasCheckedAnswers = true
        successCascadeGeneration += 1

        var incorrectViews: [DialogueQuizQuestionView] = []
        var hasCorrect = false

        for questionView in questionViews {
            if questionView.cascadeButton != nil {
                hasCorrect = true
            } else if questionView.hasSelection {
                incorrectViews.append(questionView)
            }
        }

        for questionView in incorrectViews {
            questionView.revealIncorrectAnswer()
        }

        if !incorrectViews.isEmpty {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            ExperimentFeedbackSound.playIncorrect()
        }

        onSelectionChanged?()

        guard hasCorrect else { return }

        if incorrectViews.isEmpty {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }

        let generation = successCascadeGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + DialogueQuizMotion.successCheckDelay) { [weak self] in
            guard let self, generation == self.successCascadeGeneration else { return }
            self.playSuccessCascade(questionCount: self.questionViews.count, generation: generation)
        }
    }

    private func playSuccessCascade(questionCount: Int, generation: Int) {
        let entries: [(view: DialogueQuizQuestionView, button: KanaChoiceButton)] = questionViews.compactMap { view in
            guard let button = view.cascadeButton else { return nil }
            return (view, button)
        }
        let count = entries.count
        guard count > 0, generation == successCascadeGeneration else { return }

        let successSound = ExperimentFeedbackSound.prepareSuccess(
            for: .kanaSpelling,
            spellingSyllableCount: questionCount
        )
        let stagger = DialogueQuizMotion.successCascadeStagger
        let chimeKeyTime = DialogueQuizMotion.successChimeKeyTime(forSyllableCount: questionCount)
        let chimeLead = DialogueQuizMotion.successChimeLead(forSyllableCount: questionCount)

        for entry in entries {
            entry.view.prepareForSuccessCascade()
        }

        if chimeLead > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() - chimeLead) { [weak self] in
                guard let self, generation == self.successCascadeGeneration else { return }
                ExperimentFeedbackSound.playPreparedSuccessSound(successSound)
            }
        }

        for (index, entry) in entries.enumerated() {
            let delay = Double(index) * stagger
            let isLast = index == count - 1
            let playsChimeOnBounce = index == 0 && chimeLead == 0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, generation == self.successCascadeGeneration else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                entry.view.markRevealedForSuccessCascade()
                entry.button.animateSuccessBounce(
                    successSound: playsChimeOnBounce ? successSound : nil,
                    successChimeKeyTime: playsChimeOnBounce ? chimeKeyTime : nil,
                    animatedAppearance: false
                ) {
                    guard generation == self.successCascadeGeneration else { return }
                    if isLast {
                        self.onSelectionChanged?()
                    }
                }
            }
        }
    }
}

// MARK: - DialogueQuizQuestionView

private final class DialogueQuizQuestionView: UIView {

    private let question: DialogueQuizQuestion
    private let numberLabel = UILabel()
    private let promptLabel = UILabel()
    private let choicesStack = UIStackView()
    private let explainerLabel = UILabel()
    private var choiceButtons: [KanaChoiceButton] = []
    private var selectedButton: KanaChoiceButton?
    private var hasRevealedResult = false

    var hasSelection: Bool { selectedButton != nil }
    var isSelectionCorrect: Bool {
        guard let selectedButton else { return false }
        return valuesMatch(selectedButton.value, question.correctChoice)
    }
    var cascadeButton: KanaChoiceButton? {
        guard isSelectionCorrect else { return nil }
        return selectedButton
    }
    var onSelectionChanged: (() -> Void)?

    init(questionNumber: Int, question: DialogueQuizQuestion, choiceHeight: CGFloat) {
        self.question = question
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configureLabels(questionNumber: questionNumber)
        configureChoices(choiceHeight: choiceHeight)
        installLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureLabels(questionNumber: Int) {
        numberLabel.text = "Question \(questionNumber)."
        numberLabel.font = .preferredFont(forTextStyle: .footnote)
        numberLabel.textColor = .secondaryLabel
        numberLabel.textAlignment = .center
        numberLabel.translatesAutoresizingMaskIntoConstraints = false

        promptLabel.text = question.prompt
        promptLabel.font = .preferredFont(forTextStyle: .title3).bold()
        promptLabel.textColor = .label
        promptLabel.textAlignment = .center
        promptLabel.numberOfLines = 0
        promptLabel.adjustsFontForContentSizeCategory = true
        promptLabel.translatesAutoresizingMaskIntoConstraints = false

        explainerLabel.text = question.wrongAnswerExplanation
        explainerLabel.font = .preferredFont(forTextStyle: .subheadline)
        explainerLabel.textColor = .secondaryLabel
        explainerLabel.textAlignment = .center
        explainerLabel.numberOfLines = 0
        explainerLabel.adjustsFontForContentSizeCategory = true
        explainerLabel.isHidden = true
        explainerLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureChoices(choiceHeight: CGFloat) {
        choicesStack.axis = .vertical
        choicesStack.spacing = question.layout == .grid ? 8 : 10
        choicesStack.translatesAutoresizingMaskIntoConstraints = false

        switch question.layout {
        case .grid:
            choiceButtons = LessonChoiceGrid.rebuild(
                in: choicesStack,
                choices: question.choices,
                labelStyle: .compact,
                spacing: 8,
                target: self,
                action: #selector(choiceTapped(_:)),
                preferredHeight: choiceHeight
            )
        case .list:
            choiceButtons = LessonChoiceList.rebuild(
                in: choicesStack,
                choices: question.choices,
                labelStyle: .compact,
                spacing: 10,
                target: self,
                action: #selector(choiceTapped(_:)),
                preferredHeight: choiceHeight
            )
        }
    }

    private func installLayout() {
        let stack = UIStackView(arrangedSubviews: [
            numberLabel,
            promptLabel,
            choicesStack,
            explainerLabel,
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        stack.setCustomSpacing(12, after: numberLabel)
        stack.setCustomSpacing(20, after: promptLabel)
        stack.setCustomSpacing(16, after: choicesStack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @objc private func choiceTapped(_ sender: KanaChoiceButton) {
        guard !hasRevealedResult else { return }

        selectedButton = sender
        for button in choiceButtons {
            button.setChosen(button === sender)
        }
        onSelectionChanged?()
    }

    func revealIncorrectAnswer() {
        guard !hasRevealedResult, let selectedButton else { return }
        hasRevealedResult = true
        selectedButton.applyIncorrectAppearance()
        if !question.wrongAnswerExplanation.isEmpty {
            explainerLabel.isHidden = false
        }
        lockChoices()
    }

    func prepareForSuccessCascade() {
        lockChoices()
    }

    func markRevealedForSuccessCascade() {
        hasRevealedResult = true
    }

    private func lockChoices() {
        for button in choiceButtons {
            button.isUserInteractionEnabled = false
        }
    }

    private func valuesMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}

private extension UIFont {
    func bold() -> UIFont {
        let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) ?? fontDescriptor
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
