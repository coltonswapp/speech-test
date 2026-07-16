//
//  DialogueNestedPagingExperimentViewController.swift
//  shizen
//
//  Prototype for nested vertical scroll handoff: dialogue on page one, optional
//  quiz on page two, vocabulary / grammar highlights on the last page.
//

import UIKit

// MARK: - NestedVerticalScrollHandoffCoordinator

/// Transfers inner-scroll overflow to an outer pager while the finger is down.
/// Container extremes (first page top, last page bottom) keep native UIKit bounce.
private final class NestedVerticalScrollHandoffCoordinator: NSObject, UIScrollViewDelegate {

    private weak var outerScrollView: UIScrollView?
    private var innerScrollViews: [UIScrollView]
    private let boundaryEpsilon: CGFloat
    private let pageCommitThreshold: CGFloat
    private let velocityThreshold: CGFloat
    private var isTransferringOffset = false
    private var lastSnappedPage = 0
    private var lastTrackedOffsetY: [ObjectIdentifier: CGFloat] = [:]
    private var isInnerScrollingLockedForPageTransition = false
    private let pageChangeHaptic = UIImpactFeedbackGenerator(style: .medium)
    private var progressReportingLink: CADisplayLink?
    private(set) var isAnimatingPageSnap = false

    var onPageChanged: ((Int) -> Void)?
    var onPageTransitionProgressChanged: ((CGFloat) -> Void)?

    init(
        outerScrollView: UIScrollView,
        innerScrollViews: [UIScrollView],
        boundaryEpsilon: CGFloat = 0.5,
        pageCommitThreshold: CGFloat = 0.22,
        velocityThreshold: CGFloat = 0.3
    ) {
        self.outerScrollView = outerScrollView
        self.innerScrollViews = innerScrollViews
        self.boundaryEpsilon = boundaryEpsilon
        self.pageCommitThreshold = pageCommitThreshold
        self.velocityThreshold = velocityThreshold
        super.init()
        innerScrollViews.forEach { $0.delegate = self }
        pageChangeHaptic.prepare()
    }

    func snapToPage(_ page: Int) {
        guard let outerScrollView, outerScrollView.bounds.height > 0 else { return }
        let pageHeight = outerScrollView.bounds.height
        let clampedPage = min(max(page, 0), outerMaxPageIndex())
        snapOuterToPage(clampedPage, pageHeight: pageHeight, velocity: .zero)
    }

    func detachFromInnerScrollViews() {
        progressReportingLink?.invalidate()
        progressReportingLink = nil
        innerScrollViews.forEach { scrollView in
            if scrollView.delegate === self {
                scrollView.delegate = nil
            }
        }
    }

    func replaceInnerScrollViews(_ scrollViews: [UIScrollView]) {
        innerScrollViews.forEach { scrollView in
            if scrollView.delegate === self {
                scrollView.delegate = nil
            }
            lastTrackedOffsetY.removeValue(forKey: ObjectIdentifier(scrollView))
        }
        innerScrollViews = scrollViews
        scrollViews.forEach { $0.delegate = self }
        lastSnappedPage = min(lastSnappedPage, max(0, scrollViews.count - 1))
    }

    func replaceDialogueScrollView(_ scrollView: UIScrollView) {
        if innerScrollViews.indices.contains(0) {
            let old = innerScrollViews[0]
            if old.delegate === self {
                old.delegate = nil
            }
            lastTrackedOffsetY.removeValue(forKey: ObjectIdentifier(old))
        }
        innerScrollViews[0] = scrollView
        scrollView.delegate = self
    }

    // MARK: UIScrollViewDelegate

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard innerScrollViews.contains(where: { $0 === scrollView }) else { return }
        lastTrackedOffsetY[ObjectIdentifier(scrollView)] = scrollView.contentOffset.y
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard innerScrollViews.contains(where: { $0 === scrollView }) else { return }
        guard scrollView.isTracking else { return }
        transferOverflowWhileTracking(from: scrollView)
        syncInnerScrollingDuringPageTransition(activeScrollView: scrollView)
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        guard innerScrollViews.contains(where: { $0 === scrollView }) else { return }
        if outerHasMovedOffPage() {
            setInnerScrollingEnabled(false)
            commitOrCancelPageTransition(velocity: velocity)
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard innerScrollViews.contains(where: { $0 === scrollView }) else { return }
        lastTrackedOffsetY.removeValue(forKey: ObjectIdentifier(scrollView))
        resetOuterDriftIfNeeded()
        if !outerHasMovedOffPage(), !isInnerScrollingLockedForPageTransition {
            setInnerScrollingEnabled(true)
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard innerScrollViews.contains(where: { $0 === scrollView }) else { return }
    }

    // MARK: Handoff

    private enum PageTransitionAnchor {
        case fromBottom(pageOrigin: CGFloat)
        case fromTop(pageOrigin: CGFloat)
    }

    private func transferOverflowWhileTracking(from innerScrollView: UIScrollView) {
        guard !isTransferringOffset, let outerScrollView else { return }

        let bounds = boundaryOffsets(for: innerScrollView)
        let innerOffsetY = innerScrollView.contentOffset.y
        let pageIndex = innerPageIndex(for: innerScrollView)
        let maxPageIndex = outerMaxPageIndex()
        let pageHeight = outerScrollView.bounds.height

        guard pageHeight > 0 else { return }

        let scrollID = ObjectIdentifier(innerScrollView)
        let previousY = lastTrackedOffsetY[scrollID] ?? innerOffsetY
        let delta = innerOffsetY - previousY
        guard abs(delta) > 0.001 else { return }

        let pageOrigin = CGFloat(pageIndex) * pageHeight
        let outerMinY = -outerScrollView.adjustedContentInset.top
        let outerMaxY = CGFloat(maxPageIndex) * pageHeight

        isTransferringOffset = true
        defer {
            isTransferringOffset = false
            lastTrackedOffsetY[scrollID] = innerScrollView.contentOffset.y
            reportPageTransitionProgress()
        }

        if let anchor = activePageTransitionAnchor(pageOrigin: pageOrigin) {
            switch anchor {
            case .fromBottom:
                outerScrollView.contentOffset.y = min(
                    max(outerScrollView.contentOffset.y + delta, pageOrigin),
                    outerMaxY
                )
                innerScrollView.contentOffset.y = bounds.maxY
            case .fromTop:
                outerScrollView.contentOffset.y = max(
                    min(outerScrollView.contentOffset.y + delta, pageOrigin),
                    outerMinY
                )
                innerScrollView.contentOffset.y = bounds.minY
            }
            return
        }

        if innerOffsetY > bounds.maxY + boundaryEpsilon {
            guard pageIndex < maxPageIndex else { return }

            let overflow = innerOffsetY - bounds.maxY
            outerScrollView.contentOffset.y = min(outerScrollView.contentOffset.y + overflow, outerMaxY)
            innerScrollView.contentOffset.y = bounds.maxY
        } else if innerOffsetY < bounds.minY - boundaryEpsilon {
            guard pageIndex > 0 else { return }

            let overflow = innerOffsetY - bounds.minY
            outerScrollView.contentOffset.y = max(outerScrollView.contentOffset.y + overflow, outerMinY)
            innerScrollView.contentOffset.y = bounds.minY
        } else if innerOffsetY >= bounds.maxY - boundaryEpsilon, delta > 0, pageIndex < maxPageIndex {
            outerScrollView.contentOffset.y = min(outerScrollView.contentOffset.y + delta, outerMaxY)
            innerScrollView.contentOffset.y = bounds.maxY
        } else if innerOffsetY <= bounds.minY + boundaryEpsilon, delta < 0, pageIndex > 0 {
            outerScrollView.contentOffset.y = max(outerScrollView.contentOffset.y + delta, outerMinY)
            innerScrollView.contentOffset.y = bounds.minY
        }
    }

    /// While the outer pager sits between snapped pages, keep the inner scroll pinned at the
    /// boundary that started the transition and route all finger movement to the outer pager.
    private func activePageTransitionAnchor(pageOrigin: CGFloat) -> PageTransitionAnchor? {
        guard let outerScrollView, outerScrollView.bounds.height > 0 else { return nil }
        let outerY = outerScrollView.contentOffset.y

        if outerY > pageOrigin + boundaryEpsilon {
            return .fromBottom(pageOrigin: pageOrigin)
        }
        if outerY < pageOrigin - boundaryEpsilon {
            return .fromTop(pageOrigin: pageOrigin)
        }
        return nil
    }

    private func reportPageTransitionProgress() {
        guard let outerScrollView, outerScrollView.bounds.height > 0 else {
            onPageTransitionProgressChanged?(0)
            return
        }
        let progress = outerScrollView.contentOffset.y / outerScrollView.bounds.height
        onPageTransitionProgressChanged?(max(progress, 0))
    }

    private func resetOuterDriftIfNeeded() {
        guard let outerScrollView, outerScrollView.bounds.height > 0 else { return }
        guard !outerHasMovedOffPage() else { return }

        let pageHeight = outerScrollView.bounds.height
        let nearestPage = Int(round(outerScrollView.contentOffset.y / pageHeight))
        let origin = CGFloat(nearestPage) * pageHeight
        guard abs(outerScrollView.contentOffset.y - origin) > 0.01 else { return }
        isAnimatingPageSnap = true
        startProgressReporting()
        UIView.animate(
            withDuration: 0.34,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            outerScrollView.contentOffset.y = origin
        } completion: { [weak self] _ in
            guard let self else { return }
            self.isAnimatingPageSnap = false
            self.stopProgressReporting()
            self.reportPageTransitionProgress()
        }
    }

    private func outerHasMovedOffPage() -> Bool {
        guard let outerScrollView, outerScrollView.bounds.height > 0 else { return false }
        let pageHeight = outerScrollView.bounds.height
        let snappedPage = Int(round(outerScrollView.contentOffset.y / pageHeight))
        let pageOrigin = CGFloat(snappedPage) * pageHeight
        return abs(outerScrollView.contentOffset.y - pageOrigin) > boundaryEpsilon
    }

    private func innerPageIndex(for scrollView: UIScrollView) -> Int {
        innerScrollViews.firstIndex(where: { $0 === scrollView }) ?? 0
    }

    private func outerMaxPageIndex() -> Int {
        guard let outerScrollView, outerScrollView.bounds.height > 0 else { return 0 }
        let pageHeight = outerScrollView.bounds.height
        return max(
            0,
            Int((outerScrollView.contentSize.height - outerScrollView.bounds.height) / pageHeight)
        )
    }

    private func commitOrCancelPageTransition(velocity: CGPoint) {
        guard let outerScrollView, outerScrollView.bounds.height > 0 else { return }

        let pageHeight = outerScrollView.bounds.height
        let maxPageIndex = outerMaxPageIndex()
        let currentOffset = outerScrollView.contentOffset.y
        let targetPage: Int

        if velocity.y > velocityThreshold {
            targetPage = min(Int(floor(currentOffset / pageHeight)) + 1, maxPageIndex)
        } else if velocity.y < -velocityThreshold {
            targetPage = max(Int(ceil(currentOffset / pageHeight)) - 1, 0)
        } else {
            let fractional = currentOffset / pageHeight
            let lowerPage = Int(floor(fractional))
            let remainder = fractional - CGFloat(lowerPage)
            let candidate = remainder > pageCommitThreshold ? lowerPage + 1 : lowerPage
            targetPage = min(max(candidate, 0), maxPageIndex)
        }

        snapOuterToPage(targetPage, pageHeight: pageHeight, velocity: velocity)
    }

    private func snapOuterToPage(_ page: Int, pageHeight: CGFloat, velocity: CGPoint) {
        guard let outerScrollView else { return }
        let targetY = CGFloat(page) * pageHeight
        notifyPageChangeIfNeeded(to: page)
        setInnerScrollingEnabled(false)
        isAnimatingPageSnap = true
        startProgressReporting()

        UIView.animate(
            withDuration: 0.34,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: abs(velocity.y),
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            outerScrollView.contentOffset.y = targetY
        } completion: { [weak self] _ in
            guard let self else { return }
            self.isAnimatingPageSnap = false
            self.setInnerScrollingEnabled(true)
            self.stopProgressReporting()
            self.reportPageTransitionProgress()
        }
    }

    private func setInnerScrollingEnabled(_ enabled: Bool) {
        isInnerScrollingLockedForPageTransition = !enabled
        innerScrollViews.forEach { $0.isScrollEnabled = enabled }
    }

    /// While the outer pager is between pages, only the scroll view driving the handoff stays
    /// interactive until release; all others are locked immediately.
    private func syncInnerScrollingDuringPageTransition(activeScrollView: UIScrollView) {
        guard outerHasMovedOffPage() else {
            if !isInnerScrollingLockedForPageTransition {
                setInnerScrollingEnabled(true)
            }
            return
        }

        for scrollView in innerScrollViews {
            scrollView.isScrollEnabled = scrollView === activeScrollView
        }
    }

    private func notifyPageChangeIfNeeded(to page: Int) {
        guard page != lastSnappedPage else { return }
        lastSnappedPage = page
        pageChangeHaptic.prepare()
        pageChangeHaptic.impactOccurred(intensity: 0.85)
        onPageChanged?(page)
    }

    private func startProgressReporting() {
        progressReportingLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(handleProgressReportingTick))
        progressReportingLink = link
        link.add(to: .main, forMode: .common)
    }

    private func stopProgressReporting() {
        progressReportingLink?.invalidate()
        progressReportingLink = nil
    }

    @objc private func handleProgressReportingTick() {
        reportPageTransitionProgress()
    }

    private func boundaryOffsets(for scrollView: UIScrollView) -> (minY: CGFloat, maxY: CGFloat) {
        let minY = -scrollView.adjustedContentInset.top
        let contentHeight = scrollView.contentSize.height
        let visibleHeight = scrollView.bounds.height
            - scrollView.adjustedContentInset.top
            - scrollView.adjustedContentInset.bottom

        guard contentHeight > visibleHeight + boundaryEpsilon else {
            return (minY, minY)
        }

        let maxY = contentHeight - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        return (minY, max(maxY, minY))
    }
}

// MARK: - DialogueNestedPagingExperimentViewController

final class DialogueNestedPagingExperimentViewController: UIViewController {

    private static let boundaryEpsilon: CGFloat = 0.5
    private static let pageNavigationControlHeight: CGFloat = 52
    private static let pageNavigationSymbolPointSize: CGFloat = 22
    private static let highlightsSecondPageTopInsetExtra: CGFloat = 56
    private static let quizCheckButtonHorizontalInset: CGFloat = 20
    private static let quizCheckButtonBottomInset: CGFloat = 8
    private static let quizCheckButtonHeight: CGFloat = 50
    /// Mirrors `DialogueExperimentViewController.nestedPagingTransportSlideDistance`; play exits +X, check uses −X.
    private static let quizCheckSlideDistance: CGFloat = 140
    private static let contentRevealSlideDistance: CGFloat = 18

    private let outerScrollView = UIScrollView()
    private let pagesStack = UIStackView()
    private let dialoguePageView = UIView()
    private let quizPageView = UIView()
    private let highlightsPageView = UIView()
    private var dialogueViewController: DialogueExperimentViewController!
    private let quizScrollView = UIScrollView()
    private let quizContentView = DialogueQuizContentView()
    private let quizCheckButton = UIButton(type: .system)
    private let highlightsScrollView = UIScrollView()
    private let highlightsContentView = DialogueLearningHighlightsContentView()
    /// One chevron per seam where two pager pages meet (max two for three pages).
    private let firstSeamChevron = UIButton(type: .system)
    private let secondSeamChevron = UIButton(type: .system)
    private var firstSeamCenterYConstraint: NSLayoutConstraint!
    private var secondSeamCenterYConstraint: NSLayoutConstraint!
    private var firstSeamPointsUp = false
    private var secondSeamPointsUp = false
    private var chevronSpringAnimator: UIViewPropertyAnimator?

    private let topScrollEdgeInteraction: UIScrollEdgeElementContainerInteraction = {
        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.edge = .top
        return interaction
    }()

    /// Host-owned anchor for the top edge effect, mirroring how the bottom
    /// effect is hosted by the (reparented) transport bar. Attaching the
    /// interaction to the system nav bar proved unreliable here, so we host a
    /// thin, non-interactive strip across the top of our own view instead.
    private let topScrollEdgeContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }()

    private var handoffCoordinator: NestedVerticalScrollHandoffCoordinator?
    private let loadingCoordinator = DialogueLessonLoadingCoordinator()
    /// When set, the controller is driven by a standalone scenario collection
    /// (its own scene image + curriculum-ordered scenarios) instead of the
    /// grammar-point–derived `DialogueExperimentCatalog`.
    private var collection: DialogueScenarioCollection?
    /// When non-nil, collection is resolved via catalog fetch after push.
    private let pendingCollectionID: String?
    private let usesLegacyCatalog: Bool
    private var selectedScenarioID: String
    private var prefersNextIncompleteScenario: Bool
    private var appliedTopContentInset: CGFloat = -1
    private var appliedBottomContentInset: CGFloat = -1
    private var pageTransitionProgress: CGFloat = 0
    private var didSettleHighlightsScrollAtTop = false
    private var didSettleQuizScrollAtTop = false
    private var lastKnownViewSize: CGSize = .zero
    private var hasLoadedLessonContent = false

    private var hasQuizPage: Bool {
        !(currentScenarioItem?.quiz.isEmpty ?? true)
    }

    private var pageCount: Int {
        hasQuizPage ? 3 : 2
    }

    private var highlightsPageIndex: Int {
        hasQuizPage ? 2 : 1
    }

    private var activePageIndex: Int {
        let pageHeight = outerScrollView.bounds.height
        guard pageHeight > 0 else { return 0 }
        return min(max(Int(round(outerScrollView.contentOffset.y / pageHeight)), 0), pageCount - 1)
    }

    private func scrollView(forPageIndex index: Int) -> UIScrollView {
        if index == 0 {
            return dialogueViewController.handoffScrollView
        }
        if hasQuizPage {
            return index == 1 ? quizScrollView : highlightsScrollView
        }
        return highlightsScrollView
    }

    private var activeInnerScrollView: UIScrollView {
        scrollView(forPageIndex: activePageIndex)
    }

    private func innerScrollViewsForCurrentScenario() -> [UIScrollView] {
        var scrollViews = [dialogueViewController.handoffScrollView]
        if hasQuizPage {
            scrollViews.append(quizScrollView)
        }
        scrollViews.append(highlightsScrollView)
        return scrollViews
    }

    /// A single switchable scenario, unified across the collection-backed and
    /// legacy grammar-catalog code paths.
    private struct ScenarioItem {
        let id: String
        let menuTitle: String
        let menuSubtitle: String?
        let pointTitle: String
        let example: GrammarExample
        let highlights: DialogueLearningHighlights
        let quiz: [DialogueQuizQuestion]
        let grammarPointIDs: [String]
    }

    /// Drive the controller from a standalone collection (preferred when already in hand).
    init(collection: DialogueScenarioCollection, initialScenarioID: String? = nil) {
        self.collection = collection
        self.pendingCollectionID = nil
        self.usesLegacyCatalog = false
        self.prefersNextIncompleteScenario = false
        if let initialScenarioID,
           collection.scenarios.contains(where: { $0.id == initialScenarioID }) {
            self.selectedScenarioID = initialScenarioID
        } else {
            self.selectedScenarioID = collection.scenarios.first?.id ?? ""
        }
        super.init(nibName: nil, bundle: nil)
    }

    /// Push immediately with a collection id; shows loading while the catalog resolves.
    init(
        collectionID: String,
        initialScenarioID: String? = nil,
        prefersNextIncompleteScenario: Bool = false
    ) {
        self.collection = DialogueScenarioCollectionCatalog.readyCollection(id: collectionID)
        self.pendingCollectionID = collectionID
        self.usesLegacyCatalog = false
        self.prefersNextIncompleteScenario = prefersNextIncompleteScenario
        self.selectedScenarioID = initialScenarioID ?? self.collection?.scenarios.first?.id ?? ""
        super.init(nibName: nil, bundle: nil)
    }

    /// Legacy entry point: drive from the grammar-point–derived catalog.
    init() {
        self.collection = nil
        self.pendingCollectionID = nil
        self.usesLegacyCatalog = true
        self.prefersNextIncompleteScenario = false
        self.selectedScenarioID = DialogueExperimentFixture.audioKey
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.collection = nil
        self.pendingCollectionID = nil
        self.usesLegacyCatalog = true
        self.prefersNextIncompleteScenario = false
        self.selectedScenarioID = DialogueExperimentFixture.audioKey
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = collection?.title ?? "Lesson"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground

        loadingCoordinator.attach(to: view)
        loadingCoordinator.beginLoading()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard hasLoadedLessonContent else { return }
        if topScrollEdgeInteraction.scrollView == nil {
            topScrollEdgeInteraction.scrollView = activeInnerScrollView
        }
        updateScrollEdgeInteractionsForActivePage()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard hasLoadedLessonContent else { return }
        dialogueViewController.stopHostedPlaybackIfDisappearing()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !hasLoadedLessonContent {
            resolveCollectionAndLoadContent()
            return
        }

        applyScrollLayoutIfNeeded()
        updateScrollEdgeInteractionsForActivePage()
        applyPageTransitionProgress(currentPageTransitionProgress())
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard hasLoadedLessonContent else {
            loadingCoordinator.bringOverlayToFront()
            return
        }
        guard view.bounds.size != lastKnownViewSize else {
            bringPageChromeToFront()
            return
        }
        lastKnownViewSize = view.bounds.size
        applyPageTransitionProgress(pageTransitionProgress)
        bringPageChromeToFront()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        guard hasLoadedLessonContent else { return }
        applyScrollLayoutIfNeeded()
    }

    // MARK: - Setup

    private func resolveCollectionAndLoadContent() {
        if usesLegacyCatalog || collection != nil {
            finishCollectionResolutionAndBuild()
            return
        }

        guard let pendingCollectionID else {
            finishCollectionResolutionAndBuild()
            return
        }

        DialogueScenarioCollectionCatalog.fetchCollection(id: pendingCollectionID) { [weak self] collection in
            guard let self else { return }
            guard let collection else {
                self.loadingCoordinator.finishLoading {
                    self.showCollectionLoadFailure(id: pendingCollectionID)
                }
                return
            }
            self.collection = collection
            self.finishCollectionResolutionAndBuild()
        }
    }

    private func finishCollectionResolutionAndBuild() {
        if prefersNextIncompleteScenario, let collection {
            selectedScenarioID = Self.nextIncompleteScenarioID(
                in: collection,
                fallback: selectedScenarioID
            )
        } else if selectedScenarioID.isEmpty, let firstID = collection?.scenarios.first?.id {
            selectedScenarioID = firstID
        }

        title = currentScenarioItem?.menuTitle ?? collection?.title ?? "Lesson"

        guard currentScenarioItem != nil else {
            let failureID = pendingCollectionID ?? collection?.id ?? "lesson"
            loadingCoordinator.finishLoading { [weak self] in
                self?.showCollectionLoadFailure(id: failureID)
            }
            return
        }

        buildLessonContentIfNeeded()
        prepareContentRevealAnimation()
        loadingCoordinator.finishLoading()
        animateContentReveal()
    }

    private func contentViewsForReveal() -> [UIView] {
        var views: [UIView] = [outerScrollView]
        if let transportBar = dialogueViewController?.nestedPagingTransportBarView {
            views.append(transportBar)
        }
        return views
    }

    private func prepareContentRevealAnimation() {
        let offset = Self.contentRevealSlideDistance
        for view in contentViewsForReveal() {
            view.transform = CGAffineTransform(translationX: 0, y: offset)
            view.alpha = 0
        }
        // Page chrome alphas are restored after the reveal via applyPageTransitionProgress.
        quizCheckButton.alpha = 0
        firstSeamChevron.alpha = 0
        secondSeamChevron.alpha = 0
    }

    private func animateContentReveal() {
        UIView.animate(
            withDuration: 0.44,
            delay: 0.04,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0.35,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            for view in self.contentViewsForReveal() {
                view.transform = .identity
                view.alpha = 1
            }
        } completion: { [weak self] _ in
            guard let self, self.hasLoadedLessonContent else { return }
            self.applyScrollLayoutIfNeeded(force: true)
            self.updateScrollEdgeInteractionsForActivePage()
            self.applyPageTransitionProgress(self.currentPageTransitionProgress())
            self.dialogueViewController.applyNestedPagingTransportProgress(0)
            self.bringPageChromeToFront()
        }
    }

    private func buildLessonContentIfNeeded() {
        guard !hasLoadedLessonContent else { return }
        hasLoadedLessonContent = true

        configureDialogueNavigationItems()
        configureOuterPager()
        configureDialoguePage()
        configureQuizPage()
        configureQuizCheckButton()
        configureHighlightsPage()
        reloadQuizContent()
        reloadHighlightsContent()
        updateQuizPageVisibility()
        configurePageChevrons()
        installHandoffCoordinator()
        configureScrollEdgeEffects()
        attachTopScrollEdgeInteraction()
        applyScrollLayoutIfNeeded(force: true)
        view.layoutIfNeeded()
        loadingCoordinator.bringOverlayToFront()
    }

    private func showCollectionLoadFailure(id: String) {
        let alert = UIAlertController(
            title: "Couldn’t load lesson",
            message: "Failed to fetch “\(id)”.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    private static func nextIncompleteScenarioID(
        in collection: DialogueScenarioCollection,
        fallback: String
    ) -> String {
        let store = DialogueProgressStore.shared
        if let next = collection.scenarios.first(where: { !store.isCompletedToday(scenarioID: $0.id) }) {
            return next.id
        }
        return collection.scenarios.first?.id ?? fallback
    }

    private func configureOuterPager() {
        outerScrollView.translatesAutoresizingMaskIntoConstraints = false
        outerScrollView.isPagingEnabled = true
        outerScrollView.showsVerticalScrollIndicator = false
        outerScrollView.showsHorizontalScrollIndicator = false
        outerScrollView.alwaysBounceVertical = false
        outerScrollView.alwaysBounceHorizontal = false
        outerScrollView.bounces = true
        outerScrollView.isScrollEnabled = false
        outerScrollView.decelerationRate = .fast
        outerScrollView.delaysContentTouches = false
        outerScrollView.contentInsetAdjustmentBehavior = .never
        outerScrollView.clipsToBounds = true
        outerScrollView.backgroundColor = ExperimentPalette.pageBackground
        outerScrollView.delegate = self
        view.addSubview(outerScrollView)

        pagesStack.translatesAutoresizingMaskIntoConstraints = false
        pagesStack.axis = .vertical
        pagesStack.alignment = .fill
        pagesStack.distribution = .fill
        pagesStack.spacing = 0
        outerScrollView.addSubview(pagesStack)

        pagesStack.addArrangedSubview(dialoguePageView)
        pagesStack.addArrangedSubview(quizPageView)
        pagesStack.addArrangedSubview(highlightsPageView)

        // Host the top edge effect on our own strip, mirroring the bottom
        // effect's transport-bar host. Spans from the top of the view down to
        // the safe-area top so the soft blur sits where the nav bar overlaps
        // the scrolling content.
        view.addSubview(topScrollEdgeContainer)
        topScrollEdgeContainer.addInteraction(topScrollEdgeInteraction)

        NSLayoutConstraint.activate([
            outerScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            outerScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outerScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            outerScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            topScrollEdgeContainer.topAnchor.constraint(equalTo: view.topAnchor),
            topScrollEdgeContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topScrollEdgeContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topScrollEdgeContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),

            pagesStack.topAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.topAnchor),
            pagesStack.leadingAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.leadingAnchor),
            pagesStack.trailingAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.trailingAnchor),
            pagesStack.bottomAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.bottomAnchor),
            pagesStack.widthAnchor.constraint(equalTo: outerScrollView.frameLayoutGuide.widthAnchor),

            dialoguePageView.heightAnchor.constraint(equalTo: outerScrollView.frameLayoutGuide.heightAnchor),
            quizPageView.heightAnchor.constraint(equalTo: outerScrollView.frameLayoutGuide.heightAnchor),
            highlightsPageView.heightAnchor.constraint(equalTo: outerScrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    private func configureDialoguePage() {
        dialoguePageView.backgroundColor = ExperimentPalette.pageBackground
        dialoguePageView.clipsToBounds = true
        guard let item = currentScenarioItem else { return }
        embedDialogue(for: item)
    }

    /// All switchable scenarios, in display order, for the active source.
    private var scenarioItems: [ScenarioItem] {
        if usesLegacyCatalog {
            return DialogueExperimentCatalog.entries.map { entry in
                ScenarioItem(
                    id: entry.id,
                    menuTitle: entry.menuTitle,
                    menuSubtitle: entry.menuSubtitle,
                    pointTitle: entry.pointTitle,
                    example: entry.example,
                    highlights: entry.learningHighlights,
                    quiz: [],
                    grammarPointIDs: entry.learningHighlights.grammarPatterns.compactMap(\.grammarPointID)
                )
            }
        }
        guard let collection else { return [] }
        return collection.scenarios.map { scenario in
            ScenarioItem(
                id: scenario.id,
                menuTitle: scenario.menuTitle,
                menuSubtitle: scenario.menuSubtitle,
                pointTitle: collection.title,
                example: scenario.example,
                highlights: scenario.highlights,
                quiz: scenario.quiz,
                grammarPointIDs: scenario.grammarPointIDs
            )
        }
    }

    private var currentScenarioItem: ScenarioItem? {
        let items = scenarioItems
        return items.first { $0.id == selectedScenarioID } ?? items.first
    }

    private func configureDialogueNavigationItems() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: nil,
            image: UIImage(systemName: "text.line.first.and.arrowtriangle.forward"),
            primaryAction: nil,
            menu: makeDialogueMenu()
        )
    }

    private func makeDialogueMenu() -> UIMenu {
        let actions = scenarioItems.map { item in
            UIAction(
                title: item.menuTitle,
                subtitle: item.menuSubtitle,
                state: item.id == selectedScenarioID ? .on : .off
            ) { [weak self] _ in
                self?.selectScenario(id: item.id)
            }
        }
        return UIMenu(
            title: collection?.title ?? "Scenarios",
            options: .singleSelection,
            children: actions
        )
    }

    private func selectScenario(id: String) {
        guard id != selectedScenarioID else { return }
        selectedScenarioID = id
        guard let item = currentScenarioItem else { return }
        title = item.menuTitle
        navigationItem.rightBarButtonItem?.menu = makeDialogueMenu()
        embedDialogue(for: item)
        reloadQuizContent()
        reloadHighlightsContent()
        updateQuizPageVisibility()
        didSettleQuizScrollAtTop = false
        didSettleHighlightsScrollAtTop = false
        refreshHandoffCoordinatorInnerScrollViews()
        clampOuterScrollToValidPageIfNeeded()
    }

    private func embedDialogue(for item: ScenarioItem) {
        if let existing = dialogueViewController {
            existing.stopHostedPlaybackIfDisappearing()
            existing.reloadScenario(
                pointTitle: item.pointTitle,
                example: item.example,
                scenarioID: item.id,
                grammarPointIDs: item.grammarPointIDs
            )
            applyScrollLayoutIfNeeded(force: true)
            configureScrollEdgeEffects()
            updateScrollEdgeInteractionsForActivePage()
            existing.applyNestedPagingTransportProgress(activePageIndex == 0 ? 0 : 1)
            return
        }

        let dialogue = DialogueExperimentViewController(
            pointTitle: item.pointTitle,
            example: item.example,
            presentationContext: .nestedPagingHost,
            scenarioID: item.id,
            grammarPointIDs: item.grammarPointIDs
        )
        dialogue.sceneImageName = collection?.sceneImageName
        dialogue.sceneImageURL = collection?.thumbnailURL
        addChild(dialogue)
        dialogue.view.translatesAutoresizingMaskIntoConstraints = false
        dialoguePageView.addSubview(dialogue.view)
        NSLayoutConstraint.activate([
            dialogue.view.topAnchor.constraint(equalTo: dialoguePageView.topAnchor),
            dialogue.view.leadingAnchor.constraint(equalTo: dialoguePageView.leadingAnchor),
            dialogue.view.trailingAnchor.constraint(equalTo: dialoguePageView.trailingAnchor),
            dialogue.view.bottomAnchor.constraint(equalTo: dialoguePageView.bottomAnchor),
        ])
        dialogue.didMove(toParent: self)
        dialogueViewController = dialogue
        dialogue.installHostedTransportBar(in: view)
        bringPageChromeToFront()

        if handoffCoordinator != nil {
            handoffCoordinator?.replaceDialogueScrollView(dialogue.handoffScrollView)
            configureScrollEdgeEffects()
            updateScrollEdgeInteractionsForActivePage()
            applyScrollLayoutIfNeeded(force: true)
            dialogueViewController.applyNestedPagingTransportProgress(activePageIndex == 0 ? 0 : 1)
        }
    }

    private func configureQuizPage() {
        quizPageView.backgroundColor = ExperimentPalette.pageBackground
        quizPageView.clipsToBounds = true
        quizPageView.isHidden = true

        quizScrollView.translatesAutoresizingMaskIntoConstraints = false
        quizScrollView.backgroundColor = .clear
        quizScrollView.showsVerticalScrollIndicator = true
        quizScrollView.alwaysBounceVertical = true
        quizScrollView.bounces = true
        quizScrollView.decelerationRate = .normal
        quizScrollView.delaysContentTouches = false
        quizScrollView.contentInsetAdjustmentBehavior = .never
        quizPageView.addSubview(quizScrollView)

        quizContentView.translatesAutoresizingMaskIntoConstraints = false
        quizContentView.onSelectionChanged = { [weak self] in
            self?.updateQuizCheckButtonState()
        }
        quizScrollView.addSubview(quizContentView)

        NSLayoutConstraint.activate([
            quizScrollView.topAnchor.constraint(equalTo: quizPageView.topAnchor),
            quizScrollView.leadingAnchor.constraint(equalTo: quizPageView.leadingAnchor),
            quizScrollView.trailingAnchor.constraint(equalTo: quizPageView.trailingAnchor),
            quizScrollView.bottomAnchor.constraint(equalTo: quizPageView.bottomAnchor),

            quizContentView.topAnchor.constraint(equalTo: quizScrollView.contentLayoutGuide.topAnchor, constant: 8),
            quizContentView.leadingAnchor.constraint(equalTo: quizScrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            quizContentView.trailingAnchor.constraint(equalTo: quizScrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            quizContentView.bottomAnchor.constraint(equalTo: quizScrollView.contentLayoutGuide.bottomAnchor, constant: -32),
            quizContentView.widthAnchor.constraint(
                equalTo: quizScrollView.frameLayoutGuide.widthAnchor,
                constant: -40
            ),
        ])
    }

    private func reloadQuizContent() {
        let questions = currentScenarioItem?.quiz ?? []
        quizContentView.configure(questions: questions)
        updateQuizCheckButtonState()
        applyQuizCheckButtonProgress(pageTransitionProgress)
    }

    private func configureQuizCheckButton() {
        var config = UIButton.Configuration.glass()
        config.cornerStyle = .capsule
        config.title = "Check"
        config.baseForegroundColor = UIColor.systemYellow
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
            return outgoing
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        quizCheckButton.configuration = config
        quizCheckButton.translatesAutoresizingMaskIntoConstraints = false
        quizCheckButton.accessibilityLabel = "Check answers"
        quizCheckButton.alpha = 0
        quizCheckButton.isEnabled = false
        quizCheckButton.isUserInteractionEnabled = false
        quizCheckButton.addAction(UIAction { [weak self] _ in
            self?.quizCheckTapped()
        }, for: .primaryActionTriggered)
        view.addSubview(quizCheckButton)

        NSLayoutConstraint.activate([
            quizCheckButton.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -Self.quizCheckButtonHorizontalInset
            ),
            quizCheckButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -Self.quizCheckButtonBottomInset
            ),
            quizCheckButton.heightAnchor.constraint(equalToConstant: Self.quizCheckButtonHeight),
        ])
    }

    private func quizCheckTapped() {
        quizContentView.checkAnswers()
        updateQuizCheckButtonState()
        applyQuizCheckButtonProgress(pageTransitionProgress)
        applyQuizScrollInsetsForPageTransition()
    }

    private func updateQuizCheckButtonState() {
        quizCheckButton.isEnabled = quizContentView.canCheckAnswers
    }

    private func updateQuizPageVisibility() {
        quizPageView.isHidden = !hasQuizPage
    }

    private func refreshHandoffCoordinatorInnerScrollViews() {
        handoffCoordinator?.replaceInnerScrollViews(innerScrollViewsForCurrentScenario())
        configureScrollEdgeEffects()
        updateScrollEdgeInteractionsForActivePage()
    }

    private func clampOuterScrollToValidPageIfNeeded() {
        let pageHeight = outerScrollView.bounds.height
        guard pageHeight > 0 else { return }
        let maxIndex = pageCount - 1
        let currentIndex = Int(round(outerScrollView.contentOffset.y / pageHeight))
        guard currentIndex > maxIndex else { return }
        handoffCoordinator?.snapToPage(maxIndex)
    }

    private func configureHighlightsPage() {
        highlightsPageView.backgroundColor = ExperimentPalette.pageBackground
        highlightsPageView.clipsToBounds = true

        highlightsScrollView.translatesAutoresizingMaskIntoConstraints = false
        highlightsScrollView.backgroundColor = .clear
        highlightsScrollView.showsVerticalScrollIndicator = true
        highlightsScrollView.alwaysBounceVertical = true
        highlightsScrollView.bounces = true
        highlightsScrollView.decelerationRate = .normal
        highlightsScrollView.delaysContentTouches = false
        highlightsScrollView.contentInsetAdjustmentBehavior = .never
        highlightsPageView.addSubview(highlightsScrollView)

        highlightsContentView.translatesAutoresizingMaskIntoConstraints = false
        highlightsContentView.onSelectVocabulary = { [weak self] word in
            guard let self else { return }
            WordDictionaryDetailSheetPresenter.push(surface: word, from: self)
        }
        highlightsContentView.onSelectGrammar = { [weak self] grammarPointID in
            guard let self else { return }
            GrammarReferencePresenter.open(grammarPointID: grammarPointID, from: self)
        }
        highlightsScrollView.addSubview(highlightsContentView)

        NSLayoutConstraint.activate([
            highlightsScrollView.topAnchor.constraint(equalTo: highlightsPageView.topAnchor),
            highlightsScrollView.leadingAnchor.constraint(equalTo: highlightsPageView.leadingAnchor),
            highlightsScrollView.trailingAnchor.constraint(equalTo: highlightsPageView.trailingAnchor),
            highlightsScrollView.bottomAnchor.constraint(equalTo: highlightsPageView.bottomAnchor),

            highlightsContentView.topAnchor.constraint(equalTo: highlightsScrollView.contentLayoutGuide.topAnchor, constant: 8),
            highlightsContentView.leadingAnchor.constraint(equalTo: highlightsScrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            highlightsContentView.trailingAnchor.constraint(equalTo: highlightsScrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            highlightsContentView.bottomAnchor.constraint(equalTo: highlightsScrollView.contentLayoutGuide.bottomAnchor, constant: -32),
            highlightsContentView.widthAnchor.constraint(
                equalTo: highlightsScrollView.frameLayoutGuide.widthAnchor,
                constant: -40
            ),
        ])
    }

    private func reloadHighlightsContent() {
        let highlights = currentScenarioItem?.highlights ?? .empty
        highlightsContentView.configure(highlights: highlights)
    }

    private func applyScrollLayoutIfNeeded(force: Bool = false) {
        let dialogueTopInset = view.safeAreaInsets.top
        let bottomInset = view.safeAreaInsets.bottom + 16
        guard force || dialogueTopInset != appliedTopContentInset || bottomInset != appliedBottomContentInset else { return }

        appliedTopContentInset = dialogueTopInset
        appliedBottomContentInset = bottomInset

        dialogueViewController.applyNestedPagingTopContentInset(dialogueTopInset)
        applyQuizScrollInsetsForPageTransition()
        applyHighlightsScrollInsetsForPageTransition()
    }

    private func applyQuizScrollInsetsForPageTransition() {
        guard hasQuizPage else { return }

        let topInset = quizTopContentInset(for: pageTransitionProgress)
        let bottomInset = quizBottomContentInset(for: pageTransitionProgress)

        quizScrollView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        quizScrollView.verticalScrollIndicatorInsets = UIEdgeInsets(
            top: topInset,
            left: 0,
            bottom: bottomInset,
            right: 0
        )
    }

    private func quizTopContentInset(for outerPageOffset: CGFloat) -> CGFloat {
        let base = view.safeAreaInsets.top
        let settled = base + Self.highlightsSecondPageTopInsetExtra
        guard hasQuizPage else { return base }

        if activePageIndex >= 1, activePageIndex < highlightsPageIndex {
            return settled
        }

        let segmentProgress = outerPageOffset
        let clamped = min(max(segmentProgress, 0), 1)
        guard clamped > 0.001 else { return base }
        if clamped >= 0.999 { return settled }
        return base + (settled - base) * clamped
    }

    private func quizBottomContentInset(for outerPageOffset: CGFloat) -> CGFloat {
        let base = appliedBottomContentInset >= 0
            ? appliedBottomContentInset
            : view.safeAreaInsets.bottom + 16
        guard hasQuizPage, !quizContentView.hasCheckedAnswers else { return base }

        let visibility = quizCheckButtonVisibility(for: outerPageOffset)
        let checkButtonClearance = Self.quizCheckButtonHeight + 16
        return base + checkButtonClearance * visibility.alpha
    }

    /// Visibility and slide progress for the quiz check button (page index 1 when a quiz exists).
    private func quizCheckButtonVisibility(for outerPageOffset: CGFloat) -> (alpha: CGFloat, slideProgress: CGFloat) {
        if outerPageOffset <= 1 {
            let t = min(max(outerPageOffset, 0), 1)
            return (t, 1 - t)
        }
        let t = min(max(outerPageOffset - 1, 0), 1)
        return (1 - t, t)
    }

    private func applyQuizCheckButtonProgress(_ outerPageOffset: CGFloat) {
        guard hasQuizPage, !quizContentView.hasCheckedAnswers else {
            quizCheckButton.alpha = 0
            quizCheckButton.isUserInteractionEnabled = false
            return
        }

        let visibility = quizCheckButtonVisibility(for: outerPageOffset)
        let translationX = -Self.quizCheckSlideDistance * visibility.slideProgress
        quizCheckButton.alpha = visibility.alpha
        quizCheckButton.transform = CGAffineTransform(translationX: translationX, y: 0)
        quizCheckButton.isEnabled = quizContentView.canCheckAnswers
        quizCheckButton.isUserInteractionEnabled = visibility.alpha > 0.65
    }

    private func applyHighlightsScrollInsetsForPageTransition() {
        let topInset = highlightsTopContentInset(for: pageTransitionProgress)
        let bottomInset = appliedBottomContentInset >= 0
            ? appliedBottomContentInset
            : view.safeAreaInsets.bottom + 16

        highlightsScrollView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        highlightsScrollView.verticalScrollIndicatorInsets = UIEdgeInsets(
            top: topInset,
            left: 0,
            bottom: bottomInset,
            right: 0
        )
    }

    private func highlightsTopContentInset(for outerPageOffset: CGFloat) -> CGFloat {
        let base = view.safeAreaInsets.top
        let settled = base + Self.highlightsSecondPageTopInsetExtra
        if activePageIndex >= highlightsPageIndex {
            return settled
        }

        let segmentStart = CGFloat(highlightsPageIndex - 1)
        let segmentProgress = outerPageOffset - segmentStart
        let clamped = min(max(segmentProgress, 0), 1)
        guard clamped > 0.001 else { return base }
        if clamped >= 0.999 { return settled }
        return base + (settled - base) * clamped
    }

    private func currentPageTransitionProgress() -> CGFloat {
        guard outerScrollView.bounds.height > 0 else { return 0 }
        return max(outerScrollView.contentOffset.y / outerScrollView.bounds.height, 0)
    }

    private func applyPageTransitionProgress(_ progress: CGFloat) {
        pageTransitionProgress = max(progress, 0)
        updatePageChevrons()

        applyQuizScrollInsetsForPageTransition()
        applyHighlightsScrollInsetsForPageTransition()
        applyQuizCheckButtonProgress(progress)
        dialogueViewController.applyNestedPagingTransportProgress(activePageIndex == 0 ? 0 : 1)

        let settledOnQuiz = hasQuizPage && activePageIndex == 1
        if settledOnQuiz, !didSettleQuizScrollAtTop, quizScrollView.contentOffset.y <= 1 {
            quizScrollView.contentOffset.y = -quizScrollView.adjustedContentInset.top
        }
        didSettleQuizScrollAtTop = settledOnQuiz

        let settledOnHighlights = activePageIndex >= highlightsPageIndex
        if settledOnHighlights, !didSettleHighlightsScrollAtTop, highlightsScrollView.contentOffset.y <= 1 {
            let topBoundary = -highlightsScrollView.adjustedContentInset.top
            highlightsScrollView.contentOffset.y = topBoundary
        }
        didSettleHighlightsScrollAtTop = settledOnHighlights
    }

    private func pageChevronBottomCenterY() -> CGFloat {
        view.bounds.height - view.safeAreaInsets.bottom - 33
    }

    private func pageChevronTopCenterY() -> CGFloat {
        view.safeAreaInsets.top + Self.pageNavigationControlHeight / 2
    }

    private var isChevronFollowingScroll: Bool {
        if outerScrollView.isTracking || outerScrollView.isDecelerating { return true }
        if handoffCoordinator?.isAnimatingPageSnap ?? false { return true }
        return innerScrollViewsForCurrentScenario().contains { $0.isTracking || $0.isDecelerating }
    }

    /// Each chevron tracks a page seam but sits on the inset top/bottom rail —
    /// not on the raw seam line. Position follows scroll offset continuously;
    /// when the pager isn't moving, changes spring in instead of snapping.
    private func updatePageChevrons() {
        let pageHeight = outerScrollView.bounds.height
        guard pageHeight > 0, pageCount > 1 else {
            firstSeamChevron.alpha = 0
            secondSeamChevron.alpha = 0
            firstSeamChevron.isUserInteractionEnabled = false
            secondSeamChevron.isUserInteractionEnabled = false
            return
        }

        let scrollOffsetY = outerScrollView.contentOffset.y
        let seamCount = pageCount - 1

        let apply = {
            self.layoutSeamChevron(
                button: self.firstSeamChevron,
                centerYConstraint: self.firstSeamCenterYConstraint,
                lowerPageIndex: 0,
                scrollOffsetY: scrollOffsetY,
                pageHeight: pageHeight,
                pointsUp: &self.firstSeamPointsUp
            )

            if seamCount >= 2 {
                self.layoutSeamChevron(
                    button: self.secondSeamChevron,
                    centerYConstraint: self.secondSeamCenterYConstraint,
                    lowerPageIndex: 1,
                    scrollOffsetY: scrollOffsetY,
                    pageHeight: pageHeight,
                    pointsUp: &self.secondSeamPointsUp
                )
            } else {
                self.secondSeamChevron.alpha = 0
                self.secondSeamChevron.isUserInteractionEnabled = false
            }

            self.view.layoutIfNeeded()
        }

        if isChevronFollowingScroll {
            chevronSpringAnimator?.stopAnimation(true)
            chevronSpringAnimator = nil
            apply()
            return
        }

        chevronSpringAnimator?.stopAnimation(true)
        let animator = UIViewPropertyAnimator(
            duration: 0.34,
            dampingRatio: 0.9,
            animations: apply
        )
        animator.startAnimation()
        chevronSpringAnimator = animator
    }

    /// Maps seam travel through the viewport onto the inset top/bottom rail.
    private func chevronCenterY(forSeamViewportY seamViewportY: CGFloat, pageHeight: CGFloat) -> CGFloat {
        let topRest = pageChevronTopCenterY()
        let bottomRest = pageChevronBottomCenterY()
        let travel = 1 - min(max(seamViewportY / pageHeight, 0), 1)
        return bottomRest + (topRest - bottomRest) * travel
    }

    private func layoutSeamChevron(
        button: UIButton,
        centerYConstraint: NSLayoutConstraint,
        lowerPageIndex: Int,
        scrollOffsetY: CGFloat,
        pageHeight: CGFloat,
        pointsUp: inout Bool
    ) {
        let seamContentY = CGFloat(lowerPageIndex + 1) * pageHeight
        let seamViewportY = seamContentY - scrollOffsetY
        let viewportHeight = view.bounds.height
        let fadeMargin = Self.pageNavigationControlHeight * 1.5

        let centerY = chevronCenterY(forSeamViewportY: seamViewportY, pageHeight: pageHeight)
        centerYConstraint.constant = centerY

        let alphaAbove = min(max((seamViewportY + fadeMargin) / fadeMargin, 0), 1)
        let alphaBelow = min(max((viewportHeight + fadeMargin - seamViewportY) / fadeMargin, 0), 1)
        let visibility = min(alphaAbove, alphaBelow)
        button.alpha = visibility
        button.isUserInteractionEnabled = visibility > 0.65

        let shouldPointUp = seamViewportY < viewportHeight * 0.5
        if shouldPointUp != pointsUp {
            pointsUp = shouldPointUp
            applyChevronDirection(to: button, pointsUp: shouldPointUp)
        }

        button.accessibilityLabel = shouldPointUp
            ? "Return to previous section"
            : "Show next section"
    }

    private func applyChevronDirection(to button: UIButton, pointsUp: Bool) {
        let symbolName = pointsUp ? "chevron.compact.up" : "chevron.compact.down"
        let symbolConfig = UIImage.SymbolConfiguration(
            pointSize: Self.pageNavigationSymbolPointSize,
            weight: .medium
        )
        button.setImage(
            UIImage(systemName: symbolName, withConfiguration: symbolConfig),
            for: .normal
        )
    }

    private func configureScrollEdgeEffects() {
        for scrollView in innerScrollViewsForCurrentScenario() {
            scrollView.delaysContentTouches = false
            scrollView.topEdgeEffect.style = .soft
            scrollView.topEdgeEffect.isHidden = false
            scrollView.bottomEdgeEffect.style = .soft
            scrollView.bottomEdgeEffect.isHidden = false
        }
        updateScrollEdgeInteractionsForActivePage()
    }

    private func attachTopScrollEdgeInteraction() {
        topScrollEdgeInteraction.scrollView = dialogueViewController.handoffScrollView
    }

    private func updateScrollEdgeInteractionsForActivePage() {
        topScrollEdgeInteraction.scrollView = activeInnerScrollView
    }

    private func configurePageChevrons() {
        let symbolConfig = UIImage.SymbolConfiguration(
            pointSize: Self.pageNavigationSymbolPointSize,
            weight: .medium
        )

        for button in [firstSeamChevron, secondSeamChevron] {
            var config = UIButton.Configuration.plain()
            config.baseForegroundColor = .secondaryLabel
            config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
            button.configuration = config
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setPreferredSymbolConfiguration(symbolConfig, forImageIn: .normal)
            view.addSubview(button)
        }

        firstSeamChevron.addAction(UIAction { [weak self] _ in
            self?.seamChevronTapped(lowerPageIndex: 0, pointsUp: self?.firstSeamPointsUp ?? false)
        }, for: .primaryActionTriggered)
        secondSeamChevron.addAction(UIAction { [weak self] _ in
            self?.seamChevronTapped(lowerPageIndex: 1, pointsUp: self?.secondSeamPointsUp ?? false)
        }, for: .primaryActionTriggered)

        applyChevronDirection(to: firstSeamChevron, pointsUp: false)
        applyChevronDirection(to: secondSeamChevron, pointsUp: false)

        firstSeamCenterYConstraint = firstSeamChevron.centerYAnchor.constraint(
            equalTo: view.topAnchor,
            constant: outerScrollView.bounds.height
        )
        secondSeamCenterYConstraint = secondSeamChevron.centerYAnchor.constraint(
            equalTo: view.topAnchor,
            constant: outerScrollView.bounds.height * 2
        )

        NSLayoutConstraint.activate([
            firstSeamChevron.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            firstSeamCenterYConstraint,
            firstSeamChevron.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.pageNavigationControlHeight),
            firstSeamChevron.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.pageNavigationControlHeight),

            secondSeamChevron.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            secondSeamCenterYConstraint,
            secondSeamChevron.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.pageNavigationControlHeight),
            secondSeamChevron.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.pageNavigationControlHeight),
        ])
    }

    private func seamChevronTapped(lowerPageIndex: Int, pointsUp: Bool) {
        let targetPage = pointsUp ? lowerPageIndex : lowerPageIndex + 1
        handoffCoordinator?.snapToPage(min(max(targetPage, 0), pageCount - 1))
    }

    private func bringPageChromeToFront() {
        // Keep the top edge strip above the scrolling content so its soft blur
        // renders over the pager (mirrors the transport bar staying frontmost).
        view.bringSubviewToFront(topScrollEdgeContainer)
        if let transportBar = dialogueViewController?.nestedPagingTransportBarView {
            view.bringSubviewToFront(transportBar)
        }
        view.bringSubviewToFront(quizCheckButton)
        view.bringSubviewToFront(firstSeamChevron)
        view.bringSubviewToFront(secondSeamChevron)
        loadingCoordinator.bringOverlayToFront()
    }

    private func installHandoffCoordinator() {
        let coordinator = NestedVerticalScrollHandoffCoordinator(
            outerScrollView: outerScrollView,
            innerScrollViews: innerScrollViewsForCurrentScenario(),
            boundaryEpsilon: Self.boundaryEpsilon
        )
        coordinator.onPageTransitionProgressChanged = { [weak self] progress in
            self?.applyPageTransitionProgress(progress)
        }
        coordinator.onPageChanged = { [weak self] page in
            guard let self else { return }
            self.updateScrollEdgeInteractionsForActivePage()
            let transportProgress: CGFloat = page == 0 ? 0 : 1
            self.dialogueViewController.applyNestedPagingTransportProgress(transportProgress, animated: true)
        }
        handoffCoordinator = coordinator
    }

}

extension DialogueNestedPagingExperimentViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard hasLoadedLessonContent, scrollView === outerScrollView else { return }
        applyPageTransitionProgress(currentPageTransitionProgress())
    }
}
