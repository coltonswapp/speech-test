//
//  GrammarLessonCoordinator.swift
//  shizen
//

import UIKit

protocol GrammarLessonSessionDelegate: AnyObject {
    func grammarLessonSessionDidFinish(point: GrammarPoint, metrics: KanaLessonSessionMetrics)
    func grammarLessonSessionDidFail(point: GrammarPoint, metrics: KanaLessonSessionMetrics)
    func grammarLessonSessionDidCancel(point: GrammarPoint)
}

final class GrammarLessonCoordinator: NSObject {

    weak var delegate: GrammarLessonSessionDelegate?

    private let point: GrammarPoint
    private let masteryStore: GrammarMasteryStore
    private let sessionTracker = KanaLessonSessionTracker()
    private var progressiveCoordinator: ProgressiveContainerCoordinator?
    private var didPresentSummary = false

    init(point: GrammarPoint, masteryStore: GrammarMasteryStore = .shared) {
        self.point = point
        self.masteryStore = masteryStore
        super.init()
    }

    func present(from viewController: UIViewController) {
        let coordinator = makeCoordinator()
        let container = coordinator.start()
        coordinator.setLivesVisible(false)
        coordinator.updateLives(sessionTracker.metrics.livesRemaining)
        container.modalPresentationStyle = .fullScreen
        viewController.present(container, animated: true)
    }

    func makeCoordinator() -> ProgressiveContainerCoordinator {
        let steps = GrammarLessonContentBuilder.lessonSteps(for: point)
        let coordinator = ProgressiveContainerCoordinator(steps: steps)
        coordinator.delegate = self
        wireCallbacks(into: steps)
        progressiveCoordinator = coordinator
        return coordinator
    }

    private func wireCallbacks(into steps: [UIViewController]) {
        for step in steps {
            if let mc = step as? GrammarMultipleChoiceStepViewController {
                mc.onStepResult = { [weak self] correct in
                    self?.handleDrillResult(correct: correct)
                }
            } else if let precursor = step as? GrammarPrecursorChoiceStepViewController {
                precursor.onStepResult = { [weak self] correct in
                    self?.handleDrillResult(correct: correct)
                }
            } else if let builder = step as? GrammarSentenceBuilderStepViewController {
                builder.onStepResult = { [weak self] correct in
                    self?.handleDrillResult(correct: correct)
                }
            } else if let example = step as? GrammarExampleStepViewController {
                example.onStepResult = { _ in }
            }
        }
    }

    private func handleDrillResult(correct: Bool) {
        guard !didPresentSummary else { return }
        let failedOut = sessionTracker.recordAnswer(correct: correct, encouragementEnabled: false)
        progressiveCoordinator?.updateLives(sessionTracker.metrics.livesRemaining)
        if !correct {
            progressiveCoordinator?.presentNotchDrop(.lifeLost(
                remaining: sessionTracker.metrics.livesRemaining
            ))
        }
        if failedOut {
            presentSummary(outcome: .failed)
        }
    }

    private func presentSummary(outcome: GrammarLessonSummaryOutcome) {
        guard !didPresentSummary, let progressiveCoordinator else { return }
        didPresentSummary = true
        sessionTracker.endSession()

        let summary = GrammarLessonSummaryStepViewController(
            point: point,
            outcome: outcome,
            metrics: sessionTracker.metrics.snapshot()
        )
        summary.onContinue = { [weak self] in
            self?.completeSummary(outcome: outcome)
        }
        progressiveCoordinator.pushPostSessionStep(summary)
    }

    private func completeSummary(outcome: GrammarLessonSummaryOutcome) {
        let metrics = sessionTracker.metrics.snapshot()
        progressiveCoordinator?.delegate = nil
        progressiveCoordinator = nil

        switch outcome {
        case .completed:
            masteryStore.markKnown(grammarID: point.id)
            delegate?.grammarLessonSessionDidFinish(point: point, metrics: metrics)
        case .failed:
            delegate?.grammarLessonSessionDidFail(point: point, metrics: metrics)
        }
    }
}

extension GrammarLessonCoordinator: ProgressiveContainerCoordinatorDelegate {
    func progressiveContainerCoordinatorDidFinish(_ coordinator: ProgressiveContainerCoordinator) {
        presentSummary(outcome: .completed)
    }

    func progressiveContainerCoordinatorDidCancel(_ coordinator: ProgressiveContainerCoordinator) {
        coordinator.delegate = nil
        progressiveCoordinator = nil
        sessionTracker.endSession()
        delegate?.grammarLessonSessionDidCancel(point: point)
    }
}
