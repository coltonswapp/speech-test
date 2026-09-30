import NNKit
import UIKit

final class OnboardingContainerViewController: UIViewController {

    weak var coordinator: OnboardingCoordinator?

    private let onboardingNavigationController: UINavigationController
    private let backButton = OnboardingChrome.makeCircularIconButton(symbolName: "chevron.left")
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let containerView = UIView()
    private var progressLeadingToBack: NSLayoutConstraint!
    private var progressLeadingToEdge: NSLayoutConstraint!

    init(navigationController: UINavigationController) {
        self.onboardingNavigationController = navigationController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.pageBackground
        setupUI()
        embedChildNavigation()
        view.bringSubviewToFront(backButton)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.bringSubviewToFront(backButton)
        applyRoundedProgressAppearance()
    }

    func setBackButtonHidden(_ hidden: Bool) {
        backButton.isHidden = hidden
        guard progressLeadingToBack != nil else { return }
        progressLeadingToBack.isActive = !hidden
        progressLeadingToEdge.isActive = hidden
    }

    func updateProgress(step: Int, totalSteps: Int) {
        guard totalSteps > 0 else {
            progressView.setProgress(0, animated: false)
            return
        }
        let progress = Float(step + 1) / Float(totalSteps)
        progressView.setProgress(min(1, progress), animated: true)
    }

    private func setupUI() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = .clear
        backButton.accessibilityLabel = "Back"
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progressTintColor = .systemYellow
        progressView.trackTintColor = ExperimentPalette.progressBarTrack
        progressView.clipsToBounds = true
        progressView.progress = 0

        view.addSubview(containerView)
        view.addSubview(backButton)
        view.addSubview(progressView)

        let guide = view.safeAreaLayoutGuide
        progressLeadingToBack = progressView.leadingAnchor.constraint(
            equalTo: backButton.trailingAnchor,
            constant: 12
        )
        progressLeadingToEdge = progressView.leadingAnchor.constraint(
            equalTo: guide.leadingAnchor,
            constant: 20
        )
        progressLeadingToEdge.isActive = false

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            backButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            backButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),

            progressLeadingToBack,
            progressView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            progressView.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 6),
        ])

        let backHidden = backButton.isHidden
        progressLeadingToBack.isActive = !backHidden
        progressLeadingToEdge.isActive = backHidden
    }

    private func applyRoundedProgressAppearance() {
        let radius = progressView.bounds.height / 2
        progressView.layer.cornerRadius = radius
        for subview in progressView.subviews {
            subview.clipsToBounds = true
            subview.layer.cornerRadius = radius
        }
    }

    private func embedChildNavigation() {
        addChild(onboardingNavigationController)
        onboardingNavigationController.view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(onboardingNavigationController.view)
        NSLayoutConstraint.activate([
            onboardingNavigationController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            onboardingNavigationController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            onboardingNavigationController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            onboardingNavigationController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
        onboardingNavigationController.didMove(toParent: self)
    }

    @objc private func backTapped() {
        HapticsHelper.lightHaptic()
        coordinator?.back()
    }
}
