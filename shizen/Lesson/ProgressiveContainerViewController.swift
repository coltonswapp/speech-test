//
//  ProgressiveContainerViewController.swift
//  shizen
//

import UIKit

protocol ProgressiveContainerViewControllerDelegate: AnyObject {
    func progressiveContainerDidTapClose(_ container: ProgressiveContainerViewController)
    func progressiveContainerDidTapSkip(_ container: ProgressiveContainerViewController)
}

/// Persistent chrome (progress, close) with a child navigation controller for step content.
final class ProgressiveContainerViewController: UIViewController {

    static let backgroundColor: UIColor = ExperimentPalette.pageBackground

    private static let closeButtonSize: CGFloat = 44
    private static let progressBarHeight: CGFloat = 6
    private static let livesDotSize: CGFloat = 10
    private static let livesDotSpacing: CGFloat = 5
    private static let headerHorizontalInset: CGFloat = 16
    private static let headerItemSpacing: CGFloat = 10

    weak var delegate: ProgressiveContainerViewControllerDelegate?

    private let stepNavigationController: UINavigationController
    private let lessonHeaderContainer = UIView()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let livesStackView = UIStackView()
    private var lifeDotViews: [UIView] = []
    private let closeButton = UIButton(type: .system)
    private let closeGlyphView = UIImageView()
    private let skipButton = UIButton(type: .system)
    private let containerView = UIView()
    private var showsLives = false
    private var livesRemaining = KanaLessonSessionMetrics.maxLives
    private var livesTotal = KanaLessonSessionMetrics.maxLives
    private var isLessonHeaderHidden = false
    private weak var connectedLessonScrollView: UIScrollView?

    private let scrollEdgeInteraction: UIScrollEdgeElementContainerInteraction = {
        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.edge = .top
        return interaction
    }()

    init(stepNavigationController: UINavigationController) {
        self.stepNavigationController = stepNavigationController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Self.backgroundColor

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progressTintColor = .systemYellow
        progressView.trackTintColor = ExperimentPalette.progressBarTrack
        progressView.clipsToBounds = true

        configureCloseButton()
        configureSkipButton()
        configureLivesStack()
        configureLessonHeaderContainer()

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = .clear

        view.addSubview(containerView)
        view.addSubview(lessonHeaderContainer)
        view.addSubview(skipButton)
        view.bringSubviewToFront(lessonHeaderContainer)
        view.bringSubviewToFront(skipButton)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            lessonHeaderContainer.topAnchor.constraint(equalTo: view.topAnchor),
            lessonHeaderContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            lessonHeaderContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            lessonHeaderContainer.bottomAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 12),

            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            skipButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            skipButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16),
        ])

        embed(stepNavigationController)
        syncLivesDisplay()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        closeButton.bringSubviewToFront(closeGlyphView)
        applyRoundedProgressAppearance()
    }

    func connectLessonScrollView(_ scrollView: UIScrollView?) {
        connectedLessonScrollView = scrollView
        scrollEdgeInteraction.scrollView = scrollView
    }

    private func configureLessonHeaderContainer() {
        lessonHeaderContainer.translatesAutoresizingMaskIntoConstraints = false
        lessonHeaderContainer.backgroundColor = .clear
        lessonHeaderContainer.isUserInteractionEnabled = true
        lessonHeaderContainer.addInteraction(scrollEdgeInteraction)
        lessonHeaderContainer.addSubview(closeButton)
        lessonHeaderContainer.addSubview(progressView)
        lessonHeaderContainer.addSubview(livesStackView)

        let guide = lessonHeaderContainer.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: Self.headerHorizontalInset),
            closeButton.widthAnchor.constraint(equalToConstant: Self.closeButtonSize),
            closeButton.heightAnchor.constraint(equalToConstant: Self.closeButtonSize),

            livesStackView.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            livesStackView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -Self.headerHorizontalInset),

            progressView.leadingAnchor.constraint(
                equalTo: closeButton.trailingAnchor,
                constant: Self.headerItemSpacing
            ),
            progressView.trailingAnchor.constraint(
                equalTo: livesStackView.leadingAnchor,
                constant: -Self.headerItemSpacing
            ),
            progressView.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            progressView.heightAnchor.constraint(equalToConstant: Self.progressBarHeight),
        ])
    }

    private func applyRoundedProgressAppearance() {
        let radius = progressView.bounds.height / 2
        progressView.layer.cornerRadius = radius
        for subview in progressView.subviews {
            subview.clipsToBounds = true
            subview.layer.cornerRadius = radius
        }
    }

    func updateProgress(stepIndex: Int, totalSteps: Int) {
        guard totalSteps > 0 else {
            progressView.setProgress(0, animated: false)
            return
        }
        let progress = Float(stepIndex) / Float(totalSteps)
        progressView.setProgress(min(1, progress), animated: true)
    }

    func setLivesVisible(_ visible: Bool) {
        showsLives = visible
        syncLivesDisplay()
    }

    func updateLives(remaining: Int, total: Int = KanaLessonSessionMetrics.maxLives) {
        livesRemaining = remaining
        livesTotal = total
        syncLivesDisplay()
    }

    func setSkipHidden(_ hidden: Bool) {
        skipButton.isHidden = hidden
    }

    func setProgressBarHidden(_ hidden: Bool, animated: Bool = true) {
        setLessonHeaderHidden(hidden, animated: animated)
    }

    /// Slides close, progress, and lives off the top edge; expands step content to the safe area.
    func setLessonHeaderHidden(_ hidden: Bool, animated: Bool = true) {
        guard isViewLoaded, hidden != isLessonHeaderHidden else { return }
        isLessonHeaderHidden = hidden

        view.layoutIfNeeded()
        let slideDistance = closeButton.frame.maxY + 20

        let updates = {
            let transform = hidden
                ? CGAffineTransform(translationX: 0, y: -slideDistance)
                : .identity
            self.lessonHeaderContainer.transform = transform
            self.lessonHeaderContainer.alpha = hidden ? 0 : 1
            self.view.layoutIfNeeded()
        }

        if animated {
            UIView.animate(
                withDuration: 0.38,
                delay: 0,
                usingSpringWithDamping: 0.88,
                initialSpringVelocity: 0.2,
                options: [.curveEaseInOut, .allowUserInteraction],
                animations: updates
            )
        } else {
            updates()
        }
    }

    private func configureLivesStack() {
        livesStackView.axis = .horizontal
        livesStackView.spacing = Self.livesDotSpacing
        livesStackView.alignment = .center
        livesStackView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func syncLivesDisplay() {
        guard isViewLoaded else { return }

        livesStackView.isHidden = !showsLives
        ensureLifeDotCount(livesTotal)

        for (index, dot) in lifeDotViews.enumerated() {
            let isFilled = index < livesRemaining
            dot.backgroundColor = isFilled ? .systemYellow : ExperimentPalette.progressBarTrack
            dot.alpha = isFilled ? 1 : 0.35
        }
    }

    private func ensureLifeDotCount(_ total: Int) {
        guard lifeDotViews.count != total else { return }

        for dot in lifeDotViews {
            livesStackView.removeArrangedSubview(dot)
            dot.removeFromSuperview()
        }
        lifeDotViews.removeAll()

        for _ in 0..<total {
            let dot = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.layer.cornerRadius = Self.livesDotSize / 2
            dot.clipsToBounds = true
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: Self.livesDotSize),
                dot.heightAnchor.constraint(equalToConstant: Self.livesDotSize),
            ])
            livesStackView.addArrangedSubview(dot)
            lifeDotViews.append(dot)
        }
    }

    private func configureCloseButton() {
        var closeConfig = UIButton.Configuration.glass()
        closeConfig.cornerStyle = .capsule
        closeButton.configuration = closeConfig
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.accessibilityLabel = "Close"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        closeGlyphView.image = UIImage(systemName: "chevron.left", withConfiguration: symbolConfig)?
            .withRenderingMode(.alwaysTemplate)
        closeGlyphView.tintColor = .label
        closeGlyphView.preferredSymbolConfiguration = symbolConfig
        closeGlyphView.contentMode = .scaleAspectFit
        closeGlyphView.isUserInteractionEnabled = false
        closeGlyphView.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addSubview(closeGlyphView)

        NSLayoutConstraint.activate([
            closeGlyphView.centerXAnchor.constraint(equalTo: closeButton.centerXAnchor),
            closeGlyphView.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
        ])
    }

    private func configureSkipButton() {
        var config = UIButton.Configuration.glass()
        config.cornerStyle = .capsule
        config.title = "Skip"
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        skipButton.configuration = config
        skipButton.translatesAutoresizingMaskIntoConstraints = false
        skipButton.accessibilityLabel = "Skip step"
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
    }

    private func embed(_ child: UIViewController) {
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            child.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
        child.didMove(toParent: self)
    }

    @objc private func closeTapped() {
        delegate?.progressiveContainerDidTapClose(self)
    }

    @objc private func skipTapped() {
        delegate?.progressiveContainerDidTapSkip(self)
    }
}
