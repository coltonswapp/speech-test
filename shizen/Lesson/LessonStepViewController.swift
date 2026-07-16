//
//  LessonStepViewController.swift
//  shizen
//
//  Lesson-specific layout on top of progressive step chrome: instruction, CTA presets, content pinning.
//

import UIKit

enum LessonStepCTA {
    case check(style: PrimaryButton.Style = .blue)
    case next(style: PrimaryButton.Style = .yellow)
    case continue_(style: PrimaryButton.Style = .blue)
    case custom(title: String, style: PrimaryButton.Style, accessibilityLabel: String?)

    fileprivate var title: String {
        switch self {
        case .check: return "Check"
        case .next: return "Next"
        case .continue_: return "Continue"
        case .custom(let title, _, _): return title
        }
    }

    fileprivate var style: PrimaryButton.Style {
        switch self {
        case .check(let style), .next(let style), .continue_(let style), .custom(_, let style, _):
            return style
        }
    }

    fileprivate var accessibilityLabel: String {
        switch self {
        case .check: return "Check answer"
        case .next: return "Next"
        case .continue_: return "Continue"
        case .custom(_, _, let label): return label ?? title
        }
    }
}

enum LessonStepLayout {
    static let contentTopInset: CGFloat = 8
    /// One-shot top inset for lesson scroll views (clears the lesson header chrome).
    static let lessonScrollTopInset: CGFloat = 120
    static let contentHorizontalInset: CGFloat = 16
    static let instructionHeaderTopInset: CGFloat = 8
    static let instructionHeaderHorizontalInset: CGFloat = 20
}

/// Shared conventions for kana lesson step screens inside a progressive container.
class LessonStepViewController: ProgressiveStepViewController {

    /// Standard top-of-step drill prompt; always use ``configureInstruction`` to set its text.
    let instructionLabel = UILabel()

    private var advanceWorkItem: DispatchWorkItem?
    private var didInstallInstructionHeader = false

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        LessonInstructionLabel.apply(to: instructionLabel)
    }

    // MARK: - Instruction

    func configureInstruction(_ text: String?) {
        LessonInstructionLabel.apply(to: instructionLabel)
        instructionLabel.text = text
    }

    /// Vertical stack with ``instructionLabel`` as the first row. Call ``configureInstruction`` first.
    func makeLessonContentStack(
        belowInstruction views: [UIView],
        spacing: CGFloat = 20,
        afterInstructionSpacing: CGFloat? = nil
    ) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: [instructionLabel] + views)
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = spacing
        if let afterInstructionSpacing {
            stack.setCustomSpacing(afterInstructionSpacing, after: instructionLabel)
        }
        return stack
    }

    /// Pins `instructionLabel` to the top of `contentView` when content is laid out separately (e.g. pair match).
    @discardableResult
    func installInstructionHeader(
        topInset: CGFloat = LessonStepLayout.instructionHeaderTopInset,
        horizontalInset: CGFloat = LessonStepLayout.instructionHeaderHorizontalInset
    ) -> NSLayoutYAxisAnchor {
        guard !didInstallInstructionHeader else { return instructionLabel.bottomAnchor }
        didInstallInstructionHeader = true

        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(instructionLabel)

        NSLayoutConstraint.activate([
            instructionLabel.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: LessonStepLayout.lessonScrollTopInset + topInset
            ),
            instructionLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: horizontalInset
            ),
            instructionLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -horizontalInset
            ),
        ])
        return instructionLabel.bottomAnchor
    }

    // MARK: - CTA

    func configureCTA(_ cta: LessonStepCTA, target: Any?, action: Selector) {
        primaryButton.primaryStyle = cta.style
        primaryButton.setTitle(cta.title, for: .normal)
        primaryButton.removeTarget(nil, action: nil, for: .allEvents)
        primaryButton.addTarget(target, action: action, for: .touchUpInside)
        primaryButton.accessibilityLabel = cta.accessibilityLabel
    }

    // MARK: - Content layout

    /// Pins lesson content below the safe-area top with standard horizontal insets.
    /// Scroll views extend edge-to-edge and receive a one-shot top content inset for the lesson header.
    func installLessonContent(
        _ root: UIView,
        topInset: CGFloat = LessonStepLayout.contentTopInset,
        horizontalInset: CGFloat = LessonStepLayout.contentHorizontalInset,
        pinsBelowLessonHeader: Bool = true
    ) {
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        var constraints: [NSLayoutConstraint] = [
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalInset),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalInset),
        ]

        if let scrollView = root as? UIScrollView {
            constraints.append(root.topAnchor.constraint(equalTo: contentView.topAnchor))
            constraints.append(root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor))
            connectLessonScrollView(scrollView, contentTopInset: LessonStepLayout.lessonScrollTopInset)
        } else {
            let topAnchor = pinsBelowLessonHeader
                ? contentView.topAnchor
                : contentView.safeAreaLayoutGuide.topAnchor
            let resolvedTopInset = pinsBelowLessonHeader
                ? LessonStepLayout.lessonScrollTopInset + topInset
                : topInset
            constraints.append(
                root.topAnchor.constraint(equalTo: topAnchor, constant: resolvedTopInset)
            )
            constraints.append(root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor))
        }

        NSLayoutConstraint.activate(constraints)
    }

    // MARK: - Step advance

    func advanceToNextStep() {
        progressiveContainerCoordinator?.advanceToNextStep(from: self)
    }

    func scheduleAutoAdvance(
        after delay: TimeInterval = KanaSoundMatchMetrics.successAdvancePause
    ) {
        cancelScheduledAdvance()
        let work = DispatchWorkItem { [weak self] in
            self?.advanceToNextStep()
        }
        advanceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func cancelScheduledAdvance() {
        advanceWorkItem?.cancel()
        advanceWorkItem = nil
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancelScheduledAdvance()
    }

    // MARK: - Reference detail embedding

    func configureReferenceDetailChrome() {
        buttonContainer.isHidden = true
    }
}
