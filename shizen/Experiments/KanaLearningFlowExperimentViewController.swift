//
//  KanaLearningFlowExperimentViewController.swift
//  shizen
//
//  DEBUG experiment: hiragana/katakana learning hub with progress tiles and row lessons.
//

import UIKit

final class KanaLearningFlowExperimentViewController: UIViewController {

    private enum ScriptItem: Int, CaseIterable {
        case hiragana
        case katakana

        var script: KanaScript {
            switch self {
            case .hiragana: return .hiragana
            case .katakana: return .katakana
            }
        }
    }

    private let hiraganaProgressStore: KanaProgressStore
    private let katakanaProgressStore: KanaProgressStore
    private var activeScript: KanaScript = .hiragana
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let scriptControl = UISegmentedControl(items: ["Hiragana", "Katakana"])
    private let progressCollectionView: UICollectionView
    private let reviewRowControl = UIControl()
    private let reviewTitleLabel = UILabel()
    private let reviewSubtitleLabel = UILabel()
    private let reviewIconView = UIImageView()
    private let reviewChevronView = UIImageView()
    private var lessonsContainer = UIView()
    private var lessonsViewController: KanaProgressPathViewController!
    private var lessonsHeightConstraint: NSLayoutConstraint?
    private var progressHeightConstraint: NSLayoutConstraint?
    private var activeLessonCoordinator: KanaLessonCoordinator?
    private var lastLaidOutCollectionWidth: CGFloat = 0
    private var lessonsViewConstraints: [NSLayoutConstraint] = []

    private static let gridSpacing: CGFloat = 4
    private static let cardHorizontalInset: CGFloat = 12
    private static let interCellSpacing: CGFloat = 10
    private static let horizontalInset: CGFloat = 16
    private static let cardHeaderTopInset: CGFloat = 10
    private static let cardTitleToGridSpacing: CGFloat = 8
    private static let cardBottomInset: CGFloat = 12
    private static let cardTitleHeight: CGFloat = 18

    private var activeProgressStore: KanaProgressStore {
        activeScript == .hiragana ? hiraganaProgressStore : katakanaProgressStore
    }

    init(
        hiraganaProgressStore: KanaProgressStore = .shared,
        katakanaProgressStore: KanaProgressStore = .katakanaShared
    ) {
        self.hiraganaProgressStore = hiraganaProgressStore
        self.katakanaProgressStore = katakanaProgressStore
        self.progressCollectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewLayout())
        super.init(nibName: nil, bundle: nil)
        self.progressCollectionView.collectionViewLayout = makeProgressLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground

        configureScrollView()
        configureProgressSection()
        configureReviewSection()
        configureLessonsSection()
        layoutViews()
        updateReviewRow()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hiraganaProgressStore.reload()
        katakanaProgressStore.reload()
        progressCollectionView.reloadData()
        updateReviewRow()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = progressCollectionView.bounds.width
        guard width > 0 else { return }

        updateProgressCollectionHeight()

        guard width != lastLaidOutCollectionWidth else { return }
        lastLaidOutCollectionWidth = width
        progressCollectionView.collectionViewLayout.invalidateLayout()
        progressCollectionView.reloadData()
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

    private func configureProgressSection() {
        let header = makeSectionHeader(
            title: "Progress",
            subtitle: "Gotta Learn 'Em All!"
        )

        progressCollectionView.translatesAutoresizingMaskIntoConstraints = false
        progressCollectionView.backgroundColor = .clear
        progressCollectionView.dataSource = self
        progressCollectionView.delegate = self
        progressCollectionView.isScrollEnabled = false
        progressCollectionView.register(
            KanaProgressGridCell.self,
            forCellWithReuseIdentifier: KanaProgressGridCell.reuseID
        )

        let progressStack = UIStackView(arrangedSubviews: [header, progressCollectionView])
        progressStack.axis = .vertical
        progressStack.spacing = 12
        progressStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(progressStack)
        contentStack.setCustomSpacing(12, after: progressStack)

        let height = progressCollectionView.heightAnchor.constraint(
            equalToConstant: progressCollectionHeight(
                forCollectionWidth: max(view.bounds.width - Self.horizontalInset * 2, 0)
            )
        )
        height.isActive = true
        progressHeightConstraint = height
    }

    private func configureReviewSection() {
        reviewRowControl.translatesAutoresizingMaskIntoConstraints = false
        reviewRowControl.backgroundColor = ExperimentPalette.cardSurface
        reviewRowControl.layer.cornerRadius = 10
        reviewRowControl.layer.cornerCurve = .continuous
        reviewRowControl.clipsToBounds = true
        reviewRowControl.addAction(UIAction { [weak self] _ in
            self?.startReviewIfAvailable()
        }, for: .touchUpInside)

        reviewIconView.translatesAutoresizingMaskIntoConstraints = false
        reviewIconView.image = UIImage(systemName: "arrow.clockwise")
        reviewIconView.tintColor = .secondaryLabel
        reviewIconView.contentMode = .scaleAspectFit
        reviewIconView.isUserInteractionEnabled = false

        reviewTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        reviewTitleLabel.font = .preferredFont(forTextStyle: .body)
        reviewTitleLabel.text = "Start a review"
        reviewTitleLabel.isUserInteractionEnabled = false

        reviewSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        reviewSubtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        reviewSubtitleLabel.textColor = .secondaryLabel
        reviewSubtitleLabel.numberOfLines = 0
        reviewSubtitleLabel.isUserInteractionEnabled = false

        reviewChevronView.translatesAutoresizingMaskIntoConstraints = false
        reviewChevronView.image = UIImage(systemName: "chevron.right")
        reviewChevronView.tintColor = .tertiaryLabel
        reviewChevronView.contentMode = .scaleAspectFit
        reviewChevronView.isUserInteractionEnabled = false

        reviewRowControl.addSubview(reviewIconView)
        reviewRowControl.addSubview(reviewTitleLabel)
        reviewRowControl.addSubview(reviewSubtitleLabel)
        reviewRowControl.addSubview(reviewChevronView)

        NSLayoutConstraint.activate([
            reviewRowControl.heightAnchor.constraint(greaterThanOrEqualToConstant: 58),

            reviewIconView.leadingAnchor.constraint(equalTo: reviewRowControl.leadingAnchor, constant: 16),
            reviewIconView.centerYAnchor.constraint(equalTo: reviewRowControl.centerYAnchor),
            reviewIconView.widthAnchor.constraint(equalToConstant: 28),
            reviewIconView.heightAnchor.constraint(equalToConstant: 28),

            reviewTitleLabel.topAnchor.constraint(equalTo: reviewRowControl.topAnchor, constant: 10),
            reviewTitleLabel.leadingAnchor.constraint(equalTo: reviewIconView.trailingAnchor, constant: 12),
            reviewTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: reviewChevronView.leadingAnchor, constant: -8),

            reviewSubtitleLabel.topAnchor.constraint(equalTo: reviewTitleLabel.bottomAnchor, constant: 2),
            reviewSubtitleLabel.leadingAnchor.constraint(equalTo: reviewTitleLabel.leadingAnchor),
            reviewSubtitleLabel.trailingAnchor.constraint(equalTo: reviewTitleLabel.trailingAnchor),
            reviewSubtitleLabel.bottomAnchor.constraint(equalTo: reviewRowControl.bottomAnchor, constant: -10),

            reviewChevronView.trailingAnchor.constraint(equalTo: reviewRowControl.trailingAnchor, constant: -16),
            reviewChevronView.centerYAnchor.constraint(equalTo: reviewRowControl.centerYAnchor),
            reviewChevronView.widthAnchor.constraint(equalToConstant: 8),
            reviewChevronView.heightAnchor.constraint(equalToConstant: 13),
        ])

        contentStack.addArrangedSubview(reviewRowControl)
    }

    private func configureLessonsSection() {
        let header = makeSectionHeader(title: "Lessons")

        scriptControl.selectedSegmentIndex = activeScript == .hiragana ? 0 : 1
        scriptControl.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.activeScript = self.scriptControl.selectedSegmentIndex == 0 ? .hiragana : .katakana
            self.replaceLessonsViewController()
            self.updateReviewRow()
        }, for: .valueChanged)

        lessonsContainer.translatesAutoresizingMaskIntoConstraints = false

        let rows = KanaCurriculum.seionLessonRows(script: activeScript)
        let height = lessonsContainer.heightAnchor.constraint(
            equalToConstant: KanaProgressPathViewController.estimatedEmbeddedListHeight(rowCount: rows.count)
        )
        height.isActive = true
        lessonsHeightConstraint = height

        replaceLessonsViewController()

        let lessonsStack = UIStackView(arrangedSubviews: [header, scriptControl, lessonsContainer])
        lessonsStack.axis = .vertical
        lessonsStack.spacing = 8
        lessonsStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(lessonsStack)
    }

    private func replaceLessonsViewController() {
        if let existing = self.lessonsViewController {
            existing.willMove(toParent: nil)
            existing.view.removeFromSuperview()
            existing.removeFromParent()
        }

        let rows = KanaCurriculum.seionLessonRows(script: activeScript)
        lessonsHeightConstraint?.constant = KanaProgressPathViewController.estimatedEmbeddedListHeight(rowCount: rows.count)

        let child = KanaProgressPathViewController(
            progressStore: activeProgressStore,
            rows: rows,
            script: activeScript,
            presentationStyle: .embeddedLessonsOnly
        )
        child.onEmbeddedHeightChange = { [weak self] height in
            self?.updateLessonsHeight(height)
        }
        child.onProgressDidChange = { [weak self] in
            guard let self else { return }
            self.activeProgressStore.reload()
            self.progressCollectionView.reloadData()
            self.updateReviewRow()
        }

        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        lessonsContainer.addSubview(child.view)
        child.didMove(toParent: self)
        lessonsViewController = child

        NSLayoutConstraint.deactivate(lessonsViewConstraints)
        lessonsViewConstraints = [
            child.view.topAnchor.constraint(equalTo: lessonsContainer.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: lessonsContainer.bottomAnchor),
            child.view.leadingAnchor.constraint(
                equalTo: lessonsContainer.leadingAnchor,
                constant: -Self.horizontalInset
            ),
            child.view.trailingAnchor.constraint(
                equalTo: lessonsContainer.trailingAnchor,
                constant: Self.horizontalInset
            ),
        ]
        NSLayoutConstraint.activate(lessonsViewConstraints)
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
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: inset),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -inset),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -inset * 2),
        ])
    }

    private func makeSectionHeader(title: String, subtitle: String? = nil) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)

        var arrangedSubviews: [UIView] = [titleLabel]

        if let subtitle {
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
        return stack
    }

    private func updateReviewRow() {
        let dueCount = activeProgressStore.dueGlyphCount
        reviewSubtitleLabel.text = dueCount > 0
            ? "\(dueCount) \(activeScript.displayName) character\(dueCount == 1 ? "" : "s") due"
            : "Nothing due right now"
        reviewRowControl.isEnabled = dueCount > 0
        reviewRowControl.alpha = dueCount > 0 ? 1 : 0.55
        reviewChevronView.isHidden = dueCount == 0
    }

    private func startReviewIfAvailable() {
        guard activeProgressStore.dueGlyphCount > 0 else { return }
        let coordinator = KanaLessonCoordinator(
            kind: .srsReview,
            row: nil,
            progressStore: activeProgressStore
        )
        coordinator.delegate = self
        activeLessonCoordinator = coordinator
        coordinator.present(from: self)
    }

    private func updateLessonsHeight(_ height: CGFloat) {
        let resolved = max(ceil(height), 1)
        guard abs((lessonsHeightConstraint?.constant ?? 0) - resolved) > 0.5 else { return }
        lessonsHeightConstraint?.constant = resolved
    }

    private func updateProgressCollectionHeight() {
        let height = progressCollectionHeight(forCollectionWidth: progressCollectionView.bounds.width)
        guard progressHeightConstraint?.constant != height else { return }
        progressHeightConstraint?.constant = height
    }

    // MARK: - Progress grid metrics

    private func itemWidth(forCollectionWidth totalWidth: CGFloat) -> CGFloat {
        guard totalWidth > 0 else { return 0 }
        let available = totalWidth - Self.interCellSpacing
        return floor(max(available, 0) / 2)
    }

    private func gridWidth(forCollectionWidth totalWidth: CGFloat) -> CGFloat {
        max(0, itemWidth(forCollectionWidth: totalWidth) - Self.cardHorizontalInset * 2)
    }

    private func cellHeight(for itemWidth: CGFloat) -> CGFloat {
        guard itemWidth > 0 else { return 1 }
        let gridWidth = itemWidth - Self.cardHorizontalInset * 2
        let gridHeight = KanaProgressGridView.gridHeight(
            forGridWidth: gridWidth,
            spacing: Self.gridSpacing,
            glyphCount: KanaProgressSquareStyle.glyphCount
        )
        let cardChrome = Self.cardHeaderTopInset
            + Self.cardTitleHeight
            + Self.cardTitleToGridSpacing
            + Self.cardBottomInset
        return cardChrome + gridHeight
    }

    private func progressCollectionHeight(forCollectionWidth totalWidth: CGFloat) -> CGFloat {
        cellHeight(for: itemWidth(forCollectionWidth: totalWidth))
    }

    private func makeProgressLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] _, environment in
            guard let self else { return nil }

            let totalWidth = environment.container.effectiveContentSize.width
            guard totalWidth > 0 else {
                let emptyItem = NSCollectionLayoutItem(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(0.5),
                        heightDimension: .absolute(1)
                    )
                )
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1),
                        heightDimension: .absolute(1)
                    ),
                    subitems: [emptyItem, emptyItem]
                )
                return NSCollectionLayoutSection(group: group)
            }

            let itemWidth = self.itemWidth(forCollectionWidth: totalWidth)
            let itemHeight = self.cellHeight(for: itemWidth)

            let itemSize = NSCollectionLayoutSize(
                widthDimension: .absolute(itemWidth),
                heightDimension: .absolute(itemHeight)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(itemHeight)
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item, item])
            group.interItemSpacing = .fixed(Self.interCellSpacing)

            return NSCollectionLayoutSection(group: group)
        }
    }

    // MARK: - Navigation

    private func openChart(for script: KanaScript) {
        let store = script == .hiragana ? hiraganaProgressStore : katakanaProgressStore
        navigationController?.pushViewController(
            KanaLearningChartViewController(progressStore: store, script: script),
            animated: true
        )
    }
}

// MARK: - Progress collection

extension KanaLearningFlowExperimentViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        ScriptItem.allCases.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: KanaProgressGridCell.reuseID,
            for: indexPath
        ) as! KanaProgressGridCell

        let item = ScriptItem.allCases[indexPath.item]
        let glyphs = KanaCurriculum.progressGridGlyphs(script: item.script)
        let gridWidth = gridWidth(forCollectionWidth: collectionView.bounds.width)
        cell.configure(
            script: item.script,
            glyphs: glyphs,
            studyCounts: KanaProgressGridSupport.studyCounts(
                for: glyphs,
                progressStore: item.script == .hiragana ? hiraganaProgressStore : katakanaProgressStore
            ),
            spacing: Self.gridSpacing,
            gridWidth: gridWidth,
            showsChevron: true
        )
        return cell
    }
}

extension KanaLearningFlowExperimentViewController: UICollectionViewDelegate {

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        (cell as? KanaProgressGridCell)?.applyGridWidth(gridWidth(forCollectionWidth: collectionView.bounds.width))
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = ScriptItem(rawValue: indexPath.item) else { return }
        openChart(for: item.script)
    }
}

// MARK: - KanaLessonSessionDelegate

extension KanaLearningFlowExperimentViewController: KanaLessonSessionDelegate {
    func kanaLessonSessionDidFinish(kind: KanaSessionKind, row: KanaRow?, metrics: KanaLessonSessionMetrics) {
        activeLessonCoordinator = nil
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.hiraganaProgressStore.reload()
            self.katakanaProgressStore.reload()
            self.progressCollectionView.reloadData()
            self.updateReviewRow()
        }
    }

    func kanaLessonSessionDidFail(kind: KanaSessionKind, row: KanaRow?, metrics: KanaLessonSessionMetrics) {
        activeLessonCoordinator = nil
        dismiss(animated: true)
    }

    func kanaLessonSessionDidCancel(kind: KanaSessionKind, row: KanaRow?) {
        activeLessonCoordinator = nil
        dismiss(animated: true)
    }
}

// MARK: - MainTabScrollable

extension KanaLearningFlowExperimentViewController: MainTabScrollable {
    var mainTabScrollViews: [UIScrollView] { [scrollView] }
}
