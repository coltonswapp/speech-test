//
//  DialogueQuizContentView.swift
//  shizen
//
//  Optional comprehension quiz shown between dialogue and highlights pages.
//

import UIKit

// MARK: - DialogueQuizContentView

final class DialogueQuizContentView: UIView {

    private static let choiceHeight: CGFloat = 45

    private let contentStack = UIStackView()
    private var questionViews: [DialogueQuizQuestionView] = []

    private(set) var hasCheckedAnswers = false
    var onSelectionChanged: (() -> Void)?
    /// Fired once when Check finds every question answered correctly.
    var onQuizPassed: (() -> Void)?

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

    /// Reveals every question's result at once with a quiet color crossfade —
    /// no per-question bounce cascade, which reads as chaos when a scenario
    /// carries several questions. One haptic + one sound summarize the outcome.
    func checkAnswers() {
        guard canCheckAnswers else { return }
        hasCheckedAnswers = true

        var allCorrect = true
        for questionView in questionViews {
            allCorrect = questionView.isSelectionCorrect && allCorrect
            questionView.revealResult()
        }

        if allCorrect {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            ExperimentFeedbackSound.playSuccess(
                for: .kanaSpelling,
                spellingSyllableCount: questionViews.count
            )
            onQuizPassed?()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            ExperimentFeedbackSound.playIncorrect()
        }

        onSelectionChanged?()
    }
}
