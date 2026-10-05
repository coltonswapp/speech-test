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

    /// Jumps to a page without the snap animation. Used when swapping scenes.
    func settleOnPage(_ page: Int) {
        guard let outerScrollView, outerScrollView.bounds.height > 0 else { return }
        let pageHeight = outerScrollView.bounds.height
        let clampedPage = min(max(page, 0), outerMaxPageIndex())
        outerScrollView.contentOffset.y = CGFloat(clampedPage) * pageHeight
        lastSnappedPage = clampedPage
        setInnerScrollingEnabled(true)
        reportPageTransitionProgress()
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
    /// Clearance below the status bar for the top-rail page chevron (`pageChevronTopCenterY` + half control height).
    private static let highlightsChevronBandPadding: CGFloat = 4
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
    private let nextSceneButton = UIButton(type: .system)
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
    private var isPresentingChevronAppearance = false

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
    /// Last top inset we pinned the vocab scroll to, so arrival can track the chevron.
    private var highlightsPinnedTopBoundary: CGFloat = 0
    private var lastKnownViewSize: CGSize = .zero
    private var hasLoadedLessonContent = false
    private enum QuizPlayButtonPresence {
        case offscreen
        case entering
        case onscreen
        case exiting
    }
    private var quizPlayButtonPresence: QuizPlayButtonPresence = .offscreen
    private var quizContinueButtonRevealed = false
    private var isAnimatingQuizContinueButton = false
    private var isApprovingScene = false
    private var approvedScenarioIDs: Set<String> = []
    /// Set while "Next scene" dismisses the completion sheet, so that dismiss
    /// doesn't also drop the learner into review of the scene they just left.
    private var suppressViewLessonOnSheetDismiss = false
    private var nextSceneButtonEndsLesson = false

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
        nextSceneButton.alpha = 0
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

        configureOuterPager()
        configureDialoguePage()
        configureQuizPage()
        configureDialogueNavigationItems()
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

    private var nextScenarioItem: ScenarioItem? {
        let items = scenarioItems
        guard let index = items.firstIndex(where: { $0.id == selectedScenarioID }),
              items.indices.contains(index + 1) else { return nil }
        return items[index + 1]
    }

    /// Last scene of a lesson collection: the next-scene slot ends the lesson instead.
    private var endsLessonHere: Bool {
        !usesLegacyCatalog && collection != nil && currentScenarioItem != nil && nextScenarioItem == nil
    }

    /// Listening and quiz are done for this visit, or the scene was already completed.
    private var sceneIsReadyForNextScene: Bool {
        if isHighlightsUnlocked { return true }
        guard let id = currentScenarioItem?.id else { return false }
        return DialogueProgressStore.shared.isCompleted(scenarioID: id)
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
        let displayOptions: [(DialogueTranscriptDisplayMode, String, String)] = [
            (.full, "Japanese · swipe for English", "text.bubble"),
            (.japaneseOnly, "Hide English", "eye.slash"),
            (.listeningSpeakers, "Live meters", "waveform"),
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
        let displayMenu = UIMenu(
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
        let experimentsMenu = UIMenu(
            title: "Experiments",
            image: UIImage(systemName: "flask"),
            children: [
                displayMenu,
                tokenSyncAction,
                makeTokenHighlightPreviewAction(),
            ]
        )
        let dictionarySearch = UIAction(
            title: "Dictionary",
            image: UIImage(systemName: "character.book.closed")
        ) { [weak self] _ in
            self?.presentDictionaryLookup()
        }
        var children: [UIMenuElement] = [dictionarySearch, experimentsMenu]
        if let context = contentQASceneContext {
            let approved = approvedScenarioIDs.contains(selectedScenarioID)
            let approve = UIAction(
                title: isApprovingScene ? "Approving scene…" : "Approve scene",
                subtitle: approved ? "Dialogue and quiz looked over" : "Mark this scene looked over",
                image: UIImage(systemName: approved ? "checkmark.circle.fill" : "checkmark.circle"),
                attributes: isApprovingScene ? .disabled : []
            ) { [weak self] _ in
                self?.approveCurrentScene(collectionId: context.collectionId, slug: context.slug)
            }
            let note = UIAction(
                title: "Note",
                subtitle: contentQANoteMenuSubtitle,
                image: UIImage(systemName: "square.and.pencil")
            ) { [weak self] _ in
                self?.presentContentQANote()
            }
            let qaMenu = UIMenu(
                title: "QA",
                image: UIImage(systemName: "checklist"),
                children: [approve, note]
            )
            children.append(qaMenu)
        }
        if let next = nextScenarioItem, sceneIsReadyForNextScene {
            let nextScene = UIAction(
                title: "Next scene",
                subtitle: next.menuTitle,
                image: UIImage(systemName: "arrow.right.circle")
            ) { [weak self] _ in
                self?.advanceToNextScene()
            }
            children.append(nextScene)
        }
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
            title: collection?.title ?? "Dialogue",
            children: children
        )
    }

    private struct ContentQASceneContext {
        let collectionId: String
        let slug: String
        let lessonTitle: String
        let lessonID: String
        let sceneTitle: String
    }

    private struct ContentQAFocus {
        let title: String
        let detailLines: [String]
        var source: ContentCMSClient.QANoteSource = .dialogue
        var quizQuestionNumber: Int?
    }

    private struct ContentQAContext {
        let scene: ContentQASceneContext
        let focus: ContentQAFocus
    }

    private var contentQAContext: ContentQAContext? {
        guard let scene = contentQASceneContext else { return nil }
        return ContentQAContext(scene: scene, focus: makeContentQAFocus())
    }

    private var contentQANoteMenuSubtitle: String {
        contentQAContext?.focus.title ?? "Comment + Studio link for an agent"
    }

    private func contentQASessionModeLabel() -> String {
        switch sessionMode {
        case .attempt: return "Lesson attempt"
        case .viewLesson: return "Study / view lesson"
        case .retakeQuiz: return "Quiz retake"
        }
    }

    private func makeContentQAFocus() -> ContentQAFocus {
        let pageIndex = activePageIndex
        if pageIndex == 0 {
            if let focus = dialogueViewController?.contentQAFocus(
                sessionModeLabel: contentQASessionModeLabel()
            ) {
                return ContentQAFocus(title: focus.title, detailLines: focus.details)
            }
            return ContentQAFocus(
                title: "Dialogue",
                detailLines: ["Session: \(contentQASessionModeLabel())"]
            )
        }
        if hasQuizPage, pageIndex == 1 {
            if let focus = quizViewController?.contentQAFocus() {
                return ContentQAFocus(
                    title: focus.title,
                    detailLines: focus.details,
                    source: .quiz,
                    quizQuestionNumber: focus.questionNumber
                )
            }
            return ContentQAFocus(title: "Quiz", detailLines: [], source: .quiz)
        }
        return highlightsContentQAFocus()
    }

    private func highlightsContentQAFocus() -> ContentQAFocus {
        guard let item = currentScenarioItem else {
            return ContentQAFocus(title: "Lesson highlights", detailLines: [])
        }
        let highlights = item.highlights
        var details: [String] = []
        if highlights.vocabulary.isEmpty {
            details.append("Vocab: none authored")
        } else {
            let preview = highlights.vocabulary.prefix(10).joined(separator: ", ")
            let suffix = highlights.vocabulary.count > 10 ? "…" : ""
            details.append("Vocab (\(highlights.vocabulary.count)): \(preview)\(suffix)")
        }
        if highlights.grammarPatterns.isEmpty {
            details.append("Grammar: none authored")
        } else {
            let labels = highlights.grammarPatternLabels.prefix(6).joined(separator: ", ")
            let suffix = highlights.grammarPatterns.count > 6 ? "…" : ""
            details.append("Grammar (\(highlights.grammarPatterns.count)): \(labels)\(suffix)")
        }
        if highlights.contextNotes.isEmpty {
            details.append("Context notes: none")
        } else {
            details.append("Context notes: \(highlights.contextNotes.count)")
            if let first = highlights.contextNotes.first {
                details.append("First note: \(Self.contentQATrimmedExportText(first))")
            }
        }
        return ContentQAFocus(title: "Lesson highlights", detailLines: details)
    }

    private static func contentQATrimmedExportText(_ text: String, maxLength: Int = 240) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > maxLength else { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        return String(collapsed[..<end]) + "…"
    }

    /// Best-effort Studio identity for any dialogue source (CMS lesson, bundled JSON, harness clip).
    private var contentQASceneContext: ContentQASceneContext? {
        guard let item = currentScenarioItem else { return nil }
        let identity = Self.parseContentQAIdentity(
            scenarioID: item.id,
            collectionID: collection?.id
        )
        let lessonTitle: String
        let lessonID: String
        if let collection {
            lessonTitle = collection.title
            lessonID = collection.id
        } else if usesLegacyCatalog, let entry = DialogueExperimentCatalog.entry(id: item.id) {
            lessonTitle = entry.pointTitle
            lessonID = entry.pointID
        } else {
            lessonTitle = item.pointTitle
            lessonID = identity.collectionId
        }
        return ContentQASceneContext(
            collectionId: identity.collectionId,
            slug: identity.slug,
            lessonTitle: lessonTitle,
            lessonID: lessonID,
            sceneTitle: item.menuTitle
        )
    }

    private static func parseContentQAIdentity(
        scenarioID: String,
        collectionID: String?
    ) -> (collectionId: String, slug: String) {
        if let collectionID {
            let prefix = "\(collectionID)/"
            if scenarioID.hasPrefix(prefix) {
                let slug = String(scenarioID.dropFirst(prefix.count))
                if !slug.isEmpty, !slug.contains("/") {
                    return (collectionID, slug)
                }
            }
            if !scenarioID.contains("/") {
                return (collectionID, scenarioID)
            }
        }
        if let slash = scenarioID.firstIndex(of: "/") {
            let collectionId = String(scenarioID[..<slash])
            let slug = String(scenarioID[scenarioID.index(after: slash)...])
            if !collectionId.isEmpty, !slug.isEmpty, !slug.contains("/") {
                return (collectionId, slug)
            }
        }
        let fallbackCollection = collectionID ?? "dialogue"
        return (fallbackCollection, scenarioID)
    }

    var canPresentContentQANote: Bool {
        contentQAContext != nil
    }

    /// Presents the shared QA note sheet. Scene identity, source, and Studio link
    /// stay on the current lesson page. Pass a focus override when the note is
    /// about a pushed surface such as sentence scrub.
    func presentContentQANote(focusTitle: String? = nil, focusDetailLines: [String]? = nil) {
        guard let context = contentQAContext else { return }
        var sourceId = "\(context.scene.collectionId)/\(context.scene.slug)"
        if let number = context.focus.quizQuestionNumber {
            sourceId += "#q\(number)"
        }
        DialogueContentQANoteViewController.present(
            from: self,
            source: context.focus.source,
            sourceId: sourceId,
            focusTitle: focusTitle ?? context.focus.title,
            focusDetailLines: focusDetailLines ?? context.focus.detailLines,
            lessonTitle: context.scene.lessonTitle,
            lessonID: context.scene.lessonID,
            sceneTitle: context.scene.sceneTitle,
            sceneSlug: context.scene.slug,
            studioLink: ContentCMSClient.studioScenarioEditorLink(
                collectionId: context.scene.collectionId,
                slug: context.scene.slug
            )
        )
    }

    /// Results push inside the sheet's own navigation controller, never onto the scene's stack.
    private func presentDictionaryLookup() {
        if dialogueViewController.dialoguePlaybackPhase == .playing {
            dialogueViewController.dialoguePausePlayback()
        }
        quizViewController?.stopEvidencePlayback()
        let nav = UINavigationController(rootViewController: DictionarySearchViewController())
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    private func approveCurrentScene(collectionId: String, slug: String) {
        guard !isApprovingScene else { return }
        let scenarioID = selectedScenarioID
        isApprovingScene = true
        navigationItem.rightBarButtonItem?.menu = makeDialogueMenu()
        ContentCMSClient.checkOffScene(collectionId: collectionId, slug: slug) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isApprovingScene = false
                switch result {
                case .success(let data):
                    self.approvedScenarioIDs.insert(scenarioID)
                    self.navigationItem.rightBarButtonItem?.menu = self.makeDialogueMenu()
                    let parsed = Self.parseContentQACheckOff(data)
                    self.presentSceneApprovalResult(parsed)
                case .failure(let error):
                    self.navigationItem.rightBarButtonItem?.menu = self.makeDialogueMenu()
                    let alert = UIAlertController(
                        title: "Couldn’t approve scene",
                        message: error.localizedDescription,
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
    }

    private struct ContentQACheckOffSummary {
        var alreadyCheckedOff: Bool
        var dialogueReviewedAt: String?
        var quizReviewedAt: String?
    }

    private static func parseContentQACheckOff(_ data: Data) -> ContentQACheckOffSummary {
        struct Payload: Decodable {
            let alreadyCheckedOff: Bool?
            let review: Review?
            struct Review: Decodable {
                let dialogueReviewedAt: String?
                let quizReviewedAt: String?
            }
        }
        let payload = try? JSONDecoder().decode(Payload.self, from: data)
        return ContentQACheckOffSummary(
            alreadyCheckedOff: payload?.alreadyCheckedOff == true,
            dialogueReviewedAt: payload?.review?.dialogueReviewedAt,
            quizReviewedAt: payload?.review?.quizReviewedAt
        )
    }

    private func presentSceneApprovalResult(_ summary: ContentQACheckOffSummary) {
        let dialogue = Self.displayTimestamp(summary.dialogueReviewedAt)
        let quiz = Self.displayTimestamp(summary.quizReviewedAt)
        let message: String
        if summary.alreadyCheckedOff {
            message = "Already looked over.\nDialogue \(dialogue)\nQuiz \(quiz)"
        } else {
            message = "Marked looked over.\nDialogue \(dialogue)\nQuiz \(quiz)"
        }
        let alert = UIAlertController(
            title: summary.alreadyCheckedOff ? "Scene already approved" : "Scene approved",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private static func displayTimestamp(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "—" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return iso }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func makeTokenHighlightPreviewAction() -> UIAction {
        let style = ExperimentSettings.dialogueTokenSyncHighlightStyle
        return UIAction(
            title: "Token highlight",
            subtitle: style.title,
            image: UIImage(systemName: "paintbrush.pointed")
        ) { [weak self] _ in
            self?.dialogueViewController?.presentTokenHighlightPreview()
        }
    }

    private func toggleTokenSyncHighlight() {
        ExperimentSettings.dialogueShowsTokenSync.toggle()
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
        embedDialogue(for: item)
        navigationItem.rightBarButtonItem?.menu = makeDialogueMenu()
        reloadQuizContent()
        reloadHighlightsContent()
        updateUnlockedPagesVisibility()
        highlightsPinnedTopBoundary = 0
        quizViewController.resetHandoffTopPin()
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
            existing.usesStudyTranscriptContrast = sessionMode == .viewLesson
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
        dialogue.usesStudyTranscriptContrast = sessionMode == .viewLesson
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
        configureNextSceneButton()

        bottomScrollEdgeContainer.addSubview(quizPlayButton)
        bottomScrollEdgeContainer.addSubview(quizNextButton)
        bottomScrollEdgeContainer.addSubview(quizContinueButton)
        bottomScrollEdgeContainer.addSubview(nextSceneButton)

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

            nextSceneButton.topAnchor.constraint(equalTo: quizPlayButton.topAnchor),
            nextSceneButton.bottomAnchor.constraint(equalTo: quizPlayButton.bottomAnchor),
            nextSceneButton.trailingAnchor.constraint(
                equalTo: bottomScrollEdgeContainer.trailingAnchor,
                constant: -Self.quizCheckButtonHorizontalInset
            ),
            nextSceneButton.leadingAnchor.constraint(
                greaterThanOrEqualTo: quizPlayButton.trailingAnchor,
                constant: 12
            ),
        ])
    }

    private func configureNextSceneButton() {
        applyNextSceneButtonConfiguration(endsLesson: false)
        nextSceneButton.translatesAutoresizingMaskIntoConstraints = false
        nextSceneButton.setContentHuggingPriority(.required, for: .horizontal)
        nextSceneButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        nextSceneButton.accessibilityLabel = "Next scene"
        nextSceneButton.alpha = 0
        nextSceneButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if self.endsLessonHere {
                self.presentLessonWrapUp()
            } else {
                self.advanceToNextScene()
            }
        }, for: .primaryActionTriggered)
    }

    private func applyNextSceneButtonConfiguration(endsLesson: Bool) {
        nextSceneButtonEndsLesson = endsLesson
        var config = UIButton.Configuration.glass()
        config.cornerStyle = .capsule
        config.title = endsLesson ? "End lesson" : "Next scene"
        config.image = UIImage(systemName: endsLesson ? "flag.checkered" : "arrow.right")
        config.imagePlacement = .trailing
        config.imagePadding = 6
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
            outgoing.foregroundColor = .label
            return outgoing
        }
        config.imageColorTransformer = UIConfigurationColorTransformer { _ in .label }
        nextSceneButton.configuration = config
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
        navigationItem.rightBarButtonItem?.menu = makeDialogueMenu()
        applyPageTransitionProgress(currentPageTransitionProgress())
    }

    private func handleQuizFinished() {
        hasFinishedQuizThisVisit = true
        updateUnlockedPagesVisibility()
        view.layoutIfNeeded()
        refreshHandoffCoordinatorInnerScrollViews()
        navigationItem.rightBarButtonItem?.menu = makeDialogueMenu()
        applyPageTransitionProgress(currentPageTransitionProgress())
    }

    private func startRetake() {
        guard authoredHasQuiz else { return }
        sessionMode = .retakeQuiz
        applySessionUnlocksForCurrentMode()
        dialogueViewController.resetAttemptListeningState()
        dialogueViewController.usesStudyTranscriptContrast = false
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
        dialogueViewController?.usesStudyTranscriptContrast = true
        updateUnlockedPagesVisibility()
        refreshHandoffCoordinatorInnerScrollViews()
        navigationItem.rightBarButtonItem?.menu = makeDialogueMenu()
        view.layoutIfNeeded()
        highlightsPinnedTopBoundary = 0
        if snapToHighlights, isHighlightsUnlocked {
            handoffCoordinator?.snapToPage(highlightsPageIndex)
        } else {
            clampOuterScrollToValidPageIfNeeded()
        }
        applyPageTransitionProgress(currentPageTransitionProgress())
    }

    private func advanceToNextScene() {
        guard let next = nextScenarioItem else { return }
        let openCompleted = DialogueProgressStore.shared.isCompleted(scenarioID: next.id)
        sessionMode = openCompleted ? .viewLesson : .attempt
        UIView.transition(
            with: outerScrollView,
            duration: 0.28,
            options: [.transitionCrossDissolve, .allowUserInteraction]
        ) { [weak self] in
            guard let self else { return }
            self.handoffCoordinator?.settleOnPage(0)
            self.selectScenario(id: next.id)
        }
        dialogueViewController.applyNestedPagingTransportProgress(0, animated: false)
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
        sheet.nextSceneTitle = nextScenarioItem?.menuTitle
        if sessionMode == .attempt, let feedback = lessonFeedbackContext(item: item, tally: tally),
           LessonFeedbackPrompt.shouldOffer(feedback) {
            sheet.feedbackContext = feedback
        }
        sheet.onExploreHighlights = { [weak self] in
            self?.dismiss(animated: true) {
                self?.enterViewLesson(snapToHighlights: true)
            }
        }
        sheet.onNextScene = nextScenarioItem == nil ? nil : { [weak self] in
            guard let self else { return }
            self.suppressViewLessonOnSheetDismiss = true
            self.dismiss(animated: true) {
                self.advanceToNextScene()
                self.suppressViewLessonOnSheetDismiss = false
            }
        }
        if endsLessonHere {
            sheet.onEndLesson = { [weak self] in
                self?.dismiss(animated: true) {
                    self?.presentLessonWrapUp()
                }
            }
        }
        sheet.onSheetDismissed = { [weak self] in
            guard let self, !self.suppressViewLessonOnSheetDismiss, self.sessionMode != .viewLesson else { return }
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

    private func presentLessonWrapUp() {
        guard presentedViewController == nil, let collection else { return }
        DialogueLessonWrapUpPresenter.present(from: self, collection: collection) { [weak self] in
            self?.dismiss(animated: true) {
                self?.returnToLessonList()
            }
        }
    }

    /// Pops past this lesson's scene picker when it is on the stack.
    private func returnToLessonList() {
        guard let navigationController else { return }
        let stack = navigationController.viewControllers
        if let pickerIndex = stack.lastIndex(where: { $0 is LessonScenarioPickerViewController }), pickerIndex > 0 {
            navigationController.popToViewController(stack[pickerIndex - 1], animated: true)
        } else {
            navigationController.popViewController(animated: true)
        }
    }

    private func lessonFeedbackContext(item: ScenarioItem, tally: DialogueCompletionTally) -> LessonFeedbackContext? {
        guard let scene = contentQASceneContext else { return nil }
        return LessonFeedbackContext(
            collectionId: scene.collectionId,
            scenarioId: scene.slug,
            publishedVariantId: item.example.publishedVariantId,
            publishedContentHash: item.example.publishedContentHash,
            correctCount: tally.score.correctCount,
            questionCount: tally.score.questionCount,
            starCount: tally.starCount,
            englishPeekedCount: tally.englishPeekedCount
        )
    }

    private func updateQuizNextButtonState() {
        applyQuizNextButtonProgress(pageTransitionProgress)
    }

    private func updateUnlockedPagesVisibility() {
        quizPageView.isHidden = !hasQuizPage
        highlightsPageView.isHidden = !isHighlightsUnlocked
        let offersQuiz = authoredHasQuiz && sessionMode != .viewLesson
        dialogueViewController?.onQuizRequested = offersQuiz
            ? { [weak self] in self?.openQuizFromDialogue() }
            : nil
    }

    private func openQuizFromDialogue() {
        guard hasQuizPage else { return }
        handoffCoordinator?.snapToPage(1)
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
                glossFraming: .word,
                from: self
            )
        }
        highlightsContentView.onSelectGrammar = { [weak self] pattern in
            guard let self else { return }
            let item = self.currentScenarioItem
            let lines = item?.example.scenario?.lines ?? []
            let spokenTexts = lines.filter(\.isSpokenLine).map(\.japanese)
            let catalog: DialogueTeachingPattern? = {
                guard let patternId = pattern.patternId else { return nil }
                return self.collection?.teachingPattern(id: patternId)
            }()
            let hear: GrammarPatternDetailPresenter.HearContext? = {
                guard let item else { return nil }
                let hasAudio =
                    !(item.example.publishedAudioUrl?
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    || !(item.example.audioKey?
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                guard hasAudio, !spokenTexts.isEmpty else { return nil }
                return GrammarPatternDetailPresenter.HearContext(
                    publishedAudioUrl: item.example.publishedAudioUrl,
                    audioKey: item.example.audioKey,
                    cacheMetadata: item.example.remoteAudioCacheMetadata,
                    spokenJapaneseTexts: spokenTexts,
                    tokenSync: DialogueTokenSync.validated(
                        item.example.tokenSync,
                        spokenTexts: spokenTexts,
                        publishedContentHash: item.example.publishedContentHash
                    )
                )
            }()
            GrammarPatternDetailPresenter.push(
                pattern: pattern,
                catalogPattern: catalog,
                exampleLines: lines,
                hearContext: hear,
                request: GeminiGrammarUsage.request(for: pattern, in: lines),
                from: self
            )
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
        let topInset = quizTopContentInset(for: pageTransitionProgress)
        quizViewController.applyNestedPagingTopContentInset(topInset)
        quizViewController.applyNestedPagingBottomContentInset(
            quizBottomContentInset(for: pageTransitionProgress)
        )
        quizViewController.pinHandoffScrollToTopInsetIfResting(topInset)
    }

    private func highlightsSettledTopContentInset() -> CGFloat {
        view.safeAreaInsets.top + highlightsChevronTopInsetExtra()
    }

    private func highlightsChevronTopInsetExtra() -> CGFloat {
        let chevronBottom = pageChevronTopCenterY() + Self.pageNavigationControlHeight / 2
        return chevronBottom - view.safeAreaInsets.top + Self.highlightsChevronBandPadding
    }

    private func quizTopContentInset(for outerPageOffset: CGFloat) -> CGFloat {
        let base = view.safeAreaInsets.top
        let settled = highlightsSettledTopContentInset()
        guard hasQuizPage else { return base }
        // Stay on the progress fraction. Rounding to the quiz page halfway
        // through the transition used to jump the inset ahead of the chevron.
        if outerPageOffset >= 1 { return settled }
        let clamped = min(max(outerPageOffset, 0), 1)
        return base + (settled - base) * clamped
    }

    private func quizBottomContentInset(for outerPageOffset: CGFloat) -> CGFloat {
        let base = appliedBottomContentInset >= 0
            ? appliedBottomContentInset
            : view.safeAreaInsets.bottom + 16
        return base + Self.quizCheckButtonHeight
    }

    /// Fades in on the highlights page, in the same trailing slot as quiz Continue.
    private func applyNextSceneButtonProgress(_ outerPageOffset: CGFloat) {
        let next = nextScenarioItem
        let endsLesson = endsLessonHere
        guard next != nil || endsLesson, sceneIsReadyForNextScene, isHighlightsUnlocked else {
            nextSceneButton.alpha = 0
            nextSceneButton.isEnabled = false
            nextSceneButton.isUserInteractionEnabled = false
            return
        }
        if endsLesson != nextSceneButtonEndsLesson {
            applyNextSceneButtonConfiguration(endsLesson: endsLesson)
        }
        let segmentStart = CGFloat(highlightsPageIndex - 1)
        let pageAlpha = min(max(outerPageOffset - segmentStart, 0), 1)
        nextSceneButton.alpha = pageAlpha
        nextSceneButton.isEnabled = pageAlpha > 0.55
        nextSceneButton.isUserInteractionEnabled = pageAlpha > 0.55
        if let next {
            nextSceneButton.accessibilityLabel = "Next scene, \(next.menuTitle)"
        } else {
            nextSceneButton.accessibilityLabel = "End lesson"
        }
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

    /// Drops the proof button below the screen, past the home indicator.
    private var quizPlayButtonOffscreenTransform: CGAffineTransform {
        let travel = Self.quizCheckButtonHeight
            + Self.quizCheckButtonBottomInset
            + view.safeAreaInsets.bottom
            + 16
        return CGAffineTransform(translationX: 0, y: travel)
    }

    private func applyQuizPlayButtonVisibility(canPlay: Bool, pageAlpha: CGFloat) {
        let interactive = canPlay && pageAlpha > 0.55
        quizPlayButton.isEnabled = canPlay
        quizPlayButton.isUserInteractionEnabled = interactive

        if canPlay {
            switch quizPlayButtonPresence {
            case .onscreen:
                quizPlayButton.alpha = pageAlpha
                quizPlayButton.transform = .identity
            case .entering:
                break
            case .offscreen, .exiting:
                animateQuizPlayButtonIn(pageAlpha: pageAlpha)
            }
            return
        }

        switch quizPlayButtonPresence {
        case .offscreen:
            quizPlayButton.alpha = 0
            quizPlayButton.transform = quizPlayButtonOffscreenTransform
            quizPlayButton.isEnabled = false
            quizPlayButton.isUserInteractionEnabled = false
        case .exiting:
            break
        case .onscreen, .entering:
            animateQuizPlayButtonOut()
        }
    }

    private func animateQuizPlayButtonIn(pageAlpha: CGFloat) {
        let startOffscreen = quizPlayButtonPresence == .offscreen
        quizPlayButton.layer.removeAllAnimations()
        if startOffscreen {
            quizPlayButton.transform = quizPlayButtonOffscreenTransform
            quizPlayButton.alpha = 0
        }
        quizPlayButtonPresence = .entering
        UIView.animate(
            withDuration: 0.46,
            delay: 0.02,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0.35,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.quizPlayButton.transform = .identity
            self.quizPlayButton.alpha = pageAlpha
        } completion: { [weak self] _ in
            guard let self, self.quizPlayButtonPresence == .entering else { return }
            self.quizPlayButtonPresence = .onscreen
            self.quizPlayButton.transform = .identity
            self.quizPlayButton.alpha = self.quizNextButtonVisibility(
                for: self.pageTransitionProgress
            )
        }
    }

    private func animateQuizPlayButtonOut() {
        quizPlayButtonPresence = .exiting
        quizPlayButton.isEnabled = false
        quizPlayButton.isUserInteractionEnabled = false
        quizPlayButton.layer.removeAllAnimations()
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.quizPlayButton.transform = self.quizPlayButtonOffscreenTransform
            self.quizPlayButton.alpha = 0
        } completion: { [weak self] _ in
            guard let self, self.quizPlayButtonPresence == .exiting else { return }
            self.quizPlayButtonPresence = .offscreen
            self.quizPlayButton.transform = self.quizPlayButtonOffscreenTransform
            self.quizPlayButton.alpha = 0
        }
    }

    private func resetQuizPlayButtonReveal() {
        quizPlayButtonPresence = .offscreen
        quizPlayButton.layer.removeAllAnimations()
        quizPlayButton.transform = quizPlayButtonOffscreenTransform
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
        var bottomInset = appliedBottomContentInset >= 0
            ? appliedBottomContentInset
            : view.safeAreaInsets.bottom + 16
        if nextScenarioItem != nil || endsLessonHere {
            bottomInset += Self.quizCheckButtonHeight
        }

        highlightsScrollView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        highlightsScrollView.verticalScrollIndicatorInsets = UIEdgeInsets(
            top: topInset,
            left: 0,
            bottom: bottomInset,
            right: 0
        )
        pinHighlightsScrollToTopInsetIfResting(topInset)
    }

    /// Keeps vocab content just under the traveling chevron. Only while the
    /// scroll view is still at the top — a learner who has scrolled in is left alone.
    private func pinHighlightsScrollToTopInsetIfResting(_ topInset: CGFloat) {
        let scrollView = highlightsScrollView
        guard !scrollView.isTracking, !scrollView.isDecelerating else { return }
        let topBoundary = -topInset
        let offset = scrollView.contentOffset.y
        guard highlightsScrollOffsetIsPinnedToTop(
            offset: offset,
            topBoundary: topBoundary,
            safeAreaTopInset: view.safeAreaInsets.top
        ) else { return }
        highlightsPinnedTopBoundary = topBoundary
        guard abs(offset - topBoundary) > 0.5 else { return }
        scrollView.contentOffset.y = topBoundary
    }

    /// True when the learner has not scrolled into the list — includes the
    /// safe-area-only top while the chevron band grows during outer paging.
    private func highlightsScrollOffsetIsPinnedToTop(
        offset: CGFloat,
        topBoundary: CGFloat,
        safeAreaTopInset: CGFloat
    ) -> Bool {
        if abs(offset) <= 1 { return true }
        if abs(offset - highlightsPinnedTopBoundary) < 2 { return true }
        let safeAreaOnlyTop = -safeAreaTopInset
        if offset >= topBoundary - 0.5, offset <= safeAreaOnlyTop + 1 {
            return true
        }
        return false
    }

    private func highlightsTopContentInset(for outerPageOffset: CGFloat) -> CGFloat {
        let base = view.safeAreaInsets.top
        let settled = highlightsSettledTopContentInset()
        let segmentStart = CGFloat(max(highlightsPageIndex - 1, 0))
        let clamped = min(max(outerPageOffset - segmentStart, 0), 1)
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
        applyNextSceneButtonProgress(progress)
        dialogueViewController.applyNestedPagingTransportProgress(activePageIndex == 0 ? 0 : 1)

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
        if isPresentingChevronAppearance { return }
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

        let nothingVisible = firstSeamChevron.alpha < 0.05 && secondSeamChevron.alpha < 0.05
        if isChevronFollowingScroll || nothingVisible {
            chevronSpringAnimator?.stopAnimation(true)
            chevronSpringAnimator = nil
            if nothingVisible, !isChevronFollowingScroll {
                // First appearance (quiz just unlocked). The resting Y is far from
                // the constraint's initial value, so a spring travels the screen.
                isPresentingChevronAppearance = true
                defer { isPresentingChevronAppearance = false }
                var firstTarget: CGFloat = 0
                var secondTarget: CGFloat = 0
                UIView.performWithoutAnimation {
                    apply()
                    firstTarget = self.firstSeamChevron.alpha
                    secondTarget = self.secondSeamChevron.alpha
                    self.firstSeamChevron.alpha = 0
                    self.secondSeamChevron.alpha = 0
                }
                UIView.animate(
                    withDuration: 0.22,
                    delay: 0,
                    options: [.curveEaseOut, .allowUserInteraction]
                ) {
                    self.firstSeamChevron.alpha = firstTarget
                    self.secondSeamChevron.alpha = secondTarget
                }
            } else {
                apply()
            }
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
        guard committedTally != nil, sessionMode != .viewLesson, !suppressViewLessonOnSheetDismiss else { return }
        enterViewLesson(snapToHighlights: false)
    }
}

// MARK: - Content QA note sheet

/// Routing hints Shohei's agents read from the note text.
private enum ContentQANoteTag: String, CaseIterable {
    case content
    case bug
    case localPrompt = "local-prompt"
    case remoteAgent = "remote-agent"
    case ux
    case quiz
    case fyi
    case question

    var hashtag: String { "#\(rawValue)" }
}

final class DialogueContentQANoteViewController: UIViewController, UITextViewDelegate {

    private let source: ContentCMSClient.QANoteSource
    private let sourceId: String
    private let focusTitle: String
    private let focusDetailLines: [String]
    private let lessonTitle: String
    private let lessonID: String
    private let sceneTitle: String?
    private let sceneSlug: String?
    private let studioLink: String

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let noteTextView = UITextView()
    private let sendButton = PrimaryButton(type: .system)
    private let contextDisclosureButton = UIButton(type: .system)
    private let contextChevron = UIImageView()
    private let contextBodyLabel = UILabel()
    private var tagButtons: [(tag: ContentQANoteTag, button: GlassTagControl)] = []
    private var keyboardObservers: [NSObjectProtocol] = []
    private var isSending = false
    private var contextExpanded = false

    init(
        source: ContentCMSClient.QANoteSource,
        sourceId: String,
        focusTitle: String,
        focusDetailLines: [String],
        lessonTitle: String,
        lessonID: String,
        sceneTitle: String? = nil,
        sceneSlug: String? = nil,
        studioLink: String
    ) {
        self.source = source
        self.sourceId = sourceId
        self.focusTitle = focusTitle
        self.focusDetailLines = focusDetailLines
        self.lessonTitle = lessonTitle
        self.lessonID = lessonID
        self.sceneTitle = sceneTitle
        self.sceneSlug = sceneSlug
        self.studioLink = studioLink
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.pageBackground
        navigationItem.title = focusTitle
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )
        let copyItem = UIBarButtonItem(
            image: UIImage(systemName: "doc.on.doc"),
            style: .plain,
            target: self,
            action: #selector(copyTapped)
        )
        copyItem.accessibilityLabel = "Copy for agent"
        navigationItem.leftBarButtonItem = copyItem

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        stack.addArrangedSubview(makeMetaBlock())
        stack.addArrangedSubview(makeNoteSection())

        sendButton.primaryStyle = .yellow
        sendButton.setTitle("Send to agent", for: .normal)
        sendButton.accessibilityLabel = "Send to agent"
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        view.addSubview(sendButton)

        NSLayoutConstraint.activate([
            sendButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PrimaryButton.horizontalInset),
            sendButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PrimaryButton.horizontalInset),
            sendButton.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12),
            sendButton.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),

            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: sendButton.topAnchor, constant: -16),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
            stack.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor, constant: -32),
        ])

        installKeyboardScrollObservers()
    }

    deinit {
        keyboardObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollCaretIntoView(animated: true)
    }

    private func installKeyboardScrollObservers() {
        let center = NotificationCenter.default
        keyboardObservers = [
            center.addObserver(
                forName: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.keyboardWillChangeFrame(notification)
            },
        ]
    }

    private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let curveRaw = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 0
        let options = UIView.AnimationOptions(rawValue: curveRaw << 16)

        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.view.layoutIfNeeded()
            self.scrollCaretIntoView(animated: false)
        }
    }

    /// The text view grows instead of scrolling, so the outer scroll view follows the caret.
    private func scrollCaretIntoView(animated: Bool) {
        guard noteTextView.isFirstResponder, let selection = noteTextView.selectedTextRange else { return }
        view.layoutIfNeeded()
        let caret = noteTextView.caretRect(for: selection.end)
        guard !caret.isNull, !caret.isInfinite else { return }
        let target = noteTextView.convert(caret, to: scrollView)
        scrollView.scrollRectToVisible(target.insetBy(dx: 0, dy: -24), animated: animated)
    }

    func textViewDidChange(_ textView: UITextView) {
        scrollCaretIntoView(animated: false)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        scrollCaretIntoView(animated: false)
    }

    private func makeMetaBlock() -> UIView {
        contextChevron.image = UIImage(systemName: "chevron.right")
        contextChevron.tintColor = .secondaryLabel
        contextChevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            textStyle: .subheadline,
            scale: .small
        )
        contextChevron.setContentHuggingPriority(.required, for: .horizontal)
        contextChevron.setContentCompressionResistancePriority(.required, for: .horizontal)

        let title = UILabel()
        title.text = "Context"
        title.font = .preferredFont(forTextStyle: .subheadline)
        title.textColor = .secondaryLabel

        let row = UIStackView(arrangedSubviews: [contextChevron, title])
        row.axis = .horizontal
        row.spacing = 6
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false

        contextDisclosureButton.accessibilityLabel = "Context"
        contextDisclosureButton.accessibilityValue = "Collapsed"
        contextDisclosureButton.addTarget(self, action: #selector(toggleContextExpanded), for: .touchUpInside)
        contextDisclosureButton.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contextDisclosureButton.topAnchor, constant: 4),
            row.bottomAnchor.constraint(equalTo: contextDisclosureButton.bottomAnchor, constant: -4),
            row.leadingAnchor.constraint(equalTo: contextDisclosureButton.leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: contextDisclosureButton.trailingAnchor),
        ])

        contextBodyLabel.numberOfLines = 0
        contextBodyLabel.font = .preferredFont(forTextStyle: .subheadline)
        contextBodyLabel.textColor = .secondaryLabel
        contextBodyLabel.text = contextLines().joined(separator: "\n")
        contextBodyLabel.isHidden = true

        let wrap = UIStackView(arrangedSubviews: [contextDisclosureButton, contextBodyLabel])
        wrap.axis = .vertical
        wrap.spacing = 8
        wrap.alignment = .fill
        return wrap
    }

    @objc private func toggleContextExpanded() {
        contextExpanded.toggle()
        contextChevron.image = UIImage(systemName: contextExpanded ? "chevron.down" : "chevron.right")
        contextDisclosureButton.accessibilityValue = contextExpanded ? "Expanded" : "Collapsed"
        UIView.animate(withDuration: 0.2) {
            self.contextBodyLabel.isHidden = !self.contextExpanded
            self.view.layoutIfNeeded()
        }
    }

    private func makeNoteSection() -> UIView {
        let heading = UILabel()
        heading.text = "Note"
        heading.font = .preferredFont(forTextStyle: .headline)

        noteTextView.font = .preferredFont(forTextStyle: .body)
        noteTextView.layer.cornerRadius = 12
        noteTextView.layer.borderWidth = 1
        noteTextView.layer.borderColor = UIColor.separator.cgColor
        noteTextView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        noteTextView.isScrollEnabled = false
        noteTextView.delegate = self
        noteTextView.translatesAutoresizingMaskIntoConstraints = false
        // Lowest hugging in the sheet: the field absorbs all spare height down to the tags and CTA.
        noteTextView.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        noteTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        let wrap = UIStackView(arrangedSubviews: [heading, noteTextView, makeTagFlow()])
        wrap.axis = .vertical
        wrap.spacing = 8
        wrap.setCustomSpacing(14, after: noteTextView)
        return wrap
    }

    private func makeTagFlow() -> UIView {
        tagButtons = ContentQANoteTag.allCases.map { tag in
            (tag, GlassTagControl(title: tag.hashtag))
        }
        let flow = GlassTagFlowView()
        flow.setTags(tagButtons.map(\.button))
        flow.setContentCompressionResistancePriority(.required, for: .vertical)
        return flow
    }

    private var typedNote: String {
        noteTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedTags: [ContentQANoteTag] {
        tagButtons.filter { $0.button.isSelected }.map(\.tag)
    }

    /// Leading `Tags:` line plus a blank separator, or nothing when no tags are on.
    private func tagLines() -> [String] {
        let tags = selectedTags
        guard !tags.isEmpty else { return [] }
        return ["Tags: " + tags.map(\.hashtag).joined(separator: " "), ""]
    }

    private func contextLines() -> [String] {
        var lines = [
            "Looking at: \(focusTitle)",
        ]
        lines.append(contentsOf: focusDetailLines)
        lines.append("")
        lines.append("Lesson: \(lessonTitle) (\(lessonID))")
        if let sceneTitle, let sceneSlug {
            lines.append("Scene: \(sceneTitle) (\(sceneSlug))")
        }
        lines.append("Studio: \(studioLink)")
        return lines
    }

    static func present(
        from presenter: UIViewController,
        source: ContentCMSClient.QANoteSource,
        sourceId: String,
        focusTitle: String,
        focusDetailLines: [String],
        lessonTitle: String,
        lessonID: String,
        sceneTitle: String? = nil,
        sceneSlug: String? = nil,
        studioLink: String
    ) {
        let note = DialogueContentQANoteViewController(
            source: source,
            sourceId: sourceId,
            focusTitle: focusTitle,
            focusDetailLines: focusDetailLines,
            lessonTitle: lessonTitle,
            lessonID: lessonID,
            sceneTitle: sceneTitle,
            sceneSlug: sceneSlug,
            studioLink: studioLink
        )
        let sheet = UINavigationController(rootViewController: note)
        sheet.modalPresentationStyle = .pageSheet
        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.selectedDetentIdentifier = .large
            presentation.prefersGrabberVisible = true
        }
        presenter.present(sheet, animated: true)
    }

    private func agentPasteboardText() -> String {
        var lines = tagLines() + contextLines()
        lines.append("")
        lines.append("Note:")
        lines.append(typedNote)
        return lines.joined(separator: "\n")
    }

    /// Tags and typed text first, then the same context block the clipboard copy carries.
    private func webhookNoteText() -> String {
        (tagLines() + [typedNote, ""] + contextLines()).joined(separator: "\n")
    }

    @objc private func copyTapped() {
        view.endEditing(true)
        UIPasteboard.general.string = agentPasteboardText()
        showToast(text: "Copied")
    }

    @objc private func sendTapped() {
        guard !isSending else { return }
        guard !typedNote.isEmpty else {
            showToast(text: "Write a note first", sentiment: .negative)
            return
        }
        view.endEditing(true)
        setSending(true)
        let note = ContentCMSClient.QANote(
            source: source,
            sourceId: sourceId,
            title: focusTitle,
            note: webhookNoteText(),
            metadata: .init(url: studioLink, createdAt: Date())
        )
        ContentCMSClient.sendQANote(note) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.setSending(false)
                switch result {
                case .success:
                    self.showToast(text: "Sent to Shohei")
                    self.dismiss(animated: true)
                case .failure(let error):
                    let alert = UIAlertController(
                        title: "Couldn’t send note",
                        message: error.localizedDescription,
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
    }

    private func setSending(_ sending: Bool) {
        isSending = sending
        sendButton.isEnabled = !sending
        sendButton.setTitle(sending ? "Sending…" : "Send to agent", for: .normal)
        isModalInPresentation = sending
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }
}
