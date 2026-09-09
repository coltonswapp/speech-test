import UIKit

final class OnboardingCoordinator: NSObject {

    weak var authenticationDelegate: AuthenticationDelegate?

    private(set) var userInfo = UserOnboardingInfo()
    private var isPreviewMode = false
    private var currentStepIndex = 0

    private lazy var navigationController = OnboardingNavigationController()
    private lazy var containerViewController: OnboardingContainerViewController = {
        let container = OnboardingContainerViewController(navigationController: navigationController)
        container.coordinator = self
        return container
    }()

    private lazy var steps: [OnboardingViewController] = {
        if let config = OnboardingConfiguration.loadLocal() {
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

    func updateListeningQuizAnswer(_ answers: [String]) {
        userInfo.listeningQuizAnswer = answers
    }

    /// Hook for later branching (role-like answers that mutate the remaining step list).
    func rebuildStepsIfNeeded() {}

    func finishSetup() {
        performUnlessPreviewMode {
            OnboardingStore.save(userInfo)
            OnboardingStore.hasCompletedOnboarding = true
        }
        authenticationDelegate?.signUpComplete()
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
    }

    private func performUnlessPreviewMode(_ work: () -> Void) {
        guard !isPreviewMode else { return }
        work()
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
            options: ["Travel", "Make Friends", "Business"],
            isMultiSelect: false,
            layout: .list
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
        }
    }
}
