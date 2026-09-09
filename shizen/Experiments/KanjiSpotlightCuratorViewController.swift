//
//  KanjiSpotlightCuratorViewController.swift
//  shizen
//
//  Hand-pick compounds (and optional verbs) that showcase distinct readings
//  for one subject kanji, then continue into the exportable slideshow.
//

import UIKit

final class KanjiSpotlightCuratorViewController: UIViewController {

    private let subject: KanjiSpotlightSubject

    private var compoundCandidates: [KanjiSpotlightShowcaseItem] = []
    private var verbCandidates: [KanjiSpotlightShowcaseItem] = []
    /// Selected items in tap order (compounds and verbs interleaved by selection).
    private var selectedInOrder: [KanjiSpotlightShowcaseItem] = []

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Row>!
    private var continueButton: UIBarButtonItem?

    private nonisolated enum Section: Int, Hashable, Sendable {
        case selected
        case compounds
        case verbs
    }

    /// Distinct row IDs so the same showcase item can appear in Selected and
    /// in the candidate lists at the same time.
    private enum Row: Hashable {
        case selected(KanjiSpotlightShowcaseItem)
        case compound(KanjiSpotlightShowcaseItem)
        case verb(KanjiSpotlightShowcaseItem)

        var item: KanjiSpotlightShowcaseItem {
            switch self {
            case .selected(let item), .compound(let item), .verb(let item):
                return item
            }
        }
    }

    init(subject: KanjiSpotlightSubject) {
        self.subject = subject
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = subject.character
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemGroupedBackground

        configureContinueButton()
        configureCollectionView()
        loadCandidates()
    }

    private func configureContinueButton() {
        let button = UIBarButtonItem(
            title: "Continue",
            style: .done,
            target: self,
            action: #selector(continueTapped)
        )
        continueButton = button
        navigationItem.rightBarButtonItem = button
        updateContinueEnabled()
    }

    private func configureCollectionView() {
        var listConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        listConfiguration.headerMode = .supplementary
        listConfiguration.footerMode = .supplementary
        let layout = UICollectionViewCompositionalLayout.list(using: listConfiguration)
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.delegate = self
        view.addSubview(collectionView)

        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Row> {
            [weak self] cell, _, row in
            guard let self else { return }
            let item = row.item
            var configuration = cell.defaultContentConfiguration()

            switch row {
            case .selected:
                let exampleNumber = (self.selectedInOrder.firstIndex(of: item) ?? 0) + 1
                configuration.text = "\(exampleNumber). \(item.expression)  \(item.readingLine)"
                configuration.textProperties.font = .preferredFont(forTextStyle: .body)
                configuration.secondaryText = item.gloss
                configuration.secondaryTextProperties.color = .secondaryLabel
                configuration.secondaryTextProperties.numberOfLines = 2
                cell.accessories = [.checkmark()]
            case .compound, .verb:
                configuration.text = "\(item.expression)  \(item.readingLine)"
                configuration.textProperties.font = .preferredFont(forTextStyle: .body)
                configuration.secondaryText = item.gloss
                configuration.secondaryTextProperties.color = .secondaryLabel
                configuration.secondaryTextProperties.numberOfLines = 2
                cell.accessories = self.selectedInOrder.contains(item) ? [.checkmark()] : []
            }

            cell.contentConfiguration = configuration
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Row>(
            collectionView: collectionView
        ) { collectionView, indexPath, row in
            collectionView.dequeueConfiguredReusableCell(
                using: cellRegistration,
                for: indexPath,
                item: row
            )
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] supplementaryView, _, indexPath in
            guard let self,
                  let section = Section(rawValue: indexPath.section)
            else { return }
            var configuration = supplementaryView.defaultContentConfiguration()
            switch section {
            case .selected:
                configuration.text = "Selected"
                configuration.secondaryText = "Deck order · tap to remove"
            case .compounds:
                configuration.text = "Compounds"
                configuration.secondaryText = "Pick 2–3 with distinct readings"
            case .verbs:
                configuration.text = "Verbs & non-compounds"
                configuration.secondaryText = "Optional · when the kanji appears in verbs"
            }
            configuration.textProperties.font = .preferredFont(forTextStyle: .headline)
            configuration.secondaryTextProperties.color = .secondaryLabel
            supplementaryView.contentConfiguration = configuration
        }

        let footerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [weak self] supplementaryView, _, indexPath in
            guard let self,
                  let section = Section(rawValue: indexPath.section)
            else { return }
            var configuration = supplementaryView.defaultContentConfiguration()
            switch section {
            case .selected:
                if self.selectedInOrder.isEmpty {
                    configuration.text = "Tap compounds below to build your deck."
                } else {
                    let compounds = self.selectedInOrder.filter { $0.kind == .compound }.count
                    let verbs = self.selectedInOrder.filter { $0.kind == .verb }.count
                    configuration.text =
                        "\(self.selectedInOrder.count) selected · \(compounds) compounds · \(verbs) verbs"
                }
            case .compounds:
                let selected = self.selectedInOrder.filter { $0.kind == .compound }.count
                configuration.text =
                    "Selected \(selected)/\(KanjiSpotlightCatalog.maxCompounds). Order is tap order."
            case .verbs:
                let selected = self.selectedInOrder.filter { $0.kind == .verb }.count
                configuration.text =
                    "Selected \(selected)/\(KanjiSpotlightCatalog.maxVerbs). Readings shown as kana · romaji."
            }
            configuration.textProperties.font = .preferredFont(forTextStyle: .footnote)
            configuration.textProperties.color = .secondaryLabel
            supplementaryView.contentConfiguration = configuration
        }

        dataSource.supplementaryViewProvider = { collectionView, elementKind, indexPath in
            if elementKind == UICollectionView.elementKindSectionHeader {
                return collectionView.dequeueConfiguredReusableSupplementary(
                    using: headerRegistration,
                    for: indexPath
                )
            }
            return collectionView.dequeueConfiguredReusableSupplementary(
                using: footerRegistration,
                for: indexPath
            )
        }
    }

    private func loadCandidates() {
        let character = subject.character
        Task.detached(priority: .userInitiated) { [weak self] in
            let catalog = KanjiSpotlightCatalog.candidates(for: character)
            let suggested = KanjiSpotlightCatalog.suggestedSelection(
                compounds: catalog.compounds,
                verbs: catalog.verbs,
                compoundCount: min(3, KanjiSpotlightCatalog.maxCompounds),
                verbCount: 0
            )
            await MainActor.run {
                guard let self else { return }
                self.compoundCandidates = catalog.compounds
                self.verbCandidates = catalog.verbs
                self.selectedInOrder = suggested
                self.applySnapshot()
                self.updateContinueEnabled()
            }
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([.selected, .compounds, .verbs])
        snapshot.appendItems(selectedInOrder.map(Row.selected), toSection: .selected)
        snapshot.appendItems(compoundCandidates.map(Row.compound), toSection: .compounds)
        snapshot.appendItems(verbCandidates.map(Row.verb), toSection: .verbs)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func refreshSelectionUI() {
        applySnapshot()
        updateContinueEnabled()
    }

    private func updateContinueEnabled() {
        continueButton?.isEnabled = !selectedInOrder.isEmpty
    }

    private func toggleSelection(_ item: KanjiSpotlightShowcaseItem) {
        if let index = selectedInOrder.firstIndex(of: item) {
            selectedInOrder.remove(at: index)
        } else {
            let maxAllowed = item.kind == .compound
                ? KanjiSpotlightCatalog.maxCompounds
                : KanjiSpotlightCatalog.maxVerbs
            let currentCount = selectedInOrder.filter { $0.kind == item.kind }.count
            guard currentCount < maxAllowed else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }
            selectedInOrder.append(item)
        }
        refreshSelectionUI()
    }

    @objc private func continueTapped() {
        guard !selectedInOrder.isEmpty else { return }
        let deck = KanjiSpotlightDeck(subject: subject, items: selectedInOrder)
        navigationController?.pushViewController(
            KanjiSpotlightPagerViewController(deck: deck),
            animated: true
        )
    }
}

// MARK: - UICollectionViewDelegate

extension KanjiSpotlightCuratorViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let row = dataSource.itemIdentifier(for: indexPath) else { return }
        toggleSelection(row.item)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
