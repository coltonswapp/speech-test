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
    /// Clip window the dialogue already used for this line. Token-stamp bounds
    /// when those replaced the file's line marks. Playback seeks here.
    var timeRange: Range<TimeInterval>? = nil
    /// Used when `timeRange` is missing so clip-slice play can still follow
    /// stamp windows instead of published m4a marks.
    var tokenSync: DialogueTokenSync? = nil
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
    /// Validated token timings from the host. Used only for dialogue-line karaoke.
    private var tokenSync: DialogueTokenSync?
    private let recordedClip: RealtimeAudioClip?
    private let onReplayClip: ((RealtimeAudioClip) -> Void)?
    private let dialogueLineAudio: DialogueLineAudioReference?
    /// Neighboring dialogue lines for the Gemini nuance card.
    private var dialogueContext: DialogueNuanceContext?
    private let grammarAudioPlayer = GrammarAudioPlayer()
    private var appliedKaraokeTokenKey = -1

    init(
        sentence: String,
        englishTranslation: String? = nil,
        recordedClip: RealtimeAudioClip? = nil,
        onReplayClip: ((RealtimeAudioClip) -> Void)? = nil,
        dialogueLineAudio: DialogueLineAudioReference? = nil,
        dialogueContext: DialogueNuanceContext? = nil,
        tokens: [JapaneseToken]? = nil,
        tokenSync: DialogueTokenSync? = nil
    ) {
        currentSentence = sentence
        let trimmedEnglish = englishTranslation?.trimmingCharacters(in: .whitespacesAndNewlines)
        providedEnglish = (trimmedEnglish?.isEmpty ?? true) ? nil : trimmedEnglish
        providedTokens = tokens.flatMap { $0.isEmpty ? nil : $0 }
        self.recordedClip = recordedClip
        self.onReplayClip = onReplayClip
        self.dialogueLineAudio = dialogueLineAudio
        self.dialogueContext = dialogueContext
        self.tokenSync = tokenSync
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
        tokenSync = nil
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
    private let nuanceButton = GlassIconButton(
        symbolName: "sparkle.magnifyingglass",
        pointSize: 22,
        tintColor: .systemYellow,
        accessibilityLabel: "Deeper meaning"
    )
    private let nuanceCardView = DialogueNuanceCardView()
    private var nuanceCardIsShown = false
    private var nuanceCardAnimator: UIViewPropertyAnimator?
    /// The animator's forward direction leaves the card visible when this is true.
    private var nuanceAnimatorEndsShown = false
    /// Reversing the active reveal animator runs the card all the way back to the button.
    private var reversingNuanceAnimatorReachesButton = false
    /// Pixels of the card while it flies back to the button and the stack gap closes.
    private var nuanceDismissSnapshot: UIView?
    private var nuanceLoadTask: Task<Void, Never>?
    private var nuanceLoadRequest: GeminiDialogueNuance.Request?
    /// Token or span the learner last selected, included in a QA note.
    private var qaSelectionSummary: String?

    private static let nuanceSymbol = "sparkle.magnifyingglass"
    private static let nuanceDismissSymbol = "arrow.down.left"
    private static let nuanceSymbolPointSize: CGFloat = 22

    private static let audioButtonSize: CGFloat = 56
    private static let audioGlyphPointSize: CGFloat = 22
    private static let audioGlyphColor = UIColor.systemYellow

    private let speakSentenceButton = UIButton(type: .system)
    private let speakSentenceGlyphView = UIImageView()
    private var isPlayingSentence = false
    private var sentencePlaybackGeneration = 0

    /// Direct (non-SwiftUI) system translation, iOS 26+. Reused across
    /// sentences — the ja→en pair never changes for this screen.
    private var translationSession: TranslationSession?
    private var translationTask: Task<Void, Never>?

    private let wordSpeaker = WordUtteranceSpeaker()
    private let wordDictionaryDetailView: WordDictionaryDetailView = {
        let v = WordDictionaryDetailView()
        v.showsCompounds = false
        v.showsSenseSuggestion = true
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

        var children: [UIMenuElement] = [overlayToggle, repeatAfterMe, examplesMenu]
        if lessonQAHost?.canPresentContentQANote == true {
            let note = UIAction(
                title: "Note",
                image: UIImage(systemName: "square.and.pencil")
            ) { [weak self] _ in
                self?.presentContentQANote()
            }
            children.insert(note, at: 0)
        }
        return UIMenu(children: children)
    }

    /// Lesson shell that pushed this scrub, when the sentence belongs to a Studio scene.
    private var lessonQAHost: DialogueNestedPagingExperimentViewController? {
        navigationController?.viewControllers
            .compactMap { $0 as? DialogueNestedPagingExperimentViewController }
            .last
    }

    private func presentContentQANote() {
        guard let host = lessonQAHost else { return }
        var details = ["Japanese: \(currentSentence)"]
        if let english = qaEnglishLine() {
            details.append("English: \(english)")
        }
        let speaker = dialogueContext?.focused.speaker
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !speaker.isEmpty {
            details.append("Speaker: \(speaker)")
        }
        if let lineIndex = dialogueLineAudio?.lineIndex {
            details.append("Spoken index: \(lineIndex)")
        }
        if let qaSelectionSummary {
            details.append(qaSelectionSummary)
        }
        let title: String
        if let lineIndex = dialogueLineAudio?.lineIndex {
            title = "Sentence scrub · line \(lineIndex + 1)"
        } else {
            title = "Sentence scrub"
        }
        host.presentContentQANote(focusTitle: title, focusDetailLines: details)
    }

    private func qaEnglishLine() -> String? {
        if let providedEnglish, !providedEnglish.isEmpty {
            return providedEnglish
        }
        let shown = englishTranslationLabel.text?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !shown.isEmpty, shown != "Translating…", !shown.hasPrefix("Couldn’t translate") else {
            return nil
        }
        return shown
    }

    private func refreshOptionsMenu() {
        navigationItem.rightBarButtonItem?.menu = makeOptionsMenu()
    }

    private func applyExampleSentence(_ text: String) {
        guard text != currentSentence else { return }
        currentSentence = text
        providedEnglish = nil
        providedTokens = nil
        tokenSync = nil
        dialogueContext = nil
        qaSelectionSummary = nil
        stopSentencePlayback()
        updateSpeakButtonAccessibility()
        beginEnglishTranslationIfNeeded()
        applySentenceToScrubView()

        resetNuanceCard()
        refreshOptionsMenu()
    }

    private func applySentenceToScrubView() {
        appliedKaraokeTokenKey = -1
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
        scrubbableSentenceView.onSpanSelected = { [weak self] range, surface in
            self?.handleSpanSelected(range: range, surface: surface)
        }
        scrubbableSentenceView.onRequestDictionaryDetail = { [weak self] surface, sentence in
            guard let self else { return }
            WordDictionaryDetailSheetPresenter.push(
                surface: surface,
                sentence: sentence,
                from: self
            )
        }
        wordDictionaryDetailView.onSelectRelatedWord = { [weak self] word in
            guard let self else { return }
            WordDictionaryDetailSheetPresenter.push(
                surface: word,
                glossFraming: .word,
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
            glyphPointSize: Self.audioGlyphPointSize,
            accessibilityLabel: "Speak sentence"
        )
        speakSentenceButton.accessibilityHint = "Plays audio of the Japanese example sentence"
        speakSentenceButton.addTarget(self, action: #selector(speakFullSentenceTapped), for: .touchUpInside)

        englishTranslationLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        englishTranslationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        nuanceButton.setContentHuggingPriority(.required, for: .horizontal)
        nuanceButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        nuanceButton.accessibilityHint = "Shows a deeper reading of this line"
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
            nuanceButton.heightAnchor.constraint(equalTo: speakSentenceButton.heightAnchor),
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshOptionsMenu()
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
            stopSentencePlayback()
            translationTask?.cancel()
            nuanceLoadTask?.cancel()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        speakSentenceButton.bringSubviewToFront(speakSentenceGlyphView)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard nuanceCardAnimator != nil || nuanceDismissSnapshot != nil else { return }
        let shown = nuanceCardIsShown
        discardNuanceAnimator()
        coordinator.animate(alongsideTransition: { _ in
            self.applySettledNuanceCard(shown: shown)
        })
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
        if isPlayingSentence {
            speakSentenceButton.accessibilityLabel = "Pause"
            speakSentenceButton.accessibilityHint = "Stops audio playback"
            return
        }
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

    private func setSentencePlaying(_ playing: Bool) {
        guard isPlayingSentence != playing else { return }
        isPlayingSentence = playing
        let symbolName = playing ? "pause.fill" : "play.fill"
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: Self.audioGlyphPointSize, weight: .semibold)
        let image = UIImage(systemName: symbolName, withConfiguration: symbolConfig)?
            .withRenderingMode(.alwaysTemplate)
        speakSentenceGlyphView.preferredSymbolConfiguration = symbolConfig
        if let image {
            speakSentenceGlyphView.setSymbolImage(image, contentTransition: .replace)
        } else {
            speakSentenceGlyphView.image = image
        }
        updateSpeakButtonAccessibility()
    }

    private func finishSentencePlayback() {
        clearKaraokeHighlight()
        setSentencePlaying(false)
    }

    private func stopSentencePlayback() {
        sentencePlaybackGeneration += 1
        grammarAudioPlayer.stop()
        wordSpeaker.stop()
        RealtimePCMPlayer.shared.stop()
        finishSentencePlayback()
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
        if nuanceCardIsShown {
            nuanceCardIsShown = false
            dismissNuanceCard()
        } else {
            nuanceCardIsShown = true
            beginNuanceLoadIfNeeded()
            revealNuanceCard()
        }
    }

    /// Opens the card from the deeper-meaning button's corner. The glyph
    /// slides the same way, and dismiss reverses both motions.
    private func revealNuanceCard() {
        updateNuanceButton(showing: true)
        if nuanceDismissSnapshot != nil {
            continueNuanceRevealFromDismissSnapshot()
            return
        }
        if retargetNuanceAnimation(showing: true) { return }
        let reversesToButton = nuanceCardView.isHidden
        if reversesToButton {
            prepareNuanceCardForReveal()
        }
        let animator = GlossMotion.revealAnimator {
            self.nuanceCardView.isHidden = false
            self.nuanceCardView.alpha = 1
            self.nuanceCardView.transform = .identity
            self.view.layoutIfNeeded()
        }
        beginNuanceAnimator(animator, endsShown: true, reversesToButton: reversesToButton)
        animator.startAnimation()
    }

    private func dismissNuanceCard() {
        updateNuanceButton(showing: false)
        if retargetNuanceAnimation(showing: false) { return }
        if nuanceDismissSnapshot != nil { return }
        beginNuanceSnapshotDismiss()
    }

    private func updateNuanceButton(showing: Bool) {
        if showing {
            nuanceButton.transitionSymbol(
                to: Self.nuanceDismissSymbol,
                pointSize: Self.nuanceSymbolPointSize,
                direction: .down
            )
            nuanceButton.accessibilityLabel = "Hide deeper meaning"
            nuanceButton.accessibilityHint = "Hides the deeper reading of this line"
        } else {
            nuanceButton.transitionSymbol(
                to: Self.nuanceSymbol,
                pointSize: Self.nuanceSymbolPointSize,
                direction: .up
            )
            nuanceButton.accessibilityLabel = "Deeper meaning"
            nuanceButton.accessibilityHint = "Shows a deeper reading of this line"
        }
    }

    /// Collapse measured while the card is in the stack, then the gap is closed
    /// again so the reveal animation can open it together with the scale.
    private func prepareNuanceCardForReveal() {
        var fromTransform = CGAffineTransform.identity
        UIView.performWithoutAnimation {
            nuanceCardView.alpha = 0
            nuanceCardView.isHidden = false
            view.layoutIfNeeded()
            fromTransform = nuanceCardTransformFromButton()
            nuanceCardView.transform = fromTransform
            nuanceCardView.isHidden = true
            view.layoutIfNeeded()
        }
        nuanceCardView.isHidden = false
        nuanceCardView.transform = fromTransform
        nuanceCardView.alpha = 0
    }

    /// Flies a snapshot into the button while the real card leaves the stack,
    /// so the gap closes on the same curve instead of snapping shut afterward.
    private func beginNuanceSnapshotDismiss() {
        guard nuanceCardView.bounds.width > 1,
              nuanceCardView.bounds.height > 1,
              let host = nuanceCardView.superview,
              let snapshot = nuanceCardView.snapshotView(afterScreenUpdates: false) else {
            beginNuanceModelDismiss()
            return
        }

        let collapsed = nuanceCardTransformFromButton()
        let pose = presentedPose(of: nuanceCardView)
        snapshot.translatesAutoresizingMaskIntoConstraints = true
        snapshot.autoresizingMask = []
        snapshot.bounds = nuanceCardView.bounds
        snapshot.center = nuanceCardView.center
        snapshot.transform = pose.transform
        snapshot.alpha = pose.alpha
        snapshot.isUserInteractionEnabled = false
        snapshot.accessibilityElementsHidden = true
        snapshot.layer.zPosition = 1
        host.addSubview(snapshot)
        nuanceDismissSnapshot = snapshot

        UIView.performWithoutAnimation {
            nuanceCardView.isHidden = true
            nuanceCardView.alpha = 1
            nuanceCardView.transform = .identity
        }

        let animator = GlossMotion.dismissAnimator {
            snapshot.transform = collapsed
            self.view.layoutIfNeeded()
        }
        animator.addAnimations({
            snapshot.alpha = 0
        }, delayFactor: GlossMotion.dismissFadeDelay)
        beginNuanceAnimator(animator, endsShown: false, reversesToButton: false)
        animator.startAnimation()
    }

    /// Used when a snapshot can't be taken. The card itself eases back to the button.
    private func beginNuanceModelDismiss() {
        let collapsed = nuanceCardTransformFromButton()
        let pose = presentedPose(of: nuanceCardView)
        let animator = GlossMotion.dismissAnimator {
            self.nuanceCardView.transform = collapsed
        }
        animator.addAnimations({
            self.nuanceCardView.alpha = 0
        }, delayFactor: GlossMotion.dismissFadeDelay)
        // Discard any in-flight reveal before planting the pose it would otherwise snap away.
        beginNuanceAnimator(animator, endsShown: false, reversesToButton: false)
        UIView.performWithoutAnimation {
            nuanceCardView.transform = pose.transform
            nuanceCardView.alpha = pose.alpha
        }
        animator.startAnimation()
    }

    /// Show tapped while the snapshot is still in flight. Plant that pose on the
    /// real card and spring it open.
    private func continueNuanceRevealFromDismissSnapshot() {
        let snapshot = nuanceDismissSnapshot
        let pose = snapshot.map { presentedPose(of: $0) } ?? (transform: .identity, alpha: 1)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        discardNuanceAnimator()
        UIView.performWithoutAnimation {
            nuanceCardView.isHidden = false
            view.layoutIfNeeded()
            nuanceCardView.transform = pose.transform
            nuanceCardView.alpha = pose.alpha
            snapshot?.removeFromSuperview()
        }
        CATransaction.commit()
        nuanceDismissSnapshot = nil

        let animator = GlossMotion.revealAnimator {
            self.nuanceCardView.alpha = 1
            self.nuanceCardView.transform = .identity
            self.view.layoutIfNeeded()
        }
        beginNuanceAnimator(animator, endsShown: true, reversesToButton: false)
        animator.startAnimation()
    }

    private func retargetNuanceAnimation(showing: Bool) -> Bool {
        guard nuanceDismissSnapshot == nil,
              let animator = nuanceCardAnimator,
              animator.state == .active else { return false }
        let headingShown = nuanceAnimatorEndsShown != animator.isReversed
        if headingShown == showing { return true }
        // A reveal resumed from a half-hidden snapshot would only spring back
        // to that midpoint. Start a new dismiss so the card still reaches the button.
        if !showing, nuanceAnimatorEndsShown, !reversingNuanceAnimatorReachesButton {
            return false
        }
        animator.isReversed.toggle()
        return true
    }

    private func beginNuanceAnimator(
        _ animator: UIViewPropertyAnimator,
        endsShown: Bool,
        reversesToButton: Bool
    ) {
        discardNuanceAnimator()
        nuanceAnimatorEndsShown = endsShown
        reversingNuanceAnimatorReachesButton = reversesToButton
        animator.scrubsLinearly = false
        animator.addCompletion { [weak self] _ in
            guard let self, self.nuanceCardAnimator === animator else { return }
            self.nuanceCardAnimator = nil
            self.applySettledNuanceCard(shown: self.nuanceCardIsShown)
        }
        nuanceCardAnimator = animator
    }

    private func discardNuanceAnimator() {
        guard let animator = nuanceCardAnimator else { return }
        nuanceCardAnimator = nil
        guard animator.state == .active else { return }
        animator.stopAnimation(true)
    }

    private func applySettledNuanceCard(shown: Bool) {
        nuanceDismissSnapshot?.removeFromSuperview()
        nuanceDismissSnapshot = nil
        UIView.performWithoutAnimation {
            if shown {
                nuanceCardView.isHidden = false
                nuanceCardView.alpha = 1
                nuanceCardView.transform = .identity
                nuanceCardView.presentPendingFeedback()
            } else {
                nuanceCardView.isHidden = true
                nuanceCardView.layer.removeAllAnimations()
                nuanceCardView.transform = .identity
                nuanceCardView.alpha = 1
            }
            view.layoutIfNeeded()
        }
    }

    private func presentedPose(of view: UIView) -> (transform: CGAffineTransform, alpha: CGFloat) {
        guard let presentation = view.layer.presentation() else {
            return (view.transform, view.alpha)
        }
        return (
            CATransform3DGetAffineTransform(presentation.transform),
            CGFloat(presentation.opacity)
        )
    }

    /// Thumbs wait until the card has finished growing so the two springs don't overlap.
    private func animateNuanceCardResizeIfVisible() {
        guard !nuanceCardView.isHidden else {
            nuanceCardView.presentPendingFeedback()
            return
        }
        GlossMotion.animateResize(in: view, joining: nuanceCardAnimator) { [weak self] in
            self?.nuanceCardView.presentPendingFeedback()
        }
    }

    private func nuanceCardTransformFromButton() -> CGAffineTransform {
        guard let host = nuanceCardView.superview else { return .identity }
        let buttonCenter = nuanceButton.convert(
            CGPoint(x: nuanceButton.bounds.midX, y: nuanceButton.bounds.midY),
            to: host
        )
        return GlossMotion.collapsedTransform(for: nuanceCardView, toward: buttonCenter)
    }

    private func resetNuanceCard() {
        nuanceLoadTask?.cancel()
        nuanceLoadTask = nil
        nuanceLoadRequest = nil
        discardNuanceAnimator()
        nuanceDismissSnapshot?.removeFromSuperview()
        nuanceDismissSnapshot = nil
        nuanceCardView.layer.removeAllAnimations()
        nuanceCardView.isHidden = true
        nuanceCardView.transform = .identity
        nuanceCardView.alpha = 1
        nuanceCardView.apply(.loading)
        nuanceCardIsShown = false
        nuanceButton.setSymbol(
            Self.nuanceSymbol,
            pointSize: Self.nuanceSymbolPointSize,
            tintColor: Self.audioGlyphColor
        )
        nuanceButton.accessibilityLabel = "Deeper meaning"
        nuanceButton.accessibilityHint = "Shows a deeper reading of this line"
        nuanceButton.transform = .identity
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
                self.nuanceCardView.apply(.result(cached.result, feedback: cached.feedback))
                self.animateNuanceCardResizeIfVisible()
                return
            }

            self.nuanceCardView.apply(.loading)
            do {
                let explained = try await GeminiDialogueNuance.explain(request)
                guard !Task.isCancelled else { return }
                self.nuanceCardView.apply(.result(explained.result, feedback: explained.feedback))
                self.animateNuanceCardResizeIfVisible()
            } catch {
                guard !Task.isCancelled else { return }
                let message = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                self.nuanceCardView.apply(.failed(message))
                self.animateNuanceCardResizeIfVisible()
            }
        }
    }

    private func handleSelectionChanged(index: Int?, surface: String?) {
        guard let surface, !surface.isEmpty else {
            qaSelectionSummary = nil
            wordDictionaryDetailView.configure(surface: "")
            selectionStartDivider.isHidden = true
            return
        }

        if let index,
           let range = scrubbableSentenceView.lookupTokenRange(for: index),
           range.count > 1 {
            qaSelectionSummary = "Span: \(surface)"
            wordDictionaryDetailView.configureSelectedSpan(
                surface: surface,
                sentence: currentSentence,
                tokens: scrubbableSentenceView.tokenTexts(in: range)
            )
        } else {
            qaSelectionSummary = "Token: \(surface)"
            wordDictionaryDetailView.configure(surface: surface, sentence: currentSentence)
        }
        selectionStartDivider.isHidden = false
    }

    private func handleSpanSelected(range: ClosedRange<Int>, surface: String) {
        qaSelectionSummary = "Span: \(surface)"
        wordDictionaryDetailView.configureSelectedSpan(
            surface: surface,
            sentence: currentSentence,
            tokens: scrubbableSentenceView.tokenTexts(in: range)
        )
        selectionStartDivider.isHidden = false
    }

    @objc private func speakFullSentenceTapped() {
        if isPlayingSentence {
            stopSentencePlayback()
            return
        }

        let trimmed = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        sentencePlaybackGeneration += 1
        let generation = sentencePlaybackGeneration
        let finished: () -> Void = { [weak self] in
            guard let self, self.sentencePlaybackGeneration == generation else { return }
            self.finishSentencePlayback()
        }

        setSentencePlaying(true)
        if let recordedClip, !recordedClip.pcmData.isEmpty {
            clearKaraokeHighlight()
            if let onReplayClip {
                onReplayClip(recordedClip)
                let duration = Double(recordedClip.pcmData.count / 2) / recordedClip.sampleRate
                DispatchQueue.main.asyncAfter(deadline: .now() + max(0.4, duration + 0.15), execute: finished)
            } else {
                RealtimePCMPlayer.shared.play(recordedClip, onFinished: finished)
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
                fallbackText: trimmed,
                lineTimeRange: dialogueLineAudio.timeRange,
                tokenSync: tokenSync,
                onTime: { [weak self] time in
                    self?.applyKaraoke(at: time)
                },
                onFinished: finished
            )
            return
        }
        clearKaraokeHighlight()
        wordSpeaker.speak(trimmed, onFinished: finished)
    }

    private func applyKaraoke(at time: TimeInterval) {
        let sync = ExperimentSettings.dialogueShowsTokenSync ? tokenSync : nil
        guard let sync, let dialogueLineAudio else {
            clearKaraokeHighlight()
            return
        }
        let fullHeight = ExperimentSettings.dialogueTokenSyncHighlightStyle == .full
        let tokenIndex = sync.tokenIndex(lineIndex: dialogueLineAudio.lineIndex, at: time)
        let key = (tokenIndex ?? -1) + (fullHeight ? 10_000 : 0)
        guard key != appliedKaraokeTokenKey else { return }
        appliedKaraokeTokenKey = key
        if let tokenIndex,
           let range = sync.utf16Range(
            lineIndex: dialogueLineAudio.lineIndex,
            tokenIndex: tokenIndex,
            inDisplay: scrubbableSentenceView.sentenceLineView.displayedString
           ) {
            scrubbableSentenceView.setKaraokeHighlight(
                range: range,
                fullHeight: fullHeight,
                highlightColor: FuriganaTranscriptLabel.tokenSyncHighlightColor
            )
        } else {
            scrubbableSentenceView.setKaraokeHighlight(
                range: nil,
                fullHeight: fullHeight,
                highlightColor: FuriganaTranscriptLabel.tokenSyncHighlightColor
            )
        }
    }

    private func clearKaraokeHighlight() {
        appliedKaraokeTokenKey = -1
        scrubbableSentenceView.setKaraokeHighlight(
            range: nil,
            fullHeight: false,
            highlightColor: FuriganaTranscriptLabel.tokenSyncHighlightColor
        )
    }

    private func openRepeatAfterMe() {
        let trimmed = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stopSentencePlayback()

        let repeatVC = RepeatAfterMeViewController(
            sentence: trimmed,
            englishTranslation: providedEnglish ?? englishTranslationLabel.text,
            recordedClip: recordedClip,
            dialogueLineAudio: dialogueLineAudio
        )
        navigationController?.pushViewController(repeatVC, animated: true)
    }
}
