//
//  ClipExplorerViewController.swift
//  shizen
//
//  Debug: explore the clip catalog. Pick a JLPT level first (optional), then
//  one of Studio's catalog tags (format, topic, style, pace, series), laid out
//  like the QA note's tags: a heading per facet over a wrapping flow of glass
//  hashtag pills, each with how many clips carry it at that level. Tap a tag
//  for that tag's List of Clips at the chosen level; a search (keyboard Search
//  key) opens the same list for its matches.
//
//  Lists only hold feed clips (the ones Studio judged worth a swipe), since
//  they play as a feed. The list for one query is ClipQueryListViewController,
//  also pushed from a tag or "More From This Channel" in Clip Details.
//

import UIKit

/// Plays clips as a feed starting at the given index.
typealias ClipFeedPlayHandler = ([ClipSummary], Int) -> Void

/// Plays `clips` from `start`: through `handler` if given, else as a feed pushed on
/// `controller`'s stack. Either way the feed offers no way to explore further: the
/// learner goes back to the root to search or explore again.
@MainActor
private func playClips(
    _ clips: [ClipSummary],
    startingAt start: Int,
    handler: ClipFeedPlayHandler?,
    from controller: UIViewController?
) {
    if let handler {
        handler(clips, start)
    } else {
        let feed = ClipFeedViewController(clips: clips, startingAt: start)
        feed.allowsExploring = false
        controller?.navigationController?.pushViewController(feed, animated: true)
    }
}

// MARK: - Explorer

final class ClipExplorerViewController: UIViewController, UISearchBarDelegate {
    private static let levels = [5, 4, 3, 2, 1]
    /// Tag sections, in order: a heading and the facets under it.
    private static let tagGroups: [(String, [ClipTagFilter.Facet])] = [
        ("Format", [.format]),
        ("Topic", [.topic]),
        ("Style", [.register, .speakers, .dialect]),
        ("Pace", [.pace]),
        ("Series", [.series]),
    ]

    private let onPlay: ClipFeedPlayHandler?
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let statusLabel = UILabel()
    /// Narrows the tags (and their lists) to one level. Nil = every level.
    private var selectedLevel: Int?
    private var levelPills: [Int: GlassTagControl] = [:]
    private let allAtLevelButton = UIButton(type: .system)
    private var tagSections: [UIView] = []
    /// Every tag in any feed clip, built once; a level only updates counts and
    /// disables the tags none of its clips carry.
    private var tagPills: [ClipTagFilter: GlassTagControl] = [:]
    /// Drops a tag load that a newer level choice has overtaken.
    private var tagLoadGeneration = 0

    /// `onPlay`: play clips as a feed from the given one; nil pushes the feed here.
    init(onPlay: ClipFeedPlayHandler? = nil) {
        self.onPlay = onPlay
        super.init(nibName: nil, bundle: nil)
        title = "Explore Clips"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Opens the explorer on `controller`'s stack (or in its own sheet when there's no stack).
    static func open(from controller: UIViewController) {
        let explorer = ClipExplorerViewController()
        if let navigationController = controller.navigationController {
            navigationController.pushViewController(explorer, animated: true)
        } else {
            explorer.navigationItem.leftBarButtonItem = UIBarButtonItem(
                systemItem: .close,
                primaryAction: UIAction { [weak explorer] _ in explorer?.dismiss(animated: true) }
            )
            controller.present(UINavigationController(rootViewController: explorer), animated: true)
        }
    }

    /// Magnifying glass for a navigation bar: opens the explorer from `controller`.
    static func searchBarItem(pushingFrom controller: UIViewController) -> UIBarButtonItem {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "magnifyingglass"),
            primaryAction: UIAction { [weak controller] _ in
                guard let controller else { return }
                open(from: controller)
            }
        )
        item.accessibilityLabel = "Search clips"
        return item
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.pageBackground
        navigationItem.largeTitleDisplayMode = .never

        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchBar.delegate = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Title, channel, line or tag"
        searchController.searchBar.returnKeyType = .search
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .onDrag
        scrollView.alwaysBounceVertical = true
        stack.axis = .vertical
        stack.spacing = 28
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(makeLevelSection())

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
        ])

        Task { await loadTags() }
    }

    // MARK: Level

    /// N5…N1 as single-select pills, plus a link to every clip at the chosen level.
    private func makeLevelSection() -> UIView {
        let pills = Self.levels.map { level in
            let pill = GlassTagControl(title: "N\(level)")
            pill.isToggleable = true
            pill.accessibilityHint = "Shows the tags in N\(level) clips."
            pill.addAction(UIAction { [weak self, weak pill] _ in
                guard let self, let pill else { return }
                self.selectLevel(pill.isSelected ? level : nil)
            }, for: .valueChanged)
            levelPills[level] = pill
            return pill
        }
        let flow = GlassTagFlowView()
        flow.setTags(pills)
        flow.setContentCompressionResistancePriority(.required, for: .vertical)

        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "chevron.right")
        config.imagePlacement = .trailing
        config.imagePadding = 4
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .footnote, scale: .small)
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)
        allAtLevelButton.configuration = config
        allAtLevelButton.contentHorizontalAlignment = .leading
        allAtLevelButton.addAction(UIAction { [weak self] _ in
            guard let self, let level = self.selectedLevel else { return }
            self.openList(.level(level))
        }, for: .primaryActionTriggered)

        let section = makeSection(title: "Level", content: [flow, allAtLevelButton])
        updateLevelChrome()
        return section
    }

    private func selectLevel(_ level: Int?) {
        guard level != selectedLevel else { return }
        selectedLevel = level
        for (value, pill) in levelPills where pill.isSelected != (value == level) {
            pill.isSelected = value == level
        }
        updateLevelChrome()
        Task { await loadTags() }
    }

    private func updateLevelChrome() {
        if let level = selectedLevel {
            var config = allAtLevelButton.configuration
            config?.attributedTitle = AttributedString(
                "All N\(level) Clips",
                attributes: AttributeContainer([.font: UIFont.preferredFont(forTextStyle: .subheadline)])
            )
            allAtLevelButton.configuration = config
            allAtLevelButton.isHidden = false
            statusLabel.text = "Tags in N\(level) clips. Tap one for its N\(level) clips."
        } else {
            allAtLevelButton.isHidden = true
            statusLabel.text = "Choose a level, then a tag. Or tap a tag for every level, or search above."
        }
    }

    // MARK: Tags

    /// Builds the tag sections from every level once, then shows the chosen level's
    /// counts in place: tags with no clips at that level fade to disabled rather than
    /// disappearing, so nothing moves.
    private func loadTags() async {
        tagLoadGeneration += 1
        let generation = tagLoadGeneration
        let level = selectedLevel
        do {
            if tagPills.isEmpty {
                let all = try await ContentCMSClient.fetchClipFacets(feedOnly: true, jlptLevel: nil)
                guard generation == tagLoadGeneration else { return }
                buildTagSections(from: all)
            }
            let facets = level == nil
                ? nil
                : try await ContentCMSClient.fetchClipFacets(feedOnly: true, jlptLevel: level)
            guard generation == tagLoadGeneration else { return }
            if let facets { applyCounts(facets) } else { applyCounts(nil) }
        } catch {
            guard generation == tagLoadGeneration else { return }
            statusLabel.text = "Couldn’t load tags. \(error.localizedDescription)"
            return
        }
        if let level, !tagPills.values.contains(where: \.isEnabled) {
            statusLabel.text = "No N\(level) feed clips are tagged yet."
        } else {
            updateLevelChrome()
        }
    }

    /// Every level's counts, kept to restore when the level is cleared.
    private var allLevelCounts: [ClipTagFilter: Int] = [:]

    private func buildTagSections(from facets: [ClipTagFilter.Facet: [ContentCMSClient.ClipFacetValue]]) {
        tagSections.forEach { $0.removeFromSuperview() }
        tagPills = [:]
        allLevelCounts = [:]
        tagSections = Self.tagGroups.compactMap { title, facetList in
            let values = facetList.flatMap { facet in
                (facets[facet] ?? []).map { (ClipTagFilter(facet: facet, value: $0.value), $0.count) }
            }
            guard !values.isEmpty else { return nil }
            let pills = values.map { filter, count in
                let pill = GlassTagControl(title: filter.hashtag, detail: String(count))
                pill.isToggleable = false
                pill.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    self.openList(.tag(filter, level: self.selectedLevel))
                }, for: .primaryActionTriggered)
                tagPills[filter] = pill
                allLevelCounts[filter] = count
                return pill
            }
            let flow = GlassTagFlowView()
            flow.setTags(pills)
            flow.setContentCompressionResistancePriority(.required, for: .vertical)
            return makeSection(title: title, content: [flow])
        }
        tagSections.forEach { stack.addArrangedSubview($0) }
    }

    /// One level's counts (nil = every level) on the existing pills.
    private func applyCounts(_ facets: [ClipTagFilter.Facet: [ContentCMSClient.ClipFacetValue]]?) {
        var counts = allLevelCounts
        if let facets {
            counts = [:]
            for (facet, values) in facets {
                for value in values { counts[ClipTagFilter(facet: facet, value: value.value)] = value.count }
            }
        }
        for (filter, pill) in tagPills {
            let count = counts[filter] ?? 0
            pill.setDetail(String(count), animated: true)
            pill.isEnabled = count > 0
        }
    }

    /// A heading over its content (a wrapping flow of glass pills), as on the QA note.
    private func makeSection(title: String, content: [UIView]) -> UIView {
        let heading = UILabel()
        heading.text = title
        heading.font = .preferredFont(forTextStyle: .headline)
        heading.adjustsFontForContentSizeCategory = true
        heading.accessibilityTraits = .header

        let section = UIStackView(arrangedSubviews: [heading] + content)
        section.axis = .vertical
        section.spacing = 12
        return section
    }

    private func openList(_ query: ClipQuery) {
        navigationController?.pushViewController(
            ClipQueryListViewController(query: query, onPlay: onPlay),
            animated: true
        )
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        let text = (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        searchBar.resignFirstResponder()
        openList(.search(text, level: selectedLevel))
    }
}

// MARK: - List of Clips

/// What a List of Clips shows: a tag's clips, a search's, a channel's, or one
/// level's, any of them narrowed to a single JLPT level.
struct ClipQuery: Hashable {
    var tag: ClipTagFilter?
    var search: String?
    /// Exactly this YouTube channel name (searched on the server, matched exactly here).
    var channel: String?
    /// Exactly this JLPT level (5 = N5 … 1 = N1). Nil = every level.
    var level: Int?

    static func tag(_ filter: ClipTagFilter, level: Int? = nil) -> ClipQuery {
        ClipQuery(tag: filter, level: level)
    }

    static func search(_ text: String, level: Int? = nil) -> ClipQuery {
        ClipQuery(search: text, level: level)
    }

    static func level(_ level: Int) -> ClipQuery {
        ClipQuery(level: level)
    }

    static func channel(_ name: String, level: Int? = nil) -> ClipQuery {
        ClipQuery(channel: name, level: level)
    }

    var title: String {
        if let tag { return tag.hashtag }
        if let search { return "“\(search)”" }
        if let channel { return channel }
        if let level { return "N\(level)" }
        return "All Clips"
    }

    /// A tag's, search's or channel's list can switch levels; a level's list is already one level.
    var offersLevelPicker: Bool { tag != nil || search != nil || channel != nil }
}

/// One tag's (or search's) clips: Play All, Shuffle, or pick one.
final class ClipQueryListViewController: UIViewController, UICollectionViewDelegate {
    nonisolated private enum Section: Hashable {
        case header
        case clips
    }

    nonisolated private enum Item: Hashable {
        case header
        case clip(String)
        /// Loading, an error, or no matches.
        case status
    }

    private let onPlay: ClipFeedPlayHandler?
    private var query: ClipQuery
    private var clips: [ClipSummary] = []
    private var clipsByID: [String: ClipSummary] = [:]
    private var isLoading = true
    private var errorText: String?
    /// Drops a load that a newer level choice has overtaken.
    private var generation = 0

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: Self.makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    /// `onPlay`: play clips as a feed from the given one; nil pushes the feed here.
    init(query: ClipQuery, onPlay: ClipFeedPlayHandler? = nil) {
        self.query = query
        self.onPlay = onPlay
        super.init(nibName: nil, bundle: nil)
        title = query.title
    }

    convenience init(filter: ClipTagFilter, onPlay: ClipFeedPlayHandler? = nil) {
        self.init(query: .tag(filter), onPlay: onPlay)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground

        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = self
        collectionView.frame = view.bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(collectionView)

        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self, weak refresh] _ in
            Task {
                await self?.load()
                refresh?.endRefreshing()
            }
        }, for: .valueChanged)
        collectionView.refreshControl = refresh

        configureDataSource()
        applySnapshot()
        Task { await load() }
    }

    private static func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { sectionIndex, _ in
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(84))
            let group = NSCollectionLayoutGroup.vertical(
                layoutSize: size,
                subitems: [NSCollectionLayoutItem(layoutSize: size)]
            )
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 4
            section.contentInsets = sectionIndex == 0
                ? NSDirectionalEdgeInsets(top: 16, leading: 20, bottom: 20, trailing: 20)
                : NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 16, trailing: 20)
            return section
        }
    }

    private func configureDataSource() {
        let headerRegistration = UICollectionView.CellRegistration<ClipQueryHeaderCell, Item> { [weak self] cell, _, _ in
            guard let self else { return }
            cell.configure(
                title: self.query.title,
                subtitle: self.subtitle,
                level: self.query.offersLevelPicker ? .some(self.query.level) : nil,
                showsPlayButtons: !self.clips.isEmpty
            )
            cell.onPlayAll = { [weak self] in self?.play(startingAt: 0, shuffled: false) }
            cell.onShuffle = { [weak self] in self?.play(startingAt: 0, shuffled: true) }
            cell.onSelectLevel = { [weak self] level in
                Task { await self?.setLevel(level) }
            }
        }
        let clipRegistration = UICollectionView.CellRegistration<ClipQueryCell, Item> { [weak self] cell, _, item in
            guard case .clip(let id) = item, let clip = self?.clipsByID[id] else { return }
            cell.configure(clip: clip)
        }
        let statusRegistration = UICollectionView.CellRegistration<ClipQueryStatusCell, Item> { [weak self] cell, _, _ in
            guard let self else { return }
            if self.isLoading {
                cell.showLoading()
            } else {
                cell.show(message: self.emptyMessage)
            }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .header:
                collectionView.dequeueConfiguredReusableCell(using: headerRegistration, for: indexPath, item: item)
            case .clip:
                collectionView.dequeueConfiguredReusableCell(using: clipRegistration, for: indexPath, item: item)
            case .status:
                collectionView.dequeueConfiguredReusableCell(using: statusRegistration, for: indexPath, item: item)
            }
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.header, .clips])
        snapshot.appendItems([.header], toSection: .header)
        snapshot.appendItems(clips.isEmpty ? [.status] : clips.map { .clip($0.clipID) }, toSection: .clips)
        dataSource.apply(snapshot, animatingDifferences: false)
        // The header and status read the current state; refresh them in place.
        var refreshed = dataSource.snapshot()
        refreshed.reconfigureItems(refreshed.itemIdentifiers.filter { $0 == .header || $0 == .status })
        dataSource.apply(refreshed, animatingDifferences: false)
    }

    // MARK: State

    private var subtitle: String {
        if isLoading && clips.isEmpty { return "Loading…" }
        let count = clips.count == 1 ? "1 clip" : "\(clips.count) clips"
        if query.level != nil { return count }
        let levels = Set(clips.compactMap(\.jlptLevel))
        guard let easiest = levels.max(), let hardest = levels.min() else { return count }
        return easiest == hardest ? "\(count) · N\(easiest)" : "\(count) · N\(easiest)–N\(hardest)"
    }

    private var emptyMessage: String {
        if let errorText { return "Couldn’t load clips. \(errorText)" }
        if let level = query.level, query.offersLevelPicker { return "No N\(level) clips match. Try another level." }
        return "No clips match."
    }

    private func play(startingAt start: Int, shuffled: Bool) {
        guard !clips.isEmpty else { return }
        playClips(shuffled ? clips.shuffled() : clips, startingAt: start, handler: onPlay, from: self)
    }

    /// Narrows the list to one level (nil = every level) and reloads it.
    private func setLevel(_ level: Int?) async {
        guard level != query.level else { return }
        query.level = level
        clips = []
        clipsByID = [:]
        await load()
    }

    private func load() async {
        generation += 1
        let current = generation
        let query = query
        let filters = query.tag.map { [$0] } ?? []
        // The server has no channel filter, but its search covers channel names;
        // the exact match happens below.
        let search = query.search ?? query.channel ?? ""
        isLoading = true
        applySnapshot()
        do {
            // Feed clips only: the list plays as a feed.
            let fetched = try await ContentCMSClient.fetchClipList(
                jlptLevel: query.level,
                feedOnly: true,
                filters: filters,
                search: search
            )
            guard current == generation else { return }
            var seen = Set<String>()
            clips = Self.locallyFiltered(fetched, filters: filters, search: search)
                .filter { $0.isInFeed && (query.level == nil || $0.jlptLevel == query.level) }
                .filter { query.channel == nil || $0.channelName?.trimmingCharacters(in: .whitespacesAndNewlines) == query.channel }
                .filter { seen.insert($0.clipID).inserted }
            clipsByID = Dictionary(uniqueKeysWithValues: clips.map { ($0.clipID, $0) })
            errorText = nil
        } catch {
            guard current == generation else { return }
            errorText = error.localizedDescription
        }
        isLoading = false
        applySnapshot()
    }

    /// The server already filters; this repeats it so a server from before
    /// search, tags, feed or exact level (which ignores the params) still shows
    /// the right clips.
    private static func locallyFiltered(_ clips: [ClipSummary], filters: [ClipTagFilter], search: String) -> [ClipSummary] {
        clips.filter { clip in
            for filter in filters {
                let has: [String] = switch filter.facet {
                case .format: [clip.tags?.format].compactMap { $0 }
                case .topic: clip.tags?.topics ?? []
                case .register: [clip.tags?.register].compactMap { $0 }
                case .speakers: [clip.tags?.speakers].compactMap { $0 }
                case .dialect: [clip.tags?.dialect].compactMap { $0 }
                case .pace: [clip.pace?.label].compactMap { $0 }
                case .series: [clip.tags?.series].compactMap { $0 }
                }
                if !has.contains(filter.value) { return false }
            }
            guard !search.isEmpty else { return true }
            let haystack = [clip.title, clip.titleEN, clip.channelName, clip.previewJP, clip.clipID]
                + (clip.tags.map { $0.filters(pace: clip.pace).map(\.value) } ?? [])
            return haystack.contains { $0?.localizedCaseInsensitiveContains(search) == true }
        }
    }

    // MARK: UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        if case .clip = dataSource.itemIdentifier(for: indexPath) { return true }
        return false
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard case .clip(let id) = dataSource.itemIdentifier(for: indexPath),
              let index = clips.firstIndex(where: { $0.clipID == id }) else { return }
        play(startingAt: index, shuffled: false)
    }
}

// MARK: - List cells

/// Title, count and levels, the level picker, and Play All / Shuffle.
private final class ClipQueryHeaderCell: UICollectionViewCell {
    private static let levels = [5, 4, 3, 2, 1]

    var onPlayAll: (() -> Void)?
    var onShuffle: (() -> Void)?
    var onSelectLevel: ((Int?) -> Void)?

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let levelControl = UISegmentedControl(items: ["All"] + levels.map { "N\($0)" })
    private let buttonsRow = UIStackView()
    private var stack: UIStackView?

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(
            for: .systemFont(ofSize: 34, weight: .bold)
        )
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2
        titleLabel.accessibilityTraits = .header

        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        levelControl.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let index = self.levelControl.selectedSegmentIndex
            self.onSelectLevel?(index > 0 ? Self.levels[index - 1] : nil)
        }, for: .valueChanged)

        buttonsRow.addArrangedSubview(Self.makeButton(
            title: "Play All",
            symbol: "play.fill",
            configuration: .prominentGlass()
        ) { [weak self] in self?.onPlayAll?() })
        buttonsRow.addArrangedSubview(Self.makeButton(
            title: "Shuffle",
            symbol: "shuffle",
            configuration: .glass()
        ) { [weak self] in self?.onShuffle?() })
        buttonsRow.spacing = 12
        buttonsRow.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, levelControl, buttonsRow])
        stack.axis = .vertical
        stack.spacing = 14
        stack.setCustomSpacing(18, after: levelControl)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        self.stack = stack
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `level`: nil hides the picker; `.some(nil)` selects All.
    func configure(title: String, subtitle: String, level: Int??, showsPlayButtons: Bool) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        if let level {
            levelControl.isHidden = false
            levelControl.selectedSegmentIndex = level.flatMap { Self.levels.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        } else {
            levelControl.isHidden = true
        }
        buttonsRow.isHidden = !showsPlayButtons
        // The buttons sit a little further down than the rest.
        stack?.setCustomSpacing(levelControl.isHidden ? 18 : 14, after: subtitleLabel)
    }

    private static func makeButton(
        title: String,
        symbol: String,
        configuration: UIButton.Configuration,
        action: @escaping () -> Void
    ) -> UIButton {
        var config = configuration
        config.title = title
        config.image = UIImage(systemName: symbol)
        config.imagePadding = 6
        config.buttonSize = .large
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.preferredFont(forTextStyle: .headline)
            return attributes
        }
        return UIButton(configuration: config, primaryAction: UIAction { _ in action() })
    }
}

/// Thumbnail with its length, title, first line, and level · pace · channel.
private final class ClipQueryCell: UICollectionViewCell {
    private let thumbnailView = UIImageView()
    private let durationLabel = PaddedLabel()
    private let titleLabel = UILabel()
    private let previewLabel = UILabel()
    private let detailLabel = UILabel()
    private var videoID: String?
    private var thumbnailTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)

        thumbnailView.backgroundColor = .tertiarySystemFill
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.layer.cornerRadius = 10
        thumbnailView.layer.cornerCurve = .continuous

        durationLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        durationLabel.textColor = .white
        durationLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        durationLabel.layer.cornerRadius = 4
        durationLabel.layer.masksToBounds = true

        titleLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 15, weight: .semibold))
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2

        previewLabel.font = .preferredFont(forTextStyle: .footnote)
        previewLabel.adjustsFontForContentSizeCategory = true
        previewLabel.textColor = .secondaryLabel

        detailLabel.font = .preferredFont(forTextStyle: .caption1)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .tertiaryLabel

        let text = UIStackView(arrangedSubviews: [titleLabel, previewLabel, detailLabel])
        text.axis = .vertical
        text.spacing = 4

        for view in [thumbnailView, durationLabel, text] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }
        let bottom = text.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8)
        let thumbBottom = thumbnailView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8)
        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 120),
            thumbnailView.heightAnchor.constraint(equalToConstant: 68),
            thumbBottom,

            durationLabel.trailingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: -5),
            durationLabel.bottomAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: -5),

            text.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            text.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 14),
            text.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottom,
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { contentView.alpha = isHighlighted ? 0.6 : 1 }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailTask?.cancel()
        thumbnailTask = nil
    }

    func configure(clip: ClipSummary) {
        let title = clip.title ?? clip.previewJP
        titleLabel.text = title
        previewLabel.text = clip.previewJP
        var parts: [String] = []
        if let level = clip.jlptLevel { parts.append("N\(level)") }
        if let pace = clip.pace { parts.append(pace.label.capitalized) }
        if let channel = clip.channelName { parts.append(channel) }
        detailLabel.text = parts.joined(separator: " · ")
        let total = max(0, Int((clip.endSec - clip.startSec).rounded(.down)))
        durationLabel.text = String(format: "%d:%02d", total / 60, total % 60)
        accessibilityLabel = [title, clip.previewJP, detailLabel.text].compactMap { $0 }.joined(separator: ", ")

        guard clip.videoID != videoID || thumbnailView.image == nil else { return }
        videoID = clip.videoID
        thumbnailTask?.cancel()
        if let cached = ClipThumbnail.cached(videoID: clip.videoID) {
            thumbnailView.image = cached
            return
        }
        thumbnailView.image = nil
        let videoID = clip.videoID
        thumbnailTask = Task { [weak self] in
            let image = await ClipThumbnail.image(videoID: videoID)
            guard let self, !Task.isCancelled, self.videoID == videoID, let image else { return }
            UIView.transition(with: self.thumbnailView, duration: 0.2, options: .transitionCrossDissolve) {
                self.thumbnailView.image = image
            }
        }
    }
}

/// A spinner while loading, else a message (no matches, or an error).
private final class ClipQueryStatusCell: UICollectionViewCell {
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()
    private var stack: UIStackView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        self.stack = stack
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showLoading() {
        // Down from the header a little, as a page-level spinner.
        stack?.isLayoutMarginsRelativeArrangement = true
        stack?.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 40, leading: 0, bottom: 0, trailing: 0)
        label.isHidden = true
        spinner.isHidden = false
        spinner.startAnimating()
    }

    func show(message: String) {
        stack?.isLayoutMarginsRelativeArrangement = false
        spinner.stopAnimating()
        spinner.isHidden = true
        label.isHidden = false
        label.text = message
    }
}

/// A label with a little room around its text (the thumbnail's length badge).
private final class PaddedLabel: UILabel {
    private let insets = UIEdgeInsets(top: 2, left: 5, bottom: 2, right: 5)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}
