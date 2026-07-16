//
//  KanaChoiceButton.swift
//  shizen
//
//  Shared four-choice grid tile with PrimaryButton-style press feedback.
//

import UIKit

enum KanaChoiceButtonLabelStyle {
    case romaji
    case kana
    /// Grammar prohibition-form tiles (hiragana verb endings).
    case grammarForm
    /// Longer Japanese or English glosses in grammar drills.
    case compact
    /// Full-pattern grammar drill options (e.g. 飲んではいけません).
    case grammarDrillChoice
    /// Form-choice list options — matches kana-flow regular weight at readable size.
    case grammarFormChoice
    /// Full Japanese sentences in sentence-choice list rows.
    case grammarSentenceList

    var fontSize: CGFloat {
        switch self {
        case .romaji: 24
        case .kana: 28
        case .grammarForm: 30
        case .compact: 17
        case .grammarDrillChoice: 16
        case .grammarFormChoice: 22
        case .grammarSentenceList: 18
        }
    }

    var fontWeight: UIFont.Weight {
        switch self {
        case .romaji: .medium
        case .kana: .bold
        case .grammarForm: .semibold
        case .compact: .medium
        case .grammarDrillChoice: .medium
        case .grammarFormChoice: .regular
        case .grammarSentenceList: .medium
        }
    }

    var numberOfLines: Int {
        switch self {
        case .romaji, .kana, .grammarForm: 1
        case .compact, .grammarDrillChoice, .grammarFormChoice, .grammarSentenceList: 0
        }
    }
}

final class KanaChoiceButton: UIControl {

    private enum ControlTappedState {
        case touchDown
        case touchCancel
        case touchUp
    }

    private enum BorderState { case normal, selected, success, incorrect }

    static let preferredHeight: CGFloat = 72
    static let listRowMinimumHeight: CGFloat = 56
    private static let listRowVerticalPadding: CGFloat = 14
    private static let listRowHorizontalPadding: CGFloat = 12

    enum Layout {
        case gridTile
        case listRow
    }

    let value: String
    private let labelStyle: KanaChoiceButtonLabelStyle
    private let layout: Layout
    private let customHeight: CGFloat?
    private let choiceLabel = UILabel()
    private var isChosen = false
    private var isCorrectState = false
    private var isIncorrectState = false
    private var isPressAnimating = false
    private var touchDownTimestamp: TimeInterval?
    private let hapticThreshold: TimeInterval = 0.15
    private let pressHaptic = UIImpactFeedbackGenerator(style: .soft)
    private let releaseHaptic = UIImpactFeedbackGenerator(style: .light)

    private static let pressedFill = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.28, alpha: 1)
            : UIColor(red: 0.88, green: 0.88, blue: 0.88, alpha: 1)
    }

    init(
        value: String,
        labelStyle: KanaChoiceButtonLabelStyle,
        layout: Layout = .gridTile,
        preferredHeight: CGFloat? = nil
    ) {
        self.value = value
        self.labelStyle = labelStyle
        self.layout = layout
        self.customHeight = preferredHeight
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        pressHaptic.prepare()
        releaseHaptic.prepare()
    }

    func setChosen(_ chosen: Bool, animated: Bool = true) {
        isChosen = chosen
        guard !isCorrectState else { return }
        applyBorderState(chosen ? .selected : .normal, animated: animated)
    }

    /// Word-bank tile placed into the answer; stays highlighted but no longer tappable.
    func setBankConsumed(_ consumed: Bool) {
        isUserInteractionEnabled = !consumed
        alpha = consumed ? 0.45 : 1
    }

    func applySuccessAppearance() {
        isCorrectState = true
        isIncorrectState = false
        applyBorderState(.success, animated: true)
    }

    func applyIncorrectAppearance() {
        guard !isCorrectState else { return }
        isIncorrectState = true
        isChosen = false
        applyBorderState(.incorrect, animated: true)
    }

    /// Green highlight plus the shared kana success bounce (used in success cascades).
    func animateSuccessBounce(
        successSound: ExperimentFeedbackSound.PreparedSuccessSound? = nil,
        successChimeKeyTime: TimeInterval? = nil,
        animatedAppearance: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        isCorrectState = true
        isIncorrectState = false
        applyBorderState(.success, animated: animatedAppearance)
        animateKanaSoundMatchBounce(
            configuration: .production,
            successSound: successSound,
            successChimeKeyTime: successChimeKeyTime,
            completion: completion
        )
    }

    func resetAppearance() {
        isCorrectState = false
        isIncorrectState = false
        isChosen = false
        alpha = 1
        isUserInteractionEnabled = true
        applyBorderState(.normal, animated: false)
    }

    private func applyBorderState(_ state: BorderState, animated: Bool) {
        let updates = {
            switch state {
            case .normal:
                self.backgroundColor = ExperimentPalette.cardSurface
                self.layer.borderWidth = ExperimentCardStroke.normalWidth
                self.layer.borderColor = ExperimentPalette.cardBorder
                    .resolvedColor(with: self.traitCollection).cgColor
            case .selected:
                self.backgroundColor = ExperimentPalette.highlightFill
                self.layer.borderWidth = ExperimentCardStroke.emphasisWidth
                self.layer.borderColor = ExperimentPalette.highlightBorder
                    .resolvedColor(with: self.traitCollection).cgColor
            case .success:
                self.backgroundColor = ExperimentPalette.successFill
                self.layer.borderWidth = ExperimentCardStroke.emphasisWidth
                self.layer.borderColor = ExperimentPalette.successBorder
                    .resolvedColor(with: self.traitCollection).cgColor
            case .incorrect:
                self.backgroundColor = ExperimentPalette.errorFill
                self.layer.borderWidth = ExperimentCardStroke.emphasisWidth
                self.layer.borderColor = ExperimentPalette.errorBorder
                    .resolvedColor(with: self.traitCollection).cgColor
            }
        }
        guard animated else {
            updates()
            return
        }
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            updates()
        }
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false
        layer.cornerRadius = ExperimentCardStroke.choiceCornerRadius
        layer.cornerCurve = .continuous
        applyBorderState(.normal, animated: false)

        choiceLabel.text = value
        choiceLabel.font = .systemFont(ofSize: labelStyle.fontSize, weight: labelStyle.fontWeight)
        choiceLabel.numberOfLines = layout == .listRow ? 0 : labelStyle.numberOfLines
        choiceLabel.textAlignment = layout == .listRow ? .left : .center
        choiceLabel.textColor = .label
        choiceLabel.adjustsFontForContentSizeCategory = true
        choiceLabel.isUserInteractionEnabled = false
        choiceLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(choiceLabel)

        switch layout {
        case .gridTile:
            let height = customHeight ?? Self.preferredHeight
            NSLayoutConstraint.activate([
                heightAnchor.constraint(equalToConstant: height),
                choiceLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                choiceLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                choiceLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
                choiceLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            ])
        case .listRow:
            let minHeight = customHeight ?? Self.listRowMinimumHeight
            if let customHeight {
                NSLayoutConstraint.activate([
                    heightAnchor.constraint(equalToConstant: customHeight),
                    choiceLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                    choiceLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.listRowHorizontalPadding),
                    choiceLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.listRowHorizontalPadding),
                ])
            } else {
                NSLayoutConstraint.activate([
                    heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight),
                    choiceLabel.topAnchor.constraint(equalTo: topAnchor, constant: Self.listRowVerticalPadding),
                    choiceLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.listRowVerticalPadding),
                    choiceLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.listRowHorizontalPadding),
                    choiceLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.listRowHorizontalPadding),
                ])
            }
        }

        accessibilityLabel = value
        setupPressHandling()
    }

    private func setupPressHandling() {
        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchDragExit), for: .touchDragExit)
        addTarget(self, action: #selector(touchUpOutside), for: .touchUpOutside)
        addTarget(self, action: #selector(touchCancel), for: .touchCancel)
        addTarget(self, action: #selector(touchUpInside), for: .touchUpInside)
    }

    @objc private func touchDown() {
        guard isEnabled, !isCorrectState else { return }
        touchDownTimestamp = Date().timeIntervalSince1970
        ExperimentFeedbackSound.playClick()
        pressHaptic.impactOccurred()
        standardControlAnimation(.touchDown)
    }

    @objc private func touchDragExit() {
        touchDownTimestamp = nil
        standardControlAnimation(.touchCancel)
    }

    @objc private func touchUpOutside() {
        touchDownTimestamp = nil
        standardControlAnimation(.touchCancel)
    }

    @objc private func touchCancel() {
        touchDownTimestamp = nil
        standardControlAnimation(.touchCancel)
    }

    @objc private func touchUpInside() {
        if let timestamp = touchDownTimestamp {
            let elapsed = Date().timeIntervalSince1970 - timestamp
            if elapsed > hapticThreshold {
                releaseHaptic.impactOccurred()
            }
        }
        standardControlAnimation(.touchUp)
        touchDownTimestamp = nil
    }

    private func standardControlAnimation(_ tappedState: ControlTappedState) {
        guard isEnabled, !isCorrectState else {
            resetPressAnimation(animated: true)
            return
        }

        switch tappedState {
        case .touchDown:
            isPressAnimating = true
            let pressedFill = Self.pressedFill.resolvedColor(with: traitCollection)
            UIView.animate(withDuration: 0.075, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
                self.backgroundColor = pressedFill
                self.layer.borderWidth = ExperimentCardStroke.normalWidth
                self.layer.borderColor = ExperimentPalette.cardBorder
                    .resolvedColor(with: self.traitCollection).cgColor
            }
        case .touchCancel, .touchUp:
            resetPressAnimation(animated: true)
        }
    }

    private func resetPressAnimation(animated: Bool) {
        isPressAnimating = false
        let restore = {
            self.transform = .identity
            self.applyBorderState(self.restingBorderState, animated: false)
        }
        guard animated else {
            restore()
            return
        }
        UIView.animate(withDuration: 0.1, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            restore()
        }
    }

    private var restingBorderState: BorderState {
        if isCorrectState { return .success }
        if isIncorrectState { return .incorrect }
        if isChosen { return .selected }
        return .normal
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyBorderState(restingBorderState, animated: false)
    }
}
