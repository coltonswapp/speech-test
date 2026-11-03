//
//  GrammarPatternDetailViewController.swift
//  shizen
//
//  Destination for a grammar pill on the dialogue highlights page. Catalog-backed
//  highlights show Pattern library meaning/form, quiz-style scene evidence, and
//  an Explain gloss. Legacy label-only pills keep the How to use card.
//

import InteractionKit
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
        catalogPattern: DialogueTeachingPattern? = nil,
        evidenceContext: DialogueQuizEvidenceContext? = nil,
        spokenLines: [GrammarScenarioLine] = [],
        request: GeminiGrammarUsage.Request?,
        sceneContext: LessonDialogueSceneContext? = nil,
        from viewController: UIViewController
    ) {
        let detail = GrammarPatternDetailViewController(
            pattern: pattern,
            catalogPattern: catalogPattern,
            evidenceContext: evidenceContext,
            spokenLines: spokenLines,
            request: request,
            sceneContext: sceneContext
        )
        if let nav = viewController.navigationController {
            nav.pushViewController(detail, animated: true)
        } else {
            viewController.present(UINavigationController(rootViewController: detail), animated: true)
        }
    }
}

final class GrammarPatternDetailViewController: UIViewController {

    private let pattern: DialogueGrammarPatternRef
    private let catalogPattern: DialogueTeachingPattern?
    private let evidenceContext: DialogueQuizEvidenceContext?
    private let spokenLines: [GrammarScenarioLine]
    private let request: GeminiGrammarUsage.Request?
    private let sceneContext: LessonDialogueSceneContext?
    private let point: GrammarPoint?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let patternLabel = FuriganaTranscriptLabel()
    private let definitionLabel = UILabel()
    private let formNoteLabel = UILabel()
    private let usageCard = DialogueGrammarUsageCardView()
    private let examplesRow = DialogueGrammarExampleStripView()
    private let playButton = OnboardingChrome.makeGlassPlayButton()
    private let audioPlayer = GrammarAudioPlayer()
    private var evidenceRow: DialogueQuizEvidenceRowView?
    private var evidenceLines: [DialogueQuizSourceLine] = []
    private var loadTask: Task<Void, Never>?
    private var playingSpokenIndex: Int?
    private var loadedExamples: [GeminiGrammarUsage.Example]?

    init(
        pattern: DialogueGrammarPatternRef,
        catalogPattern: DialogueTeachingPattern?,
        evidenceContext: DialogueQuizEvidenceContext?,
        spokenLines: [GrammarScenarioLine],
        request: GeminiGrammarUsage.Request?,
        sceneContext: LessonDialogueSceneContext?
    ) {
        self.pattern = pattern
        self.catalogPattern = catalogPattern
        self.evidenceContext = evidenceContext
        self.spokenLines = spokenLines
        self.request = request
        self.sceneContext = sceneContext
        point = pattern.grammarPointID.flatMap { GrammarCurriculum.point(id: $0) }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true {
            loadTask?.cancel()
            audioPlayer.stop()
            setPlayingSpokenIndex(nil)
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
        configureSupportMenu()
        contentStack.addArrangedSubview(Self.makeHairlineDivider())
        if let catalogDescription {
            contentStack.addArrangedSubview(Self.makeCatalogDescriptionCard(body: catalogDescription))
        }
        usageCard.onExplain = { [weak self] in self?.toggleExplain() }
        usageCard.onExamples = { [weak self] in self?.toggleExamples() }
        usageCard.setExamplesAvailable(true)
        examplesRow.isHidden = true
        examplesRow.onChipTap = { [weak self] example in
            self?.openExampleScrub(example)
        }
        let glossStack = UIStackView(arrangedSubviews: [usageCard, examplesRow])
        glossStack.axis = .vertical
        glossStack.alignment = .fill
        glossStack.spacing = 8
        contentStack.addArrangedSubview(glossStack)
        contentStack.setCustomSpacing(32, after: glossStack)
        if usesCatalogCopy {
            usageCard.apply(.catalog(shortMeaning: catalogShortMeaning, formNote: catalogFormNote))
            usageCard.setExplainAvailable(request != nil)
        } else {
            usageCard.setExplainAvailable(false)
            loadUsage()
        }
        configureEvidenceSection()
        configurePlayButton()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = contentStack.bounds.width
        if width > 0, patternLabel.preferredMaxLayoutWidth != width {
            patternLabel.preferredMaxLayoutWidth = width
        }
    }

    private func configureSupportMenu() {
        guard let sceneContext else { return }
        navigationItem.rightBarButtonItem = LessonHighlightSupportMenu.makeBarButtonItem(
            scene: sceneContext,
            subject: .grammar(pattern, displayLabel: displayLabel),
            presenter: self
        )
    }

    // MARK: Header

    private var displayLabel: String {
        let stamped = pattern.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let catalog = catalogPattern?.label.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stamped.isEmpty, stamped != pattern.patternId { return stamped }
        if !catalog.isEmpty { return catalog }
        if !stamped.isEmpty { return stamped }
        return pattern.patternId ?? ""
    }

    private var catalogShortMeaning: String {
        catalogPattern?.shortMeaning?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var catalogFormNote: String {
        catalogPattern?.formNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var catalogDescription: String? {
        catalogPattern?.description
    }

    /// Catalog copy is the inspect card when `patternId` resolved; skip Gemini / lesson extras.
    private var usesCatalogCopy: Bool {
        catalogPattern != nil && (!catalogShortMeaning.isEmpty || !catalogFormNote.isEmpty)
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
        let lessonDefinition = point?.shortDefinition.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Catalog meaning/form live on the How to use card; header keeps a definition for legacy pills.
        let definition = usesCatalogCopy ? "" : lessonDefinition
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

    // MARK: Example chips

    private func openExampleScrub(_ example: GeminiGrammarUsage.Example) {
        let scrub = SentenceScrubExperimentViewController(
            sentence: example.japanese,
            englishTranslation: example.english,
            showsListenControl: false
        )
        if let nav = navigationController {
            nav.pushViewController(scrub, animated: true)
        } else {
            present(UINavigationController(rootViewController: scrub), animated: true)
        }
    }

    private func toggleExamples() {
        if usageCard.isExamplesEngaged {
            usageCard.setExamplesEngaged(false)
            examplesRow.isHidden = true
            GlossMotion.animateResize(in: view)
            return
        }
        usageCard.setExamplesEngaged(true)
        examplesRow.isHidden = false
        if let loadedExamples, !loadedExamples.isEmpty {
            examplesRow.apply(loadedExamples)
            GlossMotion.animateResize(in: view)
            return
        }
        examplesRow.applyLoading()
        GlossMotion.animateResize(in: view)
        loadExamples()
    }

    private func loadExamples() {
        loadTask = Task { [weak self] in
            guard let self else { return }
            let items: [GeminiGrammarUsage.Example]
            let message: String?
            var feedback: LLMFeedbackReceipt?
            if let request {
                guard GeminiGrammarUsage.isConfigured else {
                    await MainActor.run {
                        self.showExampleItems(self.curriculumExamples, fallback: GeminiGrammarUsage.unavailabilityMessage)
                    }
                    return
                }
                if let cached = await GeminiGrammarUsage.cachedResult(for: request) {
                    items = cached.result.parsedExamples
                    feedback = cached.feedback
                    message = items.isEmpty ? "No extra examples for this pattern." : nil
                } else {
                    do {
                        let explained = try await GeminiGrammarUsage.explain(request)
                        items = explained.result.parsedExamples
                        feedback = explained.feedback
                        message = items.isEmpty ? "No extra examples for this pattern." : nil
                    } catch {
                        items = []
                        message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                }
            } else {
                items = []
                message = "This scene has no lines to build examples from."
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.showExampleItems(items, fallback: message)
                if let feedback {
                    self.usageCard.offerFeedback(feedback)
                    self.usageCard.presentPendingFeedback(ignoreCadence: true)
                }
            }
        }
    }

    private var curriculumExamples: [GeminiGrammarUsage.Example] {
        (point?.primaryExamples ?? []).compactMap { example in
            let japanese = example.japanese.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !japanese.isEmpty else { return nil }
            let english = example.english.trimmingCharacters(in: .whitespacesAndNewlines)
            return GeminiGrammarUsage.Example(
                japanese: japanese,
                reading: nil,
                english: english.isEmpty ? nil : english
            )
        }
    }

    private func showExampleItems(_ items: [GeminiGrammarUsage.Example], fallback: String?) {
        let resolved = items.isEmpty ? curriculumExamples : items
        if !resolved.isEmpty {
            loadedExamples = resolved
            examplesRow.apply(resolved)
        } else {
            examplesRow.applyMessage(fallback ?? "No extra examples for this pattern.")
        }
        guard usageCard.isExamplesEngaged else { return }
        examplesRow.isHidden = false
        GlossMotion.animateResize(in: view)
    }

    // MARK: Scene evidence

    private var exampleSpokenIndices: [Int]? {
        let authored = evidenceContext?.clampedSpokenIndices(pattern.sourceSpokenIndices)
        if let authored { return authored }
        return pattern.exampleSpokenIndices(in: spokenLines)
    }

    private var exampleSpokenLines: [DialogueQuizSourceLine] {
        guard let indices = exampleSpokenIndices else { return [] }
        if let evidenceContext {
            return evidenceContext.sourceLines(spokenIndices: indices)
        }
        return Self.sourceLinesAssigningSides(from: spokenLines, indices: indices)
    }

    private var leadingAlignedEvidenceLines: [DialogueQuizSourceLine] {
        exampleSpokenLines.map {
            DialogueQuizSourceLine(
                speaker: $0.speaker,
                japanese: $0.japanese,
                english: $0.english,
                spokenIndex: $0.spokenIndex,
                speakerSide: .leading
            )
        }
    }

    private func configureEvidenceSection() {
        let lines = leadingAlignedEvidenceLines
        guard !lines.isEmpty else { return }
        evidenceLines = lines

        let row = DialogueQuizEvidenceRowView(lines: lines)
        row.hostScrollView = scrollView
        row.onPlayLine = { [weak self] line in
            self?.playEvidenceLine(line)
        }
        row.onFocusLine = { [weak self] line in
            self?.presentSentenceFocus(for: line)
        }
        for container in row.swipeContainers {
            container.configureContentPopGestureDeferral(from: self)
        }
        evidenceRow = row

        let caption = UILabel()
        caption.text = "From this lesson"
        caption.font = .preferredFont(forTextStyle: .footnote)
        caption.textColor = .tertiaryLabel
        caption.textAlignment = .center

        let section = UIStackView(arrangedSubviews: [caption, row])
        section.axis = .vertical
        section.alignment = .fill
        section.spacing = 8
        contentStack.addArrangedSubview(section)
    }

    private func configurePlayButton() {
        playButton.isHidden = evidenceLines.isEmpty
        playButton.accessibilityHint = "Plays this line from the lesson"
        playButton.addAction(UIAction { [weak self] _ in
            self?.toggleEvidencePlayback()
        }, for: .touchUpInside)
        view.addSubview(playButton)
        NSLayoutConstraint.activate([
            playButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            playButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
        scrollView.verticalScrollIndicatorInsets.bottom = playButton.isHidden ? 0 : 80
        scrollView.contentInset.bottom = playButton.isHidden ? 24 : 88
        updatePlayButtonChrome()
    }

    private func toggleEvidencePlayback() {
        if playingSpokenIndex != nil {
            stopEvidencePlayback()
            return
        }
        guard let line = evidenceLines.first else { return }
        playEvidenceLine(line)
    }

    private func updatePlayButtonChrome() {
        let playing = playingSpokenIndex != nil
        playButton.setSymbol(playing ? "pause.fill" : "play.fill")
        playButton.accessibilityLabel = playing ? "Pause" : "Play"
    }

    private func playEvidenceLine(_ line: DialogueQuizSourceLine) {
        if playingSpokenIndex == line.spokenIndex {
            stopEvidencePlayback()
            return
        }

        let dialogueLines = evidenceContext?.spokenJapaneseTexts ?? spokenLines.map(\.japanese)
        let fallback = dialogueLines.indices.contains(line.spokenIndex)
            ? dialogueLines[line.spokenIndex]
            : line.japanese
        let tokenSync = evidenceContext?.tokenSync

        setPlayingSpokenIndex(line.spokenIndex)
        let finished: () -> Void = { [weak self] in
            self?.setPlayingSpokenIndex(nil)
        }
        audioPlayer.playDialogueLine(
            at: line.spokenIndex,
            publishedAudioUrl: evidenceContext?.publishedAudioUrl,
            audioKey: evidenceContext?.audioKey,
            cacheMetadata: evidenceContext?.cacheMetadata,
            dialogueLines: dialogueLines,
            fallbackText: fallback,
            tokenSync: tokenSync,
            onTime: { [weak self] time in
                self?.evidenceRow?.applyKaraoke(tokenSync: tokenSync, time: time)
            },
            onFinished: finished
        )
    }

    private func stopEvidencePlayback() {
        audioPlayer.stop()
        setPlayingSpokenIndex(nil)
    }

    private func setPlayingSpokenIndex(_ spokenIndex: Int?) {
        playingSpokenIndex = spokenIndex
        evidenceRow?.setPlayingSpokenIndex(spokenIndex)
        if spokenIndex == nil {
            evidenceRow?.applyKaraoke(tokenSync: nil, time: 0)
        }
        updatePlayButtonChrome()
    }

    private func presentSentenceFocus(for line: DialogueQuizSourceLine) {
        stopEvidencePlayback()

        let dialogueLineAudio: DialogueLineAudioReference?
        let published = evidenceContext?.publishedAudioUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = evidenceContext?.audioKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !published.isEmpty || !key.isEmpty {
            dialogueLineAudio = DialogueLineAudioReference(
                publishedAudioUrl: evidenceContext?.publishedAudioUrl,
                audioKey: evidenceContext?.audioKey ?? "",
                cacheMetadata: evidenceContext?.cacheMetadata,
                lineIndex: line.spokenIndex,
                dialogueLines: evidenceContext?.spokenJapaneseTexts ?? spokenLines.map(\.japanese),
                tokenSync: evidenceContext?.tokenSync
            )
        } else {
            dialogueLineAudio = nil
        }

        let catalog = evidenceContext?.spokenLines ?? exampleSpokenLines
        let nuanceLines = catalog.map {
            DialogueNuanceContext.Line(speaker: $0.speaker, japanese: $0.japanese, english: $0.english)
        }
        let focusedIndex = catalog.firstIndex(where: { $0.spokenIndex == line.spokenIndex }) ?? line.spokenIndex
        let dialogueContext = DialogueNuanceContext.around(
            lines: nuanceLines,
            focusedIndex: focusedIndex
        ) ?? .isolated(japanese: line.japanese, english: line.english, speaker: line.speaker)

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

    private static func sourceLinesAssigningSides(
        from spoken: [GrammarScenarioLine],
        indices: [Int]
    ) -> [DialogueQuizSourceLine] {
        var speakerSides: [String: DialogueSpeakerSide] = [:]
        var nextSide: DialogueSpeakerSide = .leading
        return indices.compactMap { index in
            guard spoken.indices.contains(index) else { return nil }
            let line = spoken[index]
            let speakerSide = DialogueBubbleLayout.assignSpeakerSide(
                for: line.speaker,
                sides: &speakerSides,
                nextSide: &nextSide
            )
            return DialogueQuizSourceLine(
                speaker: line.speaker,
                japanese: line.japanese,
                english: line.english,
                spokenIndex: index,
                speakerSide: speakerSide
            )
        }
    }

    // MARK: Explain + How to use

    /// Inspect never shows the generated examples shelf; scene lines are the example.
    private static func inspectResult(_ result: GeminiGrammarUsage.Result) -> GeminiGrammarUsage.Result {
        GeminiGrammarUsage.Result(
            inThisScene: result.inThisScene,
            form: result.form,
            examples: [],
            note: result.note
        )
    }

    private func toggleExplain() {
        if usageCard.isExplainEngaged {
            usageCard.setExplainEngaged(false)
            GlossMotion.animateResize(in: view)
            return
        }
        usageCard.setExplainEngaged(true)
        loadExplain()
    }

    private func loadExplain() {
        guard let request else {
            usageCard.applyExplainFailed("This scene has no lines to explain.")
            return
        }
        guard GeminiGrammarUsage.isConfigured else {
            usageCard.applyExplainFailed(GeminiGrammarUsage.unavailabilityMessage)
            return
        }

        usageCard.applyExplainLoading()
        loadTask = Task { [weak self] in
            let explained: Result<GeminiGrammarUsage.Explanation, Error>
            if let cached = await GeminiGrammarUsage.cachedResult(for: request) {
                explained = .success(cached)
            } else {
                do {
                    explained = .success(try await GeminiGrammarUsage.explain(request))
                } catch {
                    explained = .failure(error)
                }
            }
            guard !Task.isCancelled, let self, self.usageCard.isExplainEngaged else { return }
            switch explained {
            case .success(let value):
                self.loadedExamples = value.result.parsedExamples
                self.usageCard.applyExplainResult(
                    Self.inspectResult(value.result),
                    feedback: value.feedback
                )
                GlossMotion.animateResize(in: self.view) { [weak self] in
                    self?.usageCard.presentPendingFeedback(ignoreCadence: true)
                }
            case .failure(let error):
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.usageCard.applyExplainFailed(message)
                GlossMotion.animateResize(in: self.view)
            }
        }
    }

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
            var parsed: [GeminiGrammarUsage.Example] = []
            if let cached = await GeminiGrammarUsage.cachedResult(for: request) {
                parsed = cached.result.parsedExamples
                state = .result(Self.inspectResult(cached.result), feedback: cached.feedback)
            } else {
                do {
                    let explained = try await GeminiGrammarUsage.explain(request)
                    parsed = explained.result.parsedExamples
                    state = .result(Self.inspectResult(explained.result), feedback: explained.feedback)
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    state = .failed(message)
                }
            }
            guard !Task.isCancelled, let self else { return }
            if !parsed.isEmpty { self.loadedExamples = parsed }
            self.usageCard.apply(state)
            GlossMotion.animateResize(in: self.view) { [weak self] in
                self?.usageCard.presentPendingFeedback(ignoreCadence: true)
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

    /// Pattern library textbook definition; matches the How to use gloss card chrome.
    private static func makeCatalogDescriptionCard(body: String) -> UIView {
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.clipsToBounds = false

        let surface = GlossCardSurfaceView()
        surface.backgroundColor = .secondarySystemGroupedBackground
        surface.layer.cornerRadius = 14
        surface.layer.cornerCurve = .continuous
        surface.layer.shadowColor = UIColor.black.cgColor
        surface.layer.shadowOpacity = 0.14
        surface.layer.shadowRadius = 10
        surface.layer.shadowOffset = CGSize(width: 0, height: 4)
        surface.translatesAutoresizingMaskIntoConstraints = false

        let sectionTitle = UILabel()
        sectionTitle.text = "DESCRIPTION"
        sectionTitle.font = UIFont.preferredFont(forTextStyle: .caption1)
        sectionTitle.textColor = .secondaryLabel

        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.font = .preferredFont(forTextStyle: .body)
        bodyLabel.textColor = .label
        bodyLabel.numberOfLines = 0

        let sectionStack = UIStackView(arrangedSubviews: [sectionTitle, bodyLabel])
        sectionStack.axis = .vertical
        sectionStack.alignment = .fill
        sectionStack.spacing = 6
        sectionStack.translatesAutoresizingMaskIntoConstraints = false

        let insets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        let shadowBleed: CGFloat = 12
        surface.addSubview(sectionStack)
        wrapper.addSubview(surface)

        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: wrapper.topAnchor),
            surface.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            surface.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -shadowBleed),

            sectionStack.topAnchor.constraint(equalTo: surface.topAnchor, constant: insets.top),
            sectionStack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: insets.left),
            sectionStack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -insets.right),
            sectionStack.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -insets.bottom),
        ])
        return wrapper
    }
}
