//
//  GrammarCheckpointListViewController.swift
//  shizen
//

import UIKit

final class GrammarCheckpointListViewController: UIViewController {

    enum PresentationStyle {
        case standalone
        case embedded
    }

    private enum Section: Int, CaseIterable {
        case checkpoints = 0
    }

    private let masteryStore: GrammarMasteryStore
    private let checkpoints: [GrammarCheckpoint]
    private let allPoints: [GrammarPoint]
    private let presentationStyle: PresentationStyle

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    var onEmbeddedHeightChange: ((CGFloat) -> Void)?
    var onProgressDidChange: (() -> Void)?
    var onSelectCheckpoint: ((GrammarCheckpoint) -> Void)?

    init(
        masteryStore: GrammarMasteryStore = .shared,
        checkpoints: [GrammarCheckpoint] = GrammarCurriculum.n5Checkpoints,
        allPoints: [GrammarPoint] = GrammarCurriculum.n5Points,
        presentationStyle: PresentationStyle = .embedded
    ) {
        self.masteryStore = masteryStore
        self.checkpoints = checkpoints
        self.allPoints = allPoints
        self.presentationStyle = presentationStyle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if presentationStyle == .standalone {
            title = "JLPT N5 Grammar"
        }
        view.backgroundColor = ExperimentPalette.pageBackground
        configureCollectionView()
        configureDataSource()
        reloadContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshFromMasteryStore()
    }

    func refreshFromMasteryStore() {
        masteryStore.reload()
        reloadContent()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        reportEmbeddedHeightIfNeeded()
    }

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            guard let self else {
                return NSCollectionLayoutSection.list(
                    using: UICollectionLayoutListConfiguration(appearance: .insetGrouped),
                    layoutEnvironment: environment
                )
            }

            var listConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            if self.presentationStyle == .embedded {
                listConfiguration.headerMode = .none
                listConfiguration.headerTopPadding = 0
            } else {
                listConfiguration.headerMode = sectionIndex == Section.checkpoints.rawValue ? .supplementary : .none
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
        collectionView.backgroundColor = presentationStyle == .embedded
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
        ) { collectionView, indexPath, itemID in
            collectionView.dequeueConfiguredReusableCell(
                using: cellRegistration,
                for: indexPath,
                item: itemID
            )
        }

        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(
                using: headerRegistration,
                for: indexPath
            )
        }
    }

    private func configure(cell: UICollectionViewListCell, for itemID: String) {
        guard let checkpoint = checkpoint(for: itemID) else { return }
        let points = checkpoint.points(from: allPoints)
        let known = points.filter { masteryStore.masteryState(for: $0.id) == .known }.count
        let total = points.count

        var content = UIListContentConfiguration.subtitleCell()
        content.text = checkpoint.title
        content.secondaryText = subtitle(for: checkpoint, known: known, total: total)
        content.textProperties.numberOfLines = 2
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 2
        content.image = UIImage(systemName: known == total && total > 0 ? "checkmark.circle.fill" : "circle.inset.filled")
        content.imageProperties.tintColor = known == total && total > 0
            ? .systemGreen
            : UIColor(red: 0.45, green: 0.28, blue: 0.92, alpha: 1)
        cell.accessories = [.disclosureIndicator()]
        cell.contentConfiguration = content
        cell.backgroundConfiguration = UIBackgroundConfiguration.listGroupedCell()
    }

    private func configure(header: UICollectionViewListCell, for sectionIndex: Int) {
        guard sectionIndex == Section.checkpoints.rawValue else { return }

        var content = UIListContentConfiguration.groupedHeader()
        let known = masteryStore.knownCount
        let total = allPoints.count
        content.text = "JLPT N5 grammar"
        content.secondaryText = "\(known) / \(total) patterns known"
        content.secondaryTextProperties.color = .secondaryLabel
        header.contentConfiguration = content
    }

    private func subtitle(for checkpoint: GrammarCheckpoint, known: Int, total: Int) -> String {
        let progress = "\(known) / \(total) known"
        if let blurb = checkpoint.subtitle, !blurb.isEmpty {
            return "\(progress) · \(blurb)"
        }
        return progress
    }

    private func reloadContent() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([Section.checkpoints.rawValue])
        snapshot.appendItems(checkpoints.map(\.id), toSection: Section.checkpoints.rawValue)

        dataSource.apply(snapshot, animatingDifferences: view.window != nil) { [weak self] in
            self?.reportEmbeddedHeightIfNeeded()
        }
    }

    private func reportEmbeddedHeightIfNeeded() {
        guard presentationStyle == .embedded else { return }
        collectionView.layoutIfNeeded()
        let height = collectionView.collectionViewLayout.collectionViewContentSize.height
        onEmbeddedHeightChange?(height)
    }

    private func checkpoint(for id: String) -> GrammarCheckpoint? {
        checkpoints.first { $0.id == id }
    }

    private func handleSelection(checkpointID: String) {
        guard let checkpoint = checkpoint(for: checkpointID) else { return }
        if let onSelectCheckpoint {
            onSelectCheckpoint(checkpoint)
        } else {
            let path = GrammarProgressPathViewController(
                masteryStore: masteryStore,
                checkpoint: checkpoint,
                points: GrammarCurriculum.points(for: checkpoint),
                presentationStyle: .standalone
            )
            path.onProgressDidChange = { [weak self] in
                self?.masteryStore.reload()
                self?.reloadContent()
                self?.onProgressDidChange?()
            }
            navigationController?.pushViewController(path, animated: true)
        }
    }
}

extension GrammarCheckpointListViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let itemID = dataSource.itemIdentifier(for: indexPath) else { return }
        handleSelection(checkpointID: itemID)
    }
}
