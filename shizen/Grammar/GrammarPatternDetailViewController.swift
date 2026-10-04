//
//  GrammarPatternDetailViewController.swift
//  shizen
//
//  Destination for a grammar pill on the dialogue highlights page. Laid out like
//  the word dictionary screen: pattern header, How to use card, then the curriculum
//  lesson when the pattern is tagged.
//

import UIKit

enum GrammarPatternDetailPresenter {

    /// Pushes onto the navigation stack, or presents in a navigation controller when there is none.
    static func push(
        pattern: DialogueGrammarPatternRef,
        request: GeminiGrammarUsage.Request?,
        from viewController: UIViewController
    ) {
        let detail = GrammarPatternDetailViewController(pattern: pattern, request: request)
        if let nav = viewController.navigationController {
            nav.pushViewController(detail, animated: true)
        } else {
            viewController.present(UINavigationController(rootViewController: detail), animated: true)
        }
    }
}

final class GrammarPatternDetailViewController: UIViewController {

    private static let maxLessonExamples = 2

    private let pattern: DialogueGrammarPatternRef
    private let request: GeminiGrammarUsage.Request?
    private let point: GrammarPoint?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let patternLabel = FuriganaTranscriptLabel()
    private let definitionLabel = UILabel()
    private let usageCard = DialogueGrammarUsageCardView()
    private var loadTask: Task<Void, Never>?

    init(pattern: DialogueGrammarPatternRef, request: GeminiGrammarUsage.Request?) {
        self.pattern = pattern
        self.request = request
        point = pattern.grammarPointID.flatMap { GrammarCurriculum.point(id: $0) }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true {
            loadTask?.cancel()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        let inset: CGFloat = 20
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: inset),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: inset),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -inset),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -inset * 2),
        ])

        configureHeader()
        contentStack.addArrangedSubview(Self.makeHairlineDivider())
        contentStack.addArrangedSubview(usageCard)
        configureLessonSection()

        loadUsage()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = contentStack.bounds.width
        if width > 0, patternLabel.preferredMaxLayoutWidth != width {
            patternLabel.preferredMaxLayoutWidth = width
        }
    }

    // MARK: Header

    private func configureHeader() {
        let font: UIFont = {
            let base = UIFont.preferredFont(forTextStyle: .largeTitle)
            guard let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) else { return base }
            return UIFont(descriptor: descriptor, size: 0)
        }()
        patternLabel.font = font
        patternLabel.textColor = .label
        patternLabel.numberOfLines = 0
        patternLabel.verticalTextInsetsAffectAlignmentRect = true
        patternLabel.accessibilityTraits = .header
        JapaneseFuriganaBuilder.applyScrubDisplay(
            to: patternLabel,
            attributed: JapaneseFuriganaBuilder.attributedString(for: pattern.label, font: font, textColor: .label),
            contentInsets: UIEdgeInsets(
                top: JapaneseFuriganaBuilder.wordDetailRubyTopInset(for: font),
                left: 0,
                bottom: 2,
                right: 0
            )
        )

        definitionLabel.font = .preferredFont(forTextStyle: .subheadline)
        definitionLabel.textColor = .secondaryLabel
        definitionLabel.numberOfLines = 0
        let definition = point?.shortDefinition.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        definitionLabel.text = definition.isEmpty ? nil : definition
        definitionLabel.isHidden = definition.isEmpty

        let header = UIStackView(arrangedSubviews: [patternLabel, definitionLabel])
        header.axis = .vertical
        header.alignment = .fill
        header.spacing = 2
        contentStack.addArrangedSubview(header)
    }

    // MARK: Lesson

    private func configureLessonSection() {
        guard let point else { return }

        let title = UILabel()
        title.text = "FROM THE LESSON"
        title.font = .preferredFont(forTextStyle: .subheadline)
        title.textColor = .secondaryLabel

        let section = UIStackView(arrangedSubviews: [title])
        section.axis = .vertical
        section.alignment = .fill
        section.spacing = 12
        section.setCustomSpacing(8, after: title)

        for example in point.primaryExamples.prefix(Self.maxLessonExamples) {
            section.addArrangedSubview(Self.makeExampleRow(example))
        }

        var config = UIButton.Configuration.glass()
        config.cornerStyle = .capsule
        config.title = "Open lesson"
        config.image = UIImage(
            systemName: "chevron.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        )
        config.imagePlacement = .trailing
        config.imagePadding = 6
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 15, weight: .semibold)
            return outgoing
        }
        let lessonButton = UIButton(configuration: config)
        lessonButton.accessibilityHint = "Opens the grammar lesson for \(point.pattern)"
        lessonButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            GrammarReferencePresenter.open(point: point, from: self)
        }, for: .touchUpInside)
        let buttonRow = UIStackView(arrangedSubviews: [lessonButton, UIView()])
        buttonRow.axis = .horizontal
        section.setCustomSpacing(16, after: section.arrangedSubviews.last ?? title)
        section.addArrangedSubview(buttonRow)

        contentStack.addArrangedSubview(Self.makeHairlineDivider())
        contentStack.addArrangedSubview(section)
    }

    private static func makeExampleRow(_ example: GrammarExample) -> UIView {
        let japanese = UILabel()
        japanese.font = .preferredFont(forTextStyle: .body)
        japanese.textColor = .label
        japanese.numberOfLines = 0
        japanese.text = example.japanese

        let english = UILabel()
        english.font = .preferredFont(forTextStyle: .subheadline)
        english.textColor = .secondaryLabel
        english.numberOfLines = 0
        english.text = example.english

        let row = UIStackView(arrangedSubviews: [japanese, english])
        row.axis = .vertical
        row.alignment = .fill
        row.spacing = 2
        return row
    }

    // MARK: How to use

    private func loadUsage() {
        guard let request else {
            usageCard.apply(.unavailable("This scene has no lines to explain."))
            return
        }
        guard GeminiGrammarUsage.isConfigured else {
            usageCard.apply(.unavailable(GeminiGrammarUsage.unavailabilityMessage))
            return
        }

        usageCard.apply(.loading)
        loadTask = Task { [weak self] in
            let state: DialogueGrammarUsageCardView.State
            if let cached = await GeminiGrammarUsage.cachedResult(for: request) {
                state = .result(cached.result, feedback: cached.feedback)
            } else {
                do {
                    let explained = try await GeminiGrammarUsage.explain(request)
                    state = .result(explained.result, feedback: explained.feedback)
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    state = .failed(message)
                }
            }
            guard !Task.isCancelled, let self else { return }
            self.usageCard.apply(state)
            GlossMotion.animateResize(in: self.view) { [weak self] in
                self?.usageCard.presentPendingFeedback()
            }
        }
    }

    private static func makeHairlineDivider() -> UIView {
        let divider = UIView()
        divider.backgroundColor = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
        return divider
    }
}
