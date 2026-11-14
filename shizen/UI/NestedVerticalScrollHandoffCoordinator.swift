//
//  NestedVerticalScrollHandoffCoordinator.swift
//  shizen
//
//  Vertical pager with nested inner scroll views (dialogue lesson pages, clip
//  transcript → highlights). Moved out of DialogueNestedPagingExperimentViewController
//  so other screens can share it; behavior is unchanged.
//

import UIKit

// MARK: - NestedVerticalScrollHandoffCoordinator

/// Transfers inner-scroll overflow to an outer pager while the finger is down.
/// Container extremes (first page top, last page bottom) keep native UIKit bounce.
final class NestedVerticalScrollHandoffCoordinator: NSObject, UIScrollViewDelegate {

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
    /// The coordinator is every inner scroll view's delegate; hosts that also need
    /// drag / scroll callbacks (auto-scroll holds, dismissing popovers) set this.
    weak var forwardingDelegate: UIScrollViewDelegate?

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

    func snapToPage(_ page: Int, completion: (() -> Void)? = nil) {
        guard let outerScrollView, outerScrollView.bounds.height > 0 else {
            completion?()
            return
        }
        let pageHeight = outerScrollView.bounds.height
        let clampedPage = min(max(page, 0), outerMaxPageIndex())
        snapOuterToPage(clampedPage, pageHeight: pageHeight, velocity: .zero, completion: completion)
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
        forwardingDelegate?.scrollViewWillBeginDragging?(scrollView)
        guard innerScrollViews.contains(where: { $0 === scrollView }) else { return }
        lastTrackedOffsetY[ObjectIdentifier(scrollView)] = scrollView.contentOffset.y
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        forwardingDelegate?.scrollViewDidScroll?(scrollView)
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
        forwardingDelegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
        guard innerScrollViews.contains(where: { $0 === scrollView }) else { return }
        lastTrackedOffsetY.removeValue(forKey: ObjectIdentifier(scrollView))
        resetOuterDriftIfNeeded()
        if !outerHasMovedOffPage(), !isInnerScrollingLockedForPageTransition {
            setInnerScrollingEnabled(true)
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        forwardingDelegate?.scrollViewDidEndDecelerating?(scrollView)
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
        // Round, don't truncate: a fractional page height (e.g. a pager below a
        // 16:9 player) can make one page of travel 0.9999…, which truncated to 0
        // and blocked paging entirely.
        return max(
            0,
            Int(((outerScrollView.contentSize.height - outerScrollView.bounds.height) / pageHeight).rounded())
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

    private func snapOuterToPage(
        _ page: Int,
        pageHeight: CGFloat,
        velocity: CGPoint,
        completion: (() -> Void)? = nil
    ) {
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
            completion?()
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
