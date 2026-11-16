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

/// Hands out clips a batch at a time, paging through the server's feed list
/// (`?limit=&cursor=`) as the viewer nears the end of what's loaded.
@MainActor
private final class ClipFeedSource {
    /// Clips per server request; a few batches' worth, so most top-ups are local.
    private static let pageSize = 10

    private let learnerLevel: Int?
    private var buffer: [ClipSummary] = []
    private var cursor: String?
    private var reachedEnd = false
    private var seen = Set<String>()

    init(learnerLevel: Int?) {
        self.learnerLevel = learnerLevel
    }

    /// A fixed set of clips (e.g. every clip from one video), in the order given.
    init(clips: [ClipSummary]) {
        learnerLevel = nil
        buffer = clips
        reachedEnd = true
    }

    var hasMore: Bool { !buffer.isEmpty || !reachedEnd }

    func nextBatch(count: Int) async throws -> [ClipSummary] {
        while buffer.count < count, !reachedEnd {
            let page = try await ContentCMSClient.fetchClipPage(
                learnerLevel: learnerLevel,
                feedOnly: true,
                limit: Self.pageSize,
                cursor: cursor
            )
            // A clip re-saved between pages can't show up twice.
            buffer.append(contentsOf: page.clips.filter { seen.insert($0.clipID).inserted })
            cursor = page.nextCursor
            reachedEnd = page.nextCursor == nil
        }
        let batch = Array(buffer.prefix(count))
        buffer.removeFirst(batch.count)
        return batch
    }
}

final class ClipFeedViewController: UIViewController, UIScrollViewDelegate {

    enum Presentation {
        /// Pushed or presented on a navigation stack: the clip menu goes in the navigation bar.
        case pushed
        /// A page of the main screen: playback follows `setActive(_:)`, and the main
        /// screen shows the clip menu (`currentClipMenu`) in its own navigation bar.
        case mainTab
    }

    /// Clips added per fetch.
    private static let batchSize = 3
    /// Top up when this many clips or fewer remain after the current one.
    private static let prefetchRemaining = 1
    /// Clips either side of the current one that keep a live player.
    private static let liveNeighbors = 1
    private static let pageCommitThreshold: CGFloat = 0.52
    private static let pageVelocityThreshold: CGFloat = 1.15
    /// 1:1 so a transcript overscroll moves the feed like a direct drag does.
    private static let pageTransitionResistance: CGFloat = 1

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
    private let presentation: Presentation
    /// Whether this feed is on screen and allowed to play. Pushed feeds are always active.
    private(set) var isActive = true
    var hasClips: Bool { !clips.isEmpty }
    /// Main tab: the viewer moved to another clip.
    var onClipChanged: (() -> Void)?
    /// The current clip's options menu, for a host that shows it in its own navigation bar.
    var currentClipMenu: UIMenu? { pages[currentIndex]?.navigationMenuItem?.menu }

    init(learnerLevel: Int?, presentation: Presentation = .pushed) {
        source = ClipFeedSource(learnerLevel: learnerLevel)
        self.presentation = presentation
        super.init(nibName: nil, bundle: nil)
        title = "Feed"
    }

    /// Plays exactly these clips, in order (Clip Details → More From This Video → Play All).
    /// With `startingAt`, opens on that clip and carries on through the rest, wrapping
    /// round to the ones before it (the Feed tab opening on the card you tapped).
    init(clips: [ClipSummary], startingAt start: Int = 0) {
        let start = clips.indices.contains(start) ? start : 0
        source = ClipFeedSource(clips: Array(clips[start...] + clips[..<start]))
        presentation = .pushed
        super.init(nibName: nil, bundle: nil)
        title = "Feed"
    }

    /// Wraps the feed for full-screen presentation from the Feed tab: ✕ to close, and the
    /// clip menu in its own navigation bar.
    static func makePresented(clips: [ClipSummary], startingAt start: Int) -> UINavigationController {
        let feed = ClipFeedViewController(clips: clips, startingAt: start)
        feed.navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak feed] _ in feed?.dismiss(animated: true) }
        )
        let nav = UINavigationController(rootViewController: feed)
        nav.modalPresentationStyle = .fullScreen
        return nav
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

    /// Plays the current clip when the feed comes on screen, pauses it when it leaves.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            pages[currentIndex]?.startPlayback()
        } else {
            pages[currentIndex]?.pausePlayback()
        }
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
            if isFirstBatch, isActive { pages[currentIndex]?.startPlayback() }
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
            page.onFeedPan = { [weak self] pan in
                self?.handleFeedPan(pan)
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

    // MARK: - Direct drag (outside the transcript)

    /// Past the first or last clip, the pager moves this much per point dragged.
    private static let edgeRubberBand: CGFloat = 0.3
    /// Release past this share of a page, or faster than `flickVelocity`, to change clips.
    private static let dragCommitFraction: CGFloat = 0.35
    private static let flickVelocity: CGFloat = 500
    private var dragStartOffsetY: CGFloat = 0

    /// Moves the pager 1:1 with the finger, then springs to the nearest clip
    /// (or the next one on a flick) through the coordinator so page changes fire once.
    private func handleFeedPan(_ pan: UIPanGestureRecognizer) {
        let pageHeight = pagerScrollView.bounds.height
        guard pageHeight > 0, !clips.isEmpty else { return }
        // Measured in the feed's view: the page itself moves under the finger.
        let translation = pan.translation(in: view).y
        switch pan.state {
        case .began:
            pagerScrollView.layer.removeAllAnimations()
            dragStartOffsetY = pagerScrollView.contentOffset.y
        case .changed:
            let maxY = CGFloat(clips.count - 1) * pageHeight
            var y = dragStartOffsetY - translation
            if y < 0 {
                y *= Self.edgeRubberBand
            } else if y > maxY {
                y = maxY + (y - maxY) * Self.edgeRubberBand
            }
            pagerScrollView.contentOffset.y = y
        case .ended, .cancelled, .failed:
            let velocity = pan.state == .ended ? pan.velocity(in: view).y : 0
            let progress = (pagerScrollView.contentOffset.y - CGFloat(currentIndex) * pageHeight) / pageHeight
            var target = currentIndex
            if progress > Self.dragCommitFraction || (progress > 0 && velocity < -Self.flickVelocity) {
                target += 1
            } else if progress < -Self.dragCommitFraction || (progress < 0 && velocity > Self.flickVelocity) {
                target -= 1
            }
            target = min(max(target, 0), clips.count - 1)
            coordinator?.snapToPage(target)
        default:
            break
        }
    }

    private func pageDidChange(to page: Int) {
        guard page != currentIndex, clips.indices.contains(page) else { return }
        pages[currentIndex]?.pausePlayback()
        currentIndex = page
        syncPages()
        if isActive { pages[page]?.startPlayback() }
        topUpIfNeeded()
        onClipChanged?()
    }

    /// The clip's options menu lives in the feed's navigation bar (on the main tab, the
    /// main screen's bar reads `currentClipMenu` instead).
    private func syncNavigationItem() {
        guard presentation == .pushed else { return }
        navigationItem.rightBarButtonItem = pages[currentIndex]?.navigationMenuItem
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pages[currentIndex]?.pausePlayback()
    }

    /// Main tab: back from a pushed screen (Settings) with the feed still on screen.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if presentation == .mainTab, isActive { pages[currentIndex]?.startPlayback() }
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
