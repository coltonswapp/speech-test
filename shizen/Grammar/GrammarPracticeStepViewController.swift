//
//  GrammarPracticeStepViewController.swift
//  shizen
//

import InteractionKit
import UIKit

final class GrammarPracticeStepViewController: UIViewController {

    var onResult: ((Bool) -> Void)?
    var onSeeInContext: ((String) -> Void)?

    private let item: GrammarPracticeItem
    private let scrubbableSentenceView = ScrubbableSentenceView(engine: JapaneseScrubSentenceEngine.shared)
    private let promptLabel = UILabel()
    private let choicesStack = UIStackView()
    private var choiceButtons: [KanaChoiceButton] = []
    private var checkState: LessonMultipleChoiceCheckState!

    private let contentScrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let buttonContainer = UIView()
    private let primaryButton = PrimaryButton()
    private let seeInContextButton = UIButton(type: .system)
    private var primaryButtonBottomConstraint: NSLayoutConstraint?
    private var didInstallSeeInContextButton = false

    private static let contentHorizontalInset: CGFloat = 20
    private static let buttonBottomInset = ProgressiveStepViewController.buttonBottomInset
    private static let contentToButtonSpacing = ProgressiveStepViewController.contentToButtonSpacing

    init(item: GrammarPracticeItem) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.pageBackground
        buildUI()
    }

    private func buildUI() {
        let instruction = item.kind == .meaningChoice
            ? "What does this sentence mean?"
            : "Pick the correct option."

        let instructionLabel = UILabel()
        LessonInstructionLabel.apply(to: instructionLabel)
        instructionLabel.text = instruction
        instructionLabel.textAlignment = .center

        var promptViews: [UIView] = [instructionLabel]

        switch item.kind {
        case .meaningChoice:
            if let japanese = item.japanese {
                scrubbableSentenceView.showCalloutOnScrub = true
                scrubbableSentenceView.sentenceLineView.textAlignment = .center
                scrubbableSentenceView.configure(
                    sentence: japanese,
                    font: GrammarJapaneseTypography.drillPromptFont,
                    showsFurigana: true
                )
                scrubbableSentenceView.bindDismissOnTap(view)
                promptViews.append(scrubbableSentenceView)
            }
        case .contrastChoice:
            promptLabel.textAlignment = .center
            promptLabel.numberOfLines = 0
            promptLabel.font = .preferredFont(forTextStyle: .subheadline)
            promptLabel.textColor = .secondaryLabel
            promptLabel.text = item.contrastLabel
            promptViews.append(promptLabel)
            if let rule = item.ruleTargeted, !rule.isEmpty {
                let ruleLabel = UILabel()
                ruleLabel.textAlignment = .center
                ruleLabel.numberOfLines = 0
                ruleLabel.font = .preferredFont(forTextStyle: .footnote)
                ruleLabel.textColor = .tertiaryLabel
                ruleLabel.text = rule
                promptViews.append(ruleLabel)
            }
        }

        choicesStack.axis = .vertical
        choicesStack.spacing = item.kind == .contrastChoice ? 8 : 10

        let labelStyle: KanaChoiceButtonLabelStyle = item.kind == .contrastChoice ? .grammarForm : .compact
        if item.kind == .contrastChoice {
            choiceButtons = LessonChoiceGrid.rebuild(
                in: choicesStack,
                choices: item.choices,
                labelStyle: labelStyle,
                spacing: 8,
                target: self,
                action: #selector(choiceTapped(_:))
            )
        } else {
            choiceButtons = LessonChoiceList.rebuild(
                in: choicesStack,
                choices: item.choices,
                labelStyle: labelStyle,
                spacing: 10,
                target: self,
                action: #selector(choiceTapped(_:))
            )
        }

        checkState = LessonMultipleChoiceCheckState(
            choices: choiceButtons,
            correctValue: item.correctChoice,
            successExercise: .kanaDiscovery
        )
        checkState.onResult = { [weak self] success in
            guard let self else { return }
            self.onResult?(success)
            self.primaryButton.setTitle("Continue", for: .normal)
            self.primaryButton.removeTarget(nil, action: nil, for: .allEvents)
            self.primaryButton.addTarget(self, action: #selector(self.continueTapped), for: .touchUpInside)
            if !success, let scenarioID = self.item.sourceScenarioId {
                self.showSeeInContextButton(scenarioID: scenarioID)
            }
        }

        primaryButton.setTitle("Check", for: .normal)
        primaryButton.addTarget(self, action: #selector(checkTapped), for: .touchUpInside)

        installChrome()
        installContent(promptViews: promptViews)
        updateCheckButtonState()
    }

    private func installChrome() {
        contentScrollView.translatesAutoresizingMaskIntoConstraints = false
        contentScrollView.alwaysBounceVertical = true
        contentScrollView.alwaysBounceHorizontal = false
        contentScrollView.showsHorizontalScrollIndicator = false
        contentScrollView.isDirectionalLockEnabled = true
        contentScrollView.contentInsetAdjustmentBehavior = .never

        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.backgroundColor = .clear

        primaryButton.translatesAutoresizingMaskIntoConstraints = false

        seeInContextButton.translatesAutoresizingMaskIntoConstraints = false
        seeInContextButton.isHidden = true
        var seeInContextConfig = UIButton.Configuration.plain()
        seeInContextConfig.title = "See in context"
        seeInContextConfig.baseForegroundColor = .secondaryLabel
        seeInContextButton.configuration = seeInContextConfig

        view.addSubview(contentScrollView)
        contentScrollView.addSubview(contentStack)
        view.addSubview(buttonContainer)
        buttonContainer.addSubview(primaryButton)

        let buttonInset = PrimaryButton.horizontalInset
        let primaryBottom = primaryButton.bottomAnchor.constraint(
            equalTo: buttonContainer.safeAreaLayoutGuide.bottomAnchor,
            constant: -Self.buttonBottomInset
        )
        primaryButtonBottomConstraint = primaryBottom

        NSLayoutConstraint.activate([
            contentScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            contentScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(
                equalTo: contentScrollView.contentLayoutGuide.topAnchor,
                constant: 16
            ),
            contentStack.leadingAnchor.constraint(
                equalTo: contentScrollView.frameLayoutGuide.leadingAnchor,
                constant: Self.contentHorizontalInset
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: contentScrollView.frameLayoutGuide.trailingAnchor,
                constant: -Self.contentHorizontalInset
            ),
            contentStack.bottomAnchor.constraint(
                equalTo: contentScrollView.contentLayoutGuide.bottomAnchor,
                constant: -16
            ),
            contentStack.widthAnchor.constraint(
                equalTo: contentScrollView.frameLayoutGuide.widthAnchor,
                constant: -Self.contentHorizontalInset * 2
            ),

            buttonContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            buttonContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            buttonContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            primaryButton.topAnchor.constraint(
                equalTo: buttonContainer.topAnchor,
                constant: Self.contentToButtonSpacing
            ),
            primaryButton.leadingAnchor.constraint(
                equalTo: buttonContainer.leadingAnchor,
                constant: buttonInset
            ),
            primaryButton.trailingAnchor.constraint(
                equalTo: buttonContainer.trailingAnchor,
                constant: -buttonInset
            ),
            primaryBottom,
            primaryButton.heightAnchor.constraint(equalToConstant: PrimaryButton.preferredHeight),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyBottomContentInsetIfNeeded()
    }

    private func applyBottomContentInsetIfNeeded() {
        let inset = max(buttonContainer.bounds.height, 0)
        guard abs(contentScrollView.contentInset.bottom - inset) >= 0.5 else { return }
        contentScrollView.contentInset.bottom = inset
        contentScrollView.verticalScrollIndicatorInsets.bottom = inset
    }

    private func installContent(promptViews: [UIView]) {
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for view in promptViews {
            contentStack.addArrangedSubview(view)
        }
        contentStack.addArrangedSubview(choicesStack)
    }

    private func showSeeInContextButton(scenarioID: String) {
        guard !didInstallSeeInContextButton else { return }
        didInstallSeeInContextButton = true

        seeInContextButton.isHidden = false
        seeInContextButton.removeTarget(nil, action: nil, for: .allEvents)
        seeInContextButton.addAction(UIAction { [weak self] _ in
            self?.onSeeInContext?(scenarioID)
        }, for: .touchUpInside)

        buttonContainer.addSubview(seeInContextButton)

        primaryButtonBottomConstraint?.isActive = false
        primaryButtonBottomConstraint = primaryButton.bottomAnchor.constraint(
            equalTo: seeInContextButton.topAnchor,
            constant: -Self.contentToButtonSpacing
        )

        NSLayoutConstraint.activate([
            seeInContextButton.centerXAnchor.constraint(equalTo: buttonContainer.centerXAnchor),
            seeInContextButton.bottomAnchor.constraint(
                equalTo: buttonContainer.safeAreaLayoutGuide.bottomAnchor,
                constant: -Self.buttonBottomInset
            ),
            primaryButtonBottomConstraint!,
        ])

        applyBottomContentInsetIfNeeded()
    }

    @objc private func choiceTapped(_ sender: KanaChoiceButton) {
        checkState.select(sender)
        updateCheckButtonState()
    }

    @objc private func checkTapped() {
        checkState.check { [weak self] in
            self?.updateCheckButtonState()
        }
    }

    @objc private func continueTapped() {
        if let parent = parent as? GrammarPracticeContainerViewController {
            parent.advance()
        }
    }

    private func updateCheckButtonState() {
        checkState.updateCheckButton(primaryButton)
    }
}

final class GrammarPracticeContainerViewController: UIPageViewController {

    private let point: GrammarPoint
    private let items: [GrammarPracticeItem]
    private let masteryStore: GrammarMasteryStore
    private var stepControllers: [GrammarPracticeStepViewController] = []
    private var currentIndex = 0
    private var correctCount = 0
    private var answeredCount = 0

    var onFinish: ((Int, Int) -> Void)?

    init(
        point: GrammarPoint,
        items: [GrammarPracticeItem],
        masteryStore: GrammarMasteryStore = .shared
    ) {
        self.point = point
        self.items = items
        self.masteryStore = masteryStore
        super.init(transitionStyle: .scroll, navigationOrientation: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.pageBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        navigationItem.title = point.pattern

        stepControllers = items.map { item in
            let step = GrammarPracticeStepViewController(item: item)
            step.onResult = { [weak self] success in
                guard let self else { return }
                if self.answeredCount <= self.currentIndex {
                    self.answeredCount += 1
                    if success { self.correctCount += 1 }
                    self.masteryStore.recordPracticeResult(
                        grammarID: self.point.id,
                        wasCorrect: success
                    )
                }
            }
            step.onSeeInContext = { [weak self] scenarioID in
                self?.presentDialogueContext(scenarioID: scenarioID)
            }
            return step
        }

        if let first = stepControllers.first {
            setViewControllers([first], direction: .forward, animated: false)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        disableInteractivePaging()
    }

    private func disableInteractivePaging() {
        for case let scrollView as UIScrollView in view.subviews {
            scrollView.isScrollEnabled = false
            scrollView.alwaysBounceHorizontal = false
        }
    }

    func advance() {
        let nextIndex = currentIndex + 1
        guard nextIndex < stepControllers.count else {
            finishSession()
            return
        }
        let direction: UIPageViewController.NavigationDirection = .forward
        currentIndex = nextIndex
        setViewControllers([stepControllers[nextIndex]], direction: direction, animated: true)
    }

    private func finishSession() {
        masteryStore.finalizePracticeSession(
            grammarID: point.id,
            correctCount: correctCount,
            totalCount: max(answeredCount, items.count)
        )
        onFinish?(correctCount, items.count)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func presentDialogueContext(scenarioID: String) {
        guard let scenario = DialogueScenarioCollectionCatalog.allCollections
            .flatMap(\.scenarios)
            .first(where: { $0.id == scenarioID })
        else { return }

        let dialogue = DialogueExperimentViewController(
            pointTitle: scenario.menuTitle,
            example: scenario.example
        )
        let nav = UINavigationController(rootViewController: dialogue)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }
}
