//
//  LessonThumbnailViewerController.swift
//  shizen
//
//  Full-screen scene image viewer. Opens with a zoom from the tapped
//  thumbnail, pages horizontally through every scene, and keeps a filmstrip
//  of all thumbnails along the bottom. Pinch or double-tap zooms, a single tap
//  hides the chrome, and a downward drag zooms back into the source thumbnail.
//

import UIKit

final class LessonThumbnailViewerController: UIViewController {

    struct Item {
        let caption: String
        /// Already-decoded thumbnail so the zoom starts with real pixels.
        let placeholder: UIImage?
    }

    /// Loads the full-size image for an index. May call back more than once (bundled, then remote).
    typealias ImageLoader = (_ index: Int, _ update: @escaping (UIImage) -> Void) -> Void

    /// View the zoom starts from and returns to (its frame and corner radius). Nil falls back to a fade.
    var sourceViewProvider: ((Int) -> UIView?)?
    /// Fires as the visible page changes so the presenter can keep its thumbnail on screen.
    var onIndexChange: ((Int) -> Void)?

    private(set) var currentIndex: Int
    private let items: [Item]
    private var images: [UIImage?]
    private var requestedIndices = Set<Int>()
    private let imageLoader: ImageLoader
    private let zoomTransition = LessonThumbnailZoomTransition()

    let backdropView = UIView()
    private let pagerLayout = UICollectionViewFlowLayout()
    private lazy var pager = UICollectionView(frame: .zero, collectionViewLayout: pagerLayout)
    private let filmstripLayout = UICollectionViewFlowLayout()
    private lazy var filmstrip = UICollectionView(frame: .zero, collectionViewLayout: filmstripLayout)
    private let captionLabel = UILabel()
    private let closeButton = GlassIconButton(
        symbolName: "xmark",
        pointSize: 18,
        tintColor: .white,
        accessibilityLabel: "Close"
    )
    private let moreButton = GlassIconButton(
        symbolName: "ellipsis",
        pointSize: 18,
        tintColor: .white,
        accessibilityLabel: "More"
    )
    private var chromeViews: [UIView] { [closeButton, moreButton, captionLabel, filmstrip] }
    private var isChromeHidden = false
    private var hasPositionedInitialPage = false
    private var dismissPan: UIPanGestureRecognizer!
    /// Row / hero thumbnail currently faded out while the viewer is up.
    private weak var hiddenSourceView: UIView?

    static let pageGap: CGFloat = 20
    static let imageCornerRadius: CGFloat = 16
    private static let horizontalImageInset: CGFloat = 16
    private static let topChromeReserve: CGFloat = 72
    private static let bottomChromeReserve: CGFloat = 150
    static let fullImagePixelSize: CGFloat = 2048

    init(items: [Item], initialIndex: Int, imageLoader: @escaping ImageLoader) {
        self.items = items
        self.images = items.map(\.placeholder)
        self.currentIndex = min(max(initialIndex, 0), max(items.count - 1, 0))
        self.imageLoader = imageLoader
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom
        modalPresentationCapturesStatusBarAppearance = true
        transitioningDelegate = zoomTransition
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var prefersStatusBarHidden: Bool { isChromeHidden }
    override var prefersHomeIndicatorAutoHidden: Bool { isChromeHidden }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        overrideUserInterfaceStyle = .dark

        backdropView.backgroundColor = .black
        backdropView.frame = view.bounds
        backdropView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(backdropView)

        configurePager()
        configureChrome()
        configureGestures()
        updateCaption()
        loadImageIfNeeded(at: currentIndex)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let pageSize = CGSize(width: view.bounds.width + Self.pageGap, height: view.bounds.height)
        if pagerLayout.itemSize != pageSize {
            pagerLayout.itemSize = pageSize
            pagerLayout.invalidateLayout()
            pager.layoutIfNeeded()
            pager.contentOffset.x = CGFloat(currentIndex) * pageSize.width
        }
        if !hasPositionedInitialPage, view.bounds.width > 0 {
            hasPositionedInitialPage = true
            pager.layoutIfNeeded()
            pager.contentOffset.x = CGFloat(currentIndex) * pageSize.width
            filmstrip.layoutIfNeeded()
            selectFilmstripItem(at: currentIndex, animated: false)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed {
            restoreHiddenSource()
        }
    }

    // MARK: - Transition hooks

    /// Image shown for the current page, placeholder included.
    var currentImage: UIImage? {
        images.indices.contains(currentIndex) ? images[currentIndex] : nil
    }

    /// Where the current image sits on screen, after any drag or zoom. Falls back to the resting fit.
    func currentImageFrame(in target: UIView) -> CGRect {
        if let cell = pager.cellForItem(at: IndexPath(item: currentIndex, section: 0)) as? LessonViewerPageCell,
           cell.imageView.image != nil,
           cell.imageView.bounds.width > 0 {
            return cell.imageView.convert(cell.imageView.bounds, to: target)
        }
        return restingImageFrame(in: target)
    }

    func restingImageFrame(in target: UIView) -> CGRect {
        let fit = Self.fitRect(
            imageSize: currentImage?.size ?? CGSize(width: 1, height: 1),
            in: view.bounds,
            safeArea: view.safeAreaInsets
        )
        return view.convert(fit, to: target)
    }

    /// Hides the live page while a transition snapshot stands in for it.
    func setPagerHiddenForTransition(_ hidden: Bool) {
        pager.isHidden = hidden
    }

    func setChromeAlpha(_ alpha: CGFloat) {
        for view in chromeViews {
            view.alpha = isChromeHidden ? 0 : alpha
        }
    }

    /// Hides the source thumbnail for `index` and restores any previously hidden one.
    func hideSource(for index: Int) {
        hiddenSourceView?.alpha = 1
        let source = sourceViewProvider?(index)
        source?.alpha = 0
        hiddenSourceView = source
    }

    func restoreHiddenSource() {
        hiddenSourceView?.alpha = 1
        hiddenSourceView = nil
    }

    /// Keeps the tracked source invisible without revealing it (dismiss zoom).
    func keepSourceHidden() {
        hiddenSourceView?.alpha = 0
    }

    // MARK: - Layout

    private func configurePager() {
        pagerLayout.scrollDirection = .horizontal
        pagerLayout.minimumLineSpacing = 0
        pagerLayout.minimumInteritemSpacing = 0

        pager.backgroundColor = .clear
        pager.isPagingEnabled = true
        pager.showsHorizontalScrollIndicator = false
        pager.contentInsetAdjustmentBehavior = .never
        pager.decelerationRate = .fast
        pager.dataSource = self
        pager.delegate = self
        pager.register(LessonViewerPageCell.self, forCellWithReuseIdentifier: LessonViewerPageCell.reuseID)
        pager.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pager)

        // Wider than the screen so pages swipe with a gap between them.
        NSLayoutConstraint.activate([
            pager.topAnchor.constraint(equalTo: view.topAnchor),
            pager.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pager.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -Self.pageGap / 2),
            pager.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: Self.pageGap / 2),
        ])
    }

    private func configureChrome() {
        closeButton.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        }, for: .touchUpInside)
        moreButton.menu = makeMoreMenu()
        moreButton.showsMenuAsPrimaryAction = true

        captionLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 15, weight: .regular)
        )
        captionLabel.adjustsFontForContentSizeCategory = true
        captionLabel.textColor = UIColor(white: 1, alpha: 0.82)
        captionLabel.textAlignment = .center
        captionLabel.numberOfLines = 2
        captionLabel.translatesAutoresizingMaskIntoConstraints = false

        filmstripLayout.scrollDirection = .horizontal
        filmstripLayout.itemSize = CGSize(
            width: LessonViewerFilmstripCell.side,
            height: LessonViewerFilmstripCell.side
        )
        filmstripLayout.minimumLineSpacing = 12
        filmstripLayout.sectionInset = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)
        filmstrip.backgroundColor = .clear
        filmstrip.clipsToBounds = false
        filmstrip.showsHorizontalScrollIndicator = false
        filmstrip.dataSource = self
        filmstrip.delegate = self
        filmstrip.register(LessonViewerFilmstripCell.self, forCellWithReuseIdentifier: LessonViewerFilmstripCell.reuseID)
        filmstrip.translatesAutoresizingMaskIntoConstraints = false

        for chrome in [closeButton, moreButton, captionLabel, filmstrip] as [UIView] {
            view.addSubview(chrome)
        }

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            closeButton.widthAnchor.constraint(equalToConstant: 48),
            closeButton.heightAnchor.constraint(equalToConstant: 48),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            closeButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),

            moreButton.widthAnchor.constraint(equalToConstant: 48),
            moreButton.heightAnchor.constraint(equalToConstant: 48),
            moreButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            moreButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),

            filmstrip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filmstrip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filmstrip.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -8),
            filmstrip.heightAnchor.constraint(equalToConstant: LessonViewerFilmstripCell.side + 12),

            captionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            captionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            captionLabel.bottomAnchor.constraint(equalTo: filmstrip.topAnchor, constant: -20),
        ])
    }

    private func configureGestures() {
        dismissPan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        dismissPan.delegate = self
        pager.addGestureRecognizer(dismissPan)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        pager.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        pager.addGestureRecognizer(singleTap)
    }

    private func makeMoreMenu() -> UIMenu {
        let share = UIAction(
            title: "Share",
            image: UIImage(systemName: "square.and.arrow.up")
        ) { [weak self] _ in
            self?.shareCurrentImage()
        }
        let save = UIAction(
            title: "Save to Photos",
            image: UIImage(systemName: "square.and.arrow.down")
        ) { [weak self] _ in
            guard let image = self?.currentImage else { return }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }
        return UIMenu(children: [share, save])
    }

    private func shareCurrentImage() {
        guard let image = currentImage else { return }
        let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        activity.popoverPresentationController?.sourceItem = moreButton
        present(activity, animated: true)
    }

    /// Aspect-fit inside the page, clear of the top buttons and the caption + filmstrip.
    static func fitRect(imageSize: CGSize, in bounds: CGRect, safeArea: UIEdgeInsets) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0 else { return .zero }
        let maxWidth = bounds.width - horizontalImageInset * 2
        let maxHeight = bounds.height
            - (safeArea.top + topChromeReserve)
            - (safeArea.bottom + bottomChromeReserve)
        let scale = min(maxWidth / imageSize.width, max(maxHeight, 1) / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        ).integral
    }

    // MARK: - Paging

    private func setCurrentIndex(_ index: Int, scrollPager: Bool) {
        guard items.indices.contains(index) else { return }
        if scrollPager {
            pager.setContentOffset(
                CGPoint(x: CGFloat(index) * pagerLayout.itemSize.width, y: 0),
                animated: false
            )
        }
        guard index != currentIndex else { return }
        resetZoom(at: currentIndex)
        currentIndex = index
        updateCaption()
        selectFilmstripItem(at: index, animated: true)
        loadImageIfNeeded(at: index)
        onIndexChange?(index)
        hideSource(for: index)
    }

    private func updateCaption() {
        captionLabel.text = items.indices.contains(currentIndex) ? items[currentIndex].caption : nil
    }

    private func selectFilmstripItem(at index: Int, animated: Bool) {
        for case let cell as LessonViewerFilmstripCell in filmstrip.visibleCells {
            guard let path = filmstrip.indexPath(for: cell) else { continue }
            cell.setCurrent(path.item == index, animated: animated)
        }
        // Scroll only when the current thumbnail is partly off screen, so the strip stays put while paging.
        guard filmstrip.numberOfItems(inSection: 0) > index,
              let attributes = filmstrip.layoutAttributesForItem(at: IndexPath(item: index, section: 0))
        else { return }
        let target = attributes.frame.insetBy(dx: -filmstripLayout.sectionInset.left, dy: 0)
        let visible = CGRect(origin: filmstrip.contentOffset, size: filmstrip.bounds.size)
        guard !visible.contains(target) else { return }
        filmstrip.scrollRectToVisible(target, animated: animated)
    }

    private func resetZoom(at index: Int) {
        let cell = pager.cellForItem(at: IndexPath(item: index, section: 0)) as? LessonViewerPageCell
        cell?.resetZoom(animated: false)
    }

    private func currentPageCell() -> LessonViewerPageCell? {
        pager.cellForItem(at: IndexPath(item: currentIndex, section: 0)) as? LessonViewerPageCell
    }

    // MARK: - Images

    private func loadImageIfNeeded(at index: Int) {
        guard items.indices.contains(index), requestedIndices.insert(index).inserted else { return }
        imageLoader(index) { [weak self] image in
            self?.applyImage(image, at: index)
        }
    }

    private func applyImage(_ image: UIImage, at index: Int) {
        guard images.indices.contains(index) else { return }
        images[index] = image
        let path = IndexPath(item: index, section: 0)
        (pager.cellForItem(at: path) as? LessonViewerPageCell)?.setImage(image)
        (filmstrip.cellForItem(at: path) as? LessonViewerFilmstripCell)?.imageView.image = image
    }

    // MARK: - Gestures

    @objc private func handleSingleTap() {
        isChromeHidden.toggle()
        UIView.animate(withDuration: 0.22) {
            for view in self.chromeViews {
                view.alpha = self.isChromeHidden ? 0 : 1
            }
            self.setNeedsStatusBarAppearanceUpdate()
        }
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard let cell = currentPageCell() else { return }
        cell.toggleZoom(at: gesture.location(in: cell.imageView))
    }

    @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        guard let cell = currentPageCell() else { return }
        let translation = gesture.translation(in: view)
        let progress = min(1, max(0, translation.y / (view.bounds.height * 0.5)))

        switch gesture.state {
        case .began, .changed:
            let scale = 1 - progress * 0.25
            cell.zoomView.transform = CGAffineTransform(translationX: translation.x, y: translation.y)
                .scaledBy(x: scale, y: scale)
            backdropView.alpha = 1 - progress
            setChromeAlpha(1 - min(1, progress * 3))
        case .ended, .cancelled, .failed:
            let velocity = gesture.velocity(in: view).y
            let shouldDismiss = gesture.state == .ended && (translation.y > 120 || velocity > 900)
            if shouldDismiss {
                dismiss(animated: true)
            } else {
                UIViewPropertyAnimator(duration: 0.4, dampingRatio: 0.82) {
                    cell.zoomView.transform = .identity
                    self.backdropView.alpha = 1
                    self.setChromeAlpha(1)
                }.startAnimation()
            }
        default:
            break
        }
    }
}

// MARK: - Data source

extension LessonThumbnailViewerController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView === pager {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: LessonViewerPageCell.reuseID,
                for: indexPath
            ) as! LessonViewerPageCell
            cell.setImage(images[indexPath.item])
            return cell
        }
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: LessonViewerFilmstripCell.reuseID,
            for: indexPath
        ) as! LessonViewerFilmstripCell
        cell.imageView.image = images[indexPath.item]
        cell.setCurrent(indexPath.item == currentIndex, animated: false)
        cell.accessibilityLabel = items[indexPath.item].caption
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        loadImageIfNeeded(at: indexPath.item)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard collectionView === filmstrip else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        setCurrentIndex(indexPath.item, scrollPager: true)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === pager, pager.isDragging || pager.isDecelerating else { return }
        let width = pagerLayout.itemSize.width
        guard width > 0 else { return }
        let page = Int((scrollView.contentOffset.x / width).rounded())
        setCurrentIndex(min(max(page, 0), items.count - 1), scrollPager: false)
    }
}

// MARK: - Gesture delegate

extension LessonThumbnailViewerController: UIGestureRecognizerDelegate {

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === dismissPan else { return true }
        guard let cell = currentPageCell(), !cell.isZoomed else { return false }
        let velocity = dismissPan.velocity(in: view)
        return velocity.y > 0 && abs(velocity.y) > abs(velocity.x)
    }
}

// MARK: - Page cell

private final class LessonViewerPageCell: UICollectionViewCell, UIScrollViewDelegate {

    static let reuseID = "LessonViewerPageCell"

    /// Zooms the image. Dragged and scaled during swipe-to-dismiss.
    let zoomView = UIScrollView()
    let imageView = UIImageView()

    var isZoomed: Bool { zoomView.zoomScale > zoomView.minimumZoomScale + 0.01 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        zoomView.delegate = self
        zoomView.minimumZoomScale = 1
        zoomView.maximumZoomScale = 4
        zoomView.showsVerticalScrollIndicator = false
        zoomView.showsHorizontalScrollIndicator = false
        zoomView.contentInsetAdjustmentBehavior = .never
        zoomView.decelerationRate = .fast
        contentView.addSubview(zoomView)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerCurve = .continuous
        imageView.layer.cornerRadius = LessonThumbnailViewerController.imageCornerRadius
        zoomView.addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        zoomView.transform = .identity
        resetZoom(animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pageFrame = contentView.bounds.insetBy(dx: LessonThumbnailViewerController.pageGap / 2, dy: 0)
        guard zoomView.bounds.size != pageFrame.size || zoomView.center != CGPoint(x: pageFrame.midX, y: pageFrame.midY) else { return }
        zoomView.transform = .identity
        zoomView.frame = pageFrame
        layoutImage()
    }

    func setImage(_ image: UIImage?) {
        let sizeChanged = imageView.image?.size != image?.size
        imageView.image = image
        if sizeChanged {
            layoutImage()
        }
    }

    func resetZoom(animated: Bool) {
        zoomView.setZoomScale(zoomView.minimumZoomScale, animated: animated)
    }

    func toggleZoom(at point: CGPoint) {
        if isZoomed {
            resetZoom(animated: true)
            return
        }
        let scale: CGFloat = 2.5
        let size = CGSize(width: zoomView.bounds.width / scale, height: zoomView.bounds.height / scale)
        zoomView.zoom(to: CGRect(
            x: point.x - size.width / 2,
            y: point.y - size.height / 2,
            width: size.width,
            height: size.height
        ), animated: true)
    }

    /// Image sits at its aspect-fit size at zoom 1; insets keep it centered at any zoom.
    private func layoutImage() {
        zoomView.setZoomScale(1, animated: false)
        guard let image = imageView.image, zoomView.bounds.width > 0 else {
            imageView.frame = .zero
            return
        }
        let safeArea = window?.safeAreaInsets ?? .zero
        let fit = LessonThumbnailViewerController.fitRect(
            imageSize: image.size,
            in: CGRect(origin: .zero, size: zoomView.bounds.size),
            safeArea: safeArea
        )
        imageView.frame = CGRect(origin: .zero, size: fit.size)
        zoomView.contentSize = fit.size
        centerImage()
    }

    private func centerImage() {
        let content = imageView.frame.size
        let bounds = zoomView.bounds.size
        let horizontal = max(0, (bounds.width - content.width) / 2)
        let vertical = max(0, (bounds.height - content.height) / 2)
        zoomView.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }
}

// MARK: - Filmstrip cell

private final class LessonViewerFilmstripCell: UICollectionViewCell {

    static let reuseID = "LessonViewerFilmstripCell"
    static let side: CGFloat = 50

    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor(white: 1, alpha: 0.08)
        imageView.layer.cornerCurve = .continuous
        imageView.layer.cornerRadius = 10
        imageView.layer.borderColor = UIColor.white.cgColor
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(imageView)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Border and brightness only. No scale, so the strip never jumps while paging.
    func setCurrent(_ isCurrent: Bool, animated: Bool) {
        imageView.layer.borderWidth = isCurrent ? 2.5 : 0
        if isCurrent {
            accessibilityTraits.insert(.selected)
        } else {
            accessibilityTraits.remove(.selected)
        }
        let alpha: CGFloat = isCurrent ? 1 : 0.6
        guard animated else {
            contentView.alpha = alpha
            return
        }
        UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.contentView.alpha = alpha
        }
    }
}

// MARK: - Zoom transition

/// Zooms a scene thumbnail into the viewer and back. Dismissal starts from
/// wherever the image is (mid-drag or zoomed) and lands on the current page's thumbnail.
final class LessonThumbnailZoomTransition: NSObject, UIViewControllerTransitioningDelegate {

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        Animator(isPresenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        Animator(isPresenting: false)
    }

    private final class Animator: NSObject, UIViewControllerAnimatedTransitioning {

        let isPresenting: Bool

        init(isPresenting: Bool) {
            self.isPresenting = isPresenting
        }

        func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
            isPresenting ? 0.5 : 0.42
        }

        func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
            if isPresenting {
                animatePresentation(using: transitionContext)
            } else {
                animateDismissal(using: transitionContext)
            }
        }

        private func animatePresentation(using context: UIViewControllerContextTransitioning) {
            guard let viewer = context.viewController(forKey: .to) as? LessonThumbnailViewerController else {
                context.completeTransition(false)
                return
            }
            let container = context.containerView
            viewer.view.frame = context.finalFrame(for: viewer)
            container.addSubview(viewer.view)
            viewer.view.layoutIfNeeded()

            let source = viewer.sourceViewProvider?(viewer.currentIndex)
            let snapshot = Self.makeSnapshot(image: viewer.currentImage ?? (source as? UIImageView)?.image)
            let startFrame = source.map { $0.convert($0.bounds, to: container) }
            let endFrame = viewer.restingImageFrame(in: container)

            if let startFrame, let source {
                snapshot.frame = startFrame
                snapshot.layer.cornerRadius = source.layer.cornerRadius
            } else {
                snapshot.frame = endFrame
                snapshot.alpha = 0
                snapshot.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            }
            container.addSubview(snapshot)

            source?.alpha = 0
            viewer.setPagerHiddenForTransition(true)
            viewer.backdropView.alpha = 0
            viewer.setChromeAlpha(0)

            let animator = UIViewPropertyAnimator(
                duration: transitionDuration(using: context),
                dampingRatio: 0.84
            ) {
                snapshot.transform = .identity
                snapshot.frame = endFrame
                snapshot.alpha = 1
                snapshot.layer.cornerRadius = LessonThumbnailViewerController.imageCornerRadius
                viewer.backdropView.alpha = 1
            }
            animator.addAnimations({
                viewer.setChromeAlpha(1)
            }, delayFactor: 0.35)
            animator.addCompletion { position in
                viewer.setPagerHiddenForTransition(false)
                snapshot.removeFromSuperview()
                let finished = position == .end && !context.transitionWasCancelled
                if finished {
                    viewer.hideSource(for: viewer.currentIndex)
                } else {
                    source?.alpha = 1
                }
                context.completeTransition(finished)
            }
            animator.startAnimation()
        }

        private func animateDismissal(using context: UIViewControllerContextTransitioning) {
            guard let viewer = context.viewController(forKey: .from) as? LessonThumbnailViewerController else {
                context.completeTransition(false)
                return
            }
            let container = context.containerView
            let source = viewer.sourceViewProvider?(viewer.currentIndex)
            let startFrame = viewer.currentImageFrame(in: container)
            let snapshot = Self.makeSnapshot(image: viewer.currentImage ?? (source as? UIImageView)?.image)
            snapshot.frame = startFrame
            snapshot.layer.cornerRadius = LessonThumbnailViewerController.imageCornerRadius
            container.addSubview(snapshot)

            viewer.setPagerHiddenForTransition(true)
            source?.alpha = 0
            viewer.keepSourceHidden()
            let sourceFrame = source.map { $0.convert($0.bounds, to: container) }

            let animator = UIViewPropertyAnimator(
                duration: transitionDuration(using: context),
                dampingRatio: 0.9
            ) {
                if let sourceFrame, let source {
                    snapshot.frame = sourceFrame
                    snapshot.layer.cornerRadius = source.layer.cornerRadius
                } else {
                    snapshot.alpha = 0
                    snapshot.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
                }
                viewer.backdropView.alpha = 0
                viewer.setChromeAlpha(0)
            }
            animator.addCompletion { position in
                let finished = position == .end && !context.transitionWasCancelled
                snapshot.removeFromSuperview()
                if finished {
                    source?.alpha = 1
                    viewer.restoreHiddenSource()
                } else {
                    viewer.setPagerHiddenForTransition(false)
                }
                context.completeTransition(finished)
            }
            animator.startAnimation()
        }

        private static func makeSnapshot(image: UIImage?) -> UIImageView {
            let snapshot = UIImageView(image: image)
            snapshot.contentMode = .scaleAspectFill
            snapshot.clipsToBounds = true
            snapshot.layer.cornerCurve = .continuous
            return snapshot
        }
    }
}
