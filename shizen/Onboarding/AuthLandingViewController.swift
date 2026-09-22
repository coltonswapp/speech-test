import NNKit
import SwiftUI
import UIKit

final class AuthLandingViewController: UIViewController {

    enum Entry {
        case original
        case journey
    }

    var isPreviewMode = false
    var entry: Entry = .original

    private var onboardingCoordinator: OnboardingCoordinator?
    private var introHost: UIHostingController<IntroPage>?
    private let closeButton = OnboardingChrome.makeCircularIconButton(symbolName: "xmark")

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black
        embedIntro()
        setupCloseButton()
    }

    func signUpComplete() {
        dismiss(animated: true)
    }

    private func embedIntro() {
        let page = IntroPage(
            onGetStarted: { [weak self] in
                guard let self, self.entry == .journey else { return }
                self.pushOnboarding(provider: nil, flow: .journey)
            },
            onAppleSignIn: { [weak self] in self?.appleTapped() },
            onLogin: { [weak self] in self?.loginTapped() },
            onSignUp: { [weak self] in self?.signUpTapped() },
            revealsAuthOnGetStarted: entry == .original
        )
        let host = UIHostingController(rootView: page)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)

        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        introHost = host
    }

    private func setupCloseButton() {
        closeButton.accessibilityLabel = "Close"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
        ])
        updateCloseButtonVisibility()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.bringSubviewToFront(closeButton)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateCloseButtonVisibility()
    }

    private func updateCloseButtonVisibility() {
        closeButton.isHidden = !(isPreviewMode || presentingViewController != nil)
    }

    @objc private func closeTapped() {
        HapticsHelper.lightHaptic()
        dismiss(animated: true)
    }

    @objc private func appleTapped() {
        beginOnboarding(provider: .apple, toast: "Apple Sign-In isn’t configured yet")
    }

    @objc private func loginTapped() {
        beginOnboarding(provider: .guest, toast: "Log in isn’t configured yet")
    }

    @objc private func signUpTapped() {
        beginOnboarding(provider: .guest, toast: nil)
    }

    private func beginOnboarding(provider: AuthProvider, toast: String?) {
        HapticsHelper.lightHaptic()
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
        pushOnboarding(provider: provider, flow: .original)
    }

    private func pushOnboarding(provider: AuthProvider?, flow: OnboardingCoordinator.Flow) {
        let coordinator = OnboardingCoordinator(flow: flow)
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
            toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
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
