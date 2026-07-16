//
//  GeminiUsageHistoryViewController.swift
//  shizen
//
//  Lists individual Gemini token-usage records plus an aggregate summary,
//  so real per-request token counts can inform usage/cost estimates.
//

import UIKit

final class GeminiUsageHistoryViewController: UIViewController {

    private nonisolated enum Section: Int, CaseIterable, Sendable {
        case summary
        case costEstimate
        case records

        var title: String? {
            switch self {
            case .summary: return nil
            case .costEstimate: return "Estimated cost"
            case .records: return "Requests"
            }
        }
    }

    private nonisolated enum Item: Hashable, Sendable {
        case summary(requestCount: Int, totalTokens: Int, byFeatureSubtitle: String)
        case costPerDay(text: String)
        case costPerSession(text: String)
        case record(GeminiUsageRecord)
    }

    private var records: [GeminiUsageRecord] = []

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Gemini usage"
        view.backgroundColor = .systemGroupedBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Clear",
            style: .plain,
            target: self,
            action: #selector(clearTapped)
        )

        configureCollectionView()
        configureDataSource()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    // MARK: - Collection view

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { sectionIndex, environment in
            var listConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            let section = Section.allCases[sectionIndex]
            listConfiguration.headerMode = section.title != nil ? .supplementary : .none
            return NSCollectionLayoutSection.list(
                using: listConfiguration,
                layoutEnvironment: environment
            )
        }

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> {
            [weak self] cell, _, item in
            self?.configure(cell: cell, for: item)
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { header, _, indexPath in
            var content = UIListContentConfiguration.groupedHeader()
            content.text = Section.allCases[indexPath.section].title
            header.contentConfiguration = content
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(
                using: cellRegistration,
                for: indexPath,
                item: item
            )
        }

        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            guard Section.allCases[indexPath.section].title != nil else { return nil }
            return collectionView.dequeueConfiguredReusableSupplementary(
                using: headerRegistration,
                for: indexPath
            )
        }
    }

    private func configure(cell: UICollectionViewListCell, for item: Item) {
        var content = UIListContentConfiguration.subtitleCell()

        switch item {
        case .summary(let requestCount, let totalTokens, let byFeatureSubtitle):
            content.text = "\(requestCount) requests · \(totalTokens) tokens"
            content.secondaryText = byFeatureSubtitle
            content.textProperties.font = .preferredFont(forTextStyle: .headline)

        case .costPerDay(let text):
            content.text = "Per day"
            content.secondaryText = text

        case .costPerSession(let text):
            content.text = "Per session"
            content.secondaryText = text

        case .record(let record):
            content.text = "\(record.feature.displayName) · \(record.model)"
            content.secondaryText = String(
                format: "%@ · %d prompt + %d response = %d tokens",
                Self.dateFormatter.string(from: record.timestamp),
                record.promptTokens,
                record.candidatesTokens,
                record.totalTokens
            )
        }

        cell.contentConfiguration = content
        cell.backgroundConfiguration = UIBackgroundConfiguration.listGroupedCell()
    }

    private func reload() {
        records = GeminiUsageTracker.shared.allRecords().sorted { $0.timestamp > $1.timestamp }
        applySnapshot()
        collectionView.backgroundView = records.isEmpty ? makeEmptyLabel() : nil
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections(Section.allCases)

        let summary = GeminiUsageTracker.shared.summary()
        var byFeatureSubtitle = GeminiUsageFeature.allCases
            .compactMap { feature -> String? in
                guard let tokens = summary.byFeature[feature], tokens > 0 else { return nil }
                return "\(feature.displayName): \(tokens)"
            }
            .joined(separator: " · ")
        if let totalCost = summary.totalCostUSD {
            let suffix = summary.hasUnpricedRecords ? "+ (some models unpriced)" : ""
            byFeatureSubtitle += byFeatureSubtitle.isEmpty ? "" : "\n"
            byFeatureSubtitle += "Total: \(GeminiCostFormatter.string(from: totalCost))\(suffix)"
        }
        snapshot.appendItems(
            [.summary(
                requestCount: summary.requestCount,
                totalTokens: summary.totalTokens,
                byFeatureSubtitle: byFeatureSubtitle.isEmpty ? "No requests yet" : byFeatureSubtitle
            )],
            toSection: .summary
        )

        let costEstimate = GeminiUsageTracker.shared.costEstimate()
        let unpricedSuffix = costEstimate.hasUnpricedRecords ? " (some models unpriced)" : ""
        snapshot.appendItems(
            [
                .costPerDay(text: Self.costEstimateText(
                    amount: costEstimate.averagePerDayUSD,
                    count: costEstimate.dayCount,
                    unit: "day",
                    suffix: unpricedSuffix
                )),
                .costPerSession(text: Self.costEstimateText(
                    amount: costEstimate.averagePerSessionUSD,
                    count: costEstimate.sessionCount,
                    unit: "session",
                    suffix: unpricedSuffix
                )),
            ],
            toSection: .costEstimate
        )

        snapshot.appendItems(records.map(Item.record), toSection: .records)

        dataSource.apply(snapshot, animatingDifferences: view.window != nil)
    }

    private static func costEstimateText(amount: Double?, count: Int, unit: String, suffix: String) -> String {
        guard let amount, count > 0 else { return "No data yet" }
        let countLabel = "\(count) \(unit)\(count == 1 ? "" : "s")"
        return "\(GeminiCostFormatter.string(from: amount))\(suffix) · based on \(countLabel)"
    }

    @objc private func clearTapped() {
        let alert = UIAlertController(
            title: "Clear usage log?",
            message: "This deletes all recorded Gemini token-usage history. This can't be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            GeminiUsageTracker.shared.clearAll()
            self?.reload()
        })
        present(alert, animated: true)
    }

    private func makeEmptyLabel() -> UILabel {
        let label = UILabel()
        label.text = "No Gemini requests recorded yet.\n\nUsage is logged automatically as you use tokenization and contextual insights."
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        label.numberOfLines = 0
        return label
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

extension GeminiUsageHistoryViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
    }
}
