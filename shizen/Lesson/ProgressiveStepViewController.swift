//
//  ProgressiveStepViewController.swift
//  shizen
//

import UIKit

protocol ProgressiveContainerCoordinating: AnyObject {
    func advanceToNextStep(from viewController: UIViewController)
    func removeListeningStepsFromLesson(from viewController: UIViewController)
    func setLivesVisible(_ visible: Bool)
    func updateLives(_ remaining: Int)
    func setProgressBarHidden(_ hidden: Bool, animated: Bool)
    func setLessonHeaderHidden(_ hidden: Bool, animated: Bool)
    func presentEncouragementNotchDrop(clipIndex: Int, windowScene: UIWindowScene?)
    func dismissNotchDropIfNeeded()
}

/// Shared chrome for a single progressive step: content area plus a bottom CTA.
class ProgressiveStepViewController: UIViewController {

    static let contentToButtonSpacing: CGFloat = 12
    /// Padding below the primary CTA, measured from the safe-area bottom edge.
    static let buttonBottomInset: CGFloat = 24
    static let cantListenToPrimarySpacing: CGFloat = 12

    weak var progressiveContainerCoordinator: ProgressiveContainerCoordinating?

    /// Host for step-specific content; extends behind the bottom CTA when a scroll view is connected.
    let contentView = UIView()
    let buttonContainer = UIView()
    let primaryButton = PrimaryButton()
    private(set) var cantListenRightNowButton: UIButton?

    private let scrollEdgeInteraction: UIScrollEdgeElementContainerInteraction = {
        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.edge = .bottom
        return interaction
    }()

    private(set) weak var connectedLessonScrollView: UIScrollView?
    private var didInstallProgressiveStepChrome = false
    private var didInstallCantListenButton = false
    private var primaryButtonBottomConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ProgressiveContainerViewController.backgroundColor
        installProgressiveStepChromeIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let scrollView = connectedLessonScrollView {
            applyBottomContentInset(to: scrollView)
        }
    }

    func installProgressiveStepChromeIfNeeded() {
        guard !didInstallProgressiveStepChrome else { return }
        didInstallProgressiveStepChrome = true

        contentView.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.backgroundColor = .clear

        view.addSubview(contentView)
        view.addSubview(buttonContainer)
        buttonContainer.addSubview(primaryButton)
        buttonContainer.addInteraction(scrollEdgeInteraction)

        let buttonInset = PrimaryButton.horizontalInset
        let primaryBottom = primaryButton.bottomAnchor.constraint(
            equalTo: buttonContainer.safeAreaLayoutGuide.bottomAnchor,
            constant: -Self.buttonBottomInset
        )
        primaryButtonBottomConstraint = primaryBottom

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            buttonContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            buttonContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            buttonContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            primaryButton.topAnchor.constraint(
                equalTo: buttonContainer.topAnchor,
                constant: Self.contentToButtonSpacing
            ),
            primaryButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor, constant: buttonInset),
            primaryButton.trailingAnchor.constraint(equalTo: buttonContainer.trailingAnchor, constant: -buttonInset),
            primaryBottom,
            primaryButton.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),
        ])
    }

    /// Pins a step scroll view edge-to-edge and applies lesson scroll insets once.
    func connectLessonScrollView(_ scrollView: UIScrollView, contentTopInset: CGFloat = LessonStepLayout.lessonScrollTopInset) {
        connectedLessonScrollView = scrollView
        scrollEdgeInteraction.scrollView = scrollView
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.topEdgeEffect.style = .soft
        scrollView.topEdgeEffect.isHidden = false
        scrollView.bottomEdgeEffect.style = .soft
        scrollView.bottomEdgeEffect.isHidden = false
        progressiveContainerViewController?.connectLessonScrollView(scrollView)
        scrollView.applyMainTabTopInset(contentTopInset)
        applyBottomContentInset(to: scrollView)
    }

    private var progressiveContainerViewController: ProgressiveContainerViewController? {
        navigationController?.parent as? ProgressiveContainerViewController
    }

    private func applyBottomContentInset(to scrollView: UIScrollView) {
        let inset = max(buttonContainer.bounds.height, 0)
        guard abs(scrollView.contentInset.bottom - inset) >= 0.5 else { return }
        scrollView.contentInset.bottom = inset
        scrollView.verticalScrollIndicatorInsets.bottom = inset
    }

    /// Secondary affordance for audio-only steps; sits below the primary CTA.
    func installCantListenRightNowButton(target: Any?, action: Selector) {
        guard !didInstallCantListenButton else { return }
        didInstallCantListenButton = true
        installProgressiveStepChromeIfNeeded()

        var config = UIButton.Configuration.plain()
        config.title = "Can't listen right now?"
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 14)

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "Can't listen right now. Skip listening steps in this lesson."
        button.addTarget(target, action: action, for: .touchUpInside)

        buttonContainer.addSubview(button)
        cantListenRightNowButton = button

        primaryButtonBottomConstraint?.isActive = false
        primaryButtonBottomConstraint = primaryButton.bottomAnchor.constraint(
            equalTo: button.topAnchor,
            constant: -Self.cantListenToPrimarySpacing
        )

        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: buttonContainer.centerXAnchor),
            button.bottomAnchor.constraint(
                equalTo: buttonContainer.safeAreaLayoutGuide.bottomAnchor,
                constant: -Self.buttonBottomInset
            ),
            primaryButtonBottomConstraint!,
        ])

        if let scrollView = connectedLessonScrollView {
            applyBottomContentInset(to: scrollView)
        }
    }
}
