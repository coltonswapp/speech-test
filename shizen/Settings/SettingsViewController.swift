//
//  SettingsViewController.swift
//  shizen
//
//  Settings menu. Debug tools live behind their own list screens.
//

import StoreKit
import UIKit

final class SettingsViewController: UIViewController {

    private static let websiteURL = URL(string: "https://shizenapp.com")!

    private var progressiveContainerCoordinator: ProgressiveContainerCoordinator?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    private nonisolated enum Section: String, Hashable, Sendable, CaseIterable {
        case account = "Account"
        case general = "General"
        case learning = "Learning"
        case support = "Support"
        case debug = "Debug"
    }

    private nonisolated enum LearningRow: Int, CaseIterable, Hashable, Sendable {
        case kana
        case grammar

        var title: String {
            switch self {
            case .kana: return "Kana"
            case .grammar: return "Grammar"
            }
        }

        var subtitle: String {
            switch self {
            case .kana: return "Hiragana and katakana charts, lessons"
            case .grammar: return "Grammar points and checkpoints"
            }
        }

        var symbolName: String {
            switch self {
            case .kana: return "textformat.characters"
            case .grammar: return "text.book.closed"
            }
        }
    }

    private nonisolated enum DebugLink: Int, CaseIterable, Hashable, Sendable {
        case aiUsage
        case tokenization
        case kana
        case lessons
        case dialogue
        case speaking
        case study
        case playground

        var title: String {
            switch self {
            case .aiUsage: return "AI usage"
            case .tokenization: return "Tokenization"
            case .kana: return "Kana"
            case .lessons: return "Lessons"
            case .dialogue: return "Dialogue"
            case .speaking: return "Speaking"
            case .study: return "Study"
            case .playground: return "Playground"
            }
        }

        var symbolName: String {
            switch self {
            case .aiUsage: return "chart.bar.doc.horizontal"
            case .tokenization: return "character.book.closed"
            case .kana: return "textformat.characters"
            case .lessons: return "rectangle.grid.2x2"
            case .dialogue: return "bubble.left.and.bubble.right"
            case .speaking: return "waveform"
            case .study: return "books.vertical"
            case .playground: return "sparkles"
            }
        }
    }

    private nonisolated enum Item: Hashable, Sendable {
        case account(title: String, subtitle: String, isSignedIn: Bool)
        case sounds
        case permissions
        case clearAudioCache(subtitle: String)
        case learning(LearningRow)
        case rateApp
        case website
        case debugLink(DebugLink, subtitle: String)
    }

    private nonisolated enum DebugDestination: Int, CaseIterable, Hashable, Sendable {
        case onboarding
        case journeyOnboarding
        case textToSpeech
        case kanaLearningFlow
        case kanaProgressPath
        case kanaProgressGrid
        case lessonWaterfallGrid
        case languageProgressSnake
        case languageProgressSnakeLeft
        case hiraganaChart
        case katakanaChart
        case flashcards
        case savedVocabulary
        case lemmaResolution
        case kanaSpelling
        case kanaListenSpelling
        case kanaSoundMatch
        case kanaPairMatch
        case kanaLessonComplete
        case kanaLessonEncouragementBreak
        case emojiStickers
        case explosions
        case feedbackSounds
        case vocabSpeaking
        case realtimeTutor
        case tutorConversations
        case characterSpeaking
        case speechProfileOverlay
        case glassProgressVoiceOverlay
        case dialogueExperimentHarness
        case kanjiDecomposition
        case kanjiSpotlight
        case swiftUIShaders
        case registerLadder
        case verbCombo
        case dialogueContentRecording
        case stageLayouts
        case pillField
        case spanHighlight

        var title: String {
            switch self {
            case .onboarding: return "Auth + onboarding"
            case .journeyOnboarding: return "Journey onboarding"
            case .textToSpeech: return "Text to Speech"
            case .kanaLearningFlow: return "Kana learning flow"
            case .kanaProgressPath: return "Kana progress path"
            case .kanaProgressGrid: return "Kana progress grid"
            case .lessonWaterfallGrid: return "Lesson waterfall grid"
            case .languageProgressSnake: return "Lesson path (sine)"
            case .languageProgressSnakeLeft: return "Lesson path (sine left)"
            case .hiraganaChart: return "Hiragana chart"
            case .katakanaChart: return "Katakana chart"
            case .flashcards: return "Flashcards"
            case .savedVocabulary: return "Saved vocabulary"
            case .lemmaResolution: return "Lemma resolution"
            case .kanaSpelling: return "Kana spelling"
            case .kanaListenSpelling: return "Listen & spell"
            case .kanaSoundMatch: return "Kana → sound"
            case .kanaPairMatch: return "Kana pair match"
            case .kanaLessonComplete: return "Lesson complete"
            case .kanaLessonEncouragementBreak: return "Streak break screen"
            case .emojiStickers: return "Emoji stickers"
            case .explosions: return "Explosions"
            case .feedbackSounds: return "Feedback sounds"
            case .vocabSpeaking: return "Vocab speaking"
            case .realtimeTutor: return "Realtime tutor"
            case .tutorConversations: return "Tutor conversations"
            case .characterSpeaking: return "Speaking meters"
            case .speechProfileOverlay: return "Speech profile overlay"
            case .glassProgressVoiceOverlay: return "Glass progress + voice"
            case .dialogueExperimentHarness: return "Dialogue lyrics harness"
            case .kanjiDecomposition: return "Kanji decomposition"
            case .kanjiSpotlight: return "Kanji spotlight"
            case .swiftUIShaders: return "SwiftUI shaders"
            case .registerLadder: return "Register ladder"
            case .verbCombo: return "Verb combinations"
            case .dialogueContentRecording: return "Dialogue Replay"
            case .stageLayouts: return "Stage layouts"
            case .pillField: return "Pill field"
            case .spanHighlight: return "Multi-select highlight"
            }
        }

        var subtitle: String {
            switch self {
            case .onboarding: return "Landing stubs · survey / slider / listening quiz · placeholder demos"
            case .journeyOnboarding: return "Same landing · questions first · ear test · trial · auth at the end"
            case .textToSpeech: return "Stream OpenAI TTS · sentence chunks · lyrics"
            case .kanaLearningFlow: return "Progress tiles · hiragana & katakana lessons · SRS"
            case .kanaProgressPath: return "Row-by-row hiragana lessons · SRS · chart"
            case .kanaProgressGrid: return "Hiragana & katakana heatmaps · 92 squares · size slider"
            case .lessonWaterfallGrid: return "Testing waterfall grid style lesson screen"
            case .languageProgressSnake: return "Glass stepping stones · sine-wave path · live tuner"
            case .languageProgressSnakeLeft: return "Stones in the left 40% · titles on the right · card covers on select"
            case .hiraganaChart: return "Manual-layout gojūon reference"
            case .katakanaChart: return "Manual-layout gojūon reference"
            case .flashcards: return "Swipe right · know it / left · review"
            case .savedVocabulary: return "Words saved from sentence scrub and the dictionary"
            case .lemmaResolution: return "Verb forms → dictionary headword · romaji · regression check"
            case .kanaSpelling: return "Tap tiles to spell the target word"
            case .kanaListenSpelling: return "Hear the word, then spell it in kana"
            case .kanaSoundMatch: return "6 steps · hiragana ↔ romaji matching"
            case .kanaPairMatch: return "Tap to match · 4 pairs · kana ↔ romaji"
            case .kanaLessonComplete: return "Preview summary · entry animation & encouragement"
            case .kanaLessonEncouragementBreak: return "Mid-lesson combo break · notch audio · header slides away"
            case .emojiStickers: return "Die-cut white halo · pick preset or type"
            case .explosions: return "Tap to burst · pick emojis · size presets"
            case .feedbackSounds: return "Play success chimes and incorrect dong"
            case .vocabSpeaking: return "3 steps · speak the word with the mic"
            case .realtimeTutor: return "Speech-to-speech Japanese tutor · gpt-realtime-2"
            case .tutorConversations: return "Saved tutor transcripts"
            case .characterSpeaking: return "Live meters · encouragement clips"
            case .speechProfileOverlay: return "Liquid-glass capsule · drops in while audio plays"
            case .glassProgressVoiceOverlay: return "Progress chrome in glass container · toggle voice overlay"
            case .dialogueExperimentHarness: return "Scenario audio · UIMenu clip switch · alignment QA"
            case .kanjiDecomposition: return "Full or 3-slide compound breakdown · export cards"
            case .kanjiSpotlight: return "One kanji · curated compounds & verbs · export cards"
            case .swiftUIShaders: return "Kris Puckett Metal shaders · playground"
            case .registerLadder: return "One sentence, 3 registers · Gemini · export cards"
            case .verbCombo: return "5 stills · hook, rule, 3 examples · Gemini · export cards"
            case .dialogueContentRecording: return "TikTok stage · conversation, two-pass, or quiz"
            case .stageLayouts: return "Defined onboarding layouts · title rises in · assets shift"
            case .pillField: return "Study-method capsules · size, depth, blur, haptics"
            case .spanHighlight: return "Fill, band color, height, and corner radius"
            }
        }

        var symbolName: String {
            switch self {
            case .onboarding: return "person.crop.circle.badge.checkmark"
            case .journeyOnboarding: return "door.left.hand.open"
            case .textToSpeech: return "waveform"
            case .kanaLearningFlow: return "square.grid.2x2"
            case .kanaProgressPath: return "point.topleft.down.curvedto.point.bottomright.up"
            case .kanaProgressGrid: return "square.grid.3x3.fill"
            case .lessonWaterfallGrid: return "rectangle.grid.2x2.fill"
            case .languageProgressSnake: return "point.3.connected.trianglepath.dotted"
            case .languageProgressSnakeLeft: return "text.alignleft"
            case .hiraganaChart: return "textformat.characters"
            case .katakanaChart: return "textformat.characters.dottedunderline"
            case .flashcards: return "rectangle.stack"
            case .savedVocabulary: return "folder.badge.plus"
            case .lemmaResolution: return "text.badge.checkmark"
            case .kanaSpelling: return "character.cursor.ibeam"
            case .kanaListenSpelling: return "ear"
            case .kanaSoundMatch: return "speaker.wave.2"
            case .kanaPairMatch: return "square.on.square"
            case .kanaLessonComplete: return "checkmark.seal"
            case .kanaLessonEncouragementBreak: return "flame"
            case .emojiStickers: return "face.smiling"
            case .explosions: return "sparkles"
            case .feedbackSounds: return "speaker.wave.3"
            case .vocabSpeaking: return "mic"
            case .realtimeTutor: return "person.wave.2"
            case .tutorConversations: return "bubble.left.and.bubble.right"
            case .characterSpeaking: return "person.bust"
            case .speechProfileOverlay: return "capsule.portrait"
            case .glassProgressVoiceOverlay: return "chart.bar.doc.horizontal"
            case .dialogueExperimentHarness: return "waveform.path"
            case .kanjiDecomposition: return "puzzlepiece.extension"
            case .kanjiSpotlight: return "lightbulb"
            case .swiftUIShaders: return "sparkles"
            case .registerLadder: return "text.badge.star"
            case .verbCombo: return "plus.forwardslash.minus"
            case .dialogueContentRecording: return "video"
            case .stageLayouts: return "square.stack.3d.up"
            case .pillField: return "capsule"
            case .spanHighlight: return "highlighter"
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemGroupedBackground
        configureCollectionView()
        configureDataSource()
        applySnapshot()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applySnapshot()
    }

    // MARK: - Collection view

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] _, environment in
            self?.listSection(environment: environment)
                ?? Self.plainListSection(environment: environment)
        }

        let footerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(44)
        )
        let footer = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: footerSize,
            elementKind: UICollectionView.elementKindSectionFooter,
            alignment: .bottom
        )
        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.boundarySupplementaryItems = [footer]
        layout.configuration = config

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.delegate = self
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func listSection(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        var listConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        listConfiguration.headerMode = .supplementary
        let section = NSCollectionLayoutSection.list(
            using: listConfiguration,
            layoutEnvironment: environment
        )
        let headerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(32)
        )
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize,
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
        section.boundarySupplementaryItems = [header]
        return section
    }

    private static func plainListSection(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let listConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        return NSCollectionLayoutSection.list(using: listConfiguration, layoutEnvironment: environment)
    }

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> {
            [weak self] cell, _, item in
            self?.configure(cell: cell, for: item)
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<SettingsSectionHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            guard let section = self?.dataSource.sectionIdentifier(for: indexPath.section) else { return }
            header.configure(title: section.rawValue)
        }

        let footerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { footer, _, _ in
            var content = footer.defaultContentConfiguration()
            content.text = Self.versionFooterText()
            content.textProperties.alignment = .center
            content.textProperties.font = .preferredFont(forTextStyle: .footnote)
            content.textProperties.color = .secondaryLabel
            content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 24, trailing: 16)
            footer.contentConfiguration = content
            footer.backgroundConfiguration = .clear()
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }

        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            switch kind {
            case UICollectionView.elementKindSectionHeader:
                return collectionView.dequeueConfiguredReusableSupplementary(
                    using: headerRegistration,
                    for: indexPath
                )
            case UICollectionView.elementKindSectionFooter:
                return collectionView.dequeueConfiguredReusableSupplementary(
                    using: footerRegistration,
                    for: indexPath
                )
            default:
                return nil
            }
        }
    }

    private func configure(cell: UICollectionViewListCell, for item: Item) {
        switch item {
        case .account(let title, let subtitle, _):
            SettingsMenuStyle.apply(
                to: cell,
                title: title,
                subtitle: subtitle,
                symbolName: "person.crop.circle",
                accessories: [.disclosureIndicator()]
            )

        case .sounds:
            SettingsMenuStyle.apply(
                to: cell,
                title: "Sounds",
                subtitle: "Success chimes and incorrect feedback",
                symbolName: "speaker.wave.2",
                accessories: [soundsSwitchAccessory()]
            )

        case .permissions:
            SettingsMenuStyle.apply(
                to: cell,
                title: "Permissions",
                subtitle: "Microphone and speech recognition",
                symbolName: "hand.raised",
                accessories: [.disclosureIndicator()]
            )

        case .clearAudioCache(let subtitle):
            SettingsMenuStyle.apply(
                to: cell,
                title: "Clear Audio Cache",
                subtitle: subtitle,
                symbolName: "arrow.clockwise",
                accessories: [.disclosureIndicator()]
            )

        case .learning(let row):
            SettingsMenuStyle.apply(
                to: cell,
                title: row.title,
                subtitle: row.subtitle,
                symbolName: row.symbolName,
                accessories: [.disclosureIndicator()]
            )

        case .rateApp:
            SettingsMenuStyle.apply(
                to: cell,
                title: "Rate App",
                subtitle: nil,
                symbolName: "star",
                accessories: [.disclosureIndicator()]
            )

        case .website:
            SettingsMenuStyle.apply(
                to: cell,
                title: "Website",
                subtitle: "shizenapp.com",
                symbolName: "safari",
                accessories: [.disclosureIndicator()]
            )

        case .debugLink(let link, let subtitle):
            SettingsMenuStyle.apply(
                to: cell,
                title: link.title,
                subtitle: subtitle,
                symbolName: link.symbolName,
                accessories: [.disclosureIndicator()]
            )
        }
    }

    private func soundsSwitchAccessory() -> UICellAccessory {
        let toggle = UISwitch()
        toggle.onTintColor = Colors.brandYellow
        toggle.isOn = ExperimentSettings.soundsEnabled
        toggle.addAction(UIAction { action in
            guard let toggle = action.sender as? UISwitch else { return }
            ExperimentSettings.soundsEnabled = toggle.isOn
        }, for: .valueChanged)
        return .customView(configuration: .init(customView: toggle, placement: .trailing()))
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        var sections: [Section] = [.account, .general, .learning, .support]
        #if DEBUG
        sections.append(.debug)
        #endif
        snapshot.appendSections(sections)

        let account = AuthService.shared.account
        snapshot.appendItems(
            [
                .account(
                    title: account.title,
                    subtitle: account.subtitle,
                    isSignedIn: account.isSignedIn
                ),
            ],
            toSection: .account
        )
        snapshot.appendItems(
            [
                .sounds,
                .permissions,
                .clearAudioCache(subtitle: audioCacheSubtitle()),
            ],
            toSection: .general
        )
        snapshot.appendItems(LearningRow.allCases.map(Item.learning), toSection: .learning)
        snapshot.appendItems([.rateApp, .website], toSection: .support)

        #if DEBUG
        snapshot.appendItems(
            DebugLink.allCases.map { link in
                Item.debugLink(link, subtitle: debugLinkSubtitle(link))
            },
            toSection: .debug
        )
        #endif

        dataSource.apply(snapshot, animatingDifferences: view.window != nil)
    }

    private func debugLinkSubtitle(_ link: DebugLink) -> String {
        switch link {
        case .aiUsage:
            return aiUsageSubtitle()
        case .tokenization:
            return tokenizerSubtitle()
        case .kana:
            return "Charts, lessons, and drills"
        case .lessons:
            return "CMS lessons and path layouts"
        case .dialogue:
            return "Replay, harness, and register"
        case .speaking:
            return "Tutor, meters, and speech"
        case .study:
            return "Flashcards, vocab, and kanji"
        case .playground:
            return "Onboarding, stage layouts, and effects"
        }
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
            return "\(current.displayName) · sign in required, insights hidden"
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

    private func audioCacheSubtitle() -> String {
        let count = RemoteAudioCache.cachedFileCount()
        if count == 0 {
            return "No cached lesson audio"
        }
        let clipLabel = count == 1 ? "clip" : "clips"
        return "\(count) cached \(clipLabel) · re-downloads on next play"
    }

    private static func versionFooterText() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        if version.isEmpty, build.isEmpty { return "Shizen" }
        if build.isEmpty { return "Shizen \(version)" }
        return "Shizen \(version) (\(build))"
    }

    // MARK: - Debug lists

    private func pushDetailList(title: String, makeItems: @escaping () -> [SettingsMenuItem]) {
        let list = SettingsDetailListViewController(title: title, makeItems: makeItems)
        list.onSelect = { [weak self] item, source in
            self?.handleMenuItem(item, sourceView: source)
        }
        navigationController?.pushViewController(list, animated: true)
    }

    private func openDebugLink(_ link: DebugLink) {
        switch link {
        case .aiUsage:
            navigationController?.pushViewController(GeminiUsageHistoryViewController(), animated: true)
        case .tokenization:
            pushDetailList(title: link.title) { [weak self] in
                self?.tokenizationItems() ?? []
            }
        case .kana:
            pushDetailList(title: link.title) { [weak self] in
                self?.debugItems([
                    .kanaLearningFlow,
                    .kanaProgressPath,
                    .kanaProgressGrid,
                    .hiraganaChart,
                    .katakanaChart,
                    .kanaSpelling,
                    .kanaListenSpelling,
                    .kanaSoundMatch,
                    .kanaPairMatch,
                    .kanaLessonComplete,
                    .kanaLessonEncouragementBreak,
                ]) ?? []
            }
        case .lessons:
            pushDetailList(title: link.title) { [weak self] in
                guard let self else { return [] }
                return [self.cmsLessonsItem()] + self.debugItems([
                    .lessonWaterfallGrid,
                    .languageProgressSnake,
                    .languageProgressSnakeLeft,
                ])
            }
        case .dialogue:
            pushDetailList(title: link.title) { [weak self] in
                self?.debugItems([
                    .dialogueContentRecording,
                    .dialogueExperimentHarness,
                    .registerLadder,
                ]) ?? []
            }
        case .speaking:
            pushDetailList(title: link.title) { [weak self] in
                self?.debugItems([
                    .textToSpeech,
                    .vocabSpeaking,
                    .realtimeTutor,
                    .tutorConversations,
                    .characterSpeaking,
                    .speechProfileOverlay,
                    .glassProgressVoiceOverlay,
                ]) ?? []
            }
        case .study:
            pushDetailList(title: link.title) { [weak self] in
                self?.debugItems([
                    .flashcards,
                    .savedVocabulary,
                    .lemmaResolution,
                    .kanjiDecomposition,
                    .verbCombo,
                    .kanjiSpotlight,
                ]) ?? []
            }
        case .playground:
            pushDetailList(title: link.title) { [weak self] in
                self?.debugItems([
                    .onboarding,
                    .journeyOnboarding,
                    .stageLayouts,
                    .pillField,
                    .spanHighlight,
                    .emojiStickers,
                    .explosions,
                    .feedbackSounds,
                    .swiftUIShaders,
                ]) ?? []
            }
        }
    }

    private func tokenizationItems() -> [SettingsMenuItem] {
        [
            SettingsMenuItem(
                id: "app-tokenizer",
                title: "App tokenizer",
                subtitle: tokenizerSubtitle(),
                symbolName: "character.book.closed"
            ),
            SettingsMenuItem(
                id: "tokenizer-lab",
                title: "Tokenizer Lab",
                subtitle: "NL · MeCab · Foundation model · Gemini Flash · Gemini Flash Lite",
                symbolName: "flask"
            ),
            SettingsMenuItem(
                id: "contextual-gloss",
                title: "Contextual insights",
                subtitle: contextualGlossBackendSubtitle(),
                symbolName: "sparkles"
            ),
        ]
    }

    private func cmsLessonsItem() -> SettingsMenuItem {
        SettingsMenuItem(
            id: "cms-lessons",
            title: "CMS lessons",
            subtitle: "Waterfall grid · fetch published dialogue lessons",
            symbolName: "rectangle.grid.2x2"
        )
    }

    private func debugItems(_ rows: [DebugDestination]) -> [SettingsMenuItem] {
        rows.map { row in
            SettingsMenuItem(
                id: "debug-\(row.rawValue)",
                title: row.title,
                subtitle: row.subtitle,
                symbolName: row.symbolName
            )
        }
    }

    private func refreshAfterPreferenceChange() {
        applySnapshot()
        if let detail = navigationController?.topViewController as? SettingsDetailListViewController {
            detail.reload()
        }
    }

    // MARK: - Selection

    private func handleSelection(_ item: Item) {
        switch item {
        case .account(_, _, let isSignedIn):
            if isSignedIn {
                confirmLogOut()
            } else {
                let presenter = navigationController ?? self
                presenter.present(AuthLandingViewController.makeLoginSheet(), animated: true)
            }
        case .sounds:
            break
        case .permissions:
            openSystemSettings()
        case .clearAudioCache:
            presentClearAudioCacheConfirmation()
        case .learning(let row):
            openLearning(row)
        case .rateApp:
            requestAppReview()
        case .website:
            UIApplication.shared.open(Self.websiteURL)
        case .debugLink(let link, _):
            openDebugLink(link)
        }
    }

    private func handleMenuItem(_ item: SettingsMenuItem, sourceView: UIView) {
        switch item.id {
        case "app-tokenizer":
            presentAppTokenizerPicker(sourceView: sourceView)
        case "tokenizer-lab":
            navigationController?.pushViewController(TokenizerLabViewController(), animated: true)
        case "contextual-gloss":
            presentContextualGlossBackendPicker(sourceView: sourceView)
        case "cms-lessons":
            navigationController?.pushViewController(CMSLessonsViewController(), animated: true)
        default:
            guard item.id.hasPrefix("debug-"),
                  let raw = Int(item.id.dropFirst("debug-".count)),
                  let row = DebugDestination(rawValue: raw) else { return }
            handleDebugSelection(row)
        }
    }

    private func openLearning(_ row: LearningRow) {
        switch row {
        case .kana:
            let kana = KanaLearningFlowExperimentViewController()
            kana.title = row.title
            navigationController?.pushViewController(kana, animated: true)
        case .grammar:
            let grammar = GrammarLearningFlowViewController()
            grammar.title = row.title
            navigationController?.pushViewController(grammar, animated: true)
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func requestAppReview() {
        guard let scene = view.window?.windowScene else { return }
        AppStore.requestReview(in: scene)
    }

    private func confirmLogOut() {
        let alert = UIAlertController(
            title: "Log out?",
            message: "You can sign in again with Apple or Google.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Log Out", style: .destructive) { [weak self] _ in
            do {
                try AuthService.shared.signOut()
                self?.applySnapshot()
            } catch {
                let failure = UIAlertController(
                    title: "Couldn’t log out",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                failure.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(failure, animated: true)
            }
        })
        present(alert, animated: true)
    }

    private func presentClearAudioCacheConfirmation() {
        let count = RemoteAudioCache.cachedFileCount()
        let message: String
        if count == 0 {
            message = "There is no cached lesson audio on disk."
        } else {
            let clipLabel = count == 1 ? "clip" : "clips"
            message = "Remove \(count) cached \(clipLabel)? Lesson audio will be re-downloaded from the CDN the next time you play a scenario. Dialogue progress is not affected."
        }

        let alert = UIAlertController(
            title: "Clear audio cache?",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if count > 0 {
            alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
                self?.performClearAudioCache()
            })
        }
        present(alert, animated: true)
    }

    private func performClearAudioCache() {
        do {
            let removed = try RemoteAudioCache.clearAllCachedFiles()
            applySnapshot()
            let clipLabel = removed == 1 ? "clip" : "clips"
            let alert = UIAlertController(
                title: "Audio cache cleared",
                message: removed == 0
                    ? "There was nothing to remove."
                    : "Removed \(removed) cached \(clipLabel).",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        } catch {
            let alert = UIAlertController(
                title: "Couldn’t clear cache",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func pushLessonPath(style: LanguageProgressSnakeExperimentViewController.Style) {
        let snake = LanguageProgressSnakeExperimentViewController(style: style)
        snake.onStartLesson = { [weak self] lesson in
            guard lesson.state != .locked, let id = lesson.id else { return }
            let picker = LessonScenarioPickerViewController(
                collectionID: id,
                fallbackTitle: lesson.title
            )
            self?.navigationController?.pushViewController(picker, animated: true)
        }
        navigationController?.pushViewController(snake, animated: true)
    }

    private func handleDebugSelection(_ row: DebugDestination) {
        switch row {
        case .onboarding:
            presentOnboardingPlayground()
        case .journeyOnboarding:
            presentOnboardingPlayground(entry: .journey)
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
        case .lessonWaterfallGrid:
            navigationController?.pushViewController(
                LessonWaterfallGridExperimentViewController(),
                animated: true
            )
        case .languageProgressSnake:
            pushLessonPath(style: .sine)
        case .languageProgressSnakeLeft:
            pushLessonPath(style: .sineLeftAligned)
        case .hiraganaChart:
            navigationController?.pushViewController(HiraganaChartViewController(), animated: true)
        case .katakanaChart:
            navigationController?.pushViewController(KatakanaChartViewController(), animated: true)
        case .flashcards:
            navigationController?.pushViewController(FlashcardExperimentViewController(), animated: true)
        case .savedVocabulary:
            navigationController?.pushViewController(
                SavedVocabularyListViewController(folderID: SavedVocabularyStore.inboxID),
                animated: true
            )
        case .lemmaResolution:
            navigationController?.pushViewController(
                LemmaResolutionExperimentViewController(),
                animated: true
            )
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
        case .kanaLessonComplete:
            navigationController?.pushViewController(
                KanaLessonCompleteExperimentViewController(),
                animated: true
            )
        case .kanaLessonEncouragementBreak:
            presentKanaLessonEncouragementBreakFlow()
        case .emojiStickers:
            navigationController?.pushViewController(
                EmojiStickerExperimentViewController(),
                animated: true
            )
        case .explosions:
            navigationController?.pushViewController(
                ExplosionExperimentViewController(),
                animated: true
            )
        case .feedbackSounds:
            navigationController?.pushViewController(
                ExperimentFeedbackSoundDebugViewController(),
                animated: true
            )
        case .vocabSpeaking:
            presentVocabSpeakingFlow()
        case .realtimeTutor:
            navigationController?.pushViewController(RealtimeTutorViewController(), animated: true)
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
        case .dialogueExperimentHarness:
            navigationController?.pushViewController(
                DialogueExperimentHarnessViewController(),
                animated: true
            )
        case .kanjiDecomposition:
            navigationController?.pushViewController(
                KanjiDecompositionListViewController(),
                animated: true
            )
        case .kanjiSpotlight:
            navigationController?.pushViewController(
                KanjiSpotlightListViewController(),
                animated: true
            )
        case .swiftUIShaders:
            navigationController?.pushViewController(
                SwiftUIShadersPlaygroundViewController(),
                animated: true
            )
        case .dialogueContentRecording:
            navigationController?.pushViewController(
                DialogueContentListViewController(),
                animated: true
            )
        case .registerLadder:
            navigationController?.pushViewController(
                RegisterLadderPromptViewController(),
                animated: true
            )
        case .verbCombo:
            navigationController?.pushViewController(
                VerbComboPromptViewController(),
                animated: true
            )
        case .stageLayouts:
            let page = OnboardingStageLayoutExperimentViewController()
            page.modalPresentationStyle = .fullScreen
            present(page, animated: true)
        case .pillField:
            let page = StudyMethodFieldExperimentViewController()
            page.modalPresentationStyle = .fullScreen
            present(page, animated: true)
        case .spanHighlight:
            navigationController?.pushViewController(
                MultiSelectHighlightExperimentViewController(),
                animated: true
            )
        }
    }

    private func presentOnboardingPlayground(entry: AuthLandingViewController.Entry = .original) {
        let landing = AuthLandingViewController()
        landing.entry = entry
        landing.isPreviewMode = true
        let nav = UINavigationController(rootViewController: landing)
        nav.setNavigationBarHidden(true, animated: false)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
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
        (navigationController ?? self).present(container, animated: true)
    }

    private func presentAppTokenizerPicker(sourceView: UIView) {
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
                self?.refreshAfterPreferenceChange()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }
        let presenter = navigationController?.topViewController ?? self
        presenter.present(sheet, animated: true)
    }

    private func presentContextualGlossBackendPicker(sourceView: UIView) {
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
                self?.refreshAfterPreferenceChange()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }
        let presenter = navigationController?.topViewController ?? self
        presenter.present(sheet, animated: true)
    }
}

extension SettingsViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        handleSelection(item)
    }
}

extension SettingsViewController: ProgressiveContainerCoordinatorDelegate {
    func progressiveContainerCoordinatorDidFinish(_ coordinator: ProgressiveContainerCoordinator) {
        (navigationController ?? self).dismiss(animated: true)
        progressiveContainerCoordinator = nil
    }

    func progressiveContainerCoordinatorDidCancel(_ coordinator: ProgressiveContainerCoordinator) {
        (navigationController ?? self).dismiss(animated: true)
        progressiveContainerCoordinator = nil
    }
}
