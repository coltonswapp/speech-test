//
//  MainViewController.swift
//  shizen
//
//  Root container with swipeable sections and category tab bar.
//

import UIKit

final class MainViewController: UIViewController {
    private enum MainSection: Int, CaseIterable {
        case dialogue
        case practice
        case feed

        /// Sections shown as tabs, in order (raw values must match their index).
        /// The clip feed is an experiment: Debug builds only for now.
        static var visible: [MainSection] {
            #if DEBUG
            return [.dialogue, .practice, .feed]
            #else
            return [.dialogue, .practice]
            #endif
        }

        var title: String {
            switch self {
            case .dialogue: return "Dialogue"
            case .practice: return "Practice"
            case .feed: return "Feed"
            }
        }

        func makeViewController() -> UIViewController {
            switch self {
            case .dialogue:
                let flow = DialogueHomeViewController()
                flow.title = nil
                return flow
            case .practice:
                let flow = PracticeHomeViewController()
                flow.title = nil
                return flow
            case .feed:
                let feed = MainFeedTabViewController()
                feed.topOverlayHeight = GameCategoryTabBar.layoutHeight
                return feed
            }
        }
    }

    private lazy var tabBar = GameCategoryTabBar(
        titles: MainSection.visible.map { $0 == .dialogue ? Self.dialogueTabTitle() : $0.title },
        initialSelectedIndex: MainSection.dialogue.rawValue
    )
    private let pagingScrollView = HorizontalPagingScrollView()
    private let pagesStackView = UIStackView()
    private var pageViewControllers: [UIViewController] = []
    private var isUpdatingFromScroll = false
    private var lastPagerHapticPageIndex = MainSection.dialogue.rawValue
    private var didApplyDefaultTabSelection = false
    /// The tab to hold while a rotation or window resize changes the pager's width.
    private var pageIndexAcrossResize: Int?
    private var lastPagerLayoutWidth: CGFloat = 0
    private var lastAppliedMainTabTopInset: CGFloat = -1
    private var trackedVerticalScrollPageIndex = 0
    private var lastObservedVerticalOffset: CGFloat = 0
    private var verticalScrollObservations: [NSKeyValueObservation] = []
    private var authObserver: NSObjectProtocol?
    private var isPresentingAuthGate = false
    /// The clip menu button while the feed is immersive; nil otherwise.
    private var feedOptionsItem: UIBarButtonItem?
    /// The feed tab is the nearest page, so the bar shows its expand button.
    private var isFeedPageActive = false
    /// Immersive feed only: a progressive blur from the top of the screen that thins out
    /// and ends `feedTopBlurFade` points below the navigation bar.
    private let feedTopBlur = ProgressiveBlurView(style: .systemUltraThinMaterial, steps: 4)
    private static let feedTopBlurFade: CGFloat = 12
    /// The variable blur has no material tint, so it runs at full opacity; its strength
    /// is `ProgressiveBlurView.maxRadius`.
    private static let feedTopBlurOpacity: CGFloat = 1

    private static let verticalScrollTopRevealThreshold: CGFloat = 12
    private static let verticalScrollDirectionThreshold: CGFloat = 2
    /// Content must sit above the bottom edge by at least this much before scroll-up can expand tabs.
    private static let verticalScrollBottomExpandDistance: CGFloat = 48
    private static let tabPagerSnapAnimationDuration: TimeInterval = 0.22

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Shizen"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground
        setupPager()
        installPages()
        setupFeedTopBlur()
        setupTabBar()
        setupNavigationBar()
        tabBar.delegate = self
        pagingScrollView.delegate = self
        configureLessonTrackMenu()
        installVerticalScrollObservers()
        observeAuthGate()
    }

    deinit {
        if let authObserver {
            NotificationCenter.default.removeObserver(authObserver)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.main.async { [weak self] in
            self?.presentAuthGateIfNeeded()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyMainTabScrollInsetsToPagesIfNeeded()
        applyDefaultTabSelectionIfNeeded()
        keepPagerOnPageAcrossResize()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        // Read the page while the offset still matches the old width.
        pageIndexAcrossResize = activePageIndex
        isUpdatingFromScroll = true
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.keepPagerOnPageAcrossResize()
        }, completion: { [weak self] _ in
            guard let self else { return }
            self.keepPagerOnPageAcrossResize(force: true)
            self.pageIndexAcrossResize = nil
            self.isUpdatingFromScroll = false
        })
    }

    /// The pager's offset is `page × width`, so a rotation or window resize leaves it
    /// between two tabs. Snap it back onto the page it was showing.
    private func keepPagerOnPageAcrossResize(force: Bool = false) {
        let width = pagingScrollView.bounds.width
        guard width > 0, didApplyDefaultTabSelection else { return }
        defer { lastPagerLayoutWidth = width }
        guard force || (lastPagerLayoutWidth > 0 && abs(width - lastPagerLayoutWidth) > 0.5) else { return }
        guard !pagingScrollView.isDragging, !pagingScrollView.isDecelerating else { return }

        let page = max(0, min(pageIndexAcrossResize ?? lastPagerHapticPageIndex, pageViewControllers.count - 1))
        let wasUpdatingFromScroll = isUpdatingFromScroll
        isUpdatingFromScroll = true
        pagingScrollView.layoutIfNeeded()
        pagingScrollView.contentOffset = CGPoint(x: width * CGFloat(page), y: 0)
        isUpdatingFromScroll = wasUpdatingFromScroll
        lastPagerHapticPageIndex = page
        tabBar.setPageProgress(CGFloat(page), animated: false)
        tabBar.syncScrollPositionToSelection(animated: false)
    }

    private func applyDefaultTabSelectionIfNeeded() {
        guard !didApplyDefaultTabSelection else { return }
        let width = pagingScrollView.bounds.width
        guard width > 0 else { return }
        didApplyDefaultTabSelection = true

        let defaultIndex = MainSection.dialogue.rawValue
        pagingScrollView.contentOffset = CGPoint(x: width * CGFloat(defaultIndex), y: 0)
        tabBar.syncScrollPositionToSelection(animated: false)
        lastPagerHapticPageIndex = defaultIndex
        resetVerticalScrollTrackingForActivePage()
        updateFeedActivity()
    }

    // MARK: - Navigation

    /// Sets whole item arrays: the feed puts several items on the right, and assigning
    /// `rightBarButtonItem` would only replace the first (leaving the others behind).
    private func setupNavigationBar(animated: Bool = false) {
        let settings = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(openSettings)
        )
        var right = [settings]
        if isFeedPageActive, let feed = feedPage {
            right.append(feedModeItem(feed: feed, immersive: false))
        }
        navigationItem.setRightBarButtonItems(right, animated: animated)
        navigationItem.setLeftBarButtonItems([makeDictionaryItem()], animated: animated)
    }

    private func makeDictionaryItem() -> UIBarButtonItem {
        UIBarButtonItem(
            image: UIImage(systemName: "character.book.closed"),
            style: .plain,
            target: self,
            action: #selector(openDictionary)
        )
    }

    /// Expands into the full feed, or (when `immersive`) collapses back out of it.
    private func feedModeItem(feed: MainFeedTabViewController, immersive: Bool) -> UIBarButtonItem {
        let item = UIBarButtonItem(
            image: UIImage(systemName: immersive
                ? "arrow.down.forward.and.arrow.up.backward"
                : "arrow.up.backward.and.arrow.down.forward"),
            primaryAction: UIAction { [weak feed] _ in feed?.toggleImmersive() }
        )
        item.accessibilityLabel = immersive ? "Exit full feed" : "Full feed"
        // Its own glass capsule, apart from the settings / clip-menu group beside it.
        item.sharesBackground = false
        return item
    }

    private var feedPage: MainFeedTabViewController? {
        pageViewControllers.lazy.compactMap { $0 as? MainFeedTabViewController }.first
    }

    @objc private func openDictionary() {
        let vc = DictionarySearchViewController()
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    @objc private func openSettings() {
        navigationController?.pushViewController(SettingsViewController(), animated: true)
    }

    // MARK: - Auth gate

    private func observeAuthGate() {
        guard authObserver == nil else { return }
        authObserver = NotificationCenter.default.addObserver(
            forName: AuthService.userDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.presentAuthGateIfNeeded()
            }
        }
    }

    private func presentAuthGateIfNeeded() {
        guard view.window != nil else { return }
        guard AuthService.shared.userId == nil else {
            presentAccessGateIfNeeded()
            return
        }
        presentLoginSheet()
    }

    /// Signed in without a trial or subscription: listen-first until its lesson steps are done
    /// for this uid, then just the paywall. Nothing leads into the app without access.
    private func presentAccessGateIfNeeded() {
        guard !ProMembership.hasAccess, !isPresentingAuthGate else { return }
        let presenter = navigationController ?? self
        if let presented = presenter.presentedViewController {
            // The login sheet calls back here once it's gone.
            if presented is ListenFirstOnboardingHostController
                || presented.restorationIdentifier == AuthLandingViewController.presentationIdentifier {
                return
            }
            isPresentingAuthGate = true
            presenter.dismiss(animated: false) { [weak self] in
                self?.isPresentingAuthGate = false
                self?.presentAuthGateIfNeeded()
            }
            return
        }
        let mode: ListenFirstOnboardingHostController.Mode =
            OnboardingStore.hasFinishedLessonStepsForCurrentUser ? .paywallOnly : .fullFlow
        presenter.present(ListenFirstOnboardingHostController(mode: mode), animated: false)
    }

    private func presentLoginSheet() {
        guard view.window != nil else { return }
        guard AuthService.shared.userId == nil else { return }
        let presenter = navigationController ?? self
        if presenter.presentedViewController?.restorationIdentifier == AuthLandingViewController.presentationIdentifier {
            return
        }
        guard !isPresentingAuthGate else { return }

        if presenter.presentedViewController != nil {
            isPresentingAuthGate = true
            presenter.dismiss(animated: true) { [weak self] in
                self?.isPresentingAuthGate = false
                self?.presentLoginSheet()
            }
            return
        }

        if let navigationController, navigationController.viewControllers.count > 1 {
            isPresentingAuthGate = true
            navigationController.popToRootViewController(animated: true)
            let finish = { [weak self] in
                self?.isPresentingAuthGate = false
                self?.presentLoginSheet()
            }
            if let coordinator = navigationController.transitionCoordinator {
                coordinator.animate(alongsideTransition: nil) { _ in finish() }
            } else {
                finish()
            }
            return
        }

        // Closing a page sheet doesn't run this screen's `viewDidAppear`, so route from its callback.
        let sheet = AuthLandingViewController.makeLoginSheet { [weak self] in
            self?.presentAuthGateIfNeeded()
        }
        presenter.present(sheet, animated: true)
    }

    // MARK: - Layout

    private func setupFeedTopBlur() {
        feedTopBlur.translatesAutoresizingMaskIntoConstraints = false
        feedTopBlur.isUserInteractionEnabled = false
        feedTopBlur.alpha = 0
        view.addSubview(feedTopBlur)
        NSLayoutConstraint.activate([
            feedTopBlur.topAnchor.constraint(equalTo: view.topAnchor),
            feedTopBlur.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            feedTopBlur.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            feedTopBlur.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: Self.feedTopBlurFade
            ),
        ])
    }

    private func setupTabBar() {
        view.addSubview(tabBar)
        view.bringSubviewToFront(tabBar)
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupPager() {
        pagingScrollView.translatesAutoresizingMaskIntoConstraints = false
        pagingScrollView.backgroundColor = .clear
        pagingScrollView.topEdgeEffect.style = .soft
        pagingScrollView.topEdgeEffect.isHidden = false
        pagingScrollView.delaysContentTouches = false
        view.addSubview(pagingScrollView)

        pagesStackView.translatesAutoresizingMaskIntoConstraints = false
        pagesStackView.axis = .horizontal
        pagesStackView.alignment = .fill
        pagesStackView.distribution = .fill
        pagesStackView.spacing = 0
        pagingScrollView.addSubview(pagesStackView)

        NSLayoutConstraint.activate([
            pagingScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            pagingScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pagingScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pagingScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            pagesStackView.topAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.topAnchor),
            pagesStackView.leadingAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.leadingAnchor),
            pagesStackView.trailingAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.trailingAnchor),
            pagesStackView.bottomAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.bottomAnchor),
            pagesStackView.heightAnchor.constraint(equalTo: pagingScrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    private func installPages() {
        for section in MainSection.visible {
            let pageContainer = UIView()
            pageContainer.translatesAutoresizingMaskIntoConstraints = false
            pagesStackView.addArrangedSubview(pageContainer)
            pageContainer.widthAnchor.constraint(equalTo: pagingScrollView.frameLayoutGuide.widthAnchor).isActive = true

            let child = section.makeViewController()
            if let feed = child as? MainFeedTabViewController {
                feed.onImmersiveChange = { [weak self, weak feed] immersive in
                    guard let feed else { return }
                    self?.setFeedImmersiveChrome(immersive, feed: feed)
                }
                feed.onClipMenuChanged = { [weak self, weak feed] in
                    guard let self, let feed, self.feedOptionsItem != nil else { return }
                    self.feedOptionsItem?.menu = feed.currentClipMenu
                    // No clip menu on the end-of-feed page.
                    self.feedOptionsItem?.isEnabled = feed.currentClipMenu != nil
                }
            }
            embed(child, in: pageContainer)
            pageViewControllers.append(child)
        }
    }

    private func embed(_ child: UIViewController, in container: UIView) {
        addChild(child)
        child.loadViewIfNeeded()
        guard let childView = child.view else {
            assertionFailure("Child view controller did not load a view")
            child.didMove(toParent: self)
            return
        }
        childView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(childView)
        NSLayoutConstraint.activate([
            childView.topAnchor.constraint(equalTo: container.topAnchor),
            childView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            childView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            childView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        child.didMove(toParent: self)
    }

    private func applyMainTabScrollInsetsToPagesIfNeeded() {
        let safeTop = view.safeAreaInsets.top
        guard safeTop > 0 else { return }
        let topInset = safeTop + GameCategoryTabBar.layoutHeight
        guard abs(topInset - lastAppliedMainTabTopInset) >= 0.5 else { return }
        lastAppliedMainTabTopInset = topInset
        for child in pageViewControllers {
            applyMainTabScrollInsets(to: child, topInset: topInset)
        }
    }

    private func applyMainTabScrollInsets(to viewController: UIViewController, topInset: CGFloat) {
        guard let scrollable = viewController as? MainTabScrollable else { return }
        for scrollView in scrollable.mainTabScrollViews {
            scrollView.applyMainTabTopInset(topInset)
        }
    }

    private func syncPagerHapticPageFromCurrentOffset() {
        let width = pagingScrollView.bounds.width
        guard width > 0 else { return }
        let progress = pagingScrollView.contentOffset.x / width
        let clamped = max(0, min(progress, CGFloat(MainSection.visible.count - 1)))
        lastPagerHapticPageIndex = max(0, min(Int(round(clamped)), MainSection.visible.count - 1))
    }

    private var activePageIndex: Int {
        let width = pagingScrollView.bounds.width
        guard width > 0 else { return 0 }
        let progress = pagingScrollView.contentOffset.x / width
        return max(0, min(Int(round(progress)), pageViewControllers.count - 1))
    }

    private func installVerticalScrollObservers() {
        verticalScrollObservations = []
        for child in pageViewControllers {
            guard let scrollable = child as? MainTabScrollable else { continue }
            for scrollView in scrollable.mainTabScrollViews {
                configureScrollEdgeEffects(on: scrollView)
                let observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                    self?.handleMainTabVerticalScroll(scrollView)
                }
                verticalScrollObservations.append(observation)
            }
        }
        resetVerticalScrollTrackingForActivePage()
    }

    private func resetVerticalScrollTrackingForActivePage() {
        trackedVerticalScrollPageIndex = activePageIndex
        if let scrollView = verticalScrollView(forPageAt: activePageIndex) {
            lastObservedVerticalOffset = scrollView.contentOffset.y
        } else {
            lastObservedVerticalOffset = 0
        }
        updateScrollEdgeInteractionForActivePage()
    }

    private func updateScrollEdgeInteractionForActivePage() {
        tabBar.setScrollEdgeScrollView(verticalScrollView(forPageAt: activePageIndex))
    }

    private func configureScrollEdgeEffects(on scrollView: UIScrollView) {
        scrollView.topEdgeEffect.style = .soft
        scrollView.topEdgeEffect.isHidden = false
        scrollView.delaysContentTouches = false
    }

    private func verticalScrollView(forPageAt index: Int) -> UIScrollView? {
        guard pageViewControllers.indices.contains(index),
              let scrollable = pageViewControllers[index] as? MainTabScrollable
        else { return nil }
        return scrollable.mainTabScrollViews.first
    }

    private func handleMainTabVerticalScroll(_ scrollView: UIScrollView) {
        guard scrollView === verticalScrollView(forPageAt: activePageIndex) else { return }

        let offsetY = scrollView.contentOffset.y
        let scrollPosition = offsetY + scrollView.adjustedContentInset.top

        defer { lastObservedVerticalOffset = offsetY }

        if scrollPosition <= Self.verticalScrollTopRevealThreshold {
            tabBar.setShowsInactiveTabs(true, animated: true)
            return
        }

        let delta = offsetY - lastObservedVerticalOffset
        guard abs(delta) >= Self.verticalScrollDirectionThreshold else { return }

        if delta > 0 {
            tabBar.setShowsInactiveTabs(false, animated: true)
        } else if hasScrolledUpFromBottomEdge(in: scrollView) {
            tabBar.setShowsInactiveTabs(true, animated: true)
        }
    }

    private func maxContentOffsetY(in scrollView: UIScrollView) -> CGFloat? {
        let contentHeight = scrollView.contentSize.height
        let visibleHeight = scrollView.bounds.height
        guard contentHeight > visibleHeight else { return nil }
        return contentHeight - visibleHeight + scrollView.adjustedContentInset.bottom
    }

    /// True when content sits meaningfully above the bottom — not during bottom rubber-band bounce.
    private func hasScrolledUpFromBottomEdge(in scrollView: UIScrollView) -> Bool {
        guard let maxOffsetY = maxContentOffsetY(in: scrollView) else { return true }
        return scrollView.contentOffset.y < maxOffsetY - Self.verticalScrollBottomExpandDistance
    }

    /// The feed plays only while it's the nearest page: past halfway out, it pauses.
    private func updateFeedActivity() {
        let active = activePageIndex
        var feedActive = false
        for (index, child) in pageViewControllers.enumerated() {
            guard let feed = child as? MainFeedTabViewController else { continue }
            feed.setActive(index == active)
            feedActive = feedActive || index == active
        }
        // Leaving the feed already collapsed it (inside `setActive`), so the regular bar
        // is up; only the expand button comes and goes here.
        if feedActive != isFeedPageActive {
            isFeedPageActive = feedActive
            if feedOptionsItem == nil { setupNavigationBar(animated: true) }
        }
    }

    /// Immersive feed: the tab bar fades out and side-swiping between tabs stops, and the
    /// navigation bar trades settings for the clip's menu, with the expand button turned
    /// into collapse. The "Feed" title is hidden. Dictionary stays, so words can be looked
    /// up mid-feed. Runs inside the feed's fade animation.
    private func setFeedImmersiveChrome(_ immersive: Bool, feed: MainFeedTabViewController) {
        tabBar.alpha = immersive ? 0 : 1
        tabBar.isUserInteractionEnabled = !immersive
        pagingScrollView.isScrollEnabled = !immersive
        // The system's soft edge blur fades a long way below the bar and hazes the clip's
        // info line, so the immersive feed swaps it for a shorter one of our own.
        pagingScrollView.topEdgeEffect.isHidden = immersive
        feedTopBlur.alpha = immersive ? Self.feedTopBlurOpacity : 0
        if immersive {
            // The clip's own menu (it rebuilds itself each time it opens); swapped
            // for the next clip's in `onClipMenuChanged`.
            let options = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: feed.currentClipMenu)
            options.accessibilityLabel = "Options"
            options.isEnabled = feed.currentClipMenu != nil
            feedOptionsItem = options
            navigationItem.setLeftBarButtonItems([makeDictionaryItem()], animated: true)
            let collapse = feedModeItem(feed: feed, immersive: true)
            let search = ClipExplorerViewController.searchBarItem(pushingFrom: self)
            navigationItem.setRightBarButtonItems([options, collapse, search], animated: true)
            // Empty, not nil: nil falls back to this screen's "Shizen" title.
            navigationItem.title = ""
        } else {
            feedOptionsItem = nil
            setupNavigationBar(animated: true)
            navigationItem.title = title
        }
    }

    private func revealInactiveTabsForHorizontalInteraction(animated: Bool) {
        tabBar.setShowsInactiveTabs(true, animated: animated)
    }

    private static func dialogueTabTitle() -> String {
        "Dialogue · \(DialogueLessonTrack.current.title)"
    }

    private func configureLessonTrackMenu() {
        tabBar.contextMenuProvider = { [weak self] in
            self?.makeLessonTrackMenu()
        }
    }

    private func makeLessonTrackMenu() -> UIMenu {
        UIMenu(
            title: "Lesson level",
            children: DialogueLessonTrack.allCases.map { track in
                UIAction(
                    title: track.title,
                    state: track == .current ? .on : .off
                ) { [weak self] _ in
                    DialogueLessonTrack.current = track
                    self?.tabBar.setTitle(Self.dialogueTabTitle(), at: MainSection.dialogue.rawValue)
                }
            }
        )
    }
}

// MARK: - GameCategoryTabBarDelegate

extension MainViewController: GameCategoryTabBarDelegate {
    func tabBar(_ tabBar: GameCategoryTabBar, didSelectTabAt index: Int) {
        let offsetX = pagingScrollView.bounds.width * CGFloat(index)
        isUpdatingFromScroll = true
        CATransaction.begin()
        CATransaction.setAnimationDuration(Self.tabPagerSnapAnimationDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        pagingScrollView.setContentOffset(CGPoint(x: offsetX, y: 0), animated: true)
        CATransaction.commit()
    }

    func tabBar(_ tabBar: GameCategoryTabBar, didScrollToPageProgress progress: CGFloat) {
        let width = pagingScrollView.bounds.width
        guard width > 0 else { return }
        let offsetX = progress * width
        isUpdatingFromScroll = true
        pagingScrollView.contentOffset.x = offsetX
        revealInactiveTabsForHorizontalInteraction(animated: true)
    }

    func tabBarDidEndScrolling(_ tabBar: GameCategoryTabBar) {
        isUpdatingFromScroll = false
        syncPagerHapticPageFromCurrentOffset()
    }

    func tabBar(_ tabBar: GameCategoryTabBar, didSelectHoldOptionAt index: Int) {
        let tracks = DialogueLessonTrack.allCases
        guard tracks.indices.contains(index) else { return }
        DialogueLessonTrack.current = tracks[index]
        tabBar.setTitle(Self.dialogueTabTitle(), at: MainSection.dialogue.rawValue)
    }
}

// MARK: - UIScrollViewDelegate

extension MainViewController: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === pagingScrollView else { return }
        revealInactiveTabsForHorizontalInteraction(animated: true)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === pagingScrollView else { return }
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        let progress = scrollView.contentOffset.x / width
        let pageIndex = max(0, min(Int(round(progress)), pageViewControllers.count - 1))
        if pageIndex != trackedVerticalScrollPageIndex {
            trackedVerticalScrollPageIndex = pageIndex
            resetVerticalScrollTrackingForActivePage()
            updateFeedActivity()
        }
        if !isUpdatingFromScroll {
            revealInactiveTabsForHorizontalInteraction(animated: true)
            let clamped = max(0, min(progress, CGFloat(MainSection.visible.count - 1)))
            let nearestPage = max(0, min(Int(round(clamped)), MainSection.visible.count - 1))
            if nearestPage != lastPagerHapticPageIndex {
                lastPagerHapticPageIndex = nearestPage
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
            tabBar.setPageProgress(progress, animated: false)
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if scrollView === pagingScrollView, !decelerate {
            syncPagerHapticPageFromCurrentOffset()
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        if scrollView === pagingScrollView {
            isUpdatingFromScroll = false
            syncPagerHapticPageFromCurrentOffset()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if scrollView === pagingScrollView {
            isUpdatingFromScroll = false
            syncPagerHapticPageFromCurrentOffset()
        }
    }
}

/// Claims the pan gesture only when the swipe is clearly horizontal so nested vertical scroll views keep working.
final class HorizontalPagingScrollView: UIScrollView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isPagingEnabled = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        alwaysBounceVertical = false
        alwaysBounceHorizontal = true
        bounces = true
        contentInsetAdjustmentBehavior = .never
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
              pan === panGestureRecognizer
        else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        let translation = pan.translation(in: self)
        return abs(translation.x) > abs(translation.y)
    }

    /// With `delaysContentTouches = false`, UIKit's default refuses to cancel touches in
    /// `UIControl`s, so a swipe that starts on a card or button finishes as a tap
    /// (`.touchUpInside`). Let the page swipe take the touch from controls too.
    override func touchesShouldCancel(in view: UIView) -> Bool {
        if view is UITextInput { return super.touchesShouldCancel(in: view) }
        return true
    }
}
