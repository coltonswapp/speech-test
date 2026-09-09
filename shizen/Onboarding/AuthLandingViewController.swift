import UIKit

final class AuthLandingViewController: UIViewController {

    var isPreviewMode = false

    private var onboardingCoordinator: OnboardingCoordinator?

    private let closeButton = OnboardingChrome.makeCircularIconButton(symbolName: "xmark")
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let appleButton = UIButton(type: .system)
    private let googleButton = UIButton(type: .system)
    private let continueButton = PrimaryButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.pageBackground
        setupUI()
    }

    func signUpComplete() {
        dismiss(animated: true)
    }

    private func setupUI() {
        closeButton.accessibilityLabel = "Close"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        titleLabel.text = "Welcome to Shizen"
        titleLabel.font = OnboardingChrome.titleFont
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.text = "Sign in to save progress — or continue and set up your listening profile."
        subtitleLabel.font = OnboardingChrome.subtitleFont
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        configureProviderButton(
            appleButton,
            title: "Sign in with Apple",
            symbolName: "apple.logo",
            background: .label,
            foreground: .systemBackground
        )
        appleButton.addTarget(self, action: #selector(appleTapped), for: .touchUpInside)

        configureProviderButton(
            googleButton,
            title: "Continue with Google",
            symbolName: "g.circle.fill",
            background: ExperimentPalette.cardSurface,
            foreground: .label
        )
        googleButton.layer.borderWidth = ExperimentCardStroke.normalWidth
        googleButton.layer.borderColor = ExperimentPalette.cardBorder.cgColor
        googleButton.addTarget(self, action: #selector(googleTapped), for: .touchUpInside)

        continueButton.primaryStyle = .yellow
        continueButton.setTitle("Continue", for: .normal)
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)

        view.addSubview(closeButton)
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(appleButton)
        view.addSubview(googleButton)
        view.addSubview(continueButton)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),

            titleLabel.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: OnboardingChrome.horizontalInset),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -OnboardingChrome.horizontalInset),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            appleButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PrimaryButton.horizontalInset),
            appleButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PrimaryButton.horizontalInset),
            appleButton.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),

            googleButton.topAnchor.constraint(equalTo: appleButton.bottomAnchor, constant: 12),
            googleButton.leadingAnchor.constraint(equalTo: appleButton.leadingAnchor),
            googleButton.trailingAnchor.constraint(equalTo: appleButton.trailingAnchor),
            googleButton.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),
            googleButton.bottomAnchor.constraint(equalTo: continueButton.topAnchor, constant: -16),

            continueButton.leadingAnchor.constraint(equalTo: appleButton.leadingAnchor),
            continueButton.trailingAnchor.constraint(equalTo: appleButton.trailingAnchor),
            continueButton.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),
            continueButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -12),
        ])
    }

    private func configureProviderButton(
        _ button: UIButton,
        title: String,
        symbolName: String,
        background: UIColor,
        foreground: UIColor
    ) {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .fixed
        config.background.cornerRadius = 14
        config.background.backgroundColor = background
        config.baseForegroundColor = foreground
        config.image = UIImage(systemName: symbolName)
        config.imagePadding = 8
        config.title = title
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var attributes = incoming
            attributes.font = .systemFont(ofSize: 17, weight: .bold)
            attributes.foregroundColor = foreground
            return attributes
        }
        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func appleTapped() {
        beginOnboarding(provider: .apple, toast: "Apple Sign-In isn’t configured yet")
    }

    @objc private func googleTapped() {
        beginOnboarding(provider: .google, toast: "Google Sign-In isn’t configured yet")
    }

    @objc private func continueTapped() {
        beginOnboarding(provider: .guest, toast: nil)
    }

    private func beginOnboarding(provider: AuthProvider, toast: String?) {
        let start: () -> Void = { [weak self] in
            guard let self else { return }
            self.pushOnboarding(provider: provider)
        }
        if let toast {
            showToast(toast, completion: start)
        } else {
            start()
        }
    }

    private func pushOnboarding(provider: AuthProvider) {
        let coordinator = OnboardingCoordinator()
        if isPreviewMode {
            coordinator.enablePreviewMode()
        }
        coordinator.setPendingProvider(provider)
        coordinator.authenticationDelegate = self
        onboardingCoordinator = coordinator
        navigationController?.pushViewController(coordinator.start(), animated: true)
    }

    private func showToast(_ message: String, completion: @escaping () -> Void) {
        let toast = UIView()
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        toast.layer.cornerRadius = 12
        toast.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = message
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        toast.addSubview(label)
        view.addSubview(toast)

        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: continueButton.topAnchor, constant: -20),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),

            label.topAnchor.constraint(equalTo: toast.topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: toast.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: toast.trailingAnchor, constant: -14),
            label.bottomAnchor.constraint(equalTo: toast.bottomAnchor, constant: -10),
        ])

        toast.alpha = 0
        UIView.animate(withDuration: 0.2) {
            toast.alpha = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            UIView.animate(withDuration: 0.2, animations: {
                toast.alpha = 0
            }, completion: { _ in
                toast.removeFromSuperview()
                completion()
            })
        }
    }
}

extension AuthLandingViewController: AuthenticationDelegate {}
