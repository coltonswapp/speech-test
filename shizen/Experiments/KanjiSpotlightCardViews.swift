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

private func installKanjiSpotlightWatermark(in host: UIView) {
    let label = UILabel()
    label.text = "shizenapp.com"
    label.font = .systemFont(ofSize: 11, weight: .medium)
    label.textColor = UIColor.secondaryLabel.withAlphaComponent(0.65)
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(label)
    NSLayoutConstraint.activate([
        label.centerXAnchor.constraint(equalTo: host.centerXAnchor),
        label.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -14),
    ])
}

// MARK: - Subject kanji slide (readings + swipe cue)

final class KanjiSpotlightKanjiCardView: UIView {
    private let titleLabel = UILabel()
    private let heroView = KanjiDecompositionCharacterHeroView(
        layoutIdentifier: .character(index: 0),
        cardWidth: KanjiSpotlightCardMetrics.subjectHeroWidth,
        glyphFontSize: KanjiSpotlightCardMetrics.subjectGlyphSize,
        badgePlacement: .trailingEdgeCentered
    )
    private let swipeHintLabel = UILabel()
    private let contentStack = UIStackView()
    private var collectionView: UICollectionView!
    private var collectionHeightConstraint: NSLayoutConstraint!

    private var onReading: String?
    private var kunReading: String?

    private var headerRegistration: UICollectionView.SupplementaryRegistration<UICollectionViewListCell>!
    private var readingsCellRegistration: UICollectionView.CellRegistration<KanjiSpotlightReadingsCell, Void>!

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

        titleLabel.text = "Kanji spotlight"
        titleLabel.font = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .systemFont(ofSize: 24, weight: .bold)
        )
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1

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
        installKanjiSpotlightWatermark(in: self)

        collectionHeightConstraint = collectionView.heightAnchor.constraint(equalToConstant: 1)
        collectionHeightConstraint.isActive = true

        NSLayoutConstraint.activate([
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -8),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -36),
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

        readingsCellRegistration = UICollectionView.CellRegistration<KanjiSpotlightReadingsCell, Void> {
            [weak self] cell, _, _ in
            guard let self else { return }
            cell.configure(on: self.onReading, kun: self.kunReading)
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
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.layoutIfNeeded()

        let measured = collectionView.collectionViewLayout.collectionViewContentSize.height
        let target = max(measured.rounded(.up) + 4, 1)
        collectionHeightConstraint.constant = target

        if abs(previousHeight - target) > 0.5 {
            setNeedsLayout()
        }
    }

    func configure(subject: KanjiSpotlightSubject) {
        guard let character = subject.character.first else { return }
        heroView.configure(character: character, meaning: subject.badgeMeaning)

        let readings = subject.detail.spotlightReadingLines
        onReading = readings.on
        kunReading = readings.kun

        collectionView.reloadData()
        collectionView.collectionViewLayout.invalidateLayout()
        setNeedsLayout()
        layoutIfNeeded()
    }

    func applyBadgeMeaning(_ meaning: String) {
        heroView.applyMeaning(meaning)
    }

    func badgeContains(point: CGPoint, in coordinateSpace: UIView) -> Bool {
        heroView.badgeContains(point: point, in: coordinateSpace)
    }
}

extension KanjiSpotlightKanjiCardView: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        1
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        collectionView.dequeueConfiguredReusableCell(
            using: readingsCellRegistration,
            for: indexPath,
            item: ()
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

// MARK: - Readings cell (On + Kun with romaji)

private final class KanjiSpotlightReadingsCell: UICollectionViewListCell {
    private let rowStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        rowStack.axis = .horizontal
        rowStack.alignment = .firstBaseline
        rowStack.spacing = KanjiSpotlightCardMetrics.inset(16)
        rowStack.distribution = .fillEqually
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: KanjiSpotlightCardMetrics.inset(8)
            ),
            rowStack.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -KanjiSpotlightCardMetrics.inset(8)
            ),
            rowStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }

    func configure(on: String?, kun: String?) {
        rowStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let on, !on.isEmpty {
            rowStack.addArrangedSubview(readingGroup(title: "On", value: on))
        }
        if let kun, !kun.isEmpty {
            rowStack.addArrangedSubview(readingGroup(title: "Kun", value: kun))
        }
        if rowStack.arrangedSubviews.isEmpty {
            rowStack.addArrangedSubview(readingGroup(title: "Reading", value: "—"))
        }
    }

    private func readingGroup(title: String, value: String) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: KanjiSpotlightCardMetrics.size(10), weight: .semibold)
        titleLabel.textColor = .tertiaryLabel

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: KanjiSpotlightCardMetrics.size(13), weight: .medium)
        valueLabel.textColor = .label
        valueLabel.numberOfLines = 2
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7
        valueLabel.lineBreakMode = .byWordWrapping

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        return stack
    }
}

// MARK: - Compound / verb showcase slide

final class KanjiSpotlightEntryCardView: UIView {
    private let titleLabel = UILabel()
    private let wordHero = KanjiDecompositionWordHeroCard(
        fixedWidth: KanjiSpotlightCardMetrics.exampleHeroWidth,
        heightToWidthRatio: 1.0
    )
    private let glossLabel = UILabel()

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

        titleLabel.font = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .systemFont(ofSize: 24, weight: .bold)
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
        contentStack.setCustomSpacing(32, after: titleLabel)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)
        installKanjiSpotlightWatermark(in: self)

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

    func configure(item: KanjiSpotlightShowcaseItem, exampleNumber: Int) {
        titleLabel.text = "Example \(exampleNumber)"
        glossLabel.text = item.gloss
        // Same centered furigana word hero as Kanji Decomposition's combined reveal.
        wordHero.configure(expression: item.expression, showFurigana: true)
    }
}
