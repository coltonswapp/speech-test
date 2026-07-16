//
//  KanaProgressPathViewController.swift
//  shizen
//
//  Row-by-row hiragana lessons in a standard grouped collection list.
//

import UIKit

final class KanaProgressPathViewController: UIViewController {

    enum PresentationStyle {
        case standalone
        case embeddedLessonsOnly
    }

    private enum Section: Int, CaseIterable {
        case tools = 0
        case rows = 1
    }

    private enum ItemID {
        static let chart = "tool.chart"
        static let srsReview = "tool.srsReview"

        static func row(_ row: KanaRow, state: KanaRowProgressState) -> String {
            "row|\(row.id)|\(stateToken(state))"
        }

        static func rowID(from itemID: String) -> String? {
            guard itemID.hasPrefix("row|") else { return nil }
            let parts = itemID.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count == 3 else { return nil }
            return String(parts[1])
        }

        private static func stateToken(_ state: KanaRowProgressState) -> String {
            switch state {
            case .locked: return "locked"
            case .available: return "available"
            case .lessonCompleted: return "lessonCompleted"
            case .completed: return "completed"
            }
        }
    }

    private let progressStore: KanaProgressStore
    private let rows: [KanaRow]
    private let script: KanaScript
    private let presentationStyle: PresentationStyle

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    /// Inset-grouped list sections draw rounded corners below the last item frame.
    private static let embeddedListBottomPadding: CGFloat = 20
    private var activeLessonCoordinator: KanaLessonCoordinator?
    var onEmbeddedHeightChange: ((CGFloat) -> Void)?
    var onProgressDidChange: (() -> Void)?

    /// Conservative sizing so embedded parents allocate enough height before the first layout pass.
    static func estimatedEmbeddedListHeight(rowCount: Int) -> CGFloat {
        let headerHeight: CGFloat = 60
        let rowHeight: CGFloat = 58
        return headerHeight + CGFloat(rowCount) * rowHeight + embeddedListBottomPadding
    }

    init(
        progressStore: KanaProgressStore = .shared,
        rows: [KanaRow] = KanaCurriculum.hiraganaSeionRows,
        script: KanaScript? = nil,
        presentationStyle: PresentationStyle = .standalone
    ) {
        self.progressStore = progressStore
        self.rows = rows
        self.script = script ?? rows.first?.script ?? .hiragana
        self.presentationStyle = presentationStyle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if presentationStyle == .standalone {
            title = script == .hiragana ? "Hiragana" : "Katakana"
        }
        view.backgroundColor = ExperimentPalette.pageBackground
        configureCollectionView()
        configureDataSource()
        reloadContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        progressStore.reload()
        reloadContent()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        reportEmbeddedHeightIfNeeded()
    }

    // MARK: - Collection view

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            guard let self else {
                return NSCollectionLayoutSection.list(
                    using: UICollectionLayoutListConfiguration(appearance: .insetGrouped),
                    layoutEnvironment: environment
                )
            }

            var listConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            listConfiguration.headerMode = sectionIndex == Section.rows.rawValue ? .supplementary : .none
            if self.presentationStyle == .embeddedLessonsOnly {
                listConfiguration.headerTopPadding = 0
            }

            return NSCollectionLayoutSection.list(
                using: listConfiguration,
                layoutEnvironment: environment
            )
        }

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.isScrollEnabled = presentationStyle == .standalone
        collectionView.backgroundColor = presentationStyle == .embeddedLessonsOnly
            ? .clear
            : ExperimentPalette.pageBackground
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, String> {
            [weak self] cell, _, itemID in
            self?.configure(cell: cell, for: itemID)
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            self?.configure(header: header, for: indexPath.section)
        }

        dataSource = UICollectionViewDiffableDataSource<Int, String>(
            collectionView: collectionView
        ) { (collectionView: UICollectionView, indexPath: IndexPath, itemID: String) in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: itemID)
        }

        dataSource.supplementaryViewProvider = {
            (collectionView: UICollectionView, kind: String, indexPath: IndexPath) -> UICollectionReusableView? in
            guard kind == UICollectionView.elementKindSectionHeader else { return nil }
            return collectionView.dequeueConfiguredReusableSupplementary(
                using: headerRegistration,
                for: indexPath
            )
        }
    }

    private func configure(cell: UICollectionViewListCell, for itemID: String) {
        var content = UIListContentConfiguration.subtitleCell()

        switch itemID {
        case ItemID.chart:
            content.text = "Learning chart"
            content.secondaryText = "Unlocked kana in color · locked kana greyed out"
            content.image = UIImage(systemName: "square.grid.3x3")
            cell.accessories = [.disclosureIndicator()]
            cell.isUserInteractionEnabled = true
            cell.alpha = 1

        case ItemID.srsReview:
            let dueCount = progressStore.dueGlyphCount
            content.text = "Start a review"
            content.secondaryText = dueCount > 0
                ? "\(dueCount) character\(dueCount == 1 ? "" : "s") due"
                : "Nothing due right now"
            content.image = UIImage(systemName: "arrow.clockwise")
            cell.accessories = dueCount > 0 ? [.disclosureIndicator()] : []
            cell.isUserInteractionEnabled = dueCount > 0
            cell.alpha = dueCount > 0 ? 1 : 0.55

        default:
            guard let rowID = ItemID.rowID(from: itemID), let row = row(for: rowID) else { return }
            let state = progressStore.rowState(row)
            content.text = row.displayName
            content.secondaryText = subtitle(for: row, state: state)
            content.image = rowIcon(for: state)
            content.imageProperties.tintColor = rowTint(for: state)

            let selectable = state != .locked
            cell.accessories = selectable ? [.disclosureIndicator()] : []
            cell.isUserInteractionEnabled = selectable
            cell.alpha = selectable ? 1 : 0.55
        }

        content.textProperties.numberOfLines = 1
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.backgroundConfiguration = UIBackgroundConfiguration.listGroupedCell()
    }

    private func configure(header: UICollectionViewListCell, for sectionIndex: Int) {
        guard sectionIndex == Section.rows.rawValue else { return }

        var content = UIListContentConfiguration.groupedHeader()
        let learned = progressStore.learnedGlyphCount(in: rows)
        let total = progressStore.totalGlyphCount(in: rows)
        content.text = "Seion rows"
        content.secondaryText = "\(learned) / \(total) learned"
        content.secondaryTextProperties.color = .secondaryLabel
        header.contentConfiguration = content
    }

    private func rowIcon(for state: KanaRowProgressState) -> UIImage? {
        switch state {
        case .locked:
            return UIImage(systemName: "lock.circle")
        case .available:
            return UIImage(systemName: "circle.inset.filled")
        case .lessonCompleted:
            return UIImage(systemName: "exclamationmark.circle.fill")
        case .completed:
            return UIImage(systemName: "checkmark.circle.fill")
        }
    }

    private func rowTint(for state: KanaRowProgressState) -> UIColor {
        switch state {
        case .locked:
            return .tertiaryLabel
        case .available:
            return UIColor(red: 0.45, green: 0.28, blue: 0.92, alpha: 1)
        case .lessonCompleted:
            return .systemOrange
        case .completed:
            return .systemGreen
        }
    }

    // MARK: - Data

    private func reloadContent() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()

        switch presentationStyle {
        case .standalone:
            snapshot.appendSections([Section.tools.rawValue, Section.rows.rawValue])
            snapshot.appendItems([ItemID.chart, ItemID.srsReview], toSection: Section.tools.rawValue)
        case .embeddedLessonsOnly:
            snapshot.appendSections([Section.rows.rawValue])
        }

        let rowItemIDs = rows.map { row in
            ItemID.row(row, state: progressStore.rowState(row))
        }
        snapshot.appendItems(rowItemIDs, toSection: Section.rows.rawValue)

        dataSource.apply(snapshot, animatingDifferences: view.window != nil) { [weak self] in
            self?.reportEmbeddedHeightIfNeeded()
        }
    }

    private func reportEmbeddedHeightIfNeeded() {
        guard presentationStyle == .embeddedLessonsOnly else { return }
        guard collectionView.bounds.width > 0 else { return }
        collectionView.layoutIfNeeded()
        let height = ceil(collectionView.collectionViewLayout.collectionViewContentSize.height)
            + Self.embeddedListBottomPadding
        onEmbeddedHeightChange?(height)
    }

    private func subtitle(for row: KanaRow, state: KanaRowProgressState) -> String {
        switch state {
        case .locked:
            if progressStore.isRowBlockedByReviewBacklog(row) {
                return "Complete a row review to unlock more rows"
            }
            return "Complete the previous row lesson to unlock"
        case .available:
            return "Tap to start the lesson · \(row.glyphs.count) characters"
        case .lessonCompleted:
            return "Lesson complete · tap to start the review"
        case .completed:
            return "Completed · tap to practice again"
        }
    }

    private func row(for id: String) -> KanaRow? {
        rows.first { $0.id == id }
    }

    // MARK: - Actions

    private func handleSelection(of itemID: String) {
        switch itemID {
        case ItemID.chart:
            navigationController?.pushViewController(
                KanaLearningChartViewController(progressStore: progressStore, script: script),
                animated: true
            )
        case ItemID.srsReview:
            guard progressStore.dueGlyphCount > 0 else { return }
            launchSession(kind: .srsReview, row: nil)
        default:
            guard let rowID = ItemID.rowID(from: itemID), let row = row(for: rowID) else { return }
            switch progressStore.rowState(row) {
            case .locked:
                return
            case .available, .completed:
                launchSession(kind: .lesson, row: row)
            case .lessonCompleted:
                launchSession(kind: .rowReview, row: row)
            }
        }
    }

    private func launchSession(kind: KanaSessionKind, row: KanaRow?) {
        let coordinator = KanaLessonCoordinator(kind: kind, row: row, progressStore: progressStore)
        coordinator.delegate = self
        activeLessonCoordinator = coordinator
        coordinator.present(from: self)
    }
}

// MARK: - UICollectionViewDelegate

extension KanaProgressPathViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let itemID = dataSource.itemIdentifier(for: indexPath) else { return }
        handleSelection(of: itemID)
    }
}

// MARK: - KanaLessonSessionDelegate

extension KanaProgressPathViewController: KanaLessonSessionDelegate {
    func kanaLessonSessionDidFinish(kind: KanaSessionKind, row: KanaRow?, metrics: KanaLessonSessionMetrics) {
        activeLessonCoordinator = nil
        dismiss(animated: true) { [weak self] in
            self?.reloadContent()
            self?.onProgressDidChange?()
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
