//
//  WordDictionaryDetailView.swift
//  shizen-chinese
//
//  Reusable word detail: pinyin ruby header, Apple Intelligence card,
//  character chips, numbered CEDICT definitions, common compounds.
//

import InteractionKit
import UIKit

final class WordDictionaryDetailView: UIView {

    private let contentStack = UIStackView()

    private let wordContentStack = UIStackView()
    private let selectedWordLabel = PinyinRubyLabel()
    private let pinyinFallbackLabel = UILabel()

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

    private let characterChipsScrollView = UIScrollView()
    private let characterChipsStack = UIStackView()
    private let characterSectionTitle = UILabel()
    private let characterSectionStack = UIStackView()

    private let dividerBeforeDefinitions = WordDictionaryDetailView.makeHairlineDivider()
    private let definitionsSectionTitle = UILabel()
    private let definitionStack = UIStackView()

    private let dividerBeforeCompounds = WordDictionaryDetailView.makeHairlineDivider()
    private let compoundsSectionTitle = UILabel()
    private let compoundsSectionStack = UIStackView()
    private let compoundStack = UIStackView()

    var onSelectCompound: ((String) -> Void)?
    var onSelectCharacter: ((String) -> Void)?

    var showsCompounds = true {
        didSet {
            guard showsCompounds != oldValue, !lastConfiguredSurface.isEmpty else { return }
            configure(surface: lastConfiguredSurface, sentence: lastConfiguredSentence)
        }
    }

    private var lastConfiguredSurface = ""
    private var lastConfiguredSentence: String?

    private static let contextualCardContentInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    private static let contextualCardShadowBleed: CGFloat = 12
    private static let accentGlyphColor = UIColor.systemYellow

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    func configure(surface: String, sentence: String? = nil) {
        contextualGlossTask?.cancel()
        lastConfiguredSurface = surface
        lastConfiguredSentence = sentence

        guard !surface.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isHidden = true
            contextualCardContainer.isHidden = true
            return
        }

        isHidden = false
        let entries = CedictStore.shared.entries(forSimplified: surface)
        let primary = entries.max { $0.score < $1.score } ?? entries.first

        let wordFont = selectedWordLabel.font ?? UIFont.preferredFont(forTextStyle: .largeTitle)
        let appliedRuby = ChinesePinyinRubyBuilder.applyDisplay(
            to: selectedWordLabel,
            hanzi: surface,
            pinyinMarked: primary?.pinyinMarked ?? "",
            font: wordFont,
            textColor: .label
        )
        let fallbackPinyin = primary?.pinyinMarked.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        pinyinFallbackLabel.text = fallbackPinyin
        pinyinFallbackLabel.isHidden = appliedRuby || fallbackPinyin.isEmpty

        rebuildCharacterChips(surface: surface)
        rebuildCompoundContent(surface: surface)

        let willRequestContextualGloss = FoundationModelContextualGloss.isAvailable
        rebuildDefinitionContent(
            entries: entries,
            suppressEmptyState: willRequestContextualGloss
        )

        dividerAfterWord.isHidden = false
        definitionsSectionTitle.isHidden = entries.isEmpty && willRequestContextualGloss
        definitionStack.isHidden = entries.isEmpty && willRequestContextualGloss
        let showCharacters = !characterChipsScrollView.isHidden
        characterSectionStack.isHidden = !showCharacters
        dividerBeforeDefinitions.isHidden = !showCharacters || definitionsSectionTitle.isHidden
        let showCompounds = !compoundStack.arrangedSubviews.isEmpty
        compoundsSectionStack.isHidden = !showCompounds
        dividerBeforeCompounds.isHidden = !showCompounds || definitionsSectionTitle.isHidden

        loadContextualGloss(
            surface: surface,
            sentence: sentence,
            entries: entries,
            primaryEntry: primary
        )
    }

    var primaryEntry: CedictEntry? {
        let entries = CedictStore.shared.entries(forSimplified: lastConfiguredSurface)
        return entries.max { $0.score < $1.score } ?? entries.first
    }

    private func loadContextualGloss(
        surface: String,
        sentence: String?,
        entries: [CedictEntry],
        primaryEntry: CedictEntry?
    ) {
        guard FoundationModelContextualGloss.isAvailable else {
            contextualCardContainer.isHidden = true
            return
        }

        let trimmedSentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let contextSentence = trimmedSentence.isEmpty ? surface : trimmedSentence
        let hasBroaderSentence = !trimmedSentence.isEmpty && trimmedSentence != surface
        contextualSectionTitle.text = hasBroaderSentence ? "IN THIS SENTENCE" : "MEANING"

        let requestID = UUID()
        contextualRequestID = requestID

        let dictionaryGloss = primaryEntry
            .map(\.primaryGloss)
            .flatMap { $0.isEmpty ? nil : $0 }

        let request = FoundationModelContextualGloss.Request(
            sentence: contextSentence,
            surface: surface,
            dictionaryForm: nil,
            dictionaryGloss: dictionaryGloss
        )

        let hasDictionaryMatch = !entries.isEmpty
        contextualGlossTask = Task { [weak self] in
            if let cached = await FoundationModelContextualGloss.cachedResult(for: request) {
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
                let gloss = try await FoundationModelContextualGloss.explain(request)
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

    private func showDictionaryMissFallback() {
        definitionsSectionTitle.isHidden = false
        definitionStack.isHidden = false
        dividerBeforeDefinitions.isHidden = characterSectionStack.isHidden
        rebuildDefinitionContent(entries: [], suppressEmptyState: false)
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

    private func applyContextualGloss(_ gloss: FoundationModelContextualGloss.Result) {
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

        wordContentStack.axis = .vertical
        wordContentStack.alignment = .leading
        wordContentStack.spacing = 4
        wordContentStack.clipsToBounds = false

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

        pinyinFallbackLabel.font = .preferredFont(forTextStyle: .subheadline)
        pinyinFallbackLabel.textColor = .secondaryLabel
        pinyinFallbackLabel.textAlignment = .natural
        pinyinFallbackLabel.numberOfLines = 0
        pinyinFallbackLabel.isHidden = true

        wordContentStack.addArrangedSubview(selectedWordLabel)
        wordContentStack.addArrangedSubview(pinyinFallbackLabel)

        let sectionHeaderFont = UIFont.preferredFont(forTextStyle: .subheadline)

        contextualSectionTitle.text = "MEANING"
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

        contextualLoadingSpinner.configure(with: Self.accentGlyphColor)
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

        characterChipsScrollView.translatesAutoresizingMaskIntoConstraints = false
        characterChipsScrollView.showsHorizontalScrollIndicator = false
        characterChipsScrollView.alwaysBounceHorizontal = true
        characterChipsScrollView.clipsToBounds = false

        characterChipsStack.translatesAutoresizingMaskIntoConstraints = false
        characterChipsStack.axis = .horizontal
        characterChipsStack.spacing = 8
        characterChipsStack.alignment = .center

        characterChipsScrollView.addSubview(characterChipsStack)
        let chipsContent = characterChipsScrollView.contentLayoutGuide
        NSLayoutConstraint.activate([
            characterChipsStack.topAnchor.constraint(equalTo: chipsContent.topAnchor),
            characterChipsStack.leadingAnchor.constraint(equalTo: chipsContent.leadingAnchor),
            characterChipsStack.trailingAnchor.constraint(equalTo: chipsContent.trailingAnchor),
            characterChipsStack.bottomAnchor.constraint(equalTo: chipsContent.bottomAnchor),
            characterChipsScrollView.heightAnchor.constraint(equalTo: characterChipsStack.heightAnchor),
        ])

        characterSectionTitle.text = "CHARACTERS"
        characterSectionTitle.font = sectionHeaderFont
        characterSectionTitle.textColor = .secondaryLabel

        characterSectionStack.axis = .vertical
        characterSectionStack.alignment = .fill
        characterSectionStack.spacing = 8
        characterSectionStack.addArrangedSubview(characterSectionTitle)
        characterSectionStack.addArrangedSubview(characterChipsScrollView)

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

        contentStack.addArrangedSubview(wordContentStack)
        contentStack.setCustomSpacing(16, after: wordContentStack)
        contentStack.addArrangedSubview(dividerAfterWord)
        contentStack.setCustomSpacing(16, after: dividerAfterWord)
        contentStack.addArrangedSubview(contextualCardContainer)
        contentStack.setCustomSpacing(16, after: contextualCardContainer)
        contentStack.addArrangedSubview(characterSectionStack)
        contentStack.setCustomSpacing(16, after: characterSectionStack)
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
        characterSectionStack.isHidden = true
        dividerBeforeDefinitions.isHidden = true
        definitionsSectionTitle.isHidden = true
        dividerBeforeCompounds.isHidden = true
        compoundsSectionStack.isHidden = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !contextualCardContainer.isHidden {
            contextualCardSurface.layer.shadowPath = UIBezierPath(
                roundedRect: contextualCardSurface.bounds,
                cornerRadius: contextualCardSurface.layer.cornerRadius
            ).cgPath
        }
    }

    // MARK: - Content builders

    private func rebuildCharacterChips(surface: String) {
        characterChipsStack.arrangedSubviews.forEach {
            characterChipsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let items = CedictStore.shared.briefInfo(forCharactersIn: surface)
        guard items.count > 1 || (items.count == 1 && surface.count > 1) else {
            characterChipsScrollView.isHidden = true
            return
        }

        characterChipsScrollView.isHidden = false
        let titleFont = UIFont.preferredFont(forTextStyle: .title2)
        let captionFont = UIFont.preferredFont(forTextStyle: .caption1)
        for item in items {
            let chip = GlassChipControl(
                title: item.character,
                subtitle: item.briefMeaning.isEmpty ? nil : item.briefMeaning,
                titleFont: titleFont,
                subtitleFont: captionFont
            )
            let character = item.character
            chip.addAction(
                UIAction { [weak self] _ in self?.onSelectCharacter?(character) },
                for: .touchUpInside
            )
            characterChipsStack.addArrangedSubview(chip)
        }
    }

    private func rebuildDefinitionContent(
        entries: [CedictEntry],
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

        var groups: [String: [CedictEntry]] = [:]
        var order: [String] = []
        for entry in entries {
            if groups[entry.pinyinMarked] == nil {
                order.append(entry.pinyinMarked)
            }
            groups[entry.pinyinMarked, default: []].append(entry)
        }

        for (groupIdx, pinyin) in order.enumerated() {
            if groupIdx > 0 {
                let sep = UIView()
                sep.backgroundColor = .separator
                sep.translatesAutoresizingMaskIntoConstraints = false
                sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
                definitionStack.addArrangedSubview(sep)
                definitionStack.setCustomSpacing(20, after: sep)
            }

            guard let groupRows = groups[pinyin] else { continue }
            let sorted = groupRows.sorted { $0.score > $1.score }

            if order.count > 1, let one = sorted.first {
                let expr = UILabel()
                expr.text = "\(one.simplified)　\(one.pinyinMarked)"
                expr.font = headFont
                expr.textColor = .label
                expr.numberOfLines = 0
                definitionStack.addArrangedSubview(expr)
            }

            var senseIdx = 0
            for row in sorted {
                for line in row.glossaryLines {
                    if line.uppercased().hasPrefix("CL:") {
                        let tag = UILabel()
                        tag.text = line
                        tag.font = caption
                        tag.textColor = .tertiaryLabel
                        tag.numberOfLines = 0
                        definitionStack.addArrangedSubview(tag)
                        continue
                    }
                    senseIdx += 1
                    let attributed = NSMutableAttributedString()
                    attributed.append(NSAttributedString(
                        string: "\(senseIdx). ",
                        attributes: [.font: bodyFont, .foregroundColor: UIColor.secondaryLabel]
                    ))
                    attributed.append(NSAttributedString(
                        string: line,
                        attributes: [.font: bodyFont, .foregroundColor: UIColor.label]
                    ))
                    let label = UILabel()
                    label.attributedText = attributed
                    label.numberOfLines = 0
                    definitionStack.addArrangedSubview(label)
                }
            }
        }
    }

    private func rebuildCompoundContent(surface: String) {
        compoundStack.arrangedSubviews.forEach {
            compoundStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        guard showsCompounds, CedictStore.isSingleHanCharacter(surface) else { return }

        let compounds = CedictStore.shared.compounds(forSurface: surface)
        guard !compounds.isEmpty else { return }

        for (idx, entry) in compounds.enumerated() {
            if idx > 0 {
                compoundStack.addArrangedSubview(Self.makeHairlineDivider())
            }
            compoundStack.addArrangedSubview(makeCompoundRow(entry: entry))
        }
    }

    private func makeCompoundRow(entry: CedictEntry) -> UIView {
        let button = CompoundRowButton(expression: entry.simplified)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(compoundRowTapped(_:)), for: .touchUpInside)

        let exprLabel = UILabel()
        exprLabel.font = UIFont.preferredFont(forTextStyle: .title3)
        exprLabel.textColor = .label
        exprLabel.setContentHuggingPriority(.required, for: .horizontal)
        exprLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        exprLabel.text = "\(entry.simplified)　\(entry.pinyinMarked)"

        let glossLabel = UILabel()
        glossLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        glossLabel.textColor = .secondaryLabel
        glossLabel.numberOfLines = 1
        glossLabel.text = entry.primaryGloss

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

    private static func makeHairlineDivider() -> UIView {
        let v = UIView()
        v.backgroundColor = .separator
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
        return v
    }
}

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
