//
//  MainViewController.swift
//  shizen-chinese
//
//  Root container with swipeable sections and category tab bar.
//  v1 ships a single Practice tab; the pager stays so Dialogue can slot in later.
//

import UIKit

final class MainViewController: UIViewController {
    private enum MainSection: Int, CaseIterable {
        case practice

        var title: String {
            switch self {
            case .practice: return "Practice"
            }
        }

        func makeViewController() -> UIViewController {
            switch self {
            case .practice:
                let flow = PracticeHomeViewController()
                flow.title = nil
                return flow
            }
        }
    }

    private lazy var tabBar = GameCategoryTabBar(
        titles: MainSection.allCases.map(\.title),
        initialSelectedIndex: MainSection.practice.rawValue
    )
    private let pagingScrollView = HorizontalPagingScrollView()
    private let pagesStackView = UIStackView()
    private var pageViewControllers: [UIViewController] = []
    private var isUpdatingFromScroll = false
    private var lastPagerHapticPageIndex = MainSection.practice.rawValue
    private var didApplyDefaultTabSelection = false
    private var lastAppliedMainTabTopInset: CGFloat = -1
    private var trackedVerticalScrollPageIndex = 0
    private var lastObservedVerticalOffset: CGFloat = 0
    private let verticalScrollObserver = MainTabVerticalScrollObserver()

    private static let verticalScrollTopRevealThreshold: CGFloat = 12
    private static let verticalScrollDirectionThreshold: CGFloat = 2
    private static let verticalScrollBottomExpandDistance: CGFloat = 48
    private static let tabPagerSnapAnimationDuration: TimeInterval = 0.22

    override func viewDidLoad() {
        super.viewDidLoad()
        title = nil
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground
        setupPager()
        installPages()
        setupTabBar()
        setupNavigationBar()
        tabBar.delegate = self
        pagingScrollView.delegate = self
        installVerticalScrollObservers()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyMainTabScrollInsetsToPagesIfNeeded()
        applyDefaultTabSelectionIfNeeded()
    }

    private func applyDefaultTabSelectionIfNeeded() {
        guard !didApplyDefaultTabSelection else { return }
        let width = pagingScrollView.bounds.width
        guard width > 0 else { return }
        didApplyDefaultTabSelection = true

        let defaultIndex = MainSection.practice.rawValue
        pagingScrollView.contentOffset = CGPoint(x: width * CGFloat(defaultIndex), y: 0)
        tabBar.syncScrollPositionToSelection(animated: false)
        lastPagerHapticPageIndex = defaultIndex
        resetVerticalScrollTrackingForActivePage()
    }

    // MARK: - Navigation

    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "character.book.closed"),
            style: .plain,
            target: self,
            action: #selector(openDictionary)
        )
    }

    @objc private func openDictionary() {
        let vc = DictionarySearchViewController()
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    // MARK: - Layout

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
        for section in MainSection.allCases {
            let pageContainer = UIView()
            pageContainer.translatesAutoresizingMaskIntoConstraints = false
            pagesStackView.addArrangedSubview(pageContainer)
            pageContainer.widthAnchor.constraint(equalTo: pagingScrollView.frameLayoutGuide.widthAnchor).isActive = true

            let child = section.makeViewController()
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
        let clamped = max(0, min(progress, CGFloat(MainSection.allCases.count - 1)))
        lastPagerHapticPageIndex = max(0, min(Int(round(clamped)), MainSection.allCases.count - 1))
    }

    private var activePageIndex: Int {
        let width = pagingScrollView.bounds.width
        guard width > 0 else { return 0 }
        let progress = pagingScrollView.contentOffset.x / width
        return max(0, min(Int(round(progress)), pageViewControllers.count - 1))
    }

    private func installVerticalScrollObservers() {
        verticalScrollObserver.onScroll = { [weak self] scrollView in
            self?.handleMainTabVerticalScroll(scrollView)
        }
        for child in pageViewControllers {
            guard let scrollable = child as? MainTabScrollable else { continue }
            for scrollView in scrollable.mainTabScrollViews {
                configureScrollEdgeEffects(on: scrollView)
                scrollView.delegate = verticalScrollObserver
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

    private func hasScrolledUpFromBottomEdge(in scrollView: UIScrollView) -> Bool {
        guard let maxOffsetY = maxContentOffsetY(in: scrollView) else { return true }
        return scrollView.contentOffset.y < maxOffsetY - Self.verticalScrollBottomExpandDistance
    }

    private func revealInactiveTabsForHorizontalInteraction(animated: Bool) {
        tabBar.setShowsInactiveTabs(true, animated: animated)
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
        }
        if !isUpdatingFromScroll {
            revealInactiveTabsForHorizontalInteraction(animated: true)
            let clamped = max(0, min(progress, CGFloat(MainSection.allCases.count - 1)))
            let nearestPage = max(0, min(Int(round(clamped)), MainSection.allCases.count - 1))
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

/// Forwards vertical scroll events from main-tab pages without claiming other scroll delegate hooks.
private final class MainTabVerticalScrollObserver: NSObject, UIScrollViewDelegate {
    var onScroll: ((UIScrollView) -> Void)?

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onScroll?(scrollView)
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
}
