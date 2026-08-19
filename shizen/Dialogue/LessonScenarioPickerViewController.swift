//
//  LessonScenarioPickerViewController.swift
//  shizen
//
//  Intermediate screen between the lesson grid and the dialogue player:
//  shows every scenario in a lesson with its completion state so the user
//  picks exactly which conversation to tackle next.
//

import UIKit

final class LessonScenarioPickerViewController: UIViewController {

    private let collectionID: String
    private let fallbackTitle: String?
    private var collection: DialogueScenarioCollection?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let loadingCoordinator = DialogueLessonLoadingCoordinator()
    private var scenarioRows: [LessonScenarioRowControl] = []

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
            DialogueScenarioCollectionCatalog.fetchCollection(id: collectionID) { [weak self] collection in
                guard let self else { return }
                self.loadingCoordinator.finishLoading { [weak self] in
                    guard let self else { return }
                    if let collection {
                        self.applyCollection(collection)
                    } else {
                        self.showLoadFailure()
                    }
                }
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

        for row in scenarioRows {
            contentStack.removeArrangedSubview(row)
            row.removeFromSuperview()
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
            let row = LessonScenarioRowControl(
                index: index + 1,
                title: scenario.menuTitle,
                subtitle: scenario.menuSubtitle
            )
            row.addAction(UIAction { [weak self] _ in
                self?.openScenario(id: scenario.id)
            }, for: .touchUpInside)
            contentStack.addArrangedSubview(row)
            scenarioRows.append(row)
        }

        refreshCompletionStates()
    }

    private func refreshCompletionStates() {
        guard let collection else { return }
        let store = DialogueProgressStore.shared
        for (row, scenario) in zip(scenarioRows, collection.scenarios) {
            row.setCompleted(store.isCompleted(scenarioID: scenario.id))
        }
    }

    private func showLoadFailure() {
        let alert = UIAlertController(
            title: "Couldn’t load lesson",
            message: "Failed to fetch “\(collectionID)”.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    private func openScenario(id: String) {
        guard let collection else { return }
        let dialogue = DialogueNestedPagingExperimentViewController(
            collection: collection,
            initialScenarioID: id
        )
        navigationController?.pushViewController(dialogue, animated: true)
    }
}

// MARK: - Scenario row

/// Card-style row: number badge (or completion checkmark), title/subtitle, chevron.
private final class LessonScenarioRowControl: UIControl {

    private static let badgeDiameter: CGFloat = 34

    private let badgeContainer = UIView()
    private let badgeLabel = UILabel()
    private let checkmarkView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    init(index: Int, title: String, subtitle: String?) {
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

        checkmarkView.image = UIImage(systemName: "checkmark.circle.fill")
        checkmarkView.tintColor = .systemGreen
        checkmarkView.contentMode = .scaleAspectFit
        checkmarkView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 26, weight: .medium)
        checkmarkView.isHidden = true
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.addSubview(checkmarkView)

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

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.translatesAutoresizingMaskIntoConstraints = false

        let rowStack = UIStackView(arrangedSubviews: [badgeContainer, textStack, chevron])
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
            checkmarkView.centerXAnchor.constraint(equalTo: badgeContainer.centerXAnchor),
            checkmarkView.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor),

            rowStack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setCompleted(_ completed: Bool) {
        checkmarkView.isHidden = !completed
        badgeLabel.isHidden = completed
        badgeContainer.backgroundColor = completed ? .clear : ExperimentPalette.pageBackground
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
