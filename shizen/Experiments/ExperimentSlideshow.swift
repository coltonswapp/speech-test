//
//  ExperimentSlideshow.swift
//  shizen
//
//  Shared TikTok slideshow shell: horizontal swiping, export viewfinder,
//  Photos save, and the hashtag sheet. A new format subclasses
//  `ExperimentSlideshowViewController`, implements `makeSlideshowPages()`,
//  and overrides `recommendedHashtags` when its tag list differs.
//  Per-slide editing (tap a label, drag a badge) hooks `slideshowDidShowPage()`.
//

import UIKit

// MARK: - Chrome

enum ExperimentSlideshowChrome {
    /// Dimmed stage behind the export viewfinder.
    static let stageBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.06, alpha: 1)
            : UIColor(white: 0.78, alpha: 1)
    }

    static let viewfinderBorder = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.45)
            : UIColor(white: 0, alpha: 0.35)
    }
}

enum ExperimentSlideWatermark {
    enum Placement {
        case top
        case bottom
    }

    /// Pins `shizenapp.com` to the top or bottom center of a slide.
    static func install(in host: UIView, placement: Placement = .bottom) {
        let label = UILabel()
        label.text = "shizenapp.com"
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = UIColor.secondaryLabel.withAlphaComponent(0.65)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(label)

        var constraints = [
            label.centerXAnchor.constraint(equalTo: host.centerXAnchor),
        ]
        switch placement {
        case .top:
            constraints.append(label.topAnchor.constraint(equalTo: host.topAnchor, constant: 16))
        case .bottom:
            constraints.append(label.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -14))
        }
        NSLayoutConstraint.activate(constraints)
    }
}

enum ExperimentHashtags {
    static let kanji = [
        "#learnjapanese",
        "#japanese",
        "#studytok",
        "#jlpt",
        "#kanji",
        "#nihongo",
        "#japaneselanguage",
        "#studyjapanese",
        "#日本語",
        "#languagelearning",
    ]

    static let registerLadder = [
        "#learnjapanese",
        "#japanese",
        "#keigo",
        "#丁寧語",
        "#studytok",
        "#jlpt",
        "#nihongo",
        "#japaneselanguage",
        "#studyjapanese",
        "#日本語",
        "#languagelearning",
        "#politeness",
    ]

    static let dialogue = [
        "#learnjapanese",
        "#japanese",
        "#nihongo",
        "#studytok",
        "#japaneseconversation",
        "#jlpt",
        "#japaneselanguage",
        "#studyjapanese",
        "#日本語",
        "#languagelearning",
    ]
}

// MARK: - Slideshow

/// Horizontal card slideshow with an export-size control and a Photos export menu.
///
/// Subclasses build pages in `makeSlideshowPages()`. The live card and the image
/// saved to Photos both come from that page's card factory, laid out at the canvas
/// point size, so the viewfinder matches the export.
class ExperimentSlideshowViewController: UIViewController {

    private let pageControl = UIPageControl()
    private let sizeControl = UISegmentedControl(
        items: ExperimentExportSize.allCases.map(\.shortTitle)
    )
    private let pageViewController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal
    )

    private(set) var pages: [ExperimentSlidePageViewController] = []
    private(set) var currentIndex = 0
    private(set) var exportBarButton: UIBarButtonItem?
    private var pendingPhotoSaves = 0
    private var photoSaveTotal = 0
    private var photoSaveErrors: [Error] = []

    private(set) var selectedExportSize: ExperimentExportSize = .story {
        didSet {
            guard selectedExportSize != oldValue else { return }
            pages.forEach { $0.apply(exportSize: selectedExportSize) }
        }
    }

    /// Tags offered from the export menu. Empty hides the Hashtags item.
    var recommendedHashtags: [String] { [] }

    /// Menu rows inserted above Save to Photos. Built each time the menu opens.
    func additionalExportMenuChildren() -> [UIMenuElement] { [] }

    /// Shown above the export-size control. Return the same instance every call.
    func supplementaryPreviewControl() -> UIView? { nil }

    func makeSlideshowPages() -> [ExperimentSlidePageViewController] {
        fatalError("Subclasses must implement makeSlideshowPages()")
    }

    /// Reinstall gestures for the page now on screen. Also called from `viewDidAppear`.
    func slideshowDidShowPage() {}

    /// A swipe or page-dot change finished. Default reinstalls page gestures.
    func slideshowDidFinishPageTransition() {
        slideshowDidShowPage()
    }

    /// Every photo in the last save landed in the library.
    func slideshowDidSaveAllPhotos() {}

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentSlideshowChrome.stageBackground

        installExportButton()
        pages = makeSlideshowPages()
        applyPreviewChrome()
        installPageViewController()
        installControls()
        slideshowDidShowPage()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        slideshowDidShowPage()
    }

    func visiblePage() -> ExperimentSlidePageViewController? {
        pageViewController.viewControllers?.first as? ExperimentSlidePageViewController
    }

    func replacePages(with newPages: [ExperimentSlidePageViewController]) {
        pages = newPages
        currentIndex = 0
        applyPreviewChrome()
        pageControl.numberOfPages = pages.count
        pageControl.currentPage = 0
        if let first = pages.first {
            pageViewController.setViewControllers([first], direction: .forward, animated: false)
        }
        slideshowDidShowPage()
    }

    func setPageScrollingEnabled(_ enabled: Bool) {
        for case let scrollView as UIScrollView in pageViewController.view.subviews {
            scrollView.isScrollEnabled = enabled
            scrollView.bounces = enabled
        }
    }

    func setPageControlEnabled(_ enabled: Bool) {
        pageControl.isEnabled = enabled
    }

    func restoreExportButton() {
        navigationItem.rightBarButtonItem = exportBarButton
    }

    func hideExportButton() {
        navigationItem.rightBarButtonItem = nil
    }

    private func installExportButton() {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            menu: UIMenu(children: [
                UIDeferredMenuElement.uncached { [weak self] completion in
                    completion(self?.exportMenuChildren() ?? [])
                },
            ])
        )
        button.accessibilityLabel = "Export slides"
        exportBarButton = button
        navigationItem.rightBarButtonItem = button
    }

    private func exportMenuChildren() -> [UIMenuElement] {
        var children = additionalExportMenuChildren()
        children.append(
            UIMenu(title: "Save to Photos", options: .displayInline, children: [
                UIAction(title: "Current slide") { [weak self] _ in
                    self?.exportCurrentSlide()
                },
                UIAction(title: "All slides") { [weak self] _ in
                    self?.exportAllSlides()
                },
            ])
        )
        if !recommendedHashtags.isEmpty {
            children.append(
                UIAction(
                    title: "Hashtags",
                    image: UIImage(systemName: "number")
                ) { [weak self] _ in
                    self?.presentHashtagPicker()
                }
            )
        }
        return children
    }

    private func presentHashtagPicker() {
        ExperimentHashtagPickerViewController.present(
            hashtags: recommendedHashtags,
            from: self
        )
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
            slideshowDidSaveAllPhotos()
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

    private func installPageViewController() {
        addChild(pageViewController)
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        pageViewController.dataSource = self
        pageViewController.delegate = self
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

    private func applyPreviewChrome() {
        let clearance: CGFloat = supplementaryPreviewControl() == nil ? 88 : 132
        pages.forEach { page in
            page.controlsClearance = clearance
            page.apply(exportSize: selectedExportSize)
        }
    }

    private func installControls() {
        sizeControl.translatesAutoresizingMaskIntoConstraints = false
        sizeControl.selectedSegmentIndex = ExperimentExportSize.allCases.firstIndex(of: selectedExportSize) ?? 0
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

        var constraints = [
            pageControl.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            sizeControl.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: -10),
            sizeControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            sizeControl.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            sizeControl.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            sizeControl.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ]

        if let extra = supplementaryPreviewControl() {
            extra.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(extra)
            constraints.append(contentsOf: [
                extra.bottomAnchor.constraint(equalTo: sizeControl.topAnchor, constant: -10),
                extra.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                extra.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
                extra.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
                extra.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            ])
        }

        NSLayoutConstraint.activate(constraints)
    }

    private func sizeControlChanged() {
        let index = sizeControl.selectedSegmentIndex
        guard ExperimentExportSize.allCases.indices.contains(index) else { return }
        selectedExportSize = ExperimentExportSize.allCases[index]
    }

    private func pageControlChanged() {
        let target = pageControl.currentPage
        guard pages.indices.contains(target), target != currentIndex else { return }
        let direction: UIPageViewController.NavigationDirection = target > currentIndex ? .forward : .reverse
        pageViewController.setViewControllers([pages[target]], direction: direction, animated: true) { [weak self] finished in
            guard let self, finished else { return }
            self.currentIndex = target
            self.slideshowDidFinishPageTransition()
        }
    }

    private func updateCurrentIndex(from viewController: UIViewController) {
        guard let page = viewController as? ExperimentSlidePageViewController,
              let index = pages.firstIndex(where: { $0 === page })
        else { return }
        currentIndex = index
        pageControl.currentPage = index
    }
}

extension ExperimentSlideshowViewController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? ExperimentSlidePageViewController,
              let index = pages.firstIndex(where: { $0 === page }),
              index > 0
        else { return nil }
        return pages[index - 1]
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? ExperimentSlidePageViewController,
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
        slideshowDidFinishPageTransition()
    }
}

// MARK: - Page / viewfinder

/// One slide. `makeCardView` rebuilds the card for Photos export at the canvas size.
/// `prepareCard` runs on both the live card and that export rebuild (badge offsets, etc.).
final class ExperimentSlidePageViewController: UIViewController {
    private let makeCardView: () -> UIView
    private let prepareCard: ((UIView) -> Void)?
    private(set) var cardView: UIView
    private let viewfinderBorder = UIView()

    private var exportSize: ExperimentExportSize = .feedPortrait
    /// Matches the slideshow's control stack so the frame clears the size control and dots.
    var controlsClearance: CGFloat = 88 {
        didSet {
            guard controlsClearance != oldValue else { return }
            view.setNeedsLayout()
        }
    }

    init(makeCardView: @escaping () -> UIView, prepareCard: ((UIView) -> Void)? = nil) {
        self.makeCardView = makeCardView
        self.prepareCard = prepareCard
        let cardView = makeCardView()
        prepareCard?(cardView)
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

    func apply(exportSize: ExperimentExportSize) {
        self.exportSize = exportSize
        view.setNeedsLayout()
    }

    @MainActor
    func makeExportImage(size: CGSize, in windowScene: UIWindowScene?) -> UIImage {
        let exportCardView = makeCardView()
        prepareCard?(exportCardView)
        return ExperimentSlideExportRenderer.image(for: exportCardView, size: size, in: windowScene)
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
        viewfinderBorder.layer.borderColor = ExperimentSlideshowChrome.viewfinderBorder
            .resolvedColor(with: traitCollection).cgColor
    }
}

// MARK: - Hashtags

/// Sheet of recommended hashtags. Select up to five, then copy them in tap order.
final class ExperimentHashtagPickerViewController: UITableViewController {

    private static let maxSelections = 5

    private let hashtags: [String]
    private var selectedInOrder: [String] = []

    init(hashtags: [String]) {
        self.hashtags = hashtags
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func present(hashtags: [String], from presenter: UIViewController) {
        guard !hashtags.isEmpty else { return }
        let picker = ExperimentHashtagPickerViewController(hashtags: hashtags)
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        presenter.present(nav, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Hashtags"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Copy",
            style: .done,
            target: self,
            action: #selector(copyTapped)
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        updateCopyEnabled()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        hashtags.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Recommended"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Choose up to \(Self.maxSelections). Copy pastes them in the order you selected."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let tag = hashtags[indexPath.row]
        var config = UIListContentConfiguration.cell()
        config.text = tag
        cell.contentConfiguration = config
        cell.accessoryType = selectedInOrder.contains(tag) ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let tag = hashtags[indexPath.row]
        if let index = selectedInOrder.firstIndex(of: tag) {
            selectedInOrder.remove(at: index)
        } else {
            guard selectedInOrder.count < Self.maxSelections else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }
            selectedInOrder.append(tag)
        }
        tableView.reloadData()
        updateCopyEnabled()
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func copyTapped() {
        guard !selectedInOrder.isEmpty else { return }
        UIPasteboard.general.string = selectedInOrder.joined(separator: " ")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss(animated: true)
    }

    private func updateCopyEnabled() {
        navigationItem.rightBarButtonItem?.isEnabled = !selectedInOrder.isEmpty
    }
}
