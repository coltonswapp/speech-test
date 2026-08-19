//
//  SentenceScrubExperimentViewController.swift
//  shizen
//
//  Pan horizontally across a tokenized sentence to change the selection; haptics + JMdict gloss.
//

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
    private let recordedClip: RealtimeAudioClip?
    private let onReplayClip: ((RealtimeAudioClip) -> Void)?
    private let dialogueLineAudio: DialogueLineAudioReference?
    private let grammarAudioPlayer = GrammarAudioPlayer()

    init(
        sentence: String,
        englishTranslation: String? = nil,
        recordedClip: RealtimeAudioClip? = nil,
        onReplayClip: ((RealtimeAudioClip) -> Void)? = nil,
        dialogueLineAudio: DialogueLineAudioReference? = nil
    ) {
        currentSentence = sentence
        let trimmedEnglish = englishTranslation?.trimmingCharacters(in: .whitespacesAndNewlines)
        providedEnglish = (trimmedEnglish?.isEmpty ?? true) ? nil : trimmedEnglish
        self.recordedClip = recordedClip
        self.onReplayClip = onReplayClip
        self.dialogueLineAudio = dialogueLineAudio
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
        super.init(coder: coder)
    }

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let scrubbableSentenceView = ScrubbableSentenceView()

    /// Full-sentence English from the system Translation framework (below the Japanese line).
    private let englishTranslationLabel = UILabel()

    /// Sentence + translation on the leading side; circular play control on the trailing side.
    private let sentenceSectionRowStack = UIStackView()
    private let sentenceContentStack = UIStackView()

    private static let audioButtonSize: CGFloat = 56
    private static let audioGlyphColor = UIColor.systemYellow

    private let speakSentenceButton = UIButton(type: .system)
    private let speakSentenceGlyphView = UIImageView()
    private let repeatAfterMeButton = UIButton(type: .system)
    private let repeatAfterMeGlyphView = UIImageView()

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

    private let hintStack = UIStackView()
    private let hintIcon = UIImageView()
    private let hintLabel = UILabel()

    private var didInteract = false

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

        let exampleActions = Self.exampleSentences.map { title, text in
            UIAction(title: title, state: text == currentSentence ? .on : .off) { [weak self] _ in
                self?.applyExampleSentence(text)
            }
        }
        let examplesMenu = UIMenu(title: "Example sentence", children: exampleActions)

        return UIMenu(children: [overlayToggle, examplesMenu])
    }

    private func refreshOptionsMenu() {
        navigationItem.rightBarButtonItem?.menu = makeOptionsMenu()
    }

    private func applyExampleSentence(_ text: String) {
        guard text != currentSentence else { return }
        currentSentence = text
        providedEnglish = nil
        wordSpeaker.stop()
        grammarAudioPlayer.stop()
        updateSpeakButtonAccessibility()
        beginEnglishTranslationIfNeeded()

        scrubbableSentenceView.configure(
            sentence: currentSentence,
            font: titleFontForSentenceLine(),
            showsFurigana: true
        )

        didInteract = false
        hintStack.isHidden = false
        hintStack.alpha = 1

        refreshOptionsMenu()
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

        let titleFont = titleFontForSentenceLine()

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
        scrubbableSentenceView.configure(sentence: currentSentence, font: titleFont, showsFurigana: true)
        scrubbableSentenceView.bindDismissOnScroll(scrollView)
        scrubbableSentenceView.bindDismissOnTap(scrollView)

        englishTranslationLabel.font = .preferredFont(forTextStyle: .subheadline)
        englishTranslationLabel.textColor = .secondaryLabel
        englishTranslationLabel.textAlignment = .natural
        englishTranslationLabel.numberOfLines = 0
        setEnglishLabelText(providedEnglish ?? "")

        sentenceContentStack.axis = .vertical
        sentenceContentStack.alignment = .leading
        sentenceContentStack.spacing = 6
        sentenceContentStack.addArrangedSubview(scrubbableSentenceView)
        sentenceContentStack.addArrangedSubview(englishTranslationLabel)

        sentenceContentStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sentenceContentStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        sentenceSectionRowStack.axis = .horizontal
        sentenceSectionRowStack.alignment = .top
        sentenceSectionRowStack.spacing = 16
        sentenceSectionRowStack.distribution = .fill
        sentenceSectionRowStack.addArrangedSubview(sentenceContentStack)
        sentenceSectionRowStack.addArrangedSubview(repeatAfterMeButton)
        sentenceSectionRowStack.addArrangedSubview(speakSentenceButton)

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

        repeatAfterMeButton.setContentHuggingPriority(.required, for: .horizontal)
        repeatAfterMeButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        Self.configureGlassAudioButton(
            repeatAfterMeButton,
            glyphView: repeatAfterMeGlyphView,
            symbolName: "person.wave.2.fill",
            glyphPointSize: 20,
            accessibilityLabel: "Repeat after me"
        )
        repeatAfterMeButton.accessibilityHint = "Listen to the sentence, then repeat it with the tutor"
        repeatAfterMeButton.addTarget(self, action: #selector(repeatAfterMeTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            speakSentenceButton.topAnchor.constraint(equalTo: scrubbableSentenceView.sentenceLineView.topAnchor),
            speakSentenceButton.trailingAnchor.constraint(equalTo: sentenceSectionRowStack.trailingAnchor),
            repeatAfterMeButton.topAnchor.constraint(equalTo: scrubbableSentenceView.sentenceLineView.topAnchor),
            repeatAfterMeButton.trailingAnchor.constraint(equalTo: speakSentenceButton.leadingAnchor, constant: -10),
        ])

        hintIcon.translatesAutoresizingMaskIntoConstraints = false
        hintIcon.image = UIImage(systemName: "hand.tap.fill")
        hintIcon.tintColor = .tertiaryLabel
        hintIcon.contentMode = .scaleAspectFit

        hintLabel.font = .preferredFont(forTextStyle: .subheadline)
        hintLabel.textColor = .tertiaryLabel
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.text = "Pan across the sentence to explore definitions."

        hintStack.axis = .vertical
        hintStack.alignment = .center
        hintStack.spacing = 10
        hintStack.addArrangedSubview(hintIcon)
        hintStack.addArrangedSubview(hintLabel)

        NSLayoutConstraint.activate([
            hintIcon.widthAnchor.constraint(equalToConstant: 36),
            hintIcon.heightAnchor.constraint(equalToConstant: 36),
        ])

        contentStack.addArrangedSubview(sentenceSectionRowStack)
        contentStack.addArrangedSubview(hintStack)
        contentStack.setCustomSpacing(20, after: hintStack)
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
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        speakSentenceButton.bringSubviewToFront(speakSentenceGlyphView)
        repeatAfterMeButton.bringSubviewToFront(repeatAfterMeGlyphView)
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
        englishTranslationLabel.isHidden = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
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

    private func handleSelectionChanged(index: Int?, surface: String?) {
        if index != nil, !didInteract {
            didInteract = true
            UIView.animate(withDuration: 0.2, animations: {
                self.hintStack.alpha = 0
            }, completion: { _ in
                self.hintStack.isHidden = true
            })
        }

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

    @objc private func repeatAfterMeTapped() {
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
