//
//  DialogueQuizQuestionView.swift
//  shizen
//
//  Single comprehension-quiz question (prompt + choices + wrong-answer explainer).
//

import UIKit

final class DialogueQuizQuestionView: UIView {

    private let question: DialogueQuizQuestion
    private let numberLabel = UILabel()
    private let promptLabel = UILabel()
    private let targetLabel = FuriganaTranscriptLabel()
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
    var onSelectionChanged: (() -> Void)?
    var showsQuestionEyebrow: Bool {
        get { !numberLabel.isHidden }
        set { numberLabel.isHidden = !newValue }
    }

    init(
        questionNumber: Int,
        question: DialogueQuizQuestion,
        choiceHeight: CGFloat,
        showsQuestionNumber: Bool = true
    ) {
        self.question = question
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configureLabels(questionNumber: questionNumber, showsQuestionNumber: showsQuestionNumber)
        configureChoices(choiceHeight: choiceHeight)
        installLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureLabels(questionNumber: Int, showsQuestionNumber: Bool) {
        numberLabel.text = showsQuestionNumber ? "Question \(questionNumber)." : "Quick check"
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

        configureTargetLabel()

        explainerLabel.text = question.wrongAnswerExplanation
        explainerLabel.font = .preferredFont(forTextStyle: .subheadline)
        explainerLabel.textColor = .secondaryLabel
        explainerLabel.textAlignment = .center
        explainerLabel.numberOfLines = 0
        explainerLabel.adjustsFontForContentSizeCategory = true
        explainerLabel.isHidden = true
        explainerLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureTargetLabel() {
        let trimmed = question.target?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        targetLabel.translatesAutoresizingMaskIntoConstraints = false
        targetLabel.clipsToBounds = false
        targetLabel.numberOfLines = 0
        targetLabel.textAlignment = .center
        targetLabel.adjustsFontForContentSizeCategory = true
        targetLabel.verticalTextInsetsAffectAlignmentRect = false
        targetLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        targetLabel.isHidden = trimmed.isEmpty
        guard !trimmed.isEmpty else { return }

        let font = UIFont.preferredFont(forTextStyle: .title2).bold()
        let attributed = JapaneseFuriganaBuilder.scenarioAttributedString(
            for: trimmed,
            font: font,
            textColor: .label
        )
        let centered = NSMutableAttributedString(attributedString: attributed)
        if centered.length > 0 {
            let style = NSMutableParagraphStyle()
            if let existing = centered.attribute(
                .paragraphStyle,
                at: 0,
                effectiveRange: nil
            ) as? NSParagraphStyle {
                style.setParagraphStyle(existing)
            }
            style.alignment = .center
            centered.addAttribute(
                .paragraphStyle,
                value: style,
                range: NSRange(location: 0, length: centered.length)
            )
        }
        JapaneseFuriganaBuilder.applyScrubDisplay(
            to: targetLabel,
            attributed: centered,
            contentInsets: JapaneseFuriganaBuilder.compactDisplayInsets(for: font)
        )
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
            targetLabel,
            choicesStack,
            explainerLabel,
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        stack.setCustomSpacing(12, after: numberLabel)
        if targetLabel.isHidden {
            stack.setCustomSpacing(20, after: promptLabel)
        } else {
            stack.setCustomSpacing(12, after: promptLabel)
            stack.setCustomSpacing(20, after: targetLabel)
        }
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
        revealResult()
        onSelectionChanged?()
    }

    func revealResult() {
        guard !hasRevealedResult, let selectedButton else { return }
        hasRevealedResult = true
        if isSelectionCorrect {
            selectedButton.applySuccessAppearance()
        } else {
            selectedButton.applyIncorrectAppearance()
            if !question.wrongAnswerExplanation.isEmpty {
                explainerLabel.isHidden = false
            }
        }
        lockChoices()
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
