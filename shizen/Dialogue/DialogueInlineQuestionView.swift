//
//  DialogueInlineQuestionView.swift
//  shizen
//
//  Mid-listen checkpoint laid out in the transcript like a quiz question.
//  Continue returns to the dialogue and collapses this row; tapping the
//  Quick Check chip expands it again.
//

import UIKit

final class DialogueInlineQuestionView: UIView {

    var onContinue: (() -> Void)?
    var onAnswered: (() -> Void)?
    var onExpandedChanged: (() -> Void)?

    var hasSelection: Bool { questionView.hasSelection }
    var isSelectionCorrect: Bool { questionView.isSelectionCorrect }

    private let questionView: DialogueQuizQuestionView
    private let continueButton = UIButton(type: .system)
    private let headerButton = UIButton(type: .system)
    private let headerContainer = UIView()
    private let stack = UIStackView()
    private var didContinue = false
    private var isExpanded = true

    init(question: DialogueInlineQuestion) {
        questionView = DialogueQuizQuestionView(
            questionNumber: 1,
            question: question.asQuizQuestion,
            choiceHeight: 52,
            showsQuestionNumber: false
        )
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configure()
        applyPresentationImmediately()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Arms Continue for this hold. If the learner already answered, reveal
    /// the button so they can return to the dialogue.
    func prepareForHold() {
        didContinue = false
        isExpanded = true
        applyPresentationImmediately()
        guard hasSelection else { return }
        handleAnswered()
    }

    private func configure() {
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        clipsToBounds = true

        configureHeaderButton()
        configureContinueButton()

        questionView.onSelectionChanged = { [weak self] in
            self?.handleAnswered()
        }

        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 18
        stack.isLayoutMarginsRelativeArrangement = true
        stack.insetsLayoutMarginsFromSafeArea = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(headerContainer)
        stack.addArrangedSubview(questionView)
        stack.addArrangedSubview(continueButton)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func configureHeaderButton() {
        var config = UIButton.Configuration.plain()
        config.title = "Quick Check"
        config.image = UIImage(systemName: "chevron.right")
        config.imagePlacement = .trailing
        config.imagePadding = 8
        config.cornerStyle = .capsule
        config.baseForegroundColor = .tertiaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 8,
            leading: 18,
            bottom: 8,
            trailing: 16
        )
        config.background.backgroundColor = ExperimentPalette.cardSurface
        config.background.strokeColor = ExperimentPalette.cardBorder
        config.background.strokeWidth = 1
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            let preferred = UIFont.preferredFont(forTextStyle: .subheadline)
            outgoing.font = .systemFont(ofSize: preferred.pointSize, weight: .medium)
            return outgoing
        }
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            font: .preferredFont(forTextStyle: .footnote),
            scale: .small
        )
        headerButton.configuration = config
        headerButton.translatesAutoresizingMaskIntoConstraints = false
        headerButton.layer.shadowColor = UIColor.black.cgColor
        headerButton.layer.shadowOpacity = 0.035
        headerButton.layer.shadowRadius = 2
        headerButton.layer.shadowOffset = CGSize(width: 0, height: 1)
        headerButton.addTarget(self, action: #selector(headerTapped), for: .touchUpInside)
        headerButton.accessibilityLabel = "Quick Check"
        headerButton.accessibilityHint = "Shows the question"
        headerButton.setContentHuggingPriority(.required, for: .vertical)
        headerButton.setContentCompressionResistancePriority(.required, for: .vertical)

        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(headerButton)
        NSLayoutConstraint.activate([
            headerButton.topAnchor.constraint(equalTo: headerContainer.topAnchor),
            headerButton.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            headerButton.centerXAnchor.constraint(equalTo: headerContainer.centerXAnchor),
            headerButton.leadingAnchor.constraint(
                greaterThanOrEqualTo: headerContainer.leadingAnchor
            ),
            headerButton.trailingAnchor.constraint(
                lessThanOrEqualTo: headerContainer.trailingAnchor
            ),
        ])
    }

    private func configureContinueButton() {
        var continueConfig = UIButton.Configuration.filled()
        continueConfig.cornerStyle = .capsule
        continueConfig.title = "Continue"
        continueConfig.baseBackgroundColor = .label
        continueConfig.baseForegroundColor = .systemBackground
        continueConfig.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22)
        continueButton.configuration = continueConfig
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
    }

    private func handleAnswered() {
        continueButton.isHidden = false
        continueButton.alpha = 0
        continueButton.transform = CGAffineTransform(translationX: 0, y: 6)
        onExpandedChanged?()
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            self.continueButton.alpha = 1
            self.continueButton.transform = .identity
            self.onExpandedChanged?()
        }
        onAnswered?()
    }

    @objc private func headerTapped() {
        guard didContinue else { return }
        setExpanded(!isExpanded, animated: true)
    }

    @objc private func continueTapped() {
        finish()
    }

    private func finish() {
        guard !didContinue else { return }
        didContinue = true
        setExpanded(false, animated: true) { [weak self] in
            self?.onContinue?()
        }
    }

    private func setExpanded(
        _ expanded: Bool,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        guard expanded != isExpanded else {
            completion?()
            return
        }
        isExpanded = expanded
        guard animated else {
            applyPresentationImmediately()
            completion?()
            return
        }

        if expanded {
            animateExpansion(completion: completion)
        } else {
            animateCollapse(completion: completion)
        }
    }

    private func animateCollapse(completion: (() -> Void)?) {
        // Fade the answer first, then close the stack. Keeping this separate
        // prevents the content from being clipped while it is still visible.
        UIView.animate(
            withDuration: 0.14,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState]
        ) {
            self.questionView.alpha = 0
            self.questionView.transform = CGAffineTransform(
                translationX: 0,
                y: -4
            ).scaledBy(x: 0.985, y: 0.985)
            self.continueButton.alpha = 0
        } completion: { _ in
            self.headerContainer.isHidden = false
            self.headerButton.alpha = 0
            self.headerButton.transform = CGAffineTransform(translationX: 0, y: 3)
            self.questionView.isHidden = true
            self.continueButton.isHidden = true

            UIView.animate(
                withDuration: 0.32,
                delay: 0,
                usingSpringWithDamping: 0.9,
                initialSpringVelocity: 0.2,
                options: [.curveEaseOut, .beginFromCurrentState]
            ) {
                self.applyContainerPresentation()
                self.headerButton.alpha = 1
                self.headerButton.transform = .identity
                self.onExpandedChanged?()
            } completion: { _ in
                self.questionView.transform = .identity
                self.continueButton.alpha = 1
                completion?()
            }
        }
    }

    private func animateExpansion(completion: (() -> Void)?) {
        headerContainer.isHidden = false
        questionView.isHidden = false
        questionView.alpha = 0
        questionView.transform = CGAffineTransform(
            translationX: 0,
            y: -6
        ).scaledBy(x: 0.985, y: 0.985)
        continueButton.isHidden = true

        UIView.animate(
            withDuration: 0.42,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0.1,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            self.applyContainerPresentation()
            self.questionView.alpha = 1
            self.questionView.transform = .identity
            self.onExpandedChanged?()
        } completion: { _ in
            completion?()
        }
    }

    private func applyPresentationImmediately() {
        let reviewing = didContinue

        headerContainer.isHidden = !reviewing
        headerButton.alpha = 1
        headerButton.transform = .identity
        questionView.isHidden = !isExpanded
        questionView.alpha = 1
        questionView.transform = .identity
        questionView.showsQuestionEyebrow = !reviewing
        continueButton.isHidden = !(isExpanded && hasSelection && !reviewing)
        continueButton.alpha = 1
        continueButton.transform = .identity

        applyContainerPresentation()
        onExpandedChanged?()
    }

    private func applyContainerPresentation() {
        let reviewing = didContinue
        let collapsed = reviewing && !isExpanded

        questionView.showsQuestionEyebrow = !reviewing
        headerButton.imageView?.transform = isExpanded
            ? CGAffineTransform(rotationAngle: .pi / 2)
            : .identity
        headerButton.accessibilityHint = isExpanded ? "Hides the question" : "Shows the question"

        stack.alignment = .fill
        stack.spacing = collapsed ? 0 : 18
        stack.layoutMargins = collapsed
            ? UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
            : UIEdgeInsets(top: reviewing ? 10 : 20, left: 16, bottom: 18, right: 16)

        backgroundColor = collapsed ? .clear : ExperimentPalette.pageBackground
        layer.cornerRadius = collapsed ? 0 : 18
    }
}
