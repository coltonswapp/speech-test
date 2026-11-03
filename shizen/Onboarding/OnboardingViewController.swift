import NNKit
import UIKit

class OnboardingViewController: UIViewController {

    /// Stable snake_case id; also the `step_name` on `onboarding_step_viewed`.
    var onboardingStepId: String?
    weak var coordinator: OnboardingCoordinator?

    /// Sets `onboardingStepId` inline in a flow's step list.
    func withStepId(_ id: String) -> Self {
        onboardingStepId = id
        return self
    }

    let headerContainerView = UIView()
    let labelStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    let titleLabel: UILabel = {
        let label = UILabel()
        label.font = OnboardingChrome.titleFont
        label.textColor = .label
        label.numberOfLines = 0
        label.textAlignment = .center
        return label
    }()

    let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = OnboardingChrome.subtitleFont
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.textAlignment = .center
        return label
    }()

    private(set) var ctaButton: PrimaryButton?
    private var buttonBottomConstraint: NSLayoutConstraint?

    /// In-place sub-steps this controller animates through; each one advances the progress bar.
    var progressBeatCount: Int { 1 }
    private(set) var progressBeat = 0

    var hidesOnboardingBackButton: Bool { false }

    func advanceProgressBeat(to beat: Int) {
        progressBeat = min(max(0, beat), progressBeatCount - 1)
        coordinator?.stepBeatDidChange(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.pageBackground
        setupBaseUI()
        setupContent()
    }

    private func setupBaseUI() {
        headerContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerContainerView)
        headerContainerView.addSubview(labelStack)
        labelStack.addArrangedSubview(titleLabel)
        labelStack.addArrangedSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            headerContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerContainerView.bottomAnchor.constraint(equalTo: labelStack.bottomAnchor, constant: 16),

            labelStack.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: OnboardingChrome.titleTopInset
            ),
            labelStack.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: OnboardingChrome.titleHorizontalInset
            ),
            labelStack.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -OnboardingChrome.titleHorizontalInset
            ),
        ])
    }

    func setupOnboarding(title: String, subtitle: String? = nil) {
        titleLabel.text = title
        if let subtitle, !subtitle.isEmpty {
            subtitleLabel.text = subtitle
            subtitleLabel.isHidden = false
        } else {
            subtitleLabel.text = nil
            subtitleLabel.isHidden = true
        }
    }

    /// Override in subclasses to add custom content below the header.
    func setupContent() {}

    func addCTAButton(title: String = "Next") {
        let button = PrimaryButton(type: .system)
        button.primaryStyle = .yellow
        button.setTitle(title, for: .normal)
        button.addTarget(self, action: #selector(ctaTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)

        buttonBottomConstraint = button.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor,
            constant: -12
        )

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PrimaryButton.horizontalInset),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PrimaryButton.horizontalInset),
            button.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),
            buttonBottomConstraint!,
        ])

        ctaButton = button
        view.bringSubviewToFront(button)
    }

    var contentBottomAnchor: NSLayoutYAxisAnchor {
        ctaButton?.topAnchor ?? view.safeAreaLayoutGuide.bottomAnchor
    }

    func setCTAEnabled(_ enabled: Bool) {
        ctaButton?.isEnabled = enabled
    }

    @objc func ctaTapped() {
        coordinator?.next()
    }

    func playSelectionHaptic() {
        HapticsHelper.lightHaptic()
    }

    func explodeEmoji(from view: UIView, preset: ExplosionPreset = .small) {
        OnboardingCelebration.burst(preset, from: view)
    }
}

/// Emoji bursts for wins. Under Reduce Motion they become a single soft scale-and-fade on the
/// element that won; callers keep their haptics either way.
enum OnboardingCelebration {

    static func burst(_ preset: ExplosionPreset, from view: UIView, at point: CGPoint? = nil) {
        guard !UIAccessibility.isReduceMotionEnabled else {
            softPulse(view)
            return
        }
        guard let window = view.window else { return }
        let local = point ?? CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        ExplosionManager.trigger(preset, at: view.convert(local, to: window))
    }

    private static func softPulse(_ view: UIView) {
        let original = view.transform
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .allowUserInteraction], animations: {
            view.transform = original.scaledBy(x: 1.05, y: 1.05)
            view.alpha = 0.85
        }, completion: { _ in
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseIn, .allowUserInteraction]) {
                view.transform = original
                view.alpha = 1
            }
        })
    }
}
