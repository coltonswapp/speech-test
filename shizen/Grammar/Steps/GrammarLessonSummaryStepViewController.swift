//
//  GrammarLessonSummaryStepViewController.swift
//  shizen
//

import UIKit

enum GrammarLessonSummaryOutcome {
    case completed
    case failed
}

final class GrammarLessonSummaryStepViewController: LessonStepViewController {

    var onContinue: (() -> Void)?

    private let point: GrammarPoint
    private let outcome: GrammarLessonSummaryOutcome
    private let metrics: KanaLessonSessionMetrics

    init(point: GrammarPoint, outcome: GrammarLessonSummaryOutcome, metrics: KanaLessonSessionMetrics) {
        self.point = point
        self.outcome = outcome
        self.metrics = metrics
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        configureCTA(.continue_(), target: self, action: #selector(continueTapped))
        progressiveContainerCoordinator?.setLivesVisible(false)
    }

    private func buildUI() {
        let title = UILabel()
        title.font = .systemFont(ofSize: 26, weight: .bold)
        title.textAlignment = .center
        title.numberOfLines = 0
        title.text = outcome == .completed ? "Grammar complete!" : "Out of lives"

        let subtitle = UILabel()
        subtitle.font = .preferredFont(forTextStyle: .body)
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0
        subtitle.textColor = .secondaryLabel
        subtitle.text = point.title

        let stats = UILabel()
        stats.font = .preferredFont(forTextStyle: .subheadline)
        stats.textAlignment = .center
        stats.numberOfLines = 0
        stats.textColor = .tertiaryLabel
        let total = metrics.correctCount + metrics.wrongCount
        let accuracy = metrics.accuracy.map { Int(($0 * 100).rounded()) } ?? 0
        stats.text = "\(metrics.correctCount) correct · \(total) answered · \(accuracy)% accuracy"

        let stack = UIStackView(arrangedSubviews: [title, subtitle, stats])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        installLessonContent(stack)
    }

    @objc private func continueTapped() {
        onContinue?()
    }
}
