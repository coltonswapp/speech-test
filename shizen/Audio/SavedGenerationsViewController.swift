//
//  SavedGenerationsViewController.swift
//  shizen
//
//  Settings screen: saved TTS bundles, tokenizer tools, and debug/experiments.
//

import TTSCore
import UIKit

final class SavedGenerationsViewController: UIViewController {

    private let store: SavedGenerationStore
    private var entries: [SavedGenerationEntry] = []
    private var progressiveContainerCoordinator: ProgressiveContainerCoordinator?
    var onSelect: ((URL) -> Void)?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    private nonisolated enum Section: Int, CaseIterable, Sendable {
        case resources
        case savedGenerations
        case tokenizerTools
        case aiUsage
        case debug

        var title: String {
            switch self {
            case .resources: return "Resources"
            case .savedGenerations: return "Saved generations"
            case .tokenizerTools: return "Japanese tokenization"
            case .aiUsage: return "AI usage"
            case .debug: return "Debug"
            }
        }
    }

    private nonisolated enum ResourceRow: Int, CaseIterable, Hashable, Sendable {
        case kana
        case grammar
        case cmsLessons

        var title: String {
            switch self {
            case .kana: return "Kana"
            case .grammar: return "Grammar"
            case .cmsLessons: return "CMS lessons"
            }
        }

        var subtitle: String {
            switch self {
            case .kana: return "Hiragana & katakana charts, lessons"
            case .grammar: return "Grammar points, checkpoints"
            case .cmsLessons: return "Waterfall grid · fetch published dialogue lessons"
            }
        }

        var symbolName: String {
            switch self {
            case .kana: return "textformat.characters"
            case .grammar: return "text.book.closed"
            case .cmsLessons: return "rectangle.grid.2x2"
            }
        }
    }

    private nonisolated enum Item: Hashable, Sendable {
        case resource(ResourceRow)
        case savedGeneration(id: URL, title: String, subtitle: String)
        case appTokenizer(subtitle: String?)
        case tokenizerLab
        case contextualGlossBackend(subtitle: String?)
        case aiUsageSummary(subtitle: String?)
        case soundsEnabled
        case debugDestination(DebugSettingsRow)
    }

    private nonisolated enum DebugSettingsRow: Int, CaseIterable, Hashable, Sendable {
        case textToSpeech
        case kanaLearningFlow
        case kanaProgressPath
        case kanaProgressGrid
        case waterfallGrid
        case lessonWaterfallGrid
        case sentenceScrub
        case languageProgressSnake
        case hiraganaChart
        case katakanaChart
        case flashcards
        case kanaSpelling
        case kanaListenSpelling
        case kanaSoundMatch
        case kanaPairMatch
        case kanaSoundMatchBounce
        case kanaLessonComplete
        case kanaLessonEncouragementBreak
        case emojiStickers
        case feedbackSounds
        case vocabSpeaking
        case realtimeTutor
        case tutorConversations
        case characterSpeaking
        case speechProfileOverlay
        case glassProgressVoiceOverlay
        case glassNotchShelf
        case dialogueExperimentHarness
        case dialogueNestedPaging
        case dialogueBubbleUnderglow

        var title: String {
            switch self {
            case .textToSpeech: return "Text to Speech"
            case .kanaLearningFlow: return "Kana learning flow"
            case .kanaProgressPath: return "Kana progress path"
            case .kanaProgressGrid: return "Kana progress grid"
            case .waterfallGrid: return "Waterfall grid"
            case .lessonWaterfallGrid: return "Lesson waterfall grid"
            case .sentenceScrub: return "Sentence scrub"
            case .languageProgressSnake: return "Language progress (snake)"
            case .hiraganaChart: return "Hiragana chart"
            case .katakanaChart: return "Katakana chart"
            case .flashcards: return "Flashcards"
            case .kanaSpelling: return "Kana spelling"
            case .kanaListenSpelling: return "Listen & spell"
            case .kanaSoundMatch: return "Kana → sound"
            case .kanaPairMatch: return "Kana pair match"
            case .kanaSoundMatchBounce: return "Match bounce tuner"
            case .kanaLessonComplete: return "Lesson complete"
            case .kanaLessonEncouragementBreak: return "Streak break screen"
            case .emojiStickers: return "Emoji stickers"
            case .feedbackSounds: return "Feedback sounds"
            case .vocabSpeaking: return "Vocab speaking"
            case .realtimeTutor: return "Realtime tutor"
            case .tutorConversations: return "Tutor conversations"
            case .characterSpeaking: return "Speaking characters"
            case .speechProfileOverlay: return "Speech profile overlay"
            case .glassProgressVoiceOverlay: return "Glass progress + voice"
            case .glassNotchShelf: return "Notch shelf glass"
            case .dialogueExperimentHarness: return "Dialogue lyrics harness"
            case .dialogueNestedPaging: return "Dialogue nested paging"
            case .dialogueBubbleUnderglow: return "Bubble underglow tuner"
            }
        }

        var subtitle: String {
            switch self {
            case .textToSpeech: return "Stream OpenAI TTS · sentence chunks · lyrics"
            case .kanaLearningFlow: return "Progress tiles · hiragana & katakana lessons · SRS"
            case .kanaProgressPath: return "Row-by-row hiragana lessons · SRS · chart"
            case .kanaProgressGrid: return "Hiragana & katakana heatmaps · 92 squares · size slider"
            case .waterfallGrid: return "Two-column cascade · key/value cards · variable height"
            case .lessonWaterfallGrid: return "Testing watefall grid style lesson screen"
            case .sentenceScrub: return "Pan token underlines · full JMdict entries"
            case .languageProgressSnake: return "Duolingo-style path · alternating lesson nodes"
            case .hiraganaChart: return "Manual-layout gojūon reference"
            case .katakanaChart: return "Manual-layout gojūon reference"
            case .flashcards: return "Swipe right · know it / left · review"
            case .kanaSpelling: return "Tap tiles to spell the target word"
            case .kanaListenSpelling: return "Hear the word, then spell it in kana"
            case .kanaSoundMatch: return "6 steps · hiragana ↔ romaji matching"
            case .kanaPairMatch: return "Tap to match · 4 pairs · kana ↔ romaji"
            case .kanaSoundMatchBounce: return "Sliders · preview success bounce"
            case .kanaLessonComplete: return "Preview summary · entry animation & encouragement"
            case .kanaLessonEncouragementBreak: return "Mid-lesson combo break · notch audio · header slides away"
            case .emojiStickers: return "Die-cut white halo · pick preset or type"
            case .feedbackSounds: return "Play success chimes and incorrect dong"
            case .vocabSpeaking: return "3 steps · speak the word with the mic"
            case .realtimeTutor: return "Speech-to-speech Japanese tutor · gpt-realtime-2"
            case .tutorConversations: return "Saved tutor transcripts"
            case .characterSpeaking: return "Waveform vs orb · encouragement clips"
            case .speechProfileOverlay: return "Liquid-glass capsule · drops in while audio plays"
            case .glassProgressVoiceOverlay: return "Progress chrome in glass container · toggle voice overlay"
            case .glassNotchShelf: return "Shelf under notch · voice meter peels out"
            case .dialogueExperimentHarness: return "Scenario audio · UIMenu clip switch · alignment QA"
            case .dialogueNestedPaging: return "Nested vertical scroll · boundary handoff · rectangles → circles"
            case .dialogueBubbleUnderglow: return "Single glass bubble · sliders for underglow tuning"
            }
        }

        var symbolName: String {
            switch self {
            case .textToSpeech: return "waveform"
            case .kanaLearningFlow: return "square.grid.2x2"
            case .kanaProgressPath: return "point.topleft.down.curvedto.point.bottomright.up"
            case .kanaProgressGrid: return "square.grid.3x3.fill"
            case .waterfallGrid: return "rectangle.grid.2x2"
            case .lessonWaterfallGrid: return "rectangle.grid.2x2.fill"
            case .sentenceScrub: return "text.cursor"
            case .languageProgressSnake: return "point.3.connected.trianglepath.dotted"
            case .hiraganaChart: return "textformat.characters"
            case .katakanaChart: return "textformat.characters.dottedunderline"
            case .flashcards: return "rectangle.stack"
            case .kanaSpelling: return "character.cursor.ibeam"
            case .kanaListenSpelling: return "ear"
            case .kanaSoundMatch: return "speaker.wave.2"
            case .kanaPairMatch: return "square.on.square"
            case .kanaSoundMatchBounce: return "slider.horizontal.3"
            case .kanaLessonComplete: return "checkmark.seal"
            case .kanaLessonEncouragementBreak: return "flame"
            case .emojiStickers: return "face.smiling"
            case .feedbackSounds: return "speaker.wave.3"
            case .vocabSpeaking: return "mic"
            case .realtimeTutor: return "person.wave.2"
            case .tutorConversations: return "bubble.left.and.bubble.right"
            case .characterSpeaking: return "person.bust"
            case .speechProfileOverlay: return "capsule.portrait"
            case .glassProgressVoiceOverlay: return "chart.bar.doc.horizontal"
            case .glassNotchShelf: return "iphone.gen3"
            case .dialogueExperimentHarness: return "waveform.path"
            case .dialogueNestedPaging: return "rectangle.arrowtriangle.2.inward"
            case .dialogueBubbleUnderglow: return "bubble.left.fill"
            }
        }
    }

    init(store: SavedGenerationStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = .systemGroupedBackground
        configureCollectionView()
        configureDataSource()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadEntries()
    }

    // MARK: - Collection view

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { sectionIndex, environment in
            var listConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            listConfiguration.headerMode = .supplementary
            return NSCollectionLayoutSection.list(
                using: listConfiguration,
                layoutEnvironment: environment
            )
        }

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> {
            [weak self] cell, _, item in
            self?.configure(cell: cell, for: item)
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { header, _, indexPath in
            var content = UIListContentConfiguration.groupedHeader()
            content.text = Section.allCases[indexPath.section].title
            header.contentConfiguration = content
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(
                using: cellRegistration,
                for: indexPath,
                item: item
            )
        }

        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(
                using: headerRegistration,
                for: indexPath
            )
        }
    }

    private func configure(cell: UICollectionViewListCell, for item: Item) {
        var content = UIListContentConfiguration.subtitleCell()
        content.secondaryTextProperties.color = .secondaryLabel
        cell.accessories = []

        switch item {
        case .resource(let row):
            content.text = row.title
            content.secondaryText = row.subtitle
            content.image = UIImage(systemName: row.symbolName)
            content.imageProperties.tintColor = .secondaryLabel
            cell.accessories = [.disclosureIndicator()]

        case .savedGeneration(_, let title, let subtitle):
            content.text = title
            content.secondaryText = subtitle
            content.textProperties.numberOfLines = 2
            content.image = UIImage(systemName: "waveform.badge.mic")
            content.imageProperties.tintColor = .secondaryLabel
            cell.accessories = [.disclosureIndicator()]

        case .appTokenizer(let subtitle):
            content.text = "App tokenizer"
            content.secondaryText = subtitle
            content.image = UIImage(systemName: "character.book.closed")
            content.imageProperties.tintColor = .secondaryLabel
            cell.accessories = [.disclosureIndicator()]

        case .tokenizerLab:
            content.text = "Tokenizer Lab"
            content.secondaryText = "NL · MeCab · Foundation model · Gemini Flash · Gemini Flash Lite"
            content.image = UIImage(systemName: "flask")
            content.imageProperties.tintColor = .secondaryLabel
            cell.accessories = [.disclosureIndicator()]

        case .contextualGlossBackend(let subtitle):
            content.text = "Contextual insights"
            content.secondaryText = subtitle
            content.image = UIImage(systemName: "sparkles")
            content.imageProperties.tintColor = .secondaryLabel
            cell.accessories = [.disclosureIndicator()]

        case .aiUsageSummary(let subtitle):
            content.text = "Gemini usage"
            content.secondaryText = subtitle
            content.image = UIImage(systemName: "chart.bar.doc.horizontal")
            content.imageProperties.tintColor = .secondaryLabel
            cell.accessories = [.disclosureIndicator()]

        case .soundsEnabled:
            content.text = "Sounds"
            content.secondaryText = "Success chimes, clicks, and incorrect feedback"
            content.image = UIImage(systemName: "speaker.wave.2.circle")
            content.imageProperties.tintColor = .secondaryLabel
            let toggle = UISwitch()
            toggle.isOn = ExperimentSettings.soundsEnabled
            toggle.addAction(UIAction { action in
                guard let toggle = action.sender as? UISwitch else { return }
                ExperimentSettings.soundsEnabled = toggle.isOn
            }, for: .valueChanged)
            cell.accessories = [.customView(configuration: .init(customView: toggle, placement: .trailing()))]

        case .debugDestination(let row):
            content.text = row.title
            content.secondaryText = row.subtitle
            content.image = UIImage(systemName: row.symbolName)
            content.imageProperties.tintColor = .secondaryLabel
            cell.accessories = [.disclosureIndicator()]
        }

        cell.contentConfiguration = content
        cell.backgroundConfiguration = UIBackgroundConfiguration.listGroupedCell()
    }

    private func reloadEntries() {
        entries = (try? store.listEntries()) ?? []
        applySnapshot()
        if entries.isEmpty {
            collectionView.backgroundView = makeEmptyLabel()
        } else {
            collectionView.backgroundView = nil
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections(Section.allCases)

        snapshot.appendItems(
            ResourceRow.allCases.map(Item.resource),
            toSection: .resources
        )

        snapshot.appendItems(
            entries.map { entry in
                Item.savedGeneration(
                    id: entry.directoryURL,
                    title: entry.utterancePreview.isEmpty ? "Untitled" : entry.utterancePreview,
                    subtitle: String(
                        format: "%@ · %d sentences · %.1fs · %@",
                        Self.dateFormatter.string(from: entry.createdAt),
                        entry.sentenceCount,
                        entry.durationSeconds,
                        entry.voice
                    )
                )
            },
            toSection: .savedGenerations
        )

        snapshot.appendItems(
            [
                .appTokenizer(subtitle: tokenizerSubtitle()),
                .tokenizerLab,
                .contextualGlossBackend(subtitle: contextualGlossBackendSubtitle()),
            ],
            toSection: .tokenizerTools
        )

        snapshot.appendItems(
            [.aiUsageSummary(subtitle: aiUsageSubtitle())],
            toSection: .aiUsage
        )

        snapshot.appendItems(
            [.soundsEnabled] + DebugSettingsRow.allCases.map(Item.debugDestination),
            toSection: .debug
        )

        dataSource.apply(snapshot, animatingDifferences: view.window != nil)
    }

    private func tokenizerSubtitle() -> String {
        let currentBackend = JapaneseTokenizerBackend.preferred
        if currentBackend == .foundationModel, !FoundationModelJapaneseTokenizer.isAvailable {
            return "\(currentBackend.displayName) · unavailable, falls back to MeCab"
        }
        if currentBackend.geminiModel != nil, !GeminiJapaneseTokenizer.isConfigured {
            return "\(currentBackend.displayName) · no API key, falls back to MeCab"
        }
        return "Sentence scrub · \(currentBackend.displayName)"
    }

    private func contextualGlossBackendSubtitle() -> String {
        let current = ContextualGlossBackend.preferred
        if current == .onDevice, !FoundationModelContextualGloss.isAvailable {
            return "\(current.displayName) · unavailable, insights hidden"
        }
        if current == .gemini, !GeminiContextualGloss.isConfigured {
            return "\(current.displayName) · no API key, insights hidden"
        }
        return current.displayName
    }

    private func aiUsageSubtitle() -> String {
        let summary = GeminiUsageTracker.shared.summary()
        guard summary.requestCount > 0 else { return "No requests yet" }
        var text = "\(summary.requestCount) requests · \(summary.totalTokens) tokens"
        if let cost = summary.totalCostUSD {
            text += " · \(GeminiCostFormatter.string(from: cost))\(summary.hasUnpricedRecords ? "+" : "")"
        }
        return text
    }

    private func makeEmptyLabel() -> UILabel {
        let label = UILabel()
        label.text = "Nothing saved yet.\n\nAfter Speak finishes, tap Save in the sentences toolbar to store audio and sentence timing."
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        label.numberOfLines = 0
        return label
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    // MARK: - Navigation destinations

    private func handleSelection(_ item: Item) {
        switch item {
        case .resource(let row):
            handleResourceSelection(row)

        case .savedGeneration(let id, _, _):
            onSelect?(id)

        case .appTokenizer:
            presentAppTokenizerPicker()

        case .tokenizerLab:
            navigationController?.pushViewController(TokenizerLabViewController(), animated: true)

        case .contextualGlossBackend:
            presentContextualGlossBackendPicker()

        case .aiUsageSummary:
            navigationController?.pushViewController(GeminiUsageHistoryViewController(), animated: true)

        case .soundsEnabled:
            break

        case .debugDestination(let row):
            handleDebugSelection(row)
        }
    }

    private func handleResourceSelection(_ row: ResourceRow) {
        switch row {
        case .kana:
            let kana = KanaLearningFlowExperimentViewController()
            kana.title = row.title
            navigationController?.pushViewController(kana, animated: true)
        case .grammar:
            let grammar = GrammarLearningFlowViewController()
            grammar.title = row.title
            navigationController?.pushViewController(grammar, animated: true)
        case .cmsLessons:
            navigationController?.pushViewController(CMSLessonsViewController(), animated: true)
        }
    }

    private func handleDebugSelection(_ row: DebugSettingsRow) {
        switch row {
        case .textToSpeech:
            navigationController?.pushViewController(
                TextToSpeechExperimentViewController(),
                animated: true
            )
        case .kanaLearningFlow:
            navigationController?.pushViewController(
                KanaLearningFlowExperimentViewController(),
                animated: true
            )
        case .kanaProgressPath:
            navigationController?.pushViewController(KanaProgressPathViewController(), animated: true)
        case .kanaProgressGrid:
            navigationController?.pushViewController(KanaProgressGridExperimentViewController(), animated: true)
        case .waterfallGrid:
            navigationController?.pushViewController(
                WaterfallCollectionExperimentViewController(),
                animated: true
            )
        case .lessonWaterfallGrid:
            navigationController?.pushViewController(
                LessonWaterfallGridExperimentViewController(),
                animated: true
            )
        case .sentenceScrub:
            let scrub = SentenceScrubExperimentViewController()
            navigationController?.pushViewController(scrub, animated: true)
        case .languageProgressSnake:
            let snake = LanguageProgressSnakeExperimentViewController()
            navigationController?.pushViewController(snake, animated: true)
        case .hiraganaChart:
            let chart = HiraganaChartViewController()
            navigationController?.pushViewController(chart, animated: true)
        case .katakanaChart:
            let chart = KatakanaChartViewController()
            navigationController?.pushViewController(chart, animated: true)
        case .flashcards:
            let flashcards = FlashcardExperimentViewController()
            navigationController?.pushViewController(flashcards, animated: true)
        case .kanaSpelling:
            presentKanaSpellingFlow()
        case .kanaListenSpelling:
            presentKanaListenSpellingFlow()
        case .kanaSoundMatch:
            presentKanaSoundMatchFlow()
        case .kanaPairMatch:
            navigationController?.pushViewController(
                KanaPairMatchExperimentViewController(),
                animated: true
            )
        case .kanaSoundMatchBounce:
            navigationController?.pushViewController(
                KanaSoundMatchBounceExperimentViewController(),
                animated: true
            )
        case .kanaLessonComplete:
            navigationController?.pushViewController(
                KanaLessonCompleteExperimentViewController(),
                animated: true
            )
        case .kanaLessonEncouragementBreak:
            presentKanaLessonEncouragementBreakFlow()
        case .emojiStickers:
            let stickers = EmojiStickerExperimentViewController()
            navigationController?.pushViewController(stickers, animated: true)
        case .feedbackSounds:
            navigationController?.pushViewController(
                ExperimentFeedbackSoundDebugViewController(),
                animated: true
            )
        case .vocabSpeaking:
            presentVocabSpeakingFlow()
        case .realtimeTutor:
            let tutor = RealtimeTutorViewController()
            navigationController?.pushViewController(tutor, animated: true)
        case .tutorConversations:
            navigationController?.pushViewController(TutorConversationsViewController(), animated: true)
        case .characterSpeaking:
            navigationController?.pushViewController(
                CharacterSpeakingExperimentViewController(),
                animated: true
            )
        case .speechProfileOverlay:
            navigationController?.pushViewController(
                SpeechProfileOverlayExperimentViewController(),
                animated: true
            )
        case .glassProgressVoiceOverlay:
            navigationController?.pushViewController(
                GlassProgressVoiceOverlayExperimentViewController(),
                animated: true
            )
        case .glassNotchShelf:
            navigationController?.pushViewController(
                GlassNotchShelfExperimentViewController(),
                animated: true
            )
        case .dialogueExperimentHarness:
            navigationController?.pushViewController(
                DialogueExperimentHarnessViewController(),
                animated: true
            )
        case .dialogueNestedPaging:
            let dialogueVC: DialogueNestedPagingExperimentViewController
            if let collection = DialogueScenarioCollectionCatalog.trainStation {
                dialogueVC = DialogueNestedPagingExperimentViewController(collection: collection)
            } else {
                dialogueVC = DialogueNestedPagingExperimentViewController()
            }
            navigationController?.pushViewController(
                dialogueVC,
                animated: true
            )
        case .dialogueBubbleUnderglow:
            navigationController?.pushViewController(
                DialogueBubbleUnderglowExperimentViewController(),
                animated: true
            )
        }
    }

    private func presentKanaSpellingFlow() {
        presentProgressiveFlow(
            ProgressiveContainerCoordinator(kanaSpellingWords: KanaSpellingWordBank.words)
        )
    }

    private func presentKanaListenSpellingFlow() {
        presentProgressiveFlow(
            ProgressiveContainerCoordinator(kanaListenSpellingWords: KanaSpellingWordBank.words)
        )
    }

    private func presentKanaSoundMatchFlow() {
        presentProgressiveFlow(
            ProgressiveContainerCoordinator(kanaSoundMatchRounds: KanaSoundMatchRoundBank.rounds)
        )
    }

    private func presentVocabSpeakingFlow() {
        presentProgressiveFlow(
            ProgressiveContainerCoordinator(vocabSpeakingPrompts: VocabSpeakingBank.prompts)
        )
    }

    private func presentKanaLessonEncouragementBreakFlow() {
        let coordinator = ProgressiveContainerCoordinator(
            steps: [KanaLessonEncouragementExperimentPreview.makeStep()]
        )
        coordinator.setLivesVisible(true)
        coordinator.updateLives(KanaLessonSessionMetrics.maxLives)
        presentProgressiveFlow(coordinator)
    }

    private func presentProgressiveFlow(_ coordinator: ProgressiveContainerCoordinator) {
        coordinator.delegate = self
        progressiveContainerCoordinator = coordinator

        let container = coordinator.start()
        container.modalPresentationStyle = .fullScreen
        present(container, animated: true)
    }

    private func presentAppTokenizerPicker() {
        let sheet = UIAlertController(
            title: "App tokenizer",
            message: "Used for sentence scrub and other tokenized Japanese UI.",
            preferredStyle: .actionSheet
        )
        let current = JapaneseTokenizerBackend.preferred
        for backend in JapaneseTokenizerBackend.allCases {
            let title = backend == current ? "✓ \(backend.displayName)" : backend.displayName
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                JapaneseTokenizerBackend.preferred = backend
                self?.applySnapshot()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController,
           let indexPath = indexPathForAppTokenizerRow(),
           let cell = collectionView.cellForItem(at: indexPath) {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }
        present(sheet, animated: true)
    }

    private func indexPathForAppTokenizerRow() -> IndexPath? {
        dataSource.snapshot().itemIdentifiers(inSection: .tokenizerTools).firstIndex { item in
            if case .appTokenizer = item { return true }
            return false
        }.map { IndexPath(row: $0, section: Section.tokenizerTools.rawValue) }
    }

    private func presentContextualGlossBackendPicker() {
        let sheet = UIAlertController(
            title: "Contextual insights",
            message: "How \"in this sentence\" explanations are generated when scrubbing or looking up a word.",
            preferredStyle: .actionSheet
        )
        let current = ContextualGlossBackend.preferred
        for backend in ContextualGlossBackend.allCases {
            let title = backend == current ? "✓ \(backend.displayName)" : backend.displayName
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                ContextualGlossBackend.preferred = backend
                self?.applySnapshot()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController,
           let indexPath = indexPathForContextualGlossBackendRow(),
           let cell = collectionView.cellForItem(at: indexPath) {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }
        present(sheet, animated: true)
    }

    private func indexPathForContextualGlossBackendRow() -> IndexPath? {
        dataSource.snapshot().itemIdentifiers(inSection: .tokenizerTools).firstIndex { item in
            if case .contextualGlossBackend = item { return true }
            return false
        }.map { IndexPath(row: $0, section: Section.tokenizerTools.rawValue) }
    }
}

extension SavedGenerationsViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        handleSelection(item)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        trailingSwipeActionsConfigurationForItemAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case .savedGeneration(let url, _, _) = item else { return nil }

        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            guard let self else {
                done(false)
                return
            }
            do {
                try self.store.deleteEntry(at: url)
                self.reloadEntries()
                done(true)
            } catch {
                done(false)
            }
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

extension SavedGenerationsViewController: ProgressiveContainerCoordinatorDelegate {
    func progressiveContainerCoordinatorDidFinish(_ coordinator: ProgressiveContainerCoordinator) {
        dismiss(animated: true)
        progressiveContainerCoordinator = nil
    }

    func progressiveContainerCoordinatorDidCancel(_ coordinator: ProgressiveContainerCoordinator) {
        dismiss(animated: true)
        progressiveContainerCoordinator = nil
    }
}
