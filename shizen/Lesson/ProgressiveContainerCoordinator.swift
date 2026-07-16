//
//  ProgressiveContainerCoordinator.swift
//  shizen
//

import UIKit

struct PendingEncouragement {
    let clipIndex: Int
    let comboStreak: Int
    let glyphs: [(kana: String, romaji: String)]
    let praisePhrase: String
}

protocol ProgressiveContainerCoordinatorDelegate: AnyObject {
    func progressiveContainerCoordinatorDidFinish(_ coordinator: ProgressiveContainerCoordinator)
    func progressiveContainerCoordinatorDidCancel(_ coordinator: ProgressiveContainerCoordinator)
}

/// Owns the step stack, progress sync, and presentation root (container + child navigation).
final class ProgressiveContainerCoordinator: NSObject {

    weak var delegate: ProgressiveContainerCoordinatorDelegate?

    private let stepNavigationController: UINavigationController
    private weak var containerViewController: ProgressiveContainerViewController?
    private var stepViewControllers: [UIViewController]
    private(set) var currentStepIndex = 0
    private var listeningStepsRemoved = false
    private let notchDropPresenter = NotchDropPresenter()
    private var pendingEncouragement: PendingEncouragement?

    var stepCount: Int { stepViewControllers.count }

    var isNotchDropPresenting: Bool { notchDropPresenter.isPresenting }

    init(steps: [UIViewController]) {
        let stepNavigationController = UINavigationController()
        stepNavigationController.navigationBar.isHidden = true
        stepNavigationController.view.backgroundColor = ProgressiveContainerViewController.backgroundColor

        self.stepNavigationController = stepNavigationController
        self.stepViewControllers = steps
        super.init()

        wireStepCoordinators()
        stepNavigationController.delegate = self
    }

    convenience init(kanaSpellingWords words: [KanaSpellingWord] = KanaSpellingWordBank.words) {
        let totalSteps = words.count
        let steps = words.enumerated().map { index, word in
            KanaSpellingViewController(word: word, wordIndex: index, totalSteps: totalSteps)
        }
        self.init(steps: steps)
    }

    convenience init(kanaListenSpellingWords words: [KanaSpellingWord] = KanaSpellingWordBank.words) {
        let totalSteps = words.count
        let steps = words.enumerated().map { index, word in
            KanaListenSpellingViewController(word: word, wordIndex: index, totalSteps: totalSteps)
        }
        self.init(steps: steps)
    }

    convenience init(kanaSoundMatchRounds rounds: [KanaSoundMatchRound] = KanaSoundMatchRoundBank.rounds) {
        let totalSteps = rounds.count
        let steps = rounds.enumerated().map { index, round in
            KanaSoundMatchExperimentViewController(round: round, stepIndex: index, totalSteps: totalSteps)
        }
        self.init(steps: steps)
    }

    convenience init(vocabSpeakingPrompts prompts: [VocabSpeakingPrompt] = VocabSpeakingBank.prompts) {
        let totalSteps = prompts.count
        let steps = prompts.enumerated().map { index, prompt in
            VocabSpeakingStepViewController(prompt: prompt, stepIndex: index, totalSteps: totalSteps)
        }
        self.init(steps: steps)
    }

    func start() -> ProgressiveContainerViewController {
        let container = ProgressiveContainerViewController(stepNavigationController: stepNavigationController)
        container.delegate = self
        containerViewController = container

        if let first = stepViewControllers.first {
            stepNavigationController.setViewControllers([first], animated: false)
        }
        syncProgress()

        return container
    }

    private func wireStepCoordinators() {
        for step in stepViewControllers {
            (step as? ProgressiveStepViewController)?.progressiveContainerCoordinator = self
        }
    }

    private func syncProgress() {
        containerViewController?.updateProgress(
            stepIndex: currentStepIndex,
            totalSteps: stepViewControllers.count
        )
    }

    func presentNotchDrop(_ content: NotchDropContent) {
        guard let scene = containerViewController?.view.window?.windowScene else { return }
        notchDropPresenter.present(content, windowScene: scene)
    }

    /// Holds encouragement until the learner leaves the current step so audio cannot overlap the next exercise.
    func queueEncouragement(_ payload: PendingEncouragement) {
        pendingEncouragement = payload
    }

    func presentEncouragementNotchDrop(clipIndex: Int, windowScene: UIWindowScene? = nil) {
        let scene = windowScene ?? containerViewController?.view.window?.windowScene
        guard let scene else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let retryScene = self.containerViewController?.view.window?.windowScene {
                    self.presentEncouragementNotchDrop(clipIndex: clipIndex, windowScene: retryScene)
                }
            }
            return
        }
        notchDropPresenter.present(
            .encouragement(clipIndex: clipIndex),
            windowScene: scene,
            autoDismissWhenFinished: true
        )
    }

    func dismissNotchDropIfNeeded() {
        guard notchDropPresenter.isPresenting else { return }
        notchDropPresenter.dismiss()
    }

    func setLivesVisible(_ visible: Bool) {
        containerViewController?.setLivesVisible(visible)
    }

    func updateLives(_ remaining: Int) {
        containerViewController?.updateLives(remaining: remaining)
    }

    func setProgressBarHidden(_ hidden: Bool, animated: Bool = true) {
        containerViewController?.setLessonHeaderHidden(hidden, animated: animated)
    }

    func setLessonHeaderHidden(_ hidden: Bool, animated: Bool = true) {
        containerViewController?.setLessonHeaderHidden(hidden, animated: animated)
    }

    /// Inserts a step immediately after the current one (e.g. mid-lesson encouragement).
    func insertStepAfterCurrent(_ viewController: UIViewController) {
        let insertIndex = currentStepIndex + 1
        guard insertIndex <= stepViewControllers.count else { return }
        stepViewControllers.insert(viewController, at: insertIndex)
        if let progressive = viewController as? ProgressiveStepViewController {
            progressive.progressiveContainerCoordinator = self
        }
    }

    func pushPostSessionStep(_ viewController: UIViewController) {
        containerViewController?.updateProgress(
            stepIndex: stepViewControllers.count,
            totalSteps: stepViewControllers.count
        )
        containerViewController?.setSkipHidden(true)
        stepNavigationController.pushViewController(viewController, animated: true)
    }

    private func finish() {
        pendingEncouragement = nil
        dismissNotchDropIfNeeded()
        delegate?.progressiveContainerCoordinatorDidFinish(self)
    }

    private func cancel() {
        pendingEncouragement = nil
        dismissNotchDropIfNeeded()
        delegate?.progressiveContainerCoordinatorDidCancel(self)
    }

    private static func isListeningStep(_ viewController: UIViewController) -> Bool {
        viewController is KanaListenIdentifyStepViewController
            || viewController is KanaListenSpellingViewController
    }

    private func reindexSteps() {
        let total = stepViewControllers.count
        for (index, step) in stepViewControllers.enumerated() {
            if let discovery = step as? KanaDiscoveryStepViewController {
                discovery.applyStepIndex(index, totalSteps: total)
            } else if let listen = step as? KanaListenIdentifyStepViewController {
                listen.applyStepIndex(index, totalSteps: total)
            } else if let match = step as? KanaSoundMatchExperimentViewController {
                match.applyStepIndex(index, totalSteps: total)
            } else if let spelling = step as? KanaSpellingViewController {
                spelling.applyStepIndex(index, totalSteps: total)
            } else if let vocab = step as? KanaVocabAssociationStepViewController {
                vocab.applyStepIndex(index, totalSteps: total)
            } else if let pairMatch = step as? KanaPairMatchStepViewController {
                pairMatch.applyStepIndex(index, totalSteps: total)
            }
        }
    }
}

extension ProgressiveContainerCoordinator: ProgressiveContainerCoordinating {
    func removeListeningStepsFromLesson(from viewController: UIViewController) {
        guard !listeningStepsRemoved else { return }
        guard Self.isListeningStep(viewController),
              let currentIndex = stepViewControllers.firstIndex(where: { $0 === viewController })
        else { return }

        let originalSteps = stepViewControllers
        let filtered = originalSteps.filter { !Self.isListeningStep($0) }
        guard filtered.count < originalSteps.count else { return }

        listeningStepsRemoved = true
        stepViewControllers = filtered
        reindexSteps()

        guard let next = originalSteps[(currentIndex + 1)...].first(where: { !Self.isListeningStep($0) }) else {
            finish()
            return
        }

        var newStack = stepNavigationController.viewControllers.filter { !Self.isListeningStep($0) }
        if newStack.last !== next {
            newStack.append(next)
        }
        stepNavigationController.setViewControllers(newStack, animated: true)
        if let nextIndex = filtered.firstIndex(where: { $0 === next }) {
            currentStepIndex = nextIndex
        }
        syncProgress()
    }

    func advanceToNextStep(from viewController: UIViewController) {
        guard let index = stepViewControllers.firstIndex(where: { $0 === viewController }) else { return }

        let nextIndex = index + 1
        let isAdvancingToEncouragement = pendingEncouragement != nil
        if !isAdvancingToEncouragement {
            dismissNotchDropIfNeeded()
        }

        if let payload = pendingEncouragement {
            pendingEncouragement = nil
            let encouragement = KanaLessonEncouragementStepViewController(
                comboStreak: payload.comboStreak,
                clipIndex: payload.clipIndex,
                glyphs: payload.glyphs,
                praisePhrase: payload.praisePhrase
            )
            insertStepAfterCurrent(encouragement)
            performAdvance(to: nextIndex)
            return
        }

        performAdvance(to: nextIndex)
    }

    private func performAdvance(to nextIndex: Int) {
        guard nextIndex < stepViewControllers.count else {
            finish()
            return
        }

        let next = stepViewControllers[nextIndex]
        stepNavigationController.pushViewController(next, animated: true)
        currentStepIndex = nextIndex
        syncProgress()
    }
}

extension ProgressiveContainerCoordinator: UINavigationControllerDelegate {
    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        guard let index = stepViewControllers.firstIndex(where: { $0 === viewController }) else { return }
        currentStepIndex = index
        syncProgress()
        syncLessonHeaderScrollEdge(for: viewController)
    }

    private func syncLessonHeaderScrollEdge(for viewController: UIViewController) {
        guard let step = viewController as? ProgressiveStepViewController else {
            containerViewController?.connectLessonScrollView(nil)
            return
        }
        containerViewController?.connectLessonScrollView(step.connectedLessonScrollView)
    }
}

extension ProgressiveContainerCoordinator: ProgressiveContainerViewControllerDelegate {
    func progressiveContainerDidTapClose(_ container: ProgressiveContainerViewController) {
        cancel()
    }

    func progressiveContainerDidTapSkip(_ container: ProgressiveContainerViewController) {
        pendingEncouragement = nil
        dismissNotchDropIfNeeded()
        guard currentStepIndex < stepViewControllers.count else { return }
        advanceToNextStep(from: stepViewControllers[currentStepIndex])
    }
}
