//
//  DialogueQuizViewController.swift
//  shizen
//
//  One-question-per-page comprehension quiz for the nested dialogue pager.
//

import NNKit
import UIKit

// MARK: - DialogueQuizViewController

final class DialogueQuizViewController: UIViewController {

    private static let choiceHeight: CGFloat = 54
    private static let questionHorizontalInset: CGFloat = 20
    /// Must be at least the follow-along bottom buffer so a last evidence line
    /// can scroll clear of the play button, matching dialogue playback.
    private static let scrollBottomContentInsetExtra: CGFloat = 100

    private let pageViewController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal
    )
    private let evidenceAudioPlayer = GrammarAudioPlayer()

    private var questionPages: [DialogueQuizQuestionPageViewController] = []
    private var currentIndex = 0
    private var evidenceContext: DialogueQuizEvidenceContext?

    /// Host-driven top inset — same role as `DialogueExperimentViewController.nestedPagingTopContentInset`.
    private var nestedPagingTopContentInset: CGFloat = 0
    private var nestedPagingBottomContentInset: CGFloat = 0

    private var didFinishQuiz = false
    /// Fired once when every question has been answered correctly.
    var onQuizPassed: (() -> Void)?
    /// Fired once when every question has a selection, with the running score.
    var onQuizFinished: ((DialogueQuizScore) -> Void)?
    /// Host should refresh nested handoff when the active question scroll view changes.
    var onHandoffScrollViewChanged: (() -> Void)?
    /// Fired just before quiz evidence audio starts so the host can pause dialogue playback.
    var onEvidencePlaybackWillStart: (() -> Void)?
    /// Host should refresh the shared next-question transport control.
    var onNavigationChromeNeedsUpdate: (() -> Void)?

    var hasNextQuestion: Bool {
        currentIndex + 1 < questionPages.count
    }

    var hasFinishedAllQuestions: Bool { didFinishQuiz }

    var currentScore: DialogueQuizScore {
        DialogueQuizScore(
            correctCount: questionPages.filter(\.isSelectionCorrect).count,
            questionCount: questionPages.count
        )
    }

    var canAdvanceToNextQuestion: Bool {
        hasNextQuestion
            && questionPages.indices.contains(currentIndex)
            && questionPages[currentIndex].hasSelection
    }

    var currentQuestionHasEvidence: Bool {
        guard questionPages.indices.contains(currentIndex) else { return false }
        return !(evidenceContext?.sourceLines(for: questionPages[currentIndex].question).isEmpty ?? true)
    }

    var canPlayCurrentEvidence: Bool {
        currentQuestionHasEvidence
            && questionPages.indices.contains(currentIndex)
            && questionPages[currentIndex].hasSelection
    }

    private(set) var isPlayingCurrentEvidence = false

    /// Vertical scroll view for the currently visible question page (nested handoff).
    var handoffScrollView: UIScrollView {
        if questionPages.indices.contains(currentIndex) {
            return questionPages[currentIndex].scrollView
        }
        return placeholderScrollView
    }

    /// Used only when no questions are configured so the host always has a scroll view.
    private let placeholderScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.bounces = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = true
        scrollView.backgroundColor = .clear
        return scrollView
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.pageBackground
        installPageViewController()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        coordinateEvidenceSwipes()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || isBeingDismissed {
            stopEvidencePlayback()
        }
    }

    func configure(
        questions: [DialogueQuizQuestion],
        evidenceContext: DialogueQuizEvidenceContext? = nil
    ) {
        loadViewIfNeeded()
        didFinishQuiz = false
        currentIndex = 0
        self.evidenceContext = evidenceContext
        stopEvidencePlayback()

        questionPages = questions.enumerated().map { index, question in
            let sourceLines = evidenceContext?.sourceLines(for: question) ?? []
            let page = DialogueQuizQuestionPageViewController(
                questionNumber: index + 1,
                questionCount: questions.count,
                question: question,
                choiceHeight: Self.choiceHeight,
                horizontalInset: Self.questionHorizontalInset,
                sourceLines: sourceLines
            )
            page.onSelectionChanged = { [weak self, weak page] in
                guard let self, let page else { return }
                self.handleImmediateAnswer(on: page)
            }
            page.onRevealContentDidChange = { [weak self, weak page] in
                guard let self, let page else { return }
                self.handleRevealContentDidChange(on: page)
            }
            page.onFocusEvidenceLine = { [weak self] line in
                self?.presentSentenceFocus(for: line)
            }
            return page
        }

        if let first = questionPages.first {
            pageViewController.setViewControllers([first], direction: .forward, animated: false)
        } else if let visible = pageViewController.viewControllers, !visible.isEmpty {
            // UIPageViewController requires a non-empty set; leave the last page
            // briefly until the host hides the quiz page for an empty quiz.
            pageViewController.setViewControllers([visible[0]], direction: .forward, animated: false)
        }

        applyScrollContentInsets()
        onNavigationChromeNeedsUpdate?()
        onHandoffScrollViewChanged?()
        coordinateEvidenceSwipes()
    }

    func stopEvidencePlayback() {
        evidenceAudioPlayer.stop()
        clearPlaybackEmphasis()
        setPlayingCurrentEvidence(false)
    }

    func toggleCurrentEvidencePlayback() {
        if isPlayingCurrentEvidence {
            stopEvidencePlayback()
        } else {
            playCurrentEvidence()
        }
    }

    func playCurrentEvidence() {
        guard questionPages.indices.contains(currentIndex) else { return }
        playEvidence(for: questionPages[currentIndex].question, on: questionPages[currentIndex])
    }

    private func setPlayingCurrentEvidence(_ playing: Bool) {
        guard isPlayingCurrentEvidence != playing else { return }
        isPlayingCurrentEvidence = playing
        onNavigationChromeNeedsUpdate?()
    }

    private func clearPlaybackEmphasis() {
        for page in questionPages {
            page.setPlayingSpokenIndex(nil)
            page.applyEvidenceKaraoke(tokenSync: nil, time: 0)
        }
    }

    private func handleImmediateAnswer(on page: DialogueQuizQuestionPageViewController) {
        let allCorrect = !questionPages.isEmpty && questionPages.allSatisfy(\.isSelectionCorrect)

        if page.isSelectionCorrect {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if let point = page.selectedChoiceExplosionPoint() {
                ExplosionManager.trigger(.small, at: point)
            }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }

        let allAnswered = !questionPages.isEmpty && questionPages.allSatisfy(\.hasSelection)
        let justFinished = allAnswered && !didFinishQuiz
        if justFinished {
            didFinishQuiz = true
        }

        coordinateEvidenceSwipes()
        onNavigationChromeNeedsUpdate?()
        onHandoffScrollViewChanged?()
        if !page.isSelectionCorrect {
            page.scrollRevealedEvidenceIntoViewIfNeeded()
        }

        if justFinished {
            if allCorrect {
                onQuizPassed?()
            }
            onQuizFinished?(currentScore)
        }
    }

    private func handleRevealContentDidChange(on page: DialogueQuizQuestionPageViewController) {
        coordinateEvidenceSwipes()
        onHandoffScrollViewChanged?()
        page.scrollRevealedEvidenceIntoViewIfNeeded()
    }

    private var pagingScrollView: UIScrollView? {
        pageViewController.view.subviews.first { $0 is UIScrollView } as? UIScrollView
    }

    private func coordinateEvidenceSwipes() {
        let paging = pagingScrollView
        for page in questionPages {
            page.attachEvidenceSwipeCoordination(
                pagingScrollView: paging,
                from: self
            )
        }
    }

    private func presentSentenceFocus(for line: DialogueQuizSourceLine) {
        stopEvidencePlayback()
        onEvidencePlaybackWillStart?()

        let dialogueLineAudio: DialogueLineAudioReference?
        if let evidenceContext,
           evidenceContext.spokenLines.indices.contains(line.spokenIndex),
           (evidenceContext.publishedAudioUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || evidenceContext.audioKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) {
            dialogueLineAudio = DialogueLineAudioReference(
                publishedAudioUrl: evidenceContext.publishedAudioUrl,
                audioKey: evidenceContext.audioKey ?? "",
                cacheMetadata: evidenceContext.cacheMetadata,
                lineIndex: line.spokenIndex,
                dialogueLines: evidenceContext.spokenJapaneseTexts
            )
        } else {
            dialogueLineAudio = nil
        }

        let nuanceLines = (evidenceContext?.spokenLines ?? []).map {
            DialogueNuanceContext.Line(
                speaker: $0.speaker,
                japanese: $0.japanese,
                english: $0.english
            )
        }
        let dialogueContext = DialogueNuanceContext.around(
            lines: nuanceLines,
            focusedIndex: line.spokenIndex
        ) ?? .isolated(
            japanese: line.japanese,
            english: line.english,
            speaker: line.speaker
        )

        let tokens = evidenceContext?.tokenSync?.japaneseTokens(
            lineIndex: line.spokenIndex,
            in: line.japanese
        )
        let scrub = SentenceScrubExperimentViewController(
            sentence: line.japanese,
            englishTranslation: line.english,
            dialogueLineAudio: dialogueLineAudio,
            dialogueContext: dialogueContext,
            tokens: tokens,
            tokenSync: evidenceContext?.tokenSync
        )
        navigationController?.pushViewController(scrub, animated: true)
    }

    private func playEvidence(
        for question: DialogueQuizQuestion,
        on page: DialogueQuizQuestionPageViewController
    ) {
        guard let evidenceContext,
              let indices = evidenceContext.clampedSpokenIndices(for: question),
              let first = indices.first
        else { return }

        onEvidencePlaybackWillStart?()
        let dialogueLines = evidenceContext.spokenJapaneseTexts
        let fallback = dialogueLines[first]
        let tokenSync = evidenceContext.tokenSync
        let highlight: (Int?) -> Void = { [weak page] spokenIndex in
            page?.setPlayingSpokenIndex(spokenIndex)
        }
        let applyKaraoke: (TimeInterval) -> Void = { [weak page] time in
            page?.applyEvidenceKaraoke(tokenSync: tokenSync, time: time)
        }
        let finished = { [weak self, weak page] in
            highlight(nil)
            page?.applyEvidenceKaraoke(tokenSync: nil, time: 0)
            self?.setPlayingCurrentEvidence(false)
        }
        setPlayingCurrentEvidence(true)

        if indices.count == 1 {
            highlight(first)
            evidenceAudioPlayer.playDialogueLine(
                at: first,
                publishedAudioUrl: evidenceContext.publishedAudioUrl,
                audioKey: evidenceContext.audioKey,
                cacheMetadata: evidenceContext.cacheMetadata,
                dialogueLines: dialogueLines,
                fallbackText: fallback,
                onTime: applyKaraoke,
                onFinished: finished
            )
            return
        }

        evidenceAudioPlayer.playDialogueSequence(
            spokenIndices: indices,
            publishedAudioUrl: evidenceContext.publishedAudioUrl,
            audioKey: evidenceContext.audioKey,
            cacheMetadata: evidenceContext.cacheMetadata,
            dialogueLines: dialogueLines,
            fallbackText: fallback,
            onSpokenIndexStart: { highlight($0) },
            onTime: applyKaraoke,
            onFinished: finished
        )
    }

    /// Same contract as `DialogueExperimentViewController.applyNestedPagingTopContentInset`.
    /// Host passes the nested-pager top inset; content sits in that band via scroll
    /// `contentInset` (edge-to-edge layout, no safeAreaLayoutGuide pinning).
    func applyNestedPagingTopContentInset(_ inset: CGFloat) {
        loadViewIfNeeded()
        nestedPagingTopContentInset = inset
        applyScrollContentInsets()
    }

    /// Bottom clearance for scroll content (host transport chrome / home indicator).
    func applyNestedPagingBottomContentInset(_ inset: CGFloat) {
        nestedPagingBottomContentInset = inset
        applyScrollContentInsets()
    }

    private func applyScrollContentInsets() {
        let topInset = nestedPagingTopContentInset
        let bottomInset = nestedPagingBottomContentInset
            + Self.scrollBottomContentInsetExtra
        let inset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        let indicatorInsets = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        for page in questionPages {
            page.scrollView.contentInset = inset
            page.scrollView.verticalScrollIndicatorInsets = indicatorInsets
        }
        placeholderScrollView.contentInset = inset
        placeholderScrollView.verticalScrollIndicatorInsets = indicatorInsets
    }

    func ownsScrollView(_ scrollView: UIScrollView) -> Bool {
        if scrollView === placeholderScrollView { return true }
        return questionPages.contains { $0.scrollView === scrollView }
    }

    func settleHandoffScrollAtTopIfNeeded() {
        let scrollView = handoffScrollView
        guard scrollView.contentOffset.y <= 1 else { return }
        scrollView.contentOffset.y = -scrollView.adjustedContentInset.top
    }

    // MARK: - Layout

    private func installPageViewController() {
        addChild(pageViewController)
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        pageViewController.dataSource = self
        pageViewController.delegate = self
        pageViewController.view.insetsLayoutMarginsFromSafeArea = false
        view.addSubview(pageViewController.view)
        pageViewController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func goToNextQuestion() {
        let target = currentIndex + 1
        guard questionPages.indices.contains(target),
              questionPages[currentIndex].hasSelection
        else { return }
        showQuestion(at: target, direction: .forward)
    }

    private func showQuestion(
        at target: Int,
        direction: UIPageViewController.NavigationDirection
    ) {
        guard questionPages.indices.contains(target), target != currentIndex else { return }
        pageViewController.setViewControllers(
            [questionPages[target]],
            direction: direction,
            animated: true
        ) { [weak self] finished in
            guard let self, finished else { return }
            if target != self.currentIndex {
                self.stopEvidencePlayback()
            }
            self.currentIndex = target
            self.onNavigationChromeNeedsUpdate?()
            self.onHandoffScrollViewChanged?()
            self.coordinateEvidenceSwipes()
        }
    }

    private func updateCurrentIndex(from viewController: UIViewController) {
        guard let page = viewController as? DialogueQuizQuestionPageViewController,
              let index = questionPages.firstIndex(where: { $0 === page })
        else { return }
        if index != currentIndex {
            stopEvidencePlayback()
        }
        currentIndex = index
        onNavigationChromeNeedsUpdate?()
        onHandoffScrollViewChanged?()
        coordinateEvidenceSwipes()
    }
}

// MARK: - UIPageViewControllerDataSource & Delegate

extension DialogueQuizViewController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? DialogueQuizQuestionPageViewController,
              let index = questionPages.firstIndex(where: { $0 === page }),
              index > 0
        else { return nil }
        return questionPages[index - 1]
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? DialogueQuizQuestionPageViewController,
              let index = questionPages.firstIndex(where: { $0 === page }),
              index + 1 < questionPages.count,
              page.hasSelection
        else { return nil }
        return questionPages[index + 1]
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard finished, completed,
              let visible = pageViewController.viewControllers?.first
        else { return }
        updateCurrentIndex(from: visible)
    }
}

// MARK: - DialogueQuizQuestionPageViewController

final class DialogueQuizQuestionPageViewController: UIViewController {

    /// Extra space kept above the playing line when follow-along scrolling.
    private static let followAlongTopBuffer: CGFloat = 56
    /// Extra space kept below the English (or bubble) so it clears the play
    /// button and its edge-effect blur — same value as dialogue playback.
    private static let followAlongBottomBuffer: CGFloat = 100

    let scrollView = UIScrollView()
    private let questionView: DialogueQuizQuestionView
    private let horizontalInset: CGFloat
    let question: DialogueQuizQuestion

    var hasSelection: Bool { questionView.hasSelection }
    var isSelectionCorrect: Bool { questionView.isSelectionCorrect }

    func selectedChoiceExplosionPoint() -> CGPoint? {
        guard let choice = questionView.selectedChoiceView, let window = choice.window else {
            return nil
        }
        return choice.convert(CGPoint(x: choice.bounds.midX, y: choice.bounds.midY), to: window)
    }
    var onSelectionChanged: (() -> Void)? {
        get { questionView.onSelectionChanged }
        set { questionView.onSelectionChanged = newValue }
    }
    var onRevealContentDidChange: (() -> Void)? {
        get { questionView.onRevealContentDidChange }
        set { questionView.onRevealContentDidChange = newValue }
    }
    var onFocusEvidenceLine: ((DialogueQuizSourceLine) -> Void)? {
        get { questionView.onFocusEvidenceLine }
        set { questionView.onFocusEvidenceLine = newValue }
    }

    init(
        questionNumber: Int,
        questionCount: Int,
        question: DialogueQuizQuestion,
        choiceHeight: CGFloat,
        horizontalInset: CGFloat,
        sourceLines: [DialogueQuizSourceLine] = []
    ) {
        self.question = question
        self.horizontalInset = horizontalInset
        questionView = DialogueQuizQuestionView(
            questionNumber: questionNumber,
            question: question,
            choiceHeight: choiceHeight,
            questionCount: questionCount,
            sourceLines: sourceLines
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .clear
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = true
        scrollView.bounces = true
        scrollView.decelerationRate = .normal
        scrollView.delaysContentTouches = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.topEdgeEffect.style = .soft
        scrollView.topEdgeEffect.isHidden = false
        scrollView.bottomEdgeEffect.style = .soft
        scrollView.bottomEdgeEffect.isHidden = false
        view.addSubview(scrollView)

        questionView.translatesAutoresizingMaskIntoConstraints = false
        // Match dialogue: content starts at the content layout guide; host inset
        // is applied via contentInset, not a top constraint constant.
        questionView.insetsLayoutMarginsFromSafeArea = false
        scrollView.addSubview(questionView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            questionView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            questionView.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                constant: horizontalInset
            ),
            questionView.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                constant: -horizontalInset
            ),
            questionView.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                constant: -32
            ),
            questionView.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -horizontalInset * 2
            ),
        ])

        questionView.hostScrollView = scrollView
    }

    func scrollRevealedEvidenceIntoViewIfNeeded() {
        view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        guard questionView.revealedEvidenceScrollTarget != nil else { return }

        var rect = CGRect.null
        questionView.withSettledEvidenceLayout {
            guard let label = questionView.revealedEvidenceScrollTarget else { return }
            rect = label.convert(label.bounds, to: scrollView).insetBy(dx: 0, dy: -16)
            if let peek = questionView.revealedEvidencePeekTarget {
                let peekRect = peek.convert(peek.bounds, to: scrollView)
                let visibleHeight = min(peekRect.height, 140)
                rect = rect.union(
                    CGRect(x: peekRect.minX, y: peekRect.minY, width: peekRect.width, height: visibleHeight)
                )
            }
        }

        guard !rect.isNull else { return }
        let visible = scrollView.bounds.inset(by: scrollView.adjustedContentInset)
        guard !visible.contains(rect) else { return }
        scrollView.scrollRectToVisible(rect, animated: true)
    }

    func attachEvidenceSwipeCoordination(
        pagingScrollView: UIScrollView?,
        from viewController: UIViewController?
    ) {
        questionView.hostScrollView = scrollView
        questionView.configureEvidenceSwipeDeferral(
            pagingScrollView: pagingScrollView,
            from: viewController
        )
    }

    func revealResult() {
        questionView.revealResult()
    }

    func setPlayingSpokenIndex(_ spokenIndex: Int?) {
        questionView.setPlayingSpokenIndex(spokenIndex)
        if let spokenIndex, questionView.evidenceLineCount > 1 {
            scrollPlayingEvidenceLineIntoView(spokenIndex: spokenIndex)
        }
    }

    /// Follow-along: keep the playing evidence line — through its English —
    /// above the play button, same contract as dialogue `scrollLineIntoView`.
    private func scrollPlayingEvidenceLineIntoView(spokenIndex: Int) {
        view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        guard !scrollView.isTracking, !scrollView.isDecelerating else { return }

        var rowFrame = CGRect.null
        questionView.withSettledEvidenceLayout {
            guard let row = questionView.evidenceLineView(forSpokenIndex: spokenIndex),
                  !row.isHidden,
                  row.bounds.height > 0
            else { return }
            rowFrame = row.convert(row.bounds, to: scrollView)
        }
        guard !rowFrame.isNull else { return }

        let inset = scrollView.adjustedContentInset
        let currentY = scrollView.contentOffset.y
        let visibleBottom = currentY + scrollView.bounds.height
            - inset.bottom - Self.followAlongBottomBuffer
        let visibleTop = currentY + Self.followAlongTopBuffer

        let targetY: CGFloat
        if rowFrame.maxY > visibleBottom {
            targetY = rowFrame.maxY - scrollView.bounds.height
                + inset.bottom + Self.followAlongBottomBuffer
        } else if rowFrame.minY < visibleTop {
            targetY = rowFrame.minY - Self.followAlongTopBuffer
        } else {
            return
        }

        guard let endY = scrollView.clampedContentOffsetY(targetY, allowNoScroll: true),
              abs(endY - currentY) >= 1
        else { return }

        UIView.animate(
            withDuration: DialogueBubbleLayout.emphasisDuration,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]
        ) {
            self.scrollView.setClampedContentOffsetY(endY, allowsScrollCallback: false)
        }
    }

    func applyEvidenceKaraoke(tokenSync: DialogueTokenSync?, time: TimeInterval) {
        questionView.applyEvidenceKaraoke(tokenSync: tokenSync, time: time)
    }
}

private extension UIScrollView {
    func clampedContentOffsetY(_ y: CGFloat, allowNoScroll: Bool) -> CGFloat? {
        let inset = adjustedContentInset
        let minY = -inset.top
        let maxY = max(minY, contentSize.height - bounds.height + inset.bottom)
        if maxY <= minY {
            if allowNoScroll { return nil }
            return minY
        }
        return min(max(y, minY), maxY)
    }

    func setClampedContentOffsetY(_ y: CGFloat, allowsScrollCallback: Bool) {
        let previousDelegate = delegate
        if !allowsScrollCallback { delegate = nil }
        let clampedY = clampedContentOffsetY(y, allowNoScroll: false) ?? y
        contentOffset = CGPoint(x: 0, y: clampedY)
        if !allowsScrollCallback { delegate = previousDelegate }
    }
}
