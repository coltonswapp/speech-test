//
//  DialogueQuizCompletionViewController.swift
//  shizen
//
//  Celebratory result after the last comprehension question.
//

import SwiftUI
import SwiftUIShaders
import UIKit

final class DialogueQuizCompletionViewController: UIViewController {

    static let detentIdentifier = UISheetPresentationController.Detent.Identifier("quizComplete")

    var onExploreHighlights: (() -> Void)?
    var onSheetDismissed: (() -> Void)?

    private let tally: DialogueCompletionTally
    private let highlights: DialogueLearningHighlights

    private let eyebrowLabel = UILabel()
    private let titleLabel = UILabel()
    private let auroraHost = UIHostingController(
        rootView: DialogueCompletionAuroraView(configuration: .production)
    )
    private let starsView = DialogueCompletionStarsView()
    private let subtitleLabel = UILabel()
    private let scoreCard: DialogueScoreSummaryCardView
    private let exploreButton = PrimaryButton()
    private let closeButton = UIButton(type: .system)
    private var hasCommittedAction = false
    private var hasAnimatedIn = false

    init(tally: DialogueCompletionTally, highlights: DialogueLearningHighlights) {
        self.tally = tally
        self.highlights = highlights
        self.scoreCard = DialogueScoreSummaryCardView(tally: tally)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.pageBackground
        installContent()
        prepareEntranceAnimation()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureSheetPresentation()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePreferredContentSize()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        playEntranceAnimationIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        onSheetDismissed?()
    }

    private func installContent() {
        eyebrowLabel.text = resultEyebrow.uppercased()
        eyebrowLabel.font = .systemFont(ofSize: 12, weight: .bold)
        eyebrowLabel.textColor = ExperimentPalette.meaningBadgeText
        eyebrowLabel.textAlignment = .center
        eyebrowLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = resultTitle
        titleLabel.font = .systemFont(ofSize: 30, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        starsView.configure(earned: tally.starCount, maximum: DialogueScoreRules.maxStars)

        subtitleLabel.text = resultSubtitle
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        var closeConfiguration = UIButton.Configuration.gray()
        closeConfiguration.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        )
        closeConfiguration.cornerStyle = .capsule
        closeConfiguration.baseForegroundColor = .secondaryLabel
        closeConfiguration.contentInsets = .zero
        closeButton.configuration = closeConfiguration
        closeButton.accessibilityLabel = "Close"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        }, for: .touchUpInside)

        auroraHost.view.backgroundColor = .clear
        auroraHost.view.isUserInteractionEnabled = false
        auroraHost.view.translatesAutoresizingMaskIntoConstraints = false

        exploreButton.primaryStyle = .yellow
        exploreButton.setTitle(exploreButtonTitle, for: .normal)
        exploreButton.accessibilityLabel = exploreButtonTitle
        exploreButton.addAction(UIAction { [weak self] _ in
            self?.exploreTapped()
        }, for: .touchUpInside)

        addChild(auroraHost)
        view.addSubview(auroraHost.view)
        auroraHost.didMove(toParent: self)
        view.addSubview(closeButton)
        view.addSubview(eyebrowLabel)
        view.addSubview(titleLabel)
        view.addSubview(starsView)
        view.addSubview(subtitleLabel)
        view.addSubview(scoreCard)
        view.addSubview(exploreButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            eyebrowLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 22),
            eyebrowLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 52),
            eyebrowLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -52),

            titleLabel.topAnchor.constraint(equalTo: eyebrowLabel.bottomAnchor, constant: 5),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            starsView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            starsView.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            auroraHost.view.topAnchor.constraint(equalTo: view.topAnchor),
            auroraHost.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            auroraHost.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            auroraHost.view.heightAnchor.constraint(
                equalToConstant: DialogueAuroraConfiguration.production.height
            ),

            subtitleLabel.topAnchor.constraint(equalTo: starsView.bottomAnchor, constant: 10),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            scoreCard.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 20),
            scoreCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scoreCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            exploreButton.topAnchor.constraint(greaterThanOrEqualTo: scoreCard.bottomAnchor, constant: 22),
            exploreButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PrimaryButton.horizontalInset),
            exploreButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PrimaryButton.horizontalInset),
            exploreButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -24
            ),
            exploreButton.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),
        ])
    }

    private var resultEyebrow: String {
        switch tally.starCount {
        case 3: return "Perfect run"
        case 2: return "Great work"
        default: return "Dialogue complete"
        }
    }

    private var resultTitle: String {
        switch tally.starCount {
        case 3: return "Flawless!"
        case 2: return "Nice work!"
        default: return "Keep going!"
        }
    }

    private var resultSubtitle: String {
        switch tally.starCount {
        case 3: return "\(tally.scoreSubtitle) · No English hints"
        case 2 where tally.earnedAllCorrectStar: return "\(tally.scoreSubtitle) · Almost perfect"
        case 2: return "\(tally.scoreSubtitle) · Full immersion"
        default: return "\(tally.scoreSubtitle) · Every run builds fluency"
        }
    }

    private var exploreButtonTitle: String {
        if !highlights.vocabulary.isEmpty {
            return "Explore vocabulary"
        }
        if !highlights.grammarPatterns.isEmpty {
            return "Explore grammar"
        }
        return "Continue"
    }

    private func exploreTapped() {
        guard !hasCommittedAction else { return }
        hasCommittedAction = true
        onExploreHighlights?()
    }

    private var hostingSheet: UISheetPresentationController? {
        navigationController?.sheetPresentationController ?? sheetPresentationController
    }

    private func configureSheetPresentation() {
        guard let sheet = hostingSheet else { return }
        sheet.prefersGrabberVisible = true
        sheet.prefersEdgeAttachedInCompactHeight = true
        sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
        sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        sheet.preferredCornerRadius = 28
        let detent = UISheetPresentationController.Detent.custom(
            identifier: Self.detentIdentifier
        ) { [weak self] context in
            guard let self else { return 480 }
            return min(self.fittedContentHeight, context.maximumDetentValue)
        }
        sheet.detents = [detent]
        sheet.selectedDetentIdentifier = Self.detentIdentifier
    }

    private var fittedContentHeight: CGFloat {
        let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        let contentWidth = max(width - 40, 0)
        let cardTarget = CGSize(width: contentWidth, height: UIView.layoutFittingCompressedSize.height)
        let cardHeight = scoreCard.systemLayoutSizeFitting(
            cardTarget,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        let titleWidth = max(width - 64, 0)
        let titleHeight = titleLabel.sizeThatFits(CGSize(width: titleWidth, height: .greatestFiniteMagnitude)).height
        let subtitleHeight = subtitleLabel.sizeThatFits(CGSize(width: titleWidth, height: .greatestFiniteMagnitude)).height

        let topSafe = view.safeAreaInsets.top
        let bottomSafe = view.safeAreaInsets.bottom
        return topSafe
            + 22
            + 15
            + 5
            + titleHeight
            + 14
            + DialogueCompletionStarsView.preferredHeight
            + 10
            + subtitleHeight
            + 20
            + cardHeight
            + 22
            + PrimaryButton.preferredHeight
            + 24
            + bottomSafe
    }

    private func updatePreferredContentSize() {
        let height = fittedContentHeight
        let size = CGSize(width: view.bounds.width, height: height)
        guard abs(preferredContentSize.height - height) > 1 else { return }
        preferredContentSize = size
        hostingSheet?.invalidateDetents()
    }

    private func prepareEntranceAnimation() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        eyebrowLabel.alpha = 0
        titleLabel.alpha = 0
        titleLabel.transform = CGAffineTransform(translationX: 0, y: 8)
        auroraHost.view.alpha = 0
        auroraHost.view.transform = CGAffineTransform(scaleX: 0.72, y: 0.72)
        starsView.prepareForAnimation()
        subtitleLabel.alpha = 0
        scoreCard.alpha = 0
        scoreCard.transform = CGAffineTransform(translationX: 0, y: 18)
        exploreButton.alpha = 0
        exploreButton.transform = CGAffineTransform(translationX: 0, y: 12)
    }

    private func playEntranceAnimationIfNeeded() {
        guard !hasAnimatedIn else { return }
        hasAnimatedIn = true

        guard !UIAccessibility.isReduceMotionEnabled else {
            starsView.showFinalState()
            return
        }

        UIView.animate(withDuration: 0.35, delay: 0.05, options: [.curveEaseOut, .allowUserInteraction]) {
            self.eyebrowLabel.alpha = 1
            self.titleLabel.alpha = 1
            self.titleLabel.transform = .identity
            self.auroraHost.view.alpha = 1
            self.auroraHost.view.transform = .identity
        }

        starsView.animateIn(earned: tally.starCount, delay: 0.18)

        UIView.animate(
            withDuration: 0.55,
            delay: 0.48,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0.35,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.subtitleLabel.alpha = 1
            self.scoreCard.alpha = 1
            self.scoreCard.transform = .identity
        }

        UIView.animate(
            withDuration: 0.45,
            delay: 0.63,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0.25,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.exploreButton.alpha = 1
            self.exploreButton.transform = .identity
        }
    }
}

struct DialogueAuroraConfiguration: Equatable {
    var intensity: Float
    var bands: Float
    var speed: Float
    var contrast: Double
    var opacity: Double
    var blur: CGFloat
    var fadeLocation: CGFloat
    var height: CGFloat

    static let production = DialogueAuroraConfiguration(
        intensity: 1,
        bands: 4,
        speed: 1.3,
        contrast: 2.2,
        opacity: 0.62,
        blur: 8,
        fadeLocation: 0.62,
        height: 270
    )
}

struct DialogueCompletionAuroraView: View {

    let configuration: DialogueAuroraConfiguration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                staticGlow
            } else {
                animatedAurora
            }
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.86), location: 0),
                    .init(color: .white.opacity(0.72), location: configuration.fadeLocation),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .opacity(configuration.opacity)
        .blur(radius: configuration.blur)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var animatedAurora: some View {
        Color(red: 1.0, green: 0.78, blue: 0.05)
            .mask {
                Color.black
                    .bcsAurora(
                        intensity: configuration.intensity,
                        bands: configuration.bands,
                        speed: configuration.speed,
                        colorShift: 0
                    )
                    .saturation(0)
                    .contrast(configuration.contrast)
                    .luminanceToAlpha()
            }
    }

    private var staticGlow: some View {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.88, blue: 0.34).opacity(0.35),
                Color(red: 1.0, green: 0.76, blue: 0.0).opacity(0.7),
                Color(red: 1.0, green: 0.91, blue: 0.48).opacity(0.35),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// Large objective stars that land one at a time.
final class DialogueCompletionStarsView: UIView {

    static let preferredHeight: CGFloat = 58
    private static let starPointSize: CGFloat = 48
    private static let spacing: CGFloat = 8
    private static let filledColor = UIColor(red: 253 / 255, green: 200 / 255, blue: 1 / 255, alpha: 1)
    private static let emptyColor = UIColor.tertiaryLabel

    private let stack = UIStackView()
    private var starViews: [UIImageView] = []
    private var earnedCount = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Self.spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: Self.preferredHeight),
        ])
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(earned: Int, maximum: Int) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        starViews.removeAll()
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: Self.starPointSize, weight: .semibold)
        let clampedEarned = min(Swift.max(earned, 0), maximum)
        earnedCount = clampedEarned
        for index in 0..<maximum {
            let filled = index < clampedEarned
            let imageView = UIImageView(
                image: UIImage(systemName: "star.fill", withConfiguration: symbolConfig)
            )
            imageView.tintColor = filled ? Self.filledColor : Self.emptyColor
            imageView.contentMode = .scaleAspectFit
            imageView.setContentHuggingPriority(.required, for: .horizontal)
            if index == 1 {
                imageView.transform = CGAffineTransform(translationX: 0, y: -5)
            }
            stack.addArrangedSubview(imageView)
            starViews.append(imageView)
        }
        accessibilityLabel = "\(clampedEarned) of \(maximum) stars"
    }

    func prepareForAnimation() {
        for star in starViews {
            star.alpha = 0
            star.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
                .rotated(by: -.pi / 5)
        }
    }

    func showFinalState() {
        for (index, star) in starViews.enumerated() {
            star.alpha = 1
            star.transform = index == 1
                ? CGAffineTransform(translationX: 0, y: -5)
                : .identity
        }
    }

    func animateIn(earned: Int, delay: TimeInterval) {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.prepare()

        for (index, star) in starViews.enumerated() {
            let starDelay = delay + TimeInterval(index) * 0.12
            guard index < min(earned, earnedCount) else {
                UIView.animate(
                    withDuration: 0.3,
                    delay: starDelay,
                    options: [.curveEaseOut, .allowUserInteraction]
                ) {
                    star.alpha = 1
                    star.transform = index == 1
                        ? CGAffineTransform(translationX: 0, y: -5)
                        : .identity
                }
                continue
            }

            UIView.animate(
                withDuration: 0.58,
                delay: starDelay,
                usingSpringWithDamping: 0.54,
                initialSpringVelocity: 0.8,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                star.alpha = 1
                star.transform = index == 1
                    ? CGAffineTransform(translationX: 0, y: -5)
                    : .identity
            } completion: { _ in
                impact.impactOccurred(intensity: index == 2 ? 0.9 : 0.55)
                impact.prepare()
            }
        }
    }
}
