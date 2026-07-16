//
//  GameCategoryTabBar.swift
//  shizen
//
//  Horizontally scrolling category tabs synced to a paging content scroll view.
//

import UIKit

protocol GameCategoryTabBarDelegate: AnyObject {
    func tabBar(_ tabBar: GameCategoryTabBar, didSelectTabAt index: Int)
    func tabBar(_ tabBar: GameCategoryTabBar, didScrollToPageProgress progress: CGFloat)
    func tabBarDidEndScrolling(_ tabBar: GameCategoryTabBar)
}

final class GameCategoryTabBar: UIView {

    /// Fixed height from Auto Layout; pair with the host safe-area top inset for scroll underlap.
    static let layoutHeight: CGFloat = 44

    weak var delegate: GameCategoryTabBarDelegate?

    private(set) var selectedIndex: Int = 0
    private(set) var showsInactiveTabs = true
    private var titles: [String] = []
    private var isProgrammaticScroll = false
    private var suspendSelectionSyncFromScroll = false
    private var pageProgressTracking: CGFloat = 0

    private static let pillHeight: CGFloat = 36
    private static let snapAnimationDuration: TimeInterval = 0.22
    private static let snapDecelerationRate = UIScrollView.DecelerationRate(rawValue: 0.92)

    private let scrollEdgeInteraction: UIScrollEdgeElementContainerInteraction = {
        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.edge = .top
        return interaction
    }()

    private let pillGlass: UIVisualEffectView = {
        let glass = LiquidGlassEffectView.makeContainer()
        glass.isUserInteractionEnabled = false
        LiquidGlassEffectView.applyCapsuleStyle(to: glass, cornerRadius: pillHeight / 2)
        return glass
    }()

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 8
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.isScrollEnabled = true
        cv.decelerationRate = Self.snapDecelerationRate
        cv.delegate = self
        cv.dataSource = self
        cv.register(TabCell.self, forCellWithReuseIdentifier: TabCell.reuseID)
        return cv
    }()

    init(titles: [String], initialSelectedIndex: Int = 0) {
        self.titles = titles
        let clampedInitial = max(0, min(initialSelectedIndex, max(titles.count - 1, 0)))
        self.selectedIndex = clampedInitial
        self.pageProgressTracking = CGFloat(clampedInitial)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(pillGlass)
        addSubview(collectionView)
        addInteraction(scrollEdgeInteraction)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(equalToConstant: Self.layoutHeight),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        syncScrollPositionToSelection(animated: false)
    }

    func selectTab(at index: Int, animated: Bool, playHaptic: Bool = true) {
        guard index >= 0, index < titles.count else { return }
        let indexChanged = index != selectedIndex
        selectedIndex = index
        pageProgressTracking = CGFloat(index)
        if indexChanged, playHaptic {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        if animated {
            suspendSelectionSyncFromScroll = true
        }
        scrollToPageProgress(CGFloat(index), animated: animated)
        if !animated {
            suspendSelectionSyncFromScroll = false
            updatePillAndLabels(progress: CGFloat(index))
        }
    }

    /// Keeps the collection view centered on the selected tab once layout metrics are valid.
    func syncScrollPositionToSelection(animated: Bool) {
        guard collectionView.numberOfItems(inSection: 0) > 0, !titles.isEmpty else { return }
        collectionView.layoutIfNeeded()
        let progress = max(0, min(pageProgressTracking, CGFloat(titles.count - 1)))
        selectedIndex = max(0, min(Int(round(progress)), titles.count - 1))
        scrollToPageProgress(progress, animated: animated)
        updatePillAndLabels(progress: progress)
    }

    /// Collapses unselected tabs while reading; expand again via vertical scroll-up or horizontal interaction.
    func setShowsInactiveTabs(_ shows: Bool, animated: Bool) {
        guard showsInactiveTabs != shows else { return }
        showsInactiveTabs = shows
        collectionView.isScrollEnabled = shows

        let apply = { self.applyInactiveTabVisibility() }

        if animated {
            UIView.animate(
                withDuration: 0.32,
                delay: 0,
                options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState],
                animations: apply
            )
        } else {
            apply()
        }

        if !shows {
            setPageProgress(CGFloat(selectedIndex), animated: animated)
        }
    }

    /// Connects the tab bar to the active page scroll view for the system scroll-edge expansion effect.
    func setScrollEdgeScrollView(_ scrollView: UIScrollView?) {
        scrollEdgeInteraction.scrollView = scrollView
    }

    func setPageProgress(_ progress: CGFloat, animated: Bool) {
        guard !titles.isEmpty else { return }
        let clamped = max(0, min(progress, CGFloat(titles.count - 1)))
        pageProgressTracking = clamped
        scrollToPageProgress(clamped, animated: animated)
    }

    private func scrollToPageProgress(_ progress: CGFloat, animated: Bool) {
        guard let offsetX = contentOffsetX(forPageProgress: progress) else { return }
        let cv = collectionView
        isProgrammaticScroll = true
        let offsetChanged = abs(cv.contentOffset.x - offsetX) > 0.5
        let actuallyAnimate = animated && offsetChanged
        if actuallyAnimate {
            animateContentOffset(to: CGPoint(x: offsetX, y: 0))
        } else {
            cv.contentOffset.x = offsetX
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isProgrammaticScroll = false
                self.suspendSelectionSyncFromScroll = false
            }
        }
    }

    private func animateContentOffset(to offset: CGPoint) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(Self.snapAnimationDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        collectionView.setContentOffset(offset, animated: true)
        CATransaction.commit()
    }

    private func contentOffsetX(forPageProgress progress: CGFloat) -> CGFloat? {
        guard let range = contentOffsetRangeX() else { return nil }
        let centerX = centerXInContent(forPageProgress: progress)
        let offsetX = centerX - collectionView.bounds.width / 2
        return min(max(range.min, offsetX), range.max)
    }

    private func centerXInContent(forPageProgress progress: CGFloat) -> CGFloat {
        let count = titles.count
        guard count > 0 else { return 0 }
        let widths = titles.map { cellWidth(for: $0) }
        let leftInset = collectionView.bounds.width / 2 - widths[0] / 2
        let spacing: CGFloat = 8
        func centerOfItem(_ i: Int) -> CGFloat {
            var x = leftInset
            for j in 0..<i { x += widths[j] + spacing }
            return x + widths[i] / 2
        }
        let idx = min(Int(progress), count - 1)
        let t = progress - CGFloat(idx)
        if idx >= count - 1 || t <= 0 {
            return centerOfItem(idx)
        }
        let c0 = centerOfItem(idx)
        let c1 = centerOfItem(idx + 1)
        return c0 + t * (c1 - c0)
    }

    private func cellWidth(for title: String) -> CGFloat {
        let font = TabCell.selectedFont
        return (title as NSString).size(withAttributes: [.font: font]).width + 32
    }

    private func contentOffsetRangeX() -> (min: CGFloat, max: CGFloat)? {
        let cv = collectionView
        guard !titles.isEmpty, cv.bounds.width > 0 else { return nil }
        let contentWidth = max(cv.contentSize.width, estimatedContentWidth())
        let maxOffset = max(0, contentWidth - cv.bounds.width)
        return (0, maxOffset)
    }

    private func estimatedContentWidth() -> CGFloat {
        guard !titles.isEmpty, collectionView.bounds.width > 0 else { return 0 }
        let widths = titles.map { cellWidth(for: $0) }
        let spacing: CGFloat = 8
        let leftInset = collectionView.bounds.width / 2 - widths[0] / 2
        let rightInset = collectionView.bounds.width / 2 - widths[widths.count - 1] / 2
        let cellsWidth = widths.reduce(0, +) + spacing * CGFloat(max(widths.count - 1, 0))
        return leftInset + cellsWidth + rightInset
    }

    private func snapToNearestPage(animated: Bool) {
        guard !titles.isEmpty else { return }
        let progress = pageProgressFromContentOffset()
        let clampedProgress = max(0, min(progress, CGFloat(titles.count - 1)))
        let index = Int(round(clampedProgress))
        let roundedIndex = max(0, min(index, titles.count - 1))
        selectedIndex = roundedIndex
        isProgrammaticScroll = true
        suspendSelectionSyncFromScroll = true
        scrollToPageProgress(CGFloat(roundedIndex), animated: animated)
        delegate?.tabBar(self, didSelectTabAt: roundedIndex)
    }

    private func updatePillAndLabels(progress: CGFloat) {
        guard !titles.isEmpty, bounds.width > 0 else { return }
        let count = titles.count
        let clamped = max(0, min(progress, CGFloat(count - 1)))
        let widths = titles.map { cellWidth(for: $0) }
        let i = min(Int(clamped), count - 1)
        let t = clamped - CGFloat(i)
        let pillWidth: CGFloat
        if i >= count - 1 || t <= 0 {
            pillWidth = widths[i]
        } else {
            pillWidth = widths[i] + t * (widths[i + 1] - widths[i])
        }
        let height = Self.pillHeight
        pillGlass.bounds = CGRect(x: 0, y: 0, width: pillWidth, height: height)
        pillGlass.center = CGPoint(x: bounds.midX, y: bounds.midY)
        pillGlass.layer.cornerRadius = height / 2
        for cell in collectionView.visibleCells {
            guard
                let tabCell = cell as? TabCell,
                let indexPath = collectionView.indexPath(for: cell)
            else { continue }
            tabCell.setSelectedness(selectedness(forItem: indexPath.item, progress: clamped))
        }
        applyInactiveTabVisibility()
    }

    private func applyInactiveTabVisibility() {
        let inactiveAlpha: CGFloat = showsInactiveTabs ? 1 : 0
        for cell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell) else { continue }
            let isActive = indexPath.item == selectedIndex
            cell.alpha = isActive ? 1 : inactiveAlpha
            cell.isUserInteractionEnabled = showsInactiveTabs || isActive
        }
    }

    private func finalizeInteractiveScroll() {
        isProgrammaticScroll = false
        suspendSelectionSyncFromScroll = false
        delegate?.tabBarDidEndScrolling(self)
    }

    private func selectedness(forItem item: Int, progress: CGFloat) -> CGFloat {
        let distance = abs(CGFloat(item) - progress)
        return max(0, min(1, 1 - distance))
    }

    private func pageProgressFromContentOffset() -> CGFloat {
        pageProgress(forContentOffsetX: collectionView.contentOffset.x)
    }

    private func pageProgress(forContentOffsetX offsetX: CGFloat) -> CGFloat {
        let cv = collectionView
        let centerX = offsetX + cv.bounds.width / 2
        let widths = titles.map { cellWidth(for: $0) }
        guard !widths.isEmpty else { return 0 }
        let leftInset = cv.bounds.width / 2 - widths[0] / 2
        let spacing: CGFloat = 8
        func centerOfItem(_ i: Int) -> CGFloat {
            var x = leftInset
            for j in 0..<i { x += widths[j] + spacing }
            return x + widths[i] / 2
        }
        if centerX <= centerOfItem(0) { return 0 }
        for i in 0..<(widths.count - 1) {
            let c0 = centerOfItem(i)
            let c1 = centerOfItem(i + 1)
            if centerX <= c1 {
                let t = (centerX - c0) / (c1 - c0)
                return CGFloat(i) + max(0, min(1, t))
            }
        }
        return CGFloat(widths.count - 1)
    }
}

// MARK: - UICollectionViewDataSource

extension GameCategoryTabBar: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        titles.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TabCell.reuseID, for: indexPath) as! TabCell
        cell.configure(title: titles[indexPath.item])
        let progress = pageProgressFromContentOffset()
        cell.setSelectedness(selectedness(forItem: indexPath.item, progress: progress))
        let isActive = indexPath.item == selectedIndex
        cell.alpha = showsInactiveTabs || isActive ? 1 : 0
        cell.isUserInteractionEnabled = showsInactiveTabs || isActive
        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension GameCategoryTabBar: UICollectionViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        let progress = pageProgressFromContentOffset()
        let clampedProgress = max(0, min(progress, CGFloat(titles.count - 1)))
        pageProgressTracking = clampedProgress
        updatePillAndLabels(progress: clampedProgress)
        let newIndex = Int(round(clampedProgress))
        let clamped = max(0, min(newIndex, titles.count - 1))
        if !suspendSelectionSyncFromScroll, clamped != selectedIndex {
            selectedIndex = clamped
        }
        if !isProgrammaticScroll {
            delegate?.tabBar(self, didScrollToPageProgress: clampedProgress)
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if scrollView === collectionView {
            isProgrammaticScroll = false
            setShowsInactiveTabs(true, animated: true)
        }
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        guard scrollView === collectionView, showsInactiveTabs else { return }

        let projectedProgress = pageProgress(forContentOffsetX: targetContentOffset.pointee.x)
        let clampedProgress = max(0, min(projectedProgress, CGFloat(titles.count - 1)))
        let roundedIndex = max(0, min(Int(round(clampedProgress)), titles.count - 1))
        if let snapOffsetX = contentOffsetX(forPageProgress: CGFloat(roundedIndex)) {
            targetContentOffset.pointee.x = snapOffsetX
        }

        selectedIndex = roundedIndex
        pageProgressTracking = CGFloat(roundedIndex)
        suspendSelectionSyncFromScroll = true
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if scrollView === collectionView, !decelerate {
            snapToNearestPage(animated: true)
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if scrollView === collectionView {
            finalizeInteractiveScroll()
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        if scrollView === collectionView {
            isProgrammaticScroll = false
            suspendSelectionSyncFromScroll = false
            delegate?.tabBarDidEndScrolling(self)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item != selectedIndex else { return }
        selectedIndex = indexPath.item
        pageProgressTracking = CGFloat(indexPath.item)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isProgrammaticScroll = true
        suspendSelectionSyncFromScroll = true
        scrollToPageProgress(CGFloat(indexPath.item), animated: true)
        delegate?.tabBar(self, didSelectTabAt: indexPath.item)
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension GameCategoryTabBar: UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let title = titles[indexPath.item]
        let textWidth = (title as NSString).size(withAttributes: [.font: TabCell.selectedFont]).width
        return CGSize(width: textWidth + 32, height: 36)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        insetForSectionAt section: Int
    ) -> UIEdgeInsets {
        guard !titles.isEmpty, collectionView.bounds.width > 0 else {
            return UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        }
        let w0 = cellWidth(for: titles[0])
        let wLast = cellWidth(for: titles[titles.count - 1])
        let half = collectionView.bounds.width / 2
        let leftInset = half - w0 / 2
        let rightInset = half - wLast / 2
        return UIEdgeInsets(top: 4, left: leftInset, bottom: 4, right: rightInset)
    }
}

// MARK: - Tab Cell

private final class TabCell: UICollectionViewCell {
    static let reuseID = "GameCategoryTabCell"
    private static let fontSize: CGFloat = 14
    private static let minWeight = UIFont.Weight.regular.rawValue
    private static let maxWeight = UIFont.Weight.bold.rawValue
    /// Widest tab label metric (bold) for cell sizing.
    static let selectedFont = UIFont.systemFont(ofSize: fontSize, weight: .bold)

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = TabCell.font(forSelectedness: 0)
        label.textAlignment = .center
        return label
    }()

    static func font(forSelectedness amount: CGFloat) -> UIFont {
        let clamped = max(0, min(1, amount))
        let weightValue = minWeight + (maxWeight - minWeight) * clamped
        return UIFont.systemFont(ofSize: fontSize, weight: UIFont.Weight(weightValue))
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String) {
        titleLabel.text = title
    }

    func setSelectedness(_ amount: CGFloat) {
        let clamped = max(0, min(1, amount))
        titleLabel.textColor = TabCell.blend(from: .secondaryLabel, to: .label, t: clamped)
        titleLabel.font = Self.font(forSelectedness: clamped)
    }

    private static func blend(from a: UIColor, to b: UIColor, t: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(
            red: ar + (br - ar) * t,
            green: ag + (bg - ag) * t,
            blue: ab + (bb - ab) * t,
            alpha: aa + (ba - aa) * t
        )
    }
}
