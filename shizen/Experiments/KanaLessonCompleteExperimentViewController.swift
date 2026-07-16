//
//  KanaLessonCompleteExperimentViewController.swift
//  shizen
//
//  DEBUG experiment: preview the lesson summary screen.
//

import UIKit

final class KanaLessonCompleteExperimentViewController: UIViewController {

    private var outcome: KanaLessonSummaryOutcome = .completed
    private var kind: KanaSessionKind = .lesson

    private weak var summaryViewController: KanaLessonSummaryStepViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Lesson complete"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ProgressiveContainerViewController.backgroundColor

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Replay",
            primaryAction: UIAction { [weak self] _ in
                self?.replayPresentation()
            }
        )

        installSummaryPreview()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        replayPresentation()
    }

    private func installSummaryPreview() {
        summaryViewController?.willMove(toParent: nil)
        summaryViewController?.view.removeFromSuperview()
        summaryViewController?.removeFromParent()

        let summary = KanaLessonSummaryStepViewController(
            kind: kind,
            outcome: outcome,
            metrics: mockMetrics(for: outcome),
            suppressCompletionSound: true
        )
        summary.onContinue = { [weak self] in
            self?.replayPresentation()
        }

        addChild(summary)
        summary.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(summary.view)
        NSLayoutConstraint.activate([
            summary.view.topAnchor.constraint(equalTo: view.topAnchor),
            summary.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            summary.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            summary.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        summary.didMove(toParent: self)
        summaryViewController = summary
    }

    private func mockMetrics(for outcome: KanaLessonSummaryOutcome) -> KanaLessonSessionMetrics {
        switch outcome {
        case .completed:
            var metrics = KanaLessonSessionMetrics(startedAt: Date().addingTimeInterval(-125))
            metrics.correctCount = 12
            metrics.wrongCount = 1
            metrics.bestStreak = 5
            metrics.livesRemaining = 2
            return metrics
        case .failed:
            var metrics = KanaLessonSessionMetrics(startedAt: Date().addingTimeInterval(-87))
            metrics.correctCount = 4
            metrics.wrongCount = 3
            metrics.bestStreak = 2
            metrics.livesRemaining = 0
            return metrics
        }
    }

    private func replayPresentation() {
        guard let summaryViewController else { return }
        SpeechOverlayPresenter.shared.dismiss()
        summaryViewController.prepareForEntryAnimation()
        summaryViewController.playEntryAnimation(includeContinueButton: false)

        let trumpetDuration = ExperimentFeedbackSound.duration(
            forAssetNamed: ExperimentFeedbackSoundCatalog.lessonCompleteAsset
        )
        let playbackStartedAt = Date()
        var didRevealAfterTrumpets = false

        let revealAfterTrumpets = { [weak summaryViewController] in
            guard let summaryViewController, !didRevealAfterTrumpets else { return }
            didRevealAfterTrumpets = true
            summaryViewController.playContinueButtonAnimation()
        }

        let scheduleReveal = {
            let elapsed = Date().timeIntervalSince(playbackStartedAt)
            let remaining = max(0, trumpetDuration - elapsed)
            if remaining <= 0.01 {
                revealAfterTrumpets()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: revealAfterTrumpets)
            }
        }

        ExperimentFeedbackSound.playLessonComplete(completion: scheduleReveal)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(trumpetDuration, 1) + 0.3,
            execute: revealAfterTrumpets
        )
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
