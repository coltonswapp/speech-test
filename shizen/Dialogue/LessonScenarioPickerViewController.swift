//
//  LessonScenarioPickerViewController.swift
//  shizen
//
//  Intermediate screen between the lesson grid and the dialogue player:
//  shows every scenario in a lesson with its best star grade so the user
//  picks exactly which conversation to tackle next.
//

import UIKit

final class LessonScenarioPickerViewController: UIViewController {

    private let collectionID: String
    private let fallbackTitle: String?
    private var collection: DialogueScenarioCollection?

    /// When set, tapping a scenario calls this instead of opening the nested paging player.
    var onOpenScenario: ((DialogueScenarioCollection, String) -> Void)?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let loadingCoordinator = DialogueLessonLoadingCoordinator()
    private var scenarioRows: [LessonScenarioRowContainer] = []

    private static let horizontalInset: CGFloat = 16

    init(collectionID: String, fallbackTitle: String? = nil) {
        self.collectionID = collectionID
        self.fallbackTitle = fallbackTitle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = fallbackTitle ?? "Lesson"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground

        configureScrollView()

        if #available(iOS 26.0, *) {
            scrollView.topEdgeEffect.style = .soft
        }

        loadingCoordinator.attach(to: view)
        if let ready = DialogueScenarioCollectionCatalog.readyCollection(id: collectionID) {
            applyCollection(ready)
        } else {
            loadingCoordinator.beginLoading()
        }
        DialogueScenarioCollectionCatalog.fetchCollection(id: collectionID) { [weak self] collection in
            guard let self else { return }
            let apply = {
                if let collection {
                    self.applyCollection(collection)
                } else if self.collection == nil {
                    self.showLoadFailure()
                }
            }
            if self.collection == nil {
                self.loadingCoordinator.finishLoading(completion: apply)
            } else {
                apply()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh checkmarks when returning from a scenario just completed.
        DialogueProgressStore.shared.reload()
        refreshCompletionStates()
    }

    // MARK: - Layout

    private func configureScrollView() {
        scrollView.alwaysBounceVertical = true
        scrollView.backgroundColor = ExperimentPalette.pageBackground
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        let inset = Self.horizontalInset
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: inset),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -inset),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -inset * 2),
        ])
    }

    // MARK: - Content

    private func applyCollection(_ collection: DialogueScenarioCollection) {
        self.collection = collection
        title = collection.title

        for view in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        scenarioRows = []

        let header = UILabel()
        header.text = "Choose a scenario"
        header.font = .preferredFont(forTextStyle: .subheadline)
        header.textColor = .secondaryLabel
        header.translatesAutoresizingMaskIntoConstraints = false
        let headerWrap = UIStackView(arrangedSubviews: [header])
        headerWrap.isLayoutMarginsRelativeArrangement = true
        headerWrap.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 0)
        contentStack.addArrangedSubview(headerWrap)
        contentStack.setCustomSpacing(16, after: headerWrap)

        for (index, scenario) in collection.scenarios.enumerated() {
            let row = LessonScenarioRowContainer(
                index: index + 1,
                title: scenario.menuTitle,
                subtitle: scenario.menuSubtitle
            )
            row.onOpen = { [weak self] in
                self?.openScenario(id: scenario.id)
            }
            row.onRetake = { [weak self] in
                self?.openScenario(id: scenario.id, sessionMode: .retakeQuiz)
            }
            contentStack.addArrangedSubview(row)
            scenarioRows.append(row)
        }

        refreshCompletionStates()
    }

    private func refreshCompletionStates() {
        guard let collection else { return }
        let store = DialogueProgressStore.shared
        for (row, scenario) in zip(scenarioRows, collection.scenarios) {
            let completed = store.isCompleted(scenarioID: scenario.id)
            row.setProgress(
                completed: completed,
                starCount: store.displayedStarCount(scenarioID: scenario.id),
                lastPoints: store.lastPoints(scenarioID: scenario.id),
                showsRetake: completed && !scenario.quiz.isEmpty
            )
        }
    }

    private func showLoadFailure() {
        let alert = UIAlertController(
            title: "Couldn’t load lesson",
            message: "Failed to fetch “\(collectionID)” from \(ContentCMSClient.baseURL?.absoluteString ?? "the CMS"). Rebuild the app and force-quit so it isn’t using a cached lesson JSON.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    private func openScenario(id: String, sessionMode: DialogueLessonSessionMode? = nil) {
        guard let collection else { return }
        if let onOpenScenario {
            onOpenScenario(collection, id)
            return
        }
        let completed = DialogueProgressStore.shared.isCompleted(scenarioID: id)
        let mode = sessionMode ?? (completed ? .viewLesson : .attempt)
        let dialogue = DialogueNestedPagingExperimentViewController(
            collection: collection,
            initialScenarioID: id,
            sessionMode: mode
        )
        navigationController?.pushViewController(dialogue, animated: true)
    }
}

// MARK: - Scenario row

/// Card plus an optional sibling Retake control so the two taps never nest.
private final class LessonScenarioRowContainer: UIView {

    var onOpen: (() -> Void)?
    var onRetake: (() -> Void)?

    private let row: LessonScenarioRowControl
    private let retakeButton = UIButton(type: .system)

    init(index: Int, title: String, subtitle: String?) {
        row = LessonScenarioRowControl(index: index, title: title, subtitle: subtitle)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        row.addAction(UIAction { [weak self] _ in
            self?.onOpen?()
        }, for: .touchUpInside)

        var retakeConfig = UIButton.Configuration.gray()
        retakeConfig.cornerStyle = .capsule
        retakeConfig.title = "Retake"
        retakeConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 13, weight: .semibold)
            return outgoing
        }
        retakeConfig.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        retakeButton.configuration = retakeConfig
        retakeButton.accessibilityLabel = "Retake quiz"
        retakeButton.translatesAutoresizingMaskIntoConstraints = false
        retakeButton.setContentHuggingPriority(.required, for: .horizontal)
        retakeButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        retakeButton.addAction(UIAction { [weak self] _ in
            self?.onRetake?()
        }, for: .touchUpInside)
        retakeButton.isHidden = true

        let stack = UIStackView(arrangedSubviews: [row, retakeButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            retakeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setProgress(completed: Bool, starCount: Int, lastPoints: Int?, showsRetake: Bool) {
        row.setProgress(completed: completed, starCount: starCount, lastPoints: lastPoints)
        retakeButton.isHidden = !showsRetake
    }
}

/// Card-style row: number badge, title/subtitle, best stars, last score, and chevron.
private final class LessonScenarioRowControl: UIControl {

    private static let badgeDiameter: CGFloat = 34

    private let titleText: String
    private let badgeContainer = UIView()
    private let badgeLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let starsView = DialogueScenarioStarsView()
    private let scoreLabel = UILabel()

    init(index: Int, title: String, subtitle: String?) {
        titleText = title
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        backgroundColor = ExperimentPalette.cardSurface
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.borderWidth = ExperimentCardStroke.normalWidth
        layer.borderColor = ExperimentPalette.cardBorder.cgColor

        badgeContainer.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.backgroundColor = ExperimentPalette.pageBackground
        badgeContainer.layer.cornerRadius = Self.badgeDiameter / 2
        badgeContainer.isUserInteractionEnabled = false

        badgeLabel.text = "\(index)"
        badgeLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        badgeLabel.textColor = .secondaryLabel
        badgeLabel.textAlignment = .center
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.addSubview(badgeLabel)

        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        subtitleLabel.text = subtitle
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0
        subtitleLabel.isHidden = (subtitle ?? "").isEmpty

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 3
        textStack.isUserInteractionEnabled = false
        textStack.translatesAutoresizingMaskIntoConstraints = false

        starsView.setContentHuggingPriority(.required, for: .horizontal)
        starsView.setContentCompressionResistancePriority(.required, for: .horizontal)

        scoreLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        scoreLabel.textColor = .secondaryLabel
        scoreLabel.textAlignment = .right
        scoreLabel.isHidden = true
        scoreLabel.setContentHuggingPriority(.required, for: .horizontal)
        scoreLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let gradeStack = UIStackView(arrangedSubviews: [starsView, scoreLabel])
        gradeStack.axis = .vertical
        gradeStack.alignment = .trailing
        gradeStack.spacing = 2
        gradeStack.isUserInteractionEnabled = false

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.translatesAutoresizingMaskIntoConstraints = false

        let trailingStack = UIStackView(arrangedSubviews: [gradeStack, chevron])
        trailingStack.axis = .horizontal
        trailingStack.alignment = .center
        trailingStack.spacing = 8
        trailingStack.isUserInteractionEnabled = false
        trailingStack.setContentHuggingPriority(.required, for: .horizontal)
        trailingStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        let rowStack = UIStackView(arrangedSubviews: [badgeContainer, textStack, trailingStack])
        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 14
        rowStack.isUserInteractionEnabled = false
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowStack)

        NSLayoutConstraint.activate([
            badgeContainer.widthAnchor.constraint(equalToConstant: Self.badgeDiameter),
            badgeContainer.heightAnchor.constraint(equalToConstant: Self.badgeDiameter),
            badgeLabel.centerXAnchor.constraint(equalTo: badgeContainer.centerXAnchor),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor),

            rowStack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setProgress(completed: Bool, starCount: Int, lastPoints: Int?) {
        badgeLabel.isHidden = false
        badgeContainer.backgroundColor = ExperimentPalette.pageBackground
        starsView.configure(earned: starCount, maximum: DialogueScoreRules.maxStars)
        if let lastPoints {
            scoreLabel.text = "\(lastPoints)"
            scoreLabel.isHidden = false
        } else {
            scoreLabel.isHidden = true
        }

        var label = titleText
        if completed {
            label += ", View lesson"
        }
        if completed || starCount > 0 {
            label += ", \(starCount) of \(DialogueScoreRules.maxStars) stars"
        }
        if let lastPoints {
            label += ", \(lastPoints) points"
        }
        accessibilityLabel = label
    }

    override var isHighlighted: Bool {
        didSet {
            guard oldValue != isHighlighted else { return }
            let highlighted = isHighlighted
            UIViewPropertyAnimator(duration: 0.2, dampingRatio: 0.7) { [weak self] in
                self?.backgroundColor = highlighted
                    ? Self.pressedCardSurface
                    : ExperimentPalette.cardSurface
            }.startAnimation()
        }
    }

    private static let pressedCardSurface = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .tertiarySystemGroupedBackground
            : UIColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            layer.borderColor = ExperimentPalette.cardBorder.cgColor
        }
    }
}

/// Compact best-run grade used on scenario picker rows.
private final class DialogueScenarioStarsView: UIView {

    private static let pointSize: CGFloat = 15
    private static let spacing: CGFloat = 2
    private static let fillColor = UIColor(red: 253 / 255, green: 200 / 255, blue: 1 / 255, alpha: 1)
    private static let emptyColor = UIColor.tertiaryLabel

    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        isAccessibilityElement = false

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
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(earned: Int, maximum: Int) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: Self.pointSize, weight: .semibold)
        let clampedEarned = min(max(earned, 0), maximum)
        for index in 0..<maximum {
            let imageView = UIImageView(
                image: UIImage(systemName: "star.fill", withConfiguration: symbolConfig)
            )
            imageView.tintColor = index < clampedEarned ? Self.fillColor : Self.emptyColor
            imageView.contentMode = .scaleAspectFit
            imageView.setContentHuggingPriority(.required, for: .horizontal)
            imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
            stack.addArrangedSubview(imageView)
        }
    }
}
