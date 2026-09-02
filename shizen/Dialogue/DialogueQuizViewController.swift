//
//  DialogueQuizViewController.swift
//  shizen
//
//  One-question-per-page comprehension quiz for the nested dialogue pager.
//

import UIKit

// MARK: - DialogueQuizViewController

final class DialogueQuizViewController: UIViewController {

    private static let choiceHeight: CGFloat = 45
    private static let pageControlHeight: CGFloat = 26
    private static let pageControlTopSpacing: CGFloat = 8
    private static let questionHorizontalInset: CGFloat = 20
    private static let scrollBottomContentInsetExtra: CGFloat = 24

    private let pageControl = UIPageControl()
    private let pageViewController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal
    )

    private var questionPages: [DialogueQuizQuestionPageViewController] = []
    private var currentIndex = 0
    private var pageControlBottomConstraint: NSLayoutConstraint!
    private var pageControlHeightConstraint: NSLayoutConstraint!

    /// Host-driven top inset — same role as `DialogueExperimentViewController.nestedPagingTopContentInset`.
    private var nestedPagingTopContentInset: CGFloat = 0
    private var nestedPagingBottomContentInset: CGFloat = 0

    private var didPassQuiz = false
    /// Fired once when every question has been answered correctly.
    var onQuizPassed: (() -> Void)?
    /// Host should refresh nested handoff when the active question scroll view changes.
    var onHandoffScrollViewChanged: (() -> Void)?

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
        installChrome()
    }

    func configure(questions: [DialogueQuizQuestion]) {
        loadViewIfNeeded()
        didPassQuiz = false
        currentIndex = 0

        questionPages = questions.enumerated().map { index, question in
            let page = DialogueQuizQuestionPageViewController(
                questionNumber: index + 1,
                question: question,
                choiceHeight: Self.choiceHeight,
                horizontalInset: Self.questionHorizontalInset
            )
            page.onSelectionChanged = { [weak self, weak page] in
                guard let self, let page else { return }
                self.handleImmediateAnswer(on: page)
            }
            return page
        }

        pageControl.numberOfPages = questions.count
        pageControl.currentPage = 0
        updatePageControlVisibility(pageCount: questions.count)

        if let first = questionPages.first {
            pageViewController.setViewControllers([first], direction: .forward, animated: false)
        } else if let visible = pageViewController.viewControllers, !visible.isEmpty {
            // UIPageViewController requires a non-empty set; leave the last page
            // briefly until the host hides the quiz page for an empty quiz.
            pageViewController.setViewControllers([visible[0]], direction: .forward, animated: false)
        }

        applyScrollContentInsets()
        onHandoffScrollViewChanged?()
    }

    private func updatePageControlVisibility(pageCount: Int) {
        let showsControl = pageCount > 1
        pageControl.isHidden = !showsControl
        pageControlHeightConstraint.constant = showsControl ? Self.pageControlHeight : 0
        applyScrollContentInsets()
    }

    private func handleImmediateAnswer(on page: DialogueQuizQuestionPageViewController) {
        let allCorrect = !questionPages.isEmpty && questionPages.allSatisfy(\.isSelectionCorrect)

        if page.isSelectionCorrect {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if allCorrect {
                ExperimentFeedbackSound.playSuccess(
                    for: .kanaSpelling,
                    spellingSyllableCount: questionPages.count
                )
            } else {
                ExperimentFeedbackSound.playSuccess(for: .kanaSpelling)
            }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            ExperimentFeedbackSound.playIncorrect()
        }

        if allCorrect, !didPassQuiz {
            didPassQuiz = true
            onQuizPassed?()
        }
    }

    /// Same contract as `DialogueExperimentViewController.applyNestedPagingTopContentInset`.
    /// Host passes the nested-pager top inset; content sits in that band via scroll
    /// `contentInset` (edge-to-edge layout, no safeAreaLayoutGuide pinning).
    func applyNestedPagingTopContentInset(_ inset: CGFloat) {
        loadViewIfNeeded()
        nestedPagingTopContentInset = inset
        applyScrollContentInsets()
    }

    /// Bottom clearance for scroll content (page control / home indicator).
    /// Does not move the page control — that uses `applyPageControlBottomInset`.
    func applyNestedPagingBottomContentInset(_ inset: CGFloat) {
        nestedPagingBottomContentInset = inset
        applyScrollContentInsets()
    }

    /// Stable bottom offset for the page control (home-indicator clearance).
    func applyPageControlBottomInset(_ inset: CGFloat) {
        loadViewIfNeeded()
        guard abs(pageControlBottomConstraint.constant + inset) > 0.5 else { return }
        pageControlBottomConstraint.constant = -inset
    }

    private func applyScrollContentInsets() {
        let pageControlBand = pageControl.isHidden
            ? 0
            : Self.pageControlHeight + Self.pageControlTopSpacing
        let topInset = nestedPagingTopContentInset
        let bottomInset = nestedPagingBottomContentInset
            + pageControlBand
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

    private func installChrome() {
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.currentPageIndicatorTintColor = .label
        pageControl.pageIndicatorTintColor = UIColor.secondaryLabel.withAlphaComponent(0.35)
        pageControl.hidesForSinglePage = true
        pageControl.addAction(UIAction { [weak self] _ in
            self?.pageControlChanged()
        }, for: .valueChanged)
        view.addSubview(pageControl)

        pageControlBottomConstraint = pageControl.bottomAnchor.constraint(
            equalTo: view.bottomAnchor,
            constant: 0
        )
        pageControlHeightConstraint = pageControl.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            pageControlBottomConstraint,
            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            pageControl.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            pageControlHeightConstraint,
        ])
    }

    private func pageControlChanged() {
        let target = pageControl.currentPage
        guard questionPages.indices.contains(target), target != currentIndex else { return }
        let direction: UIPageViewController.NavigationDirection = target > currentIndex ? .forward : .reverse
        pageViewController.setViewControllers(
            [questionPages[target]],
            direction: direction,
            animated: true
        ) { [weak self] finished in
            guard let self, finished else { return }
            self.currentIndex = target
            self.onHandoffScrollViewChanged?()
        }
    }

    private func updateCurrentIndex(from viewController: UIViewController) {
        guard let page = viewController as? DialogueQuizQuestionPageViewController,
              let index = questionPages.firstIndex(where: { $0 === page })
        else { return }
        currentIndex = index
        pageControl.currentPage = index
        onHandoffScrollViewChanged?()
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
              index + 1 < questionPages.count
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

    let scrollView = UIScrollView()
    private let questionView: DialogueQuizQuestionView
    private let horizontalInset: CGFloat

    var hasSelection: Bool { questionView.hasSelection }
    var isSelectionCorrect: Bool { questionView.isSelectionCorrect }
    var onSelectionChanged: (() -> Void)? {
        get { questionView.onSelectionChanged }
        set { questionView.onSelectionChanged = newValue }
    }

    init(
        questionNumber: Int,
        question: DialogueQuizQuestion,
        choiceHeight: CGFloat,
        horizontalInset: CGFloat
    ) {
        self.horizontalInset = horizontalInset
        questionView = DialogueQuizQuestionView(
            questionNumber: questionNumber,
            question: question,
            choiceHeight: choiceHeight
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
    }

    func revealResult() {
        questionView.revealResult()
    }
}
