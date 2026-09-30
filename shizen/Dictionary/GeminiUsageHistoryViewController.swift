//
//  GeminiUsageHistoryViewController.swift
//  shizen
//
//  Lists individual Gemini token-usage records in hour sections, plus an
//  aggregate summary, so real per-request token counts can inform usage/cost estimates.
//

import UIKit

final class GeminiUsageHistoryViewController: UIViewController {

    private enum UsageFilter: Hashable {
        case all
        case feature(GeminiUsageFeature)

        var title: String {
            switch self {
            case .all: return "All"
            case .feature(let feature): return feature.displayName
            }
        }

        var feature: GeminiUsageFeature? {
            switch self {
            case .all: return nil
            case .feature(let feature): return feature
            }
        }
    }

    private nonisolated enum Section: Hashable, Sendable {
        case account
        case everyone
        case summary
        case costEstimate
        case hour(Date)

        var hasHeader: Bool {
            switch self {
            case .summary: return false
            case .account, .everyone, .costEstimate, .hour: return true
            }
        }
    }

    private nonisolated enum Item: Hashable, Sendable {
        case summary(requestCount: Int, totalTokens: Int, byFeatureSubtitle: String)
        case tokenDirection(title: String, detail: String)
        case modelRate(model: String, detail: String)
        case costPerDay(text: String)
        case costPerSession(text: String)
        case serverSummary(scope: String, periodKey: String, calls: Int, costUSD: Double, hasUnpriced: Bool)
        case serverFeature(scope: String, name: String, calls: Int, costUSD: Double)
        case record(GeminiUsageRecord)
    }

    private var records: [GeminiUsageRecord] = []
    private var accountReport: LLMUsageReport?
    private var productReport: LLMProductUsageReport?
    private var serverPeriod: LLMUsagePeriod = .week
    private var selectedFilter: UsageFilter = .all
    private var filterButtons: [UsageFilter: UIButton] = [:]

    private let filterScrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.contentInsetAdjustmentBehavior = .never
        return scroll
    }()

    private let filterStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        return stack
    }()

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Gemini usage"
        view.backgroundColor = .systemGroupedBackground

        navigationItem.rightBarButtonItem = makeTrailingMenuButton()

        configureFilterBar()
        configureCollectionView()
        configureDataSource()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    // MARK: - Filter

    private func configureFilterBar() {
        view.addSubview(filterScrollView)
        filterScrollView.addSubview(filterStack)
        NSLayoutConstraint.activate([
            filterScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            filterScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterScrollView.heightAnchor.constraint(equalToConstant: 52),

            filterStack.topAnchor.constraint(equalTo: filterScrollView.contentLayoutGuide.topAnchor),
            filterStack.bottomAnchor.constraint(equalTo: filterScrollView.contentLayoutGuide.bottomAnchor),
            filterStack.leadingAnchor.constraint(equalTo: filterScrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            filterStack.trailingAnchor.constraint(equalTo: filterScrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            filterStack.heightAnchor.constraint(equalTo: filterScrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    private func rebuildFilterBar() {
        let present = Set(records.map(\.feature))
        var filters: [UsageFilter] = [.all]
        filters += GeminiUsageFeature.allCases
            .filter { present.contains($0) }
            .map { .feature($0) }
        if !filters.contains(selectedFilter) {
            selectedFilter = .all
        }

        filterButtons.removeAll()
        for view in filterStack.arrangedSubviews {
            filterStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for filter in filters {
            let button = UIButton(type: .system)
            button.addAction(UIAction { [weak self] _ in
                self?.select(filter)
            }, for: .primaryActionTriggered)
            style(button, filter: filter)
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            filterStack.addArrangedSubview(button)
            filterButtons[filter] = button
        }
    }

    private func select(_ filter: UsageFilter) {
        guard filter != selectedFilter else { return }
        selectedFilter = filter
        for (candidate, button) in filterButtons {
            style(button, filter: candidate)
        }
        applySnapshot()
        guard let button = filterButtons[filter] else { return }
        let rect = button.convert(button.bounds, to: filterScrollView).insetBy(dx: -16, dy: 0)
        filterScrollView.scrollRectToVisible(rect, animated: true)
    }

    private func style(_ button: UIButton, filter: UsageFilter) {
        let selected = filter == selectedFilter
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.title = filter.title
        config.baseBackgroundColor = selected ? .label : .secondarySystemFill
        config.baseForegroundColor = selected ? .systemBackground : .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .preferredFont(forTextStyle: .subheadline)
            return outgoing
        }
        button.configuration = config
        if selected {
            button.accessibilityTraits.insert(.selected)
        } else {
            button.accessibilityTraits.remove(.selected)
        }
    }

    private var filteredRecords: [GeminiUsageRecord] {
        guard let feature = selectedFilter.feature else { return records }
        return records.filter { $0.feature == feature }
    }

    // MARK: - Collection view

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { sectionIndex, environment in
            var listConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            let section = self.dataSource?.snapshot().sectionIdentifiers[safe: sectionIndex]
            listConfiguration.headerMode = section?.hasHeader == true ? .supplementary : .none
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
            collectionView.topAnchor.constraint(equalTo: filterScrollView.bottomAnchor),
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
        ) { [weak self] header, _, indexPath in
            var content = UIListContentConfiguration.groupedHeader()
            content.text = self?.headerTitle(at: indexPath)
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

        dataSource.supplementaryViewProvider = { [weak self] collectionView, _, indexPath in
            guard let self else { return nil }
            let identifiers = self.dataSource.snapshot().sectionIdentifiers
            guard identifiers[safe: indexPath.section]?.hasHeader == true else { return nil }
            return collectionView.dequeueConfiguredReusableSupplementary(
                using: headerRegistration,
                for: indexPath
            )
        }
    }

    private func headerTitle(at indexPath: IndexPath) -> String? {
        let snapshot = dataSource.snapshot()
        guard let section = snapshot.sectionIdentifiers[safe: indexPath.section] else { return nil }
        switch section {
        case .account:
            return "Your account · \(serverPeriodTitle)"
        case .everyone:
            return "Everyone · \(serverPeriodTitle)"
        case .summary:
            return nil
        case .costEstimate:
            return "Rough cost"
        case .hour(let hourStart):
            let hourEnd = Calendar.current.date(byAdding: .hour, value: 1, to: hourStart) ?? hourStart
            let range = Self.hourIntervalFormatter.string(from: hourStart, to: hourEnd)
            let count = snapshot.numberOfItems(inSection: section)
            let requestLabel = count == 1 ? "1 request" : "\(count) requests"
            return "\(range) · \(requestLabel)"
        }
    }

    private func configure(cell: UICollectionViewListCell, for item: Item) {
        var content = UIListContentConfiguration.subtitleCell()
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0

        switch item {
        case .summary(let requestCount, let totalTokens, let byFeatureSubtitle):
            let requestLabel = requestCount == 1 ? "1 request" : "\(Self.tokens(requestCount)) requests"
            content.text = "\(requestLabel) · \(Self.tokens(totalTokens)) tokens"
            content.secondaryText = byFeatureSubtitle
            content.textProperties.font = .preferredFont(forTextStyle: .headline)

        case .tokenDirection(let title, let detail):
            content.text = title
            content.secondaryText = detail

        case .modelRate(let model, let detail):
            content.text = model
            content.secondaryText = detail
            content.textProperties.font = .preferredFont(forTextStyle: .subheadline)
            content.secondaryTextProperties.color = .secondaryLabel

        case .costPerDay(let text):
            content.text = "Per day"
            content.secondaryText = text

        case .costPerSession(let text):
            content.text = "Per session"
            content.secondaryText = text

        case .serverSummary(_, let periodKey, let calls, let costUSD, let hasUnpriced):
            let requestLabel = calls == 1 ? "1 request" : "\(Self.tokens(calls)) requests"
            content.text = "\(requestLabel) · \(GeminiCostFormatter.string(from: costUSD))"
            content.secondaryText = hasUnpriced ? "\(periodKey) · some models unpriced" : periodKey
            content.textProperties.font = .preferredFont(forTextStyle: .headline)

        case .serverFeature(_, let name, let calls, let costUSD):
            content.text = name
            content.secondaryText = "\(Self.tokens(calls)) · \(GeminiCostFormatter.string(from: costUSD))"

        case .record(let record):
            if selectedFilter.feature == nil {
                content.text = "\(record.feature.displayName) · \(record.model)"
            } else {
                content.text = record.model
            }
            var detail = String(
                format: "%@ · %@ in + %@ out = %@ tokens",
                Self.timeFormatter.string(from: record.timestamp),
                Self.tokens(record.promptTokens),
                Self.tokens(record.outputTokens),
                Self.tokens(record.totalTokens)
            )
            if let cost = record.costUSD {
                detail += " · \(GeminiCostFormatter.string(from: cost))"
            }
            content.secondaryText = detail
        }

        cell.contentConfiguration = content
        cell.backgroundConfiguration = UIBackgroundConfiguration.listGroupedCell()
    }

    private func reload() {
        records = GeminiUsageTracker.shared.allRecords().sorted { $0.timestamp > $1.timestamp }
        rebuildFilterBar()
        applySnapshot()
        let localEmpty = records.isEmpty && accountReport == nil && productReport == nil
        collectionView.backgroundView = localEmpty ? makeEmptyLabel() : nil
        if ExperimentSettings.llmServerUsageEnabled {
            Task { await self.reloadServerUsage() }
        }
    }

    private var serverPeriodTitle: String {
        switch serverPeriod {
        case .day: return "today"
        case .week: return "this week"
        case .month: return "this month"
        }
    }

    private func makeTrailingMenuButton() -> UIBarButtonItem {
        var children: [UIMenuElement] = []
        if ExperimentSettings.llmServerUsageEnabled {
            children.append(UIMenu(
                options: .displayInline,
                children: LLMUsagePeriod.allCases.map { period in
                    UIAction(
                        title: period.rawValue.capitalized,
                        state: period == serverPeriod ? .on : .off
                    ) { [weak self] _ in
                        self?.selectServerPeriod(period)
                    }
                }
            ))
        }
        children.append(UIAction(
            title: "Clear local log…",
            attributes: .destructive
        ) { [weak self] _ in
            self?.confirmClearLocalLog()
        })
        let title = ExperimentSettings.llmServerUsageEnabled
            ? serverPeriod.rawValue.capitalized
            : "More"
        return UIBarButtonItem(title: title, menu: UIMenu(children: children))
    }

    private func selectServerPeriod(_ period: LLMUsagePeriod) {
        guard period != serverPeriod else { return }
        serverPeriod = period
        navigationItem.rightBarButtonItem = makeTrailingMenuButton()
        Task { await reloadServerUsage() }
    }

    private func reloadServerUsage() async {
        guard ExperimentSettings.llmServerUsageEnabled, LLMGatewayClient.isAvailable else { return }
        async let mine = LLMUsageClient.mine(period: serverPeriod)
        async let product = LLMUsageClient.product(period: serverPeriod)
        accountReport = try? await mine
        productReport = try? await product
        await MainActor.run {
            self.applySnapshot()
            let empty = self.records.isEmpty && self.accountReport == nil && self.productReport == nil
            self.collectionView.backgroundView = empty ? self.makeEmptyLabel() : nil
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        if let account = accountReport, account.calls > 0 {
            snapshot.appendSections([.account])
            snapshot.appendItems(serverAccountItems(account), toSection: .account)
        }
        if let product = productReport, product.calls > 0 {
            snapshot.appendSections([.everyone])
            snapshot.appendItems(serverProductItems(product), toSection: .everyone)
        }
        snapshot.appendSections([.summary, .costEstimate])

        let feature = selectedFilter.feature
        let summary = GeminiUsageTracker.shared.summary(feature: feature)
        snapshot.appendItems(
            [.summary(
                requestCount: summary.requestCount,
                totalTokens: summary.totalTokens,
                byFeatureSubtitle: summarySubtitle(summary)
            )],
            toSection: .summary
        )

        snapshot.appendItems(costItems(summary: summary), toSection: .costEstimate)

        for (hourStart, hourRecords) in Self.recordsByHour(filteredRecords) {
            let section = Section.hour(hourStart)
            snapshot.appendSections([section])
            snapshot.appendItems(hourRecords.map(Item.record), toSection: section)
        }

        dataSource.apply(snapshot, animatingDifferences: view.window != nil)
    }

    private func serverAccountItems(_ report: LLMUsageReport) -> [Item] {
        var items: [Item] = [
            .serverSummary(
                scope: "account",
                periodKey: report.periodKey,
                calls: report.calls,
                costUSD: report.estimatedCostUSD,
                hasUnpriced: report.hasUnpriced
            ),
        ]
        items += report.rankedFeatures.prefix(6).map { name, totals in
            Item.serverFeature(
                scope: "account",
                name: LLMUsageFeatureTotals.displayName(for: name),
                calls: totals.calls,
                costUSD: totals.estimatedCostUSD
            )
        }
        return items
    }

    private func serverProductItems(_ report: LLMProductUsageReport) -> [Item] {
        var items: [Item] = [
            .serverSummary(
                scope: "product",
                periodKey: report.periodKey,
                calls: report.calls,
                costUSD: report.estimatedCostUSD,
                hasUnpriced: report.hasUnpriced
            ),
        ]
        items += report.features.prefix(6).map { row in
            Item.serverFeature(
                scope: "product",
                name: row.displayName,
                calls: row.calls,
                costUSD: row.estimatedCostUSD
            )
        }
        return items
    }

    private func summarySubtitle(_ summary: GeminiUsageTracker.Summary) -> String {
        guard summary.requestCount > 0 else { return "No requests yet" }
        var lines: [String] = []
        if selectedFilter.feature == nil {
            let byFeature = GeminiUsageFeature.allCases.compactMap { feature -> String? in
                guard let tokens = summary.byFeature[feature], tokens > 0 else { return nil }
                return "\(feature.displayName): \(Self.tokens(tokens))"
            }
            if !byFeature.isEmpty {
                lines.append(byFeature.joined(separator: " · "))
            }
        }
        if let total = summary.totalCostUSD {
            let suffix = summary.hasUnpricedRecords ? " (some models unpriced)" : ""
            lines.append("Total \(GeminiCostFormatter.string(from: total))\(suffix)")
        }
        if lines.isEmpty {
            return "No published rate for these requests"
        }
        return lines.joined(separator: "\n")
    }

    private func costItems(summary: GeminiUsageTracker.Summary) -> [Item] {
        let costEstimate = GeminiUsageTracker.shared.costEstimate(feature: selectedFilter.feature)
        let unpricedSuffix = costEstimate.hasUnpricedRecords ? " (some models unpriced)" : ""
        let singleRate = singlePublishedRate(filteredRecords, unpriced: summary.hasUnpricedRecords)
        var items: [Item] = [
            .tokenDirection(
                title: "Tokens in",
                detail: directionLine(
                    tokens: summary.promptTokens,
                    cost: summary.inputCostUSD,
                    perMillion: singleRate?.inputPerMillion,
                    unpriced: summary.hasUnpricedRecords
                )
            ),
            .tokenDirection(
                title: "Tokens out",
                detail: directionLine(
                    tokens: summary.outputTokens,
                    cost: summary.outputCostUSD,
                    perMillion: singleRate?.outputPerMillion,
                    unpriced: summary.hasUnpricedRecords
                )
            ),
        ]
        items += modelRateItems(filteredRecords)
        items += [
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
        ]
        return items
    }

    private func modelRateItems(_ records: [GeminiUsageRecord]) -> [Item] {
        var order: [String] = []
        var buckets: [String: [GeminiUsageRecord]] = [:]
        for record in records {
            if buckets[record.model] == nil {
                order.append(record.model)
            }
            buckets[record.model, default: []].append(record)
        }
        return order.map { model in
            let group = buckets[model] ?? []
            let prompt = group.reduce(0) { $0 + $1.promptTokens }
            let output = group.reduce(0) { $0 + $1.outputTokens }
            let requestLabel = group.count == 1 ? "1 request" : "\(group.count) requests"
            let volume = "\(requestLabel) · \(Self.tokens(prompt)) in + \(Self.tokens(output)) out"
            let rate = GeminiPricing.rate(for: model, on: group.map(\.timestamp).max() ?? Date())
            let detail: String
            if let rate {
                let costs = group.compactMap {
                    GeminiPricing.cost(
                        model: $0.model,
                        promptTokens: $0.promptTokens,
                        outputTokens: $0.outputTokens,
                        on: $0.timestamp
                    )
                }
                let total = costs.reduce(0) { $0 + $1.totalUSD }
                detail = "\(volume) · \(rate.label) · \(GeminiCostFormatter.string(from: total))"
            } else {
                detail = "\(volume) · no published rate"
            }
            return .modelRate(model: model, detail: detail)
        }
    }

    /// One published rate when every visible request uses the same priced model.
    private func singlePublishedRate(_ records: [GeminiUsageRecord], unpriced: Bool) -> GeminiPricing.PublishedRate? {
        guard !unpriced else { return nil }
        let models = Set(records.map(\.model))
        guard models.count == 1, let model = models.first else { return nil }
        let latest = records.map(\.timestamp).max() ?? Date()
        return GeminiPricing.rate(for: model, on: latest)
    }

    private func directionLine(tokens: Int, cost: Double?, perMillion: Double?, unpriced: Bool) -> String {
        let tokenText = "\(Self.tokens(tokens)) tokens"
        guard let cost else {
            return tokens == 0 ? tokenText : "\(tokenText) · no published rate"
        }
        if let perMillion, !unpriced {
            let rate = String(format: "$%.2f", perMillion)
            return "\(tokenText) × \(rate)/1M = \(GeminiCostFormatter.string(from: cost))"
        }
        let suffix = unpriced ? " (some models unpriced)" : ""
        return "\(tokenText) · \(GeminiCostFormatter.string(from: cost))\(suffix)"
    }

    private static func recordsByHour(_ records: [GeminiUsageRecord]) -> [(Date, [GeminiUsageRecord])] {
        let calendar = Calendar.current
        var hourStarts: [Date] = []
        var buckets: [Date: [GeminiUsageRecord]] = [:]
        for record in records {
            let hourStart = calendar.dateInterval(of: .hour, for: record.timestamp)?.start ?? record.timestamp
            if buckets[hourStart] == nil {
                hourStarts.append(hourStart)
            }
            buckets[hourStart, default: []].append(record)
        }
        return hourStarts.map { hourStart in (hourStart, buckets[hourStart] ?? []) }
    }

    private static func costEstimateText(amount: Double?, count: Int, unit: String, suffix: String) -> String {
        guard let amount, count > 0 else { return "No data yet" }
        let countLabel = "\(count) \(unit)\(count == 1 ? "" : "s")"
        return "\(GeminiCostFormatter.string(from: amount))\(suffix) · based on \(countLabel)"
    }

    private static func tokens(_ count: Int) -> String {
        tokenFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private func confirmClearLocalLog() {
        let alert = UIAlertController(
            title: "Clear local usage log?",
            message: "This deletes the on-device request list only. Server day / week / month totals are not changed.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            GeminiUsageTracker.shared.clearAll()
            self?.selectedFilter = .all
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

    private static let tokenFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let hourIntervalFormatter: DateIntervalFormatter = {
        let f = DateIntervalFormatter()
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
