//
//  KanjiDetailViewController.swift
//  shizen
//
//  Detail screen for a single kanji: a centered glyph hero card, an inset-grouped
//  info section (JLPT, strokes, frequency, on/kun readings), and an inset-grouped
//  collection of compounds sorted by popularity (rendered with furigana).
//

import UIKit

// MARK: - Hero card

private final class KanjiDetailCard: UIView {
    private let glyphLabel = UILabel()

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

        glyphLabel.translatesAutoresizingMaskIntoConstraints = false
        glyphLabel.textAlignment = .center
        glyphLabel.adjustsFontForContentSizeCategory = true
        glyphLabel.adjustsFontSizeToFitWidth = true
        glyphLabel.minimumScaleFactor = 0.5
        glyphLabel.textColor = .label
        let metrics = UIFontMetrics(forTextStyle: .largeTitle)
        glyphLabel.font = metrics.scaledFont(for: .systemFont(ofSize: 64, weight: .bold))
        addSubview(glyphLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalTo: widthAnchor, multiplier: 1.24),
            glyphLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            glyphLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            glyphLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(character: String) {
        glyphLabel.text = character
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

private final class KanjiDetailHeroCell: UICollectionViewCell {
    let card = KanjiDetailCard()

    private static let cardWidth: CGFloat = 118
    private static let verticalPadding: CGFloat = 24

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        var background = UIBackgroundConfiguration.clear()
        background.backgroundColor = .clear
        backgroundConfiguration = background

        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.verticalPadding),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Self.verticalPadding),
            card.widthAnchor.constraint(equalToConstant: Self.cardWidth),
        ])
    }

    func configure(character: String) {
        card.configure(character: character)
    }
}

// MARK: - Compound list cell (furigana)

private final class KanjiCompoundListCell: UICollectionViewListCell {
    private let furiganaLabel = FuriganaTranscriptLabel()
    private let glossLabel = UILabel()
    private let stack = UIStackView()

    private static let expressionFont = UIFont.preferredFont(forTextStyle: .title3)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        furiganaLabel.clipsToBounds = false
        furiganaLabel.numberOfLines = 1

        glossLabel.font = .preferredFont(forTextStyle: .subheadline)
        glossLabel.textColor = .secondaryLabel
        glossLabel.numberOfLines = 2

        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(furiganaLabel)
        stack.addArrangedSubview(glossLabel)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }

    func configure(with entry: JMDictEntry) {
        let font = Self.expressionFont
        JapaneseFuriganaBuilder.applyScrubDisplay(
            to: furiganaLabel,
            attributed: JapaneseFuriganaBuilder.attributedString(
                for: entry.expression,
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

        let gloss = entry.glossary
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? entry.glossary
        glossLabel.text = gloss

        accessories = [.disclosureIndicator()]
    }
}

// MARK: - View controller

final class KanjiDetailViewController: UIViewController {

    private let character: String
    private let detail: KanjidicDetail?
    private var compounds: [JMDictEntry] = []
    private var infoRows: [(title: String, value: String)] = []

    private var collectionView: UICollectionView!

    private var headerRegistration: UICollectionView.SupplementaryRegistration<UICollectionViewListCell>!
    private var heroCellRegistration: UICollectionView.CellRegistration<KanjiDetailHeroCell, Void>!
    private var infoCellRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, Int>!
    private var compoundCellRegistration: UICollectionView.CellRegistration<KanjiCompoundListCell, Int>!

    private enum Section: Int, CaseIterable {
        case hero
        case info
        case compounds

        var title: String? {
            switch self {
            case .hero: return nil
            case .info: return "Info"
            case .compounds: return "Compounds"
            }
        }
    }

    init(character: String) {
        self.character = character.trimmingCharacters(in: .whitespacesAndNewlines)
        self.detail = KanjidicStore.shared.detail(forKanji: self.character)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = character
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemGroupedBackground

        compounds = JMDictStore.shared.compounds(forSurface: character, limit: 15)
        infoRows = Self.buildInfoRows(character: character, detail: detail)

        configureCollectionView()
        layoutCollectionView()
    }

    // MARK: - Data shaping

    private static func buildInfoRows(character: String, detail: KanjidicDetail?) -> [(String, String)] {
        var rows: [(String, String)] = []
        guard let detail else { return rows }

        let meaningList = detail.meaningList
        if !meaningList.isEmpty {
            rows.append(("Meaning", meaningList.joined(separator: ", ")))
        }
        let on = detail.onReadingList
        if !on.isEmpty {
            rows.append(("On", on.joined(separator: "、")))
        }
        let kun = detail.kunReadingList
        if !kun.isEmpty {
            rows.append(("Kun", kun.joined(separator: "、")))
        }
        if let jlpt = detail.jlpt {
            rows.append(("JLPT", "N\(jlpt)"))
        }
        if let grade = detail.grade {
            rows.append(("Grade", grade <= 6 ? "\(grade)" : "Jōyō"))
        }
        if let strokes = detail.strokeCount {
            rows.append(("Strokes", "\(strokes)"))
        }
        if let freq = detail.freq {
            rows.append(("Frequency", "#\(freq)"))
        }
        return rows
    }

    // MARK: - Collection view

    private func configureCollectionView() {
        headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] supplementaryView, _, indexPath in
            guard
                let self,
                let section = self.section(at: indexPath.section),
                let title = section.title
            else { return }
            var configuration = supplementaryView.defaultContentConfiguration()
            configuration.text = title.uppercased()
            configuration.textProperties.font = .preferredFont(forTextStyle: .footnote)
            configuration.textProperties.color = .secondaryLabel
            supplementaryView.contentConfiguration = configuration
        }

        heroCellRegistration = UICollectionView.CellRegistration<KanjiDetailHeroCell, Void> {
            [weak self] cell, _, _ in
            guard let self else { return }
            cell.configure(character: self.character)
        }

        infoCellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Int> {
            [weak self] cell, _, row in
            guard let self, row < self.infoRows.count else { return }
            let info = self.infoRows[row]
            var configuration = UIListContentConfiguration.valueCell()
            configuration.text = info.title
            configuration.secondaryText = info.value
            configuration.textProperties.color = .secondaryLabel
            configuration.secondaryTextProperties.color = .label
            configuration.secondaryTextProperties.numberOfLines = 0
            cell.contentConfiguration = configuration
        }

        compoundCellRegistration = UICollectionView.CellRegistration<KanjiCompoundListCell, Int> {
            [weak self] cell, _, row in
            guard let self, row < self.compounds.count else { return }
            cell.configure(with: self.compounds[row])
        }

        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, layoutEnvironment in
            guard let self, let section = self.section(at: sectionIndex) else { return nil }
            switch section {
            case .hero:
                return InsetGroupedDetailSectionLayout.makeCompositionalHeroSection(
                    estimatedHeight: 196,
                    contentInsets: NSDirectionalEdgeInsets(top: 16, leading: 0, bottom: 20, trailing: 0)
                )
            case .info, .compounds:
                var listConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
                listConfiguration.headerMode = self.rowCount(for: sectionIndex) > 0 ? .supplementary : .none
                listConfiguration.showsSeparators = true
                return NSCollectionLayoutSection.list(
                    using: listConfiguration,
                    layoutEnvironment: layoutEnvironment
                )
            }
        }

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
    }

    private func layoutCollectionView() {
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func section(at index: Int) -> Section? {
        Section(rawValue: index)
    }

    private func rowCount(for sectionIndex: Int) -> Int {
        guard let section = section(at: sectionIndex) else { return 0 }
        switch section {
        case .hero: return 1
        case .info: return infoRows.count
        case .compounds: return compounds.count
        }
    }
}

// MARK: - Data source

extension KanjiDetailViewController: UICollectionViewDataSource {

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
        guard let section = section(at: indexPath.section) else {
            fatalError("Unexpected section")
        }
        switch section {
        case .hero:
            return collectionView.dequeueConfiguredReusableCell(
                using: heroCellRegistration,
                for: indexPath,
                item: ()
            )
        case .info:
            return collectionView.dequeueConfiguredReusableCell(
                using: infoCellRegistration,
                for: indexPath,
                item: indexPath.item
            )
        case .compounds:
            return collectionView.dequeueConfiguredReusableCell(
                using: compoundCellRegistration,
                for: indexPath,
                item: indexPath.item
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

// MARK: - Delegate

extension KanjiDetailViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        section(at: indexPath.section) == .compounds
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard section(at: indexPath.section) == .compounds,
              indexPath.item < compounds.count else { return }
        collectionView.deselectItem(at: indexPath, animated: true)
        let entry = compounds[indexPath.item]
        WordDictionaryDetailSheetPresenter.present(surface: entry.expression, from: self)
    }
}
