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

    private var didPassQuiz = false
    var onSelectionChanged: (() -> Void)?
    /// Fired once when every question has been answered correctly.
    var onQuizPassed: (() -> Void)?

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
        didPassQuiz = false
        questionViews.forEach { $0.removeFromSuperview() }
        questionViews.removeAll()

        for (index, question) in questions.enumerated() {
            let questionView = DialogueQuizQuestionView(
                questionNumber: index + 1,
                question: question,
                choiceHeight: Self.choiceHeight
            )
            questionView.onSelectionChanged = { [weak self, weak questionView] in
                guard let self, let questionView else { return }
                self.handleImmediateAnswer(questionView)
            }
            contentStack.addArrangedSubview(questionView)
            questionViews.append(questionView)
        }
    }

    private func handleImmediateAnswer(_ questionView: DialogueQuizQuestionView) {
        let allCorrect = !questionViews.isEmpty && questionViews.allSatisfy(\.isSelectionCorrect)

        if questionView.isSelectionCorrect {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if allCorrect {
                ExperimentFeedbackSound.playSuccess(
                    for: .kanaSpelling,
                    spellingSyllableCount: questionViews.count
                )
            } else {
                ExperimentFeedbackSound.playSuccess(for: .kanaSpelling)
            }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            ExperimentFeedbackSound.playIncorrect()
        }

        onSelectionChanged?()

        if allCorrect, !didPassQuiz {
            didPassQuiz = true
            onQuizPassed?()
        }
    }
}
