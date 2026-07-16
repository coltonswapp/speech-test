//
//  KanaLessonSummaryStepViewController.swift
//  shizen
//

import UIKit

enum KanaLessonSummaryOutcome {
    case completed
    case failed
}

final class KanaLessonSummaryStepViewController: LessonStepViewController {

    var onContinue: (() -> Void)?

    private let kind: KanaSessionKind
    private let outcome: KanaLessonSummaryOutcome
    private let metrics: KanaLessonSessionMetrics
    private let elapsed: TimeInterval
    var presentationConfiguration: KanaLessonSummaryPresentationConfiguration
    private let suppressCompletionSound: Bool

    private weak var titleLabel: UILabel?
    private var metricCardViews: [UIView] = []
    private weak var streakLabel: UILabel?
    private var didPlayCompletionSequence = false

    private var waitsForTrumpetsBeforeContinue: Bool {
        !suppressCompletionSound && outcome == .completed
    }

    private enum MetricCardStyle {
        case yellow
        case green
        case blue

        var accentColor: UIColor {
            switch self {
            case .yellow: return UIColor(red: 1.0, green: 0.78, blue: 0.0, alpha: 1)
            case .green: return UIColor(red: 0.34, green: 0.80, blue: 0.01, alpha: 1)
            case .blue: return UIColor(red: 0.11, green: 0.69, blue: 0.96, alpha: 1)
            }
        }
    }

    init(
        kind: KanaSessionKind,
        outcome: KanaLessonSummaryOutcome,
        metrics: KanaLessonSessionMetrics,
        presentationConfiguration: KanaLessonSummaryPresentationConfiguration = .production,
        suppressCompletionSound: Bool = false
    ) {
        self.kind = kind
        self.outcome = outcome
        self.metrics = metrics
        self.elapsed = metrics.elapsed
        self.presentationConfiguration = presentationConfiguration
        self.suppressCompletionSound = suppressCompletionSound
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        if presentationConfiguration.entryAnimationEnabled {
            prepareForEntryAnimation()
        }
        if waitsForTrumpetsBeforeContinue {
            hideContinueButtonForTrumpets()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Embedded previews (e.g. experiment host) drive their own replay timing.
        guard !suppressCompletionSound else { return }

        if presentationConfiguration.entryAnimationEnabled {
            playEntryAnimation(includeContinueButton: !waitsForTrumpetsBeforeContinue)
        } else if waitsForTrumpetsBeforeContinue {
            hideContinueButtonForTrumpets()
        }

        guard waitsForTrumpetsBeforeContinue, !didPlayCompletionSequence else { return }
        didPlayCompletionSequence = true
        playCompletionSequence()
    }

    func prepareForEntryAnimation() {
        titleLabel?.alpha = 0
        titleLabel?.transform = CGAffineTransform(
            scaleX: presentationConfiguration.titleInitialScale,
            y: presentationConfiguration.titleInitialScale
        )

        for card in metricCardViews {
            card.alpha = 0
            card.transform = CGAffineTransform(translationX: 0, y: presentationConfiguration.cardInitialOffsetY)
        }

        if let streakLabel {
            streakLabel.alpha = 0
            streakLabel.transform = CGAffineTransform(translationX: 0, y: 12)
        }

        primaryButton.alpha = 0
        primaryButton.transform = CGAffineTransform(translationX: 0, y: 16)
        primaryButton.isUserInteractionEnabled = false
    }

    func playEntryAnimation(includeContinueButton: Bool = true, completion: (() -> Void)? = nil) {
        let config = presentationConfiguration

        if let titleLabel {
            UIView.animate(
                withDuration: config.titleAnimationDuration,
                delay: config.titleDelay,
                usingSpringWithDamping: config.titleSpringDamping,
                initialSpringVelocity: 0.4,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                titleLabel.alpha = 1
                titleLabel.transform = .identity
            }
        }

        let cardsBaseDelay = config.titleDelay + config.titleAnimationDuration * 0.35
        for (index, card) in metricCardViews.enumerated() {
            let delay = cardsBaseDelay + config.cardStaggerDelay * TimeInterval(index)
            UIView.animate(
                withDuration: config.cardAnimationDuration,
                delay: delay,
                usingSpringWithDamping: config.cardSpringDamping,
                initialSpringVelocity: 0.3,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                card.alpha = 1
                card.transform = .identity
            }
        }

        if let streakLabel {
            let streakStart = cardsBaseDelay + config.cardStaggerDelay * TimeInterval(metricCardViews.count)
            UIView.animate(
                withDuration: config.streakAnimationDuration,
                delay: max(config.streakDelay, streakStart),
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                streakLabel.alpha = 1
                streakLabel.transform = .identity
            }
        }

        if includeContinueButton {
            let buttonDelay = cardsBaseDelay
                + config.cardStaggerDelay * TimeInterval(metricCardViews.count)
                + config.cardAnimationDuration * 0.4
            playContinueButtonAnimation(
                delay: max(config.buttonDelay, buttonDelay),
                completion: completion
            )
        } else if waitsForTrumpetsBeforeContinue {
            hideContinueButtonForTrumpets()
            completion?()
        } else {
            completion?()
        }
    }

    func playContinueButtonAnimation(delay: TimeInterval = 0, completion: (() -> Void)? = nil) {
        let config = presentationConfiguration
        primaryButton.layer.removeAllAnimations()
        primaryButton.isHidden = false
        primaryButton.alpha = 0
        primaryButton.transform = CGAffineTransform(translationX: 0, y: 16)
        primaryButton.isUserInteractionEnabled = false
        UIView.animate(
            withDuration: config.buttonAnimationDuration,
            delay: delay,
            usingSpringWithDamping: config.buttonSpringDamping,
            initialSpringVelocity: 0.2,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.primaryButton.alpha = 1
            self.primaryButton.transform = .identity
        } completion: { _ in
            self.primaryButton.isUserInteractionEnabled = true
            completion?()
        }
    }

    private func hideContinueButtonForTrumpets() {
        primaryButton.layer.removeAllAnimations()
        primaryButton.alpha = 0
        primaryButton.transform = CGAffineTransform(translationX: 0, y: 16)
        primaryButton.isUserInteractionEnabled = false
        primaryButton.isHidden = true
    }

    private func playCompletionSequence() {
        let trumpetDuration = ExperimentFeedbackSound.duration(
            forAssetNamed: ExperimentFeedbackSoundCatalog.lessonCompleteAsset
        )
        let playbackStartedAt = Date()
        var didRevealAfterTrumpets = false

        let revealAfterTrumpets = { [weak self] in
            guard let self, !didRevealAfterTrumpets else { return }
            didRevealAfterTrumpets = true
            self.playContinueButtonAnimation()
        }

        let scheduleRevealAfterMinimumTrumpetDuration = {
            let elapsed = Date().timeIntervalSince(playbackStartedAt)
            let remaining = max(0, trumpetDuration - elapsed)
            if remaining <= 0.01 {
                revealAfterTrumpets()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: revealAfterTrumpets)
            }
        }

        ExperimentFeedbackSound.playLessonComplete(completion: scheduleRevealAfterMinimumTrumpetDuration)

        // Safety net if the audio delegate never fires.
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(trumpetDuration, 1) + 0.3,
            execute: revealAfterTrumpets
        )
    }

    private func buildUI() {
        let config = presentationConfiguration

        let titleLabel = UILabel()
        titleLabel.text = headlineTitle
        titleLabel.font = .systemFont(ofSize: config.titleFontSize, weight: .heavy)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        self.titleLabel = titleLabel

        let metricsStack = makeMetricsStack()
        metricsStack.translatesAutoresizingMaskIntoConstraints = false
        metricsStack.widthAnchor.constraint(equalToConstant: config.metricCardWidth).isActive = true

        var arrangedSubviews: [UIView] = [titleLabel, metricsStack]
        if outcome == .completed, metrics.bestStreak > 0 {
            let streakLabel = UILabel()
            streakLabel.text = "Best streak: \(metrics.bestStreak)"
            streakLabel.font = .preferredFont(forTextStyle: .headline)
            streakLabel.textColor = .secondaryLabel
            streakLabel.textAlignment = .center
            self.streakLabel = streakLabel
            arrangedSubviews.append(streakLabel)
        }

        let stack = UIStackView(arrangedSubviews: arrangedSubviews)
        stack.axis = .vertical
        stack.spacing = config.stackSpacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        configureCTA(.continue_(), target: self, action: #selector(continueTapped))
        installLessonContent(
            stack,
            topInset: config.contentTopInset,
            horizontalInset: config.horizontalInset
        )
    }

    private var headlineTitle: String {
        switch outcome {
        case .failed:
            return "Out of lives"
        case .completed:
            switch kind {
            case .lesson:
                return "Lesson complete!"
            case .rowReview, .srsReview, .customReview:
                return "Review complete!"
            }
        }
    }

    private func makeMetricsStack() -> UIStackView {
        metricCardViews = []
        let config = presentationConfiguration
        let cards: [(String, String, String, MetricCardStyle)] = metricCards
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = config.metricsStackSpacing
        stack.alignment = .center
        stack.distribution = .fill

        for (title, value, iconName, style) in cards {
            let card = makeMetricCard(title: title, value: value, iconName: iconName, style: style)
            card.translatesAutoresizingMaskIntoConstraints = false
            card.widthAnchor.constraint(equalToConstant: config.metricCardWidth).isActive = true
            metricCardViews.append(card)
            stack.addArrangedSubview(card)
        }
        return stack
    }

    private var metricCards: [(String, String, String, MetricCardStyle)] {
        switch outcome {
        case .failed:
            return [
                ("WRONG", "\(metrics.wrongCount)", "xmark.circle.fill", .yellow),
                ("CORRECT", "\(metrics.correctCount)", "checkmark.circle.fill", .green),
                ("TIME", formatElapsed(elapsed), "clock.fill", .blue),
            ]
        case .completed:
            let accuracyText: String
            if let accuracy = metrics.accuracy {
                accuracyText = "\(Int((accuracy * 100).rounded()))%"
            } else {
                accuracyText = "—"
            }
            return [
                ("CORRECT", "\(metrics.correctCount)", "checkmark.circle.fill", .yellow),
                ("ACCURACY", accuracyText, "target", .green),
                ("TIME", formatElapsed(elapsed), "clock.fill", .blue),
            ]
        }
    }

    private func makeMetricCard(
        title: String,
        value: String,
        iconName: String,
        style: MetricCardStyle
    ) -> UIView {
        let config = presentationConfiguration

        let card = UIView()
        card.backgroundColor = ExperimentPalette.cardSurface
        card.layer.cornerRadius = config.metricCardCornerRadius
        card.layer.borderWidth = config.metricCardBorderWidth
        card.layer.borderColor = style.accentColor.cgColor
        card.clipsToBounds = true

        let header = UIView()
        header.backgroundColor = style.accentColor
        header.translatesAutoresizingMaskIntoConstraints = false

        let headerLabel = UILabel()
        headerLabel.text = title
        headerLabel.font = .systemFont(ofSize: 11, weight: .heavy)
        headerLabel.textColor = .white
        headerLabel.textAlignment = .center
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(headerLabel)

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let iconView = UIImageView(image: UIImage(systemName: iconName, withConfiguration: iconConfig))
        iconView.tintColor = style.accentColor
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 22, weight: .heavy)
        valueLabel.textColor = style.accentColor
        valueLabel.textAlignment = .center
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7

        let bodyStack = UIStackView(arrangedSubviews: [iconView, valueLabel])
        bodyStack.axis = .horizontal
        bodyStack.spacing = 8
        bodyStack.alignment = .center
        bodyStack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(header)
        card.addSubview(bodyStack)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: card.topAnchor),
            header.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 28),

            headerLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            headerLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            bodyStack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            bodyStack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            bodyStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            bodyStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
        ])

        return card
    }

    private func formatElapsed(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    @objc private func continueTapped() {
        SpeechOverlayPresenter.shared.dismiss()
        onContinue?()
    }
}
