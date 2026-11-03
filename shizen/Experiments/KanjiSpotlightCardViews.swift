//
//  KanjiSpotlightCardViews.swift
//  shizen
//
//  Card faces for the Kanji Spotlight pager: subject kanji + readings, then
//  one slide per curated compound/verb. Reuses decomposition hero / word-hero
//  chrome and ExperimentPalette so export frames match sibling slideshows.
//

import UIKit

private enum KanjiSpotlightCardMetrics {
    static let listScale: CGFloat = 1.2

    static func size(_ base: CGFloat) -> CGFloat {
        (base * listScale).rounded()
    }

    static func inset(_ base: CGFloat) -> CGFloat {
        (base * listScale).rounded()
    }

    static let sideInset: CGFloat = 28
    /// Slightly larger than decomposition's default character hero (118).
    static let subjectHeroWidth: CGFloat = 136
    static let subjectGlyphSize: CGFloat = 72
    /// Matches decomposition combined-word hero.
    static let exampleHeroWidth: CGFloat = 200
}

private func installKanjiSpotlightWatermark(
    in host: UIView,
    placement: ExperimentSlideWatermark.Placement
) {
    ExperimentSlideWatermark.install(in: host, placement: placement)
}

// MARK: - Subject kanji slide (readings + swipe cue)

final class KanjiSpotlightKanjiCardView: UIView {
    private let titleLabel = UILabel()
    private let heroView = KanjiDecompositionCharacterHeroView(
        layoutIdentifier: .character(index: 0),
        cardWidth: KanjiSpotlightCardMetrics.subjectHeroWidth,
        glyphFontSize: KanjiSpotlightCardMetrics.subjectGlyphSize,
        badgePlacement: .trailingEdgeCentered,
        heroStyle: .glass,
        glowColor: ExperimentSettings.kanjiSpotlightHighlightColor
    )
    private let swipeHintLabel = UILabel()
    private let contentStack = UIStackView()
    private var collectionView: UICollectionView!
    private var collectionHeightConstraint: NSLayoutConstraint!

    /// One list row per reading type, e.g. ("On", "にち (nichi)、じつ (jitsu)").
    private var readingRows: [(title: String, value: String)] = []

    private var headerRegistration: UICollectionView.SupplementaryRegistration<UICollectionViewListCell>!
    private var readingsCellRegistration: UICollectionView.CellRegistration<SlideReadingRowCell, Int>!

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = ExperimentPalette.pageBackground

        titleLabel.text = KanjiSpotlightIntroTitle.defaultTitle
        titleLabel.font = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .systemFont(ofSize: 24, weight: .bold)
        )
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.isUserInteractionEnabled = true

        swipeHintLabel.text = "swipe to see compounds →"
        swipeHintLabel.font = .systemFont(ofSize: 14, weight: .medium)
        swipeHintLabel.textColor = .secondaryLabel
        swipeHintLabel.textAlignment = .center

        configureCollectionView()

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(heroView)
        contentStack.addArrangedSubview(collectionView)
        contentStack.addArrangedSubview(swipeHintLabel)
        contentStack.setCustomSpacing(22, after: titleLabel)
        contentStack.setCustomSpacing(16, after: collectionView)
        addSubview(contentStack)
        installKanjiSpotlightWatermark(in: self, placement: .top)

        collectionHeightConstraint = collectionView.heightAnchor.constraint(equalToConstant: 1)
        collectionHeightConstraint.isActive = true

        NSLayoutConstraint.activate([
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -8),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 40),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateCollectionHeightIfNeeded()
    }

    private func configureCollectionView() {
        headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { supplementaryView, _, _ in
            var configuration = supplementaryView.defaultContentConfiguration()
            configuration.text = "READINGS"
            configuration.textProperties.font = .systemFont(
                ofSize: KanjiSpotlightCardMetrics.size(11),
                weight: .semibold
            )
            configuration.textProperties.color = .secondaryLabel
            supplementaryView.contentConfiguration = configuration
        }

        readingsCellRegistration = UICollectionView.CellRegistration<SlideReadingRowCell, Int> {
            [weak self] cell, _, index in
            guard let self, self.readingRows.indices.contains(index) else { return }
            let row = self.readingRows[index]
            cell.configure(title: row.title, value: row.value)
        }

        let layout = UICollectionViewCompositionalLayout { _, layoutEnvironment in
            var listConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            listConfiguration.headerMode = .supplementary
            listConfiguration.showsSeparators = true
            listConfiguration.backgroundColor = ExperimentPalette.pageBackground
            let section = NSCollectionLayoutSection.list(
                using: listConfiguration,
                layoutEnvironment: layoutEnvironment
            )
            section.contentInsets.leading += 10
            section.contentInsets.trailing += 10
            return section
        }

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = ExperimentPalette.pageBackground
        collectionView.isScrollEnabled = false
        collectionView.alwaysBounceVertical = false
        collectionView.dataSource = self
    }

    private func updateCollectionHeightIfNeeded() {
        let width = bounds.width
        guard width > 0 else { return }

        let previousHeight = collectionHeightConstraint.constant
        collectionHeightConstraint.constant = 10_000
        let measured = slideListContentHeight(of: collectionView)
        let target = max(measured.rounded(.up) + 4, 1)
        collectionHeightConstraint.constant = target

        if abs(previousHeight - target) > 0.5 {
            setNeedsLayout()
        }
    }

    func configure(
        subject: KanjiSpotlightSubject,
        introTitle: String = KanjiSpotlightIntroTitle.defaultTitle
    ) {
        titleLabel.text = introTitle
        guard let character = subject.character.first else { return }
        heroView.configure(character: character, meaning: subject.badgeMeaning)

        readingRows = slideReadingRows(for: subject.detail)

        collectionView.reloadData()
        collectionView.collectionViewLayout.invalidateLayout()
        setNeedsLayout()
        layoutIfNeeded()
    }

    func applyBadgeMeaning(_ meaning: String) {
        heroView.applyMeaning(meaning)
    }

    func applyHighlightColor(_ color: DialogueBubbleUnderglowColor) {
        heroView.setGlowColor(color)
    }

    func applyIntroTitle(_ title: String) {
        titleLabel.text = title
    }

    func badgeContains(point: CGPoint, in coordinateSpace: UIView) -> Bool {
        heroView.badgeContains(point: point, in: coordinateSpace)
    }

    func titleContains(point: CGPoint, in coordinateSpace: UIView) -> Bool {
        let rect = titleLabel.convert(titleLabel.bounds, to: coordinateSpace).insetBy(dx: -8, dy: -8)
        return rect.contains(point)
    }
}

extension KanjiSpotlightKanjiCardView: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        readingRows.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        collectionView.dequeueConfiguredReusableCell(
            using: readingsCellRegistration,
            for: indexPath,
            item: indexPath.item
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        collectionView.dequeueConfiguredReusableSupplementary(
            using: headerRegistration,
            for: indexPath
        )
    }
}

// MARK: - Compound / verb showcase slide

final class KanjiSpotlightEntryCardView: UIView {
    private let titleLabel = UILabel()
    private let wordHero = KanjiDecompositionWordHeroCard(
        fixedWidth: KanjiSpotlightCardMetrics.exampleHeroWidth,
        heightToWidthRatio: 1.0,
        heroStyle: .glass,
        glowColor: ExperimentSettings.kanjiSpotlightHighlightColor
    )
    private let glossLabel = UILabel()
    private var spotlightCharacter = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = ExperimentPalette.pageBackground

        titleLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 16, weight: .semibold)
        )
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1

        glossLabel.font = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .systemFont(ofSize: 22, weight: .semibold)
        )
        glossLabel.textColor = .label
        glossLabel.textAlignment = .center
        glossLabel.numberOfLines = 3
        glossLabel.lineBreakMode = .byWordWrapping
        glossLabel.adjustsFontSizeToFitWidth = true
        glossLabel.minimumScaleFactor = 0.7

        let contentStack = UIStackView(arrangedSubviews: [titleLabel, wordHero, glossLabel])
        contentStack.axis = .vertical
        contentStack.alignment = .center
        contentStack.spacing = 24
        contentStack.setCustomSpacing(24, after: titleLabel)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)
        installKanjiSpotlightWatermark(in: self, placement: .bottom)

        NSLayoutConstraint.activate([
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -12),
            contentStack.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: KanjiSpotlightCardMetrics.sideInset
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -KanjiSpotlightCardMetrics.sideInset
            ),
            titleLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            glossLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
        ])
    }

    func configure(
        item: KanjiSpotlightShowcaseItem,
        exampleNumber: Int,
        exampleCount: Int,
        spotlightCharacter: String
    ) {
        self.spotlightCharacter = spotlightCharacter
        titleLabel.text = "Example \(exampleNumber)/\(exampleCount)"
        glossLabel.text = item.gloss
        // Same centered furigana word hero as Kanji Decomposition's combined reveal.
        wordHero.configure(
            expression: item.expression,
            showFurigana: true,
            highlightedSubstring: spotlightCharacter,
            highlightColor: ExperimentSettings.kanjiSpotlightHighlightColor.tokenHighlightUIColor
        )
    }

    func applyHighlightColor(_ color: DialogueBubbleUnderglowColor) {
        wordHero.highlightSubstring(spotlightCharacter, color: color.tokenHighlightUIColor)
        wordHero.setGlowColor(color)
    }
}
