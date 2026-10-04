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
    var onNextScene: (() -> Void)?
    /// Menu title of the following scene. When nil, the next-scene action stays hidden.
    var nextSceneTitle: String?
    /// Last scene of the lesson: the next-scene slot reads "End lesson" and calls `onEndLesson`.
    var onEndLesson: (() -> Void)?
    var onSheetDismissed: (() -> Void)?
    /// When set, the score page leads to a rating page before the real actions.
    var feedbackContext: LessonFeedbackContext?

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
    private let nextSceneButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private var nextSceneButtonTopSpacing: NSLayoutConstraint?
    private var nextSceneButtonHeight: NSLayoutConstraint?
    private var scoreCardToButtonSpacing: NSLayoutConstraint?
    private var feedbackPageToButtonSpacing: NSLayoutConstraint?
    private let feedbackPage = LessonFeedbackPageView()
    private var isShowingFeedbackPage = false
    private var hasSentFeedback = false
    private var hasCommittedAction = false
    private var hasAnimatedIn = false

    /// The score page shows "Continue" until the rating page has been shown.
    private var isFeedbackPending: Bool {
        feedbackContext != nil && !isShowingFeedbackPage
    }

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
        sendFeedbackIfNeeded()
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
            self?.sendFeedbackIfNeeded()
            self?.dismiss(animated: true)
        }, for: .touchUpInside)

        auroraHost.view.backgroundColor = .clear
        auroraHost.view.isUserInteractionEnabled = false
        auroraHost.view.translatesAutoresizingMaskIntoConstraints = false

        exploreButton.primaryStyle = .yellow
        applyPrimaryButtonTitle()
        exploreButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if self.isFeedbackPending {
                self.showFeedbackPage()
            } else {
                self.exploreTapped()
            }
        }, for: .touchUpInside)

        feedbackPage.alpha = 0
        feedbackPage.isHidden = true
        feedbackPage.onSkip = { [weak self] in
            guard let self else { return }
            self.feedbackPage.clear()
            self.sendFeedbackIfNeeded()
            self.dismiss(animated: true)
        }

        var nextConfig = UIButton.Configuration.plain()
        nextConfig.title = endsLesson ? "End lesson" : "Next scene"
        nextConfig.image = UIImage(systemName: endsLesson ? "flag.checkered" : "arrow.right")
        nextConfig.imagePlacement = .trailing
        nextConfig.imagePadding = 6
        nextConfig.baseForegroundColor = .label
        nextConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
            return outgoing
        }
        nextSceneButton.configuration = nextConfig
        nextSceneButton.translatesAutoresizingMaskIntoConstraints = false
        nextSceneButton.addAction(UIAction { [weak self] _ in
            self?.nextSceneTapped()
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
        view.addSubview(feedbackPage)
        view.addSubview(exploreButton)
        view.addSubview(nextSceneButton)

        let nextSceneTopSpacing = nextSceneButton.topAnchor.constraint(equalTo: exploreButton.bottomAnchor)
        let nextSceneHeight = nextSceneButton.heightAnchor.constraint(equalToConstant: 0)
        nextSceneButtonTopSpacing = nextSceneTopSpacing
        nextSceneButtonHeight = nextSceneHeight
        let scoreCardSpacing = exploreButton.topAnchor.constraint(
            greaterThanOrEqualTo: scoreCard.bottomAnchor,
            constant: 22
        )
        scoreCardToButtonSpacing = scoreCardSpacing
        feedbackPageToButtonSpacing = exploreButton.topAnchor.constraint(
            greaterThanOrEqualTo: feedbackPage.bottomAnchor,
            constant: 22
        )

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

            feedbackPage.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 22),
            feedbackPage.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            feedbackPage.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            scoreCardSpacing,
            exploreButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PrimaryButton.horizontalInset),
            exploreButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PrimaryButton.horizontalInset),
            exploreButton.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),

            nextSceneTopSpacing,
            nextSceneHeight,
            nextSceneButton.leadingAnchor.constraint(equalTo: exploreButton.leadingAnchor),
            nextSceneButton.trailingAnchor.constraint(equalTo: exploreButton.trailingAnchor),
            nextSceneButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -24
            ),
        ])
        applyNextSceneButton()
    }

    private var endsLesson: Bool {
        onEndLesson != nil
    }

    private func applyNextSceneButton() {
        let title = nextSceneTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNextScene = onNextScene != nil && title?.isEmpty == false
        let show = (endsLesson || hasNextScene) && !isFeedbackPending
        nextSceneButton.isHidden = !show
        nextSceneButton.isEnabled = show
        if endsLesson {
            nextSceneButton.accessibilityLabel = "End lesson"
        } else {
            nextSceneButton.accessibilityLabel = show ? "Next scene, \(title ?? "")" : "Next scene"
        }
        nextSceneButtonTopSpacing?.constant = show ? 8 : 0
        nextSceneButtonHeight?.constant = show ? 44 : 0
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

    private func applyPrimaryButtonTitle() {
        let title = isFeedbackPending ? "Continue" : exploreButtonTitle
        exploreButton.setTitle(title, for: .normal)
        exploreButton.accessibilityLabel = title
    }

    private func exploreTapped() {
        guard !hasCommittedAction else { return }
        hasCommittedAction = true
        sendFeedbackIfNeeded()
        onExploreHighlights?()
    }

    private func nextSceneTapped() {
        guard !hasCommittedAction else { return }
        hasCommittedAction = true
        sendFeedbackIfNeeded()
        if let onEndLesson {
            onEndLesson()
        } else {
            onNextScene?()
        }
    }

    private var scorePageViews: [UIView] {
        [eyebrowLabel, titleLabel, starsView, subtitleLabel, scoreCard]
    }

    private func showFeedbackPage() {
        guard isFeedbackPending else { return }
        isShowingFeedbackPage = true
        scoreCardToButtonSpacing?.isActive = false
        feedbackPageToButtonSpacing?.isActive = true
        applyPrimaryButtonTitle()
        applyNextSceneButton()
        feedbackPage.isHidden = false
        nextSceneButton.transform = .identity

        let swap = {
            self.scorePageViews.forEach { $0.alpha = 0 }
            self.feedbackPage.alpha = 1
            self.nextSceneButton.alpha = self.nextSceneButton.isHidden ? 0 : 1
            self.view.layoutIfNeeded()
        }
        let finish: (Bool) -> Void = { _ in
            self.scorePageViews.forEach { $0.isHidden = true }
            UIAccessibility.post(notification: .screenChanged, argument: self.feedbackPage)
        }
        let resize = {
            self.hostingSheet?.animateChanges {
                self.updatePreferredContentSize()
            }
        }

        if UIAccessibility.isReduceMotionEnabled {
            swap()
            finish(true)
            resize()
            return
        }
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction],
            animations: swap,
            completion: finish
        )
        resize()
    }

    /// Sends once, on the first exit from the rating page. Empty rows send nothing.
    private func sendFeedbackIfNeeded() {
        guard isShowingFeedbackPage, !hasSentFeedback, let context = feedbackContext else { return }
        hasSentFeedback = true
        let ratings = feedbackPage.ratings
        guard !ratings.isEmpty else { return }
        LessonFeedbackPrompt.markRated(context)
        Task {
            await LLMGatewayClient.postLessonFeedback(context, ratings: ratings)
        }
        showToast(text: "Thanks for the feedback")
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
        let topSafe = view.safeAreaInsets.top
        let bottomSafe = view.safeAreaInsets.bottom
        let actionsHeight = PrimaryButton.preferredHeight
            + (nextSceneButton.isHidden ? 0 : 8 + 44)
            + 24

        if isShowingFeedbackPage {
            let pageHeight = feedbackPage.systemLayoutSizeFitting(
                CGSize(width: contentWidth, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
            return topSafe + 22 + pageHeight + 22 + actionsHeight + bottomSafe
        }

        let cardTarget = CGSize(width: contentWidth, height: UIView.layoutFittingCompressedSize.height)
        let cardHeight = scoreCard.systemLayoutSizeFitting(
            cardTarget,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        let titleWidth = max(width - 64, 0)
        let titleHeight = titleLabel.sizeThatFits(CGSize(width: titleWidth, height: .greatestFiniteMagnitude)).height
        let subtitleHeight = subtitleLabel.sizeThatFits(CGSize(width: titleWidth, height: .greatestFiniteMagnitude)).height

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
            + actionsHeight
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
        nextSceneButton.alpha = 0
        nextSceneButton.transform = CGAffineTransform(translationX: 0, y: 12)
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
            if !self.nextSceneButton.isHidden {
                self.nextSceneButton.alpha = 1
                self.nextSceneButton.transform = .identity
            }
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
struct DialogueLessonWrapUp: Hashable {

    struct Scene: Hashable {
        let title: String
        /// Nil when the scene has never been finished.
        let starCount: Int?
        /// Nil when no scored run was recorded (unplayed, or a legacy completion).
        let points: Int?
    }

    let lessonTitle: String
    let thumbnailURL: URL?
    let sceneImageName: String?
    /// Best possible sum if every scene earned a perfect tally (all quiz credit + immersed listen).
    let totalPossiblePoints: Int
    let scenes: [Scene]

    /// Sum of each scene's recorded points. Nil when no scene has a scored run.
    var totalPoints: Int? {
        let recorded = scenes.compactMap(\.points)
        return recorded.isEmpty ? nil : recorded.reduce(0, +)
    }

    var earnedStars: Int {
        scenes.reduce(0) { $0 + ($1.starCount ?? 0) }
    }

    var maximumStars: Int {
        scenes.count * DialogueScoreRules.maxStars
    }

    static func maximumPoints(for scenario: DialogueScenarioCollection.Scenario) -> Int {
        scenario.quiz.count * DialogueScoreRules.pointsPerCorrectQuestion + DialogueScoreRules.immersedBonus
    }

    /// Each scene reports its best run, the same run the lesson picker's stars reflect.
    static func make(
        collection: DialogueScenarioCollection,
        progress: DialogueProgressStore = .shared
    ) -> DialogueLessonWrapUp {
        let totalPossible = collection.scenarios.reduce(0) { $0 + maximumPoints(for: $1) }
        let scenes = collection.scenarios.map { scenario in
            let best = progress.attempts(scenarioID: scenario.id).max {
                ($0.starCount, $0.points) < ($1.starCount, $1.points)
            }
            let completed = progress.isCompleted(scenarioID: scenario.id)
            return Scene(
                title: scenario.menuTitle,
                starCount: best?.starCount ?? (completed ? 1 : nil),
                points: best?.points
            )
        }
        return DialogueLessonWrapUp(
            lessonTitle: collection.title,
            thumbnailURL: collection.thumbnailURL,
            sceneImageName: collection.sceneImageName,
            totalPossiblePoints: totalPossible,
            scenes: scenes
        )
    }
}

final class DialogueLessonWrapUpViewController: UIViewController {

    static let detentIdentifier = UISheetPresentationController.Detent.Identifier("lessonWrapUp")

    private static let thumbnailSide: CGFloat = 104
    private static let contentTopInset: CGFloat = 22
    private static let contentSideInset: CGFloat = 20
    private static let actionsBottomInset: CGFloat = 24

    var onBackToLessons: (() -> Void)?

    private let wrapUp: DialogueLessonWrapUp

    private let auroraHost = UIHostingController(
        rootView: DialogueCompletionAuroraView(configuration: .production)
    )
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let thumbnailView = UIImageView()
    private let eyebrowLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let scenesCard: DialogueLessonScenesCardView
    private let backButton = PrimaryButton()
    private let closeButton = UIButton(type: .system)
    private var hasCommittedAction = false
    private var hasAnimatedIn = false

    init(wrapUp: DialogueLessonWrapUp) {
        self.wrapUp = wrapUp
        self.scenesCard = DialogueLessonScenesCardView(wrapUp: wrapUp)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.pageBackground
        installContent()
        loadThumbnail()
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

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        thumbnailView.layer.borderColor = ExperimentPalette.cardBorder.cgColor
    }

    private func installContent() {
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.backgroundColor = .tertiarySystemFill
        thumbnailView.layer.cornerCurve = .continuous
        thumbnailView.layer.cornerRadius = Self.thumbnailSide * 0.2
        thumbnailView.layer.borderWidth = 1
        thumbnailView.layer.borderColor = ExperimentPalette.cardBorder.cgColor
        thumbnailView.isAccessibilityElement = false
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false

        eyebrowLabel.text = "Lesson complete".uppercased()
        eyebrowLabel.font = .systemFont(ofSize: 12, weight: .bold)
        eyebrowLabel.textColor = ExperimentPalette.meaningBadgeText
        eyebrowLabel.textAlignment = .center

        titleLabel.text = wrapUp.lessonTitle
        titleLabel.font = .systemFont(ofSize: 30, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header

        subtitleLabel.text = subtitleText
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        contentStack.axis = .vertical
        contentStack.alignment = .center
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        for subview in [thumbnailView, eyebrowLabel, titleLabel, subtitleLabel, scenesCard] {
            contentStack.addArrangedSubview(subview)
        }
        contentStack.setCustomSpacing(16, after: thumbnailView)
        contentStack.setCustomSpacing(5, after: eyebrowLabel)
        contentStack.setCustomSpacing(8, after: titleLabel)
        contentStack.setCustomSpacing(20, after: subtitleLabel)

        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

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

        backButton.primaryStyle = .yellow
        backButton.setTitle("Back to lessons", for: .normal)
        backButton.accessibilityLabel = "Back to lessons"
        backButton.addAction(UIAction { [weak self] _ in
            self?.backTapped()
        }, for: .touchUpInside)

        addChild(auroraHost)
        view.addSubview(auroraHost.view)
        auroraHost.didMove(toParent: self)
        view.addSubview(scrollView)
        view.addSubview(closeButton)
        view.addSubview(backButton)

        let contentGuide = scrollView.contentLayoutGuide
        NSLayoutConstraint.activate([
            auroraHost.view.topAnchor.constraint(equalTo: view.topAnchor),
            auroraHost.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            auroraHost.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            auroraHost.view.heightAnchor.constraint(
                equalToConstant: DialogueAuroraConfiguration.production.height
            ),

            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: backButton.topAnchor, constant: -12),

            contentStack.topAnchor.constraint(equalTo: contentGuide.topAnchor, constant: Self.contentTopInset),
            contentStack.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor, constant: Self.contentSideInset),
            contentStack.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor, constant: -Self.contentSideInset),
            contentStack.bottomAnchor.constraint(equalTo: contentGuide.bottomAnchor, constant: -10),
            contentStack.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -Self.contentSideInset * 2
            ),

            thumbnailView.widthAnchor.constraint(equalToConstant: Self.thumbnailSide),
            thumbnailView.heightAnchor.constraint(equalToConstant: Self.thumbnailSide),
            eyebrowLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -64),
            titleLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -24),
            subtitleLabel.widthAnchor.constraint(equalTo: titleLabel.widthAnchor),
            scenesCard.widthAnchor.constraint(equalTo: contentStack.widthAnchor),

            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PrimaryButton.horizontalInset),
            backButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PrimaryButton.horizontalInset),
            backButton.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),
            backButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -Self.actionsBottomInset
            ),
        ])
    }

    private var subtitleText: String {
        let count = wrapUp.scenes.count
        let scenes = count == 1 ? "1 scene" : "\(count) scenes"
        return "\(scenes) · \(wrapUp.earnedStars) of \(wrapUp.maximumStars) stars"
    }

    private func backTapped() {
        guard !hasCommittedAction else { return }
        hasCommittedAction = true
        onBackToLessons?()
    }

    private func loadThumbnail() {
        let pixelSize = Self.thumbnailSide * 3
        if let name = wrapUp.sceneImageName,
           let bundled = LessonThumbnailLoader.bundledImage(named: name, targetPixelSize: pixelSize, variant: .color) {
            thumbnailView.image = bundled
        }
        guard let url = wrapUp.thumbnailURL else { return }
        if let cached = LessonThumbnailLoader.cachedImage(for: url, targetPixelSize: pixelSize, variant: .color) {
            thumbnailView.image = cached
            return
        }
        LessonThumbnailLoader.load(url: url, targetPixelSize: pixelSize, variant: .color) { [weak self] image in
            guard let self, let image else { return }
            UIView.transition(with: self.thumbnailView, duration: 0.2, options: .transitionCrossDissolve) {
                self.thumbnailView.image = image
            }
        }
    }

    // MARK: - Sheet sizing

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
            guard let self else { return 520 }
            return min(self.fittedContentHeight, context.maximumDetentValue)
        }
        sheet.detents = [detent]
        sheet.selectedDetentIdentifier = Self.detentIdentifier
    }

    private var fittedContentHeight: CGFloat {
        let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        let stackHeight = contentStack.systemLayoutSizeFitting(
            CGSize(width: max(width - Self.contentSideInset * 2, 0), height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        return view.safeAreaInsets.top
            + Self.contentTopInset
            + stackHeight
            + 10
            + 12
            + PrimaryButton.preferredHeight
            + Self.actionsBottomInset
            + view.safeAreaInsets.bottom
    }

    private func updatePreferredContentSize() {
        let height = fittedContentHeight
        guard abs(preferredContentSize.height - height) > 1 else { return }
        preferredContentSize = CGSize(width: view.bounds.width, height: height)
        hostingSheet?.invalidateDetents()
    }

    // MARK: - Entrance

    private func prepareEntranceAnimation() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        auroraHost.view.alpha = 0
        auroraHost.view.transform = CGAffineTransform(scaleX: 0.72, y: 0.72)
        thumbnailView.alpha = 0
        thumbnailView.transform = CGAffineTransform(scaleX: 0.82, y: 0.82)
        for label in [eyebrowLabel, titleLabel, subtitleLabel] {
            label.alpha = 0
            label.transform = CGAffineTransform(translationX: 0, y: 8)
        }
        scenesCard.alpha = 0
        scenesCard.transform = CGAffineTransform(translationX: 0, y: 18)
        backButton.alpha = 0
        backButton.transform = CGAffineTransform(translationX: 0, y: 12)
    }

    private func playEntranceAnimationIfNeeded() {
        guard !hasAnimatedIn else { return }
        hasAnimatedIn = true
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        UIView.animate(
            withDuration: 0.55,
            delay: 0.05,
            usingSpringWithDamping: 0.72,
            initialSpringVelocity: 0.4,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.auroraHost.view.alpha = 1
            self.auroraHost.view.transform = .identity
            self.thumbnailView.alpha = 1
            self.thumbnailView.transform = .identity
        }

        UIView.animate(withDuration: 0.35, delay: 0.16, options: [.curveEaseOut, .allowUserInteraction]) {
            for label in [self.eyebrowLabel, self.titleLabel, self.subtitleLabel] {
                label.alpha = 1
                label.transform = .identity
            }
        }

        UIView.animate(
            withDuration: 0.55,
            delay: 0.32,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0.35,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.scenesCard.alpha = 1
            self.scenesCard.transform = .identity
        }
        scenesCard.animateRowsIn(delay: 0.4)

        UIView.animate(
            withDuration: 0.45,
            delay: 0.5,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0.25,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.backButton.alpha = 1
            self.backButton.transform = .identity
        }
    }
}

// MARK: - Scenes card

/// Same card treatment as `DialogueScoreSummaryCardView`, one row per scene.
private final class DialogueLessonScenesCardView: UIView {

    private static let inset: CGFloat = 18
    private static let starColor = UIColor(red: 253 / 255, green: 200 / 255, blue: 1 / 255, alpha: 1)

    private let wrapUp: DialogueLessonWrapUp
    private let contentStack = UIStackView()
    private var sceneRows: [UIView] = []

    init(wrapUp: DialogueLessonWrapUp) {
        self.wrapUp = wrapUp
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        layer.borderColor = ExperimentPalette.cardBorder.cgColor
    }

    func animateRowsIn(delay: TimeInterval) {
        for (index, row) in sceneRows.enumerated() {
            row.alpha = 0
            row.transform = CGAffineTransform(translationX: 0, y: 6)
            UIView.animate(
                withDuration: 0.35,
                delay: delay + TimeInterval(index) * 0.05,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                row.alpha = 1
                row.transform = .identity
            }
        }
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = ExperimentPalette.cardSurface
        layer.cornerCurve = .continuous
        layer.cornerRadius = 22
        layer.borderWidth = 1
        layer.borderColor = ExperimentPalette.cardBorder.cgColor

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        var accessible: [UIView] = []
        if let total = wrapUp.totalPoints {
            let header = makeTotalHeader(total: total, possible: wrapUp.totalPossiblePoints)
            contentStack.addArrangedSubview(header)
            accessible.append(header)

            let divider = UIView()
            divider.backgroundColor = .separator
            divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
            contentStack.addArrangedSubview(divider)
            contentStack.setCustomSpacing(14, after: divider)
        }

        for (index, scene) in wrapUp.scenes.enumerated() {
            let row = makeSceneRow(number: index + 1, scene: scene)
            contentStack.addArrangedSubview(row)
            sceneRows.append(row)
            accessible.append(row)
        }

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: Self.inset),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.inset),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.inset),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.inset),
        ])
        accessibilityElements = accessible
    }

    private func makeTotalHeader(total: Int, possible: Int) -> UIView {
        let caption = UILabel()
        caption.text = "LESSON SCORE"
        caption.font = .systemFont(ofSize: 11, weight: .bold)
        caption.textColor = .secondaryLabel

        let scoreFont = UIFont.systemFont(ofSize: 34, weight: .bold)
        let roundedScoreFont = scoreFont.fontDescriptor.withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: 34) } ?? scoreFont

        let pointsLabel = UILabel()
        pointsLabel.text = "\(total)"
        pointsLabel.font = roundedScoreFont
        pointsLabel.textColor = .label
        pointsLabel.setContentHuggingPriority(.required, for: .horizontal)
        pointsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let slashLabel = UILabel()
        slashLabel.text = "/"
        slashLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        slashLabel.textColor = .tertiaryLabel
        slashLabel.setContentHuggingPriority(.required, for: .horizontal)

        let possibleLabel = UILabel()
        possibleLabel.text = "\(possible)"
        possibleLabel.font = roundedScoreFont.withSize(26)
        possibleLabel.textColor = .secondaryLabel
        possibleLabel.setContentHuggingPriority(.required, for: .horizontal)
        possibleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let unitLabel = UILabel()
        unitLabel.text = "points"
        unitLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        unitLabel.textColor = .secondaryLabel
        unitLabel.setContentHuggingPriority(.required, for: .horizontal)

        let scoreLine = UIStackView(arrangedSubviews: [pointsLabel, slashLabel, possibleLabel, unitLabel])
        scoreLine.axis = .horizontal
        scoreLine.alignment = .lastBaseline
        scoreLine.spacing = 2
        scoreLine.setCustomSpacing(6, after: possibleLabel)

        let copyStack = UIStackView(arrangedSubviews: [caption, scoreLine])
        copyStack.axis = .vertical
        copyStack.alignment = .leading
        copyStack.spacing = 2

        let badge = UIImageView(
            image: UIImage(
                systemName: "flag.checkered",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            )
        )
        badge.tintColor = ExperimentPalette.meaningBadgeText
        badge.backgroundColor = ExperimentPalette.highlightFill
        badge.contentMode = .center
        badge.layer.cornerCurve = .continuous
        badge.layer.cornerRadius = 19
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 38),
            badge.heightAnchor.constraint(equalToConstant: 38),
        ])

        let header = UIStackView(arrangedSubviews: [copyStack, badge])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 12
        header.isAccessibilityElement = true
        header.accessibilityLabel = "Lesson score, \(total) of \(possible) points"
        return header
    }

    private func makeSceneRow(number: Int, scene: DialogueLessonWrapUp.Scene) -> UIView {
        let played = scene.starCount != nil

        let numberLabel = UILabel()
        numberLabel.text = "\(number)"
        numberLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        numberLabel.textColor = played ? ExperimentPalette.meaningBadgeText : .tertiaryLabel
        numberLabel.textAlignment = .center
        numberLabel.backgroundColor = played ? ExperimentPalette.highlightFill : .tertiarySystemFill
        numberLabel.layer.cornerCurve = .continuous
        numberLabel.layer.cornerRadius = 14
        numberLabel.clipsToBounds = true
        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            numberLabel.widthAnchor.constraint(equalToConstant: 28),
            numberLabel.heightAnchor.constraint(equalToConstant: 28),
        ])

        let titleLabel = UILabel()
        titleLabel.text = scene.title
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = played ? .label : .secondaryLabel
        titleLabel.numberOfLines = 2
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stars = makeStars(earned: scene.starCount ?? 0)

        let pointsLabel = UILabel()
        pointsLabel.text = scene.points.map { "\($0)" } ?? "—"
        pointsLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        pointsLabel.textColor = scene.points == nil ? .tertiaryLabel : .label
        pointsLabel.textAlignment = .right
        pointsLabel.setContentHuggingPriority(.required, for: .horizontal)
        pointsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        pointsLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true

        let row = UIStackView(arrangedSubviews: [numberLabel, titleLabel, stars, pointsLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .fill
        row.spacing = 10
        row.setCustomSpacing(12, after: stars)
        row.isAccessibilityElement = true
        row.accessibilityLabel = accessibilityLabel(number: number, scene: scene)
        return row
    }

    private func makeStars(earned: Int) -> UIView {
        let pointSize: CGFloat = 12
        let symbol = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let starSide = pointSize + 2
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fill
        stack.spacing = 2
        for index in 0..<DialogueScoreRules.maxStars {
            let star = UIImageView(image: UIImage(systemName: "star.fill", withConfiguration: symbol))
            star.contentMode = .scaleAspectFit
            star.tintColor = index < earned ? Self.starColor : .quaternaryLabel
            star.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                star.widthAnchor.constraint(equalToConstant: starSide),
                star.heightAnchor.constraint(equalToConstant: starSide),
            ])
            stack.addArrangedSubview(star)
        }
        stack.setContentHuggingPriority(.required, for: .horizontal)
        stack.setContentCompressionResistancePriority(.required, for: .horizontal)
        return stack
    }

    private func accessibilityLabel(number: Int, scene: DialogueLessonWrapUp.Scene) -> String {
        let prefix = "Scene \(number), \(scene.title)"
        guard let stars = scene.starCount else { return "\(prefix), not played" }
        let starText = "\(stars) of \(DialogueScoreRules.maxStars) stars"
        guard let points = scene.points else { return "\(prefix), \(starText)" }
        return "\(prefix), \(starText), \(points) points"
    }
}

enum DialogueLessonWrapUpPresenter {
    static func present(
        from host: UIViewController,
        collection: DialogueScenarioCollection,
        onBackToLessons: @escaping () -> Void
    ) {
        let summary = DialogueLessonWrapUp.make(collection: collection)
        let sheet = DialogueLessonWrapUpViewController(wrapUp: summary)
        sheet.onBackToLessons = onBackToLessons
        sheet.modalPresentationStyle = UIModalPresentationStyle.pageSheet
        host.present(sheet, animated: true)
    }
}
