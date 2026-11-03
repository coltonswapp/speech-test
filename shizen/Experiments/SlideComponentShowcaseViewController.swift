//
//  SlideComponentShowcaseViewController.swift
//  shizen
//
//  Gallery of every social-slideshow card and building block in the app,
//  rendered live with sample data and grouped by the role each slide plays
//  (hook, explainer, example, tiers, reveal). Tap a slide to open it in the
//  shared slideshow shell for export; "Play all" pages through every slide.
//  The paintbrush menu switches every hero card between solid and glass +
//  underglow, and that choice carries into the real slideshows.
//

import UIKit

// MARK: - Catalog

struct SlideComponentShowcaseItem {
    let title: String
    /// Which slideshow format the component comes from.
    let source: String
    let makeView: () -> UIView
}

struct SlideComponentShowcaseSection {
    enum Kind {
        /// Whole slide, rendered at the export canvas size and scaled into a tile.
        case slide
        /// A piece of chrome, shown at its natural size on the slide background.
        case buildingBlock
    }

    let title: String
    let note: String
    let kind: Kind
    let items: [SlideComponentShowcaseItem]
}

enum SlideComponentShowcaseCatalog {
    private static let spotlightCharacter = "日"
    private static let decompositionExpression = "電話"

    static func sections() -> [SlideComponentShowcaseSection] {
        let spotlight = spotlightDeck()
        let word = decompositionWord()
        let verbCombo = VerbComboSamples.miru
        let ladder = registerLadderDeck()
        let days = WordSlideshowSamples.daysOfTheWeek(layout: .single)
        let daysDouble = WordSlideshowSamples.daysOfTheWeek(layout: .double)
        let opposites = WordSlideshowSamples.opposites()

        var hooks: [SlideComponentShowcaseItem] = []
        var explainers: [SlideComponentShowcaseItem] = []
        var examples: [SlideComponentShowcaseItem] = []
        var tiers: [SlideComponentShowcaseItem] = []
        var reveals: [SlideComponentShowcaseItem] = []
        var wordSlides: [SlideComponentShowcaseItem] = []

        wordSlides.append(SlideComponentShowcaseItem(title: "Word hook", source: "Word slideshow") {
            let card = WordSlideshowHookCardView()
            card.configure(deck: days)
            return card
        })
        let daysWithExamples = WordSlideshowSamples.daysOfTheWeek(layout: .single, withExamples: true)
        let oppositesWithExamples = WordSlideshowSamples.opposites(withExamples: true)
        if let group = daysWithExamples.groups.first {
            wordSlides.append(SlideComponentShowcaseItem(title: "1 per slide + example", source: "Word slideshow") {
                let card = WordSlideshowGroupCardView()
                card.configure(
                    group: group,
                    number: 1,
                    count: daysWithExamples.groups.count,
                    showsPairArrow: false,
                    showsExample: true
                )
                return card
            })
        }
        if let group = oppositesWithExamples.groups.first {
            wordSlides.append(SlideComponentShowcaseItem(title: "Examples slide", source: "Word slideshow") {
                let card = WordSlideshowExamplesCardView()
                card.configure(
                    group: group,
                    number: 1,
                    count: oppositesWithExamples.groups.count,
                    glowColors: [.yellow, .blue]
                )
                return card
            })
        }
        for (title, deck) in [("1 per slide", days), ("2 per slide", daysDouble), ("Pair (opposites)", opposites)] {
            guard let group = deck.groups.first else { continue }
            wordSlides.append(SlideComponentShowcaseItem(title: title, source: "Word slideshow") {
                let card = WordSlideshowGroupCardView()
                card.configure(
                    group: group,
                    number: 1,
                    count: deck.groups.count,
                    showsPairArrow: deck.layout == .pairs
                )
                return card
            })
        }

        hooks.append(SlideComponentShowcaseItem(title: "Verb hook", source: "Verb combo") {
            let card = VerbComboHookCardView()
            card.configure(hookVerb: verbCombo.hookVerb)
            return card
        })
        hooks.append(SlideComponentShowcaseItem(title: "English hook", source: "Register ladder") {
            let card = RegisterLadderHookCardView()
            card.configure(english: ladder.english)
            return card
        })
        if let word {
            hooks.append(SlideComponentShowcaseItem(title: "Word teaser", source: "Kanji decomposition") {
                let card = KanjiDecompositionIntroCardView()
                card.configure(word: word)
                return card
            })
        }
        if let spotlight {
            hooks.append(SlideComponentShowcaseItem(title: "Kanji + readings", source: "Kanji spotlight") {
                let card = KanjiSpotlightKanjiCardView()
                card.configure(subject: spotlight.subject)
                return card
            })
        }

        explainers.append(SlideComponentShowcaseItem(title: "Rule", source: "Verb combo") {
            let card = VerbComboRuleCardView()
            card.configure(rule: verbCombo.rule)
            return card
        })
        if let word, let character = word.characters.first {
            explainers.append(SlideComponentShowcaseItem(title: "Character breakdown", source: "Kanji decomposition") {
                let card = KanjiDecompositionCharacterCardView(badgeIdentifier: .character(index: 0))
                card.configure(character: character, excludingExpression: word.expression)
                return card
            })
            explainers.append(SlideComponentShowcaseItem(title: "Stacked parts", source: "Kanji decomposition") {
                let card = KanjiDecompositionStackedPartsCardView()
                card.configure(word: word)
                return card
            })
        }

        if let example = verbCombo.examples.first {
            examples.append(SlideComponentShowcaseItem(title: "Example sentence", source: "Verb combo") {
                let card = VerbComboExampleCardView()
                card.configure(example: example)
                return card
            })
        }
        if let spotlight, let item = spotlight.items.first {
            let count = spotlight.items.count
            examples.append(SlideComponentShowcaseItem(title: "Highlighted compound", source: "Kanji spotlight") {
                let card = KanjiSpotlightEntryCardView()
                card.configure(
                    item: item,
                    exampleNumber: 1,
                    exampleCount: count,
                    spotlightCharacter: spotlight.subject.character
                )
                return card
            })
        }

        for register in RegisterLadderDeck.Register.allCases {
            tiers.append(SlideComponentShowcaseItem(title: register.title, source: "Register ladder") {
                let card = RegisterLadderLevelCardView(register: register)
                card.configure(level: ladder.level(for: register))
                return card
            })
        }

        if let word {
            reveals.append(SlideComponentShowcaseItem(title: "Teaser (A + B = ?)", source: "Kanji decomposition") {
                let card = KanjiDecompositionTeaserCardView()
                card.configure(word: word)
                return card
            })
            reveals.append(SlideComponentShowcaseItem(title: "Combined reveal", source: "Kanji decomposition") {
                let card = KanjiDecompositionCombinedCardView()
                card.configure(word: word)
                return card
            })
            reveals.append(SlideComponentShowcaseItem(title: "Meaning reveal", source: "Kanji decomposition") {
                let card = KanjiDecompositionCombinedCardView()
                card.configure(word: word, showsParts: false)
                return card
            })
        }
        reveals.append(SlideComponentShowcaseItem(title: "Why close", source: "Register ladder") {
            let card = RegisterLadderWhyCardView()
            card.configure(why: ladder.why)
            return card
        })

        let sections = [
            SlideComponentShowcaseSection(
                title: "Hooks",
                note: "Slide 1. Stops the scroll with a question or a single big subject.",
                kind: .slide,
                items: hooks
            ),
            SlideComponentShowcaseSection(
                title: "Explainers",
                note: "Teach the idea: a rule, a character, or the parts of a word.",
                kind: .slide,
                items: explainers
            ),
            SlideComponentShowcaseSection(
                title: "Examples",
                note: "One word or sentence per slide, with the target highlighted.",
                kind: .slide,
                items: examples
            ),
            SlideComponentShowcaseSection(
                title: "Tiers",
                note: "The same idea at increasing levels, one per slide.",
                kind: .slide,
                items: tiers
            ),
            SlideComponentShowcaseSection(
                title: "Reveals & closers",
                note: "Pay off the hook: the answer, the meaning, or why it matters.",
                kind: .slide,
                items: reveals
            ),
            SlideComponentShowcaseSection(
                title: "Word slides",
                note: "Generated from a prompt with Apple Intelligence: one word, two stacked, or a pair.",
                kind: .slide,
                items: wordSlides
            ),
            SlideComponentShowcaseSection(
                title: "Building blocks",
                note: "Chrome the slides above are built from.",
                kind: .buildingBlock,
                items: buildingBlocks(word: word)
            ),
        ]
        return sections.filter { !$0.items.isEmpty }
    }

    private static func buildingBlocks(word: KanjiDecompositionWord?) -> [SlideComponentShowcaseItem] {
        let character: Character = word?.characters.first ?? "電"
        let meaning = KanjidicStore.shared.detail(forKanji: String(character))?.badgeMeaning ?? "electricity"
        let expression = word?.expression ?? decompositionExpression

        return [
            SlideComponentShowcaseItem(title: "Hero plate", source: "Solid card") {
                heroPlate(style: .solid, character: character)
            },
            SlideComponentShowcaseItem(title: "Hero plate", source: "Glass + underglow") {
                heroPlate(style: .glass, character: character)
            },
            SlideComponentShowcaseItem(title: "Character hero", source: "Badge centered") {
                let hero = KanjiDecompositionCharacterHeroView(layoutIdentifier: .character(index: 0))
                hero.configure(character: character, meaning: meaning)
                return hero
            },
            SlideComponentShowcaseItem(title: "Character hero", source: "Badge on edge") {
                let hero = KanjiDecompositionCharacterHeroView(
                    layoutIdentifier: .character(index: 0),
                    cardWidth: 96,
                    glyphFontSize: 52,
                    badgeStyle: .compact,
                    badgePlacement: .trailingEdgeCentered
                )
                hero.configure(character: character, meaning: meaning)
                return hero
            },
            SlideComponentShowcaseItem(title: "Word hero", source: "Furigana") {
                let hero = KanjiDecompositionWordHeroCard(fixedWidth: 140, heightToWidthRatio: 1.0)
                hero.configure(expression: expression)
                return hero
            },
            SlideComponentShowcaseItem(title: "Word hero", source: "Highlighted kanji") {
                let hero = KanjiDecompositionWordHeroCard(fixedWidth: 140, heightToWidthRatio: 1.0)
                hero.configure(
                    expression: expression,
                    highlightedSubstring: String(character),
                    highlightColor: ExperimentSettings.kanjiSpotlightHighlightColor.tokenHighlightUIColor
                )
                return hero
            },
            SlideComponentShowcaseItem(title: "Watermark", source: "Top or bottom") {
                let host = UIView()
                host.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    host.widthAnchor.constraint(equalToConstant: 140),
                    host.heightAnchor.constraint(equalToConstant: 40),
                ])
                ExperimentSlideWatermark.install(in: host)
                return host
            },
        ]
    }

    private static func heroPlate(style: SlideHeroStyle, character: Character) -> UIView {
        let plate = SlideHeroCardView(style: style)
        plate.translatesAutoresizingMaskIntoConstraints = false

        let glyph = UILabel()
        glyph.text = String(character)
        glyph.font = .systemFont(ofSize: 56, weight: .bold)
        glyph.textColor = .label
        glyph.textAlignment = .center
        glyph.translatesAutoresizingMaskIntoConstraints = false
        plate.addSubview(glyph)

        NSLayoutConstraint.activate([
            plate.widthAnchor.constraint(equalToConstant: 104),
            plate.heightAnchor.constraint(equalTo: plate.widthAnchor, multiplier: 1.24),
            glyph.centerXAnchor.constraint(equalTo: plate.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: plate.centerYAnchor),
        ])
        return plate
    }

    // MARK: Sample data

    private static func spotlightDeck() -> KanjiSpotlightDeck? {
        guard let subject = KanjiSpotlightSubject.make(character: spotlightCharacter) else { return nil }
        let candidates = KanjiSpotlightCatalog.candidates(for: spotlightCharacter)
        let items = KanjiSpotlightCatalog.suggestedSelection(
            compounds: candidates.compounds,
            verbs: candidates.verbs
        )
        return KanjiSpotlightDeck(subject: subject, items: items)
    }

    private static func decompositionWord() -> KanjiDecompositionWord? {
        JMDictStore.shared.entries(forSurface: decompositionExpression)
            .lazy
            .compactMap(KanjiDecompositionWord.make(from:))
            .first
    }

    private static func registerLadderDeck() -> RegisterLadderDeck {
        RegisterLadderDeck(
            english: "Thanks for helping me.",
            casual: RegisterLadderLevel(
                japanese: "手伝ってくれてありがとう！",
                gloss: "everyday wording",
                audience: RegisterLadderDeck.Register.casual.defaultAudience
            ),
            polite: RegisterLadderLevel(
                japanese: "手伝ってくれてありがとうございます。",
                gloss: "",
                audience: RegisterLadderDeck.Register.polite.defaultAudience
            ),
            formal: RegisterLadderLevel(
                japanese: "お手伝いいただき、誠にありがとうございます。",
                gloss: "",
                audience: RegisterLadderDeck.Register.formal.defaultAudience
            ),
            why: "いただく is the humble form of もらう: you lower yourself to raise the listener."
        )
    }
}

// MARK: - Showcase

final class SlideComponentShowcaseViewController: UIViewController {
    private static let gridSpacing: CGFloat = 12
    private static let sideInset: CGFloat = 16

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let sizeControl = UISegmentedControl(items: ExperimentExportSize.allCases.map(\.shortTitle))
    private let heroStyleButton = UIBarButtonItem(title: "Hero style", image: UIImage(systemName: "paintbrush"))
    private var thumbnails: [SlideComponentThumbnailView] = []
    private var exportSize: ExperimentExportSize = .feedPortrait

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Slide components"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentSlideshowChrome.stageBackground

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                title: "Play all",
                image: UIImage(systemName: "play.rectangle.on.rectangle"),
                primaryAction: UIAction { [weak self] _ in self?.playAll() }
            ),
            heroStyleButton,
        ]
        refreshHeroStyleMenu()

        sizeControl.selectedSegmentIndex = ExperimentExportSize.allCases.firstIndex(of: exportSize) ?? 0
        sizeControl.addAction(UIAction { [weak self] _ in self?.sizeControlChanged() }, for: .valueChanged)

        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 28
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        let content = scrollView.contentLayoutGuide
        let frame = scrollView.frameLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -32),
            contentStack.leadingAnchor.constraint(equalTo: frame.leadingAnchor, constant: Self.sideInset),
            contentStack.trailingAnchor.constraint(equalTo: frame.trailingAnchor, constant: -Self.sideInset),
        ])

        rebuildSections()
    }

    /// Cards read the hero style when they're created, so a style change rebuilds every tile.
    private func rebuildSections() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        thumbnails.removeAll()
        contentStack.addArrangedSubview(sizeControl)
        for section in SlideComponentShowcaseCatalog.sections() {
            contentStack.addArrangedSubview(makeSectionView(section))
        }
    }

    private func refreshHeroStyleMenu() {
        let currentStyle = ExperimentSettings.slideHeroStyle
        let styles = SlideHeroStyle.allCases.map { style in
            UIAction(title: style.title, state: style == currentStyle ? .on : .off) { [weak self] _ in
                ExperimentSettings.slideHeroStyle = style
                self?.heroStyleDidChange()
            }
        }

        let currentColor = ExperimentSettings.slideHeroGlowColor
        let colors = DialogueBubbleUnderglowColor.allCases.map { color in
            UIAction(
                title: color.title,
                image: UIImage(systemName: "circle.fill")?.withTintColor(color.uiColor, renderingMode: .alwaysOriginal),
                state: color == currentColor ? .on : .off
            ) { [weak self] _ in
                ExperimentSettings.slideHeroGlowColor = color
                self?.heroStyleDidChange()
            }
        }
        let glowMenu = UIMenu(
            title: "Underglow color",
            subtitle: currentColor.title,
            image: UIImage(systemName: "light.max"),
            children: colors
        )

        heroStyleButton.menu = UIMenu(children: [
            UIMenu(options: .displayInline, children: styles),
            glowMenu,
        ])
    }

    private func heroStyleDidChange() {
        refreshHeroStyleMenu()
        rebuildSections()
    }

    private func sizeControlChanged() {
        let index = sizeControl.selectedSegmentIndex
        guard ExperimentExportSize.allCases.indices.contains(index) else { return }
        exportSize = ExperimentExportSize.allCases[index]
        thumbnails.forEach { $0.exportSize = exportSize }
    }

    // MARK: Layout

    private func makeSectionView(_ section: SlideComponentShowcaseSection) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = section.title
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .label

        let noteLabel = UILabel()
        noteLabel.text = section.note
        noteLabel.font = .preferredFont(forTextStyle: .footnote)
        noteLabel.textColor = .secondaryLabel
        noteLabel.numberOfLines = 0

        let header = UIStackView(arrangedSubviews: [titleLabel, noteLabel])
        header.axis = .vertical
        header.spacing = 2

        let tiles = section.items.map { makeTile(for: $0, kind: section.kind) }
        let grid = UIStackView(arrangedSubviews: Self.rows(of: tiles))
        grid.axis = .vertical
        grid.spacing = Self.gridSpacing

        let stack = UIStackView(arrangedSubviews: [header, grid])
        stack.axis = .vertical
        stack.spacing = 12
        return stack
    }

    private static func rows(of tiles: [UIView]) -> [UIView] {
        stride(from: 0, to: tiles.count, by: 2).map { start in
            var row = Array(tiles[start..<min(start + 2, tiles.count)])
            if row.count == 1 {
                // Keep a lone tile at half width.
                row.append(UIView())
            }
            let stack = UIStackView(arrangedSubviews: row)
            stack.axis = .horizontal
            stack.alignment = .top
            stack.distribution = .fillEqually
            stack.spacing = gridSpacing
            return stack
        }
    }

    private func makeTile(for item: SlideComponentShowcaseItem, kind: SlideComponentShowcaseSection.Kind) -> UIView {
        let preview: UIView
        switch kind {
        case .slide:
            let thumbnail = SlideComponentThumbnailView(makeCardView: item.makeView)
            thumbnail.exportSize = exportSize
            thumbnails.append(thumbnail)
            preview = thumbnail
        case .buildingBlock:
            preview = SlideComponentBlockView(content: item.makeView())
        }

        let titleLabel = UILabel()
        titleLabel.text = item.title
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        let sourceLabel = UILabel()
        sourceLabel.text = item.source
        sourceLabel.font = .systemFont(ofSize: 12, weight: .regular)
        sourceLabel.textColor = .secondaryLabel
        sourceLabel.numberOfLines = 0

        let tile = UIStackView(arrangedSubviews: [preview, titleLabel, sourceLabel])
        tile.axis = .vertical
        tile.spacing = 4
        tile.setCustomSpacing(8, after: preview)

        if kind == .slide {
            preview.isUserInteractionEnabled = true
            preview.addGestureRecognizer(SlideComponentTapGesture { [weak self] in
                self?.open(items: [item], title: item.title)
            })
            preview.accessibilityLabel = "\(item.title), \(item.source)"
            preview.accessibilityTraits = .button
            preview.isAccessibilityElement = true
        }
        return tile
    }

    // MARK: Actions

    private func playAll() {
        let items = SlideComponentShowcaseCatalog.sections().filter { $0.kind == .slide }.flatMap(\.items)
        open(items: items, title: "All slides")
    }

    private func open(items: [SlideComponentShowcaseItem], title: String) {
        let pager = SlideComponentShowcasePagerViewController(items: items, title: title)
        navigationController?.pushViewController(pager, animated: true)
    }
}

// MARK: - Pager

/// The shared slideshow shell over showcase items, so any component can be exported.
private final class SlideComponentShowcasePagerViewController: ExperimentSlideshowViewController {
    private let items: [SlideComponentShowcaseItem]
    private let pagerTitle: String

    override var recommendedHashtags: [String] { ExperimentHashtags.kanji }

    init(items: [SlideComponentShowcaseItem], title: String) {
        self.items = items
        self.pagerTitle = title
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        title = pagerTitle
        super.viewDidLoad()
    }

    override func makeSlideshowPages() -> [ExperimentSlidePageViewController] {
        items.map { ExperimentSlidePageViewController(makeCardView: $0.makeView) }
    }
}

// MARK: - Tiles

/// A slide laid out at its export canvas size, then scaled to fill the tile width,
/// matching how ExperimentSlidePageViewController frames its viewfinder.
private final class SlideComponentThumbnailView: UIView {
    private let cardView: UIView
    private var aspectConstraint: NSLayoutConstraint?

    var exportSize: ExperimentExportSize = .feedPortrait {
        didSet {
            guard exportSize != oldValue else { return }
            applyAspect()
        }
    }

    init(makeCardView: () -> UIView) {
        cardView = makeCardView()
        super.init(frame: .zero)

        clipsToBounds = true
        layer.cornerRadius = 6
        layer.cornerCurve = .continuous
        layer.borderWidth = 1

        cardView.clipsToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = true
        cardView.autoresizingMask = []
        cardView.isUserInteractionEnabled = false
        addSubview(cardView)

        applyAspect()
        applyBorderColor()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func applyAspect() {
        let canvas = exportSize.canvasSize
        aspectConstraint?.isActive = false
        aspectConstraint = heightAnchor.constraint(equalTo: widthAnchor, multiplier: canvas.height / canvas.width)
        aspectConstraint?.isActive = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let canvas = exportSize.canvasSize
        guard canvas.width > 0, bounds.width > 0 else { return }
        let scale = bounds.width / canvas.width

        cardView.transform = .identity
        cardView.bounds = CGRect(origin: .zero, size: canvas)
        cardView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        cardView.layoutIfNeeded()
        cardView.transform = CGAffineTransform(scaleX: scale, y: scale)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyBorderColor()
    }

    private func applyBorderColor() {
        layer.borderColor = ExperimentSlideshowChrome.viewfinderBorder.resolvedColor(with: traitCollection).cgColor
    }
}

/// A building block centered at its natural size on the slide page background.
private final class SlideComponentBlockView: UIView {
    init(content: UIView) {
        super.init(frame: .zero)
        backgroundColor = ExperimentPalette.pageBackground
        layer.cornerRadius = 6
        layer.cornerCurve = .continuous
        clipsToBounds = true

        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 200),
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class SlideComponentTapGesture: UITapGestureRecognizer {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(handleTap))
    }

    @objc private func handleTap() {
        handler()
    }
}
