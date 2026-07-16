//
//  KanaDetailViewController.swift
//  shizen
//
//  Detail screen for a single hiragana glyph (DEBUG).
//


import UIKit

// MARK: - Hero cell

private final class KanaDetailHeroCell: UICollectionViewCell {

    let card = KanaCard()
    let playButton = UIButton(type: .system)
    private let playGlyphView = UIImageView()
    var onPlay: (() -> Void)?

    private static let cardWidth: CGFloat = 118
    private static let verticalPadding: CGFloat = 24
    private static let playButtonSize: CGFloat = 50
    private static let playGlyphColor = UIColor.systemYellow

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

        card.setPresentation(.detailHero)
        card.translatesAutoresizingMaskIntoConstraints = false

        // Glass style ignores `baseForegroundColor` for the symbol; tint a dedicated image view instead.
        var playConfig = UIButton.Configuration.glass()
        playConfig.cornerStyle = .capsule
        playButton.configuration = playConfig
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.accessibilityLabel = "Play pronunciation"
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        playGlyphView.image = UIImage(systemName: "speaker.wave.2.fill", withConfiguration: symbolConfig)?
            .withRenderingMode(.alwaysTemplate)
        playGlyphView.tintColor = Self.playGlyphColor
        playGlyphView.preferredSymbolConfiguration = symbolConfig
        playGlyphView.contentMode = .scaleAspectFit
        playGlyphView.isUserInteractionEnabled = false
        playGlyphView.translatesAutoresizingMaskIntoConstraints = false
        playButton.addSubview(playGlyphView)

        contentView.addSubview(card)
        contentView.addSubview(playButton)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.verticalPadding),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Self.verticalPadding),
            card.widthAnchor.constraint(equalToConstant: Self.cardWidth),

            playButton.centerXAnchor.constraint(equalTo: card.trailingAnchor),
            playButton.centerYAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            playButton.widthAnchor.constraint(equalToConstant: Self.playButtonSize),
            playButton.heightAnchor.constraint(equalToConstant: Self.playButtonSize),

            playGlyphView.centerXAnchor.constraint(equalTo: playButton.centerXAnchor),
            playGlyphView.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            playGlyphView.widthAnchor.constraint(equalToConstant: 26),
            playGlyphView.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playButton.bringSubviewToFront(playGlyphView)
    }

    func configure(kana: String, romaji: String) {
        card.configure(kana: kana, romaji: romaji)
    }

    @objc private func playTapped() {
        onPlay?()
    }
}

// MARK: - View controller

final class KanaDetailViewController: UIViewController {

    private let item: KanaDetailItem
    private let pronunciationPlayer = KanaPronunciationPlayer()

    private var collectionView: UICollectionView!

    private var headerRegistration: UICollectionView.SupplementaryRegistration<UICollectionViewListCell>!
    private var heroCellRegistration: UICollectionView.CellRegistration<KanaDetailHeroCell, Void>!
    private var soundsLikeCellRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, Void>!
    private var vocabCellRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, Int>!

    private enum Section: Int, CaseIterable {
        case hero
        case soundsLike
        case vocabulary

        var title: String? {
            switch self {
            case .hero: return nil
            case .soundsLike: return "Sounds like"
            case .vocabulary: return "Vocabulary"
            }
        }
    }

    init(kana: String, romaji: String) {
        item = KanaDetailCatalog.item(kana: kana, romaji: romaji)
        super.init(nibName: nil, bundle: nil)
    }

    init(item: KanaDetailItem) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = item.kana
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemGroupedBackground

        configureCollectionView()
        layoutCollectionView()
    }

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

        heroCellRegistration = UICollectionView.CellRegistration<KanaDetailHeroCell, Void> {
            [weak self] cell, _, _ in
            guard let self else { return }
            cell.configure(kana: self.item.kana, romaji: self.item.romaji)
            cell.onPlay = { [weak self] in
                self?.playPronunciation()
            }
        }

        soundsLikeCellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Void> {
            [weak self] cell, _, _ in
            guard let self else { return }
            var configuration = cell.defaultContentConfiguration()
            configuration.text = self.item.soundsLike
            configuration.textProperties.font = .preferredFont(forTextStyle: .body)
            configuration.textProperties.color = .label
            cell.contentConfiguration = configuration
        }

        vocabCellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Int> {
            [weak self] cell, _, row in
            guard let self, row < self.item.vocabulary.count else { return }
            var configuration = cell.defaultContentConfiguration()
            configuration.text = self.item.vocabulary[row].listLine
            configuration.textProperties.font = .preferredFont(forTextStyle: .body)
            configuration.textProperties.color = .label
            configuration.textProperties.numberOfLines = 1
            configuration.textProperties.lineBreakMode = .byTruncatingTail
            cell.contentConfiguration = configuration
        }

        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, layoutEnvironment in
            guard let self, let section = self.section(at: sectionIndex) else { return nil }
            switch section {
            case .hero:
                return InsetGroupedDetailSectionLayout.makeCompositionalHeroSection(
                    estimatedHeight: 196,
                    contentInsets: NSDirectionalEdgeInsets(top: 16, leading: 0, bottom: 20, trailing: 0)
                )
            case .soundsLike, .vocabulary:
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

    private func playPronunciation() {
        pronunciationPlayer.play(kana: item.kana, languageIdentifier: "ja-JP")
    }

    private func playVocabulary(at row: Int) {
        guard row < item.vocabulary.count else { return }
        let word = item.vocabulary[row].japanese
        pronunciationPlayer.play(kana: word, languageIdentifier: "ja-JP")
    }

    private func section(at index: Int) -> Section? {
        Section(rawValue: index)
    }

    private func rowCount(for sectionIndex: Int) -> Int {
        guard let section = section(at: sectionIndex) else { return 0 }
        switch section {
        case .hero: return 1
        case .soundsLike: return item.soundsLike.isEmpty ? 0 : 1
        case .vocabulary: return item.vocabulary.count
        }
    }
}

// MARK: - Data source

extension KanaDetailViewController: UICollectionViewDataSource {

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
        case .soundsLike:
            return collectionView.dequeueConfiguredReusableCell(
                using: soundsLikeCellRegistration,
                for: indexPath,
                item: ()
            )
        case .vocabulary:
            return collectionView.dequeueConfiguredReusableCell(
                using: vocabCellRegistration,
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

extension KanaDetailViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        section(at: indexPath.section) == .vocabulary
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard section(at: indexPath.section) == .vocabulary else { return }
        collectionView.deselectItem(at: indexPath, animated: true)
        playVocabulary(at: indexPath.item)
    }
}

