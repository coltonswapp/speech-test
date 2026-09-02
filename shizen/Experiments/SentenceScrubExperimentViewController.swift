//
//  SentenceScrubExperimentViewController.swift
//  shizen
//
//  Pan horizontally across a tokenized sentence to change the selection; haptics + JMdict gloss.
//

import InteractionKit
import Translation
import UIKit

/// Bundled or CDN dialogue-clip segment for sentence scrub play.
struct DialogueLineAudioReference {
    let publishedAudioUrl: String?
    let audioKey: String
    let cacheMetadata: RemoteAudioCacheMetadata?
    let lineIndex: Int
    let dialogueLines: [String]
}

final class SentenceScrubExperimentViewController: UIViewController {

    /// Short labels for the menu; sentences exercise different particles, questions, and kanji density.
    private static let exampleSentences: [(title: String, text: String)] = [
        ("Change", "お釣りは五十円です。"),
        ("Weather", "今日はとてもいい天気ですね。"),
        ("Walk to station", "駅まで歩いて行きましょう。"),
        ("Interesting book", "この本は面白いと思います。"),
        ("What time", "何時に会いましたか。"),
        ("Library study", "図書館で静かに勉強しました。"),
        ("Spring in Kyoto", "春の京都は美しいです。"),
        ("Another coffee", "コーヒーをもう一杯ください。"),
    ]

    private var currentSentence: String
    /// Curated English for `currentSentence` (e.g. from dialogue content). When
    /// present, shown immediately — no system translation runs at all.
    private var providedEnglish: String?
    /// Authored dialogue tokens (token sync). When set, scrub uses these
    /// instead of running the app tokenizer.
    private var providedTokens: [JapaneseToken]?
    private let recordedClip: RealtimeAudioClip?
    private let onReplayClip: ((RealtimeAudioClip) -> Void)?
    private let dialogueLineAudio: DialogueLineAudioReference?
    /// Neighboring dialogue lines for the Gemini nuance card.
    private var dialogueContext: DialogueNuanceContext?
    private let grammarAudioPlayer = GrammarAudioPlayer()

    init(
        sentence: String,
        englishTranslation: String? = nil,
        recordedClip: RealtimeAudioClip? = nil,
        onReplayClip: ((RealtimeAudioClip) -> Void)? = nil,
        dialogueLineAudio: DialogueLineAudioReference? = nil,
        dialogueContext: DialogueNuanceContext? = nil,
        tokens: [JapaneseToken]? = nil
    ) {
        currentSentence = sentence
        let trimmedEnglish = englishTranslation?.trimmingCharacters(in: .whitespacesAndNewlines)
        providedEnglish = (trimmedEnglish?.isEmpty ?? true) ? nil : trimmedEnglish
        providedTokens = tokens.flatMap { $0.isEmpty ? nil : $0 }
        self.recordedClip = recordedClip
        self.onReplayClip = onReplayClip
        self.dialogueLineAudio = dialogueLineAudio
        self.dialogueContext = dialogueContext
        super.init(nibName: nil, bundle: nil)
    }

    convenience override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        self.init(sentence: Self.exampleSentences[0].text)
    }

    required init?(coder: NSCoder) {
        currentSentence = Self.exampleSentences[0].text
        recordedClip = nil
        onReplayClip = nil
        dialogueLineAudio = nil
        dialogueContext = nil
        providedTokens = nil
        super.init(coder: coder)
    }

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let scrubbableSentenceView = ScrubbableSentenceView(engine: JapaneseScrubSentenceEngine.shared)

    /// Full-sentence English from the system Translation framework (below the Japanese line).
    private let englishTranslationLabel = UILabel()

    /// Sentence + translation stacked; circular play and nuance controls on each row’s trailing side.
    private let sentenceSectionRowStack = UIStackView()
    private let sentenceContentStack = UIStackView()
    private let translationSectionRowStack = UIStackView()
    private let nuanceButton = UIButton(type: .system)
    private let nuanceGlyphView = UIImageView()
    private let nuanceCardView = DialogueNuanceCardView()
    private var nuanceLoadTask: Task<Void, Never>?
    private var nuanceLoadRequest: GeminiDialogueNuance.Request?

    private static let audioButtonSize: CGFloat = 56
    private static let audioGlyphColor = UIColor.systemYellow

    private let speakSentenceButton = UIButton(type: .system)
    private let speakSentenceGlyphView = UIImageView()

    /// Direct (non-SwiftUI) system translation, iOS 26+. Reused across
    /// sentences — the ja→en pair never changes for this screen.
    private var translationSession: TranslationSession?
    private var translationTask: Task<Void, Never>?

    private let wordSpeaker = WordUtteranceSpeaker()
    private let wordDictionaryDetailView: WordDictionaryDetailView = {
        let v = WordDictionaryDetailView()
        v.showsCompounds = false
        return v
    }()
    private let selectionStartDivider = SentenceScrubExperimentViewController.makeHairlineDivider()

    private static func makeHairlineDivider() -> UIView {
        let v = UIView()
        v.backgroundColor = .separator
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
        return v
    }

    private static func configureGlassAudioButton(
        _ button: UIButton,
        glyphView: UIImageView,
        symbolName: String,
        glyphPointSize: CGFloat,
        accessibilityLabel: String
    ) {
        var config = UIButton.Configuration.glass()
        config.cornerStyle = .capsule
        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = accessibilityLabel

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: glyphPointSize, weight: .semibold)
        glyphView.image = UIImage(systemName: symbolName, withConfiguration: symbolConfig)?
            .withRenderingMode(.alwaysTemplate)
        glyphView.tintColor = audioGlyphColor
        glyphView.preferredSymbolConfiguration = symbolConfig
        glyphView.contentMode = .scaleAspectFit
        glyphView.isUserInteractionEnabled = false
        glyphView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(glyphView)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: audioButtonSize),
            button.heightAnchor.constraint(equalToConstant: audioButtonSize),
            glyphView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            glyphView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            glyphView.widthAnchor.constraint(equalToConstant: glyphPointSize + 6),
            glyphView.heightAnchor.constraint(equalToConstant: glyphPointSize + 6),
        ])
    }

    private func titleFontForSentenceLine() -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: .title1)
        if let d = base.fontDescriptor.withSymbolicTraits(.traitBold) {
            return UIFont(descriptor: d, size: 0)
        }
        return base
    }

    private func makeOptionsMenu() -> UIMenu {
        let overlayToggle = UIAction(
            title: "Show gloss overlay",
            state: scrubbableSentenceView.showCalloutOnScrub ? .on : .off
        ) { [weak self] _ in
            guard let self else { return }
            self.scrubbableSentenceView.showCalloutOnScrub.toggle()
            ExperimentSettings.sentenceScrubGlossOverlayEnabled = self.scrubbableSentenceView.showCalloutOnScrub
            self.refreshOptionsMenu()
        }

        let repeatAfterMe = UIAction(
            title: "Repeat after me",
            image: UIImage(systemName: "person.wave.2")
        ) { [weak self] _ in
            self?.openRepeatAfterMe()
        }

        let exampleActions = Self.exampleSentences.map { title, text in
            UIAction(title: title, state: text == currentSentence ? .on : .off) { [weak self] _ in
                self?.applyExampleSentence(text)
            }
        }
        let examplesMenu = UIMenu(title: "Example sentence", children: exampleActions)

        return UIMenu(children: [overlayToggle, repeatAfterMe, examplesMenu])
    }

    private func refreshOptionsMenu() {
        navigationItem.rightBarButtonItem?.menu = makeOptionsMenu()
    }

    private func applyExampleSentence(_ text: String) {
        guard text != currentSentence else { return }
        currentSentence = text
        providedEnglish = nil
        providedTokens = nil
        dialogueContext = nil
        wordSpeaker.stop()
        grammarAudioPlayer.stop()
        updateSpeakButtonAccessibility()
        beginEnglishTranslationIfNeeded()
        applySentenceToScrubView()

        resetNuanceCard()
        refreshOptionsMenu()
    }

    private func applySentenceToScrubView() {
        let font = titleFontForSentenceLine()
        if let providedTokens {
            scrubbableSentenceView.configureWithTokens(
                sentence: currentSentence,
                font: font,
                tokens: providedTokens,
                showsFurigana: true,
                clearInteraction: true,
                preservesTokenBoundaries: true
            )
        } else {
            scrubbableSentenceView.configure(
                sentence: currentSentence,
                font: font,
                showsFurigana: true
            )
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Sentence scrub"

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Options",
            image: nil,
            primaryAction: nil,
            menu: makeOptionsMenu()
        )

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 16

        scrubbableSentenceView.showCalloutOnScrub = ExperimentSettings.sentenceScrubGlossOverlayEnabled
        scrubbableSentenceView.sentenceLineView.textAlignment = .natural
        scrubbableSentenceView.onSelectionChanged = { [weak self] index, surface in
            self?.handleSelectionChanged(index: index, surface: surface)
        }
        scrubbableSentenceView.onRequestDictionaryDetail = { [weak self] surface, sentence in
            guard let self else { return }
            WordDictionaryDetailSheetPresenter.push(
                surface: surface,
                sentence: sentence,
                from: self
            )
        }
        wordDictionaryDetailView.onSelectKanji = { [weak self] character in
            guard let self else { return }
            let kanjiVC = KanjiDetailViewController(character: character)
            if let nav = self.navigationController {
                nav.pushViewController(kanjiVC, animated: true)
            } else {
                self.present(UINavigationController(rootViewController: kanjiVC), animated: true)
            }
        }
        applySentenceToScrubView()
        scrubbableSentenceView.bindDismissOnScroll(scrollView)
        scrubbableSentenceView.bindDismissOnTap(scrollView)

        englishTranslationLabel.font = .preferredFont(forTextStyle: .subheadline)
        englishTranslationLabel.textColor = .secondaryLabel
        englishTranslationLabel.textAlignment = .natural
        englishTranslationLabel.numberOfLines = 0
        setEnglishLabelText(providedEnglish ?? "")

        sentenceSectionRowStack.axis = .horizontal
        sentenceSectionRowStack.alignment = .top
        sentenceSectionRowStack.spacing = 16
        sentenceSectionRowStack.distribution = .fill
        sentenceSectionRowStack.addArrangedSubview(scrubbableSentenceView)
        sentenceSectionRowStack.addArrangedSubview(speakSentenceButton)

        scrubbableSentenceView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scrubbableSentenceView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        speakSentenceButton.setContentHuggingPriority(.required, for: .horizontal)
        speakSentenceButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        Self.configureGlassAudioButton(
            speakSentenceButton,
            glyphView: speakSentenceGlyphView,
            symbolName: "play.fill",
            glyphPointSize: 22,
            accessibilityLabel: "Speak sentence"
        )
        speakSentenceButton.accessibilityHint = "Plays audio of the Japanese example sentence"
        speakSentenceButton.addTarget(self, action: #selector(speakFullSentenceTapped), for: .touchUpInside)

        englishTranslationLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        englishTranslationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        nuanceButton.setContentHuggingPriority(.required, for: .horizontal)
        nuanceButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        Self.configureGlassAudioButton(
            nuanceButton,
            glyphView: nuanceGlyphView,
            symbolName: "sparkle.magnifyingglass",
            glyphPointSize: 22,
            accessibilityLabel: "Implied meaning"
        )
        nuanceButton.accessibilityHint = "Shows the implied meaning of this line"
        nuanceButton.addTarget(self, action: #selector(nuanceButtonTapped), for: .touchUpInside)

        translationSectionRowStack.axis = .horizontal
        translationSectionRowStack.alignment = .center
        translationSectionRowStack.spacing = 16
        translationSectionRowStack.distribution = .fill
        translationSectionRowStack.addArrangedSubview(englishTranslationLabel)
        translationSectionRowStack.addArrangedSubview(nuanceButton)

        sentenceContentStack.axis = .vertical
        sentenceContentStack.alignment = .fill
        sentenceContentStack.spacing = 6
        sentenceContentStack.addArrangedSubview(sentenceSectionRowStack)
        sentenceContentStack.addArrangedSubview(translationSectionRowStack)

        NSLayoutConstraint.activate([
            speakSentenceButton.topAnchor.constraint(equalTo: scrubbableSentenceView.sentenceLineView.topAnchor),
            speakSentenceButton.trailingAnchor.constraint(equalTo: sentenceSectionRowStack.trailingAnchor),
            nuanceButton.trailingAnchor.constraint(equalTo: translationSectionRowStack.trailingAnchor),
            nuanceButton.widthAnchor.constraint(equalTo: speakSentenceButton.widthAnchor),
        ])

        nuanceCardView.isHidden = true

        contentStack.addArrangedSubview(sentenceContentStack)
        contentStack.addArrangedSubview(nuanceCardView)
        contentStack.setCustomSpacing(20, after: nuanceCardView)
        contentStack.addArrangedSubview(selectionStartDivider)
        contentStack.setCustomSpacing(16, after: selectionStartDivider)
        contentStack.addArrangedSubview(wordDictionaryDetailView)

        selectionStartDivider.isHidden = true

        scrollView.addSubview(contentStack)
        view.addSubview(scrollView)

        let content = scrollView.contentLayoutGuide
        let frame = scrollView.frameLayoutGuide
        let inset: CGFloat = 20

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: content.topAnchor, constant: inset),
            contentStack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            contentStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
            contentStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),
            contentStack.leadingAnchor.constraint(equalTo: frame.leadingAnchor, constant: inset),
            contentStack.trailingAnchor.constraint(equalTo: frame.trailingAnchor, constant: -inset),
        ])

        updateSpeakButtonAccessibility()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Deferred from viewDidLoad: session availability checks and model
        // warm-up shouldn't delay the first frame of the push transition. When
        // curated English was provided this is a no-op.
        beginEnglishTranslationIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || isBeingDismissed {
            grammarAudioPlayer.stop()
            wordSpeaker.stop()
            translationTask?.cancel()
            nuanceLoadTask?.cancel()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        speakSentenceButton.bringSubviewToFront(speakSentenceGlyphView)
        nuanceButton.bringSubviewToFront(nuanceGlyphView)
    }

    private var canPlayDialogueLineAudio: Bool {
        guard let dialogueLineAudio else { return false }
        guard dialogueLineAudio.dialogueLines.indices.contains(dialogueLineAudio.lineIndex) else {
            return false
        }
        let lineText = dialogueLineAudio.dialogueLines[dialogueLineAudio.lineIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let focused = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        return !lineText.isEmpty && lineText == focused
    }

    private func updateSpeakButtonAccessibility() {
        if let recordedClip, !recordedClip.pcmData.isEmpty {
            speakSentenceButton.accessibilityLabel = "Replay recording"
            speakSentenceButton.accessibilityHint = "Plays the recorded audio for this sentence"
        } else if canPlayDialogueLineAudio {
            speakSentenceButton.accessibilityLabel = "Play dialogue line"
            speakSentenceButton.accessibilityHint = "Plays just this line from the scenario audio"
        } else {
            speakSentenceButton.accessibilityLabel = "Speak sentence"
            speakSentenceButton.accessibilityHint = "Plays audio of the Japanese example sentence"
        }
    }

    private func setEnglishLabelText(_ text: String) {
        englishTranslationLabel.text = text
    }

    /// Translates `currentSentence` via a direct `TranslationSession` (iOS 26 —
    /// no SwiftUI host needed). Skipped when curated English was provided.
    /// On the simulator, system Translation prompts for language setup
    /// repeatedly, so translation is skipped and the label stays empty.
    private func beginEnglishTranslationIfNeeded() {
        if let providedEnglish {
            translationTask?.cancel()
            setEnglishLabelText(providedEnglish)
            return
        }

        #if targetEnvironment(simulator)
        setEnglishLabelText("")
        #else
        setEnglishLabelText("Translating…")
        translationTask?.cancel()
        let sentence = currentSentence
        translationTask = Task { @MainActor [weak self] in
            let japanese = Locale.Language(identifier: "ja")
            let english = Locale.Language(identifier: "en")

            let status = await LanguageAvailability().status(from: japanese, to: english)
            guard let self, !Task.isCancelled else { return }
            guard status == .installed else {
                self.setEnglishLabelText(
                    status == .supported
                        ? "Couldn’t translate. Add Japanese and English in Settings → General → Language & Region → Translation Languages."
                        : ""
                )
                return
            }

            let session = self.translationSession
                ?? TranslationSession(installedSource: japanese, target: english)
            self.translationSession = session

            do {
                let response = try await session.translate(sentence)
                guard !Task.isCancelled, self.currentSentence == sentence else { return }
                self.setEnglishLabelText(response.targetText)
            } catch {
                guard !Task.isCancelled, self.currentSentence == sentence else { return }
                self.setEnglishLabelText(
                    "Couldn’t translate. Add Japanese and English in Settings → General → Language & Region → Translation Languages."
                )
            }
        }
        #endif
    }

    private func resolvedDialogueNuanceContext() -> DialogueNuanceContext {
        if let dialogueContext {
            return dialogueContext
        }

        if let audio = dialogueLineAudio,
           audio.dialogueLines.indices.contains(audio.lineIndex) {
            let lines = audio.dialogueLines.map {
                DialogueNuanceContext.Line(
                    speaker: "",
                    japanese: $0,
                    english: nil
                )
            }
            if let context = DialogueNuanceContext.around(lines: lines, focusedIndex: audio.lineIndex) {
                return DialogueNuanceContext(
                    preceding: context.preceding,
                    focused: DialogueNuanceContext.Line(
                        speaker: "",
                        japanese: currentSentence.trimmingCharacters(in: .whitespacesAndNewlines),
                        english: providedEnglish
                    ),
                    following: context.following
                )
            }
        }

        return DialogueNuanceContext.isolated(
            japanese: currentSentence,
            english: providedEnglish
        )
    }

    @objc private func nuanceButtonTapped() {
        let trimmed = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        nuanceCardView.isHidden = false
        beginNuanceLoadIfNeeded()
    }

    private func resetNuanceCard() {
        nuanceLoadTask?.cancel()
        nuanceLoadTask = nil
        nuanceLoadRequest = nil
        nuanceCardView.apply(.loading)
        nuanceCardView.isHidden = true
    }

    private func beginNuanceLoadIfNeeded() {
        let request = GeminiDialogueNuance.Request(context: resolvedDialogueNuanceContext())
        if nuanceLoadRequest == request, nuanceLoadTask != nil {
            return
        }

        nuanceLoadTask?.cancel()
        nuanceLoadRequest = request

        if !GeminiDialogueNuance.isAvailable {
            nuanceCardView.apply(.unavailable(GeminiDialogueNuance.unavailabilityMessage))
            return
        }

        nuanceLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let cached = await GeminiDialogueNuance.cachedResult(for: request) {
                guard !Task.isCancelled else { return }
                self.nuanceCardView.apply(.result(cached))
                return
            }

            self.nuanceCardView.apply(.loading)
            do {
                let result = try await GeminiDialogueNuance.explain(request)
                guard !Task.isCancelled else { return }
                self.nuanceCardView.apply(.result(result))
            } catch {
                guard !Task.isCancelled else { return }
                let message = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                self.nuanceCardView.apply(.failed(message))
            }
        }
    }

    private func handleSelectionChanged(index: Int?, surface: String?) {
        guard let surface, !surface.isEmpty else {
            wordDictionaryDetailView.configure(surface: "")
            selectionStartDivider.isHidden = true
            return
        }

        wordDictionaryDetailView.configure(surface: surface, sentence: currentSentence)
        selectionStartDivider.isHidden = false
    }

    @objc private func speakFullSentenceTapped() {
        let trimmed = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let recordedClip, !recordedClip.pcmData.isEmpty {
            if let onReplayClip {
                onReplayClip(recordedClip)
            } else {
                RealtimePCMPlayer.shared.play(recordedClip)
            }
            return
        }
        if canPlayDialogueLineAudio, let dialogueLineAudio {
            grammarAudioPlayer.playDialogueLine(
                at: dialogueLineAudio.lineIndex,
                publishedAudioUrl: dialogueLineAudio.publishedAudioUrl,
                audioKey: dialogueLineAudio.audioKey,
                cacheMetadata: dialogueLineAudio.cacheMetadata,
                dialogueLines: dialogueLineAudio.dialogueLines,
                fallbackText: trimmed
            )
            return
        }
        wordSpeaker.speak(trimmed)
    }

    private func openRepeatAfterMe() {
        let trimmed = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        grammarAudioPlayer.stop()
        wordSpeaker.stop()

        let repeatVC = RepeatAfterMeViewController(
            sentence: trimmed,
            englishTranslation: providedEnglish ?? englishTranslationLabel.text,
            recordedClip: recordedClip,
            dialogueLineAudio: dialogueLineAudio
        )
        navigationController?.pushViewController(repeatVC, animated: true)
    }
}
