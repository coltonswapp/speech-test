//
//  KanjiSpotlightCardViews.swift
//  shizen
//
//  Card faces for the Kanji Spotlight pager: subject kanji + meanings, then
//  one slide per curated compound/verb. Reuses decomposition hero chrome and
//  ExperimentPalette so export frames match sibling kanji slideshows.
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
    static let heroWidth: CGFloat = 118
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

private final class KanjiSpotlightHeroCard: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        clipsToBounds = false
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        layer.masksToBounds = false
        backgroundColor = ExperimentPalette.cardSurface
        layer.borderWidth = ExperimentCardStroke.normalWidth
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 1)
        applyBorderColor()
        applyShadowOpacity()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 10).cgPath
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyBorderColor()
        applyShadowOpacity()
        setNeedsLayout()
    }

    private func applyBorderColor() {
        layer.borderColor = ExperimentPalette.cardBorder
            .resolvedColor(with: traitCollection).cgColor
    }

    private func applyShadowOpacity() {
        layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.35 : 0.08
    }
}

// MARK: - Subject kanji slide (meanings + readings)

final class KanjiSpotlightKanjiCardView: UIView {
    private enum Section: Int, CaseIterable {
        case meanings
        case readings

        var title: String {
            switch self {
            case .meanings: return "Meanings"
            case .readings: return "Readings"
            }
        }
    }

    private let eyebrowLabel = UILabel()
    private let heroView = KanjiDecompositionCharacterHeroView(
        layoutIdentifier: .character(index: 0),
        badgePlacement: .trailingEdgeCentered
    )
    private let contentStack = UIStackView()
    private var collectionView: UICollectionView!
    private var collectionHeightConstraint: NSLayoutConstraint!

    private var meanings: [String] = []
    private var onReading: String?
    private var kunReading: String?

    private var headerRegistration: UICollectionView.SupplementaryRegistration<UICollectionViewListCell>!
    private var meaningCellRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, Int>!
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

        eyebrowLabel.text = "Kanji spotlight"
        eyebrowLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        eyebrowLabel.textColor = .secondaryLabel
        eyebrowLabel.textAlignment = .center

        configureCollectionView()

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(eyebrowLabel)
        contentStack.addArrangedSubview(heroView)
        contentStack.addArrangedSubview(collectionView)
        contentStack.setCustomSpacing(18, after: eyebrowLabel)
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
        ) { [weak self] supplementaryView, _, indexPath in
            guard let self, let section = Section(rawValue: indexPath.section) else { return }
            var configuration = supplementaryView.defaultContentConfiguration()
            configuration.text = section.title.uppercased()
            configuration.textProperties.font = .systemFont(
                ofSize: KanjiSpotlightCardMetrics.size(11),
                weight: .semibold
            )
            configuration.textProperties.color = .secondaryLabel
            supplementaryView.contentConfiguration = configuration
        }

        meaningCellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Int> {
            [weak self] cell, _, row in
            guard let self, row < self.meanings.count else { return }
            var configuration = cell.defaultContentConfiguration()
            configuration.text = self.meanings[row]
            configuration.textProperties.font = .systemFont(
                ofSize: KanjiSpotlightCardMetrics.size(15),
                weight: .medium
            )
            cell.contentConfiguration = configuration
        }

        readingsCellRegistration = UICollectionView.CellRegistration<KanjiSpotlightReadingsCell, Void> {
            [weak self] cell, _, _ in
            guard let self else { return }
            cell.configure(on: self.onReading, kun: self.kunReading)
        }

        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, layoutEnvironment in
            guard let self, Section(rawValue: sectionIndex) != nil else { return nil }
            var listConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            listConfiguration.headerMode = self.rowCount(for: sectionIndex) > 0 ? .supplementary : .none
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

    private func rowCount(for sectionIndex: Int) -> Int {
        guard let section = Section(rawValue: sectionIndex) else { return 0 }
        switch section {
        case .meanings: return meanings.count
        case .readings: return 1
        }
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

        meanings = Array(subject.detail.meaningList.prefix(4))
        let readings = subject.detail.spotlightReadingLines
        onReading = readings.on
        kunReading = readings.kun

        collectionView.reloadData()
        collectionView.collectionViewLayout.invalidateLayout()
        setNeedsLayout()
        layoutIfNeeded()
    }
}

extension KanjiSpotlightKanjiCardView: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        Section.allCases.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        rowCount(for: section)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            fatalError("Unexpected section")
        }
        switch section {
        case .meanings:
            return collectionView.dequeueConfiguredReusableCell(
                using: meaningCellRegistration,
                for: indexPath,
                item: indexPath.item
            )
        case .readings:
            return collectionView.dequeueConfiguredReusableCell(
                using: readingsCellRegistration,
                for: indexPath,
                item: ()
            )
        }
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
    private let eyebrowLabel = UILabel()
    private let readingLabel = UILabel()
    private let heroCard = KanjiSpotlightHeroCard()
    private let wordLabel = FuriganaTranscriptLabel()
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

        eyebrowLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        eyebrowLabel.textColor = .secondaryLabel
        eyebrowLabel.textAlignment = .center

        readingLabel.font = UIFontMetrics(forTextStyle: .title3).scaledFont(
            for: .systemFont(ofSize: 20, weight: .semibold)
        )
        readingLabel.textColor = .label
        readingLabel.textAlignment = .center
        readingLabel.numberOfLines = 2
        readingLabel.adjustsFontSizeToFitWidth = true
        readingLabel.minimumScaleFactor = 0.75

        wordLabel.clipsToBounds = false
        wordLabel.numberOfLines = 1
        wordLabel.translatesAutoresizingMaskIntoConstraints = false
        heroCard.translatesAutoresizingMaskIntoConstraints = false
        heroCard.addSubview(wordLabel)

        glossLabel.font = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .systemFont(ofSize: 22, weight: .semibold)
        )
        glossLabel.textColor = .label
        glossLabel.textAlignment = .center
        glossLabel.numberOfLines = 3
        glossLabel.lineBreakMode = .byWordWrapping
        glossLabel.adjustsFontSizeToFitWidth = true
        glossLabel.minimumScaleFactor = 0.7

        let header = UIStackView(arrangedSubviews: [eyebrowLabel, readingLabel])
        header.axis = .vertical
        header.alignment = .fill
        header.spacing = 8

        let contentStack = UIStackView(arrangedSubviews: [header, heroCard, glossLabel])
        contentStack.axis = .vertical
        contentStack.alignment = .center
        contentStack.spacing = 22
        contentStack.setCustomSpacing(28, after: header)
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

            heroCard.widthAnchor.constraint(equalToConstant: 220),
            heroCard.heightAnchor.constraint(equalTo: heroCard.widthAnchor, multiplier: 0.72),

            wordLabel.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: 12),
            wordLabel.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor, constant: -12),
            wordLabel.centerYAnchor.constraint(equalTo: heroCard.centerYAnchor),

            header.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            glossLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
        ])
    }

    func configure(item: KanjiSpotlightShowcaseItem, subjectCharacter: String) {
        switch item.kind {
        case .compound:
            eyebrowLabel.text = "Compound · \(subjectCharacter)"
        case .verb:
            eyebrowLabel.text = "Verb · \(subjectCharacter)"
        }
        readingLabel.text = item.readingLine
        glossLabel.text = item.gloss

        let font = UIFont.systemFont(ofSize: 36, weight: .bold)
        JapaneseFuriganaBuilder.applyScrubDisplay(
            to: wordLabel,
            attributed: JapaneseFuriganaBuilder.attributedString(
                for: item.expression,
                font: font,
                textColor: .label
            ),
            contentInsets: UIEdgeInsets(
                top: JapaneseFuriganaBuilder.wordDetailRubyTopInset(for: font),
                left: 0,
                bottom: 2,
                right: 0
            )
        )
    }
}
