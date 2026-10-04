//
//  LessonScenarioPickerViewController.swift
//  shizen
//
//  Lesson screen between the path and the dialogue player: hero, curriculum
//  chips, and a sequential list of scenes. The bottom-right play button opens
//  the first scene. The options menu unlocks every scene for preview and can
//  reset progress for the lesson or for one scene.
//

import UIKit

final class LessonScenarioPickerViewController: UIViewController, UIScrollViewDelegate {

    private let collectionID: String
    private let fallbackTitle: String?
    private var collection: DialogueScenarioCollection?

    /// When set, opening an unlocked scene calls this instead of pushing the player.
    var onOpenScenario: ((DialogueScenarioCollection, String) -> Void)?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let heroView = LessonHeroView()
    private let bodyStack = UIStackView()
    private let chipRow = LessonMetaChipRow()
    private let titleLabel = UILabel()
    private let summaryLabel = UILabel()
    private let scenesStack = UIStackView()
    private let playButton = GlassIconButton(
        symbolName: "play.fill",
        pointSize: 22,
        tintColor: .systemYellow,
        accessibilityLabel: "Start lesson"
    )
    private let loadingCoordinator = DialogueLessonLoadingCoordinator()
    private var scenarioRows: [LessonSceneRow] = []
    private var contentBottomConstraint: NSLayoutConstraint?
    private var loadedHeroKey: String?
    private var lessonNavigationTitle: String?
    private var isNavigationBarShown = false
    /// Local preview gate. Locked scenes open without marking them complete.
    private var previewsAllScenes = false
    private var progressObserver: NSObjectProtocol?
    private let topScrollEdgeInteraction: UIScrollEdgeElementContainerInteraction = {
        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.edge = .top
        return interaction
    }()

    private static let horizontalInset: CGFloat = 20
    private static let heroHeightRatio: CGFloat = 0.42
    private static let sceneTitlePlaceholder = "Some title of a scene"
    /// Last resort when the public export has no subtitle. Premise is not in that export.
    private static let summaryPlaceholder = "In this lesson, Kaito is traveling somewhere via train. He'll have to navigate to the station, by a ticket, & even deal with a platform change."

    init(collectionID: String, fallbackTitle: String? = nil, unlockAllScenesForQA: Bool = false) {
        self.collectionID = collectionID
        self.fallbackTitle = fallbackTitle
        self.previewsAllScenes = unlockAllScenesForQA
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let progressObserver {
            NotificationCenter.default.removeObserver(progressObserver)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.pageBackground
        configureNavigationBar()
        configureScrollView()
        configurePlayButton()
        progressObserver = NotificationCenter.default.addObserver(
            forName: DialogueProgressStore.didChange,
            object: DialogueProgressStore.shared,
            queue: .main
        ) { [weak self] _ in
            self?.refreshSceneAccess()
            self?.refreshOptionsMenu()
        }

        loadingCoordinator.attach(to: view)
        loadingCoordinator.beginLoading()
        DialogueScenarioCollectionCatalog.fetchCollection(id: collectionID) { [weak self] collection in
            guard let self else { return }
            if let collection {
                self.applyCollection(collection) {
                    self.loadingCoordinator.finishLoading()
                }
            } else if self.collection == nil {
                self.loadingCoordinator.finishLoading {
                    self.showLoadFailure()
                }
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DialogueProgressStore.shared.reload()
        refreshSceneAccess()
        refreshOptionsMenu()
        attachTopScrollEdgeInteraction()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.navigationBar.removeInteraction(topScrollEdgeInteraction)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        let insets = view.safeAreaInsets
        contentBottomConstraint?.constant = -(insets.bottom + 96)
        scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(
            top: insets.top,
            left: 0,
            bottom: insets.bottom + 72,
            right: 0
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateNavigationBarForScroll()
    }

    // MARK: - Layout

    private func configureNavigationBar() {
        title = nil
        navigationItem.title = nil
        navigationItem.largeTitleDisplayMode = .never

        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        navigationItem.compactScrollEdgeAppearance = appearance

        let options = UIBarButtonItem(
            title: nil,
            image: UIImage(systemName: "ellipsis.circle"),
            primaryAction: nil,
            menu: makeOptionsMenu()
        )
        options.accessibilityLabel = "Lesson options"
        navigationItem.rightBarButtonItem = options
    }

    private func attachTopScrollEdgeInteraction() {
        guard let navigationBar = navigationController?.navigationBar else { return }
        topScrollEdgeInteraction.scrollView = scrollView
        guard !navigationBar.interactions.contains(where: { $0 === topScrollEdgeInteraction }) else { return }
        navigationBar.addInteraction(topScrollEdgeInteraction)
    }

    private func configureScrollView() {
        scrollView.alwaysBounceVertical = true
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.topEdgeEffect.style = .soft
        scrollView.topEdgeEffect.isHidden = true
        topScrollEdgeInteraction.scrollView = scrollView
        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 0
        contentStack.clipsToBounds = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        heroView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(heroView)
        contentStack.setCustomSpacing(-LessonMetaChip.singleLineHeight / 2, after: heroView)

        bodyStack.axis = .vertical
        bodyStack.alignment = .fill
        bodyStack.spacing = 8
        bodyStack.isLayoutMarginsRelativeArrangement = true
        bodyStack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 0,
            leading: Self.horizontalInset,
            bottom: 8,
            trailing: Self.horizontalInset
        )
        bodyStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(bodyStack)

        chipRow.translatesAutoresizingMaskIntoConstraints = false
        chipRow.setContentHuggingPriority(.required, for: .vertical)
        chipRow.setContentCompressionResistancePriority(.required, for: .vertical)
        bodyStack.addArrangedSubview(chipRow)
        bodyStack.setCustomSpacing(16, after: chipRow)

        titleLabel.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(
            for: .systemFont(ofSize: 32, weight: .bold)
        )
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        titleLabel.text = fallbackTitle
        bodyStack.addArrangedSubview(titleLabel)
        bodyStack.setCustomSpacing(8, after: titleLabel)

        summaryLabel.font = .preferredFont(forTextStyle: .body)
        summaryLabel.adjustsFontForContentSizeCategory = true
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.numberOfLines = 0
        bodyStack.addArrangedSubview(summaryLabel)
        bodyStack.setCustomSpacing(28, after: summaryLabel)

        scenesStack.axis = .vertical
        scenesStack.alignment = .fill
        scenesStack.spacing = 28
        bodyStack.addArrangedSubview(scenesStack)

        let bottom = contentStack.bottomAnchor.constraint(
            equalTo: scrollView.contentLayoutGuide.bottomAnchor,
            constant: -120
        )
        contentBottomConstraint = bottom

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            bottom,
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            heroView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: Self.heroHeightRatio),
        ])
    }

    private func configurePlayButton() {
        playButton.isHidden = true
        playButton.addAction(UIAction { [weak self] _ in
            self?.openFirstScene()
        }, for: .touchUpInside)
        view.addSubview(playButton)

        NSLayoutConstraint.activate([
            playButton.widthAnchor.constraint(equalToConstant: 56),
            playButton.heightAnchor.constraint(equalToConstant: 56),
            playButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            playButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    // MARK: - Content

    /// Lays the lesson out under the loading cover. `whenReady` runs once the hero and every scene thumbnail have settled, so the title and rows appear together.
    private func applyCollection(
        _ collection: DialogueScenarioCollection,
        whenReady: @escaping () -> Void
    ) {
        self.collection = collection

        let trimmedTitle = collection.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lessonTitle = trimmedTitle.isEmpty ? (fallbackTitle ?? "Lesson") : trimmedTitle
        titleLabel.text = lessonTitle
        lessonNavigationTitle = lessonTitle

        let subtitle = collection.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        summaryLabel.text = subtitle.isEmpty ? Self.summaryPlaceholder : subtitle

        let unit = resolvedLessonUnit(for: collection)
        if isNavigationBarShown {
            navigationItem.title = lessonNavigationTitle
        }
        chipRow.setTitles(chipTitles(sceneCount: collection.scenarios.count, unit: unit))
        rebuildSceneRows(for: collection)
        playButton.isHidden = collection.scenarios.isEmpty
        refreshSceneAccess()
        refreshOptionsMenu()

        let gate = LessonImageReadyGate(count: 1 + scenarioRows.count, completion: whenReady)
        loadHeroImage(for: collection, completion: gate.arrive)
        for (row, scenario) in zip(scenarioRows, collection.scenarios) {
            LessonImageLoading.apply(
                primaryURL: scenario.thumbnailURL,
                fallbackURL: collection.thumbnailURL,
                bundledName: collection.sceneImageName,
                pixelSize: 720,
                to: row.thumbnailView,
                completion: gate.arrive
            )
        }
    }

    private struct ResolvedLessonUnit {
        var title: String?
        var jlptLevel: Int?
    }

    /// Detail export fields win. The lesson index (`units[]` + `collections[].unitId`)
    /// fills anything the detail response has not loaded yet. Unfiled lessons omit both chips.
    private func resolvedLessonUnit(for collection: DialogueScenarioCollection) -> ResolvedLessonUnit {
        var title = Self.nonEmpty(collection.unitTitle)
        var level = collection.jlptLevel.flatMap(Self.validJLPTLevel)

        let index = ContentCMSClient.cachedDialogueLessonIndex()
        let listedUnitId = index?.lessons.first { $0.id == collectionID }?.unitId
        let unitId = Self.nonEmpty(collection.unitId) ?? Self.nonEmpty(listedUnitId)
        if let unitId, let unit = index?.units.first(where: { $0.id == unitId }) {
            if title == nil {
                title = Self.nonEmpty(unit.title)
            }
            if level == nil {
                level = Self.validJLPTLevel(unit.jlptLevel)
            }
        }
        return ResolvedLessonUnit(title: title, jlptLevel: level)
    }

    private func chipTitles(sceneCount: Int, unit: ResolvedLessonUnit) -> [String] {
        var titles: [String] = []
        if let level = unit.jlptLevel {
            titles.append("N\(level)")
        }
        if let title = unit.title {
            titles.append(title)
        }
        titles.append(sceneCount == 1 ? "1 Scene" : "\(sceneCount) Scenes")
        return titles
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Public export uses 5 = N5 … 1 = N1.
    private static func validJLPTLevel(_ level: Int) -> Int? {
        (1 ... 5).contains(level) ? level : nil
    }

    /// Published-take length as m:ss. Nil omits the time on the scene row.
    private static func formattedSceneDuration(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Shows the bar, titled with the lesson, once the in-content lesson title has moved above it.
    private func updateNavigationBarForScroll() {
        guard titleLabel.bounds.height > 0, let bar = navigationController?.navigationBar else { return }
        let titleFrame = titleLabel.convert(titleLabel.bounds, to: view)
        let showsBar = titleFrame.maxY <= bar.frame.maxY
        guard showsBar != isNavigationBarShown else { return }
        isNavigationBarShown = showsBar

        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationItem.title = showsBar ? lessonNavigationTitle : nil
        scrollView.topEdgeEffect.isHidden = !showsBar
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        navigationItem.compactScrollEdgeAppearance = appearance
    }

    private func loadHeroImage(
        for collection: DialogueScenarioCollection,
        completion: @escaping () -> Void
    ) {
        let key = collection.thumbnailURL?.absoluteString ?? collection.sceneImageName ?? ""
        if key == loadedHeroKey, heroView.imageView.image != nil || key.isEmpty {
            completion()
            return
        }
        loadedHeroKey = key
        heroView.imageView.image = nil
        LessonImageLoading.apply(
            primaryURL: collection.thumbnailURL,
            fallbackURL: nil,
            bundledName: collection.sceneImageName,
            pixelSize: 1200,
            to: heroView.imageView,
            completion: completion
        )
    }

    private func rebuildSceneRows(for collection: DialogueScenarioCollection) {
        for view in scenesStack.arrangedSubviews {
            scenesStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        scenarioRows = []

        for (index, scenario) in collection.scenarios.enumerated() {
            let trimmedTitle = scenario.menuTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let row = LessonSceneRow(
                sceneNumber: index + 1,
                title: trimmedTitle.isEmpty ? Self.sceneTitlePlaceholder : trimmedTitle,
                durationText: Self.formattedSceneDuration(scenario.durationSeconds)
            )
            row.onOpen = { [weak self] in
                self?.openScenario(id: scenario.id, mode: .attempt)
            }
            row.onStudy = { [weak self] in
                self?.openScenario(id: scenario.id, mode: .viewLesson)
            }
            row.onReplay = { [weak self] in
                let mode: DialogueLessonSessionMode = scenario.quiz.isEmpty ? .attempt : .retakeQuiz
                self?.openScenario(id: scenario.id, mode: mode)
            }
            scenesStack.addArrangedSubview(row)
            scenarioRows.append(row)
        }
    }

    private func refreshSceneAccess() {
        guard let collection else { return }
        for (row, scenario) in zip(scenarioRows, collection.scenarios) {
            let stars = DialogueProgressStore.shared.displayedStarCount(scenarioID: scenario.id)
            row.apply(access: access(for: scenario.id, in: collection), starCount: stars)
        }
    }

    private func access(
        for scenarioID: String,
        in collection: DialogueScenarioCollection
    ) -> LessonSceneRow.Access {
        let store = DialogueProgressStore.shared
        guard let index = collection.scenarios.firstIndex(where: { $0.id == scenarioID }) else {
            return .locked
        }
        if store.isCompleted(scenarioID: scenarioID) {
            return .completed
        }
        let firstIncomplete = collection.scenarios.firstIndex {
            !store.isCompleted(scenarioID: $0.id)
        }
        if index == firstIncomplete {
            return .next
        }
        return previewsAllScenes ? .preview : .locked
    }

    private func refreshOptionsMenu() {
        navigationItem.rightBarButtonItem?.menu = makeOptionsMenu()
    }

    private func makeOptionsMenu() -> UIMenu {
        let unlock = UIAction(
            title: "Unlock all scenes",
            image: UIImage(systemName: previewsAllScenes ? "lock.open.fill" : "lock.open"),
            state: previewsAllScenes ? .on : .off
        ) { [weak self] _ in
            guard let self else { return }
            self.previewsAllScenes.toggle()
            self.refreshSceneAccess()
            self.refreshOptionsMenu()
        }

        let store = DialogueProgressStore.shared
        let scenarioIDs = Set(collection?.scenarios.map(\.id) ?? [])
        let lessonHasProgress = scenarioIDs.contains { store.hasRecordedProgress(scenarioID: $0) }
        let resetLesson = UIAction(
            title: "Entire lesson",
            image: UIImage(systemName: "arrow.counterclockwise"),
            attributes: lessonHasProgress ? .destructive : .disabled
        ) { [weak self] _ in
            self?.resetProgress(for: scenarioIDs)
        }

        var sceneResets: [UIMenuElement] = []
        for (index, scenario) in (collection?.scenarios ?? []).enumerated() {
            let hasProgress = store.hasRecordedProgress(scenarioID: scenario.id)
            let title = sceneMenuTitle(number: index + 1, title: scenario.menuTitle)
            sceneResets.append(UIAction(
                title: title,
                attributes: hasProgress ? .destructive : .disabled
            ) { [weak self] _ in
                self?.resetProgress(for: [scenario.id])
            })
        }

        var resetChildren: [UIMenuElement] = [
            UIMenu(options: .displayInline, children: [resetLesson]),
        ]
        if !sceneResets.isEmpty {
            resetChildren.append(UIMenu(options: .displayInline, children: sceneResets))
        }
        let resetMenu = UIMenu(
            title: "Reset progress",
            image: UIImage(systemName: "arrow.counterclockwise"),
            children: resetChildren
        )
        let note = UIAction(
            title: "Note",
            subtitle: lessonNavigationTitle ?? fallbackTitle ?? "Comment + Studio link for an agent",
            image: UIImage(systemName: "square.and.pencil")
        ) { [weak self] _ in
            self?.presentContentQANote()
        }
        let qaMenu = UIMenu(
            title: "QA",
            image: UIImage(systemName: "checklist"),
            children: [note]
        )
        return UIMenu(children: [qaMenu, unlock, resetMenu])
    }

    private func presentContentQANote() {
        let lessonTitle = lessonNavigationTitle
            ?? fallbackTitle
            ?? collection?.title
            ?? collectionID
        DialogueContentQANoteViewController.present(
            from: self,
            source: .dialogue,
            sourceId: collectionID,
            focusTitle: "Lesson",
            focusDetailLines: lessonQAFocusDetailLines(),
            lessonTitle: lessonTitle,
            lessonID: collectionID,
            studioLink: ContentCMSClient.studioLessonEditorLink(collectionId: collectionID)
        )
    }

    /// Lesson-wide context: curriculum chips plus the scene list. No Scene line
    /// is attached, so agents treat this as the collection rather than one slug.
    private func lessonQAFocusDetailLines() -> [String] {
        guard let collection else {
            return ["Lesson not loaded yet"]
        }
        var details: [String] = []
        let unit = resolvedLessonUnit(for: collection)
        if let level = unit.jlptLevel {
            details.append("JLPT: N\(level)")
        }
        if let title = unit.title {
            details.append("Unit: \(title)")
        }
        if let subtitle = collection.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !subtitle.isEmpty {
            details.append("Summary: \(subtitle)")
        }
        if collection.scenarios.isEmpty {
            details.append("Scenes: none")
        } else {
            details.append("Scenes (\(collection.scenarios.count)):")
            for (index, scenario) in collection.scenarios.enumerated() {
                details.append(sceneMenuTitle(number: index + 1, title: scenario.menuTitle))
            }
        }
        return details
    }

    private func sceneMenuTitle(number: Int, title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? Self.sceneTitlePlaceholder : trimmed
        return "Scene \(number) · \(name)"
    }

    private func resetProgress(for scenarioIDs: Set<String>) {
        DialogueProgressStore.shared.resetScenarios(scenarioIDs)
        refreshSceneAccess()
        refreshOptionsMenu()
    }

    private func showLoadFailure() {
        let alert = UIAlertController(
            title: "Couldn’t load lesson",
            message: "Failed to fetch “\(collectionID)” from \(ContentCMSClient.baseURL?.absoluteString ?? "the CMS"). Rebuild the app and force-quit so it isn’t using a cached lesson JSON.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    private func openFirstScene() {
        guard let id = collection?.scenarios.first?.id else { return }
        let completed = DialogueProgressStore.shared.isCompleted(scenarioID: id)
        openScenario(id: id, mode: completed ? .viewLesson : .attempt)
    }

    private func openScenario(id: String, mode: DialogueLessonSessionMode) {
        guard let collection else { return }
        guard access(for: id, in: collection) != .locked else { return }
        if let onOpenScenario {
            onOpenScenario(collection, id)
            return
        }
        let dialogue = DialogueNestedPagingExperimentViewController(
            collection: collection,
            initialScenarioID: id,
            sessionMode: mode
        )
        navigationController?.pushViewController(dialogue, animated: true)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        heroView.applyOverscroll(max(0, -scrollView.contentOffset.y))
        updateNavigationBarForScroll()
    }
}

// MARK: - Hero

private final class LessonHeroView: UIView {

    /// Holds the loaded bitmap. Not in the layout hierarchy — the visible pixels
    /// are `imageLayer`, so stretching it cannot change the scroll content size.
    let imageView = UIImageView()
    private let fadeView = LessonHeroFadeView()
    private let imageLayer = CALayer()
    private var pull: CGFloat = 0
    private var imageObservation: NSKeyValueObservation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        layer.masksToBounds = false

        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        imageLayer.zPosition = -1
        imageLayer.backgroundColor = UIColor.tertiarySystemFill.cgColor
        layer.addSublayer(imageLayer)

        fadeView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fadeView)

        NSLayoutConstraint.activate([
            fadeView.topAnchor.constraint(equalTo: topAnchor),
            fadeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fadeView.trailingAnchor.constraint(equalTo: trailingAnchor),
            fadeView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        imageObservation = imageView.observe(\.image, options: [.new]) { [weak self] imageView, _ in
            self?.updateImageContents(imageView.image)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageLayer.contentsScale = traitCollection.displayScale
        positionImageLayer()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        imageLayer.backgroundColor = UIColor.tertiarySystemFill.resolvedColor(with: traitCollection).cgColor
    }

    /// Pull distance below zero grows the hero image upward and outward.
    /// Only the backing layer moves, so the scroll view's layout stays still.
    func applyOverscroll(_ pull: CGFloat) {
        let clamped = max(0, pull)
        guard clamped != self.pull else { return }
        self.pull = clamped
        positionImageLayer()
    }

    private func updateImageContents(_ image: UIImage?) {
        imageLayer.contents = image.flatMap(Self.uprightContents(of:))
    }

    private func positionImageLayer() {
        let baseWidth = bounds.width
        let baseHeight = bounds.height
        guard baseWidth > 1, baseHeight > 1 else { return }
        let scale = (baseHeight + pull) / baseHeight
        let width = baseWidth * scale
        let height = baseHeight * scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = CGRect(x: (baseWidth - width) / 2, y: -pull, width: width, height: height)
        CATransaction.commit()
    }

    private static func uprightContents(of image: UIImage) -> CGImage? {
        guard image.imageOrientation != .up else { return image.cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return rendered.cgImage
    }
}

/// Fades the hero into the page background. Clear through 69%, then 80% at 89%, full at the bottom.
private final class LessonHeroFadeView: UIView {

    override class var layerClass: AnyClass { CAGradientLayer.self }

    private var gradient: CAGradientLayer { layer as! CAGradientLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        gradient.locations = [0, 0.69, 0.89, 1]
        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateColors()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        updateColors()
    }

    private func updateColors() {
        let base = ExperimentPalette.pageBackground.resolvedColor(with: traitCollection)
        gradient.colors = [0, 0, 0.8, 1].map { base.withAlphaComponent($0).cgColor }
    }
}

// MARK: - Chips

private final class LessonMetaChipRow: UIView {

    private var chips: [LessonMetaChip] = []
    private let horizontalSpacing: CGFloat = 10
    private let verticalSpacing: CGFloat = 10
    private var measuredHeight: CGFloat = LessonMetaChip.singleLineHeight
    private var lastLayoutWidth: CGFloat = -1

    func setTitles(_ titles: [String]) {
        chips.forEach { $0.removeFromSuperview() }
        chips = titles.map { LessonMetaChip(title: $0) }
        chips.forEach { addSubview($0) }
        lastLayoutWidth = -1
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let height = placeChips(maxWidth: width, applyingFrames: true)
        guard abs(width - lastLayoutWidth) > 0.5 else { return }
        lastLayoutWidth = width
        guard abs(height - measuredHeight) > 0.5 else { return }
        measuredHeight = height
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: measuredHeight)
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        let width = targetSize.width > 0 && targetSize.width < 10_000 ? targetSize.width : bounds.width
        let height = placeChips(maxWidth: max(width, 1), applyingFrames: false)
        measuredHeight = height
        return CGSize(width: width, height: height)
    }

    @discardableResult
    private func placeChips(maxWidth: CGFloat, applyingFrames: Bool) -> CGFloat {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for chip in chips {
            let size = chip.intrinsicContentSize
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + verticalSpacing
                lineHeight = 0
            }
            if applyingFrames {
                chip.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
            }
            x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
        return chips.isEmpty ? 0 : y + lineHeight
    }
}

/// Quiet edge shared by the lesson chips and scene thumbnails.
private enum LessonSurfaceRim {
    static let width: CGFloat = 1
    static let color = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.16)
            : UIColor(white: 1, alpha: 0.55)
    }
}

private final class LessonMetaChip: UIView {

    static let verticalPadding: CGFloat = 8
    static var singleLineHeight: CGFloat {
        ceil(UIFont.systemFont(ofSize: 15, weight: .semibold).lineHeight) + verticalPadding * 2
    }

    private let label = UILabel()
    private let horizontalPadding: CGFloat = 12

    init(title: String) {
        super.init(frame: .zero)
        label.text = title
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        clipsToBounds = false
        backgroundColor = .secondarySystemBackground
        layer.borderWidth = LessonSurfaceRim.width
        layer.cornerCurve = .continuous
        layer.borderColor = LessonSurfaceRim.color.resolvedColor(with: traitCollection).cgColor

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalPadding),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalPadding),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        layer.borderColor = LessonSurfaceRim.color.resolvedColor(with: traitCollection).cgColor
    }

    override var intrinsicContentSize: CGSize {
        let labelSize = label.intrinsicContentSize
        return CGSize(
            width: ceil(labelSize.width) + horizontalPadding * 2,
            height: ceil(labelSize.height) + Self.verticalPadding * 2
        )
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        backgroundColor = .secondarySystemBackground
        layer.borderColor = LessonSurfaceRim.color.resolvedColor(with: traitCollection).cgColor
    }
}

// MARK: - Scene row

private final class LessonSceneRow: UIControl {

    enum Access {
        case completed
        case next
        case preview
        case locked
    }

    var onOpen: (() -> Void)?
    var onStudy: (() -> Void)?
    var onReplay: (() -> Void)?

    let thumbnailView = UIImageView()

    private let titleText: String
    private let sceneNumber: Int
    private let eyebrowLabel = UILabel()
    private let titleLabel = UILabel()
    private let starsView = LessonSceneStarsView()
    private let startButton = UIButton(type: .custom)
    private let lockedButton = UIButton(type: .custom)
    private let studyButton = UIButton(type: .custom)
    private let replayButton = UIButton(type: .custom)
    private var textTrailingToActions: NSLayoutConstraint?
    private var textTrailingToRow: NSLayoutConstraint?
    private var access: Access = .locked

    init(sceneNumber: Int, title: String, durationText: String?) {
        self.sceneNumber = sceneNumber
        titleText = title
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.backgroundColor = .tertiarySystemFill
        thumbnailView.layer.borderWidth = LessonSurfaceRim.width
        thumbnailView.layer.borderColor = LessonSurfaceRim.color.resolvedColor(with: traitCollection).cgColor
        thumbnailView.layer.cornerCurve = .continuous
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.isAccessibilityElement = false
        thumbnailView.setContentHuggingPriority(.fittingSizeLevel, for: .horizontal)
        thumbnailView.setContentHuggingPriority(.fittingSizeLevel, for: .vertical)
        thumbnailView.setContentCompressionResistancePriority(.fittingSizeLevel, for: .horizontal)
        thumbnailView.setContentCompressionResistancePriority(.fittingSizeLevel, for: .vertical)

        if let durationText, !durationText.isEmpty {
            eyebrowLabel.text = "Scene \(sceneNumber) · \(durationText)"
        } else {
            eyebrowLabel.text = "Scene \(sceneNumber)"
        }
        eyebrowLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 13, weight: .medium)
        )
        eyebrowLabel.adjustsFontForContentSizeCategory = true
        eyebrowLabel.textColor = .secondaryLabel
        eyebrowLabel.numberOfLines = 1
        eyebrowLabel.isAccessibilityElement = false

        titleLabel.text = title
        titleLabel.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: .systemFont(ofSize: 17, weight: .bold)
        )
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        titleLabel.isAccessibilityElement = false

        configureActionButton(
            startButton,
            title: "Start Lesson",
            symbolName: "chevron.right",
            background: PrimaryButton.appearance(for: .yellow).backgroundColor,
            foreground: PrimaryButton.appearance(for: .yellow).titleColor
        )
        configureActionButton(
            lockedButton,
            title: "Locked",
            symbolName: "lock.fill",
            background: Self.lockedBackground,
            foreground: .secondaryLabel
        )
        startButton.isHidden = true
        lockedButton.isHidden = true
        starsView.isHidden = true

        configureSideButton(studyButton, title: "Study", emphasized: false)
        configureSideButton(replayButton, title: "Replay", emphasized: true)
        studyButton.addAction(UIAction { [weak self] _ in
            self?.onStudy?()
        }, for: .touchUpInside)
        replayButton.addAction(UIAction { [weak self] _ in
            self?.onReplay?()
        }, for: .touchUpInside)

        let actionStack = UIStackView(arrangedSubviews: [studyButton, replayButton])
        actionStack.axis = .vertical
        actionStack.alignment = .fill
        actionStack.spacing = 6
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionStack.setContentHuggingPriority(.required, for: .horizontal)
        actionStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        let textStack = UIStackView(arrangedSubviews: [eyebrowLabel, titleLabel, starsView, startButton, lockedButton])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.setCustomSpacing(8, after: titleLabel)
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.isUserInteractionEnabled = false
        textStack.setContentHuggingPriority(.required, for: .vertical)
        textStack.setContentCompressionResistancePriority(.required, for: .vertical)
        eyebrowLabel.setContentHuggingPriority(.required, for: .vertical)
        eyebrowLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        titleLabel.setContentHuggingPriority(.required, for: .vertical)
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        addSubview(thumbnailView)
        addSubview(textStack)
        addSubview(actionStack)
        addAction(UIAction { [weak self] _ in
            guard let self else { return }
            guard self.access == .next || self.access == .preview else { return }
            self.onOpen?()
        }, for: .touchUpInside)

        let textBottom = textStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        textBottom.priority = UILayoutPriority(999)
        let trailingToActions = textStack.trailingAnchor.constraint(equalTo: actionStack.leadingAnchor, constant: -12)
        let trailingToRow = textStack.trailingAnchor.constraint(equalTo: trailingAnchor)
        textTrailingToActions = trailingToActions
        textTrailingToRow = trailingToRow
        trailingToRow.isActive = true

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: bottomAnchor),
            thumbnailView.heightAnchor.constraint(greaterThanOrEqualToConstant: 112),
            thumbnailView.widthAnchor.constraint(equalTo: thumbnailView.heightAnchor),

            textStack.topAnchor.constraint(equalTo: topAnchor),
            textStack.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 14),

            actionStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            actionStack.trailingAnchor.constraint(equalTo: trailingAnchor),

            textStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            textBottom,
        ])

        apply(access: .locked, starCount: 0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(access: Access, starCount: Int) {
        self.access = access
        let finished = access == .completed
        // Stay enabled once finished so Study and Replay can take the tap.
        // A disabled control drops touches for its subviews too.
        isEnabled = access != .locked
        isAccessibilityElement = access != .completed
        let showsStart = access == .next || access == .preview
        startButton.isHidden = !showsStart
        if showsStart {
            setFilledButtonTitle(startButton, access == .preview ? "Preview" : "Start Lesson")
        }
        lockedButton.isHidden = access != .locked
        starsView.isHidden = !finished
        if finished {
            starsView.setEarned(starCount)
        }
        studyButton.isHidden = !finished
        replayButton.isHidden = !finished
        if finished {
            textTrailingToRow?.isActive = false
            textTrailingToActions?.isActive = true
        } else {
            textTrailingToActions?.isActive = false
            textTrailingToRow?.isActive = true
        }

        switch access {
        case .completed:
            accessibilityLabel = "Scene \(sceneNumber), \(titleText)"
            accessibilityTraits = []
        case .next:
            accessibilityLabel = "Scene \(sceneNumber), \(titleText), Start lesson"
            accessibilityTraits = .button
        case .preview:
            accessibilityLabel = "Scene \(sceneNumber), \(titleText), Preview"
            accessibilityTraits = .button
        case .locked:
            accessibilityLabel = "Scene \(sceneNumber), \(titleText), Locked"
            accessibilityTraits = [.button, .notEnabled]
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        thumbnailView.layer.cornerRadius = thumbnailView.bounds.height * 0.16
        thumbnailView.layer.borderColor = LessonSurfaceRim.color.resolvedColor(with: traitCollection).cgColor
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if access == .completed {
            for button in [studyButton, replayButton] where !button.isHidden {
                let local = button.convert(point, from: self)
                if let hit = button.hitTest(local, with: event) {
                    return hit
                }
            }
        }
        return super.hitTest(point, with: event)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        thumbnailView.layer.borderColor = LessonSurfaceRim.color.resolvedColor(with: traitCollection).cgColor
    }

    override var isHighlighted: Bool {
        didSet {
            guard access == .next || access == .preview else { return }
            alpha = isHighlighted ? 0.55 : 1
        }
    }

    private func configureActionButton(
        _ button: UIButton,
        title: String,
        symbolName: String,
        background: UIColor,
        foreground: UIColor
    ) {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = background
        config.baseForegroundColor = foreground
        config.title = title
        config.image = UIImage(systemName: symbolName)
        config.imagePlacement = .trailing
        config.imagePadding = 5
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 12)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 16, weight: .semibold)
            return outgoing
        }
        button.configuration = config
        button.isAccessibilityElement = false
        button.isUserInteractionEnabled = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    private func setFilledButtonTitle(_ button: UIButton, _ title: String) {
        var config = button.configuration
        config?.title = title
        button.configuration = config
    }

    private func configureSideButton(_ button: UIButton, title: String, emphasized: Bool) {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        if emphasized {
            let yellow = PrimaryButton.appearance(for: .yellow)
            config.baseBackgroundColor = yellow.backgroundColor
            config.baseForegroundColor = yellow.titleColor
        } else {
            config.baseBackgroundColor = .secondarySystemBackground
            config.baseForegroundColor = .label
        }
        config.title = title
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 15, weight: .semibold)
            return outgoing
        }
        button.configuration = config
        button.accessibilityLabel = title
        button.isHidden = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    private static let lockedBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .tertiarySystemFill
            : UIColor(white: 0.9, alpha: 1)
    }
}

/// Three stars for a finished scene. Filled stars are the best score.
private final class LessonSceneStarsView: UIView {

    private static let filledColor = UIColor(red: 253 / 255, green: 200 / 255, blue: 1 / 255, alpha: 1)
    private let starViews: [UIImageView]

    override init(frame: CGRect) {
        let symbol = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        starViews = (0..<3).map { _ in
            let imageView = UIImageView(image: UIImage(systemName: "star.fill", withConfiguration: symbol))
            imageView.tintColor = .tertiaryLabel
            imageView.contentMode = .scaleAspectFit
            imageView.setContentHuggingPriority(.required, for: .horizontal)
            imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
            return imageView
        }
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        let stack = UIStackView(arrangedSubviews: starViews)
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 16),
        ])
        setEarned(0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setEarned(_ earned: Int) {
        let clamped = min(max(earned, 0), starViews.count)
        for (index, star) in starViews.enumerated() {
            star.tintColor = index < clamped ? Self.filledColor : .tertiaryLabel
        }
        accessibilityLabel = "\(clamped) of \(starViews.count) stars"
    }
}

// MARK: - Images

private enum LessonImageLoading {

    static func apply(
        primaryURL: URL?,
        fallbackURL: URL?,
        bundledName: String?,
        pixelSize: CGFloat,
        to imageView: UIImageView,
        completion: (() -> Void)? = nil
    ) {
        if let bundledName,
           let bundled = LessonThumbnailLoader.bundledImage(
               named: bundledName,
               targetPixelSize: pixelSize,
               variant: .color
           ) {
            imageView.image = bundled
        }

        let urls = [primaryURL, fallbackURL].compactMap { $0 }.uniqued()
        guard let url = urls.first else {
            completion?()
            return
        }
        load(
            url: url,
            remaining: Array(urls.dropFirst()),
            pixelSize: pixelSize,
            into: imageView,
            completion: completion
        )
    }

    private static func load(
        url: URL,
        remaining: [URL],
        pixelSize: CGFloat,
        into imageView: UIImageView,
        completion: (() -> Void)?
    ) {
        if let cached = LessonThumbnailLoader.cachedImage(
            for: url,
            targetPixelSize: pixelSize,
            variant: .color
        ) {
            imageView.image = cached
            completion?()
            return
        }
        LessonThumbnailLoader.load(url: url, targetPixelSize: pixelSize, variant: .color) { [weak imageView] image in
            guard let imageView else {
                completion?()
                return
            }
            if let image {
                imageView.image = image
                completion?()
            } else if let next = remaining.first {
                load(
                    url: next,
                    remaining: Array(remaining.dropFirst()),
                    pixelSize: pixelSize,
                    into: imageView,
                    completion: completion
                )
            } else {
                completion?()
            }
        }
    }
}

/// Counts thumbnail loads. Completions may arrive synchronously, so the count is fixed before any load starts.
private final class LessonImageReadyGate {
    private var remaining: Int
    private let completion: () -> Void

    init(count: Int, completion: @escaping () -> Void) {
        remaining = count
        self.completion = completion
        if count == 0 {
            completion()
        }
    }

    func arrive() {
        remaining -= 1
        if remaining == 0 {
            completion()
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
