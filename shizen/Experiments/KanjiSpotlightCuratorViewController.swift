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
    /// Selected items in deck / slide order (compounds and verbs interleaved).
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
    private nonisolated enum Row: Hashable, Sendable {
        case writeInCompound
        case selected(KanjiSpotlightShowcaseItem)
        case compound(KanjiSpotlightShowcaseItem)
        case verb(KanjiSpotlightShowcaseItem)

        var item: KanjiSpotlightShowcaseItem? {
            switch self {
            case .writeInCompound:
                return nil
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
        collectionView.dragInteractionEnabled = true
        view.addSubview(collectionView)

        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Row> {
            [weak self] cell, _, row in
            guard let self else { return }
            var configuration = cell.defaultContentConfiguration()

            switch row {
            case .writeInCompound:
                configuration.text = "Write in compound…"
                configuration.textProperties.color = .systemBlue
                configuration.secondaryText = "Kanji + definition · great for place names"
                configuration.secondaryTextProperties.color = .secondaryLabel
                configuration.image = UIImage(systemName: "plus.circle")
                configuration.imageProperties.tintColor = .systemBlue
                cell.accessories = []
            case .selected(let item):
                let exampleNumber = (self.selectedInOrder.firstIndex(of: item) ?? 0) + 1
                configuration.text = "\(exampleNumber). \(item.expression)  \(item.readingLine)"
                configuration.textProperties.font = .preferredFont(forTextStyle: .body)
                configuration.secondaryText = item.gloss
                configuration.secondaryTextProperties.color = .secondaryLabel
                configuration.secondaryTextProperties.numberOfLines = 2
                cell.accessories = [.reorder(displayed: .always), .checkmark()]
            case .compound(let item), .verb(let item):
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
                configuration.secondaryText = "Deck order · drag to reorder · tap to remove"
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
                    "Selected \(selected)/\(KanjiSpotlightCatalog.maxCompounds)."
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

        dataSource.reorderingHandlers.canReorderItem = { row in
            if case .selected = row { return true }
            return false
        }
        dataSource.reorderingHandlers.didReorder = { [weak self] transaction in
            guard let self else { return }
            self.selectedInOrder = transaction.finalSnapshot
                .itemIdentifiers(inSection: .selected)
                .compactMap(\.item)
            self.reconfigureSelectedRows()
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
        snapshot.appendItems([.writeInCompound] + compoundCandidates.map(Row.compound), toSection: .compounds)
        snapshot.appendItems(verbCandidates.map(Row.verb), toSection: .verbs)
        dataSource.apply(snapshot, animatingDifferences: false)

        // Candidate row IDs do not change when selection does, so mark them
        // (and Selected, for the 1./2. prefixes) for reconfiguration.
        var visible = dataSource.snapshot()
        let stale = visible.itemIdentifiers(inSection: .selected)
            + visible.itemIdentifiers(inSection: .compounds)
            + visible.itemIdentifiers(inSection: .verbs)
        guard !stale.isEmpty else { return }
        visible.reconfigureItems(stale)
        dataSource.apply(visible, animatingDifferences: false)
    }

    private func reconfigureSelectedRows() {
        var snapshot = dataSource.snapshot()
        let selectedRows = snapshot.itemIdentifiers(inSection: .selected)
        guard !selectedRows.isEmpty else { return }
        snapshot.reconfigureItems(selectedRows)
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


    private func presentWriteInCompound() {
        let compoundCount = selectedInOrder.filter { $0.kind == .compound }.count
        guard compoundCount < KanjiSpotlightCatalog.maxCompounds else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }

        let alert = UIAlertController(
            title: "Write in compound",
            message: "Enter the kanji compound and its definition. Reading is optional.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Kanji (e.g. 東京)"
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addTextField { field in
            field.placeholder = "Definition (e.g. Tokyo)"
            field.autocapitalizationType = .sentences
        }
        alert.addTextField { field in
            field.placeholder = "Reading (optional)"
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            guard let self else { return }
            let expression = alert.textFields?[0].text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let gloss = alert.textFields?[1].text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let reading = alert.textFields?[2].text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !expression.isEmpty, !gloss.isEmpty else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            let item = KanjiSpotlightShowcaseItem.writeIn(
                expression: expression,
                gloss: gloss,
                reading: reading,
                kind: .compound
            )
            if !self.compoundCandidates.contains(item) {
                self.compoundCandidates.insert(item, at: 0)
            }
            self.toggleSelection(item)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        })
        present(alert, animated: true)
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
        switch row {
        case .writeInCompound:
            presentWriteInCompound()
        case .selected(let item), .compound(let item), .verb(let item):
            toggleSelection(item)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }


    func collectionView(
        _ collectionView: UICollectionView,
        targetIndexPathForMoveOfItemFromOriginalIndexPath originalIndexPath: IndexPath,
        atCurrentIndexPath currentIndexPath: IndexPath,
        toProposedIndexPath proposedIndexPath: IndexPath
    ) -> IndexPath {
        let selectedSection = Section.selected.rawValue
        guard originalIndexPath.section == selectedSection else { return originalIndexPath }
        guard proposedIndexPath.section == selectedSection else {
            let count = collectionView.numberOfItems(inSection: selectedSection)
            let clampedItem = min(max(proposedIndexPath.item, 0), max(count - 1, 0))
            return IndexPath(item: clampedItem, section: selectedSection)
        }
        return proposedIndexPath
    }
}
