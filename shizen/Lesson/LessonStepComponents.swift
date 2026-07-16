//
//  LessonStepComponents.swift
//  shizen
//
//  Reusable lesson UI builders: instruction labels, audio replay, choice grids, check flow.
//

import UIKit

enum LessonInstructionLabel {

    static func make(text: String) -> UILabel {
        let label = UILabel()
        apply(to: label)
        label.text = text
        return label
    }

    /// Standard lesson drill prompt: centered subheadline, secondary color, multiline.
    static func apply(to label: UILabel) {
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .subheadline)
    }
}

/// Glass capsule speaker control used in listen/discovery/vocab rows.
final class LessonAudioReplayButton: UIView {

    let button: UIButton

    private let glyphView: UIImageView

    init(
        size: CGFloat = 50,
        glyphPointSize: CGFloat = 22,
        glyphDimension: CGFloat = 26,
        accessibilityLabel: String = "Play pronunciation"
    ) {
        button = UIButton(type: .system)
        glyphView = UIImageView()
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false

        var replayConfig = UIButton.Configuration.glass()
        replayConfig.cornerStyle = .capsule
        button.configuration = replayConfig
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = accessibilityLabel

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: glyphPointSize, weight: .semibold)
        glyphView.image = UIImage(systemName: "speaker.wave.2.fill", withConfiguration: symbolConfig)?
            .withRenderingMode(.alwaysTemplate)
        glyphView.tintColor = .systemYellow
        glyphView.preferredSymbolConfiguration = symbolConfig
        glyphView.contentMode = .scaleAspectFit
        glyphView.isUserInteractionEnabled = false
        glyphView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(button)
        button.addSubview(glyphView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            glyphView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            glyphView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            glyphView.widthAnchor.constraint(equalToConstant: glyphDimension),
            glyphView.heightAnchor.constraint(equalToConstant: glyphDimension),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addTarget(_ target: Any?, action: Selector) {
        button.addTarget(target, action: action, for: .touchUpInside)
    }

    func addAction(_ action: UIAction) {
        button.addAction(action, for: .touchUpInside)
    }
}

enum LessonChoiceGrid {

    @discardableResult
    static func rebuild(
        in gridStack: UIStackView,
        choices: [String],
        labelStyle: KanaChoiceButtonLabelStyle,
        spacing: CGFloat,
        target: Any?,
        action: Selector,
        preferredHeight: CGFloat? = nil
    ) -> [KanaChoiceButton] {
        gridStack.arrangedSubviews.forEach { row in
            gridStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }

        var buttons: [KanaChoiceButton] = []
        let pairs = stride(from: 0, to: choices.count, by: 2).map {
            Array(choices[$0 ..< min($0 + 2, choices.count)])
        }

        for rowChoices in pairs {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = spacing
            row.distribution = .fillEqually

            for value in rowChoices {
                let button = KanaChoiceButton(
                    value: value,
                    labelStyle: labelStyle,
                    preferredHeight: preferredHeight
                )
                button.addTarget(target, action: action, for: .touchUpInside)
                buttons.append(button)
                row.addArrangedSubview(button)
            }
            gridStack.addArrangedSubview(row)
        }
        return buttons
    }
}

/// Full-width stacked choices for longer grammar glosses and sentences.
enum LessonChoiceList {

    @discardableResult
    static func rebuild(
        in listStack: UIStackView,
        choices: [String],
        labelStyle: KanaChoiceButtonLabelStyle,
        spacing: CGFloat,
        target: Any?,
        action: Selector,
        preferredHeight: CGFloat? = nil
    ) -> [KanaChoiceButton] {
        listStack.arrangedSubviews.forEach {
            listStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        var buttons: [KanaChoiceButton] = []
        for value in choices {
            let button = KanaChoiceButton(
                value: value,
                labelStyle: labelStyle,
                layout: .listRow,
                preferredHeight: preferredHeight
            )
            button.addTarget(target, action: action, for: .touchUpInside)
            buttons.append(button)
            listStack.addArrangedSubview(button)
        }
        return buttons
    }
}

/// Shared multiple-choice Check flow for kana lesson drills.
final class LessonMultipleChoiceCheckState {

    var selected: KanaChoiceButton?
    private(set) var hasSucceeded = false

    let choices: [KanaChoiceButton]
    let correctValue: String
    let successExercise: ExperimentFeedbackExercise
    var onResult: ((Bool) -> Void)?
    var additionalCanCheck: () -> Bool = { true }

    init(
        choices: [KanaChoiceButton],
        correctValue: String,
        successExercise: ExperimentFeedbackExercise
    ) {
        self.choices = choices
        self.correctValue = correctValue
        self.successExercise = successExercise
    }

    func canCheck() -> Bool {
        additionalCanCheck() && selected != nil
    }

    func updateCheckButton(_ button: PrimaryButton) {
        button.isEnabled = hasSucceeded || canCheck()
    }

    func select(_ sender: KanaChoiceButton) {
        guard !hasSucceeded else { return }
        selected = sender
        for button in choices {
            button.setChosen(button === sender)
        }
    }

    func check(onSuccessAdvance: @escaping () -> Void) {
        guard !hasSucceeded, let selected else { return }

        if Self.valuesMatch(selected.value, correctValue) {
            hasSucceeded = true
            onResult?(true)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            ExperimentFeedbackSound.playSuccess(for: successExercise)
            selected.applySuccessAppearance()
            for button in choices where button !== selected {
                button.isUserInteractionEnabled = false
            }
            onSuccessAdvance()
        } else {
            onResult?(false)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            ExperimentFeedbackSound.playIncorrect()
            self.selected = nil
            for button in choices {
                button.setChosen(false)
                button.resetAppearance()
            }
        }
    }

    private static func valuesMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            == rhs.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
