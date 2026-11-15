//
//  ClipFeedViewController.swift
//  shizen
//
//  Experiment: a vertical feed of clips. Each page is a full ClipPlayerViewController;
//  scrolling the transcript past its top or bottom hands off to the next or previous
//  clip (the same handoff the dialogue lesson uses between pages). Highlights open as a
//  sheet in the feed, since vertical swipe now means "next clip".
//
//  The feed holds a growing array of clips, served a batch at a time, and tops it up
//  when the viewer gets near the end. Only the current clip and its neighbours have a
//  live player, so a long feed doesn't hold a web view per clip.
//

import UIKit

/// Hands out clips a batch at a time. Today it pages through the one list response;
/// a server cursor (`?after=&limit=`) would slot in behind the same interface.
@MainActor
private final class ClipFeedSource {
    private let learnerLevel: Int?
    private var queue: [ClipSummary] = []
    private var didFetch = false

    init(learnerLevel: Int?) {
        self.learnerLevel = learnerLevel
    }

    var hasMore: Bool { !queue.isEmpty }

    func nextBatch(count: Int) async throws -> [ClipSummary] {
        if !didFetch {
            queue = try await ContentCMSClient.fetchClipList(learnerLevel: learnerLevel)
            didFetch = true
        }
        let batch = Array(queue.prefix(count))
        queue.removeFirst(batch.count)
        return batch
    }
}

final class ClipFeedViewController: UIViewController, UIScrollViewDelegate {

    /// Clips added per fetch.
    private static let batchSize = 3
    /// Top up when this many clips or fewer remain after the current one.
    private static let prefetchRemaining = 1
    /// Clips either side of the current one that keep a live player.
    private static let liveNeighbors = 1
    private static let pageCommitThreshold: CGFloat = 0.52
    private static let pageVelocityThreshold: CGFloat = 1.15
    private static let pageTransitionResistance: CGFloat = 0.52

    private let source: ClipFeedSource
    private var clips: [ClipSummary] = []
    private var currentIndex = 0
    private var isFetching = false

    private let pagerScrollView = UIScrollView()
    private var pages: [Int: ClipPlayerViewController] = [:]
    /// Stand-ins for pages without a live player, so inner scroll views line up with page indices.
    private var placeholders: [Int: UIScrollView] = [:]
    private var coordinator: NestedVerticalScrollHandoffCoordinator?
    private let spinner = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()

    init(learnerLevel: Int?) {
        source = ClipFeedSource(learnerLevel: learnerLevel)
        super.init(nibName: nil, bundle: nil)
        title = "Feed"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.pageBackground
        navigationItem.largeTitleDisplayMode = .never

        // Moved only by the handoff coordinator, like the dialogue lesson's outer pager.
        pagerScrollView.isPagingEnabled = true
        pagerScrollView.isScrollEnabled = false
        pagerScrollView.showsVerticalScrollIndicator = false
        pagerScrollView.alwaysBounceVertical = false
        pagerScrollView.contentInsetAdjustmentBehavior = .never
        pagerScrollView.clipsToBounds = true
        pagerScrollView.decelerationRate = .fast
        view.addSubview(pagerScrollView)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])

        spinner.startAnimating()
        Task { await fetchNextBatch() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPages()
    }

    // MARK: - Data

    private func fetchNextBatch() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            let batch = try await source.nextBatch(count: Self.batchSize)
            spinner.stopAnimating()
            guard !batch.isEmpty else {
                if clips.isEmpty { statusLabel.text = "No aligned clips yet." }
                return
            }
            statusLabel.text = nil
            let isFirstBatch = clips.isEmpty
            clips.append(contentsOf: batch)
            if isFirstBatch {
                installCoordinator()
                navigationItem.title = nil
            }
            syncPages()
            if isFirstBatch { pages[currentIndex]?.startPlayback() }
        } catch {
            spinner.stopAnimating()
            if clips.isEmpty { statusLabel.text = "Couldn’t load clips. \(error.localizedDescription)" }
        }
    }

    /// Keeps a clip or two ahead of the viewer.
    private func topUpIfNeeded() {
        guard source.hasMore, clips.count - 1 - currentIndex <= Self.prefetchRemaining else { return }
        Task { await fetchNextBatch() }
    }

    // MARK: - Pages

    private func placeholder(for index: Int) -> UIScrollView {
        if let existing = placeholders[index] { return existing }
        let scrollView = UIScrollView()
        placeholders[index] = scrollView
        return scrollView
    }

    private func innerScrollViews() -> [UIScrollView] {
        clips.indices.map { pages[$0]?.transcriptScrollView ?? placeholder(for: $0) }
    }

    private func installCoordinator() {
        // Pages need a real height before the coordinator reads the pager's size.
        view.layoutIfNeeded()
        layoutPages()
        syncPages(updatingCoordinator: false)
        let coordinator = NestedVerticalScrollHandoffCoordinator(
            outerScrollView: pagerScrollView,
            innerScrollViews: innerScrollViews(),
            pageCommitThreshold: Self.pageCommitThreshold,
            velocityThreshold: Self.pageVelocityThreshold,
            pageTransitionResistance: Self.pageTransitionResistance
        )
        coordinator.forwardingDelegate = self
        coordinator.onPageChanged = { [weak self] page in
            self?.pageDidChange(to: page)
        }
        self.coordinator = coordinator
    }

    /// Creates players for the current clip and its neighbours, drops the rest.
    private func syncPages(updatingCoordinator: Bool = true) {
        let lower = max(0, currentIndex - Self.liveNeighbors)
        let upper = min(clips.count - 1, currentIndex + Self.liveNeighbors)
        let wanted = lower <= upper ? Set(lower ... upper) : []

        for index in pages.keys where !wanted.contains(index) {
            guard let page = pages.removeValue(forKey: index) else { continue }
            page.willMove(toParent: nil)
            page.view.removeFromSuperview()
            page.removeFromParent()
        }
        for index in wanted.sorted() where pages[index] == nil {
            let clip = clips[index]
            let page = ClipPlayerViewController(clipID: clip.clipID, preview: clip)
            page.isInFeed = true
            page.onSwipeToAdjacentClip = { [weak self] step in
                guard let self else { return }
                self.coordinator?.snapToPage(min(max(self.currentIndex + step, 0), self.clips.count - 1))
            }
            addChild(page)
            pagerScrollView.addSubview(page.view)
            page.didMove(toParent: self)
            page.loadViewIfNeeded()
            pages[index] = page
        }
        layoutPages()
        if updatingCoordinator {
            // Re-claims the transcripts' delegates for the feed's handoff.
            coordinator?.replaceInnerScrollViews(innerScrollViews())
        }
        syncNavigationItem()
    }

    private func layoutPages() {
        let bounds = view.bounds
        guard bounds.height > 0 else { return }
        pagerScrollView.frame = bounds
        let contentHeight = bounds.height * CGFloat(max(clips.count, 1))
        if pagerScrollView.contentSize != CGSize(width: bounds.width, height: contentHeight) {
            pagerScrollView.contentSize = CGSize(width: bounds.width, height: contentHeight)
        }
        for (index, page) in pages {
            page.feedSafeAreaInsets = view.safeAreaInsets
            let frame = CGRect(x: 0, y: CGFloat(index) * bounds.height, width: bounds.width, height: bounds.height)
            if page.view.frame != frame { page.view.frame = frame }
        }
    }

    private func pageDidChange(to page: Int) {
        guard page != currentIndex, clips.indices.contains(page) else { return }
        pages[currentIndex]?.pausePlayback()
        currentIndex = page
        syncPages()
        pages[page]?.startPlayback()
        topUpIfNeeded()
    }

    /// The clip's options menu lives in the feed's navigation bar.
    private func syncNavigationItem() {
        navigationItem.rightBarButtonItem = pages[currentIndex]?.navigationMenuItem
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pages[currentIndex]?.pausePlayback()
    }

    // MARK: - Scroll forwarding (the coordinator is every transcript's delegate)

    private func page(owning scrollView: UIScrollView) -> ClipPlayerViewController? {
        pages.values.first { $0.transcriptScrollView === scrollView }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        page(owning: scrollView)?.scrollViewWillBeginDragging(scrollView)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        page(owning: scrollView)?.scrollViewDidScroll(scrollView)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        page(owning: scrollView)?.scrollViewDidEndDragging(scrollView, willDecelerate: decelerate)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        page(owning: scrollView)?.scrollViewDidEndDecelerating(scrollView)
    }
}
