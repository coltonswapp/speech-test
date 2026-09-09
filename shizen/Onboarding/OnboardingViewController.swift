import UIKit

class OnboardingViewController: UIViewController {

    var onboardingStepId: String?
    weak var coordinator: OnboardingCoordinator?

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

            labelStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            labelStack.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: OnboardingChrome.horizontalInset
            ),
            labelStack.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -OnboardingChrome.horizontalInset
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
}
