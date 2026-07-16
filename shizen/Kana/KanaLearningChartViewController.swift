//
//  KanaLearningChartViewController.swift
//  shizen
//
//  Progress-aware hiragana chart; locked glyphs appear greyed out.
//

import UIKit

final class KanaLearningChartViewController: UIViewController {

    private let progressStore: KanaProgressStore
    private let script: KanaScript
    private let scrollView = UIScrollView()
    private let reviewButton = PrimaryButton()
    private let inProgressValueLabel = UILabel()
    private let masteredValueLabel = UILabel()
    private var chartViews: [KanaGridChartView] = []
    private var cardRegistry: [String: KanaCard] = [:]
    private var didBuildCharts = false
    private var isSelecting = false
    private var selectedKana: Set<String> = []
    private var activeLessonCoordinator: KanaLessonCoordinator?

    init(progressStore: KanaProgressStore = .shared, script: KanaScript = .hiragana) {
        self.progressStore = progressStore
        self.script = script
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = script == .hiragana ? "Your hiragana" : "Your katakana"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground
        configureHeader()
        configureScroll()
        buildChartsIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        progressStore.reload()
        updateProgressStats()
        refreshChartProgress()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateScrollInsetsForReviewButton()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateScrollInsetsForReviewButton()
        scrollView.bringSubviewToFront(reviewButton)
    }

    private func configureHeader() {
        inProgressValueLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        inProgressValueLabel.textAlignment = .center

        masteredValueLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        masteredValueLabel.textAlignment = .center

        updateProgressStats()
    }

    private func updateProgressStats() {
        inProgressValueLabel.text = "\(progressStore.inProgressGlyphCount(script: script))"
        masteredValueLabel.text = "\(progressStore.masteredGlyphCount(script: script))"
    }

    private func makeStatColumn(title: String, valueLabel: UILabel) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .center
        return stack
    }

    private func configureScroll() {
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.semanticContentAttribute = .forceLeftToRight
        view.addSubview(scrollView)

        reviewButton.primaryStyle = .blue
        reviewButton.setTitle("Start a Review", for: .normal)
        reviewButton.translatesAutoresizingMaskIntoConstraints = false
        reviewButton.addTarget(self, action: #selector(reviewButtonTapped), for: .touchUpInside)
        scrollView.addSubview(reviewButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            reviewButton.leadingAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.leadingAnchor,
                constant: PrimaryButton.horizontalInset
            ),
            reviewButton.trailingAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.trailingAnchor,
                constant: -PrimaryButton.horizontalInset
            ),
            reviewButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -12
            ),
            reviewButton.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),
        ])
    }

    private func updateScrollInsetsForReviewButton() {
        let buttonArea = PrimaryButton.preferredHeight + 24
        scrollView.contentInset.bottom = buttonArea
        scrollView.verticalScrollIndicatorInsets.bottom = buttonArea
    }

    private func currentDisplayMode() -> KanaChartDisplayMode {
        KanaChartDisplayMode.learning(
            unlockedGlyphs: progressStore.unlockedGlyphs,
            studyCountForKana: { [progressStore] kana in progressStore.studyCount(for: kana) }
        )
    }

    private func buildChartsIfNeeded() {
        guard !didBuildCharts else { return }
        didBuildCharts = true

        let displayMode = currentDisplayMode()
        let seionChart = KanaGridChartView(kind: .seion, script: script, displayMode: displayMode)
        let voicedChart = KanaGridChartView(kind: .voiced, script: script, displayMode: displayMode)
        let yoonChart = KanaGridChartView(kind: .yoon, script: script, displayMode: displayMode)
        chartViews = [seionChart, voicedChart, yoonChart]
        wireChartInteractions()

        func makeCaption(_ text: String) -> UILabel {
            let label = UILabel()
            label.text = text
            label.textAlignment = .center
            label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .footnote)
            label.textColor = .secondaryLabel
            return label
        }

        let voicedCaption = makeCaption("Voiced & semi-voiced — unlock after seion")
        let yoonCaption = makeCaption("Yōon — unlock after seion")

        let statsRow = UIStackView(arrangedSubviews: [
            makeStatColumn(title: "In Progress", valueLabel: inProgressValueLabel),
            makeStatColumn(title: "Mastered", valueLabel: masteredValueLabel),
        ])
        statsRow.axis = .horizontal
        statsRow.distribution = .fillEqually
        statsRow.spacing = 24

        let contentStack = UIStackView(arrangedSubviews: [
            statsRow, seionChart, voicedCaption, voicedChart, yoonCaption, yoonChart,
        ])
        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.semanticContentAttribute = .forceLeftToRight
        contentStack.setCustomSpacing(28, after: seionChart)
        contentStack.setCustomSpacing(28, after: voicedChart)
        for sub in [seionChart, voicedChart, yoonChart] {
            sub.semanticContentAttribute = .forceLeftToRight
        }

        scrollView.addSubview(contentStack)

        cardRegistry = Dictionary(
            uniqueKeysWithValues: chartViews
                .flatMap { $0.allCards() }
                .compactMap { card in
                    guard let kana = card.kana else { return nil }
                    return (kana, card)
                }
        )

        let inset: CGFloat = 20
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: inset),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -inset),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: inset),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -inset),
        ])

        updateScrollInsetsForReviewButton()
        scrollView.bringSubviewToFront(reviewButton)
    }

    private func refreshChartProgress() {
        guard didBuildCharts else { return }
        let displayMode = currentDisplayMode()
        chartViews.forEach { $0.update(displayMode: displayMode) }
        wireChartInteractions()

        if isSelecting {
            applySelectionVisuals()
        }
    }

    private func wireChartInteractions() {
        chartViews.forEach { chart in
            chart.setInteractionHandler { [weak self] kana, romaji in
                self?.handleKanaInteraction(kana: kana, romaji: romaji)
            }
        }
    }

    private func handleKanaInteraction(kana: String, romaji: String) {
        if isSelecting {
            toggleSelection(for: kana)
            return
        }
        let detail = KanaDetailViewController(kana: kana, romaji: romaji)
        navigationController?.pushViewController(detail, animated: true)
    }

    @objc private func reviewButtonTapped() {
        if isSelecting {
            launchCustomReview()
        } else {
            enterSelectionMode()
        }
    }

    @objc private func cancelSelectionTapped() {
        exitSelectionMode()
    }

    private func enterSelectionMode() {
        isSelecting = true
        selectedKana.removeAll()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Cancel",
            style: .plain,
            target: self,
            action: #selector(cancelSelectionTapped)
        )
        applySelectionVisuals()
        updateReviewButton()
    }

    private func exitSelectionMode() {
        isSelecting = false
        selectedKana.removeAll()
        navigationItem.rightBarButtonItem = nil
        for card in cardRegistry.values {
            card.isChartSelected = false
            card.isChartSelectionEnabled = false
        }
        updateReviewButton()
    }

    private func toggleSelection(for kana: String) {
        guard progressStore.unlockedGlyphs.contains(kana) else { return }
        if selectedKana.contains(kana) {
            selectedKana.remove(kana)
        } else {
            selectedKana.insert(kana)
        }
        cardRegistry[kana]?.isChartSelected = selectedKana.contains(kana)
        updateReviewButton()
    }

    private func applySelectionVisuals() {
        for (kana, card) in cardRegistry {
            let isUnlocked = progressStore.unlockedGlyphs.contains(kana)
            card.isChartSelectionEnabled = isSelecting && isUnlocked
            card.isChartSelected = selectedKana.contains(kana)
        }
    }

    private func updateReviewButton() {
        if isSelecting {
            let count = selectedKana.count
            reviewButton.setTitle(count == 1 ? "Review (1)" : "Review (\(count))", for: .normal)
            reviewButton.isEnabled = count > 0
        } else {
            reviewButton.setTitle("Start a Review", for: .normal)
            reviewButton.isEnabled = true
        }
    }

    private func launchCustomReview() {
        guard !selectedKana.isEmpty else { return }
        let selection = selectedKana
        exitSelectionMode()

        let coordinator = KanaLessonCoordinator(
            kind: .customReview(selectedKana: selection, script: script),
            row: nil,
            progressStore: progressStore
        )
        coordinator.delegate = self
        activeLessonCoordinator = coordinator
        coordinator.present(from: self)
    }
}

// MARK: - KanaLessonSessionDelegate

extension KanaLearningChartViewController: KanaLessonSessionDelegate {
    func kanaLessonSessionDidFinish(kind: KanaSessionKind, row: KanaRow?, metrics: KanaLessonSessionMetrics) {
        activeLessonCoordinator = nil
        dismiss(animated: true) { [weak self] in
            self?.progressStore.reload()
            self?.updateProgressStats()
            self?.refreshChartProgress()
        }
    }

    func kanaLessonSessionDidFail(kind: KanaSessionKind, row: KanaRow?, metrics: KanaLessonSessionMetrics) {
        activeLessonCoordinator = nil
        dismiss(animated: true)
    }

    func kanaLessonSessionDidCancel(kind: KanaSessionKind, row: KanaRow?) {
        activeLessonCoordinator = nil
        dismiss(animated: true)
    }
}
