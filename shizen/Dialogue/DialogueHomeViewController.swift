//
//  DialogueHomeViewController.swift
//  shizen
//
//  Dialogue tab: Daily Dialogue consistency card (GitHub-contribution style,
//  21-day rolling window) followed by a waterfall grid of lesson cards.
//

import UIKit

final class DialogueHomeViewController: UIViewController, MainTabScrollable {

    var mainTabScrollViews: [UIScrollView] { [scrollView] }

    private let progressStore: DialogueProgressStore
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let dailyDialogueCard = DailyDialogueCardView()
    /// Holds the "Lessons" header plus one (header + grid) block per unit.
    private let lessonSectionsStack = UIStackView()
    private var sectionGridControllers: [LessonWaterfallGridController] = []

    private static let horizontalInset: CGFloat = 16

    /// Hard-coded home grid until full lesson sets are served from the CDN.
    /// Includes locked placeholders so the waterfall still feels populated.
    private static let curatedLessons: [WaterfallLesson] = [
        WaterfallLesson(
            id: "train-station",
            title: "At the Train Station",
            conversationCount: 5,
            thumbnailName: "train-station",
            isLocked: false
        ),
        WaterfallLesson(
            id: nil,
            title: "At the Library",
            conversationCount: 5,
            thumbnailName: "at-the-library",
            isLocked: false
        ),
        WaterfallLesson(
            id: nil,
            title: "At the Convenient Store",
            conversationCount: 5,
            thumbnailName: "at-the-convenient-store",
            isLocked: true
        ),
        WaterfallLesson(
            id: nil,
            title: "Asking Directions",
            conversationCount: 5,
            thumbnailName: "asking-directions",
            isLocked: true
        ),
    ]

    init(progressStore: DialogueProgressStore = .shared) {
        self.progressStore = progressStore
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground
        configureScrollView()
        configureDailyDialogueSection()
        configureLessonsSection()
        layoutViews()
        refreshDailyDialogueCard()
        fetchCMSLessons()

        if #available(iOS 26.0, *) {
            scrollView.topEdgeEffect.style = .soft
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        progressStore.reload()
        refreshDailyDialogueCard()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        for controller in sectionGridControllers {
            controller.refreshContentHeightIfNeeded()
        }
    }

    // MARK: - Layout

    private func configureScrollView() {
        scrollView.alwaysBounceVertical = true
        scrollView.backgroundColor = ExperimentPalette.pageBackground
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 24
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
    }

    private func configureDailyDialogueSection() {
        dailyDialogueCard.translatesAutoresizingMaskIntoConstraints = false
        dailyDialogueCard.onStartTapped = { [weak self] in
            self?.startTodaysDialogue()
        }
        contentStack.addArrangedSubview(dailyDialogueCard)
    }

    private func configureLessonsSection() {
        lessonSectionsStack.axis = .vertical
        lessonSectionsStack.spacing = 12
        lessonSectionsStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(lessonSectionsStack)

        // Curated fallback shows immediately; CMS units replace it when fetched.
        renderLessonSections([
            LessonUnitSection(title: nil, subtitle: nil, lessons: Self.curatedLessons)
        ])
    }

    /// Rebuilds the lessons area: top-level "Lessons" header, then one
    /// sub-header + waterfall grid per curriculum unit.
    private func renderLessonSections(_ sections: [LessonUnitSection]) {
        for view in lessonSectionsStack.arrangedSubviews {
            lessonSectionsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        sectionGridControllers = []

        let header = makeSectionHeader(
            title: "Lessons",
            subtitle: "Curated dialogue, vocab, grammar"
        )
        lessonSectionsStack.addArrangedSubview(header)

        for section in sections {
            if let title = section.title {
                if let previous = lessonSectionsStack.arrangedSubviews.last {
                    lessonSectionsStack.setCustomSpacing(20, after: previous)
                }
                let unitHeader = makeSectionHeader(title: title, subtitle: section.subtitle)
                lessonSectionsStack.addArrangedSubview(unitHeader)
            }

            let gridController = LessonWaterfallGridController()
            let collectionView = gridController.collectionView
            collectionView.translatesAutoresizingMaskIntoConstraints = false
            collectionView.isScrollEnabled = false
            collectionView.clipsToBounds = false

            let heightConstraint = collectionView.heightAnchor.constraint(equalToConstant: 1)
            heightConstraint.isActive = true
            gridController.onContentHeightChanged = { height in
                heightConstraint.constant = height
            }
            gridController.onSelect = { [weak self] _, lesson in
                self?.openLesson(lesson)
            }

            lessonSectionsStack.addArrangedSubview(collectionView)
            sectionGridControllers.append(gridController)
            gridController.setLessons(section.lessons)
        }
    }

    private func fetchCMSLessons() {
        guard ContentCMSClient.isConfigured else { return }
        ContentCMSClient.fetchDialogueLessonIndex { [weak self] result in
            DispatchQueue.main.async {
                guard let self,
                      case .success(let index) = result,
                      !index.lessons.isEmpty
                else { return }
                self.renderLessonSections(LessonUnitSectionBuilder.sections(from: index))
            }
        }
    }

    private func layoutViews() {
        view.addSubview(scrollView)
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

    private func makeSectionHeader(title: String, subtitle: String?) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .label

        var arrangedSubviews: [UIView] = [titleLabel]
        if let subtitle, !subtitle.isEmpty {
            let subtitleLabel = UILabel()
            subtitleLabel.text = subtitle
            subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
            subtitleLabel.textColor = .secondaryLabel
            subtitleLabel.numberOfLines = 0
            arrangedSubviews.append(subtitleLabel)
        }

        let stack = UIStackView(arrangedSubviews: arrangedSubviews)
        stack.axis = .vertical
        stack.spacing = 4
        // Match the leading edge of content inside the Daily Dialogue card (18pt inset).
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 0)
        return stack
    }

    // MARK: - Data

    private func refreshDailyDialogueCard() {
        let dayKeys = DialogueProgressGridSupport.recentDayKeys()
        dailyDialogueCard.configure(
            dayKeys: dayKeys,
            completedCounts: DialogueProgressGridSupport.completedCounts(
                for: dayKeys,
                progressStore: progressStore
            )
        )
    }

    // MARK: - Navigation

    private func startTodaysDialogue() {
        let dialogue = DialogueNestedPagingExperimentViewController(
            collectionID: DialogueScenarioCollectionCatalog.trainStationID,
            prefersNextIncompleteScenario: true
        )
        navigationController?.pushViewController(dialogue, animated: true)
    }

    private func openLesson(_ lesson: WaterfallLesson) {
        if lesson.isLocked { return }
        let id: String
        if let lessonID = lesson.id {
            id = lessonID
        } else if lesson.thumbnailName == "train-station" {
            id = DialogueScenarioCollectionCatalog.trainStationID
        } else {
            return
        }
        let picker = LessonScenarioPickerViewController(collectionID: id, fallbackTitle: lesson.title)
        navigationController?.pushViewController(picker, animated: true)
    }
}

// MARK: - Daily Dialogue card

/// "Daily Dialogue" card: title/subtitle, GitHub-contribution style consistency
/// grid, and a Start button that launches today's scenario. Built from two
/// vertical stacks (text column, grid column) inside a horizontal stack, plus
/// the button below — plain UIStackView layout, no custom width math.
private final class DailyDialogueCardView: UIView {

    var onStartTapped: (() -> Void)?

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let gridView = DialogueProgressGridView()
    private let startButton = UIButton(type: .system)

    /// Fixed square geometry — the grid renders at a constant pixel size, so no
    /// runtime width measurement or constraint mutation is needed.
    private static let squareSide: CGFloat = 18
    private static let squareSpacing: CGFloat = 4
    private static let columns = 7
    private static var gridSize: CGSize {
        let rows = Int(ceil(Double(DialogueProgressGridLayout.dayCount) / Double(columns)))
        let width = CGFloat(columns) * squareSide + CGFloat(columns - 1) * squareSpacing
        let height = CGFloat(rows) * squareSide + CGFloat(rows - 1) * squareSpacing
        return CGSize(width: width, height: height)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = ExperimentPalette.cardSurface
        cardView.layer.cornerRadius = 22
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = ExperimentCardStroke.normalWidth
        cardView.layer.borderColor = ExperimentPalette.cardBorder.cgColor

        titleLabel.text = "Daily Dialogue"
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        subtitleLabel.text = "Listen, comprehend, understand, learn. Come back everyday for a new test."
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        // Left column: title + subtitle, pinned edge-to-edge so they wrap within this column's width.
        let textColumn = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textColumn.axis = .vertical
        textColumn.spacing = 6
        textColumn.translatesAutoresizingMaskIntoConstraints = false

        let gridWidth = Self.gridSize.width
        let gridHeight = Self.gridSize.height
        gridView.translatesAutoresizingMaskIntoConstraints = false
        gridView.layoutWidth = gridWidth
        gridView.layoutMetrics = DialogueProgressGridLayout.Metrics(
            columnCount: Self.columns,
            spacing: Self.squareSpacing,
            squareSide: Self.squareSide,
            gridWidth: gridWidth,
            gridHeight: gridHeight
        )

        var buttonConfig = UIButton.Configuration.filled()
        buttonConfig.title = "Start"
        buttonConfig.baseBackgroundColor = Colors.brandYellow
        buttonConfig.baseForegroundColor = Colors.textYellow
        buttonConfig.cornerStyle = .capsule
        buttonConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 15, weight: .bold)
            return outgoing
        }
        startButton.configuration = buttonConfig
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.addTarget(self, action: #selector(handleStartTapped), for: .touchUpInside)

        // Right column: grid + Start button, both pinned edge-to-edge so the
        // button matches the grid's exact width.
        let gridColumn = UIStackView(arrangedSubviews: [gridView, startButton])
        gridColumn.axis = .vertical
        gridColumn.spacing = 12
        gridColumn.alignment = .fill
        gridColumn.translatesAutoresizingMaskIntoConstraints = false

        let rowStack = UIStackView(arrangedSubviews: [textColumn, gridColumn])
        rowStack.axis = .horizontal
        rowStack.alignment = .top
        rowStack.spacing = 12
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(cardView)
        cardView.addSubview(rowStack)

        textColumn.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textColumn.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        gridColumn.setContentHuggingPriority(.required, for: .horizontal)
        gridColumn.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),

            rowStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 18),
            rowStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            rowStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),
            rowStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -18),

            gridView.widthAnchor.constraint(equalToConstant: gridWidth),
            gridView.heightAnchor.constraint(equalToConstant: gridHeight),
            startButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            cardView.layer.borderColor = ExperimentPalette.cardBorder.cgColor
        }
    }

    @objc private func handleStartTapped() {
        onStartTapped?()
    }

    func configure(dayKeys: [String], completedCounts: [String: Int]) {
        gridView.dayKeys = dayKeys
        gridView.completedCounts = completedCounts
    }
}
