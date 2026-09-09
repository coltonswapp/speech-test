//
//  WordDictionaryDetailView.swift
//  shizen
//
//  Reusable word detail: furigana header, romaji, speak control, kanji chips, JMdict definitions.
//

import InteractionKit
import UIKit

/// Scrollable content is the host's job; this view stacks word, kanji, and definition sections.
final class WordDictionaryDetailView: UIView {

    private let wordSpeaker = WordUtteranceSpeaker()
    private var speechText = ""

    private let contentStack = UIStackView()

    private let wordHeaderStack = UIStackView()
    private let wordContentStack = UIStackView()
    private let selectedWordLabel = FuriganaTranscriptLabel()
    private let romajiLabel = UILabel()
    private let dictionaryFormLabel = UILabel()
    private let wordActionsStack = UIStackView()
    private let speakWordButton = UIButton(type: .system)
    private let speakWordGlyphView = UIImageView()
    private let saveVocabularyButton = UIButton(type: .system)
    private let saveVocabularyGlyphView = UIImageView()
#if DEBUG
    private let kanjiDecompositionButton = UIButton(type: .system)
    private let kanjiDecompositionGlyphView = UIImageView()
#endif
    private let saveHaptic = UIImpactFeedbackGenerator(style: .light)
    private var saveDraft: SavedVocabularyItem?
    private var isShowingSaveConfirmation = false
    private var saveButtonHideTask: Task<Void, Never>?

    private let contextualCardContainer = UIView()
    private let contextualCardSurface = UIView()
    private let contextualSectionStack = UIStackView()
    private let contextualSectionTitle = UILabel()
    private let contextualLoadingRow = UIStackView()
    private let contextualLoadingSpinner = NNLoadingSpinner(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
    private let contextualLoadingLabel = UILabel()
    private let contextualMeaningLabel = UILabel()
    private let contextualGrammarLabel = UILabel()

    private var contextualGlossTask: Task<Void, Never>?
    private var contextualRequestID = UUID()

    private let dividerAfterWord = WordDictionaryDetailView.makeHairlineDivider()

    private let kanjiChipsScrollView = UIScrollView()
    private let kanjiChipsStack = UIStackView()
    private let kanjiSectionTitle = UILabel()
    private let kanjiSectionStack = UIStackView()

    private let dividerBeforeDefinitions = WordDictionaryDetailView.makeHairlineDivider()
    private let definitionsSectionTitle = UILabel()
    private let definitionStack = UIStackView()

    private let dividerBeforeCompounds = WordDictionaryDetailView.makeHairlineDivider()
    private let compoundsSectionTitle = UILabel()
    private let compoundsSectionStack = UIStackView()
    private let compoundStack = UIStackView()

    /// Invoked when the user taps a compound row; host re-presents detail for that expression.
    var onSelectCompound: ((String) -> Void)?

    /// Invoked when the user taps a kanji chip; host opens the kanji detail screen.
    var onSelectKanji: ((String) -> Void)?

#if DEBUG
    /// Invoked when the user taps the kanji decomposition shortcut beside Speak.
    var onRequestKanjiDecomposition: (() -> Void)?
#endif

    /// When false, the COMPOUNDS section is never built or shown (e.g. inline in the scrub experiment).
    var showsCompounds = true {
        didSet {
            guard showsCompounds != oldValue, !lastConfiguredSurface.isEmpty else { return }
            configure(surface: lastConfiguredSurface, sentence: lastConfiguredSentence)
        }
    }

    /// Supplies the contextual "in this sentence" gloss. Defaults to the user's persisted
    /// `ContextualGlossBackend.preferred` setting; hosts can inject a specific provider to override it.
    var contextualGlossProvider: ContextualGlossProviding = ContextualGlossBackend.preferred.provider

    private var lastConfiguredSurface = ""
    private var lastConfiguredSentence: String?

    private static let contextualCardContentInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    private static let contextualCardShadowBleed: CGFloat = 12

    private static let audioButtonSize: CGFloat = 56
    private static let audioGlyphColor = UIColor.systemYellow

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        observeSavedVocabularyChanges()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        observeSavedVocabularyChanges()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func configure(surface: String, sentence: String? = nil) {
        contextualGlossTask?.cancel()
        lastConfiguredSurface = surface
        lastConfiguredSentence = sentence

        guard !surface.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isHidden = true
            speechText = ""
            saveDraft = nil
            dictionaryFormLabel.isHidden = true
            contextualCardContainer.isHidden = true
            refreshSaveButton()
#if DEBUG
            kanjiDecompositionButton.isHidden = true
#endif
            return
        }

        isHidden = false
        let lookup = JMDictStore.shared.lookup(forSurface: surface, inSentence: sentence)
        let entries = lookup.entries
        let displayHeadword = lookup.dictionaryForm ?? surface

        let wordFont = selectedWordLabel.font ?? UIFont.preferredFont(forTextStyle: .largeTitle)
        JapaneseFuriganaBuilder.applyScrubDisplay(
            to: selectedWordLabel,
            attributed: JapaneseFuriganaBuilder.attributedString(
                for: displayHeadword,
                font: wordFont,
                textColor: .label
            ),
            contentInsets: UIEdgeInsets(
                top: JapaneseFuriganaBuilder.wordDetailRubyTopInset(for: wordFont),
                left: 0,
                bottom: 2,
                right: 0
            )
        )

        let primary = lookup.primaryEntry
        let showingLemmaAsHeadword = displayHeadword != surface
        let readingForRomaji: String
        let romaji: String
        if showingLemmaAsHeadword {
            let lemmaKana = (lookup.dictionaryFormReading ?? displayHeadword)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            readingForRomaji = JMDictStore.shared.kanaReadingForDisplay(
                surface: displayHeadword,
                matching: primary
            )
            romaji = HiraganaRomaji.romanize(readingForRomaji.isEmpty ? lemmaKana : readingForRomaji)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            readingForRomaji = JMDictStore.shared.kanaReadingForDisplay(surface: surface, matching: primary)
            romaji = JMDictStore.shared.romajiForDisplay(surface: surface, matching: primary)
        }
        romajiLabel.isHidden = romaji.isEmpty
        romajiLabel.text = romaji.isEmpty ? nil : romaji

        if let dictionaryForm = lookup.dictionaryForm, !showingLemmaAsHeadword {
            let reading = lookup.dictionaryFormReading ?? dictionaryForm
            let lemmaRomaji = HiraganaRomaji.romanize(reading)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if lemmaRomaji.isEmpty {
                dictionaryFormLabel.text = "Dictionary form: \(dictionaryForm)"
            } else {
                dictionaryFormLabel.text = "Dictionary form: \(dictionaryForm) · \(lemmaRomaji)"
            }
            dictionaryFormLabel.isHidden = false
        } else {
            dictionaryFormLabel.text = nil
            dictionaryFormLabel.isHidden = true
        }

        speechText = readingForRomaji.isEmpty ? surface.trimmingCharacters(in: .whitespacesAndNewlines) : readingForRomaji

        let gloss = primary.map { Self.primaryGloss(from: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        let trimmedSentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines)
        saveDraft = SavedVocabularyItem(
            id: UUID().uuidString,
            surface: surface.trimmingCharacters(in: .whitespacesAndNewlines),
            dictionaryForm: lookup.dictionaryForm,
            reading: readingForRomaji.isEmpty ? nil : readingForRomaji,
            gloss: gloss,
            sentence: (trimmedSentence?.isEmpty ?? true) ? nil : trimmedSentence,
            createdAt: Date()
        )
        refreshSaveButton()

        rebuildKanjiChips(surface: surface)
        rebuildCompoundContent(surface: surface)

        let willRequestContextualGloss = Self.shouldRequestContextualGloss(
            sentence: sentence,
            hasDictionaryMatch: !entries.isEmpty,
            providerAvailable: contextualGlossProvider.isAvailable
        )
        // When JMdict misses (compounds / set phrases), prefer the contextual card over
        // an empty DEFINITIONS section — fall back to the empty label if gloss fails.
        rebuildDefinitionContent(
            surface: surface,
            entries: entries,
            suppressEmptyState: willRequestContextualGloss
        )

        dividerAfterWord.isHidden = false
        definitionsSectionTitle.isHidden = entries.isEmpty && willRequestContextualGloss
        definitionStack.isHidden = entries.isEmpty && willRequestContextualGloss
        let showKanji = !kanjiChipsScrollView.isHidden
        kanjiSectionStack.isHidden = !showKanji
        dividerBeforeDefinitions.isHidden = !showKanji || definitionsSectionTitle.isHidden
        let showCompounds = !compoundStack.arrangedSubviews.isEmpty
        compoundsSectionStack.isHidden = !showCompounds
        dividerBeforeCompounds.isHidden = !showCompounds || definitionsSectionTitle.isHidden

        loadContextualGloss(
            surface: surface,
            sentence: sentence,
            lookup: lookup,
            primaryEntry: primary
        )

#if DEBUG
        updateKanjiDecompositionButton(for: entries)
#endif
    }

    private static func shouldRequestContextualGloss(
        sentence: String?,
        hasDictionaryMatch: Bool,
        providerAvailable: Bool
    ) -> Bool {
        guard providerAvailable else { return false }
        let trimmedSentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Sentence scrub / dialogue context: always explain the token in situ.
        if !trimmedSentence.isEmpty { return true }
        // Vocabulary highlights without a dialogue line: still ask when JMdict has no hit.
        return !hasDictionaryMatch
    }

    private func loadContextualGloss(
        surface: String,
        sentence: String?,
        lookup: JMDictLookupResult,
        primaryEntry: JMDictEntry?
    ) {
        let trimmedSentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasDictionaryMatch = !lookup.entries.isEmpty
        guard Self.shouldRequestContextualGloss(
            sentence: sentence,
            hasDictionaryMatch: hasDictionaryMatch,
            providerAvailable: contextualGlossProvider.isAvailable
        ) else {
            contextualCardContainer.isHidden = true
            return
        }

        // Providers require a non-empty sentence; for unmatched compounds with no
        // dialogue line, treat the surface itself as the span to explain.
        let contextSentence = trimmedSentence.isEmpty ? surface : trimmedSentence
        let hasBroaderSentence = !trimmedSentence.isEmpty && trimmedSentence != surface
        contextualSectionTitle.text = hasBroaderSentence ? "IN THIS SENTENCE" : "MEANING"

        let requestID = UUID()
        contextualRequestID = requestID

        let dictionaryGloss = primaryEntry
            .map { Self.primaryGloss(from: $0) }
            .flatMap { $0.isEmpty ? nil : $0 }

        let request = ContextualGlossRequest(
            sentence: contextSentence,
            surface: surface,
            dictionaryForm: lookup.dictionaryForm,
            dictionaryGloss: dictionaryGloss
        )

        let provider = contextualGlossProvider
        contextualGlossTask = Task { [weak self] in
            if let cached = await provider.cachedResult(for: request) {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.contextualRequestID == requestID else { return }
                    self.applyContextualGloss(cached)
                }
                return
            }

            await MainActor.run {
                guard let self, self.contextualRequestID == requestID else { return }
                self.showContextualGlossLoading()
            }

            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }

            do {
                let gloss = try await provider.explain(request)
                await MainActor.run {
                    guard let self, self.contextualRequestID == requestID else { return }
                    self.applyContextualGloss(gloss)
                }
            } catch {
                await MainActor.run {
                    guard let self, self.contextualRequestID == requestID else { return }
                    self.contextualCardContainer.isHidden = true
                    if !hasDictionaryMatch {
                        self.showDictionaryMissFallback()
                    }
                }
            }
        }
    }

    /// Restores the DEFINITIONS empty state when a no-match contextual gloss fails.
    private func showDictionaryMissFallback() {
        definitionsSectionTitle.isHidden = false
        definitionStack.isHidden = false
        dividerBeforeDefinitions.isHidden = kanjiSectionStack.isHidden
        rebuildDefinitionContent(surface: lastConfiguredSurface, entries: [], suppressEmptyState: false)
        setNeedsLayout()
    }

    private func showContextualGlossLoading() {
        contextualCardContainer.isHidden = false
        contextualLoadingRow.isHidden = false
        contextualMeaningLabel.isHidden = true
        contextualGrammarLabel.isHidden = true
        contextualMeaningLabel.text = nil
        contextualGrammarLabel.text = nil
        contextualLoadingSpinner.reset()
        contextualLoadingSpinner.isHidden = false
        contextualCardContainer.setNeedsLayout()
        contextualCardContainer.layoutIfNeeded()
    }

    private func applyContextualGloss(_ gloss: ContextualGlossResult) {
        contextualLoadingRow.isHidden = true
        contextualLoadingSpinner.isHidden = true
        contextualMeaningLabel.isHidden = false
        contextualMeaningLabel.text = gloss.meaning
        contextualMeaningLabel.textColor = .label

        let grammar = gloss.grammarNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if grammar.isEmpty {
            contextualGrammarLabel.text = nil
            contextualGrammarLabel.isHidden = true
        } else {
            contextualGrammarLabel.text = grammar
            contextualGrammarLabel.isHidden = false
        }
        contextualCardContainer.isHidden = false
        contextualCardContainer.setNeedsLayout()
        contextualCardContainer.layoutIfNeeded()
        setNeedsLayout()
    }

    private static func primaryGloss(from entry: JMDictEntry) -> String {
        let gloss = entry.glossary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gloss.isEmpty else { return "" }
        return gloss
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? gloss
    }

    // MARK: - Setup

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        wordHeaderStack.axis = .horizontal
        wordHeaderStack.alignment = .center
        wordHeaderStack.spacing = 16
        wordHeaderStack.distribution = .fill
        wordHeaderStack.clipsToBounds = false

        wordContentStack.axis = .vertical
        wordContentStack.alignment = .leading
        wordContentStack.spacing = 4
        wordContentStack.clipsToBounds = false
        wordContentStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        wordContentStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        wordHeaderStack.addArrangedSubview(wordContentStack)

        speakWordButton.setContentHuggingPriority(.required, for: .horizontal)
        speakWordButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        Self.configureGlassAudioButton(
            speakWordButton,
            glyphView: speakWordGlyphView,
            symbolName: "speaker.wave.2.fill",
            glyphPointSize: 22,
            accessibilityLabel: "Speak word"
        )
        speakWordButton.addTarget(self, action: #selector(speakWordTapped), for: .touchUpInside)

        wordActionsStack.axis = .horizontal
        wordActionsStack.alignment = .center
        wordActionsStack.spacing = 10
        wordActionsStack.setContentHuggingPriority(.required, for: .horizontal)
        wordActionsStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        wordActionsStack.addArrangedSubview(speakWordButton)

        saveVocabularyButton.setContentHuggingPriority(.required, for: .horizontal)
        saveVocabularyButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        Self.configureGlassAudioButton(
            saveVocabularyButton,
            glyphView: saveVocabularyGlyphView,
            symbolName: "folder.badge.plus",
            glyphPointSize: 20,
            accessibilityLabel: "Save word"
        )
        saveVocabularyButton.accessibilityHint = "Adds this word to a folder"
        saveVocabularyButton.addTarget(self, action: #selector(saveVocabularyTapped), for: .touchUpInside)
        saveHaptic.prepare()
        wordActionsStack.addArrangedSubview(saveVocabularyButton)

#if DEBUG
        kanjiDecompositionButton.setContentHuggingPriority(.required, for: .horizontal)
        kanjiDecompositionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        Self.configureGlassAudioButton(
            kanjiDecompositionButton,
            glyphView: kanjiDecompositionGlyphView,
            symbolName: "puzzlepiece.extension",
            glyphPointSize: 20,
            accessibilityLabel: "Kanji decomposition"
        )
        kanjiDecompositionButton.accessibilityHint = "Open kanji decomposition cards for this word"
        kanjiDecompositionButton.addTarget(self, action: #selector(kanjiDecompositionTapped), for: .touchUpInside)
        kanjiDecompositionButton.isHidden = true
        wordActionsStack.addArrangedSubview(kanjiDecompositionButton)
#endif
        wordHeaderStack.addArrangedSubview(wordActionsStack)

        let wordFont: UIFont = {
            let base = UIFont.preferredFont(forTextStyle: .largeTitle)
            if let d = base.fontDescriptor.withSymbolicTraits(.traitBold) {
                return UIFont(descriptor: d, size: 0)
            }
            return base
        }()

        selectedWordLabel.clipsToBounds = false
        selectedWordLabel.numberOfLines = 1
        selectedWordLabel.textAlignment = .natural
        selectedWordLabel.font = wordFont
        selectedWordLabel.textColor = .label

        romajiLabel.font = .preferredFont(forTextStyle: .subheadline)
        romajiLabel.textColor = .secondaryLabel
        romajiLabel.textAlignment = .natural
        romajiLabel.numberOfLines = 0

        dictionaryFormLabel.font = .preferredFont(forTextStyle: .subheadline)
        dictionaryFormLabel.textColor = .tertiaryLabel
        dictionaryFormLabel.textAlignment = .natural
        dictionaryFormLabel.numberOfLines = 0
        dictionaryFormLabel.isHidden = true

        wordContentStack.addArrangedSubview(selectedWordLabel)
        wordContentStack.addArrangedSubview(romajiLabel)
        wordContentStack.addArrangedSubview(dictionaryFormLabel)

        let sectionHeaderFont = UIFont.preferredFont(forTextStyle: .subheadline)

        contextualSectionTitle.text = "IN THIS SENTENCE"
        contextualSectionTitle.font = UIFont.preferredFont(forTextStyle: .caption1)
        contextualSectionTitle.textColor = .secondaryLabel

        let contextualMeaningFont: UIFont = {
            let base = UIFont.preferredFont(forTextStyle: .title3)
            if let d = base.fontDescriptor.withSymbolicTraits(.traitBold) {
                return UIFont(descriptor: d, size: 0)
            }
            return base
        }()
        contextualMeaningLabel.font = contextualMeaningFont
        contextualMeaningLabel.textColor = .label
        contextualMeaningLabel.textAlignment = .natural
        contextualMeaningLabel.numberOfLines = 0

        contextualGrammarLabel.font = .preferredFont(forTextStyle: .subheadline)
        contextualGrammarLabel.textColor = .secondaryLabel
        contextualGrammarLabel.textAlignment = .natural
        contextualGrammarLabel.numberOfLines = 0
        contextualGrammarLabel.isHidden = true

        contextualLoadingSpinner.configure(with: Self.audioGlyphColor)
        contextualLoadingSpinner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contextualLoadingSpinner.widthAnchor.constraint(equalToConstant: 24),
            contextualLoadingSpinner.heightAnchor.constraint(equalToConstant: 24),
        ])

        contextualLoadingLabel.text = "Analyzing…"
        contextualLoadingLabel.font = .preferredFont(forTextStyle: .subheadline)
        contextualLoadingLabel.textColor = .secondaryLabel
        contextualLoadingLabel.numberOfLines = 1

        contextualLoadingRow.axis = .horizontal
        contextualLoadingRow.alignment = .center
        contextualLoadingRow.spacing = 10
        contextualLoadingRow.isHidden = true
        contextualLoadingRow.addArrangedSubview(contextualLoadingSpinner)
        contextualLoadingRow.addArrangedSubview(contextualLoadingLabel)

        contextualSectionStack.axis = .vertical
        contextualSectionStack.alignment = .fill
        contextualSectionStack.spacing = 6
        contextualSectionStack.addArrangedSubview(contextualSectionTitle)
        contextualSectionStack.addArrangedSubview(contextualLoadingRow)
        contextualSectionStack.addArrangedSubview(contextualMeaningLabel)
        contextualSectionStack.addArrangedSubview(contextualGrammarLabel)

        contextualCardSurface.backgroundColor = .secondarySystemGroupedBackground
        contextualCardSurface.layer.cornerRadius = 14
        contextualCardSurface.layer.cornerCurve = .continuous
        contextualCardSurface.layer.shadowColor = UIColor.black.cgColor
        contextualCardSurface.layer.shadowOpacity = 0.14
        contextualCardSurface.layer.shadowRadius = 10
        contextualCardSurface.layer.shadowOffset = CGSize(width: 0, height: 4)
        contextualCardSurface.translatesAutoresizingMaskIntoConstraints = false

        contextualCardContainer.clipsToBounds = false
        contextualCardContainer.translatesAutoresizingMaskIntoConstraints = false
        contextualCardContainer.isHidden = true
        contextualCardContainer.addSubview(contextualCardSurface)
        contextualCardSurface.addSubview(contextualSectionStack)
        contextualSectionStack.translatesAutoresizingMaskIntoConstraints = false

        let insets = Self.contextualCardContentInsets
        let shadowBleed = Self.contextualCardShadowBleed
        NSLayoutConstraint.activate([
            contextualCardSurface.topAnchor.constraint(equalTo: contextualCardContainer.topAnchor),
            contextualCardSurface.leadingAnchor.constraint(equalTo: contextualCardContainer.leadingAnchor),
            contextualCardSurface.trailingAnchor.constraint(equalTo: contextualCardContainer.trailingAnchor),
            contextualCardSurface.bottomAnchor.constraint(
                equalTo: contextualCardContainer.bottomAnchor,
                constant: -shadowBleed
            ),

            contextualSectionStack.topAnchor.constraint(equalTo: contextualCardSurface.topAnchor, constant: insets.top),
            contextualSectionStack.leadingAnchor.constraint(equalTo: contextualCardSurface.leadingAnchor, constant: insets.left),
            contextualSectionStack.trailingAnchor.constraint(equalTo: contextualCardSurface.trailingAnchor, constant: -insets.right),
            contextualSectionStack.bottomAnchor.constraint(equalTo: contextualCardSurface.bottomAnchor, constant: -insets.bottom),
        ])

        kanjiChipsScrollView.translatesAutoresizingMaskIntoConstraints = false
        kanjiChipsScrollView.showsHorizontalScrollIndicator = false
        kanjiChipsScrollView.alwaysBounceHorizontal = true
        // Glass chips carry a drop shadow (masksToBounds = false); don't clip it vertically.
        kanjiChipsScrollView.clipsToBounds = false

        kanjiChipsStack.translatesAutoresizingMaskIntoConstraints = false
        kanjiChipsStack.axis = .horizontal
        kanjiChipsStack.spacing = 8
        kanjiChipsStack.alignment = .center

        kanjiChipsScrollView.addSubview(kanjiChipsStack)
        let chipsContent = kanjiChipsScrollView.contentLayoutGuide
        NSLayoutConstraint.activate([
            kanjiChipsStack.topAnchor.constraint(equalTo: chipsContent.topAnchor),
            kanjiChipsStack.leadingAnchor.constraint(equalTo: chipsContent.leadingAnchor),
            kanjiChipsStack.trailingAnchor.constraint(equalTo: chipsContent.trailingAnchor),
            kanjiChipsStack.bottomAnchor.constraint(equalTo: chipsContent.bottomAnchor),
            kanjiChipsScrollView.heightAnchor.constraint(equalTo: kanjiChipsStack.heightAnchor),
        ])

        kanjiSectionTitle.text = "KANJI"
        kanjiSectionTitle.font = sectionHeaderFont
        kanjiSectionTitle.textColor = .secondaryLabel

        kanjiSectionStack.axis = .vertical
        kanjiSectionStack.alignment = .fill
        kanjiSectionStack.spacing = 8
        kanjiSectionStack.addArrangedSubview(kanjiSectionTitle)
        kanjiSectionStack.addArrangedSubview(kanjiChipsScrollView)

        definitionsSectionTitle.text = "DEFINITIONS"
        definitionsSectionTitle.font = sectionHeaderFont
        definitionsSectionTitle.textColor = .secondaryLabel

        definitionStack.axis = .vertical
        definitionStack.alignment = .fill
        definitionStack.spacing = 12
        definitionStack.translatesAutoresizingMaskIntoConstraints = false

        compoundsSectionTitle.text = "COMPOUNDS"
        compoundsSectionTitle.font = sectionHeaderFont
        compoundsSectionTitle.textColor = .secondaryLabel

        compoundStack.axis = .vertical
        compoundStack.alignment = .fill
        compoundStack.spacing = 0

        compoundsSectionStack.axis = .vertical
        compoundsSectionStack.alignment = .fill
        compoundsSectionStack.spacing = 8
        compoundsSectionStack.addArrangedSubview(compoundsSectionTitle)
        compoundsSectionStack.addArrangedSubview(compoundStack)

        contentStack.addArrangedSubview(wordHeaderStack)
        contentStack.setCustomSpacing(16, after: wordHeaderStack)
        contentStack.addArrangedSubview(dividerAfterWord)
        contentStack.setCustomSpacing(16, after: dividerAfterWord)
        contentStack.addArrangedSubview(contextualCardContainer)
        contentStack.setCustomSpacing(16, after: contextualCardContainer)
        contentStack.addArrangedSubview(kanjiSectionStack)
        contentStack.setCustomSpacing(16, after: kanjiSectionStack)
        contentStack.addArrangedSubview(dividerBeforeDefinitions)
        contentStack.setCustomSpacing(16, after: dividerBeforeDefinitions)
        contentStack.addArrangedSubview(definitionsSectionTitle)
        contentStack.setCustomSpacing(8, after: definitionsSectionTitle)
        contentStack.addArrangedSubview(definitionStack)
        contentStack.setCustomSpacing(16, after: definitionStack)
        contentStack.addArrangedSubview(dividerBeforeCompounds)
        contentStack.setCustomSpacing(16, after: dividerBeforeCompounds)
        contentStack.addArrangedSubview(compoundsSectionStack)

        dividerAfterWord.isHidden = true
        kanjiSectionStack.isHidden = true
        dividerBeforeDefinitions.isHidden = true
        definitionsSectionTitle.isHidden = true
        dividerBeforeCompounds.isHidden = true
        compoundsSectionStack.isHidden = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        speakWordButton.bringSubviewToFront(speakWordGlyphView)
        saveVocabularyButton.bringSubviewToFront(saveVocabularyGlyphView)
#if DEBUG
        kanjiDecompositionButton.bringSubviewToFront(kanjiDecompositionGlyphView)
#endif
        if !contextualCardContainer.isHidden {
            contextualCardSurface.layer.shadowPath = UIBezierPath(
                roundedRect: contextualCardSurface.bounds,
                cornerRadius: contextualCardSurface.layer.cornerRadius
            ).cgPath
        }
    }

    // MARK: - Actions

    @objc private func speakWordTapped() {
        wordSpeaker.speak(speechText)
    }

    @objc private func saveVocabularyTapped() {
        let surface = lastConfiguredSurface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !surface.isEmpty, let draft = saveDraft, let presenter = nearestViewController() else { return }

        saveHaptic.impactOccurred()
        saveHaptic.prepare()

        let sheet = UIAlertController(
            title: "Save to folder",
            message: surface,
            preferredStyle: .actionSheet
        )
        for folder in SavedVocabularyStore.shared.folders() {
            let alreadyInFolder = SavedVocabularyStore.shared.contains(surface: surface, inFolderID: folder.id)
            let title = alreadyInFolder ? "\(folder.name) (added)" : folder.name
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.saveDraft(draft, toFolderID: folder.id)
            })
        }
        sheet.addAction(UIAlertAction(title: "New folder…", style: .default) { [weak self] _ in
            self?.promptNewFolder(for: draft)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = saveVocabularyButton
            popover.sourceRect = saveVocabularyButton.bounds
        }
        presenter.present(sheet, animated: true)
    }

    private func promptNewFolder(for draft: SavedVocabularyItem) {
        guard let presenter = nearestViewController() else { return }
        let alert = UIAlertController(title: "New folder", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Folder name"
            field.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            let name = alert.textFields?.first?.text ?? ""
            let folder = SavedVocabularyStore.shared.createFolder(name: name)
            self?.saveDraft(draft, toFolderID: folder.id)
        })
        presenter.present(alert, animated: true)
    }

    private func saveDraft(_ draft: SavedVocabularyItem, toFolderID folderID: String) {
        var item = draft
        item.id = UUID().uuidString
        item.createdAt = Date()
        SavedVocabularyStore.shared.save(item, toFolderID: folderID)
        refreshSaveButton(showConfirmation: true)
    }

    private func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }

    private func observeSavedVocabularyChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSavedVocabularyDidChange),
            name: SavedVocabularyStore.didChangeNotification,
            object: nil
        )
    }

    @objc private func handleSavedVocabularyDidChange() {
        guard !isShowingSaveConfirmation else { return }
        refreshSaveButton()
    }

    private func refreshSaveButton(showConfirmation: Bool = false) {
        let surface = lastConfiguredSurface.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSaved = !surface.isEmpty && SavedVocabularyStore.shared.contains(surface: surface)

        if showConfirmation, isSaved {
            showSaveConfirmationThenHide()
            return
        }

        saveButtonHideTask?.cancel()
        saveButtonHideTask = nil
        isShowingSaveConfirmation = false
        saveVocabularyButton.alpha = 1
        saveVocabularyButton.isUserInteractionEnabled = true
        saveVocabularyButton.isHidden = surface.isEmpty || isSaved
        Self.applyGlyph(
            saveVocabularyGlyphView,
            symbolName: "folder.badge.plus",
            tintColor: Self.audioGlyphColor,
            glyphPointSize: 20
        )
        saveVocabularyButton.accessibilityLabel = "Save word"
        saveVocabularyButton.accessibilityHint = "Adds this word to a folder"
    }

    private func showSaveConfirmationThenHide() {
        saveButtonHideTask?.cancel()
        isShowingSaveConfirmation = true
        saveVocabularyButton.alpha = 1
        saveVocabularyButton.isHidden = false
        saveVocabularyButton.isUserInteractionEnabled = false
        Self.applyGlyph(
            saveVocabularyGlyphView,
            symbolName: "checkmark",
            tintColor: .systemBlue,
            glyphPointSize: 20
        )
        saveVocabularyButton.accessibilityLabel = "Saved word"
        saveVocabularyButton.accessibilityHint = "Adds this word to a folder"

        saveButtonHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 850_000_000)
            guard let self, !Task.isCancelled, self.isShowingSaveConfirmation else { return }
            self.isShowingSaveConfirmation = false
            self.saveVocabularyButton.isHidden = true
            self.saveVocabularyButton.alpha = 1
            self.saveVocabularyButton.isUserInteractionEnabled = true
            Self.applyGlyph(
                self.saveVocabularyGlyphView,
                symbolName: "folder.badge.plus",
                tintColor: Self.audioGlyphColor,
                glyphPointSize: 20
            )
        }
    }

#if DEBUG
    @objc private func kanjiDecompositionTapped() {
        onRequestKanjiDecomposition?()
    }

    private func updateKanjiDecompositionButton(for entries: [JMDictEntry]) {
        let primary = entries.max { ($0.score ?? 0) < ($1.score ?? 0) } ?? entries.first
        let canDecompose = primary.map { KanjiDecompositionWord.make(from: $0) != nil } ?? false
        kanjiDecompositionButton.isHidden = !canDecompose
    }
#endif

    // MARK: - Content builders

    private func rebuildKanjiChips(surface: String) {
        kanjiChipsStack.arrangedSubviews.forEach {
            kanjiChipsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let items = KanjidicStore.shared.briefInfo(forKanjiIn: surface)
        guard !items.isEmpty else {
            kanjiChipsScrollView.isHidden = true
            return
        }

        kanjiChipsScrollView.isHidden = false
        let titleFont = UIFont.preferredFont(forTextStyle: .title2)
        let captionFont = UIFont.preferredFont(forTextStyle: .caption1)
        for item in items {
            let chip = GlassChipControl(
                title: item.character,
                subtitle: item.briefMeaning,
                titleFont: titleFont,
                subtitleFont: captionFont
            )
            let character = item.character
            chip.addAction(
                UIAction { [weak self] _ in self?.onSelectKanji?(character) },
                for: .touchUpInside
            )
            kanjiChipsStack.addArrangedSubview(chip)
        }
    }

    private func rebuildDefinitionContent(
        surface: String,
        entries: [JMDictEntry],
        suppressEmptyState: Bool = false
    ) {
        definitionStack.arrangedSubviews.forEach {
            definitionStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        let headFont = UIFont.preferredFont(forTextStyle: .headline)
        let caption = UIFont.preferredFont(forTextStyle: .caption1)

        if entries.isEmpty {
            guard !suppressEmptyState else { return }
            let empty = UILabel()
            empty.text = "No dictionary entry found for this word."
            empty.font = bodyFont
            empty.textColor = .tertiaryLabel
            empty.numberOfLines = 0
            definitionStack.addArrangedSubview(empty)
            return
        }

        var groups: [Int: [JMDictEntry]] = [:]
        var order: [Int] = []
        for e in entries {
            if groups[e.sequence] == nil {
                order.append(e.sequence)
            }
            groups[e.sequence, default: []].append(e)
        }

        for (groupIdx, sequence) in order.enumerated() {
            if groupIdx > 0 {
                let sep = UIView()
                sep.backgroundColor = .separator
                sep.translatesAutoresizingMaskIntoConstraints = false
                sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
                definitionStack.addArrangedSubview(sep)
                definitionStack.setCustomSpacing(20, after: sep)
            }

            guard let groupRows = groups[sequence] else { continue }
            let sorted = groupRows.sorted { ($0.score ?? 0) > ($1.score ?? 0) }

            if order.count > 1, let one = sorted.first {
                let expr = UILabel()
                let y = one.displayReading
                if y == one.expression || y.isEmpty {
                    expr.text = one.expression
                } else {
                    expr.text = "\(one.expression)　\(y)"
                }
                expr.font = headFont
                expr.textColor = .label
                expr.numberOfLines = 0
                definitionStack.addArrangedSubview(expr)
            }

            for (senseIdx, row) in sorted.enumerated() {
                let line = NSMutableAttributedString()
                line.append(NSAttributedString(
                    string: "\(senseIdx + 1). ",
                    attributes: [.font: bodyFont, .foregroundColor: UIColor.secondaryLabel]
                ))
                let gloss = row.glossary.trimmingCharacters(in: .whitespacesAndNewlines)
                line.append(NSAttributedString(string: gloss, attributes: [.font: bodyFont, .foregroundColor: UIColor.label]))
                if let tags = row.tags, !tags.isEmpty {
                    line.append(NSAttributedString(
                        string: "\n\(tags)",
                        attributes: [.font: caption, .foregroundColor: UIColor.tertiaryLabel]
                    ))
                }
                if let info = row.info, !info.isEmpty {
                    line.append(NSAttributedString(
                        string: "\n\(info)",
                        attributes: [.font: caption, .foregroundColor: UIColor.secondaryLabel]
                    ))
                }
                let label = UILabel()
                label.attributedText = line
                label.numberOfLines = 0
                definitionStack.addArrangedSubview(label)
            }
        }
    }

    /// True when `surface` is exactly one kanji (CJK ideograph) character.
    private static func isSingleKanji(_ surface: String) -> Bool {
        let trimmed = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1, let scalar = trimmed.unicodeScalars.first else { return false }
        let v = scalar.value
        return (0x3400...0x4DBF).contains(v) || (0x4E00...0x9FFF).contains(v)
    }

    private func rebuildCompoundContent(surface: String) {
        compoundStack.arrangedSubviews.forEach {
            compoundStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        guard showsCompounds else { return }

        // Compounds are only meaningful when drilling into a single kanji. For a
        // multi-character word (e.g. 東京) they surface unrelated entries that
        // merely share a constituent kanji (東…), which is just noise here.
        guard Self.isSingleKanji(surface) else { return }

        let compounds = JMDictStore.shared.compounds(forSurface: surface)
        guard !compounds.isEmpty else { return }

        for (idx, entry) in compounds.enumerated() {
            if idx > 0 {
                compoundStack.addArrangedSubview(Self.makeHairlineDivider())
            }
            compoundStack.addArrangedSubview(makeCompoundRow(entry: entry))
        }
    }

    private func makeCompoundRow(entry: JMDictEntry) -> UIView {
        let button = CompoundRowButton(expression: entry.expression)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(compoundRowTapped(_:)), for: .touchUpInside)

        let exprLabel = UILabel()
        exprLabel.font = UIFont.preferredFont(forTextStyle: .title3)
        exprLabel.textColor = .label
        exprLabel.setContentHuggingPriority(.required, for: .horizontal)
        exprLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let reading = entry.displayReading
        if reading == entry.expression || reading.isEmpty {
            exprLabel.text = entry.expression
        } else {
            exprLabel.text = "\(entry.expression)　\(reading)"
        }

        let glossLabel = UILabel()
        glossLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        glossLabel.textColor = .secondaryLabel
        glossLabel.numberOfLines = 1
        glossLabel.text = Self.primaryGloss(from: entry)

        let textStack = UIStackView(arrangedSubviews: [exprLabel, glossLabel])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.isUserInteractionEnabled = false
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.translatesAutoresizingMaskIntoConstraints = false

        button.addSubview(textStack)
        button.addSubview(chevron)
        NSLayoutConstraint.activate([
            textStack.topAnchor.constraint(equalTo: button.topAnchor, constant: 10),
            textStack.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            textStack.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -10),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),
            chevron.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: button.trailingAnchor),
        ])
        return button
    }

    @objc private func compoundRowTapped(_ sender: CompoundRowButton) {
        onSelectCompound?(sender.expression)
    }

    // MARK: - Helpers

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

        applyGlyph(glyphView, symbolName: symbolName, tintColor: audioGlyphColor, glyphPointSize: glyphPointSize)
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

    private static func applyGlyph(
        _ glyphView: UIImageView,
        symbolName: String,
        tintColor: UIColor,
        glyphPointSize: CGFloat
    ) {
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: glyphPointSize, weight: .semibold)
        glyphView.removeAllSymbolEffects()
        glyphView.preferredSymbolConfiguration = symbolConfig
        glyphView.tintColor = tintColor
        UIView.performWithoutAnimation {
            glyphView.image = UIImage(systemName: symbolName, withConfiguration: symbolConfig)?
                .withRenderingMode(.alwaysTemplate)
        }
    }

}

/// Tappable compound row that remembers its expression for re-lookup.
private final class CompoundRowButton: UIButton {
    let expression: String

    init(expression: String) {
        self.expression = expression
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? .secondarySystemFill : .clear
        }
    }
}
