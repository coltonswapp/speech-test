import UIKit

final class OnboardingCoordinator: NSObject {

    weak var authenticationDelegate: AuthenticationDelegate?

    enum Flow: String {
        case original = "onboarding_config"
        case journey = "onboarding_journey_config"
    }

    private(set) var userInfo = UserOnboardingInfo()
    private let flow: Flow
    private var isPreviewMode = false
    private var currentStepIndex = 0

    init(flow: Flow = .original) {
        self.flow = flow
        super.init()
    }

    private lazy var navigationController = OnboardingNavigationController()
    private lazy var containerViewController: OnboardingContainerViewController = {
        let container = OnboardingContainerViewController(navigationController: navigationController)
        container.coordinator = self
        return container
    }()

    private lazy var steps: [OnboardingViewController] = {
        if let config = OnboardingConfiguration.loadLocal(named: flow.rawValue) {
            return buildStepsFromConfig(config)
        }
        return buildFallbackSteps()
    }()

    func start() -> UIViewController {
        configureInitialStep()
        navigationController.delegate = self
        return containerViewController
    }

    func enablePreviewMode() {
        isPreviewMode = true
    }

    func setPendingProvider(_ provider: AuthProvider?) {
        userInfo.pendingProvider = provider
    }

    func next() {
        rebuildStepsIfNeeded()
        let nextIndex = currentStepIndex + 1
        guard nextIndex < steps.count else {
            finishSetup()
            return
        }
        currentStepIndex = nextIndex
        let viewController = steps[nextIndex]
        configureStep(viewController)
        navigationController.pushViewController(viewController, animated: true)
    }

    func back() {
        if currentStepIndex > 0, navigationController.viewControllers.count > 1 {
            navigationController.popViewController(animated: true)
            return
        }
        containerViewController.navigationController?.popViewController(animated: true)
    }

    func updateSurveyResponses(_ responses: [String: [String]]) {
        for (questionId, answers) in responses {
            userInfo.surveyResponses[questionId] = answers
        }
    }

    func updateSliderLevel(_ value: String) {
        userInfo.sliderLevel = value
    }

    func updateDailyGoal(_ value: String) {
        userInfo.dailyGoal = value
    }

    func journeySummaryLine() -> String? {
        let why = userInfo.surveyResponses["why_learning"]?.joined(separator: ", ")
        let parts = [
            why,
            Self.displayAnswer(userInfo.sliderLevel),
            userInfo.listeningQuizAnswer.first,
            Self.displayAnswer(userInfo.dailyGoal),
        ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private static func displayAnswer(_ value: String?) -> String? {
        switch value {
        case "brand_new": return "Brand New"
        case "beginner": return "Beginner"
        case "intermediate": return "Intermediate"
        case "advanced": return "Advanced"
        case "1_minute": return "1 minute a day"
        case "3_minutes": return "3 minutes a day"
        case "10_minutes": return "10 minutes a day"
        case "20_minutes": return "20 minutes a day"
        default: return value
        }
    }

    func updateListeningQuizAnswer(_ answers: [String]) {
        userInfo.listeningQuizAnswer = answers
    }

    /// Hook for later branching (role-like answers that mutate the remaining step list).
    func rebuildStepsIfNeeded() {}

    func finishSetup() {
        if isPreviewMode {
            authenticationDelegate?.signUpComplete()
            return
        }

        OnboardingStore.save(userInfo)
        guard AuthService.shared.hasSignedInUserId else {
            requestSignInThenFinish()
            return
        }
        completeSignedInOnboarding()
    }

    func authenticate(provider: AuthProvider, from viewController: UIViewController) async throws {
        if isPreviewMode {
            userInfo.pendingProvider = provider
            return
        }
        try await AuthService.shared.signIn(with: provider, presenting: viewController)
        userInfo.pendingProvider = provider
    }

    private func completeSignedInOnboarding() {
        guard AuthService.shared.hasSignedInUserId else { return }
        OnboardingStore.save(userInfo)
        OnboardingStore.markCompletedForCurrentUser()
        Task { await UserProfileStore.shared.flushSavedBufferIfNeeded() }
        authenticationDelegate?.signUpComplete()
    }

    private func requestSignInThenFinish() {
        guard let presenter = navigationController.topViewController else { return }
        let sheet = UIAlertController(
            title: "Sign in to continue",
            message: "Apple or Google is required before an account can be created.",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Continue with Apple", style: .default) { [weak self] _ in
            self?.signInThenFinish(provider: .apple, from: presenter)
        })
        sheet.addAction(UIAlertAction(title: "Continue with Google", style: .default) { [weak self] _ in
            self?.signInThenFinish(provider: .google, from: presenter)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        presenter.present(sheet, animated: true)
    }

    private func signInThenFinish(provider: AuthProvider, from viewController: UIViewController) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.authenticate(provider: provider, from: viewController)
                self.completeSignedInOnboarding()
            } catch AuthServiceError.canceled {
                return
            } catch {
                let alert = UIAlertController(
                    title: "Sign-in failed",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                viewController.present(alert, animated: true)
            }
        }
    }

    private func configureInitialStep() {
        guard let initialStep = steps.first else { return }
        currentStepIndex = 0
        configureStep(initialStep)
        navigationController.setViewControllers([initialStep], animated: false)
    }

    private func configureStep(_ viewController: OnboardingViewController) {
        viewController.coordinator = self
        let hideBack = viewController is OnboardingFinishViewController
        containerViewController.setBackButtonHidden(hideBack)
        containerViewController.updateProgress(step: currentStepIndex, totalSteps: steps.count)
    }

    private func buildStepsFromConfig(_ config: OnboardingConfiguration) -> [OnboardingViewController] {
        var viewControllers: [OnboardingViewController] = []

        for step in config.flow.steps {
            let viewController: OnboardingViewController?
            switch step.type {
            case .survey:
                if case .survey(let surveyConfig) = step.config {
                    viewController = makeSurveyViewController(from: surveyConfig, stepId: step.id)
                } else {
                    viewController = nil
                }
            case .slider:
                if case .slider(let sliderConfig) = step.config {
                    viewController = OnboardingSliderViewController(config: sliderConfig)
                } else {
                    viewController = nil
                }
            case .listeningQuiz:
                if case .listeningQuiz(let quizConfig) = step.config {
                    viewController = OnboardingListeningQuizViewController(config: quizConfig)
                } else {
                    viewController = nil
                }
            case .demo:
                if case .demo(let demoConfig) = step.config {
                    viewController = OnboardingDemoViewController(config: demoConfig)
                } else {
                    viewController = nil
                }
            case .plan:
                if case .plan(let planConfig) = step.config {
                    viewController = OnboardingPlanViewController(config: planConfig)
                } else {
                    viewController = nil
                }
            case .paywall:
                if case .paywall(let paywallConfig) = step.config {
                    viewController = OnboardingPaywallViewController(config: paywallConfig)
                } else {
                    viewController = nil
                }
            case .auth:
                if case .auth(let authConfig) = step.config {
                    viewController = OnboardingAuthStepViewController(config: authConfig)
                } else {
                    viewController = nil
                }
            case .finish:
                if case .finish(let finishConfig) = step.config {
                    viewController = OnboardingFinishViewController(config: finishConfig)
                } else {
                    viewController = OnboardingFinishViewController(config: BasicStepConfig(
                        title: "You're in",
                        subtitle: "We'll use your answers to personalize practice.",
                        ctaText: nil
                    ))
                }
            }

            if let viewController {
                viewController.onboardingStepId = step.id
                viewControllers.append(viewController)
            }
        }

        return viewControllers
    }

    private func makeSurveyViewController(from config: SurveyStepConfig, stepId: String) -> OnboardingSurveyViewController {
        let question = SurveyQuestion(
            id: config.questionId ?? stepId,
            title: config.title,
            subtitle: config.subtitle,
            options: config.options.map(\.title),
            isMultiSelect: config.isMultiSelect,
            layout: config.layout
        )
        return OnboardingSurveyViewController(question: question, ctaText: config.ctaText)
    }

    private func buildFallbackSteps() -> [OnboardingViewController] {
        let question = SurveyQuestion(
            id: "why_learning",
            title: "Why are you learning Japanese?",
            subtitle: "This will help us create better content for you.",
            options: [
                "Travel ✈️",
                "Friends 🤝",
                "Work 💼",
                "Anime 🎌",
                "Music 🎵",
                "School 📚",
                "Family 👨‍👩‍👧",
                "Culture 🍵",
                "Fun ✨",
                "Move there 🗾",
            ],
            isMultiSelect: true,
            layout: .grid
        )
        return [
            OnboardingSurveyViewController(question: question, ctaText: "Next"),
            OnboardingFinishViewController(config: BasicStepConfig(
                title: "You're in",
                subtitle: "We'll use your answers to personalize practice.",
                ctaText: nil
            )),
        ]
    }
}

extension OnboardingCoordinator: UINavigationControllerDelegate {
    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        if let index = steps.firstIndex(where: { $0 === viewController }) {
            currentStepIndex = index
            containerViewController.updateProgress(step: index, totalSteps: steps.count)
        }
    }
}
