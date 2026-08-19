//
//  KanjiDecompositionPagerViewController.swift
//  shizen
//
//  Slideshow for a decomposed word: an intro teaser, one slide per component
//  character, then the combined-word reveal. Mirrors DialogueQuizViewController's UIPageViewController +
//  UIPageControl wiring. Each card can be exported as a fixed-size image for social slideshow posts.
//
//  Live cards are shown inside an export viewfinder: laid out at the exact canvas point size,
//  then scaled to fit, so clipping matches what Save to Photos will capture.
//

import UIKit

final class KanjiDecompositionPagerViewController: UIViewController {

    private let word: KanjiDecompositionWord

    private let pageControl = UIPageControl()
    private let sizeControl = UISegmentedControl(
        items: KanjiDecompositionExportSize.allCases.map(\.shortTitle)
    )
    private let pageViewController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal
    )

    private var pages: [KanjiDecompositionCardPageViewController] = []
    private var currentIndex = 0
    private var pendingPhotoSaves = 0
    private var photoSaveTotal = 0
    private var photoSaveErrors: [Error] = []
    private let badgeLayoutStore = KanjiDecompositionBadgeLayoutStore()
    private var isPositioningBadges = false
    private var selectedBadgeIdentifier: KanjiDecompositionBadgeIdentifier?
    private var badgePanStartOffset: CGPoint = .zero
    private var badgeTapGesture: UITapGestureRecognizer?
    private var badgeLongPressGesture: UILongPressGestureRecognizer?
    private var badgePanGesture: UIPanGestureRecognizer?
    private var exportBarButton: UIBarButtonItem?
    private var introPartLabel = "Kanji is literal, part 1"
    private var selectedExportSize: KanjiDecompositionExportSize = .story {
        didSet {
            guard selectedExportSize != oldValue else { return }
            pages.forEach { $0.apply(exportSize: selectedExportSize) }
        }
    }

    init(word: KanjiDecompositionWord) {
        self.word = word
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = word.expression
        navigationItem.largeTitleDisplayMode = .never
        // Dim outside the viewfinder so the export frame reads clearly.
        view.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.06, alpha: 1)
                : UIColor(white: 0.78, alpha: 1)
        }

        let exportButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            primaryAction: nil,
            menu: exportMenu()
        )
        exportButton.accessibilityLabel = "Export slides"
        exportBarButton = exportButton
        navigationItem.rightBarButtonItem = exportButton

        pages = makePages()
        pages.forEach { $0.apply(exportSize: selectedExportSize) }

        installPageViewController()
        installControls()
        installBadgeLayoutGestures()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installBadgeLayoutGestures()
    }

    private func makePages() -> [KanjiDecompositionCardPageViewController] {
        var result: [KanjiDecompositionCardPageViewController] = [
            KanjiDecompositionCardPageViewController(
                badgeLayoutStore: badgeLayoutStore,
                makeCardView: {
                    let cardView = KanjiDecompositionIntroCardView()
                    cardView.configure(word: self.word, partLabel: self.introPartLabel)
                    return cardView
                }
            ),
        ]

        for (index, character) in word.characters.enumerated() {
            result.append(
                KanjiDecompositionCardPageViewController(
                    badgeLayoutStore: badgeLayoutStore,
                    makeCardView: {
                        let cardView = KanjiDecompositionCharacterCardView(
                            badgeIdentifier: .character(index: index)
                        )
                        cardView.configure(character: character, excludingExpression: self.word.expression)
                        return cardView
                    }
                )
            )
        }

        result.append(
            KanjiDecompositionCardPageViewController(
                badgeLayoutStore: badgeLayoutStore,
                makeCardView: {
                    let cardView = KanjiDecompositionTeaserCardView()
                    cardView.configure(word: self.word)
                    return cardView
                }
            )
        )

        result.append(
            KanjiDecompositionCardPageViewController(
                badgeLayoutStore: badgeLayoutStore,
                makeCardView: {
                    let cardView = KanjiDecompositionCombinedCardView()
                    cardView.configure(word: self.word)
                    return cardView
                }
            )
        )

        return result
    }

    private func installPageViewController() {
        addChild(pageViewController)
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        pageViewController.dataSource = self
        pageViewController.delegate = self
        // Let the dimmed pager chrome show through around each page's viewfinder.
        pageViewController.view.backgroundColor = .clear
        pageViewController.view.subviews.forEach { $0.backgroundColor = .clear }
        view.addSubview(pageViewController.view)
        pageViewController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            pageViewController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        if let first = pages.first {
            pageViewController.setViewControllers([first], direction: .forward, animated: false)
        }
    }

    private func installControls() {
        sizeControl.translatesAutoresizingMaskIntoConstraints = false
        sizeControl.selectedSegmentIndex = KanjiDecompositionExportSize.allCases.firstIndex(of: selectedExportSize) ?? 0
        sizeControl.addAction(UIAction { [weak self] _ in
            self?.sizeControlChanged()
        }, for: .valueChanged)

        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.numberOfPages = pages.count
        pageControl.currentPage = 0
        pageControl.currentPageIndicatorTintColor = .label
        pageControl.pageIndicatorTintColor = UIColor.secondaryLabel.withAlphaComponent(0.35)
        pageControl.addAction(UIAction { [weak self] _ in
            self?.pageControlChanged()
        }, for: .valueChanged)

        view.addSubview(sizeControl)
        view.addSubview(pageControl)

        NSLayoutConstraint.activate([
            pageControl.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            sizeControl.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: -10),
            sizeControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            sizeControl.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            sizeControl.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            sizeControl.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    private func sizeControlChanged() {
        let index = sizeControl.selectedSegmentIndex
        guard KanjiDecompositionExportSize.allCases.indices.contains(index) else { return }
        selectedExportSize = KanjiDecompositionExportSize.allCases[index]
    }

    private func pageControlChanged() {
        let target = pageControl.currentPage
        guard pages.indices.contains(target), target != currentIndex else { return }
        let direction: UIPageViewController.NavigationDirection = target > currentIndex ? .forward : .reverse
        pageViewController.setViewControllers([pages[target]], direction: direction, animated: true) { [weak self] finished in
            guard let self, finished else { return }
            self.currentIndex = target
            self.syncBadgeLayoutGestures()
        }
    }

    private func syncBadgeLayoutGestures() {
        installBadgeLayoutGestures()
        if isPositioningBadges {
            selectedBadgeIdentifier = nil
            visiblePage()?.setBadgeEditingSelection(nil)
        }
    }

    private func updateCurrentIndex(from viewController: UIViewController) {
        guard let page = viewController as? KanjiDecompositionCardPageViewController,
              let index = pages.firstIndex(where: { $0 === page })
        else { return }
        currentIndex = index
        pageControl.currentPage = index
    }

    private func exportMenu() -> UIMenu {
        UIMenu(children: [
            UIMenu(title: "Save to Photos", options: .displayInline, children: [
                UIAction(title: "Current slide") { [weak self] _ in
                    self?.exportCurrentSlide()
                },
                UIAction(title: "All slides") { [weak self] _ in
                    self?.exportAllSlides()
                },
            ]),
            UIAction(
                title: "Hashtags",
                image: UIImage(systemName: "number")
            ) { [weak self] _ in
                self?.presentHashtagPicker()
            },
        ])
    }

    private func presentHashtagPicker() {
        let picker = KanjiDecompositionHashtagPickerViewController()
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    private func exportCurrentSlide() {
        guard pages.indices.contains(currentIndex) else { return }
        saveImagesToPhotos([
            pages[currentIndex].makeExportImage(
                size: selectedExportSize.canvasSize,
                in: view.window?.windowScene
            ),
        ])
    }

    private func exportAllSlides() {
        let windowScene = view.window?.windowScene
        let canvasSize = selectedExportSize.canvasSize
        let images = pages.map { page in
            page.makeExportImage(size: canvasSize, in: windowScene)
        }
        saveImagesToPhotos(images)
    }

    private func saveImagesToPhotos(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        photoSaveTotal = images.count
        pendingPhotoSaves = images.count
        photoSaveErrors.removeAll()
        for image in images {
            UIImageWriteToSavedPhotosAlbum(
                image,
                self,
                #selector(handleSaveCompletion(_:didFinishSavingWithError:contextInfo:)),
                nil
            )
        }
    }

    @objc private func handleSaveCompletion(
        _ image: UIImage,
        didFinishSavingWithError error: Error?,
        contextInfo: UnsafeRawPointer
    ) {
        if let error {
            photoSaveErrors.append(error)
        }

        pendingPhotoSaves -= 1
        guard pendingPhotoSaves <= 0 else { return }

        if photoSaveErrors.isEmpty {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            let savedCount = photoSaveTotal - photoSaveErrors.count
            let message: String
            if savedCount == 0 {
                message = photoSaveErrors.first?.localizedDescription ?? "Unknown error"
            } else {
                message = "Saved \(savedCount) of \(photoSaveTotal) photos."
            }
            let alert = UIAlertController(
                title: savedCount == 0 ? "Couldn’t save photos" : "Some photos couldn’t be saved",
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }

        photoSaveErrors.removeAll()
        pendingPhotoSaves = 0
        photoSaveTotal = 0
    }

    private func beginBadgePositioning(selecting identifier: KanjiDecompositionBadgeIdentifier? = nil) {
        isPositioningBadges = true
        selectedBadgeIdentifier = identifier
        setPageScrollingEnabled(false)
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Done",
            style: .done,
            target: self,
            action: #selector(endBadgePositioning)
        )
        navigationItem.rightBarButtonItem = nil
        pageControl.isEnabled = false
        visiblePage()?.setBadgeEditingSelection(identifier)
    }

    @objc private func endBadgePositioning() {
        isPositioningBadges = false
        selectedBadgeIdentifier = nil
        setPageScrollingEnabled(true)
        navigationItem.leftBarButtonItem = nil
        navigationItem.rightBarButtonItem = exportBarButton
        pageControl.isEnabled = true
        visiblePage()?.setBadgeEditingSelection(nil)
    }

    private func setPageScrollingEnabled(_ enabled: Bool) {
        for case let scrollView as UIScrollView in pageViewController.view.subviews {
            scrollView.isScrollEnabled = enabled
            scrollView.bounces = enabled
        }
    }

    private func presentPartLabelEditor() {
        let alert = UIAlertController(
            title: "Part label",
            message: "Shown above the question on slide 1.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = self.introPartLabel
            field.autocapitalizationType = .sentences
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard
                let self,
                let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty
            else { return }
            self.introPartLabel = text
            (self.pages.first?.cardView as? KanjiDecompositionIntroCardView)?.applyPartLabel(text)
        })
        present(alert, animated: true)
    }

    private func visiblePage() -> KanjiDecompositionCardPageViewController? {
        pageViewController.viewControllers?.first as? KanjiDecompositionCardPageViewController
    }

    private func installBadgeLayoutGestures() {
        removeBadgeLayoutGestures()
        guard let page = visiblePage() else { return }

        let target = page.cardView
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBadgeLayoutTap(_:)))
        tap.cancelsTouchesInView = false
        target.addGestureRecognizer(tap)
        badgeTapGesture = tap

        let longPress = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleBadgeLayoutLongPress(_:))
        )
        longPress.minimumPressDuration = 0.45
        longPress.cancelsTouchesInView = true
        target.addGestureRecognizer(longPress)
        badgeLongPressGesture = longPress

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleBadgeLayoutPan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = true
        target.addGestureRecognizer(pan)
        badgePanGesture = pan
    }

    private func removeBadgeLayoutGestures() {
        if let badgeTapGesture {
            badgeTapGesture.view?.removeGestureRecognizer(badgeTapGesture)
            self.badgeTapGesture = nil
        }
        if let badgeLongPressGesture {
            badgeLongPressGesture.view?.removeGestureRecognizer(badgeLongPressGesture)
            self.badgeLongPressGesture = nil
        }
        if let badgePanGesture {
            badgePanGesture.view?.removeGestureRecognizer(badgePanGesture)
            self.badgePanGesture = nil
        }
    }

    @objc private func handleBadgeLayoutTap(_ gesture: UITapGestureRecognizer) {
        guard let page = visiblePage() else { return }
        let point = gesture.location(in: page.cardView)

        if let intro = page.cardView as? KanjiDecompositionIntroCardView,
           intro.eyebrowContains(point: point, in: page.cardView) {
            presentPartLabelEditor()
            return
        }

        guard let host = page.badgeHost() else { return }
        for hero in host.characterHeroViews() where hero.badgeContains(point: point, in: page.cardView) {
            if isPositioningBadges {
                selectedBadgeIdentifier = hero.layoutIdentifier
                page.setBadgeEditingSelection(selectedBadgeIdentifier)
            } else {
                presentBadgeMeaningPicker(for: hero.layoutIdentifier)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }

        guard isPositioningBadges else { return }
        selectedBadgeIdentifier = nil
        page.setBadgeEditingSelection(nil)
    }

    @objc private func handleBadgeLayoutLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !isPositioningBadges, let page = visiblePage() else { return }
        let point = gesture.location(in: page.cardView)
        guard let host = page.badgeHost() else { return }
        for hero in host.characterHeroViews() where hero.badgeContains(point: point, in: page.cardView) {
            beginBadgePositioning(selecting: hero.layoutIdentifier)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return
        }
    }

    private func presentBadgeMeaningPicker(for identifier: KanjiDecompositionBadgeIdentifier) {
        guard let character = character(for: identifier) else { return }
        let kanji = String(character)
        let meanings = KanjidicStore.shared.detail(forKanji: kanji)?.meaningList ?? []
        guard !meanings.isEmpty else { return }

        let picker = KanjiDecompositionBadgeMeaningPickerViewController(
            kanji: kanji,
            meanings: meanings,
            selectedMeanings: KanjiDecompositionBadgeMeaningStore.shared.selectedMeanings(for: kanji)
        )
        picker.onSave = { [weak self] selected in
            guard let self else { return }
            KanjiDecompositionBadgeMeaningStore.shared.setSelectedMeanings(selected, for: kanji)
            self.applyBadgeMeaning(for: character)
        }

        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    private func character(for identifier: KanjiDecompositionBadgeIdentifier) -> Character? {
        let index: Int
        switch identifier {
        case .character(let i), .combinedPreview(let i):
            index = i
        }
        guard word.characters.indices.contains(index) else { return nil }
        return word.characters[index]
    }

    private func applyBadgeMeaning(for character: Character) {
        let kanji = String(character)
        let meaning = KanjidicStore.shared.detail(forKanji: kanji)?.badgeMeaning ?? ""
        for page in pages {
            guard let host = page.badgeHost() else { continue }
            for hero in host.characterHeroViews() {
                guard self.character(for: hero.layoutIdentifier) == character else { continue }
                hero.applyMeaning(meaning)
            }
        }
    }

    @objc private func handleBadgeLayoutPan(_ gesture: UIPanGestureRecognizer) {
        guard
            isPositioningBadges,
            let identifier = selectedBadgeIdentifier,
            let page = visiblePage(),
            let host = page.badgeHost(),
            let hero = host.characterHeroViews().first(where: { $0.layoutIdentifier == identifier })
        else { return }

        switch gesture.state {
        case .began:
            badgePanStartOffset = badgeLayoutStore.offset(for: identifier)
        case .changed:
            let translation = gesture.translation(in: page.cardView)
            let offset = CGPoint(
                x: badgePanStartOffset.x + translation.x,
                y: badgePanStartOffset.y + translation.y
            )
            badgeLayoutStore.setOffset(offset, for: identifier)
            hero.applyUserOffset(offset)
        default:
            break
        }
    }
}

// MARK: - UIPageViewControllerDataSource & Delegate

extension KanjiDecompositionPagerViewController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? KanjiDecompositionCardPageViewController,
              let index = pages.firstIndex(where: { $0 === page }),
              index > 0
        else { return nil }
        return pages[index - 1]
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? KanjiDecompositionCardPageViewController,
              let index = pages.firstIndex(where: { $0 === page }),
              index + 1 < pages.count
        else { return nil }
        return pages[index + 1]
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard finished, completed, let visible = pageViewController.viewControllers?.first else { return }
        updateCurrentIndex(from: visible)
        syncBadgeLayoutGestures()
    }
}

extension KanjiDecompositionPagerViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === badgePanGesture {
            return isPositioningBadges && selectedBadgeIdentifier != nil
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}

// MARK: - Page wrapper / export viewfinder

private final class KanjiDecompositionCardPageViewController: UIViewController {
    private let makeCardView: () -> UIView
    private let badgeLayoutStore: KanjiDecompositionBadgeLayoutStore
    private(set) var cardView: UIView
    private let viewfinderBorder = UIView()

    private var exportSize: KanjiDecompositionExportSize = .feedPortrait
    /// Bottom inset reserved so the viewfinder sits above the size + page controls.
    private let controlsClearance: CGFloat = 88

    init(badgeLayoutStore: KanjiDecompositionBadgeLayoutStore, makeCardView: @escaping () -> UIView) {
        self.badgeLayoutStore = badgeLayoutStore
        self.makeCardView = makeCardView
        let cardView = makeCardView()
        badgeLayoutStore.apply(to: cardView)
        self.cardView = cardView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        cardView.clipsToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = true
        cardView.autoresizingMask = []
        view.addSubview(cardView)

        viewfinderBorder.isUserInteractionEnabled = false
        viewfinderBorder.backgroundColor = .clear
        viewfinderBorder.layer.borderWidth = 1
        viewfinderBorder.layer.cornerCurve = .continuous
        viewfinderBorder.translatesAutoresizingMaskIntoConstraints = true
        viewfinderBorder.autoresizingMask = []
        view.addSubview(viewfinderBorder)
        applyBorderColor()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutViewfinder()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyBorderColor()
    }

    func apply(exportSize: KanjiDecompositionExportSize) {
        self.exportSize = exportSize
        view.setNeedsLayout()
    }

    /// Builds a fresh card view instance at the fixed export frame (independent of whatever
    /// size the live on-screen `cardView` currently has) and renders it to an image.
    @MainActor
    func makeExportImage(size: CGSize, in windowScene: UIWindowScene?) -> UIImage {
        let exportCardView = makeCardView()
        badgeLayoutStore.apply(to: exportCardView)
        return KanjiDecompositionExportRenderer.image(for: exportCardView, size: size, in: windowScene)
    }

    func badgeHost() -> KanjiDecompositionBadgeLayoutHost? {
        cardView as? KanjiDecompositionBadgeLayoutHost
    }

    func setBadgeEditingSelection(_ selectedIdentifier: KanjiDecompositionBadgeIdentifier?) {
        (cardView as? KanjiDecompositionCharacterCardView)?.setBadgeEditingSelection(selectedIdentifier)
        (cardView as? KanjiDecompositionTeaserCardView)?.setBadgeEditingSelection(selectedIdentifier)
        (cardView as? KanjiDecompositionCombinedCardView)?.setBadgeEditingSelection(selectedIdentifier)
    }

    private func layoutViewfinder() {
        let canvas = exportSize.canvasSize
        guard canvas.width > 0, canvas.height > 0, view.bounds.width > 0, view.bounds.height > 0 else { return }

        let available = view.bounds.inset(by: UIEdgeInsets(
            top: 16,
            left: 16,
            bottom: controlsClearance + 16,
            right: 16
        ))
        let scale = min(available.width / canvas.width, available.height / canvas.height)

        // Layout at the exact export canvas, then scale — same constraints export uses.
        cardView.transform = .identity
        cardView.bounds = CGRect(origin: .zero, size: canvas)
        cardView.center = CGPoint(x: available.midX, y: available.midY)
        cardView.layoutIfNeeded()
        cardView.transform = CGAffineTransform(scaleX: scale, y: scale)

        viewfinderBorder.transform = .identity
        let displaySize = CGSize(width: canvas.width * scale, height: canvas.height * scale)
        viewfinderBorder.bounds = CGRect(origin: .zero, size: displaySize)
        viewfinderBorder.center = cardView.center
        viewfinderBorder.layer.cornerRadius = 2
    }

    private func applyBorderColor() {
        viewfinderBorder.layer.borderColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.45)
                : UIColor(white: 0, alpha: 0.35)
        }.resolvedColor(with: traitCollection).cgColor
    }
}
