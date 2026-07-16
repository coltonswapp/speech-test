//
//  GrammarPracticeCoordinator.swift
//  shizen
//

import UIKit

enum GrammarPracticeCoordinator {

    static func present(
        for point: GrammarPoint,
        from presenter: UIViewController,
        masteryStore: GrammarMasteryStore = .shared,
        dialogueProgressStore: DialogueProgressStore = .shared,
        onFinish: (() -> Void)? = nil
    ) {
        let config = GrammarPracticeItemBuilder.SessionConfig(
            targetGrammarId: point.id,
            itemCount: 6,
            meaningChoiceRatio: 0.6
        )
        let items = GrammarPracticeItemBuilder.buildSession(
            for: point,
            completedScenarioIDs: dialogueProgressStore.completedScenarioIDs,
            config: config
        )
        guard !items.isEmpty else {
            let alert = UIAlertController(
                title: "Nothing to practice yet",
                message: "Complete dialogue scenarios that use this pattern, or add contrast drills to this grammar point.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            presenter.present(alert, animated: true)
            return
        }

        let container = GrammarPracticeContainerViewController(
            point: point,
            items: items,
            masteryStore: masteryStore
        )
        container.onFinish = { correct, total in
            let summary = UIAlertController(
                title: "Practice complete",
                message: "\(correct) of \(total) correct",
                preferredStyle: .alert
            )
            summary.addAction(UIAlertAction(title: "Done", style: .default) { _ in
                container.dismiss(animated: true) {
                    onFinish?()
                }
            })
            container.present(summary, animated: true)
        }

        let nav = UINavigationController(rootViewController: container)
        nav.modalPresentationStyle = .fullScreen
        presenter.present(nav, animated: true)
    }
}
