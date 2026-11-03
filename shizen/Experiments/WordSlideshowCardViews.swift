//
//  WordSlideshowCardViews.swift
//  shizen
//
//  Card faces for prompt-generated word slideshows: a hook slide, then one
//  slide per group with one word, or two stacked whose meaning badges
//  alternate sides (the decomposition stacked-parts look, for whole words).
//

import UIKit

private enum WordSlideshowCardMetrics {
    static let sideInset: CGFloat = 28
    static let singleHeroWidth: CGFloat = 220
    static let singleHeroRatio: CGFloat = 0.8
    static let stackedHeroWidth: CGFloat = 190
    static let stackedHeroRatio: CGFloat = 0.62
    static let maxWordFontSize: CGFloat = 44
    static let minWordFontSize: CGFloat = 22
    /// Horizontal room the word label leaves inside the hero card.
    static let heroTextInset: CGFloat = 32
    static let swipeHintBottomInset: CGFloat = 40
    /// Example sentences wrap inside this width (canvas is 360pt wide at every size).
    static let exampleWidth: CGFloat = 300
    static let exampleJapaneseFontSize: CGFloat = 20
}

// MARK: - Example sentence (Japanese with ruby + English)

/// Japanese example with furigana and the vocabulary word highlighted in its
/// card's glow hue, then the English line underneath.
final class SlideExampleSentenceView: UIView {
    private let japaneseLabel = FuriganaTranscriptLabel()
    private let englishLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        japaneseLabel.clipsToBounds = false
        japaneseLabel.preferredMaxLayoutWidth = WordSlideshowCardMetrics.exampleWidth

        englishLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 15, weight: .regular)
        )
        englishLabel.textColor = .secondaryLabel
        englishLabel.textAlignment = .center
        englishLabel.numberOfLines = 0
        englishLabel.preferredMaxLayoutWidth = WordSlideshowCardMetrics.exampleWidth

        let stack = UIStackView(arrangedSubviews: [japaneseLabel, englishLabel])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: WordSlideshowCardMetrics.exampleWidth),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    func configure(word: WordSlideshowWord, highlight: DialogueBubbleUnderglowColor) {
        let font = UIFont.systemFont(ofSize: WordSlideshowCardMetrics.exampleJapaneseFontSize, weight: .medium)
        japaneseLabel.numberOfLines = 0
        japaneseLabel.lineBreakMode = .byWordWrapping
        japaneseLabel.textAlignment = .center
        // Always attributed (even kana-only) so the word highlight has a string to mark.
        JapaneseFuriganaBuilder.applyScrubDisplay(
            to: japaneseLabel,
            attributed: SlideJapaneseText.centeredAttributed(word.exampleJapanese, font: font),
            contentInsets: UIEdgeInsets(
                top: SlideJapaneseText.hasKanji(word.exampleJapanese)
                    ? JapaneseFuriganaBuilder.wordDetailRubyTopInset(for: font)
                    : 0,
                left: 0,
                bottom: 2,
                right: 0
            )
        )
        japaneseLabel.textAlignment = .center
        if let range = word.exampleWordRange {
            japaneseLabel.setTokenHighlightPreservingLayout(
                foregroundColor: .label,
                highlightedRange: range,
                fullHeight: true,
                highlightColor: highlight.tokenHighlightUIColor
            )
        }
        englishLabel.text = word.exampleEnglish
    }
}

// MARK: - Word hero (glass word card + meaning badge)

/// A whole word in a glass hero card with furigana, and its meaning on a badge
/// that straddles the card's bottom edge. Text is centered like the Verb combo
/// cards (SlideJapaneseText); vertically it matches the Spotlight word card, with
/// the kanji on the card's midline and the ruby above them.
final class SlideWordHeroView: UIView {
    enum BadgePlacement {
        case center
        /// Badge hangs off the card's leading corner.
        case leading
        /// Badge hangs off the card's trailing corner.
        case trailing
    }

    private let heroWidth: CGFloat
    let glowColor: DialogueBubbleUnderglowColor
    private let heroCard: SlideHeroCardView
    private let wordLabel = FuriganaTranscriptLabel()
    private let badge = KanjiDecompositionMeaningBadge(style: .standard)
    private var wordCenterYConstraint: NSLayoutConstraint!

    init(
        width: CGFloat,
        heightToWidthRatio: CGFloat,
        badgePlacement: BadgePlacement,
        heroStyle: SlideHeroStyle = .glass,
        glowColor: DialogueBubbleUnderglowColor = ExperimentSettings.slideHeroGlowColor
    ) {
        heroWidth = width
        self.glowColor = glowColor
        heroCard = SlideHeroCardView(style: heroStyle, glowColor: glowColor)
        super.init(frame: .zero)
        setup(heightToWidthRatio: heightToWidthRatio, badgePlacement: badgePlacement)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup(heightToWidthRatio: CGFloat, badgePlacement: BadgePlacement) {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false

        heroCard.translatesAutoresizingMaskIntoConstraints = false
        wordLabel.translatesAutoresizingMaskIntoConstraints = false
        wordLabel.clipsToBounds = false
        badge.translatesAutoresizingMaskIntoConstraints = false
        heroCard.addSubview(wordLabel)
        addSubview(heroCard)
        addSubview(badge)

        let inset = WordSlideshowCardMetrics.heroTextInset / 2
        wordCenterYConstraint = wordLabel.centerYAnchor.constraint(equalTo: heroCard.centerYAnchor)
        var constraints: [NSLayoutConstraint] = [
            heroCard.topAnchor.constraint(equalTo: topAnchor),
            heroCard.centerXAnchor.constraint(equalTo: centerXAnchor),
            heroCard.widthAnchor.constraint(equalToConstant: heroWidth),
            heroCard.heightAnchor.constraint(equalTo: heroCard.widthAnchor, multiplier: heightToWidthRatio),

            // Full-width label with centered text, so the word can't drift sideways.
            wordLabel.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: inset),
            wordLabel.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor, constant: -inset),
            wordCenterYConstraint,
            wordLabel.topAnchor.constraint(greaterThanOrEqualTo: heroCard.topAnchor, constant: 8),

            badge.centerYAnchor.constraint(equalTo: heroCard.bottomAnchor),
            bottomAnchor.constraint(equalTo: badge.bottomAnchor),
            leadingAnchor.constraint(lessThanOrEqualTo: heroCard.leadingAnchor),
            trailingAnchor.constraint(greaterThanOrEqualTo: heroCard.trailingAnchor),
            leadingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor),
            trailingAnchor.constraint(greaterThanOrEqualTo: badge.trailingAnchor),
        ]
        switch badgePlacement {
        case .center:
            constraints.append(badge.centerXAnchor.constraint(equalTo: heroCard.centerXAnchor))
        case .leading:
            constraints.append(badge.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: -14))
        case .trailing:
            constraints.append(badge.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor, constant: 14))
        }
        NSLayoutConstraint.activate(constraints)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        wordLabel.preferredMaxLayoutWidth = heroWidth - WordSlideshowCardMetrics.heroTextInset
    }

    func configure(word: WordSlideshowWord, meaningColor: WordSlideshowMeaningColor = .standard) {
        let font = UIFont.systemFont(ofSize: fittedFontSize(for: word.expression), weight: .bold)
        SlideJapaneseText.apply(word.expression, to: wordLabel, font: font)
        // Keep the ruby reserve out of Auto Layout so centerY centers the kanji.
        // Counting it (SlideJapaneseText's default for Verb combo) drops the word
        // about half the ruby height below the middle of these fixed-height cards.
        wordLabel.verticalTextInsetsAffectAlignmentRect = true
        // With the kanji dead center, the ruby above makes the pair read a little
        // high. Drop it by a third of the ruby reserve (about 8pt at 44pt).
        wordCenterYConstraint.constant = SlideJapaneseText.hasKanji(word.expression)
            ? JapaneseFuriganaBuilder.wordDetailRubyTopInset(for: font) / 3
            : 0
        // One word, one line; the font is already sized to fit.
        wordLabel.numberOfLines = 1
        badge.configure(text: word.meaning.isEmpty ? "—" : word.meaning)
        badge.setTextColor(meaningColor.textColor(glow: glowColor))
        setNeedsLayout()
    }

    /// Shrinks long words (ありがとうございます) so they stay inside the card.
    private func fittedFontSize(for expression: String) -> CGFloat {
        let count = CGFloat(max(expression.count, 1))
        let fitting = (heroWidth - WordSlideshowCardMetrics.heroTextInset) / count
        return min(WordSlideshowCardMetrics.maxWordFontSize, max(WordSlideshowCardMetrics.minWordFontSize, fitting.rounded(.down)))
    }
}

// MARK: - Hook slide

/// Three stacked lines: "Do you know", the deck's hook phrase, "in Japanese?".
final class WordSlideshowHookCardView: UIView {
    static let leadIn = "Do you know"
    static let closer = "in Japanese?"

    private let leadInLabel = UILabel()
    private let phraseLabel = UILabel()
    private let closerLabel = UILabel()
    private let swipeHintLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        backgroundColor = ExperimentPalette.pageBackground

        let frameFont = UIFontMetrics(forTextStyle: .title3).scaledFont(
            for: .systemFont(ofSize: 18, weight: .semibold)
        )
        for (label, text) in [(leadInLabel, Self.leadIn), (closerLabel, Self.closer)] {
            label.text = text
            label.font = frameFont
            label.textColor = .secondaryLabel
            label.textAlignment = .center
        }

        phraseLabel.font = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .systemFont(ofSize: 26, weight: .bold)
        )
        phraseLabel.textColor = .label
        phraseLabel.textAlignment = .center
        phraseLabel.numberOfLines = 2
        phraseLabel.adjustsFontSizeToFitWidth = true
        phraseLabel.minimumScaleFactor = 0.7

        let headline = UIStackView(arrangedSubviews: [leadInLabel, phraseLabel, closerLabel])
        headline.axis = .vertical
        headline.alignment = .fill
        headline.spacing = 4

        swipeHintLabel.font = .systemFont(ofSize: 14, weight: .medium)
        swipeHintLabel.textColor = .secondaryLabel
        swipeHintLabel.textAlignment = .center

        headline.translatesAutoresizingMaskIntoConstraints = false
        swipeHintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headline)
        addSubview(swipeHintLabel)
        ExperimentSlideWatermark.install(in: self, placement: .top)

        NSLayoutConstraint.activate([
            headline.centerYAnchor.constraint(equalTo: centerYAnchor),
            headline.leadingAnchor.constraint(equalTo: leadingAnchor, constant: WordSlideshowCardMetrics.sideInset),
            headline.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -WordSlideshowCardMetrics.sideInset),

            // Low on the slide, clear of the headline, so it reads as a cue rather than copy.
            swipeHintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            swipeHintLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -WordSlideshowCardMetrics.swipeHintBottomInset),
            swipeHintLabel.topAnchor.constraint(greaterThanOrEqualTo: headline.bottomAnchor, constant: 24),
        ])
    }

    func configure(deck: WordSlideshowDeck) {
        phraseLabel.text = deck.resolvedHookPhrase
        let count = deck.layout == .pairs ? deck.groups.count : deck.allWords.count
        let noun = deck.layout == .pairs ? (count == 1 ? "pair" : "pairs") : (count == 1 ? "word" : "words")
        swipeHintLabel.text = "swipe for all \(count) \(noun) →"
    }
}

// MARK: - Word slide (one, or two stacked)

final class WordSlideshowGroupCardView: UIView {
    private let counterLabel = UILabel()
    private let column = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        backgroundColor = ExperimentPalette.pageBackground

        counterLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 16, weight: .semibold)
        )
        counterLabel.textColor = .secondaryLabel
        counterLabel.textAlignment = .center

        column.axis = .vertical
        column.alignment = .center
        column.spacing = 28

        let contentStack = UIStackView(arrangedSubviews: [counterLabel, column])
        contentStack.axis = .vertical
        contentStack.alignment = .center
        contentStack.spacing = 24
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)
        ExperimentSlideWatermark.install(in: self, placement: .bottom)

        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -8),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
        ])
    }

    /// - Parameters:
    ///   - number: 1-based slide position among the word slides.
    ///   - showsPairArrow: an ↕ between the two cards, for opposites and other pairs.
    /// - Parameter glowColors: underglow per word, in order; the slide-hero setting when nil.
    func configure(
        group: WordSlideshowGroup,
        number: Int,
        count: Int,
        showsPairArrow: Bool,
        glowColors: [DialogueBubbleUnderglowColor]? = nil,
        meaningColor: WordSlideshowMeaningColor = .standard,
        showsExample: Bool = false
    ) {
        counterLabel.text = "\(number)/\(count)"
        column.arrangedSubviews.forEach { view in
            column.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let isStacked = group.words.count > 1
        for (index, word) in group.words.enumerated() {
            if index > 0, showsPairArrow {
                column.addArrangedSubview(Self.makePairArrow())
            }
            let hero = SlideWordHeroView(
                width: isStacked ? WordSlideshowCardMetrics.stackedHeroWidth : WordSlideshowCardMetrics.singleHeroWidth,
                heightToWidthRatio: isStacked ? WordSlideshowCardMetrics.stackedHeroRatio : WordSlideshowCardMetrics.singleHeroRatio,
                // Stacked badges alternate sides so the two meanings don't line up.
                badgePlacement: isStacked ? (index.isMultiple(of: 2) ? .leading : .trailing) : .center,
                glowColor: glowColors.flatMap { $0.indices.contains(index) ? $0[index] : nil }
                    ?? ExperimentSettings.slideHeroGlowColor
            )
            hero.configure(word: word, meaningColor: meaningColor)
            column.addArrangedSubview(hero)

            // Single-word slides have room for the example under the card; stacked
            // slides get a separate WordSlideshowExamplesCardView after them.
            if showsExample, !isStacked, word.hasExample {
                let example = SlideExampleSentenceView()
                example.configure(word: word, highlight: hero.glowColor)
                column.addArrangedSubview(example)
                column.setCustomSpacing(36, after: hero)
            }
        }
        column.spacing = showsPairArrow ? 10 : 28
    }

    private static func makePairArrow() -> UIView {
        let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let arrow = UIImageView(image: UIImage(systemName: "arrow.up.arrow.down", withConfiguration: configuration))
        arrow.tintColor = .tertiaryLabel
        arrow.contentMode = .center
        arrow.translatesAutoresizingMaskIntoConstraints = false
        arrow.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return arrow
    }
}

// MARK: - Examples slide (follows a stacked slide)

/// The examples for a two-word slide, which has no room for them itself:
/// each word and meaning as a small heading, then its example.
final class WordSlideshowExamplesCardView: UIView {
    private let counterLabel = UILabel()
    private let column = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        backgroundColor = ExperimentPalette.pageBackground

        counterLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 16, weight: .semibold)
        )
        counterLabel.textColor = .secondaryLabel
        counterLabel.textAlignment = .center

        column.axis = .vertical
        column.alignment = .center
        column.spacing = 36

        let contentStack = UIStackView(arrangedSubviews: [counterLabel, column])
        contentStack.axis = .vertical
        contentStack.alignment = .center
        contentStack.spacing = 28
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)
        ExperimentSlideWatermark.install(in: self, placement: .bottom)

        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -8),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
        ])
    }

    func configure(group: WordSlideshowGroup, number: Int, count: Int, glowColors: [DialogueBubbleUnderglowColor]) {
        counterLabel.text = "\(number)/\(count) · Examples"
        column.arrangedSubviews.forEach { view in
            column.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for (index, word) in group.words.enumerated() where word.hasExample {
            let glow = glowColors.indices.contains(index) ? glowColors[index] : ExperimentSettings.slideHeroGlowColor

            let heading = UILabel()
            heading.text = word.meaning.isEmpty ? word.expression : "\(word.expression) · \(word.meaning)"
            heading.font = .systemFont(ofSize: 15, weight: .semibold)
            heading.textColor = .secondaryLabel
            heading.textAlignment = .center

            let example = SlideExampleSentenceView()
            example.configure(word: word, highlight: glow)

            let block = UIStackView(arrangedSubviews: [heading, example])
            block.axis = .vertical
            block.alignment = .center
            block.spacing = 10
            column.addArrangedSubview(block)
        }
    }
}

// MARK: - Meaning color

extension WordSlideshowMeaningColor {
    func textColor(glow: DialogueBubbleUnderglowColor) -> UIColor {
        switch self {
        case .standard: return ExperimentPalette.meaningBadgeText
        case .primary: return .label
        case .matchGlow: return Self.readable(glow)
        case .color(let color): return Self.readable(color)
        }
    }

    /// System hues are too light for text on the white badge (yellow, mint);
    /// darken them in light mode, use them as-is in dark mode.
    private static func readable(_ color: DialogueBubbleUnderglowColor) -> UIColor {
        UIColor { traits in
            let base = color.uiColor.resolvedColor(with: traits)
            guard traits.userInterfaceStyle != .dark else { return base }
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            guard base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return base }
            return UIColor(hue: hue, saturation: saturation, brightness: min(brightness, 0.62), alpha: alpha)
        }
    }
}
