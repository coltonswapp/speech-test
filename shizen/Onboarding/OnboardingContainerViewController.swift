import UIKit

final class OnboardingContainerViewController: UIViewController {

    weak var coordinator: OnboardingCoordinator?

    private let onboardingNavigationController: UINavigationController
    private let backButton = OnboardingChrome.makeCircularIconButton(symbolName: "chevron.left")
    private let containerView = UIView()

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
    }

    func setBackButtonHidden(_ hidden: Bool) {
        backButton.isHidden = hidden
    }

    private func setupUI() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = .clear
        backButton.accessibilityLabel = "Back"
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        view.addSubview(containerView)
        view.addSubview(backButton)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            backButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            backButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
        ])
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
        coordinator?.back()
    }
}
