//
//  RegisterLadderPagerViewController.swift
//  shizen
//
//  Slideshow for one English idea said three ways (casual / polite / keigo),
//  then a why close. Matches Kanji Decomposition's UIPageViewController +
//  export viewfinder shell. Japanese on register slides is tap-to-edit.
//

import UIKit

final class RegisterLadderPagerViewController: UIViewController {

    private let deck: RegisterLadderDeck

    private let pageControl = UIPageControl()
    private let sizeControl = UISegmentedControl(
        items: ExperimentExportSize.allCases.map(\.shortTitle)
    )
    private let pageViewController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal
    )

    private var pages: [RegisterLadderCardPageViewController] = []
    private var currentIndex = 0
    private var pendingPhotoSaves = 0
    private var photoSaveTotal = 0
    private var photoSaveErrors: [Error] = []
    private var japaneseTapGesture: UITapGestureRecognizer?
    private var selectedExportSize: ExperimentExportSize = .story {
        didSet {
            guard selectedExportSize != oldValue else { return }
            pages.forEach { $0.apply(exportSize: selectedExportSize) }
        }
    }

    init(deck: RegisterLadderDeck) {
        self.deck = deck
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Register ladder"
        navigationItem.largeTitleDisplayMode = .never
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
        navigationItem.rightBarButtonItem = exportButton

        pages = makePages()
        pages.forEach { $0.apply(exportSize: selectedExportSize) }

        installPageViewController()
        installControls()
        installJapaneseTapGesture()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installJapaneseTapGesture()
    }

    private func makePages() -> [RegisterLadderCardPageViewController] {
        [
            RegisterLadderCardPageViewController {
                let cardView = RegisterLadderHookCardView()
                cardView.configure(english: self.deck.english)
                return cardView
            },
            RegisterLadderCardPageViewController {
                let cardView = RegisterLadderLevelCardView(register: .casual)
                cardView.configure(level: self.deck.casual)
                return cardView
            },
            RegisterLadderCardPageViewController {
                let cardView = RegisterLadderLevelCardView(register: .polite)
                cardView.configure(level: self.deck.polite)
                return cardView
            },
            RegisterLadderCardPageViewController {
                let cardView = RegisterLadderLevelCardView(register: .formal)
                cardView.configure(level: self.deck.formal)
                return cardView
            },
            RegisterLadderCardPageViewController {
                let cardView = RegisterLadderWhyCardView()
                cardView.configure(why: self.deck.why)
                return cardView
            },
        ]
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
            self.installJapaneseTapGesture()
        }
    }

    private func updateCurrentIndex(from viewController: UIViewController) {
        guard let page = viewController as? RegisterLadderCardPageViewController,
              let index = pages.firstIndex(where: { $0 === page })
        else { return }
        currentIndex = index
        pageControl.currentPage = index
    }

    // MARK: - Tap-to-edit Japanese

    private func installJapaneseTapGesture() {
        removeJapaneseTapGesture()
        guard let page = visiblePage() else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleJapaneseTap(_:)))
        tap.cancelsTouchesInView = false
        page.cardView.addGestureRecognizer(tap)
        japaneseTapGesture = tap
    }

    private func removeJapaneseTapGesture() {
        if let japaneseTapGesture {
            japaneseTapGesture.view?.removeGestureRecognizer(japaneseTapGesture)
            self.japaneseTapGesture = nil
        }
    }

    @objc private func handleJapaneseTap(_ gesture: UITapGestureRecognizer) {
        guard let page = visiblePage(),
              let levelCard = page.cardView as? RegisterLadderLevelCardView
        else { return }
        let point = gesture.location(in: page.cardView)
        guard levelCard.japaneseContains(point: point, in: page.cardView) else { return }
        presentJapaneseEditor(for: levelCard.register)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func presentJapaneseEditor(for register: RegisterLadderDeck.Register) {
        let current = deck.level(for: register).japanese
        let alert = UIAlertController(
            title: "Edit \(register.title)",
            message: "Japanese shown on this slide.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = current
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard
                let self,
                let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty
            else { return }
            self.deck.setJapanese(text, for: register)
            if let levelCard = self.visiblePage()?.cardView as? RegisterLadderLevelCardView,
               levelCard.register == register {
                levelCard.applyJapanese(text)
            }
        })
        present(alert, animated: true)
    }

    private func visiblePage() -> RegisterLadderCardPageViewController? {
        pageViewController.viewControllers?.first as? RegisterLadderCardPageViewController
    }

    // MARK: - Export

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
        let picker = RegisterLadderHashtagPickerViewController()
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
}

// MARK: - UIPageViewControllerDataSource & Delegate

extension RegisterLadderPagerViewController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? RegisterLadderCardPageViewController,
              let index = pages.firstIndex(where: { $0 === page }),
              index > 0
        else { return nil }
        return pages[index - 1]
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? RegisterLadderCardPageViewController,
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
        installJapaneseTapGesture()
    }
}

// MARK: - Page wrapper / export viewfinder

private final class RegisterLadderCardPageViewController: UIViewController {
    private let makeCardView: () -> UIView
    private(set) var cardView: UIView
    private let viewfinderBorder = UIView()

    private var exportSize: ExperimentExportSize = .feedPortrait
    private let controlsClearance: CGFloat = 88

    init(makeCardView: @escaping () -> UIView) {
        self.makeCardView = makeCardView
        self.cardView = makeCardView()
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
        viewfinderBorder.layer.borderColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.45)
                : UIColor(white: 0, alpha: 0.35)
        }.resolvedColor(with: traitCollection).cgColor
    }
}
