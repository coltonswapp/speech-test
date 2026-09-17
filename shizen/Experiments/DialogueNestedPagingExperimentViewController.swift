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
    /// How much inner overflow maps onto the outer pager. `1` is 1:1; lower is more resistance.
    private let pageTransitionResistance: CGFloat
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
        pageCommitThreshold: CGFloat = 0.52,
        velocityThreshold: CGFloat = 1.15,
        pageTransitionResistance: CGFloat = 0.52
    ) {
        self.outerScrollView = outerScrollView
        self.innerScrollViews = innerScrollViews
        self.boundaryEpsilon = boundaryEpsilon
        self.pageCommitThreshold = pageCommitThreshold
        self.velocityThreshold = velocityThreshold
        self.pageTransitionResistance = pageTransitionResistance
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
                applyResistedOuterDelta(delta, minY: pageOrigin, maxY: outerMaxY)
                innerScrollView.contentOffset.y = bounds.maxY
            case .fromTop:
                applyResistedOuterDelta(delta, minY: outerMinY, maxY: pageOrigin)
                innerScrollView.contentOffset.y = bounds.minY
            }
            return
        }

        if innerOffsetY > bounds.maxY + boundaryEpsilon {
            guard pageIndex < maxPageIndex else { return }

            let overflow = innerOffsetY - bounds.maxY
            applyResistedOuterDelta(overflow, minY: outerMinY, maxY: outerMaxY)
            innerScrollView.contentOffset.y = bounds.maxY
        } else if innerOffsetY < bounds.minY - boundaryEpsilon {
            guard pageIndex > 0 else { return }

            let overflow = innerOffsetY - bounds.minY
            applyResistedOuterDelta(overflow, minY: outerMinY, maxY: outerMaxY)
            innerScrollView.contentOffset.y = bounds.minY
        } else if innerOffsetY >= bounds.maxY - boundaryEpsilon, delta > 0, pageIndex < maxPageIndex {
            applyResistedOuterDelta(delta, minY: outerMinY, maxY: outerMaxY)
            innerScrollView.contentOffset.y = bounds.maxY
        } else if innerOffsetY <= bounds.minY + boundaryEpsilon, delta < 0, pageIndex > 0 {
            applyResistedOuterDelta(delta, minY: outerMinY, maxY: outerMaxY)
            innerScrollView.contentOffset.y = bounds.minY
        }
    }

    private func applyResistedOuterDelta(_ delta: CGFloat, minY: CGFloat, maxY: CGFloat) {
        guard let outerScrollView else { return }
        outerScrollView.contentOffset.y = min(
            max(outerScrollView.contentOffset.y + delta * pageTransitionResistance, minY),
            maxY
        )
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
    /// Fraction of a page the outer pager must travel (without a strong flick) before committing.
    private static let pageCommitThreshold: CGFloat = 0.52
    /// Vertical flick speed that commits a neighboring page even below `pageCommitThreshold`.
    private static let pageVelocityThreshold: CGFloat = 1.15
    /// Inner overflow → outer pager mapping. Lower values make section seams feel stickier.
    private static let pageTransitionResistance: CGFloat = 0.52
    private static let pageNavigationControlHeight: CGFloat = 52
    private static let pageNavigationSymbolPointSize: CGFloat = 22
    private static let highlightsSecondPageTopInsetExtra: CGFloat = 56
    private static let quizCheckButtonHorizontalInset: CGFloat = 20
    private static let quizCheckButtonBottomInset: CGFloat = 8
    private static let quizCheckButtonHeight: CGFloat = 50
    private static let quizNextGlyphPointSize: CGFloat = 22
    /// Mirrors `DialogueExperimentViewController.nestedPagingTransportSlideDistance`; play exits +X, check uses −X.
    private static let quizCheckSlideDistance: CGFloat = 140
    private static let contentRevealSlideDistance: CGFloat = 18

    private let outerScrollView = UIScrollView()
    private let pagesStack = UIStackView()
    private let dialoguePageView = UIView()
    private let quizPageView = UIView()
    private let highlightsPageView = UIView()
    private var dialogueViewController: DialogueExperimentViewController!
    private var quizViewController: DialogueQuizViewController!
    private let quizNextButton = UIButton(type: .system)
    private let quizNextGlyphView = UIImageView()
    private let quizPlayButton = UIButton(type: .system)
    private let quizPlayGlyphView = UIImageView()
    private let quizContinueButton = UIButton(type: .system)
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

    /// Bottom edge interaction for quiz / highlights. Same API as dialogue's
    /// transport-bar setup and ProgressiveStep's `buttonContainer`:
    /// `interaction.scrollView = scrollView` + container that *contains* glass controls.
    private let bottomScrollEdgeInteraction: UIScrollEdgeElementContainerInteraction = {
        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.edge = .bottom
        return interaction
    }()

    /// Per-chevron edge interactions so the bottom-rail control itself shapes the
    /// soft effect (Apple: controls overlaying the edge must participate).
    private let firstSeamScrollEdgeInteraction: UIScrollEdgeElementContainerInteraction = {
        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.edge = .bottom
        return interaction
    }()

    private let secondSeamScrollEdgeInteraction: UIScrollEdgeElementContainerInteraction = {
        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.edge = .bottom
        return interaction
    }()

    /// Host-owned anchor for the top edge effect. Attaching the interaction to
    /// the system nav bar proved unreliable here, so we host a thin,
    /// non-interactive strip across the top of our own view instead.
    private let topScrollEdgeContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }()

    /// Bottom chrome host for quiz / highlights — mirrors ProgressiveStep's
    /// `buttonContainer` / dialogue's `transportBarContainer`. Must contain
    /// glass controls (next-question + bottom-rail chevrons) so the soft edge effect
    /// has descendants to shape against; an empty container does nothing.
    private let bottomScrollEdgeContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
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
    private var sessionMode: DialogueLessonSessionMode
    private var hasFinishedListeningThisVisit = false
    private var hasFinishedQuizThisVisit = false
    private var committedTally: DialogueCompletionTally?
    /// How the dialogue transcript renders (full text, Japanese only, live meters).
    private var transcriptDisplayMode: DialogueTranscriptDisplayMode = .full
    private var appliedTopContentInset: CGFloat = -1
    private var appliedBottomContentInset: CGFloat = -1
    private var pageTransitionProgress: CGFloat = 0
    private var didSettleHighlightsScrollAtTop = false
    private var didSettleQuizScrollAtTop = false
    private var lastKnownViewSize: CGSize = .zero
    private var hasLoadedLessonContent = false
    private var quizPlayButtonRevealed = false
    private var isAnimatingQuizPlayButton = false
    private var quizContinueButtonRevealed = false
    private var isAnimatingQuizContinueButton = false

    private var authoredHasQuiz: Bool {
        !(currentScenarioItem?.quiz.isEmpty ?? true)
    }

    private var isQuizUnlocked: Bool {
        authoredHasQuiz && sessionMode != .viewLesson && hasFinishedListeningThisVisit
    }

    private var isHighlightsUnlocked: Bool {
        switch sessionMode {
        case .viewLesson:
            return true
        case .retakeQuiz:
            return hasFinishedQuizThisVisit
        case .attempt:
            return authoredHasQuiz ? hasFinishedQuizThisVisit : hasFinishedListeningThisVisit
        }
    }

    private var hasQuizPage: Bool {
        isQuizUnlocked
    }

    private var pageCount: Int {
        var count = 1
        if hasQuizPage { count += 1 }
        if isHighlightsUnlocked { count += 1 }
        return count
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
            return index == 1 ? quizViewController.handoffScrollView : highlightsScrollView
        }
        return highlightsScrollView
    }

    private var activeInnerScrollView: UIScrollView {
        scrollView(forPageIndex: activePageIndex)
    }

    private func innerScrollViewsForCurrentScenario() -> [UIScrollView] {
        var scrollViews = [dialogueViewController.handoffScrollView]
        if hasQuizPage {
            scrollViews.append(quizViewController.handoffScrollView)
        }
        if isHighlightsUnlocked {
            scrollViews.append(highlightsScrollView)
        }
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
        /// Already resolved: scenario override, else collection thumbnail.
        let thumbnailURL: URL?
    }

    /// Drive the controller from a standalone collection (preferred when already in hand).
    init(
        collection: DialogueScenarioCollection,
        initialScenarioID: String? = nil,
        sessionMode: DialogueLessonSessionMode = .attempt
    ) {
        self.collection = collection
        self.pendingCollectionID = nil
        self.usesLegacyCatalog = false
        self.prefersNextIncompleteScenario = false
        self.sessionMode = sessionMode
        if let initialScenarioID,
           collection.scenarios.contains(where: { $0.id == initialScenarioID }) {
            self.selectedScenarioID = initialScenarioID
        } else {
            self.selectedScenarioID = collection.scenarios.first?.id ?? ""
        }
        super.init(nibName: nil, bundle: nil)
        applySessionUnlocksForCurrentMode()
    }

    /// Push immediately with a collection id; shows loading while the catalog resolves.
    init(
        collectionID: String,
        initialScenarioID: String? = nil,
        prefersNextIncompleteScenario: Bool = false,
        sessionMode: DialogueLessonSessionMode = .attempt
    ) {
        self.collection = DialogueScenarioCollectionCatalog.readyCollection(id: collectionID)
        self.pendingCollectionID = collectionID
        self.usesLegacyCatalog = false
        self.prefersNextIncompleteScenario = prefersNextIncompleteScenario
        self.sessionMode = sessionMode
        self.selectedScenarioID = initialScenarioID ?? self.collection?.scenarios.first?.id ?? ""
        super.init(nibName: nil, bundle: nil)
        applySessionUnlocksForCurrentMode()
    }

    /// Legacy entry point: drive from the grammar-point–derived catalog.
    init() {
        self.collection = nil
        self.pendingCollectionID = nil
        self.usesLegacyCatalog = true
        self.prefersNextIncompleteScenario = false
        self.sessionMode = .attempt
        self.selectedScenarioID = DialogueExperimentFixture.audioKey
        super.init(nibName: nil, bundle: nil)
        applySessionUnlocksForCurrentMode()
    }

    required init?(coder: NSCoder) {
        self.collection = nil
        self.pendingCollectionID = nil
        self.usesLegacyCatalog = true
        self.prefersNextIncompleteScenario = false
        self.sessionMode = .attempt
        self.selectedScenarioID = DialogueExperimentFixture.audioKey
        super.init(coder: coder)
        applySessionUnlocksForCurrentMode()
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
        quizViewController?.stopEvidencePlayback()
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
            // Chrome ordering only changes at the specific call sites that add/reorder
            // subviews (embedDialogue, content reveal, page build) — they already call
            // bringPageChromeToFront() themselves, so this pass doesn't need to.
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
        if usesLegacyCatalog {
            finishCollectionResolutionAndBuild()
            return
        }

        let id = pendingCollectionID ?? collection?.id
        if let id, ContentCMSClient.isConfigured {
            DialogueScenarioCollectionCatalog.fetchCollection(id: id) { [weak self] fresh in
                guard let self else { return }
                if let fresh {
                    self.collection = fresh
                }
                guard self.collection != nil else {
                    self.loadingCoordinator.finishLoading {
                        self.showCollectionLoadFailure(id: id)
                    }
                    return
                }
                self.finishCollectionResolutionAndBuild()
            }
            return
        }

        finishCollectionResolutionAndBuild()
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
        quizNextButton.alpha = 0
        quizPlayButton.alpha = 0
        quizContinueButton.alpha = 0
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
            if self.sessionMode == .retakeQuiz, self.hasQuizPage {
                self.handoffCoordinator?.snapToPage(1)
                self.dialogueViewController.applyNestedPagingTransportProgress(1)
            } else {
                self.dialogueViewController.applyNestedPagingTransportProgress(0)
            }
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
        configureQuizNextButton()
        configureHighlightsPage()
        reloadQuizContent()
        reloadHighlightsContent()
        updateUnlockedPagesVisibility()
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

        // Top edge: host-owned strip under the nav bar.
        // Bottom edge for quiz / highlights: ProgressiveStep-style buttonContainer
        // on this host (dialogue keeps its reparented transport bar).
        view.addSubview(topScrollEdgeContainer)
        topScrollEdgeContainer.addInteraction(topScrollEdgeInteraction)
        installBottomScrollEdgeContainer()

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

    /// ProgressiveStep / dialogue pattern:
    /// ```
    /// interaction.scrollView = scrollView
    /// interaction.edge = .bottom
    /// buttonContainer.addInteraction(interaction)
    /// ```
    /// Container height comes from its glass control descendants (next button),
    /// same as the transport bar sizing itself from its buttons.
    private func installBottomScrollEdgeContainer() {
        view.addSubview(bottomScrollEdgeContainer)
        bottomScrollEdgeContainer.addInteraction(bottomScrollEdgeInteraction)

        NSLayoutConstraint.activate([
            bottomScrollEdgeContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomScrollEdgeContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomScrollEdgeContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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
                    grammarPointIDs: entry.learningHighlights.grammarPatterns.compactMap(\.grammarPointID),
                    thumbnailURL: nil
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
                grammarPointIDs: scenario.grammarPointIDs,
                thumbnailURL: collection.thumbnailURL(for: scenario)
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
        let scenariosSection = UIMenu(
            options: [.singleSelection, .displayInline],
            children: actions
        )
        let displayOptions: [(DialogueTranscriptDisplayMode, String, String)] = [
            (.full, "Japanese · swipe for English", "text.bubble"),
            (.japaneseOnly, "Hide English", "eye.slash"),
            (.listeningSpeakers, "Live meters", "waveform"),
            (.listeningLines, "Live meters · every line", "waveform.path"),
            (.reveal, "Reveal Mode", "hand.tap"),
        ]
        let displayActions = displayOptions.map { mode, title, symbol in
            UIAction(
                title: title,
                image: UIImage(systemName: symbol),
                state: transcriptDisplayMode == mode ? .on : .off
            ) { [weak self] _ in
                self?.selectTranscriptDisplayMode(mode)
            }
        }
        let settingsSection = UIMenu(
            options: [.singleSelection, .displayInline],
            children: displayActions
        )
        let tokenSyncAction = UIAction(
            title: "Token sync",
            subtitle: "Yellow highlight on the spoken word",
            image: UIImage(systemName: "highlighter"),
            state: ExperimentSettings.dialogueShowsTokenSync ? .on : .off
        ) { [weak self] _ in
            self?.toggleTokenSyncHighlight()
        }
        var children: [UIMenuElement] = [
            scenariosSection,
            settingsSection,
            tokenSyncAction,
            makeTokenSyncHighlightStyleMenu(),
        ]
        if sessionMode == .viewLesson, authoredHasQuiz {
            let retake = UIAction(
                title: "Retake quiz",
                image: UIImage(systemName: "arrow.counterclockwise")
            ) { [weak self] _ in
                self?.startRetake()
            }
            children.append(retake)
        }
        return UIMenu(
            title: collection?.title ?? "Scenarios",
            children: children
        )
    }

    private func makeTokenSyncHighlightStyleMenu() -> UIMenu {
        let selected = ExperimentSettings.dialogueTokenSyncHighlightStyle
        let actions = DialogueTokenSyncHighlightStyle.allCases.map { style in
            UIAction(
                title: style.title,
                subtitle: style.subtitle,
                state: style == selected ? .on : .off
            ) { [weak self] _ in
                self?.setTokenSyncHighlightStyle(style)
            }
        }
        return UIMenu(
            title: "Token highlight",
            image: UIImage(systemName: "paintbrush.pointed"),
            options: .singleSelection,
            children: actions
        )
    }

    private func toggleTokenSyncHighlight() {
        ExperimentSettings.dialogueShowsTokenSync.toggle()
        navigationItem.rightBarButtonItem?.menu = makeDialogueMenu()
        dialogueViewController?.applyTokenSyncHighlightSetting()
    }

    private func setTokenSyncHighlightStyle(_ style: DialogueTokenSyncHighlightStyle) {
        ExperimentSettings.dialogueTokenSyncHighlightStyle = style
        navigationItem.rightBarButtonItem?.menu = makeDialogueMenu()
        dialogueViewController?.applyTokenSyncHighlightSetting()
    }

    private func selectTranscriptDisplayMode(_ mode: DialogueTranscriptDisplayMode) {
        guard mode != transcriptDisplayMode else { return }
        transcriptDisplayMode = mode
        dialogueViewController?.transcriptDisplayMode = mode
        navigationItem.rightBarButtonItem?.menu = makeDialogueMenu()
    }

    private func selectScenario(id: String) {
        guard id != selectedScenarioID else { return }
        selectedScenarioID = id
        sessionMode = resolvedSessionMode(preferred: sessionMode, scenarioID: id)
        applySessionUnlocksForCurrentMode()
        guard let item = currentScenarioItem else { return }
        title = item.menuTitle
        navigationItem.rightBarButtonItem?.menu = makeDialogueMenu()
        embedDialogue(for: item)
        reloadQuizContent()
        reloadHighlightsContent()
        updateUnlockedPagesVisibility()
        didSettleQuizScrollAtTop = false
        didSettleHighlightsScrollAtTop = false
        refreshHandoffCoordinatorInnerScrollViews()
        view.layoutIfNeeded()
        if sessionMode == .retakeQuiz, hasQuizPage {
            handoffCoordinator?.snapToPage(1)
        } else {
            clampOuterScrollToValidPageIfNeeded()
        }
    }

    private func embedDialogue(for item: ScenarioItem) {
        if let existing = dialogueViewController {
            existing.stopHostedPlaybackIfDisappearing()
            existing.recordsCompletionOnPlaybackFinish = shouldRecordCompletionOnPlaybackFinish(for: item)
            existing.onPlaybackFinished = { [weak self] in
                self?.handleDialoguePlaybackFinished()
            }
            existing.tokenSyncSettingDidChange = { [weak self] in
                self?.navigationItem.rightBarButtonItem?.menu = self?.makeDialogueMenu()
            }
            existing.updateSceneImage(
                url: item.thumbnailURL,
                assetName: collection?.sceneImageName
            )
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
        dialogue.sceneImageURL = item.thumbnailURL
        dialogue.transcriptDisplayMode = transcriptDisplayMode
        dialogue.recordsCompletionOnPlaybackFinish = shouldRecordCompletionOnPlaybackFinish(for: item)
        dialogue.onPlaybackFinished = { [weak self] in
            self?.handleDialoguePlaybackFinished()
        }
        dialogue.tokenSyncSettingDidChange = { [weak self] in
            self?.navigationItem.rightBarButtonItem?.menu = self?.makeDialogueMenu()
        }
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

        let quiz = DialogueQuizViewController()
        quiz.onQuizFinished = { [weak self] _ in
            self?.handleQuizFinished()
        }
        quiz.onHandoffScrollViewChanged = { [weak self] in
            self?.refreshHandoffCoordinatorInnerScrollViews()
        }
        quiz.onEvidencePlaybackWillStart = { [weak self] in
            self?.dialogueViewController.stopHostedPlaybackIfDisappearing()
        }
        quiz.onNavigationChromeNeedsUpdate = { [weak self] in
            self?.updateQuizNextButtonState()
        }

        addChild(quiz)
        quiz.view.translatesAutoresizingMaskIntoConstraints = false
        quizPageView.addSubview(quiz.view)
        NSLayoutConstraint.activate([
            quiz.view.topAnchor.constraint(equalTo: quizPageView.topAnchor),
            quiz.view.leadingAnchor.constraint(equalTo: quizPageView.leadingAnchor),
            quiz.view.trailingAnchor.constraint(equalTo: quizPageView.trailingAnchor),
            quiz.view.bottomAnchor.constraint(equalTo: quizPageView.bottomAnchor),
        ])
        quiz.didMove(toParent: self)
        quizViewController = quiz
    }

    private func reloadQuizContent() {
        resetQuizPlayButtonReveal()
        resetQuizContinueButtonReveal()
        let item = currentScenarioItem
        let questions = DialogueQuizSampler.questions(
            from: item?.quiz ?? [],
            sample: sessionMode == .retakeQuiz
        )
        let evidence = item.map(Self.quizEvidenceContext(for:))
        quizViewController.configure(questions: questions, evidenceContext: evidence)
        updateQuizNextButtonState()
        applyQuizNextButtonProgress(pageTransitionProgress)
        applyQuizScrollInsetsForPageTransition()
    }

    private static func quizEvidenceContext(for item: ScenarioItem) -> DialogueQuizEvidenceContext {
        var speakerSides: [String: DialogueSpeakerSide] = [:]
        var nextSide: DialogueSpeakerSide = .leading
        let spokenLines = (item.example.scenario?.lines ?? [])
            .filter(\.isSpokenLine)
            .enumerated()
            .map { index, line in
                let speakerSide = DialogueBubbleLayout.assignSpeakerSide(
                    for: line.speaker,
                    sides: &speakerSides,
                    nextSide: &nextSide
                )
                return DialogueQuizSourceLine(
                    speaker: line.speaker,
                    japanese: line.japanese,
                    english: line.english,
                    spokenIndex: index,
                    speakerSide: speakerSide
                )
            }
        return DialogueQuizEvidenceContext(
            publishedAudioUrl: item.example.publishedAudioUrl,
            audioKey: item.example.audioKey,
            cacheMetadata: item.example.remoteAudioCacheMetadata,
            spokenLines: spokenLines,
            tokenSync: DialogueTokenSync.validated(
                item.example.tokenSync,
                spokenTexts: spokenLines.map(\.japanese),
                publishedContentHash: item.example.publishedContentHash
            )
        )
    }

    private func configureQuizNextButton() {
        configureQuizTransportButton(
            quizPlayButton,
            glyphView: quizPlayGlyphView,
            symbolName: "play.fill",
            accessibilityLabel: "Play dialogue line"
        )
        quizPlayButton.addAction(UIAction { [weak self] _ in
            self?.quizViewController.toggleCurrentEvidencePlayback()
        }, for: .primaryActionTriggered)

        configureQuizTransportButton(
            quizNextButton,
            glyphView: quizNextGlyphView,
            symbolName: "arrow.right",
            accessibilityLabel: "Next question"
        )
        quizNextButton.addAction(UIAction { [weak self] _ in
            self?.quizViewController.goToNextQuestion()
        }, for: .primaryActionTriggered)

        configureQuizContinueButton()

        bottomScrollEdgeContainer.addSubview(quizPlayButton)
        bottomScrollEdgeContainer.addSubview(quizNextButton)
        bottomScrollEdgeContainer.addSubview(quizContinueButton)

        NSLayoutConstraint.activate([
            quizPlayButton.leadingAnchor.constraint(
                equalTo: bottomScrollEdgeContainer.leadingAnchor,
                constant: Self.quizCheckButtonHorizontalInset
            ),
            quizPlayButton.topAnchor.constraint(
                equalTo: bottomScrollEdgeContainer.topAnchor,
                constant: 8
            ),
            quizPlayButton.bottomAnchor.constraint(
                equalTo: bottomScrollEdgeContainer.safeAreaLayoutGuide.bottomAnchor,
                constant: -Self.quizCheckButtonBottomInset
            ),
            quizPlayButton.widthAnchor.constraint(equalToConstant: Self.quizCheckButtonHeight),
            quizPlayButton.heightAnchor.constraint(equalToConstant: Self.quizCheckButtonHeight),

            quizNextButton.topAnchor.constraint(equalTo: quizPlayButton.topAnchor),
            quizNextButton.bottomAnchor.constraint(equalTo: quizPlayButton.bottomAnchor),
            quizNextButton.trailingAnchor.constraint(
                equalTo: bottomScrollEdgeContainer.trailingAnchor,
                constant: -Self.quizCheckButtonHorizontalInset
            ),
            quizNextButton.widthAnchor.constraint(equalToConstant: Self.quizCheckButtonHeight),
            quizNextButton.heightAnchor.constraint(equalToConstant: Self.quizCheckButtonHeight),

            quizContinueButton.topAnchor.constraint(equalTo: quizPlayButton.topAnchor),
            quizContinueButton.bottomAnchor.constraint(equalTo: quizPlayButton.bottomAnchor),
            quizContinueButton.trailingAnchor.constraint(
                equalTo: bottomScrollEdgeContainer.trailingAnchor,
                constant: -Self.quizCheckButtonHorizontalInset
            ),
            quizContinueButton.leadingAnchor.constraint(
                greaterThanOrEqualTo: quizPlayButton.trailingAnchor,
                constant: 12
            ),
        ])
    }

    private func configureQuizContinueButton() {
        var config = UIButton.Configuration.glass()
        config.cornerStyle = .capsule
        config.title = "Continue"
        config.baseForegroundColor = .systemYellow
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
            outgoing.foregroundColor = .systemYellow
            return outgoing
        }
        quizContinueButton.configuration = config
        quizContinueButton.translatesAutoresizingMaskIntoConstraints = false
        quizContinueButton.setContentHuggingPriority(.required, for: .horizontal)
        quizContinueButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        quizContinueButton.accessibilityLabel = "Continue"
        quizContinueButton.alpha = 0
        quizContinueButton.addAction(UIAction { [weak self] _ in
            self?.presentQuizCompletion()
        }, for: .primaryActionTriggered)
    }

    private func configureQuizTransportButton(
        _ button: UIButton,
        glyphView: UIImageView,
        symbolName: String,
        accessibilityLabel: String
    ) {
        var config = UIButton.Configuration.glass()
        config.cornerStyle = .capsule
        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = accessibilityLabel

        let symbolConfig = UIImage.SymbolConfiguration(
            pointSize: Self.quizNextGlyphPointSize,
            weight: .semibold
        )
        glyphView.image = UIImage(systemName: symbolName, withConfiguration: symbolConfig)?
            .withRenderingMode(.alwaysTemplate)
        glyphView.tintColor = .systemYellow
        glyphView.preferredSymbolConfiguration = symbolConfig
        glyphView.contentMode = .scaleAspectFit
        glyphView.isUserInteractionEnabled = false
        glyphView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(glyphView)

        let glyphDimension = Self.quizNextGlyphPointSize + 4
        NSLayoutConstraint.activate([
            glyphView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            glyphView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            glyphView.widthAnchor.constraint(equalToConstant: glyphDimension),
            glyphView.heightAnchor.constraint(equalToConstant: glyphDimension),
        ])
    }

    private func shouldRecordCompletionOnPlaybackFinish(for item: ScenarioItem) -> Bool {
        sessionMode == .attempt && item.quiz.isEmpty
    }

    private func applySessionUnlocksForCurrentMode() {
        committedTally = nil
        switch sessionMode {
        case .attempt:
            hasFinishedListeningThisVisit = false
            hasFinishedQuizThisVisit = false
        case .viewLesson:
            hasFinishedListeningThisVisit = true
            hasFinishedQuizThisVisit = true
        case .retakeQuiz:
            hasFinishedListeningThisVisit = true
            hasFinishedQuizThisVisit = false
        }
    }

    private func resolvedSessionMode(
        preferred: DialogueLessonSessionMode,
        scenarioID: String
    ) -> DialogueLessonSessionMode {
        let completed = DialogueProgressStore.shared.isCompleted(scenarioID: scenarioID)
        let hasQuiz = scenarioItems.first(where: { $0.id == scenarioID })?.quiz.isEmpty == false
        switch preferred {
        case .viewLesson:
            return completed ? .viewLesson : .attempt
        case .retakeQuiz:
            if completed && hasQuiz { return .retakeQuiz }
            return completed ? .viewLesson : .attempt
        case .attempt:
            return .attempt
        }
    }

    private func awardsImmersedListenThisVisit() -> Bool {
        sessionMode != .retakeQuiz || dialogueViewController.didStartPlaybackThisAttempt
    }

    private func makeCurrentTally() -> DialogueCompletionTally {
        DialogueCompletionTally(
            score: quizViewController.currentScore,
            englishPeekedCount: dialogueViewController.englishPeekedCount,
            awardsImmersedListen: awardsImmersedListenThisVisit()
        )
    }

    private func persistCommittedTallyIfNeeded() {
        guard committedTally == nil, let item = currentScenarioItem else { return }
        let tally = makeCurrentTally()
        committedTally = tally
        let isRetake = sessionMode == .retakeQuiz
        DialogueProgressStore.shared.markCompleted(
            scenarioID: item.id,
            starCount: tally.starCount,
            points: tally.total,
            countsTowardDaily: !isRetake
        )
        if !isRetake {
            GrammarMasteryStore.shared.recordEncounter(
                grammarIDs: item.grammarPointIDs,
                scenarioID: item.id
            )
        }
    }

    private func handleDialoguePlaybackFinished() {
        guard !hasFinishedListeningThisVisit else { return }
        hasFinishedListeningThisVisit = true
        updateUnlockedPagesVisibility()
        view.layoutIfNeeded()
        refreshHandoffCoordinatorInnerScrollViews()
        applyPageTransitionProgress(currentPageTransitionProgress())
    }

    private func handleQuizFinished() {
        hasFinishedQuizThisVisit = true
        updateUnlockedPagesVisibility()
        view.layoutIfNeeded()
        refreshHandoffCoordinatorInnerScrollViews()
        applyPageTransitionProgress(currentPageTransitionProgress())
    }

    private func startRetake() {
        guard authoredHasQuiz else { return }
        sessionMode = .retakeQuiz
        applySessionUnlocksForCurrentMode()
        dialogueViewController.resetAttemptListeningState()
        reloadQuizContent()
        updateUnlockedPagesVisibility()
        refreshHandoffCoordinatorInnerScrollViews()
        navigationItem.rightBarButtonItem?.menu = makeDialogueMenu()
        view.layoutIfNeeded()
        handoffCoordinator?.snapToPage(1)
    }

    private func enterViewLesson(snapToHighlights: Bool) {
        sessionMode = .viewLesson
        hasFinishedListeningThisVisit = true
        hasFinishedQuizThisVisit = true
        dialogueViewController?.recordsCompletionOnPlaybackFinish = false
        updateUnlockedPagesVisibility()
        refreshHandoffCoordinatorInnerScrollViews()
        navigationItem.rightBarButtonItem?.menu = makeDialogueMenu()
        view.layoutIfNeeded()
        if snapToHighlights, isHighlightsUnlocked {
            handoffCoordinator?.snapToPage(highlightsPageIndex)
        } else {
            clampOuterScrollToValidPageIfNeeded()
        }
    }

    private func presentQuizCompletion() {
        guard presentedViewController == nil,
              let item = currentScenarioItem,
              quizViewController.hasFinishedAllQuestions
        else { return }

        quizViewController.stopEvidencePlayback()
        persistCommittedTallyIfNeeded()
        let tally = committedTally ?? makeCurrentTally()
        let sheet = DialogueQuizCompletionViewController(
            tally: tally,
            highlights: item.highlights
        )
        sheet.onExploreHighlights = { [weak self] in
            self?.dismiss(animated: true) {
                self?.enterViewLesson(snapToHighlights: true)
            }
        }
        sheet.onSheetDismissed = { [weak self] in
            guard let self, self.sessionMode != .viewLesson else { return }
            self.enterViewLesson(snapToHighlights: false)
        }

        sheet.modalPresentationStyle = .pageSheet
        if let presentation = sheet.sheetPresentationController {
            presentation.prefersGrabberVisible = true
            presentation.prefersEdgeAttachedInCompactHeight = true
            presentation.widthFollowsPreferredContentSizeWhenEdgeAttached = true
            presentation.prefersScrollingExpandsWhenScrolledToEdge = false
            presentation.delegate = self
        }
        present(sheet, animated: true)
    }

    private func updateQuizNextButtonState() {
        applyQuizNextButtonProgress(pageTransitionProgress)
    }

    private func updateUnlockedPagesVisibility() {
        quizPageView.isHidden = !hasQuizPage
        highlightsPageView.isHidden = !isHighlightsUnlocked
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
        highlightsPageView.isHidden = true

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
            WordDictionaryDetailSheetPresenter.push(
                surface: word,
                sentence: self.contextSentence(containing: word),
                from: self
            )
        }
        highlightsContentView.onSelectGrammar = { [weak self] grammarPointID in
            guard let self else { return }
            GrammarReferencePresenter.open(grammarPointID: grammarPointID, from: self)
        }
        highlightsScrollView.addSubview(highlightsContentView)

        highlightsScrollView.topEdgeEffect.style = .soft
        highlightsScrollView.topEdgeEffect.isHidden = false
        highlightsScrollView.bottomEdgeEffect.style = .soft
        highlightsScrollView.bottomEdgeEffect.isHidden = false

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

    /// Prefer a dialogue line that contains the vocabulary surface so the dictionary
    /// sheet can request a contextual (Gemini / on-device) gloss — especially for
    /// compounds that have no single JMdict entry (e.g. いいところ).
    private func contextSentence(containing vocabulary: String) -> String? {
        let word = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, let item = currentScenarioItem else { return nil }

        if let line = item.example.scenario?.lines.first(where: {
            $0.japanese.contains(word)
        }) {
            return line.japanese
        }
        if item.example.japanese.contains(word) {
            return item.example.japanese
        }
        return nil
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

        // Same edge-to-edge contentInset pattern as dialogue, but with the
        // secondary-page extra used by highlights so content clears the top chevron.
        quizViewController.applyNestedPagingTopContentInset(
            quizTopContentInset(for: pageTransitionProgress)
        )
        quizViewController.applyNestedPagingBottomContentInset(
            quizBottomContentInset(for: pageTransitionProgress)
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
        return base + Self.quizCheckButtonHeight
    }

    /// Fades the quiz next button in on the quiz page, matching Play's slot.
    private func quizNextButtonVisibility(for outerPageOffset: CGFloat) -> CGFloat {
        guard hasQuizPage else { return 0 }
        if outerPageOffset <= 1 {
            return min(max(outerPageOffset, 0), 1)
        }
        return 1 - min(max(outerPageOffset - 1, 0), 1)
    }

    private func applyQuizNextButtonProgress(_ outerPageOffset: CGFloat) {
        let pageAlpha = quizNextButtonVisibility(for: outerPageOffset)

        let canPlay = quizViewController?.canPlayCurrentEvidence == true
        applyQuizPlayButtonVisibility(canPlay: canPlay, pageAlpha: pageAlpha)
        updateQuizPlayGlyph(isPlaying: quizViewController?.isPlayingCurrentEvidence == true)

        let showContinue = quizViewController?.hasFinishedAllQuestions == true
            && quizViewController?.hasNextQuestion == false
        applyQuizContinueButtonVisibility(showContinue: showContinue, pageAlpha: pageAlpha)

        let hasNext = quizViewController?.hasNextQuestion == true
        let canAdvance = quizViewController?.canAdvanceToNextQuestion == true
        let nextAlpha = showContinue ? 0 : (hasNext ? pageAlpha * (canAdvance ? 1 : 0.38) : 0)
        quizNextButton.alpha = nextAlpha
        quizNextButton.isEnabled = canAdvance && !showContinue
        quizNextButton.isUserInteractionEnabled = canAdvance && !showContinue && pageAlpha > 0.55
    }

    private func applyQuizContinueButtonVisibility(showContinue: Bool, pageAlpha: CGFloat) {
        quizContinueButton.isEnabled = showContinue
        quizContinueButton.isUserInteractionEnabled = showContinue && pageAlpha > 0.55

        if showContinue {
            if quizContinueButtonRevealed {
                if !isAnimatingQuizContinueButton {
                    quizContinueButton.alpha = pageAlpha
                    quizContinueButton.transform = .identity
                }
                return
            }
            quizContinueButtonRevealed = true
            animateQuizContinueButtonIn(pageAlpha: pageAlpha)
            return
        }

        resetQuizContinueButtonReveal()
    }

    private func animateQuizContinueButtonIn(pageAlpha: CGFloat) {
        quizContinueButton.layer.removeAllAnimations()
        quizContinueButton.transform = CGAffineTransform(translationX: 0, y: 10)
            .scaledBy(x: 0.78, y: 0.78)
        quizContinueButton.alpha = 0
        isAnimatingQuizContinueButton = true
        UIView.animate(
            withDuration: 0.32,
            delay: 0.04,
            usingSpringWithDamping: 0.78,
            initialSpringVelocity: 0.7,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.quizContinueButton.transform = .identity
            self.quizContinueButton.alpha = pageAlpha
        } completion: { [weak self] _ in
            guard let self else { return }
            self.isAnimatingQuizContinueButton = false
            if self.quizContinueButtonRevealed {
                self.quizContinueButton.alpha = self.quizNextButtonVisibility(
                    for: self.pageTransitionProgress
                )
            }
        }
    }

    private func resetQuizContinueButtonReveal() {
        quizContinueButtonRevealed = false
        isAnimatingQuizContinueButton = false
        quizContinueButton.layer.removeAllAnimations()
        quizContinueButton.transform = .identity
        quizContinueButton.alpha = 0
        quizContinueButton.isEnabled = false
        quizContinueButton.isUserInteractionEnabled = false
    }

    private func applyQuizPlayButtonVisibility(canPlay: Bool, pageAlpha: CGFloat) {
        quizPlayButton.isEnabled = canPlay
        quizPlayButton.isUserInteractionEnabled = canPlay && pageAlpha > 0.55

        if canPlay {
            if quizPlayButtonRevealed {
                if !isAnimatingQuizPlayButton {
                    quizPlayButton.alpha = pageAlpha
                    quizPlayButton.transform = .identity
                }
                return
            }
            quizPlayButtonRevealed = true
            animateQuizPlayButtonIn(pageAlpha: pageAlpha)
            return
        }

        resetQuizPlayButtonReveal()
    }

    private func animateQuizPlayButtonIn(pageAlpha: CGFloat) {
        quizPlayButton.layer.removeAllAnimations()
        quizPlayButton.transform = CGAffineTransform(translationX: 0, y: 10)
            .scaledBy(x: 0.78, y: 0.78)
        quizPlayButton.alpha = 0
        isAnimatingQuizPlayButton = true
        UIView.animate(
            withDuration: 0.32,
            delay: 0.04,
            usingSpringWithDamping: 0.78,
            initialSpringVelocity: 0.7,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.quizPlayButton.transform = .identity
            self.quizPlayButton.alpha = pageAlpha
        } completion: { [weak self] _ in
            guard let self else { return }
            self.isAnimatingQuizPlayButton = false
            if self.quizPlayButtonRevealed {
                self.quizPlayButton.alpha = self.quizNextButtonVisibility(
                    for: self.pageTransitionProgress
                )
            }
        }
    }

    private func resetQuizPlayButtonReveal() {
        quizPlayButtonRevealed = false
        isAnimatingQuizPlayButton = false
        quizPlayButton.layer.removeAllAnimations()
        quizPlayButton.transform = .identity
        quizPlayButton.alpha = 0
        quizPlayButton.isEnabled = false
        quizPlayButton.isUserInteractionEnabled = false
    }

    private func updateQuizPlayGlyph(isPlaying: Bool) {
        let symbolName = isPlaying ? "pause.fill" : "play.fill"
        let symbolConfig = UIImage.SymbolConfiguration(
            pointSize: Self.quizNextGlyphPointSize,
            weight: .semibold
        )
        let image = UIImage(systemName: symbolName, withConfiguration: symbolConfig)?
            .withRenderingMode(.alwaysTemplate)
        quizPlayGlyphView.preferredSymbolConfiguration = symbolConfig
        if let image {
            quizPlayGlyphView.setSymbolImage(image, contentTransition: .replace)
        } else {
            quizPlayGlyphView.image = image
        }
        quizPlayButton.accessibilityLabel = isPlaying ? "Pause dialogue line" : "Play dialogue line"
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
        updateBottomScrollEdgeHostVisibility()

        applyQuizScrollInsetsForPageTransition()
        applyHighlightsScrollInsetsForPageTransition()
        applyQuizNextButtonProgress(progress)
        dialogueViewController.applyNestedPagingTransportProgress(activePageIndex == 0 ? 0 : 1)

        let settledOnQuiz = hasQuizPage && activePageIndex == 1
        if settledOnQuiz, !didSettleQuizScrollAtTop {
            quizViewController.settleHandoffScrollAtTopIfNeeded()
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

        syncSeamChevronScrollEdgeInteraction(
            button: button,
            lowerPageIndex: lowerPageIndex,
            pointsUp: shouldPointUp,
            isVisible: visibility > 0.01
        )

        button.accessibilityLabel = shouldPointUp
            ? "Return to previous section"
            : "Show next section"
    }

    private func syncSeamChevronScrollEdgeInteraction(
        button: UIButton,
        lowerPageIndex: Int,
        pointsUp: Bool,
        isVisible: Bool
    ) {
        let interaction = lowerPageIndex == 0
            ? firstSeamScrollEdgeInteraction
            : secondSeamScrollEdgeInteraction
        if !button.interactions.contains(where: { $0 === interaction }) {
            button.addInteraction(interaction)
        }
        interaction.edge = pointsUp ? .top : .bottom
        // Only drive the edge effect while the chevron overlays quiz / highlights
        // content; dialogue keeps the transport bar as its bottom host.
        if isVisible, activePageIndex > 0 {
            interaction.scrollView = activeInnerScrollView
        } else {
            interaction.scrollView = nil
        }
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
            // Quiz keeps delaysContentTouches so scrolling over answers is easy;
            // dialogue / highlights prefer immediate control response.
            if !quizViewController.ownsScrollView(scrollView) {
                scrollView.delaysContentTouches = false
            }
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
        let scrollView = activeInnerScrollView
        topScrollEdgeInteraction.scrollView = scrollView
        // Dialogue page: transport bar owns the bottom edge (glass controls inside).
        // Quiz / highlights: our bottomScrollEdgeContainer owns it — same call:
        // bottomScrollEdgeInteraction.scrollView = scrollView
        if activePageIndex == 0 {
            bottomScrollEdgeInteraction.scrollView = nil
            bottomScrollEdgeContainer.isHidden = true
        } else {
            bottomScrollEdgeInteraction.scrollView = scrollView
            bottomScrollEdgeContainer.isHidden = false
        }
    }

    private func updateBottomScrollEdgeHostVisibility() {
        let onSecondaryPage = activePageIndex > 0
        bottomScrollEdgeContainer.isHidden = !onSecondaryPage
        if onSecondaryPage {
            bottomScrollEdgeInteraction.scrollView = activeInnerScrollView
        }
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
        // Edge hosts above the pager (same stacking as the reparented transport bar).
        view.bringSubviewToFront(topScrollEdgeContainer)
        view.bringSubviewToFront(bottomScrollEdgeContainer)
        if let transportBar = dialogueViewController?.nestedPagingTransportBarView {
            view.bringSubviewToFront(transportBar)
        }
        // Chevrons stay above the bottom edge host so they remain tappable while
        // still sitting in the soft-effect zone (same as over the transport bar).
        view.bringSubviewToFront(firstSeamChevron)
        view.bringSubviewToFront(secondSeamChevron)
        loadingCoordinator.bringOverlayToFront()
    }

    private func installHandoffCoordinator() {
        let coordinator = NestedVerticalScrollHandoffCoordinator(
            outerScrollView: outerScrollView,
            innerScrollViews: innerScrollViewsForCurrentScenario(),
            boundaryEpsilon: Self.boundaryEpsilon,
            pageCommitThreshold: Self.pageCommitThreshold,
            velocityThreshold: Self.pageVelocityThreshold,
            pageTransitionResistance: Self.pageTransitionResistance
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

extension DialogueNestedPagingExperimentViewController: UISheetPresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard committedTally != nil, sessionMode != .viewLesson else { return }
        enterViewLesson(snapToHighlights: false)
    }
}
