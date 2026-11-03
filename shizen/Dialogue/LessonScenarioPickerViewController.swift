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

final class LessonScenarioPickerViewController: UIViewController, UIScrollViewDelegate, ScreenshotQAPresenting {

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
    private let scoreSummaryView = LessonScoreSummaryView()
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
    private var refreshObserver: NSObjectProtocol?
    /// A newer lesson copy arrived while a scene was open; apply it on return.
    private var hasPendingRefresh = false
    /// Tags this screen's look-ahead audio downloads so leaving can cancel them.
    private let prefetchOwner = UUID()
    private var hasPlayedScoreFillThisAppearance = false
    private let topScrollEdgeInteraction: UIScrollEdgeElementContainerInteraction = {
        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.edge = .top
        return interaction
    }()

    private static let horizontalInset: CGFloat = 20
    private static let heroHeightRatio: CGFloat = 0.42
    /// Scenes after the next playable one whose audio is fetched ahead on unmetered networks.
    private static let lookAheadSceneCount = 1
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
        RemoteAudioCache.cancelPrefetches(owner: prefetchOwner)
        if let progressObserver {
            NotificationCenter.default.removeObserver(progressObserver)
        }
        if let refreshObserver {
            NotificationCenter.default.removeObserver(refreshObserver)
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
            guard let self else { return }
            self.refreshSceneAccess()
            self.refreshOptionsMenu()
            self.prefetchSceneAudio()
            if self.viewIfLoaded?.window != nil, !self.loadingCoordinator.isLoading {
                self.scoreSummaryView.playFillAnimation()
            }
        }
        refreshObserver = NotificationCenter.default.addObserver(
            forName: DialogueScenarioCollectionCatalog.didRefreshCollection,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  note.userInfo?[DialogueScenarioCollectionCatalog.collectionIDKey] as? String == self.collectionID
            else { return }
            self.hasPendingRefresh = true
            self.applyPendingRefreshIfIdle()
        }

        loadingCoordinator.attach(to: view)
        loadingCoordinator.beginLoading()
        DialogueScenarioCollectionCatalog.fetchCollection(id: collectionID) { [weak self] collection in
            guard let self else { return }
            if let collection {
                self.applyCollection(collection) {
                    self.loadingCoordinator.finishLoading {
                        self.playScoreFillIfNeeded()
                        self.applyPendingRefreshIfIdle()
                    }
                }
                self.prefetchSceneAudio()
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
        hasPlayedScoreFillThisAppearance = false
        scoreSummaryView.markFillAnimationNeeded()
        applyPendingRefreshIfIdle(appearing: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        playScoreFillIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.navigationBar.removeInteraction(topScrollEdgeInteraction)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Backing out of the lesson, not pushing a scene: drop the look-ahead.
        if isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true {
            RemoteAudioCache.cancelPrefetches(owner: prefetchOwner)
        }
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
        heroView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleHeroTap)))
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
        bodyStack.setCustomSpacing(20, after: summaryLabel)

        scoreSummaryView.isHidden = true
        bodyStack.addArrangedSubview(scoreSummaryView)
        bodyStack.setCustomSpacing(28, after: scoreSummaryView)

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

    /// Swaps in a refreshed lesson copy only while this screen is on top, so an open
    /// scene never changes under the learner. Otherwise it waits for the next appearance.
    private func applyPendingRefreshIfIdle(appearing: Bool = false) {
        guard hasPendingRefresh, collection != nil, !loadingCoordinator.isLoading else { return }
        guard appearing || (viewIfLoaded?.window != nil && presentedViewController == nil) else { return }
        guard let fresh = DialogueScenarioCollectionCatalog.readyCollection(id: collectionID) else { return }
        hasPendingRefresh = false
        applyCollection(fresh) {}
        prefetchSceneAudio()
    }

    /// Downloads the next playable scene's clip and ambience bed at high priority,
    /// then the scene after it as low-priority look-ahead. Runs again on progress
    /// changes, so the window follows the learner. Cached files are skipped.
    private func prefetchSceneAudio() {
        guard let collection else { return }
        let store = DialogueProgressStore.shared
        let scenarios = collection.scenarios
        guard !scenarios.isEmpty else { return }
        let nextIndex = scenarios.firstIndex { !store.isCompleted(scenarioID: $0.id) } ?? 0
        prefetchAudio(for: scenarios[nextIndex].example, priority: .high)
        let lookAhead = scenarios.indices.dropFirst(nextIndex + 1).prefix(Self.lookAheadSceneCount)
        for index in lookAhead {
            prefetchAudio(for: scenarios[index].example, priority: .low)
        }
    }

    private func prefetchAudio(for example: GrammarExample, priority: RemoteAudioCache.Priority) {
        if let raw = example.publishedAudioUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: raw),
           url.scheme?.hasPrefix("http") == true {
            RemoteAudioCache.prefetchFile(
                for: url,
                metadata: example.remoteAudioCacheMetadata,
                priority: priority,
                owner: prefetchOwner
            )
        }
        if let bed = example.ambience {
            RemoteAudioCache.prefetchBed(id: bed.id, remoteURL: bed.url, priority: priority, owner: prefetchOwner)
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
            row.onThumbnailTap = { [weak self] in
                self?.presentThumbnailViewer(startingAt: index + 1)
            }
            scenesStack.addArrangedSubview(row)
            scenarioRows.append(row)
        }
    }

    private func refreshSceneAccess() {
        guard let collection else { return }
        let store = DialogueProgressStore.shared
        let wrapUp = DialogueLessonWrapUp.make(collection: collection, progress: store)
        var lessonPoints = 0
        var sceneCompletion: [Bool] = []
        var sceneFills: [CGFloat] = []
        for (index, (row, scenario)) in zip(scenarioRows, collection.scenarios).enumerated() {
            let points = wrapUp.scenes[index].points
            let completed = store.isCompleted(scenarioID: scenario.id)
            sceneCompletion.append(completed)
            if completed {
                lessonPoints += points ?? 0
            }
            sceneFills.append(Self.scoreFill(points: points, scenario: scenario, completed: completed, store: store))
            let best = store.bestAttempt(scenarioID: scenario.id)
            let possible = DialogueLessonWrapUp.maximumPoints(for: scenario)
            row.apply(
                access: access(for: scenario.id, in: collection),
                starCount: best?.starCount ?? (completed ? 1 : 0),
                earnedPoints: best?.points,
                possiblePoints: possible,
                hardcore: DialogueHardcoreMode.isAvailable
                    && store.hasHardcoreCompletion(scenarioID: scenario.id)
            )
        }
        scoreSummaryView.apply(
            points: lessonPoints,
            possible: wrapUp.totalPossiblePoints,
            sceneFills: sceneFills,
            sceneCompletion: sceneCompletion
        )
        scoreSummaryView.isHidden = collection.scenarios.isEmpty
    }

    /// Scene bar fill is that scene's best score over a perfect tally. Legacy
    /// completions without points use stars so a finished scene is never empty.
    private static func scoreFill(
        points: Int?,
        scenario: DialogueScenarioCollection.Scenario,
        completed: Bool,
        store: DialogueProgressStore
    ) -> CGFloat {
        let maximum = DialogueLessonWrapUp.maximumPoints(for: scenario)
        if let points, maximum > 0 {
            return min(1, CGFloat(points) / CGFloat(maximum))
        }
        guard completed else { return 0 }
        return CGFloat(store.displayedStarCount(scenarioID: scenario.id))
            / CGFloat(DialogueScoreRules.maxStars)
    }

    private func playScoreFillIfNeeded() {
        guard collection != nil, !loadingCoordinator.isLoading else { return }
        guard !hasPlayedScoreFillThisAppearance else { return }
        hasPlayedScoreFillThisAppearance = true
        view.layoutIfNeeded()
        scoreSummaryView.playFillAnimation()
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

    func presentScreenshotQANote(from presenter: UIViewController) -> Bool {
        presentContentQANote(from: presenter, forcesScreenshot: true)
        return true
    }

    private func presentContentQANote(from presenter: UIViewController? = nil, forcesScreenshot: Bool = false) {
        let lessonTitle = lessonNavigationTitle
            ?? fallbackTitle
            ?? collection?.title
            ?? collectionID
        DialogueContentQANoteViewController.present(
            from: presenter ?? self,
            source: .dialogue,
            sourceId: collectionID,
            focusTitle: "Lesson",
            focusDetailLines: lessonQAFocusDetailLines(),
            lessonTitle: lessonTitle,
            lessonID: collectionID,
            studioLink: ContentCMSClient.studioLessonEditorLink(collectionId: collectionID),
            forcesScreenshot: forcesScreenshot
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
        dialogue.analytics.source = "picker"
        navigationController?.pushViewController(dialogue, animated: true)
    }

    @objc private func handleHeroTap() {
        presentThumbnailViewer(startingAt: 0)
    }

    /// Full-screen lesson images: the lesson's main thumbnail first, then each scene.
    /// Zooms out of the tapped hero or row thumbnail.
    private func presentThumbnailViewer(startingAt index: Int) {
        guard let collection, (0 ... collection.scenarios.count).contains(index) else { return }
        let lessonItem = LessonThumbnailViewerController.Item(
            caption: lessonNavigationTitle ?? fallbackTitle ?? collection.title,
            placeholder: heroView.imageView.image
        )
        let sceneItems = collection.scenarios.enumerated().map { offset, scenario in
            LessonThumbnailViewerController.Item(
                caption: sceneMenuTitle(number: offset + 1, title: scenario.menuTitle),
                placeholder: scenarioRows.indices.contains(offset) ? scenarioRows[offset].thumbnailView.image : nil
            )
        }
        let viewer = LessonThumbnailViewerController(
            items: [lessonItem] + sceneItems,
            initialIndex: index
        ) { index, update in
            let pixelSize = LessonThumbnailViewerController.fullImagePixelSize
            if index == 0 {
                LessonImageLoading.resolve(
                    primaryURL: collection.thumbnailURL,
                    fallbackURL: nil,
                    bundledName: collection.sceneImageName,
                    pixelSize: pixelSize,
                    onImage: update
                )
                return
            }
            let sceneIndex = index - 1
            guard collection.scenarios.indices.contains(sceneIndex) else { return }
            LessonImageLoading.resolve(
                primaryURL: collection.scenarios[sceneIndex].thumbnailURL,
                fallbackURL: collection.thumbnailURL,
                bundledName: collection.sceneImageName,
                pixelSize: pixelSize,
                onImage: update
            )
        }
        viewer.sourceViewProvider = { [weak self] index in
            guard let self else { return nil }
            if index == 0 {
                return self.heroView
            }
            let sceneIndex = index - 1
            guard self.scenarioRows.indices.contains(sceneIndex) else { return nil }
            return self.scenarioRows[sceneIndex].thumbnailView
        }
        viewer.onIndexChange = { [weak self] index in
            guard let self else { return }
            if index == 0 {
                self.scrollView.contentOffset.y = 0
                self.scrollView.layoutIfNeeded()
            } else {
                self.revealSceneRow(at: index - 1)
            }
        }
        present(viewer, animated: true)
    }

    /// Keeps the current scene's row on screen behind the viewer so dismissal can zoom back into it.
    private func revealSceneRow(at index: Int) {
        guard scenarioRows.indices.contains(index) else { return }
        let row = scenarioRows[index]
        let rowFrame = row.convert(row.bounds, to: scrollView)
        let barBottom = navigationController?.navigationBar.frame.maxY ?? view.safeAreaInsets.top
        let visible = scrollView.bounds.inset(by: UIEdgeInsets(
            top: barBottom + 12,
            left: 0,
            bottom: view.safeAreaInsets.bottom + 96,
            right: 0
        ))
        guard !visible.contains(rowFrame) else { return }
        let maxOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        let targetY = rowFrame.midY - scrollView.bounds.height / 2
        scrollView.contentOffset.y = min(max(0, targetY), maxOffset)
        scrollView.layoutIfNeeded()
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
        backgroundColor = ExperimentPalette.cardSurface
        layer.borderWidth = LessonSurfaceRim.width
        layer.cornerCurve = .continuous
        updateBorderColor()

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
        updateBorderColor()
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
        backgroundColor = ExperimentPalette.cardSurface
        updateBorderColor()
    }

    private func updateBorderColor() {
        let rim = traitCollection.userInterfaceStyle == .dark
            ? LessonSurfaceRim.color
            : ExperimentPalette.cardBorder
        layer.borderColor = rim.resolvedColor(with: traitCollection).cgColor
    }
}

// MARK: - Score summary

/// Lesson score (sum of each completed scene's best run) and scene completion count.
private final class LessonScoreSummaryView: UIView {

    static let pillHeight: CGFloat = 8
    static let fillDuration: TimeInterval = 0.58
    private static let cascadeDelay: TimeInterval = 0.08

    private let pointsLabel = UILabel()
    private let possibleLabel = UILabel()
    private let pillStack = UIStackView()
    private let progressLabel = UILabel()
    private var pills: [LessonSceneScoreBar] = []
    private var sceneFills: [CGFloat] = []
    private var needsFillAnimation = false
    private let padding: CGFloat = 18

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = ExperimentPalette.cardSurface
        layer.borderWidth = 1
        layer.borderColor = ExperimentPalette.cardBorder.resolvedColor(with: traitCollection).cgColor
        layer.cornerCurve = .continuous
        layer.cornerRadius = 20
        isAccessibilityElement = true

        let caption = UILabel()
        caption.text = "LESSON SCORE"
        caption.font = .systemFont(ofSize: 11, weight: .bold)
        caption.textColor = .secondaryLabel

        let scoreFont = UIFont.systemFont(ofSize: 40, weight: .bold)
        let roundedScoreFont = scoreFont.fontDescriptor.withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: 40) } ?? scoreFont
        pointsLabel.font = roundedScoreFont
        pointsLabel.textColor = .label
        pointsLabel.setContentHuggingPriority(.required, for: .horizontal)
        pointsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        possibleLabel.font = roundedScoreFont.withSize(17)
        possibleLabel.textColor = .secondaryLabel
        possibleLabel.setContentHuggingPriority(.required, for: .horizontal)
        possibleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let scoreLine = UIStackView(arrangedSubviews: [pointsLabel, possibleLabel])
        scoreLine.axis = .horizontal
        scoreLine.alignment = .lastBaseline
        scoreLine.spacing = 2

        pillStack.axis = .horizontal
        pillStack.alignment = .fill
        pillStack.distribution = .fillEqually
        pillStack.spacing = 6
        pillStack.heightAnchor.constraint(equalToConstant: Self.pillHeight).isActive = true

        progressLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        progressLabel.textColor = .secondaryLabel
        progressLabel.numberOfLines = 1

        let stack = UIStackView(arrangedSubviews: [caption, scoreLine, pillStack, progressLabel])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.setCustomSpacing(14, after: scoreLine)
        stack.setCustomSpacing(10, after: pillStack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            pillStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        apply(points: 0, possible: 0, sceneFills: [], sceneCompletion: [])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// One bar per scene, in lesson order. Fill is that scene's score.
    func apply(points: Int, possible: Int, sceneFills: [CGFloat], sceneCompletion: [Bool]) {
        pointsLabel.text = "\(points)"
        possibleLabel.text = "/\(possible)"
        self.sceneFills = sceneFills

        if pills.count != sceneFills.count {
            pills.forEach { $0.removeFromSuperview() }
            pills = sceneFills.map { _ in
                let pill = LessonSceneScoreBar()
                pillStack.addArrangedSubview(pill)
                return pill
            }
        }

        let completed = sceneCompletion.filter { $0 }.count
        let total = sceneCompletion.count
        progressLabel.text = "\(completed) of \(total) scenes completed"
        accessibilityLabel = "Lesson score, \(points) of \(possible) points, \(completed) of \(total) scenes completed"
    }

    func markFillAnimationNeeded() {
        for bar in pills {
            bar.setFill(0, animated: false)
        }
    }

    /// Empties the bars, then fills them left to right with a slight cascade.
    func playFillAnimation() {
        needsFillAnimation = true
        tryPlayFillAnimation()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        tryPlayFillAnimation()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        layer.borderColor = ExperimentPalette.cardBorder.resolvedColor(with: traitCollection).cgColor
    }

    private func tryPlayFillAnimation() {
        guard needsFillAnimation else { return }
        guard !pills.isEmpty, pills.allSatisfy({ $0.bounds.width > 1 }) else { return }
        needsFillAnimation = false

        let fills = sceneFills
        for bar in pills {
            bar.setFill(0, animated: false)
        }

        guard !UIAccessibility.isReduceMotionEnabled else {
            for (bar, fill) in zip(pills, fills) {
                bar.setFill(fill, animated: false)
            }
            return
        }

        for (index, bar) in pills.enumerated() {
            let fill = index < fills.count ? fills[index] : 0
            bar.setFill(fill, animated: true, delay: Self.cascadeDelay * TimeInterval(index))
        }
    }
}

/// Track plus a leading fill. Width is the scene's score over a perfect tally.
private final class LessonSceneScoreBar: UIView {

    private let fillView = UIView()
    private var fillWidthConstraint: NSLayoutConstraint!
    private var fillFraction: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .tertiarySystemFill
        clipsToBounds = true
        layer.cornerCurve = .continuous
        layer.cornerRadius = LessonScoreSummaryView.pillHeight / 2

        fillView.backgroundColor = LessonSceneStarsView.filledColor
        fillView.layer.cornerCurve = .continuous
        fillView.layer.cornerRadius = LessonScoreSummaryView.pillHeight / 2
        fillView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fillView)

        fillWidthConstraint = fillView.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            fillView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fillView.topAnchor.constraint(equalTo: topAnchor),
            fillView.bottomAnchor.constraint(equalTo: bottomAnchor),
            fillWidthConstraint,
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        fillView.layer.cornerRadius = bounds.height / 2
    }

    func setFill(_ fraction: CGFloat, animated: Bool, delay: TimeInterval = 0) {
        fillFraction = min(max(fraction, 0), 1)
        let width = bounds.width * fillFraction
        let apply = {
            self.fillWidthConstraint.constant = width
            self.layoutIfNeeded()
        }
        if animated {
            UIView.animate(
                withDuration: LessonScoreSummaryView.fillDuration,
                delay: delay,
                usingSpringWithDamping: 0.88,
                initialSpringVelocity: 0.35,
                options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
            ) {
                apply()
            }
        } else {
            apply()
        }
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
    /// Tapping the thumbnail opens the image viewer instead of the scene.
    var onThumbnailTap: (() -> Void)?

    let thumbnailView = UIImageView()

    private let titleText: String
    private let sceneNumber: Int
    private let eyebrowLabel = UILabel()
    private let titleLabel = UILabel()
    private let starsView = LessonSceneStarsView()
    private let pointsLabel = UILabel()
    /// Shown on finished scenes that were first heard in hardcore mode.
    private let hardcoreBadgeView = UIImageView()
    private let scoreLine = UIStackView()
    private let startButton = UIButton(type: .custom)
    private let lockedButton = UIButton(type: .custom)
    private let chevronView = UIImageView()
    /// Grows so Preview / Start Lesson sit on the row’s bottom edge when the thumbnail is taller than the title.
    private let startButtonSpacer = UIView()
    private var textStackBottomConstraint: NSLayoutConstraint!
    private var textTrailingToChevron: NSLayoutConstraint!
    private var textTrailingToRow: NSLayoutConstraint!
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
        thumbnailView.isUserInteractionEnabled = true
        thumbnailView.addGestureRecognizer(UITapGestureRecognizer(
            target: self,
            action: #selector(handleThumbnailTap)
        ))
        thumbnailView.setContentHuggingPriority(.required, for: .horizontal)
        thumbnailView.setContentHuggingPriority(.required, for: .vertical)
        thumbnailView.setContentCompressionResistancePriority(.required, for: .horizontal)
        thumbnailView.setContentCompressionResistancePriority(.required, for: .vertical)

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

        pointsLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        pointsLabel.textColor = .secondaryLabel
        pointsLabel.isAccessibilityElement = false
        pointsLabel.isHidden = true
        pointsLabel.setContentHuggingPriority(.required, for: .horizontal)
        pointsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        hardcoreBadgeView.image = DialogueHardcoreMode.icon
        hardcoreBadgeView.tintColor = .secondaryLabel
        hardcoreBadgeView.contentMode = .scaleAspectFit
        hardcoreBadgeView.isAccessibilityElement = false
        hardcoreBadgeView.isHidden = true
        hardcoreBadgeView.setContentHuggingPriority(.required, for: .horizontal)
        hardcoreBadgeView.setContentCompressionResistancePriority(.required, for: .horizontal)
        hardcoreBadgeView.widthAnchor.constraint(equalToConstant: 14).isActive = true
        hardcoreBadgeView.heightAnchor.constraint(equalToConstant: 14).isActive = true

        scoreLine.addArrangedSubview(starsView)
        scoreLine.addArrangedSubview(pointsLabel)
        scoreLine.addArrangedSubview(hardcoreBadgeView)
        scoreLine.axis = .horizontal
        scoreLine.alignment = .center
        scoreLine.spacing = 8
        scoreLine.isHidden = true

        chevronView.image = UIImage(systemName: "chevron.right")
        chevronView.tintColor = .tertiaryLabel
        chevronView.contentMode = .scaleAspectFit
        chevronView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.isAccessibilityElement = false
        chevronView.isHidden = true
        chevronView.setContentHuggingPriority(.required, for: .horizontal)
        chevronView.setContentHuggingPriority(.required, for: .vertical)
        chevronView.setContentCompressionResistancePriority(.required, for: .horizontal)
        chevronView.setContentCompressionResistancePriority(.required, for: .vertical)

        startButtonSpacer.isHidden = true
        startButtonSpacer.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        startButtonSpacer.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)

        let textStack = UIStackView(arrangedSubviews: [
            eyebrowLabel, titleLabel, scoreLine, startButtonSpacer, startButton, lockedButton,
        ])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.setCustomSpacing(8, after: titleLabel)
        textStack.setCustomSpacing(12, after: scoreLine)
        textStack.setCustomSpacing(0, after: startButtonSpacer)
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.isUserInteractionEnabled = false
        textStack.setContentHuggingPriority(.defaultLow, for: .vertical)
        textStack.setContentCompressionResistancePriority(.required, for: .vertical)
        eyebrowLabel.setContentHuggingPriority(.required, for: .vertical)
        eyebrowLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        titleLabel.setContentHuggingPriority(.required, for: .vertical)
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        addSubview(thumbnailView)
        addSubview(textStack)
        addSubview(chevronView)
        addAction(UIAction { [weak self] _ in
            guard let self else { return }
            switch self.access {
            case .next:
                self.onOpen?()
            case .preview, .completed:
                self.onStudy?()
            default:
                return
            }
        }, for: .touchUpInside)

        textStackBottomConstraint = textStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        textStackBottomConstraint.isActive = false
        textTrailingToChevron = textStack.trailingAnchor.constraint(
            equalTo: chevronView.leadingAnchor,
            constant: -10
        )
        textTrailingToRow = textStack.trailingAnchor.constraint(equalTo: trailingAnchor)
        textTrailingToRow.isActive = true

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 112),
            thumbnailView.heightAnchor.constraint(equalToConstant: 112),
            thumbnailView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),

            textStack.topAnchor.constraint(equalTo: topAnchor),
            textStack.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 14),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),

            chevronView.centerYAnchor.constraint(equalTo: thumbnailView.centerYAnchor),
            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        apply(access: .locked, starCount: 0, earnedPoints: nil, possiblePoints: 0, hardcore: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(
        access: Access,
        starCount: Int,
        earnedPoints: Int?,
        possiblePoints: Int,
        hardcore: Bool
    ) {
        self.access = access
        let finished = access == .completed
        // Stays enabled when locked so the thumbnail still takes taps; the row action and highlight check `access`.
        isEnabled = true
        isAccessibilityElement = true
        let showsStart = access == .next || access == .preview
        startButton.isHidden = !showsStart
        startButtonSpacer.isHidden = !showsStart
        textStackBottomConstraint.isActive = showsStart
        if showsStart {
            setFilledButtonTitle(startButton, access == .preview ? "Preview" : "Start Lesson")
        }
        lockedButton.isHidden = access != .locked
        scoreLine.isHidden = false
        applyPointsLabel(finished: finished, earnedPoints: earnedPoints, possiblePoints: possiblePoints)
        if finished {
            starsView.setEarned(starCount)
        } else {
            starsView.setUnscored()
        }
        hardcoreBadgeView.isHidden = !(finished && hardcore)
        chevronView.isHidden = !finished
        if finished {
            textTrailingToRow.isActive = false
            textTrailingToChevron.isActive = true
        } else {
            textTrailingToChevron.isActive = false
            textTrailingToRow.isActive = true
        }

        let pointsAccessibility = Self.pointsAccessibilityLabel(
            finished: finished,
            earnedPoints: earnedPoints,
            possiblePoints: possiblePoints
        )
        if finished, let pointsAccessibility {
            starsView.accessibilityLabel = "\(starsView.accessibilityLabel ?? ""), \(pointsAccessibility)"
        }

        let pointsSuffix = pointsAccessibility.map { ", \($0)" } ?? ""

        switch access {
        case .completed:
            accessibilityLabel = hardcore
                ? "Scene \(sceneNumber), \(titleText), Hardcore\(pointsSuffix), Study"
                : "Scene \(sceneNumber), \(titleText)\(pointsSuffix), Study"
            accessibilityTraits = .button
        case .next:
            accessibilityLabel = "Scene \(sceneNumber), \(titleText)\(pointsSuffix), Start lesson"
            accessibilityTraits = .button
        case .preview:
            accessibilityLabel = "Scene \(sceneNumber), \(titleText)\(pointsSuffix), Preview"
            accessibilityTraits = .button
        case .locked:
            accessibilityLabel = "Scene \(sceneNumber), \(titleText)\(pointsSuffix), Locked"
            accessibilityTraits = [.button, .notEnabled]
        }
    }

    private func applyPointsLabel(finished: Bool, earnedPoints: Int?, possiblePoints: Int) {
        guard possiblePoints > 0 else {
            pointsLabel.isHidden = true
            pointsLabel.attributedText = nil
            return
        }
        let font = pointsLabel.font ?? .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let suffix = "/\(possiblePoints) points"
        if finished {
            if let earnedPoints, earnedPoints < possiblePoints {
                pointsLabel.isHidden = false
                let text = NSMutableAttributedString(
                    string: "\(earnedPoints)",
                    attributes: [.font: font, .foregroundColor: UIColor.label]
                )
                text.append(NSAttributedString(
                    string: suffix,
                    attributes: [.font: font, .foregroundColor: UIColor.secondaryLabel]
                ))
                pointsLabel.attributedText = text
            } else if earnedPoints == nil {
                pointsLabel.isHidden = false
                pointsLabel.attributedText = NSAttributedString(
                    string: "—\(suffix)",
                    attributes: [.font: font, .foregroundColor: UIColor.secondaryLabel]
                )
            } else if let earnedPoints {
                pointsLabel.isHidden = false
                pointsLabel.attributedText = NSAttributedString(
                    string: "\(earnedPoints) points",
                    attributes: [.font: font, .foregroundColor: UIColor.secondaryLabel]
                )
            }
        } else {
            pointsLabel.isHidden = false
            pointsLabel.attributedText = NSAttributedString(
                string: "\(possiblePoints) points",
                attributes: [.font: font, .foregroundColor: UIColor.secondaryLabel]
            )
        }
    }

    private static func pointsAccessibilityLabel(
        finished: Bool,
        earnedPoints: Int?,
        possiblePoints: Int
    ) -> String? {
        guard possiblePoints > 0 else { return nil }
        if finished {
            if let earnedPoints {
                return "\(earnedPoints) of \(possiblePoints) points"
            }
            return "\(possiblePoints) points possible"
        }
        return "\(possiblePoints) points available"
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        thumbnailView.layer.cornerRadius = thumbnailView.bounds.height * 0.16
        thumbnailView.layer.borderColor = LessonSurfaceRim.color.resolvedColor(with: traitCollection).cgColor
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        thumbnailView.layer.borderColor = LessonSurfaceRim.color.resolvedColor(with: traitCollection).cgColor
    }

    @objc private func handleThumbnailTap() {
        onThumbnailTap?()
    }

    override var isHighlighted: Bool {
        didSet {
            guard access == .next || access == .preview || access == .completed else { return }
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

    private static let lockedBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .tertiarySystemFill
            : UIColor(white: 0.9, alpha: 1)
    }
}

/// Three equal stars for a scene. Filled stars are the best score.
/// A scene with no score yet shows the same three, faint.
private final class LessonSceneStarsView: UIView {

    static let filledColor = UIColor(red: 253 / 255, green: 200 / 255, blue: 1 / 255, alpha: 1)
    private static let emptyColor = UIColor.tertiaryLabel
    private static let faintColor = UIColor.quaternaryLabel
    private static let pointSize: CGFloat = 14

    private let starViews: [UIImageView]

    override init(frame: CGRect) {
        let symbol = UIImage.SymbolConfiguration(pointSize: Self.pointSize, weight: .semibold)
        starViews = (0..<3).map { _ in
            let imageView = UIImageView(image: UIImage(systemName: "star.fill", withConfiguration: symbol))
            imageView.contentMode = .scaleAspectFit
            imageView.setContentHuggingPriority(.required, for: .horizontal)
            imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            let side = Self.pointSize + 1
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: side),
                imageView.heightAnchor.constraint(equalToConstant: side),
            ])
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
        ])
        setUnscored()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setEarned(_ earned: Int) {
        let clamped = min(max(earned, 0), starViews.count)
        for (index, star) in starViews.enumerated() {
            star.tintColor = index < clamped ? Self.filledColor : Self.emptyColor
        }
        accessibilityLabel = "\(clamped) of \(starViews.count) stars"
    }

    /// Placeholder for a scene that has not been scored.
    func setUnscored() {
        for star in starViews {
            star.tintColor = Self.faintColor
        }
        accessibilityLabel = "No score yet"
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
        resolve(
            primaryURL: primaryURL,
            fallbackURL: fallbackURL,
            bundledName: bundledName,
            pixelSize: pixelSize,
            onImage: { [weak imageView] image in imageView?.image = image },
            completion: completion
        )
    }

    /// Bundled art first (synchronously), then the first remote URL that loads.
    static func resolve(
        primaryURL: URL?,
        fallbackURL: URL?,
        bundledName: String?,
        pixelSize: CGFloat,
        onImage: @escaping (UIImage) -> Void,
        completion: (() -> Void)? = nil
    ) {
        if let bundledName,
           let bundled = LessonThumbnailLoader.bundledImage(
               named: bundledName,
               targetPixelSize: pixelSize,
               variant: .color
           ) {
            onImage(bundled)
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
            onImage: onImage,
            completion: completion
        )
    }

    private static func load(
        url: URL,
        remaining: [URL],
        pixelSize: CGFloat,
        onImage: @escaping (UIImage) -> Void,
        completion: (() -> Void)?
    ) {
        if let cached = LessonThumbnailLoader.cachedImage(
            for: url,
            targetPixelSize: pixelSize,
            variant: .color
        ) {
            onImage(cached)
            completion?()
            return
        }
        LessonThumbnailLoader.load(url: url, targetPixelSize: pixelSize, variant: .color) { image in
            if let image {
                onImage(image)
                completion?()
            } else if let next = remaining.first {
                load(
                    url: next,
                    remaining: Array(remaining.dropFirst()),
                    pixelSize: pixelSize,
                    onImage: onImage,
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
