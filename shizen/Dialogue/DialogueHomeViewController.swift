//
//  DialogueHomeViewController.swift
//  shizen
//
//  Dialogue tab: left-aligned lesson sine path. Daily Dialogue lives on Practice.
//

import UIKit

final class DialogueHomeViewController: UIViewController, MainTabScrollable {

    var mainTabScrollViews: [UIScrollView] { [lessonPathController.pathScrollView] }

    private let progressStore: LessonProgressProviding
    private let lessonPathController: LanguageProgressSnakeExperimentViewController
    private var latestIndex: CMSDialogueLessonIndex?
    private var progressObserver: NSObjectProtocol?
    private var didScrollToRealCurriculum = false
    private var pendingAnimatedScrollToCurrent = false

    init(progressStore: LessonProgressProviding = DialogueProgressStore.shared) {
        self.progressStore = progressStore
        self.lessonPathController = LanguageProgressSnakeExperimentViewController(
            units: PathUnit.sampleCurriculum,
            showsTuningControls: false,
            managesContentInsets: false,
            style: .sineLeftAligned
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground
        configureLessonPath()
        observeProgressChanges()
        if let cached = ContentCMSClient.cachedDialogueLessonIndex(), !cached.lessons.isEmpty {
            latestIndex = cached
            rebuildPathUnits()
        }
        fetchCMSLessons()
        if !ContentCMSClient.isConfigured {
            lessonPathController.scrollToCurrentLesson(animated: false)
        }
    }

    deinit {
        if let progressObserver {
            NotificationCenter.default.removeObserver(progressObserver)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let store = progressStore as? DialogueProgressStore {
            store.reload()
        }
        rebuildPathUnits()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard pendingAnimatedScrollToCurrent else { return }
        pendingAnimatedScrollToCurrent = false
        lessonPathController.scrollToCurrentLesson(animated: true)
    }

    // MARK: - Layout

    private func configureLessonPath() {
        lessonPathController.onStartLesson = { [weak self] lesson in
            self?.openLesson(lesson)
        }

        addChild(lessonPathController)
        let pathView = lessonPathController.view!
        pathView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pathView)
        NSLayoutConstraint.activate([
            pathView.topAnchor.constraint(equalTo: view.topAnchor),
            pathView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pathView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pathView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        lessonPathController.didMove(toParent: self)
    }

    private func fetchCMSLessons() {
        guard ContentCMSClient.isConfigured else { return }
        ContentCMSClient.fetchDialogueLessonIndex { [weak self] result in
            DispatchQueue.main.async {
                guard let self,
                      case .success(let index) = result,
                      !index.lessons.isEmpty
                else { return }
                self.latestIndex = index
                self.rebuildPathUnits()
            }
        }
    }

    // MARK: - Data

    private func rebuildPathUnits() {
        guard let latestIndex else { return }
        let units = LessonUnitSectionBuilder.pathUnits(from: latestIndex, progress: progressStore)
        let nextTarget = PathUnit.initialIndexPath(in: units)
        if didScrollToRealCurriculum, nextTarget != lessonPathController.lastScrollTarget {
            pendingAnimatedScrollToCurrent = true
        }
        lessonPathController.setUnits(units)
        guard !didScrollToRealCurriculum else { return }
        didScrollToRealCurriculum = true
        lessonPathController.scrollToCurrentLesson(animated: false)
    }

    private func observeProgressChanges() {
        progressObserver = NotificationCenter.default.addObserver(
            forName: DialogueProgressStore.didChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildPathUnits()
        }
    }

    // MARK: - Navigation

    private func openLesson(_ lesson: PathLesson) {
        if lesson.state == .locked { return }
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
final class DailyDialogueCardView: UIView {

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

// MARK: - Daily Dialogue compact strip

private final class DailyDialogueCompactStripView: UIView {

    var onStartTapped: (() -> Void)?
    var onBodyTapped: (() -> Void)?

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    private let startButton = UIButton(type: .system)

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
        cardView.layer.cornerRadius = 16
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = ExperimentCardStroke.normalWidth
        cardView.layer.borderColor = ExperimentPalette.cardBorder.cgColor

        titleLabel.text = "Daily Dialogue"
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        countLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        countLabel.textColor = .secondaryLabel
        countLabel.setContentHuggingPriority(.required, for: .horizontal)

        var buttonConfig = UIButton.Configuration.filled()
        buttonConfig.title = "Start"
        buttonConfig.baseBackgroundColor = Colors.brandYellow
        buttonConfig.baseForegroundColor = Colors.textYellow
        buttonConfig.cornerStyle = .capsule
        buttonConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        buttonConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 13, weight: .bold)
            return outgoing
        }
        startButton.configuration = buttonConfig
        startButton.setContentHuggingPriority(.required, for: .horizontal)
        startButton.addTarget(self, action: #selector(handleStartTapped), for: .touchUpInside)

        let trailing = UIStackView(arrangedSubviews: [countLabel, startButton])
        trailing.axis = .horizontal
        trailing.alignment = .center
        trailing.spacing = 10

        let row = UIStackView(arrangedSubviews: [titleLabel, trailing])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        addSubview(cardView)
        cardView.addSubview(row)
        let bodyTap = UITapGestureRecognizer(target: self, action: #selector(handleBodyTapped))
        bodyTap.cancelsTouchesInView = false
        bodyTap.delegate = self
        addGestureRecognizer(bodyTap)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 48),

            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),

            row.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),
            row.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            startButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            cardView.layer.borderColor = ExperimentPalette.cardBorder.cgColor
        }
    }

    func configure(completedToday: Int, scenariosPerDay: Int) {
        countLabel.text = "\(completedToday)/\(scenariosPerDay) today"
    }

    @objc private func handleStartTapped() {
        onStartTapped?()
    }

    @objc private func handleBodyTapped() {
        onBodyTapped?()
    }
}

extension DailyDialogueCompactStripView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let view = touch.view else { return true }
        return !view.isDescendant(of: startButton)
    }
}
