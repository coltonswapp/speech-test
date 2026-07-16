//
//  GrammarProgressPathViewController.swift
//  shizen
//

import UIKit

final class GrammarProgressPathViewController: UIViewController {

    enum PresentationStyle {
        case standalone
        case embeddedLessonsOnly
    }

    private enum Section: Int, CaseIterable {
        case points = 0
    }

    private let masteryStore: GrammarMasteryStore
    private let checkpoint: GrammarCheckpoint?
    private let points: [GrammarPoint]
    private let presentationStyle: PresentationStyle

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    var onEmbeddedHeightChange: ((CGFloat) -> Void)?
    var onProgressDidChange: (() -> Void)?

    init(
        masteryStore: GrammarMasteryStore = .shared,
        checkpoint: GrammarCheckpoint? = nil,
        points: [GrammarPoint]? = nil,
        presentationStyle: PresentationStyle = .embeddedLessonsOnly
    ) {
        self.masteryStore = masteryStore
        self.checkpoint = checkpoint
        self.points = points ?? GrammarCurriculum.n5Points
        self.presentationStyle = presentationStyle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if presentationStyle == .standalone {
            title = checkpoint?.title ?? "JLPT N5 Grammar"
        }
        view.backgroundColor = ExperimentPalette.pageBackground
        configureCollectionView()
        configureDataSource()
        reloadContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
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
            if self.presentationStyle == .embeddedLessonsOnly {
                listConfiguration.headerMode = .none
                listConfiguration.headerTopPadding = 0
            } else {
                listConfiguration.headerMode = sectionIndex == Section.points.rawValue ? .supplementary : .none
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
        guard let point = point(for: itemID) else { return }
        let state = masteryStore.masteryState(for: point.id)

        var content = UIListContentConfiguration.subtitleCell()
        content.text = point.pattern
        content.secondaryText = subtitle(for: point, state: state)
        content.textProperties.numberOfLines = 1
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 2
        content.image = rowIcon(for: state)
        content.imageProperties.tintColor = rowTint(for: state)
        cell.accessories = [.disclosureIndicator()]
        cell.contentConfiguration = content
        cell.backgroundConfiguration = UIBackgroundConfiguration.listGroupedCell()
    }

    private func configure(header: UICollectionViewListCell, for sectionIndex: Int) {
        guard sectionIndex == Section.points.rawValue else { return }

        var content = UIListContentConfiguration.groupedHeader()
        let known = knownCountInScope
        let total = points.count

        if let checkpoint {
            content.text = checkpoint.title
            if let subtitle = checkpoint.subtitle, !subtitle.isEmpty {
                content.secondaryText = "\(known) / \(total) known · \(subtitle)"
            } else {
                content.secondaryText = "\(known) / \(total) known"
            }
        } else {
            content.text = "JLPT N5 grammar"
            content.secondaryText = "\(known) / \(total) known"
        }
        content.secondaryTextProperties.color = .secondaryLabel
        header.contentConfiguration = content
    }

    private var knownCountInScope: Int {
        points.filter { masteryStore.masteryState(for: $0.id) == .known }.count
    }

    private func rowIcon(for state: GrammarMasteryState) -> UIImage? {
        switch state {
        case .new:
            return UIImage(systemName: "circle")
        case .seen:
            return UIImage(systemName: "circle.inset.filled")
        case .known:
            return UIImage(systemName: "checkmark.circle.fill")
        }
    }

    private func rowTint(for state: GrammarMasteryState) -> UIColor {
        switch state {
        case .new:
            return .tertiaryLabel
        case .seen:
            return UIColor(red: 0.45, green: 0.28, blue: 0.92, alpha: 1)
        case .known:
            return .systemGreen
        }
    }

    private func subtitle(for point: GrammarPoint, state: GrammarMasteryState) -> String {
        let badge: String
        switch state {
        case .new: badge = "New"
        case .seen: badge = "Seen"
        case .known: badge = "Known"
        }
        return "\(badge) · \(point.shortDefinition)"
    }

    private func reloadContent() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([Section.points.rawValue])
        snapshot.appendItems(points.map(\.id), toSection: Section.points.rawValue)

        dataSource.apply(snapshot, animatingDifferences: view.window != nil) { [weak self] in
            self?.reportEmbeddedHeightIfNeeded()
        }
    }

    private func reportEmbeddedHeightIfNeeded() {
        guard presentationStyle == .embeddedLessonsOnly else { return }
        collectionView.layoutIfNeeded()
        let height = collectionView.collectionViewLayout.collectionViewContentSize.height
        onEmbeddedHeightChange?(height)
    }

    private func point(for id: String) -> GrammarPoint? {
        points.first { $0.id == id }
    }

    private func handleSelection(pointID: String) {
        guard let point = point(for: pointID) else { return }
        GrammarReferencePresenter.open(
            point: point,
            from: self
        )
    }
}

extension GrammarProgressPathViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let itemID = dataSource.itemIdentifier(for: indexPath) else { return }
        handleSelection(pointID: itemID)
    }
}
