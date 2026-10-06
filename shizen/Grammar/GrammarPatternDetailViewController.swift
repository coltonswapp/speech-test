//
//  GrammarPatternDetailViewController.swift
//  shizen
//
//  Destination for a grammar pill on the dialogue highlights page. Inspect card:
//  Pattern catalog meaning (when patternId resolves), this scene's tagged spoken
//  line as the example, optional Hear for that spoken range, then curriculum /
//  Gemini usage when available.
//

import UIKit

enum GrammarPatternDetailPresenter {

    struct HearContext {
        let publishedAudioUrl: String?
        let audioKey: String?
        let cacheMetadata: RemoteAudioCacheMetadata?
        let spokenJapaneseTexts: [String]
        let tokenSync: DialogueTokenSync?
    }

    /// Pushes onto the navigation stack, or presents in a navigation controller when there is none.
    static func push(
        pattern: DialogueGrammarPatternRef,
        catalogPattern: DialogueTeachingPattern?,
        exampleLines: [GrammarScenarioLine],
        hearContext: HearContext?,
        request: GeminiGrammarUsage.Request?,
        from viewController: UIViewController
    ) {
        let detail = GrammarPatternDetailViewController(
            pattern: pattern,
            catalogPattern: catalogPattern,
            exampleLines: exampleLines,
            hearContext: hearContext,
            request: request
        )
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
    private let catalogPattern: DialogueTeachingPattern?
    private let exampleLines: [GrammarScenarioLine]
    private let hearContext: GrammarPatternDetailPresenter.HearContext?
    private let request: GeminiGrammarUsage.Request?
    private let point: GrammarPoint?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let patternLabel = FuriganaTranscriptLabel()
    private let definitionLabel = UILabel()
    private let formNoteLabel = UILabel()
    private let usageCard = DialogueGrammarUsageCardView()
    private let audioPlayer = GrammarAudioPlayer()
    private var loadTask: Task<Void, Never>?
    private var isHearing = false

    init(
        pattern: DialogueGrammarPatternRef,
        catalogPattern: DialogueTeachingPattern?,
        exampleLines: [GrammarScenarioLine],
        hearContext: GrammarPatternDetailPresenter.HearContext?,
        request: GeminiGrammarUsage.Request?
    ) {
        self.pattern = pattern
        self.catalogPattern = catalogPattern
        self.exampleLines = exampleLines
        self.hearContext = hearContext
        self.request = request
        point = pattern.grammarPointID.flatMap { GrammarCurriculum.point(id: $0) }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true {
            loadTask?.cancel()
            audioPlayer.stop()
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
        configureExampleSection()
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

    private var displayLabel: String {
        let stamped = pattern.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stamped.isEmpty { return stamped }
        return catalogPattern?.label ?? pattern.patternId ?? ""
    }

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
            attributed: JapaneseFuriganaBuilder.attributedString(
                for: displayLabel,
                font: font,
                textColor: .label
            ),
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
        let catalogMeaning = catalogPattern?.shortMeaning?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lessonDefinition = point?.shortDefinition
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let definition = !catalogMeaning.isEmpty ? catalogMeaning : lessonDefinition
        definitionLabel.text = definition.isEmpty ? nil : definition
        definitionLabel.isHidden = definition.isEmpty

        formNoteLabel.font = .preferredFont(forTextStyle: .footnote)
        formNoteLabel.textColor = .tertiaryLabel
        formNoteLabel.numberOfLines = 0
        let formNote = catalogPattern?.formNote?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        formNoteLabel.text = formNote.isEmpty ? nil : formNote
        formNoteLabel.isHidden = formNote.isEmpty

        let header = UIStackView(arrangedSubviews: [patternLabel, definitionLabel, formNoteLabel])
        header.axis = .vertical
        header.alignment = .fill
        header.spacing = 2
        contentStack.addArrangedSubview(header)
    }

    // MARK: Scene example + Hear

    private var exampleSpokenLines: [GrammarScenarioLine] {
        let spoken = exampleLines.filter(\.isSpokenLine)
        guard let indices = pattern.sourceSpokenIndices, !indices.isEmpty else {
            return []
        }
        return indices.compactMap { index in
            spoken.indices.contains(index) ? spoken[index] : nil
        }
    }

    private func configureExampleSection() {
        let lines = exampleSpokenLines
        guard !lines.isEmpty else { return }

        let title = UILabel()
        title.text = "IN THIS SCENE"
        title.font = .preferredFont(forTextStyle: .subheadline)
        title.textColor = .secondaryLabel

        let section = UIStackView(arrangedSubviews: [title])
        section.axis = .vertical
        section.alignment = .fill
        section.spacing = 10
        section.setCustomSpacing(8, after: title)

        for line in lines {
            section.addArrangedSubview(Self.makeSceneExampleRow(line))
        }

        if canHear {
            var config = UIButton.Configuration.glass()
            config.cornerStyle = .capsule
            config.title = "Hear"
            config.image = UIImage(
                systemName: "speaker.wave.2.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            )
            config.imagePadding = 6
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 15, weight: .semibold)
                return outgoing
            }
            let hearButton = UIButton(configuration: config)
            hearButton.accessibilityLabel = "Hear this pattern in the scene"
            hearButton.addAction(UIAction { [weak self] _ in
                self?.toggleHear()
            }, for: .touchUpInside)
            let buttonRow = UIStackView(arrangedSubviews: [hearButton, UIView()])
            buttonRow.axis = .horizontal
            section.addArrangedSubview(buttonRow)
        }

        contentStack.addArrangedSubview(Self.makeHairlineDivider())
        contentStack.addArrangedSubview(section)
    }

    private var canHear: Bool {
        guard let hearContext,
              let indices = pattern.sourceSpokenIndices,
              !indices.isEmpty
        else { return false }
        let hasAudio =
            !(hearContext.publishedAudioUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !(hearContext.audioKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return hasAudio
    }

    private func toggleHear() {
        guard let hearContext,
              let indices = pattern.sourceSpokenIndices,
              let first = indices.first
        else { return }

        if isHearing {
            audioPlayer.stop()
            isHearing = false
            return
        }

        let dialogueLines = hearContext.spokenJapaneseTexts
        let fallback = dialogueLines.indices.contains(first)
            ? dialogueLines[first]
            : (exampleSpokenLines.first?.japanese ?? displayLabel)

        isHearing = true
        let finished = { [weak self] in
            self?.isHearing = false
        }

        if indices.count == 1 {
            audioPlayer.playDialogueLine(
                at: first,
                publishedAudioUrl: hearContext.publishedAudioUrl,
                audioKey: hearContext.audioKey,
                cacheMetadata: hearContext.cacheMetadata,
                dialogueLines: dialogueLines,
                fallbackText: fallback,
                tokenSync: hearContext.tokenSync,
                onFinished: finished
            )
        } else {
            audioPlayer.playDialogueSequence(
                spokenIndices: indices,
                publishedAudioUrl: hearContext.publishedAudioUrl,
                audioKey: hearContext.audioKey,
                cacheMetadata: hearContext.cacheMetadata,
                dialogueLines: dialogueLines,
                fallbackText: fallback,
                tokenSync: hearContext.tokenSync,
                onSpokenIndexStart: { _ in },
                onFinished: finished
            )
        }
    }

    private static func makeSceneExampleRow(_ line: GrammarScenarioLine) -> UIView {
        let japanese = UILabel()
        japanese.font = .preferredFont(forTextStyle: .body)
        japanese.textColor = .label
        japanese.numberOfLines = 0
        let speaker = line.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        japanese.text = speaker.isEmpty ? line.japanese : "\(speaker): \(line.japanese)"

        let english = UILabel()
        english.font = .preferredFont(forTextStyle: .subheadline)
        english.textColor = .secondaryLabel
        english.numberOfLines = 0
        let englishText = line.english?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        english.text = englishText.isEmpty ? nil : englishText
        english.isHidden = englishText.isEmpty

        let row = UIStackView(arrangedSubviews: [japanese, english])
        row.axis = .vertical
        row.alignment = .fill
        row.spacing = 2
        return row
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
