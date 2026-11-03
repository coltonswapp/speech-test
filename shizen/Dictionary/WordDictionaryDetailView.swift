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
    /// Full height of the header row; the actions center on the headword inside it.
    private let wordActionsColumn = UIView()
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
    /// Model gloss for this use. The flashcard definition uses it only when the dictionary has nothing.
    private var contextualFlashcardDefinition: String?
    /// Sense the ranker chose for the sentence, as one comma-separated line.
    private var rankedFlashcardDefinition: String?
    /// Primary dictionary gloss used until a contextual line is ready.
    private var dictionaryFlashcardDefinition: String?
    /// Unlisted spans have no dictionary line, so saving waits for the span gloss
    /// rather than storing a card whose back is only the sentence.
    private var isAwaitingSpanGloss = false
    private var isShowingSaveConfirmation = false
    private var saveButtonHideTask: Task<Void, Never>?

    private let contextualCardContainer = UIView()
    private let contextualCardSurface = GlossCardSurfaceView()
    private let contextualSectionStack = UIStackView()
    private let contextualHeaderRow = UIStackView()
    private let contextualSectionTitle = UILabel()
    private var contextualSectionBottomConstraint: NSLayoutConstraint?
    private var contextualCardSurfaceBottomConstraint: NSLayoutConstraint?
    private let contextualLoadingRow = UIStackView()
    private let contextualLoadingSpinner = NNLoadingSpinner(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
    private let contextualLoadingLabel = UILabel()
    private let contextualMeaningLabel = UILabel()
    private let contextualContextHeading = UILabel()
    private let contextualLineLabel = FuriganaTranscriptLabel()
    private let contextualLineEnglishLabel = UILabel()
    private let contextualSourceLabel = UILabel()
    private let contextualGrammarLabel = UILabel()
    private let contextualMessageLabel = UILabel()
    private let relatedWordTagsView = RelatedWordTagsView()
    /// Heading plus body blocks inside the gloss card. Each hides itself when its rows do.
    private let meaningSection = GlossCardSection()
    private let contextSection = GlossCardSection()
    private let bonusSection = GlossCardSection()
    private let commonUsesButton = UIButton(type: .system)
    private let commonUsesTitle = UILabel()
    private let commonUsesLoadingRow = UIStackView()
    private let commonUsesLoadingSpinner = NNLoadingSpinner(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
    private let commonUsesLoadingLabel = UILabel()
    private let commonUsesBodyLabel = UILabel()
    private let componentTilesView = SpanComponentTilesView()
    private let commonUsesMessageLabel = UILabel()
    /// Gloss card plus the example chips that sit underneath it.
    private let glossColumn = UIStackView()
    private let bonusExamplesRow = DialogueGrammarExampleStripView()
    private let feedbackCluster = LLMFeedbackRow()
    private var bonusEngaged = false
    private var bonusButtonTitle = "Common Uses"
    private var bonusButtonSymbol = "list.bullet"
    private var bonusButtonHint = ""
    private var spanFeedbackTask: Task<Void, Never>?
    private var spanFeedbackRequestID: String?

    private var contextualGlossTask: Task<Void, Never>?
    private var commonUsesTask: Task<Void, Never>?
    private var breakDownTask: Task<Void, Never>?
    private var senseFitTask: Task<Void, Never>?
    private var senseFitGeneration = 0
    private var senseFitRows: [DefinitionSenseFitRow] = []
    private var contextualRequestID = UUID()
    private var commonUsesRequestID = UUID()
    private var breakDownRequestID = UUID()
    private var commonUsesEnabled = false
    private var breakDownEnabled = false
    private var glossBonusAction: GlossBonusAction?
    /// Line, English, and lesson label revealed by the Context button.
    private var activeWordContext: StoredWordContext?
    private var lastDictionaryGloss: String?
    /// Kana lookup was untrustworthy; definitions stay hidden until a headword validates.
    private var awaitingContextualHeadword = false

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

    /// Invoked when the user taps a related-word tag on the contextual gloss card.
    var onSelectRelatedWord: ((String) -> Void)?

#if DEBUG
    /// Invoked when the user taps the kanji decomposition shortcut beside Speak.
    var onRequestKanjiDecomposition: (() -> Void)?

    /// Anchor for the format chooser presented from the decomposition button.
    var kanjiDecompositionAnchorView: UIView { kanjiDecompositionButton }
#endif

    /// Pulses the dictionary sense that best fits the surrounding sentence.
    /// Only the sentence-scrub experiment turns this on.
    var showsSenseSuggestion = false {
        didSet {
            guard showsSenseSuggestion != oldValue, !lastConfiguredSurface.isEmpty else { return }
            configure(
                surface: lastConfiguredSurface,
                sentence: lastConfiguredSentence,
                glossFraming: lastGlossFraming
            )
        }
    }

    /// When false, the COMPOUNDS section is never built or shown (e.g. inline in the scrub experiment).
    var showsCompounds = true {
        didSet {
            guard showsCompounds != oldValue, !lastConfiguredSurface.isEmpty else { return }
            configure(
                surface: lastConfiguredSurface,
                sentence: lastConfiguredSentence,
                glossFraming: lastGlossFraming
            )
        }
    }

    /// Supplies the contextual gloss. Defaults to the user's persisted
    /// `ContextualGlossBackend.preferred` setting; hosts can inject a specific provider to override it.
    var contextualGlossProvider: ContextualGlossProviding = ContextualGlossBackend.preferred.provider

    private var lastConfiguredSurface = ""
    private var lastConfiguredSentence: String?
    private var lastConfiguredSourceTitle: String?
    private var lastConfiguredLineEnglish: String?
    private var lastGlossFraming: ContextualGlossFraming = .word

    private static let contextualCardContentInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    private static let contextualCardShadowBleed: CGFloat = 12
    /// How far the bonus button sits inside the card when its center is on the bottom edge.
    private static let glossBonusButtonOverlap: CGFloat = 18
    /// Shifts the edge controls up so they rest mostly on the card, with a small hang.
    private static let edgeControlLift: CGFloat = 8

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
        saveButtonHideTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func configure(
        surface: String,
        sentence: String? = nil,
        glossFraming: ContextualGlossFraming? = nil,
        showsCommonUses: Bool = true,
        showsBreakDown: Bool = false,
        storedContext: StoredWordContext? = nil,
        sourceTitle: String? = nil,
        lineEnglish: String? = nil,
        allowsSavedEntryContext: Bool = true
    ) {
        lastConfiguredSourceTitle = sourceTitle
        lastConfiguredLineEnglish = lineEnglish
        contextualGlossTask?.cancel()
        commonUsesTask?.cancel()
        breakDownTask?.cancel()
        cancelSenseFit()
        resetCommonUsesContent()
        contextualMessageLabel.isHidden = true
        contextualMessageLabel.text = nil
        hideStoredContextDetails()
        commonUsesEnabled = false
        breakDownEnabled = false
        glossBonusAction = nil
        activeWordContext = nil
        lastDictionaryGloss = nil
        contextualFlashcardDefinition = nil
        rankedFlashcardDefinition = nil
        dictionaryFlashcardDefinition = nil
        isAwaitingSpanGloss = false
        lastConfiguredSurface = surface
        lastConfiguredSentence = sentence
        lastGlossFraming = glossFraming ?? Self.inferredGlossFraming(sentence: sentence, surface: surface)

        awaitingContextualHeadword = false
        guard !surface.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isHidden = true
            speechText = ""
            saveDraft = nil
            contextualFlashcardDefinition = nil
            rankedFlashcardDefinition = nil
            dictionaryFlashcardDefinition = nil
            dictionaryFormLabel.isHidden = true
            contextualCardContainer.isHidden = true
            contextualMessageLabel.isHidden = true
            updateCommonUsesButton()
            refreshSaveButton()
#if DEBUG
            kanjiDecompositionButton.isHidden = true
#endif
            return
        }

        isHidden = false
        let lookup = JMDictStore.shared.lookup(forSurface: surface, inSentence: sentence)
        let entries = lookup.entries
        let trimmedSentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let contextSensitive = !trimmedSentence.isEmpty
            && JMDictStore.shared.isContextSensitiveKanaLookup(lookup, inSentence: sentence)
        let glossInSentence = lastGlossFraming == .inSentence
            && !trimmedSentence.isEmpty
            && trimmedSentence != surface.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSurface = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSentenceContext = !trimmedSentence.isEmpty && trimmedSentence != trimmedSurface
        let displayHeadword = contextSensitive ? surface : (lookup.dictionaryForm ?? surface)
        let savedItem = allowsSavedEntryContext
            ? (Self.savedWord(matching: displayHeadword) ?? Self.savedWord(matching: trimmedSurface))
            : nil
        let resolvedStored = storedContext ?? savedItem?.storedContext
        let entryContext = allowsSavedEntryContext ? resolvedStored : nil
        let displayContext = allowsSavedEntryContext
            ? Self.resolvedEntryContext(
                stored: resolvedStored,
                surface: surface,
                sentence: sentence ?? savedItem?.sentence,
                sourceTitle: sourceTitle ?? savedItem?.sourceTitle,
                lineEnglish: lineEnglish ?? savedItem?.lineEnglish
            )
            : nil
        awaitingContextualHeadword = savedItem == nil && entryContext == nil && glossInSentence && contextSensitive
        // Highlights and word lookups pass `.word` framing so the prompt is not
        // "in this sentence", but they still need a meaning — especially when
        // JMdict has no entry (七時, いいところ). A stored word already has that
        // meaning, so reopening a flashcard does not ask again.
        let shouldLoadContextualGloss = savedItem == nil
            && entryContext == nil
            && (glossInSentence || hasSentenceContext || entries.isEmpty)

        let wordFont = selectedWordLabel.font ?? UIFont.preferredFont(forTextStyle: .largeTitle)
        applySelectedWordHeadline(
            JapaneseFuriganaBuilder.attributedString(
                for: displayHeadword,
                font: wordFont,
                textColor: .label
            ),
            maxLines: 1
        )

        let primary = contextSensitive ? nil : lookup.primaryEntry
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

        if !contextSensitive, let dictionaryForm = lookup.dictionaryForm, !showingLemmaAsHeadword {
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

        let senses = contextSensitive ? [] : VocabSenseList.collect(from: entries)
        let gloss = senses.first?.text
            ?? primary.map { Self.primaryGloss(from: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        lastDictionaryGloss = contextSensitive ? nil : gloss
        dictionaryFlashcardDefinition = contextSensitive ? nil : VocabSenseList.flashcardLine(from: entries)
        breakDownEnabled = showsBreakDown && !trimmedSentence.isEmpty
        commonUsesEnabled = showsCommonUses && !breakDownEnabled && hasSentenceContext
        let savedSurface = displayHeadword.trimmingCharacters(in: .whitespacesAndNewlines)
        let lemma = contextSensitive ? nil : lookup.dictionaryForm
        saveDraft = SavedVocabularyItem(
            id: UUID().uuidString,
            surface: savedSurface,
            dictionaryForm: (lemma != savedSurface) ? lemma : nil,
            reading: readingForRomaji.isEmpty ? nil : readingForRomaji,
            gloss: dictionaryFlashcardDefinition,
            senses: dictionaryFlashcardDefinition.map { [VocabSense(text: $0)] } ?? [],
            sentence: trimmedSentence.isEmpty ? nil : trimmedSentence,
            lineEnglish: displayContext?.lineEnglish ?? lineEnglish,
            contextGloss: entryContext?.gloss,
            sourceTitle: displayContext?.source ?? sourceTitle,
            createdAt: Date()
        )
        refreshSaveButton()

        rebuildKanjiChips(surface: surface)
        rebuildCompoundContent(surface: surface)

        let displayedEntries = awaitingContextualHeadword ? [] : entries
        let hideDictionarySection = displayedEntries.isEmpty && shouldLoadContextualGloss
        rebuildDefinitionContent(entries: displayedEntries, suppressEmptyState: hideDictionarySection)

        dividerAfterWord.isHidden = false
        definitionsSectionTitle.isHidden = hideDictionarySection
        definitionStack.isHidden = hideDictionarySection
        let showKanji = !kanjiChipsScrollView.isHidden
        kanjiSectionStack.isHidden = !showKanji
        dividerBeforeDefinitions.isHidden = !showKanji || definitionsSectionTitle.isHidden
        let showCompounds = !compoundStack.arrangedSubviews.isEmpty
        compoundsSectionStack.isHidden = !showCompounds
        dividerBeforeCompounds.isHidden = !showCompounds || definitionsSectionTitle.isHidden

        updateCommonUsesButton()
        if allowsSavedEntryContext, let savedPhrase = Self.savedPhrase(matching: trimmedSurface) {
            // The span gloss was stored when the phrase was saved. A new
            // contextual gloss can disagree with the line on the flashcard.
            if let tokens = savedPhrase.tokens {
                applySpanWordHeader(tokens: tokens)
            }
            let savedReading = savedPhrase.reading?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !savedReading.isEmpty {
                speechText = savedReading
            }
            if var draft = saveDraft {
                draft.kind = .phrase
                draft.tokens = savedPhrase.tokens
                if !savedReading.isEmpty {
                    draft.reading = savedReading
                }
                saveDraft = draft
            }
        }
        if var entryContext {
            // Older phrase cards kept the span meaning on the flashcard gloss, not contextGloss.
            if entryContext.gloss == nil,
               let meaning = Self.savedPhrase(matching: trimmedSurface)?.primarySenseText {
                entryContext.gloss = meaning
                if var draft = saveDraft {
                    draft.contextGloss = meaning
                    saveDraft = draft
                }
            }
            isAwaitingSpanGloss = false
            applyStoredMeaning(entryContext)
        } else if allowsSavedEntryContext, let meaning = Self.savedPhrase(matching: trimmedSurface)?.primarySenseText {
            applyContextualGloss(
                ContextualGlossResult(meaning: meaning, grammarNote: "", relatedWords: [])
            )
        } else if shouldLoadContextualGloss {
            loadContextualGloss(
                surface: surface,
                sentence: sentence,
                lookup: lookup,
                primaryEntry: primary,
                requestsHeadword: awaitingContextualHeadword
            )
        } else {
            clearUnsolicitedGloss()
        }
        if allowsSavedEntryContext {
            installContextButton(stored: displayContext)
        }

#if DEBUG
        updateKanjiDecompositionButton(for: displayedEntries)
#endif
    }

    private static func savedWord(matching surface: String?) -> SavedVocabularyItem? {
        let trimmed = surface?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return SavedVocabularyStore.shared.item(matchingSurface: trimmed)
    }

    /// A saved multi-token card whose meaning was captured with the original span gloss.
    /// Phrases with no stored gloss stay on the gateway path.
    private static func savedPhrase(matching surface: String) -> SavedVocabularyItem? {
        guard let item = SavedVocabularyStore.shared.item(matchingSurface: surface),
              item.isPhrase,
              item.primarySenseText != nil
        else { return nil }
        return item
    }

    /// Saved context first; otherwise the line, English, and track/unit/scene from this look.
    private static func resolvedEntryContext(
        stored: StoredWordContext?,
        surface: String,
        sentence: String?,
        sourceTitle: String?,
        lineEnglish: String?
    ) -> StoredWordContext? {
        if var stored {
            if stored.lineEnglish == nil { stored.lineEnglish = nonempty(lineEnglish) }
            if stored.source == nil { stored.source = nonempty(sourceTitle) }
            if stored.line == nil { stored.line = nonempty(sentence) }
            return stored
        }
        return StoredWordContext.make(
            gloss: nil,
            line: sentence,
            surface: surface,
            source: sourceTitle,
            lineEnglish: lineEnglish
        )
    }

    private static func nonempty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Hides the gloss card when nothing is loading or explained. The Common Uses
    /// button lives on this card, so an empty card is never kept as a placeholder.
    private func clearUnsolicitedGloss() {
        contextualGlossTask?.cancel()
        contextualRequestID = UUID()
        contextualLoadingRow.isHidden = true
        contextualLoadingSpinner.isHidden = true
        contextualMeaningLabel.isHidden = true
        contextualMeaningLabel.text = nil
        hideStoredContextDetails()
        contextualGrammarLabel.isHidden = true
        contextualGrammarLabel.text = nil
        contextualMessageLabel.isHidden = true
        contextualMessageLabel.text = nil
        contextualSectionTitle.isHidden = true
        cancelSpanGlossFeedback()
        relatedWordTagsView.setWords([])
        syncContextualHeader()
        contextualCardContainer.isHidden = true
    }

    private func loadContextualGloss(
        surface: String,
        sentence: String?,
        lookup: JMDictLookupResult,
        primaryEntry: JMDictEntry?,
        requestsHeadword: Bool
    ) {
        let trimmedSentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasDictionaryMatch = !lookup.entries.isEmpty
        hideStoredContextDetails()
        relatedWordTagsView.setWords([])

        let contextSentence = trimmedSentence.isEmpty ? surface : trimmedSentence
        applyContextualSectionTitle()

        let requestID = UUID()
        contextualRequestID = requestID

        let dictionaryGloss = requestsHeadword
            ? nil
            : primaryEntry
                .map { Self.primaryGloss(from: $0) }
                .flatMap { $0.isEmpty ? nil : $0 }

        let request = ContextualGlossRequest(
            sentence: contextSentence,
            surface: surface,
            dictionaryForm: requestsHeadword ? nil : lookup.dictionaryForm,
            dictionaryGloss: dictionaryGloss,
            framing: lastGlossFraming,
            requestsHeadword: requestsHeadword
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
                    self.contextualLoadingRow.isHidden = true
                    self.contextualMeaningLabel.isHidden = true
                    self.contextualGrammarLabel.isHidden = true
                    self.contextualMessageLabel.isHidden = true
                    self.contextualSectionTitle.isHidden = true
                    self.syncContextualHeader()
                    if !self.isShowingCommonUses {
                        self.contextualCardContainer.isHidden = true
                    }
                    if !hasDictionaryMatch || requestsHeadword {
                        self.showDictionaryMissFallback()
                    }
                }
            }
        }
    }

    /// Looks up a long-press span. An exact JMdict expression uses the normal entry;
    /// anything else is explained together in the gloss card.
    /// `tokens` are the selected scrub tokens, used to keep furigana on each word.
    func configureSelectedSpan(
        surface: String,
        sentence: String,
        tokens: [String] = [],
        sourceTitle: String? = nil,
        lineEnglish: String? = nil,
        allowsSavedEntryContext: Bool = true
    ) {
        lastConfiguredSourceTitle = sourceTitle
        lastConfiguredLineEnglish = lineEnglish
        let trimmed = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            configure(surface: "")
            return
        }
        if JMDictStore.shared.hasExactExpressionMatch(for: trimmed) {
            configure(
                surface: trimmed,
                sentence: trimmedSentence,
                showsCommonUses: false,
                showsBreakDown: true,
                sourceTitle: sourceTitle,
                lineEnglish: lineEnglish,
                allowsSavedEntryContext: allowsSavedEntryContext
            )
        } else {
            showUnlistedSpan(surface: trimmed, sentence: trimmedSentence, tokens: tokens)
        }
        applySpanWordHeader(tokens: tokens)
    }

    /// Multi-token spans wrap up to three lines, with each token's own reading.
    private func applySpanWordHeader(tokens: [String]) {
        let pieces = tokens
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard pieces.count > 1 else { return }
        let wordFont = selectedWordLabel.font ?? UIFont.preferredFont(forTextStyle: .largeTitle)
        applySelectedWordHeadline(
            JapaneseFuriganaBuilder.attributedString(
                joining: pieces,
                font: wordFont,
                textColor: .label
            ),
            maxLines: 3
        )
        applySpanRomaji(for: pieces)
    }

    /// Romanize each scrub token on its own so 行って / みたい / お店
    /// reads as `itte mitai omise`, not `ittemitaiomise`.
    private func applySpanRomaji(for pieces: [String]) {
        let romaji = pieces.compactMap { piece -> String? in
            let value = JMDictStore.shared.romajiForDisplay(surface: piece, matching: nil)
            return value.isEmpty ? nil : value
        }.joined(separator: " ")
        romajiLabel.isHidden = romaji.isEmpty
        romajiLabel.text = romaji.isEmpty ? nil : romaji
    }

    private func applySelectedWordHeadline(_ attributed: NSAttributedString, maxLines: Int) {
        let wraps = maxLines > 1
        selectedWordLabel.numberOfLines = maxLines
        selectedWordLabel.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        selectedWordLabel.setContentCompressionResistancePriority(
            wraps ? .defaultLow : .defaultHigh,
            for: .horizontal
        )
        if wraps {
            updateSelectedWordWrapWidth()
        } else {
            selectedWordLabel.preferredMaxLayoutWidth = 0
        }
        JapaneseFuriganaBuilder.applyScrubDisplay(
            to: selectedWordLabel,
            attributed: attributed,
            contentInsets: UIEdgeInsets(
                top: JapaneseFuriganaBuilder.wordDetailRubyTopInset(
                    for: selectedWordLabel.font ?? UIFont.preferredFont(forTextStyle: .largeTitle)
                ),
                left: 0,
                bottom: 2,
                right: 0
            )
        )
    }

    private func updateSelectedWordWrapWidth() {
        guard selectedWordLabel.numberOfLines > 1 else {
            if selectedWordLabel.preferredMaxLayoutWidth != 0 {
                selectedWordLabel.preferredMaxLayoutWidth = 0
            }
            return
        }
        let available = wordHeaderStack.bounds.width
            - wordActionsStack.bounds.width
            - wordHeaderStack.spacing
        guard available > 1 else { return }
        guard abs(selectedWordLabel.preferredMaxLayoutWidth - available) > 0.5 else { return }
        selectedWordLabel.preferredMaxLayoutWidth = available
        selectedWordLabel.invalidateIntrinsicContentSize()
    }

    private func showUnlistedSpan(surface: String, sentence: String, tokens: [String]) {
        contextualGlossTask?.cancel()
        commonUsesTask?.cancel()
        breakDownTask?.cancel()
        cancelSenseFit()
        resetCommonUsesContent()
        commonUsesEnabled = false
        breakDownEnabled = !sentence.isEmpty
        glossBonusAction = nil
        lastDictionaryGloss = nil
        contextualFlashcardDefinition = nil
        rankedFlashcardDefinition = nil
        dictionaryFlashcardDefinition = nil

        lastConfiguredSurface = surface
        lastConfiguredSentence = sentence
        updateCommonUsesButton()
        lastGlossFraming = .inSentence
        awaitingContextualHeadword = false
        isHidden = false

        let wordFont = selectedWordLabel.font ?? UIFont.preferredFont(forTextStyle: .largeTitle)
        applySelectedWordHeadline(
            JapaneseFuriganaBuilder.attributedString(
                for: surface,
                font: wordFont,
                textColor: .label
            ),
            maxLines: 1
        )

        let reading = JMDictStore.shared.kanaReadingForDisplay(surface: surface, matching: nil)
        let romaji = JMDictStore.shared.romajiForDisplay(surface: surface, matching: nil)
        romajiLabel.isHidden = romaji.isEmpty
        romajiLabel.text = romaji.isEmpty ? nil : romaji
        dictionaryFormLabel.text = nil
        dictionaryFormLabel.isHidden = true
        speechText = reading.isEmpty ? surface : reading

        let pieces = tokens
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let isPhrase = pieces.count > 1
        let draftReading = isPhrase ? Self.joinedSpanReading(pieces) : reading
        saveDraft = SavedVocabularyItem(
            id: UUID().uuidString,
            surface: surface,
            dictionaryForm: nil,
            reading: draftReading.isEmpty ? nil : draftReading,
            gloss: nil,
            sentence: sentence.isEmpty ? nil : sentence,
            lineEnglish: lastConfiguredLineEnglish,
            sourceTitle: lastConfiguredSourceTitle,
            kind: isPhrase ? .phrase : .word,
            tokens: isPhrase ? pieces : nil,
            createdAt: Date()
        )
        isAwaitingSpanGloss = GeminiSpanGloss.isConfigured
        refreshSaveButton()

        rebuildKanjiChips(surface: surface)
        rebuildCompoundContent(surface: surface)
        rebuildDefinitionContent(entries: [], suppressEmptyState: true)

        dividerAfterWord.isHidden = false
        definitionsSectionTitle.isHidden = true
        definitionStack.isHidden = true
        let showKanji = !kanjiChipsScrollView.isHidden
        kanjiSectionStack.isHidden = !showKanji
        dividerBeforeDefinitions.isHidden = true
        let showCompounds = !compoundStack.arrangedSubviews.isEmpty
        compoundsSectionStack.isHidden = !showCompounds
        dividerBeforeCompounds.isHidden = !showCompounds || definitionsSectionTitle.isHidden

#if DEBUG
        updateKanjiDecompositionButton(for: [])
#endif
        loadSpanGloss(surface: surface, sentence: sentence)
    }

    /// Reads each scrub token on its own; a whole-string lookup can mis-segment the span.
    private static func joinedSpanReading(_ pieces: [String]) -> String {
        pieces.map { piece in
            let reading = JMDictStore.shared.kanaReadingForDisplay(surface: piece, matching: nil)
            return reading.isEmpty ? piece : reading
        }.joined()
    }

    private func loadSpanGloss(surface: String, sentence: String) {
        cancelSpanGlossFeedback()
        applyContextualSectionTitle()
        relatedWordTagsView.setWords([])
        contextualGrammarLabel.isHidden = true
        contextualMeaningLabel.isHidden = true
        contextualMessageLabel.isHidden = true
        hideStoredContextDetails()

        let contextSentence = sentence.isEmpty ? surface : sentence
        guard GeminiSpanGloss.isConfigured else {
            showContextualMessage(GeminiSpanGloss.unavailabilityMessage)
            return
        }

        let requestID = UUID()
        contextualRequestID = requestID
        let request = GeminiSpanGloss.Request(sentence: contextSentence, surface: surface)
        contextualGlossTask = Task { [weak self] in
            if let cached = await GeminiSpanGloss.cachedResult(for: request) {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.contextualRequestID == requestID else { return }
                    self.applySpanGloss(cached.result, feedback: cached.feedback)
                }
                return
            }

            await MainActor.run {
                guard let self, self.contextualRequestID == requestID else { return }
                self.showContextualGlossLoading()
            }

            do {
                let explained = try await GeminiSpanGloss.explain(request)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.contextualRequestID == requestID else { return }
                    self.applySpanGloss(explained.result, feedback: explained.feedback)
                }
            } catch {
                guard !Task.isCancelled else { return }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    guard let self, self.contextualRequestID == requestID else { return }
                    self.showContextualMessage(message)
                }
            }
        }
    }

    private func applySpanGloss(_ result: GeminiSpanGloss.Result, feedback: LLMFeedbackReceipt?) {
        applyContextualGloss(
            ContextualGlossResult(meaning: result.meaning, grammarNote: result.note, relatedWords: [])
        )
        scheduleSpanGlossFeedback(feedback)
        finishAwaitingSpanGloss()
    }

    /// Span gloss is automatic, so thumbs wait until the span stays put, then join the shared 1-in-4 cadence.
    private func scheduleSpanGlossFeedback(_ feedback: LLMFeedbackReceipt?) {
        spanFeedbackTask?.cancel()
        spanFeedbackTask = nil
        feedbackCluster.dismiss()
        guard let feedback else {
            spanFeedbackRequestID = nil
            return
        }
        let requestID = feedback.requestId
        spanFeedbackRequestID = requestID
        spanFeedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.spanFeedbackRequestID == requestID else { return }
                self.feedbackCluster.present(feedback)
                self.updateGlossCardChrome()
            }
        }
    }

    private func cancelSpanGlossFeedback() {
        spanFeedbackTask?.cancel()
        spanFeedbackTask = nil
        spanFeedbackRequestID = nil
        feedbackCluster.dismiss()
        updateGlossCardChrome()
    }

    private func showContextualMessage(_ message: String) {
        contextualLoadingRow.isHidden = true
        contextualLoadingSpinner.isHidden = true
        contextualMeaningLabel.isHidden = true
        contextualGrammarLabel.isHidden = true
        contextualMeaningLabel.text = nil
        contextualGrammarLabel.text = nil
        hideStoredContextDetails()
        cancelSpanGlossFeedback()
        relatedWordTagsView.setWords([])
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        contextualMessageLabel.text = trimmed
        contextualMessageLabel.isHidden = trimmed.isEmpty
        applyContextualSectionTitle()
        contextualCardContainer.isHidden = false
        contextualCardContainer.setNeedsLayout()
        contextualCardContainer.layoutIfNeeded()
        setNeedsLayout()
        finishAwaitingSpanGloss()
    }

    private enum GlossBonusAction {
        case commonUses
        case breakDown
        case wordContext
    }

    @objc private func commonUsesTapped() {
        if glossBonusAction == .wordContext {
            toggleWordContext()
            return
        }
        if bonusEngaged {
            collapseBonusContent()
            return
        }
        let surface = lastConfiguredSurface.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentence = lastConfiguredSentence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !surface.isEmpty, !sentence.isEmpty else { return }
        switch glossBonusAction {
        case .commonUses:
            loadCommonUses(surface: surface, sentence: sentence)
        case .breakDown:
            loadBreakDown(surface: surface, sentence: sentence)
        case .wordContext, nil:
            break
        }
    }

    private func collapseBonusContent() {
        commonUsesTask?.cancel()
        breakDownTask?.cancel()
        GlossMotion.crossfade(contextualSectionStack, animated: isGlossCardOnScreen) {
            resetCommonUsesContent()
            let showingContextual = !contextualLoadingRow.isHidden
                || (!contextualMeaningLabel.isHidden && !(contextualMeaningLabel.text ?? "").isEmpty)
                || !contextualMessageLabel.isHidden
            applyContextualSectionTitle()
            if !showingContextual {
                contextualSectionTitle.isHidden = true
                syncContextualHeader()
            }
            contextualCardContainer.isHidden = commonUsesButton.isHidden && !showingContextual
        }
        resizeGlossCard()
    }

    private var isGlossCardOnScreen: Bool {
        !contextualCardContainer.isHidden && window != nil
    }

    /// Nearest scroll view (or the window), so the host's spacing moves with the card and nothing else does.
    private var glossLayoutHost: UIView? {
        var candidate = superview
        while let view = candidate {
            if view is UIScrollView { return view }
            candidate = view.superview
        }
        return window
    }

    /// Animates a gloss card height change when it is on screen; otherwise lays out in place.
    private func resizeGlossCard(completion: (() -> Void)? = nil) {
        contextualCardContainer.setNeedsLayout()
        setNeedsLayout()
        guard window != nil, let host = glossLayoutHost else {
            contextualCardContainer.layoutIfNeeded()
            completion?()
            return
        }
        GlossMotion.animateResize(in: host, completion: completion)
    }

    private func loadCommonUses(surface: String, sentence: String) {
        commonUsesTask?.cancel()
        let requestID = UUID()
        commonUsesRequestID = requestID
        let request = GeminiCommonUses.Request(
            sentence: sentence,
            surface: surface,
            dictionaryGloss: lastDictionaryGloss
        )

        guard GeminiCommonUses.isConfigured else {
            showCommonUsesMessage(GeminiCommonUses.unavailabilityMessage)
            return
        }

        commonUsesTask = Task { [weak self] in
            if let cached = await GeminiCommonUses.cachedResult(for: request) {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.commonUsesRequestID == requestID else { return }
                    self.applyCommonUses(cached.result, feedback: cached.feedback)
                }
                return
            }

            await MainActor.run {
                guard let self, self.commonUsesRequestID == requestID else { return }
                self.showCommonUsesLoading()
            }

            do {
                let explained = try await GeminiCommonUses.explain(request)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.commonUsesRequestID == requestID else { return }
                    self.applyCommonUses(explained.result, feedback: explained.feedback)
                }
            } catch {
                guard !Task.isCancelled else { return }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    guard let self, self.commonUsesRequestID == requestID else { return }
                    self.showCommonUsesMessage(message)
                }
            }
        }
    }

    private func loadBreakDown(surface: String, sentence: String) {
        breakDownTask?.cancel()
        let requestID = UUID()
        breakDownRequestID = requestID
        let request = GeminiSpanBreakdown.Request(sentence: sentence, surface: surface)

        guard GeminiSpanBreakdown.isConfigured else {
            showBonusMessage("BREAK DOWN", GeminiSpanBreakdown.unavailabilityMessage)
            return
        }

        breakDownTask = Task { [weak self] in
            if let cached = await GeminiSpanBreakdown.cachedResult(for: request) {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.breakDownRequestID == requestID else { return }
                    self.applyBreakDown(cached.result, feedback: cached.feedback)
                }
                return
            }

            await MainActor.run {
                guard let self, self.breakDownRequestID == requestID else { return }
                self.showBonusLoading("BREAK DOWN")
            }

            do {
                let explained = try await GeminiSpanBreakdown.explain(request)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.breakDownRequestID == requestID else { return }
                    self.applyBreakDown(explained.result, feedback: explained.feedback)
                }
            } catch {
                guard !Task.isCancelled else { return }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    guard let self, self.breakDownRequestID == requestID else { return }
                    self.showBonusMessage("BREAK DOWN", message)
                }
            }
        }
    }

    private var isShowingCommonUses: Bool {
        !commonUsesTitle.isHidden || !commonUsesLoadingRow.isHidden
            || !commonUsesBodyLabel.isHidden || !commonUsesMessageLabel.isHidden
            || !componentTilesView.isHidden
    }

    /// Word / highlight lookups ask for extra insight; in-sentence lookups list other uses.
    private var commonUsesSectionTitle: String {
        lastGlossFraming == .word ? "EXPLAIN" : "COMMON USES"
    }

    private func showCommonUsesLoading() {
        showBonusLoading(commonUsesSectionTitle)
    }

    private func showBonusLoading(_ title: String) {
        GlossMotion.crossfade(contextualSectionStack, animated: isGlossCardOnScreen) {
            commonUsesTitle.text = title
            commonUsesTitle.isHidden = false
            commonUsesBodyLabel.isHidden = true
            commonUsesBodyLabel.attributedText = nil
            clearBreakDownTiles()
            clearBonusExamples()
            commonUsesMessageLabel.isHidden = true
            commonUsesMessageLabel.text = nil
            feedbackCluster.dismiss()
            commonUsesLoadingRow.isHidden = false
            commonUsesLoadingSpinner.isHidden = false
            commonUsesLoadingSpinner.reset()
            revealCardForCommonUses()
        }
        resizeGlossCard()
    }

    private func applyCommonUses(_ result: GeminiCommonUses.Result, feedback: LLMFeedbackReceipt?) {
        applyBonus(
            commonUsesSectionTitle,
            attributedCommonUses(result),
            feedback: feedback,
            examples: result.otherUses
        )
    }

    private func applyBreakDown(_ result: GeminiSpanBreakdown.Result, feedback: LLMFeedbackReceipt?) {
        let components = result.components
        applyBonus(
            "BREAK DOWN",
            attributedBreakDown(result, includePartsNote: components.isEmpty),
            feedback: feedback,
            components: components,
            examples: result.otherUses
        )
    }

    private func applyBonus(
        _ title: String,
        _ body: NSAttributedString,
        feedback: LLMFeedbackReceipt?,
        components: [GeminiSpanBreakdown.Component] = [],
        examples: [String] = []
    ) {
        GlossMotion.crossfade(contextualSectionStack, animated: isGlossCardOnScreen) {
            commonUsesLoadingRow.isHidden = true
            commonUsesLoadingSpinner.isHidden = true
            commonUsesMessageLabel.isHidden = true
            commonUsesMessageLabel.text = nil
            commonUsesTitle.text = title
            commonUsesTitle.isHidden = false
            commonUsesBodyLabel.attributedText = body
            commonUsesBodyLabel.isHidden = false
            componentTilesView.setComponents(components)
            showBonusExamples(examples)
            spanFeedbackTask?.cancel()
            spanFeedbackTask = nil
            spanFeedbackRequestID = nil
            revealCardForCommonUses()
        }
        // Thumbs split once the card has finished growing.
        let commonUsesID = commonUsesRequestID
        let breakDownID = breakDownRequestID
        resizeGlossCard { [weak self] in
            guard let self, self.bonusEngaged,
                  self.commonUsesRequestID == commonUsesID,
                  self.breakDownRequestID == breakDownID else { return }
            self.feedbackCluster.present(feedback)
        }
    }

    private func showCommonUsesMessage(_ message: String) {
        showBonusMessage(commonUsesSectionTitle, message)
    }

    private func showBonusMessage(_ title: String, _ message: String) {
        GlossMotion.crossfade(contextualSectionStack, animated: isGlossCardOnScreen) {
            commonUsesLoadingRow.isHidden = true
            commonUsesLoadingSpinner.isHidden = true
            commonUsesBodyLabel.isHidden = true
            commonUsesBodyLabel.attributedText = nil
            clearBreakDownTiles()
            clearBonusExamples()
            feedbackCluster.dismiss()
            commonUsesTitle.text = title
            commonUsesTitle.isHidden = false
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            commonUsesMessageLabel.text = trimmed
            commonUsesMessageLabel.isHidden = trimmed.isEmpty
            revealCardForCommonUses()
        }
        resizeGlossCard()
    }

    private func revealCardForCommonUses() {
        setBonusEngaged(true)
        let showingContextual = !contextualLoadingRow.isHidden
            || (!contextualMeaningLabel.isHidden && !(contextualMeaningLabel.text ?? "").isEmpty)
            || !contextualMessageLabel.isHidden
        applyContextualSectionTitle()
        if !showingContextual {
            contextualSectionTitle.isHidden = true
            syncContextualHeader()
        }
        contextualCardContainer.isHidden = false
    }

    private func attributedCommonUses(_ result: GeminiCommonUses.Result) -> NSAttributedString {
        let body = NSMutableAttributedString()
        let here = glossWithoutVerbLabel(result.inThisSentence)
        body.append(NSAttributedString(string: here, attributes: [
            .font: UIFont.preferredFont(forTextStyle: .body).semibold(),
            .foregroundColor: UIColor.label,
        ]))
        appendKanjiNote(result.kanjiNote, to: body)
        return body
    }

    private func attributedBreakDown(
        _ result: GeminiSpanBreakdown.Result,
        includePartsNote: Bool = true
    ) -> NSAttributedString {
        let body = NSMutableAttributedString()
        let here = glossWithoutVerbLabel(result.inThisSentence)
        body.append(NSAttributedString(string: here, attributes: [
            .font: UIFont.preferredFont(forTextStyle: .body).semibold(),
            .foregroundColor: UIColor.label,
        ]))
        if includePartsNote {
            appendKanjiNote(result.partsNote, to: body)
        }
        return body
    }

    /// Example phrases sit under the card, the same chips as a grammar gloss.
    private func showBonusExamples(_ uses: [String]) {
        let items = uses.compactMap { GeminiGrammarUsage.Example.parse($0) }
        guard !items.isEmpty else {
            bonusExamplesRow.isHidden = true
            return
        }
        bonusExamplesRow.apply(items)
        bonusExamplesRow.isHidden = false
    }

    private func clearBonusExamples() {
        bonusExamplesRow.isHidden = true
    }

    private func clearBreakDownTiles() {
        componentTilesView.setComponents([])
    }

    /// Renders a composition line with the kanji themselves in the primary color.
    private func appendKanjiNote(_ note: String, to body: NSMutableAttributedString) {
        let trimmed = glossWithoutVerbLabel(note)
        guard !trimmed.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacingBefore = 8
        let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)
        let attributed = NSMutableAttributedString(string: "\n\(trimmed)", attributes: [
            .font: baseFont,
            .foregroundColor: UIColor.secondaryLabel,
            .paragraphStyle: paragraph,
        ])
        let kanjiFont = baseFont.bold()
        var utf16 = 0
        for character in trimmed {
            let length = character.utf16.count
            let isKanji = character.unicodeScalars.contains { scalar in
                let value = scalar.value
                return (0x3400...0x4DBF).contains(value)
                    || (0x4E00...0x9FFF).contains(value)
                    || value == 0x3005
            }
            if isKanji {
                attributed.addAttributes(
                    [
                        .font: kanjiFont,
                        .foregroundColor: UIColor.label,
                    ],
                    range: NSRange(location: 1 + utf16, length: length)
                )
            }
            utf16 += length
        }
        body.append(attributed)
    }

    private func resetCommonUsesContent() {
        commonUsesRequestID = UUID()
        breakDownRequestID = UUID()
        commonUsesTitle.isHidden = true
        commonUsesTitle.text = nil
        commonUsesLoadingRow.isHidden = true
        commonUsesLoadingSpinner.isHidden = true
        commonUsesBodyLabel.isHidden = true
        commonUsesBodyLabel.attributedText = nil
        clearBreakDownTiles()
        clearBonusExamples()
        commonUsesMessageLabel.isHidden = true
        commonUsesMessageLabel.text = nil
        feedbackCluster.dismiss()
        setBonusEngaged(false)
    }

    private func updateCommonUsesButton() {
        let surface = lastConfiguredSurface.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentence = lastConfiguredSentence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasSentenceContext = !sentence.isEmpty && sentence != surface
        if commonUsesEnabled, hasSentenceContext, !surface.isEmpty {
            glossBonusAction = .commonUses
            if lastGlossFraming == .word {
                setGlossBonusButton(
                    title: "Explain",
                    symbolName: "text.quote",
                    hint: "Shows more about this word — how it's built and other common uses"
                )
            } else {
                setGlossBonusButton(
                    title: "Common Uses",
                    symbolName: "list.bullet",
                    hint: "Shows how this word is used here and in other common ways"
                )
            }
        } else if breakDownEnabled, !sentence.isEmpty, !surface.isEmpty {
            glossBonusAction = .breakDown
            setGlossBonusButton(
                title: "Break down",
                symbolName: "square.split.2x1",
                hint: "Shows how these words fit together in this sentence"
            )
        } else {
            glossBonusAction = nil
            commonUsesButton.isHidden = true
        }
        updateGlossCardChrome()
    }

    private func setGlossBonusButton(title: String, symbolName: String, hint: String) {
        bonusButtonTitle = title
        bonusButtonSymbol = symbolName
        bonusButtonHint = hint
        commonUsesButton.accessibilityLabel = title
        commonUsesButton.isHidden = false
        applyBonusButtonChrome()
    }

    private func setBonusEngaged(_ engaged: Bool) {
        bonusEngaged = engaged
        guard !commonUsesButton.isHidden else { return }
        applyBonusButtonChrome()
    }

    private func applyBonusButtonChrome() {
        var config: UIButton.Configuration = bonusEngaged ? .filled() : .glass()
        config.cornerStyle = .capsule
        config.title = bonusButtonTitle
        config.image = UIImage(
            systemName: bonusButtonSymbol,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 13,
                weight: bonusEngaged ? .semibold : .regular
            )
        )
        config.imagePlacement = .leading
        config.imagePadding = 5
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 14)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { [bonusEngaged] incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 15, weight: bonusEngaged ? .semibold : .regular)
            return outgoing
        }
        if bonusEngaged {
            config.baseBackgroundColor = .systemBlue
            config.baseForegroundColor = .white
        } else {
            config.baseForegroundColor = .label
        }
        commonUsesButton.configuration = config
        commonUsesButton.accessibilityHint = bonusEngaged
            ? "Hides this extra explanation"
            : bonusButtonHint
        updateGlossCardChrome()
    }

    private func syncContextualHeader() {
        contextualHeaderRow.isHidden = contextualSectionTitle.isHidden
    }

    /// "In this sentence" when reading a token in a line; otherwise the word's meaning.
    private func applyContextualSectionTitle() {
        let sentence = lastConfiguredSentence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let inSentence = lastGlossFraming == .inSentence
            && Self.hasBroaderSentence(sentence, surface: lastConfiguredSurface)
        contextualSectionTitle.text = inSentence ? "IN THIS SENTENCE" : "MEANING"
        contextualSectionTitle.isHidden = false
        syncContextualHeader()
    }

    /// Keeps gloss text above the edge controls. They sit a little above a perfect straddle.
    private func updateGlossCardChrome() {
        let showsEdge = !commonUsesButton.isHidden || !feedbackCluster.isHidden
        let overlap = showsEdge ? Self.glossBonusButtonOverlap + Self.edgeControlLift : 0
        contextualSectionBottomConstraint?.constant = -(Self.contextualCardContentInsets.bottom + overlap)
        let bleed = showsEdge
            ? max(Self.contextualCardShadowBleed, Self.glossBonusButtonOverlap + 6)
            : Self.contextualCardShadowBleed
        contextualCardSurfaceBottomConstraint?.constant = -bleed
        syncContextualHeader()
        contextualCardContainer.bringSubviewToFront(commonUsesButton)
        contextualCardContainer.bringSubviewToFront(feedbackCluster)
    }

    /// Restores the DEFINITIONS empty state when a no-match contextual gloss fails.
    private func showDictionaryMissFallback() {
        definitionsSectionTitle.isHidden = false
        definitionStack.isHidden = false
        dividerBeforeDefinitions.isHidden = kanjiSectionStack.isHidden
        rebuildDefinitionContent(entries: [])
        setNeedsLayout()
    }

    private func showContextualGlossLoading() {
        contextualCardContainer.isHidden = false
        contextualLoadingRow.isHidden = false
        contextualMeaningLabel.isHidden = true
        contextualGrammarLabel.isHidden = true
        contextualMessageLabel.isHidden = true
        if !(glossBonusAction == .wordContext && bonusEngaged) {
            hideStoredContextDetails()
        }
        contextualMeaningLabel.text = nil
        contextualGrammarLabel.text = nil
        contextualMessageLabel.text = nil
        cancelSpanGlossFeedback()
        applyContextualSectionTitle()
        relatedWordTagsView.setWords([])
        contextualLoadingSpinner.reset()
        contextualLoadingSpinner.isHidden = false
        contextualCardContainer.setNeedsLayout()
        contextualCardContainer.layoutIfNeeded()
    }

    /// Shows the saved gloss as the meaning. The line stays behind the Context button.
    private func applyStoredMeaning(_ context: StoredWordContext) {
        contextualGlossTask?.cancel()
        contextualRequestID = UUID()
        contextualLoadingRow.isHidden = true
        contextualLoadingSpinner.isHidden = true
        contextualMessageLabel.isHidden = true
        contextualMessageLabel.text = nil
        contextualGrammarLabel.isHidden = true
        contextualGrammarLabel.text = nil
        cancelSpanGlossFeedback()
        relatedWordTagsView.setWords([])
        hideStoredContextDetails()

        let gloss = context.gloss?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if gloss.isEmpty {
            contextualMeaningLabel.isHidden = true
            contextualMeaningLabel.text = nil
            contextualSectionTitle.isHidden = true
        } else {
            contextualMeaningLabel.isHidden = false
            contextualMeaningLabel.text = gloss
            contextualMeaningLabel.textColor = .label
            applyContextualSectionTitle()
        }
        syncContextualHeader()
        contextualCardContainer.isHidden = gloss.isEmpty && !context.hasLineContext
        contextualCardContainer.setNeedsLayout()
        contextualCardContainer.layoutIfNeeded()
        setNeedsLayout()
    }

    /// Context is only for a saved word or phrase. A first look at a lesson line keeps Explain.
    private func installContextButton(stored: StoredWordContext?) {
        guard let reveal = stored, reveal.hasLineContext else { return }
        activeWordContext = reveal
        glossBonusAction = .wordContext
        setGlossBonusButton(
            title: "Context",
            symbolName: "text.quote",
            hint: "Shows the line where this word came up"
        )
        let showingMeaning = !contextualMeaningLabel.isHidden
            && !(contextualMeaningLabel.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !showingMeaning, contextualGlossTask == nil {
            setWordContextVisible(true)
            setBonusEngaged(true)
        }
    }

    private func toggleWordContext() {
        let show = !bonusEngaged
        GlossMotion.crossfade(contextualSectionStack, animated: isGlossCardOnScreen) {
            self.setWordContextVisible(show)
        }
        setBonusEngaged(show)
        resizeGlossCard()
    }

    private func setWordContextVisible(_ visible: Bool) {
        guard visible, let context = activeWordContext else {
            hideStoredContextDetails()
            return
        }
        let hasLine = !(context.line?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        if hasLine, let line = context.line {
            contextualLineLabel.isHidden = false
            applyRubyLine(line, surface: lastConfiguredSurface)
        } else {
            contextualLineLabel.isHidden = true
            contextualLineLabel.attributedText = nil
        }
        let english = context.lineEnglish?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        contextualLineEnglishLabel.isHidden = english.isEmpty
        contextualLineEnglishLabel.text = english.isEmpty ? nil : english
        let source = context.source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        contextualSourceLabel.isHidden = source.isEmpty
        contextualSourceLabel.text = source.isEmpty ? nil : source
        let showsExample = hasLine || !english.isEmpty || !source.isEmpty
        contextualContextHeading.isHidden = !showsExample
        contextualCardContainer.isHidden = false
    }

    /// Furigana for the saved line, with the vocabulary word marked.
    private func applyRubyLine(_ line: String, surface: String) {
        let font = UIFont.preferredFont(forTextStyle: .body).semibold()
        contextualLineLabel.font = font
        contextualLineLabel.verticalTextInsetsAffectAlignmentRect = false
        // Only the ruby glyph height, and none when there is no kanji to read,
        // so the line sits right under its CONTEXT heading.
        let hasKanji = line.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || scalar.value == 0x3005
        }
        contextualLineLabel.textInsets = UIEdgeInsets(
            top: hasKanji ? JapaneseFuriganaBuilder.rubyGlyphTopInset(for: font) : 0,
            left: 0,
            bottom: 0,
            right: 0
        )
        contextualLineLabel.attributedText = JapaneseFuriganaBuilder.attributedString(
            for: line,
            font: font,
            textColor: .label
        )
        let needle = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        let highlight = needle.isEmpty ? nil : line.range(of: needle).map { NSRange($0, in: line) }
        contextualLineLabel.setTokenHighlightPreservingLayout(
            foregroundColor: .label,
            highlightedRange: highlight,
            fullHeight: false
        )
    }

    /// Keeps the contextual meaning for the next save. The flashcard definition is chosen separately.
    private func rememberContextGloss(_ meaning: String) {
        let trimmed = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var draft = saveDraft else { return }
        draft.contextGloss = trimmed
        saveDraft = draft
    }

    private func hideStoredContextDetails() {
        contextualContextHeading.isHidden = true
        contextualLineLabel.isHidden = true
        contextualLineLabel.attributedText = nil
        contextualLineEnglishLabel.isHidden = true
        contextualLineEnglishLabel.text = nil
        contextualSourceLabel.isHidden = true
        contextualSourceLabel.text = nil
    }

    private func applyContextualGloss(_ gloss: ContextualGlossResult) {
        if isGlossCardOnScreen {
            GlossMotion.fadeNextContentChange(in: contextualSectionStack)
        }
        contextualLoadingRow.isHidden = true
        contextualLoadingSpinner.isHidden = true
        contextualMessageLabel.isHidden = true
        contextualMessageLabel.text = nil
        applyContextualSectionTitle()
        if !(glossBonusAction == .wordContext && bonusEngaged) {
            hideStoredContextDetails()
        }
        contextualMeaningLabel.isHidden = false
        let meaning = glossWithoutVerbLabel(gloss.meaning)
        contextualMeaningLabel.text = meaning
        contextualMeaningLabel.textColor = .label
        if !meaning.isEmpty {
            contextualFlashcardDefinition = meaning
            rememberContextGloss(meaning)
            applyFlashcardDefinitionToDraft()
        }

        let grammar = glossWithoutVerbLabel(gloss.grammarNote)
        if grammar.isEmpty {
            contextualGrammarLabel.text = nil
            contextualGrammarLabel.isHidden = true
        } else {
            contextualGrammarLabel.text = grammar
            contextualGrammarLabel.isHidden = false
        }
        relatedWordTagsView.setWords(gloss.relatedWords)
        contextualCardContainer.isHidden = false
        if awaitingContextualHeadword {
            revealValidatedHeadword(gloss.headword)
        }
        contextualCardContainer.setNeedsLayout()
        contextualCardContainer.layoutIfNeeded()
        setNeedsLayout()
    }

    /// Shows the dictionary entry for a model headword only when that string is an exact expression.
    private func revealValidatedHeadword(_ headword: String) {
        let trimmed = headword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let entries = JMDictStore.shared.entries(matchingExpression: trimmed)
        guard !entries.isEmpty else { return }

        let surface = lastConfiguredSurface.trimmingCharacters(in: .whitespacesAndNewlines)
        definitionsSectionTitle.isHidden = false
        definitionStack.isHidden = false
        dividerBeforeDefinitions.isHidden = kanjiSectionStack.isHidden
        rebuildDefinitionContent(entries: entries)

        dictionaryFlashcardDefinition = VocabSenseList.flashcardLine(from: entries)
        if var draft = saveDraft {
            if trimmed != surface {
                draft.surface = trimmed
                draft.dictionaryForm = nil
            }
            saveDraft = draft
        }
        applyFlashcardDefinitionToDraft()
        refreshSaveButton()

        if trimmed != surface {
            let primary = entries.max { ($0.score ?? 0) < ($1.score ?? 0) } ?? entries.first
            let reading = JMDictStore.shared.kanaReadingForDisplay(surface: trimmed, matching: primary)
            let romaji = HiraganaRomaji.romanize(reading)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if romaji.isEmpty {
                dictionaryFormLabel.text = "Dictionary form: \(trimmed)"
            } else {
                dictionaryFormLabel.text = "Dictionary form: \(trimmed) · \(romaji)"
            }
            dictionaryFormLabel.isHidden = false
        }
    }

    private static func primaryGloss(from entry: JMDictEntry) -> String {
        let gloss = entry.glossary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gloss.isEmpty else { return "" }
        return gloss
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? gloss
    }

    private static func inferredGlossFraming(sentence: String?, surface: String) -> ContextualGlossFraming {
        let trimmedSurface = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedSentence.isEmpty, trimmedSentence != trimmedSurface {
            return .inSentence
        }
        return .word
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
        // The column of word, romaji, and dictionary form sets the height, so
        // romaji sits right under the headword rather than under the buttons.
        wordHeaderStack.alignment = .fill
        wordHeaderStack.spacing = 16
        wordHeaderStack.distribution = .fill
        wordHeaderStack.clipsToBounds = false

        wordContentStack.axis = .vertical
        wordContentStack.alignment = .fill
        wordContentStack.spacing = 2
        wordContentStack.clipsToBounds = false
        wordContentStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        wordContentStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

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
        wordActionsStack.translatesAutoresizingMaskIntoConstraints = false
        wordActionsColumn.clipsToBounds = false
        wordActionsColumn.setContentHuggingPriority(.required, for: .horizontal)
        wordActionsColumn.setContentCompressionResistancePriority(.required, for: .horizontal)
        wordActionsColumn.addSubview(wordActionsStack)
        wordContentStack.addArrangedSubview(selectedWordLabel)
        wordHeaderStack.addArrangedSubview(wordContentStack)
        wordHeaderStack.addArrangedSubview(wordActionsColumn)
        NSLayoutConstraint.activate([
            wordActionsStack.leadingAnchor.constraint(equalTo: wordActionsColumn.leadingAnchor),
            wordActionsStack.trailingAnchor.constraint(equalTo: wordActionsColumn.trailingAnchor),
            wordActionsStack.topAnchor.constraint(greaterThanOrEqualTo: wordActionsColumn.topAnchor),
            wordActionsStack.bottomAnchor.constraint(lessThanOrEqualTo: wordActionsColumn.bottomAnchor),
            wordActionsStack.centerYAnchor.constraint(equalTo: selectedWordLabel.centerYAnchor),
        ])

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
        // Ruby padding stays in the frame; the header centers the buttons on the glyphs.
        selectedWordLabel.verticalTextInsetsAffectAlignmentRect = true
        selectedWordLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        selectedWordLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        romajiLabel.font = .preferredFont(forTextStyle: .subheadline)
        romajiLabel.textColor = .secondaryLabel
        romajiLabel.textAlignment = .natural
        romajiLabel.numberOfLines = 0

        dictionaryFormLabel.font = .preferredFont(forTextStyle: .subheadline)
        dictionaryFormLabel.textColor = .tertiaryLabel
        dictionaryFormLabel.textAlignment = .natural
        dictionaryFormLabel.numberOfLines = 0
        dictionaryFormLabel.isHidden = true

        wordContentStack.addArrangedSubview(romajiLabel)
        wordContentStack.addArrangedSubview(dictionaryFormLabel)

        let sectionHeaderFont = UIFont.preferredFont(forTextStyle: .subheadline)

        contextualSectionTitle.text = nil
        contextualSectionTitle.isHidden = true
        contextualSectionTitle.font = sectionHeaderFont
        contextualSectionTitle.textColor = .secondaryLabel

        contextualMeaningLabel.font = .preferredFont(forTextStyle: .body).semibold()
        contextualMeaningLabel.textColor = .label
        contextualMeaningLabel.textAlignment = .natural
        contextualMeaningLabel.numberOfLines = 0

        contextualContextHeading.text = "CONTEXT"
        contextualContextHeading.font = sectionHeaderFont
        contextualContextHeading.textColor = .secondaryLabel
        contextualContextHeading.isHidden = true

        contextualLineLabel.font = .preferredFont(forTextStyle: .body).semibold()
        contextualLineLabel.textColor = .label
        contextualLineLabel.textAlignment = .natural
        contextualLineLabel.numberOfLines = 0
        contextualLineLabel.clipsToBounds = false
        contextualLineLabel.verticalTextInsetsAffectAlignmentRect = false
        contextualLineLabel.isHidden = true

        contextualLineEnglishLabel.font = .preferredFont(forTextStyle: .subheadline)
        contextualLineEnglishLabel.textColor = .secondaryLabel
        contextualLineEnglishLabel.textAlignment = .natural
        contextualLineEnglishLabel.numberOfLines = 0
        contextualLineEnglishLabel.isHidden = true

        contextualSourceLabel.font = .preferredFont(forTextStyle: .caption1)
        contextualSourceLabel.textColor = .tertiaryLabel
        contextualSourceLabel.textAlignment = .natural
        contextualSourceLabel.numberOfLines = 0
        contextualSourceLabel.isHidden = true

        contextualGrammarLabel.font = .preferredFont(forTextStyle: .subheadline)
        contextualGrammarLabel.textColor = .secondaryLabel
        contextualGrammarLabel.textAlignment = .natural
        contextualGrammarLabel.numberOfLines = 0
        contextualGrammarLabel.isHidden = true

        contextualMessageLabel.font = .preferredFont(forTextStyle: .subheadline)
        contextualMessageLabel.textColor = .secondaryLabel
        contextualMessageLabel.textAlignment = .natural
        contextualMessageLabel.numberOfLines = 0
        contextualMessageLabel.isHidden = true

        commonUsesTitle.font = sectionHeaderFont
        commonUsesTitle.textColor = .secondaryLabel
        commonUsesTitle.isHidden = true

        commonUsesBodyLabel.numberOfLines = 0
        commonUsesBodyLabel.isHidden = true

        componentTilesView.onSelect = { [weak self] word in
            self?.onSelectRelatedWord?(word)
        }
        componentTilesView.isHidden = true

        commonUsesMessageLabel.font = .preferredFont(forTextStyle: .subheadline)
        commonUsesMessageLabel.textColor = .secondaryLabel
        commonUsesMessageLabel.textAlignment = .natural
        commonUsesMessageLabel.numberOfLines = 0
        commonUsesMessageLabel.isHidden = true

        commonUsesLoadingSpinner.configure(with: Self.audioGlyphColor)
        commonUsesLoadingSpinner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            commonUsesLoadingSpinner.widthAnchor.constraint(equalToConstant: 24),
            commonUsesLoadingSpinner.heightAnchor.constraint(equalToConstant: 24),
        ])
        commonUsesLoadingLabel.text = "Analyzing…"
        commonUsesLoadingLabel.font = .preferredFont(forTextStyle: .subheadline)
        commonUsesLoadingLabel.textColor = .secondaryLabel
        commonUsesLoadingRow.axis = .horizontal
        commonUsesLoadingRow.alignment = .center
        commonUsesLoadingRow.spacing = 10
        commonUsesLoadingRow.isHidden = true
        commonUsesLoadingRow.addArrangedSubview(commonUsesLoadingSpinner)
        commonUsesLoadingRow.addArrangedSubview(commonUsesLoadingLabel)

        var commonUsesConfig = UIButton.Configuration.glass()
        commonUsesConfig.cornerStyle = .capsule
        commonUsesConfig.title = "Common Uses"
        commonUsesConfig.image = UIImage(
            systemName: "list.bullet",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        )
        commonUsesConfig.imagePlacement = .leading
        commonUsesConfig.imagePadding = 5
        commonUsesConfig.baseForegroundColor = .label
        commonUsesConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 14)
        commonUsesConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 15, weight: .semibold)
            return outgoing
        }
        commonUsesButton.configuration = commonUsesConfig
        commonUsesButton.accessibilityLabel = "Common uses"
        commonUsesButton.accessibilityHint = "Shows how this word is used here and in other common ways"
        commonUsesButton.isHidden = true
        commonUsesButton.setContentHuggingPriority(.required, for: .horizontal)
        commonUsesButton.setContentHuggingPriority(.required, for: .vertical)
        commonUsesButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        commonUsesButton.setContentCompressionResistancePriority(.required, for: .vertical)
        commonUsesButton.addTarget(self, action: #selector(commonUsesTapped), for: .touchUpInside)
        feedbackCluster.onVisibilityChange = { [weak self] in
            self?.updateGlossCardChrome()
        }

        contextualSectionTitle.setContentHuggingPriority(.required, for: .horizontal)
        contextualSectionTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        contextualHeaderRow.axis = .horizontal
        contextualHeaderRow.alignment = .center
        contextualHeaderRow.addArrangedSubview(contextualSectionTitle)

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

        relatedWordTagsView.onSelect = { [weak self] word in
            self?.onSelectRelatedWord?(word)
        }
        relatedWordTagsView.isHidden = true

        // Every block in the card is a heading over its body: Meaning / In this
        // sentence, Context, then Common Uses / Explain / Break down.
        meaningSection.setRows(
            heading: contextualHeaderRow,
            body: [
                contextualLoadingRow,
                contextualMeaningLabel,
                contextualGrammarLabel,
                contextualMessageLabel,
                relatedWordTagsView,
            ]
        )
        meaningSection.setCustomSpacing(12, after: contextualGrammarLabel)
        contextSection.setRows(
            heading: contextualContextHeading,
            body: [contextualLineLabel, contextualLineEnglishLabel, contextualSourceLabel]
        )
        bonusSection.setRows(
            heading: commonUsesTitle,
            body: [commonUsesLoadingRow, commonUsesBodyLabel, componentTilesView, commonUsesMessageLabel]
        )
        bonusSection.setCustomSpacing(8, after: commonUsesBodyLabel)

        contextualSectionStack.axis = .vertical
        contextualSectionStack.alignment = .fill
        contextualSectionStack.spacing = GlossCardSection.sectionSpacing
        contextualSectionStack.addArrangedSubview(meaningSection)
        contextualSectionStack.addArrangedSubview(contextSection)
        contextualSectionStack.addArrangedSubview(bonusSection)

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
        contextualCardContainer.addSubview(commonUsesButton)
        contextualCardContainer.addSubview(feedbackCluster)
        contextualSectionStack.translatesAutoresizingMaskIntoConstraints = false
        commonUsesButton.translatesAutoresizingMaskIntoConstraints = false

        let insets = Self.contextualCardContentInsets
        let shadowBleed = Self.contextualCardShadowBleed
        let sectionBottom = contextualSectionStack.bottomAnchor.constraint(
            equalTo: contextualCardSurface.bottomAnchor,
            constant: -insets.bottom
        )
        contextualSectionBottomConstraint = sectionBottom
        let surfaceBottom = contextualCardSurface.bottomAnchor.constraint(
            equalTo: contextualCardContainer.bottomAnchor,
            constant: -shadowBleed
        )
        contextualCardSurfaceBottomConstraint = surfaceBottom
        NSLayoutConstraint.activate([
            contextualCardSurface.topAnchor.constraint(equalTo: contextualCardContainer.topAnchor),
            contextualCardSurface.leadingAnchor.constraint(equalTo: contextualCardContainer.leadingAnchor),
            contextualCardSurface.trailingAnchor.constraint(equalTo: contextualCardContainer.trailingAnchor),
            surfaceBottom,

            contextualSectionStack.topAnchor.constraint(equalTo: contextualCardSurface.topAnchor, constant: insets.top),
            contextualSectionStack.leadingAnchor.constraint(equalTo: contextualCardSurface.leadingAnchor, constant: insets.left),
            contextualSectionStack.trailingAnchor.constraint(equalTo: contextualCardSurface.trailingAnchor, constant: -insets.right),
            sectionBottom,

            commonUsesButton.centerYAnchor.constraint(
                equalTo: contextualCardSurface.bottomAnchor,
                constant: -Self.edgeControlLift
            ),
            commonUsesButton.leadingAnchor.constraint(
                equalTo: contextualCardSurface.leadingAnchor,
                constant: insets.left
            ),

            feedbackCluster.bottomAnchor.constraint(
                equalTo: contextualCardSurface.bottomAnchor,
                constant: LLMFeedbackRow.diameter / 2 - Self.edgeControlLift
            ),
            feedbackCluster.trailingAnchor.constraint(
                equalTo: contextualCardSurface.trailingAnchor,
                constant: -insets.right
            ),
        ])

        kanjiChipsScrollView.translatesAutoresizingMaskIntoConstraints = false
        kanjiChipsScrollView.showsHorizontalScrollIndicator = false
        // Bounces only when the chips overflow; a short strip stays put.
        kanjiChipsScrollView.alwaysBounceHorizontal = false
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
        definitionStack.clipsToBounds = false
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
        glossColumn.axis = .vertical
        glossColumn.alignment = .fill
        glossColumn.spacing = 8
        glossColumn.clipsToBounds = false
        bonusExamplesRow.isHidden = true
        bonusExamplesRow.onChipTap = { [weak self] example in
            self?.onSelectRelatedWord?(example.japanese)
        }
        glossColumn.addArrangedSubview(contextualCardContainer)
        glossColumn.addArrangedSubview(bonusExamplesRow)

        contentStack.addArrangedSubview(glossColumn)
        contentStack.setCustomSpacing(16, after: glossColumn)
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
        updateSelectedWordWrapWidth()
        speakWordButton.bringSubviewToFront(speakWordGlyphView)
        saveVocabularyButton.bringSubviewToFront(saveVocabularyGlyphView)
#if DEBUG
        kanjiDecompositionButton.bringSubviewToFront(kanjiDecompositionGlyphView)
#endif
    }

    // MARK: - Actions

    @objc private func speakWordTapped() {
        wordSpeaker.speak(speechText)
    }

    @objc private func saveVocabularyTapped() {
        let surface = vocabularySaveSurface
        guard !surface.isEmpty, !isAwaitingSpanGloss, let draft = saveDraft, let presenter = nearestViewController() else { return }

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
        Analytics.track(.flashcardAdded, ["kind": item.kind.rawValue, "from_lesson": item.sourceTitle != nil])
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

    /// Headword written to the folder. The tap token stays on `lastConfiguredSurface` for
    /// sentence highlighting and gloss requests (転入した → 転入).
    private var vocabularySaveSurface: String {
        let draft = saveDraft?.surface.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !draft.isEmpty { return draft }
        return lastConfiguredSurface.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func refreshSaveButton(showConfirmation: Bool = false) {
        let surface = vocabularySaveSurface
        let isSaved = !surface.isEmpty && SavedVocabularyStore.shared.contains(surface: surface)

        if showConfirmation, isSaved {
            showSaveConfirmationThenHide()
            return
        }

        saveButtonHideTask?.cancel()
        saveButtonHideTask = nil
        isShowingSaveConfirmation = false
        resetSaveButtonVisuals()
        saveVocabularyButton.isUserInteractionEnabled = !isAwaitingSpanGloss
        saveVocabularyButton.isHidden = surface.isEmpty || isSaved
        saveVocabularyGlyphView.alpha = isAwaitingSpanGloss ? 0.35 : 1
        Self.applyGlyph(
            saveVocabularyGlyphView,
            symbolName: "folder.badge.plus",
            tintColor: Self.audioGlyphColor,
            glyphPointSize: 20
        )
        let isPhrase = saveDraft?.isPhrase == true
        saveVocabularyButton.accessibilityLabel = isPhrase ? "Save phrase" : "Save word"
        saveVocabularyButton.accessibilityHint = isAwaitingSpanGloss
            ? "Available once the meaning loads"
            : (isPhrase ? "Adds this phrase to a folder" : "Adds this word to a folder")
    }

    private func finishAwaitingSpanGloss() {
        guard isAwaitingSpanGloss else { return }
        isAwaitingSpanGloss = false
        guard !isShowingSaveConfirmation else { return }
        refreshSaveButton()
    }

    private func showSaveConfirmationThenHide() {
        saveButtonHideTask?.cancel()
        isShowingSaveConfirmation = true
        resetSaveButtonVisuals()
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
        saveVocabularyGlyphView.addSymbolEffect(.bounce, options: .nonRepeating)

        saveButtonHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 780_000_000)
            guard let self, !Task.isCancelled, self.isShowingSaveConfirmation else { return }

            await self.animateSaveButtonChange(duration: 0.3, options: [.curveEaseIn, .beginFromCurrentState]) {
                self.saveVocabularyButton.transform = CGAffineTransform(scaleX: 0.35, y: 0.35)
                self.saveVocabularyButton.alpha = 0
            }
            guard !Task.isCancelled, self.isShowingSaveConfirmation else { return }

            await self.animateSaveButtonChange(duration: 0.26, options: [.curveEaseInOut, .beginFromCurrentState]) {
                self.saveVocabularyButton.isHidden = true
                self.wordHeaderStack.layoutIfNeeded()
            }
            guard self.isShowingSaveConfirmation else { return }
            self.finishSaveConfirmationHide()
        }
    }

    private func finishSaveConfirmationHide() {
        isShowingSaveConfirmation = false
        saveButtonHideTask = nil
        resetSaveButtonVisuals()
        saveVocabularyButton.isUserInteractionEnabled = true
        Self.applyGlyph(
            saveVocabularyGlyphView,
            symbolName: "folder.badge.plus",
            tintColor: Self.audioGlyphColor,
            glyphPointSize: 20
        )
    }

    private func resetSaveButtonVisuals() {
        saveVocabularyButton.layer.removeAllAnimations()
        saveVocabularyGlyphView.layer.removeAllAnimations()
        saveVocabularyButton.transform = .identity
        saveVocabularyGlyphView.transform = .identity
        saveVocabularyButton.alpha = 1
        saveVocabularyGlyphView.alpha = 1
    }

    @MainActor
    private func animateSaveButtonChange(
        duration: TimeInterval,
        options: UIView.AnimationOptions,
        animations: @escaping () -> Void
    ) async {
        await withCheckedContinuation { continuation in
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: options,
                animations: animations,
                completion: { _ in continuation.resume() }
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
        entries: [JMDictEntry],
        suppressEmptyState: Bool = false
    ) {
        cancelSenseFit()
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

        var senseRows: [(entry: JMDictEntry, gloss: String, line: NSAttributedString)] = []
        for sequence in order {
            guard let groupRows = groups[sequence] else { continue }
            let sorted = groupRows.sorted { ($0.score ?? 0) > ($1.score ?? 0) }
            for (senseIdx, row) in sorted.enumerated() {
                let gloss = row.glossary.trimmingCharacters(in: .whitespacesAndNewlines)
                let line = NSMutableAttributedString()
                line.append(NSAttributedString(
                    string: "\(senseIdx + 1). ",
                    attributes: [.font: bodyFont, .foregroundColor: UIColor.secondaryLabel]
                ))
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
                senseRows.append((row, gloss, line))
            }
        }

        let sentence = lastConfiguredSentence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rankSenses = showsSenseSuggestion
            && Self.hasBroaderSentence(sentence, surface: lastConfiguredSurface)
            && senseRows.filter { !$0.gloss.isEmpty }.count > 1

        var fitRows: [DefinitionSenseFitRow] = []
        var rowCursor = 0
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

            for _ in sorted {
                let built = senseRows[rowCursor]
                rowCursor += 1
                let label = UILabel()
                label.attributedText = built.line
                label.numberOfLines = 0
                guard rankSenses, !built.gloss.isEmpty else {
                    definitionStack.addArrangedSubview(label)
                    continue
                }
                let fitRow = DefinitionSenseFitRow(gloss: built.gloss, line: label, font: bodyFont)
                fitRows.append(fitRow)
                definitionStack.addArrangedSubview(fitRow)
            }
        }

        guard rankSenses, !fitRows.isEmpty else { return }
        senseFitRows = fitRows
        let ranked = senseRows.filter { !$0.gloss.isEmpty }.map {
            VocabSense.jmdict(text: $0.gloss, entryID: $0.entry.id)
        }
        requestSenseFit(sentence: sentence, surface: lastConfiguredSurface, senses: ranked)
    }

    private static func hasBroaderSentence(_ sentence: String, surface: String) -> Bool {
        let trimmedSurface = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        return !sentence.isEmpty && sentence != trimmedSurface
    }

    private func cancelSenseFit() {
        senseFitTask?.cancel()
        senseFitGeneration += 1
        senseFitRows = []
    }

    /// Asks which listed gloss fits the sentence, then pulses that row.
    private func requestSenseFit(sentence: String, surface: String, senses: [VocabSense]) {
        senseFitTask?.cancel()
        senseFitGeneration += 1
        let generation = senseFitGeneration
        let rows = senseFitRows
        senseFitTask = Task { [weak self] in
            let index = await VocabSenseRanker.suggestedIndex(
                sentence: sentence,
                surface: surface,
                senses: senses
            )
            guard !Task.isCancelled, let self, self.senseFitGeneration == generation else { return }
            guard let index, rows.indices.contains(index) else { return }
            rows[index].setSuggested(true)
            self.rankedFlashcardDefinition = VocabSenseList.flashcardLine(fromGlossary: rows[index].glossaryText)
            self.applyFlashcardDefinitionToDraft()
        }
    }

    /// Writes the best single definition onto the save draft: the ranked sense, then the primary dictionary gloss,
    /// and the contextual meaning only when the dictionary has nothing.
    private func applyFlashcardDefinitionToDraft() {
        guard var draft = saveDraft else { return }
        let line = rankedFlashcardDefinition
            ?? dictionaryFlashcardDefinition
            ?? contextualFlashcardDefinition
        guard let line else { return }
        draft.setFlashcardDefinition(line)
        saveDraft = draft
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

/// Wrapping row of span content words in the Break down section.
/// Same glass chip as the KANJI tiles: the word large, the gloss underneath.
/// A heading over its body rows inside the gloss card. Hides itself when every row is hidden,
/// so the card's section spacing never leaves a gap for an empty block.
private final class GlossCardSection: UIStackView {
    /// Gap between two sections in the card.
    static let sectionSpacing: CGFloat = 16
    /// Gap from a section heading to its first body row.
    static let headingSpacing: CGFloat = 4
    /// Gap between body rows.
    static let rowSpacing: CGFloat = 6

    private var hiddenObservations: [NSKeyValueObservation] = []

    init() {
        super.init(frame: .zero)
        axis = .vertical
        alignment = .fill
        spacing = Self.rowSpacing
        isHidden = true
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setRows(heading: UIView, body: [UIView]) {
        for row in [heading] + body {
            addArrangedSubview(row)
            hiddenObservations.append(row.observe(\.isHidden) { [weak self] _, _ in
                self?.syncHidden()
            })
        }
        setCustomSpacing(Self.headingSpacing, after: heading)
        syncHidden()
    }

    private func syncHidden() {
        let empty = arrangedSubviews.allSatisfy(\.isHidden)
        if isHidden != empty {
            isHidden = empty
        }
    }
}

private final class SpanComponentTilesView: UIView {

    var onSelect: ((String) -> Void)?

    private var chips: [GlassChipControl] = []
    private var laidOutHeight: CGFloat = 0

    private static let horizontalSpacing: CGFloat = 8
    private static let verticalSpacing: CGFloat = 8

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setComponents(_ components: [GeminiSpanBreakdown.Component]) {
        chips.forEach { $0.removeFromSuperview() }
        let titleFont = UIFont.preferredFont(forTextStyle: .title2)
        let subtitleFont = UIFont.preferredFont(forTextStyle: .caption1)
        chips = components.compactMap { component in
            let gloss = glossWithoutVerbLabel(component.gloss)
            guard !gloss.isEmpty else { return nil }
            let headword = Self.tappableHeadword(for: component)
            let title = headword ?? Self.displayWord(for: component)
            guard !title.isEmpty else { return nil }
            let chip = GlassChipControl(
                title: title,
                subtitle: gloss,
                titleFont: titleFont,
                subtitleFont: subtitleFont,
                showsFurigana: true
            )
            chip.translatesAutoresizingMaskIntoConstraints = true
            if let headword {
                chip.addAction(UIAction { [weak self] _ in self?.onSelect?(headword) }, for: .touchUpInside)
                chip.accessibilityHint = "Opens the dictionary for this word"
            } else {
                chip.isUserInteractionEnabled = false
                chip.accessibilityTraits = .staticText
            }
            addSubview(chip)
            return chip
        }
        isHidden = chips.isEmpty
        let width = layoutWidth
        laidOutHeight = width > 0 && !chips.isEmpty ? layoutContents(in: width) : 0
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = layoutWidth
        guard width > 0, !chips.isEmpty else { return }
        let height = layoutContents(in: width)
        if abs(height - laidOutHeight) > 0.5 {
            laidOutHeight = height
            invalidateIntrinsicContentSize()
            superview?.setNeedsLayout()
        }
    }

    override var intrinsicContentSize: CGSize {
        let width = layoutWidth
        guard width > 0, !chips.isEmpty else {
            return CGSize(width: UIView.noIntrinsicMetric, height: chips.isEmpty ? 0 : laidOutHeight)
        }
        let height = laidOutHeight > 0 ? laidOutHeight : layoutContents(in: width)
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    private var layoutWidth: CGFloat {
        if bounds.width > 1 { return bounds.width }
        var view = superview
        while let candidate = view {
            if candidate.bounds.width > 1 { return candidate.bounds.width }
            view = candidate.superview
        }
        return 0
    }

    /// Exact JMdict headword for this component, preferring the dictionary form.
    private static func tappableHeadword(for component: GeminiSpanBreakdown.Component) -> String? {
        let lemma = component.lemma.trimmingCharacters(in: .whitespacesAndNewlines)
        let surface = component.surface.trimmingCharacters(in: .whitespacesAndNewlines)
        if !lemma.isEmpty, JMDictStore.shared.hasExactExpressionMatch(for: lemma) {
            return lemma
        }
        if !surface.isEmpty, surface != lemma, JMDictStore.shared.hasExactExpressionMatch(for: surface) {
            return surface
        }
        return nil
    }

    private static func displayWord(for component: GeminiSpanBreakdown.Component) -> String {
        let lemma = component.lemma.trimmingCharacters(in: .whitespacesAndNewlines)
        if !lemma.isEmpty { return lemma }
        return component.surface.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    private func layoutContents(in width: CGFloat) -> CGFloat {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for chip in chips {
            let size = chip.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            let fitsOnRow = x == 0 || x + size.width <= width + 0.5
            if !fitsOnRow {
                x = 0
                y += rowHeight + Self.verticalSpacing
                rowHeight = 0
            }
            chip.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
            x += size.width + Self.horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }

        return chips.isEmpty ? 0 : y + rowHeight
    }
}

/// Wrapping row of tappable related-word chips under a contextual gloss.
private final class RelatedWordTagsView: UIView {

    var onSelect: ((String) -> Void)?

    private let caption = UILabel()
    private var chips: [GlassChipControl] = []
    private var laidOutHeight: CGFloat = 0

    private static let horizontalSpacing: CGFloat = 8
    private static let verticalSpacing: CGFloat = 8
    private static let captionGap: CGFloat = 6

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        caption.text = "RELATED"
        caption.font = .preferredFont(forTextStyle: .caption2)
        caption.textColor = .tertiaryLabel
        addSubview(caption)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setWords(_ words: [ContextualRelatedWord]) {
        chips.forEach { $0.removeFromSuperview() }
        let titleFont = UIFont.preferredFont(forTextStyle: .title2)
        let subtitleFont = UIFont.preferredFont(forTextStyle: .caption1)
        chips = words.map { related in
            let note = glossWithoutVerbLabel(related.note)
            let chip = GlassChipControl(
                title: related.word,
                subtitle: note.isEmpty ? nil : note,
                titleFont: titleFont,
                subtitleFont: subtitleFont,
                showsFurigana: true
            )
            chip.translatesAutoresizingMaskIntoConstraints = true
            let word = related.word
            chip.addAction(UIAction { [weak self] _ in self?.onSelect?(word) }, for: .touchUpInside)
            chip.accessibilityHint = "Opens the dictionary for this related word"
            addSubview(chip)
            return chip
        }
        isHidden = words.isEmpty
        laidOutHeight = 0
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width > 0 ? bounds.width : (superview?.bounds.width ?? 0)
        guard width > 0 else { return }
        let height = layoutContents(in: width)
        if abs(height - laidOutHeight) > 0.5 {
            laidOutHeight = height
            invalidateIntrinsicContentSize()
            superview?.setNeedsLayout()
        }
    }

    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : (superview?.bounds.width ?? 0)
        guard width > 0, !chips.isEmpty else {
            return CGSize(width: UIView.noIntrinsicMetric, height: chips.isEmpty ? 0 : laidOutHeight)
        }
        let height = laidOutHeight > 0 ? laidOutHeight : layoutContents(in: width)
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    @discardableResult
    private func layoutContents(in width: CGFloat) -> CGFloat {
        let captionSize = caption.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        caption.frame = CGRect(x: 0, y: 0, width: width, height: captionSize.height)

        var x: CGFloat = 0
        var y = caption.frame.maxY + Self.captionGap
        var rowHeight: CGFloat = 0

        for chip in chips {
            let size = chip.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            let fitsOnRow = x == 0 || x + size.width <= width + 0.5
            if !fitsOnRow {
                x = 0
                y += rowHeight + Self.verticalSpacing
                rowHeight = 0
            }
            chip.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
            x += size.width + Self.horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }

        return chips.isEmpty ? 0 : y + rowHeight
    }
}

private extension UIFont {
    func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }

    func semibold() -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]
        ])
        return UIFont(descriptor: descriptor, size: 0)
    }
}

/// One dictionary sense row with a leading pulse reserved for the ranker.
private final class DefinitionSenseFitRow: UIView {
    private let dot = SenseSuggestionDot()
    private let label: UILabel
    private let gloss: String
    var glossaryText: String { gloss }

    init(gloss: String, line: UILabel, font: UIFont) {
        self.gloss = gloss
        self.label = line
        super.init(frame: .zero)
        clipsToBounds = false
        isAccessibilityElement = true
        accessibilityLabel = line.attributedText?.string ?? gloss
        label.isAccessibilityElement = false

        let slot = UIView()
        slot.translatesAutoresizingMaskIntoConstraints = false
        slot.clipsToBounds = false
        slot.isUserInteractionEnabled = false
        slot.addSubview(dot)
        let inset = max(0, (font.lineHeight - 9) / 2)
        NSLayoutConstraint.activate([
            dot.centerXAnchor.constraint(equalTo: slot.centerXAnchor),
            dot.topAnchor.constraint(equalTo: slot.topAnchor, constant: inset),
            slot.widthAnchor.constraint(equalToConstant: 9),
            slot.bottomAnchor.constraint(greaterThanOrEqualTo: dot.bottomAnchor),
        ])

        let row = UIStackView(arrangedSubviews: [slot, label])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 8
        row.clipsToBounds = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSuggested(_ suggested: Bool) {
        dot.setSuggested(suggested)
        let base = label.attributedText?.string ?? gloss
        accessibilityLabel = suggested ? "\(base). Suggested for this sentence" : base
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
