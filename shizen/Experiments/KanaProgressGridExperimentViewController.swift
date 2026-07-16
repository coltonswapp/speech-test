//
//  KanaProgressGridExperimentViewController.swift
//  shizen
//
//  DEBUG experiment: side-by-side hiragana/katakana progress heatmaps in a 92-square grid.
//

import UIKit

// MARK: - Square styling

enum KanaProgressSquareStyle {

    static let columnCount = 10
    static let glyphCount = 92
    static let gridSpacing: CGFloat = 2

    static let hiraganaBase = PrimaryButton.appearance(for: .yellow).backgroundColor
    static let katakanaBase = PrimaryButton.appearance(for: .blue).backgroundColor

    static let unstudiedFill = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.06)
            : UIColor(red: 245 / 255, green: 245 / 255, blue: 245 / 255, alpha: 1)
    }

    static func fillColor(script: KanaScript, studyCount: Int) -> UIColor {
        guard studyCount > 0 else { return unstudiedFill }
        let base = script == .hiragana ? hiraganaBase : katakanaBase
        return base.withAlphaComponent(opacity(for: studyCount))
    }

    static func opacity(for studyCount: Int) -> CGFloat {
        progressFraction(for: studyCount)
    }

    static let masteryStudyCount = KanaStudyProgress.masteryCorrectCount

    static func progressFraction(for studyCount: Int) -> CGFloat {
        KanaStudyProgress.progressFraction(for: studyCount)
    }
}

// MARK: - Demo progress (DEBUG experiment preview)

enum KanaProgressGridDemo {

    private static let fillFraction = 0.6

    static func studyCounts(for glyphs: [KanaGlyph], script: KanaScript) -> [String: Int] {
        let filledCount = Int((Double(glyphs.count) * fillFraction).rounded())
        var rng = DemoRNG(seed: script == .hiragana ? 0x1111_0001 : 0x2222_0002)

        var order = Array(0 ..< glyphs.count)
        order.shuffle(using: &rng)
        let filledIndices = Set(order.prefix(filledCount))

        return Dictionary(uniqueKeysWithValues: glyphs.enumerated().map { index, glyph in
            guard filledIndices.contains(index) else { return (glyph.kana, 0) }
            let count = Int.random(in: 1 ... 5, using: &rng)
            return (glyph.kana, count)
        })
    }
}

private struct DemoRNG: RandomNumberGenerator {

    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xDEAD_BEEF : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Grid view

final class KanaProgressGridView: UIView {

    var script: KanaScript = .hiragana {
        didSet { setNeedsDisplay() }
    }

    var glyphs: [KanaGlyph] = [] {
        didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() }
    }

    var studyCounts: [String: Int] = [:] {
        didSet { setNeedsDisplay() }
    }

    var spacing: CGFloat = 4 {
        didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() }
    }

    /// Fallback width used when Auto Layout has not assigned bounds yet.
    var layoutWidth: CGFloat = 0 {
        didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .redraw
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let height = Self.gridHeight(
            forGridWidth: effectiveGridWidth,
            spacing: spacing,
            glyphCount: glyphs.count
        )
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    private var effectiveGridWidth: CGFloat {
        bounds.width > 0 ? bounds.width : layoutWidth
    }

    static func fittedSquareSide(forGridWidth width: CGFloat, spacing: CGFloat) -> CGFloat {
        let columns = CGFloat(KanaProgressSquareStyle.columnCount)
        guard width > 0 else { return 0 }
        return (width - max(columns - 1, 0) * spacing) / columns
    }

    static func gridHeight(forGridWidth width: CGFloat, spacing: CGFloat, glyphCount: Int) -> CGFloat {
        let rows = Int(ceil(Double(glyphCount) / Double(KanaProgressSquareStyle.columnCount)))
        guard rows > 0 else { return 0 }
        let squareSide = fittedSquareSide(forGridWidth: width, spacing: spacing)
        guard squareSide > 0 else { return 0 }
        return CGFloat(rows) * squareSide + CGFloat(rows - 1) * spacing
    }

    override func draw(_ rect: CGRect) {
        let width = effectiveGridWidth
        let squareSide = Self.fittedSquareSide(forGridWidth: width, spacing: spacing)
        guard squareSide > 0 else { return }

        let cornerRadius = max(squareSide * 0.22, 1)

        for (index, glyph) in glyphs.enumerated() {
            let column = index % KanaProgressSquareStyle.columnCount
            let row = index / KanaProgressSquareStyle.columnCount
            let x = CGFloat(column) * (squareSide + spacing)
            let y = CGFloat(row) * (squareSide + spacing)
            let squareRect = CGRect(x: x, y: y, width: squareSide, height: squareSide)

            let path = UIBezierPath(roundedRect: squareRect, cornerRadius: cornerRadius)
            KanaProgressSquareStyle.fillColor(
                script: script,
                studyCount: studyCounts[glyph.kana, default: 0]
            ).setFill()
            path.fill()
        }
    }
}

// MARK: - Collection cell

final class KanaProgressGridCell: UICollectionViewCell {

    static let reuseID = "KanaProgressGridCell"

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let chevronImageView = UIImageView()
    private let gridView = KanaProgressGridView()
    private var gridHeightConstraint: NSLayoutConstraint?
    private var spacing: CGFloat = 4

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = ExperimentPalette.cardSurface
        cardView.layer.cornerRadius = 14
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = ExperimentPalette.cardBorder.cgColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = .secondaryLabel

        chevronImageView.translatesAutoresizingMaskIntoConstraints = false
        chevronImageView.image = UIImage(systemName: "chevron.right")
        chevronImageView.tintColor = .tertiaryLabel
        chevronImageView.contentMode = .scaleAspectFit
        chevronImageView.setContentHuggingPriority(.required, for: .horizontal)
        chevronImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        chevronImageView.isHidden = true

        gridView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(cardView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(chevronImageView)
        cardView.addSubview(gridView)

        let gridHeight = gridView.heightAnchor.constraint(equalToConstant: 1)
        gridHeightConstraint = gridHeight

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronImageView.leadingAnchor, constant: -8),

            chevronImageView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            chevronImageView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            chevronImageView.widthAnchor.constraint(equalToConstant: 8),
            chevronImageView.heightAnchor.constraint(equalToConstant: 13),

            gridView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            gridView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            gridView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            gridHeight,
            cardView.bottomAnchor.constraint(equalTo: gridView.bottomAnchor, constant: 12),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyGridWidth(preferredGridWidth)
    }

    private var preferredGridWidth: CGFloat = 0

    func applyGridWidth(_ width: CGFloat) {
        preferredGridWidth = width
        let resolvedWidth = gridView.bounds.width > 0 ? gridView.bounds.width : width
        guard resolvedWidth > 0 else { return }

        gridView.layoutWidth = resolvedWidth

        let height = KanaProgressGridView.gridHeight(
            forGridWidth: resolvedWidth,
            spacing: spacing,
            glyphCount: KanaProgressSquareStyle.glyphCount
        )
        if gridHeightConstraint?.constant != height {
            gridHeightConstraint?.constant = height
            gridView.invalidateIntrinsicContentSize()
        }
        gridView.setNeedsDisplay()
    }

    func configure(
        script: KanaScript,
        glyphs: [KanaGlyph],
        studyCounts: [String: Int],
        spacing: CGFloat,
        gridWidth: CGFloat,
        showsChevron: Bool = false
    ) {
        self.spacing = spacing
        chevronImageView.isHidden = !showsChevron

        let sampleGlyph = glyphs.first?.kana ?? (script == .hiragana ? "あ" : "ア")
        let scriptName = script == .hiragana ? "Hiragana" : "Katakana"
        titleLabel.text = "\(scriptName) • \(sampleGlyph)"

        gridView.script = script
        gridView.glyphs = glyphs
        gridView.studyCounts = studyCounts
        gridView.spacing = spacing
        applyGridWidth(gridWidth)
    }
}

// MARK: - View controller

final class KanaProgressGridExperimentViewController: UIViewController {

    private enum ScriptItem: Int, CaseIterable {
        case hiragana
        case katakana

        var script: KanaScript {
            switch self {
            case .hiragana: return .hiragana
            case .katakana: return .katakana
            }
        }
    }

    private let progressStore: KanaProgressStore
    private let collectionView: UICollectionView
    private let sliderPanel = UIView()
    private let sliderLabel = UILabel()
    private let squareSizeSlider = UISlider()

    private var gridSpacing: CGFloat = 4 {
        didSet {
            let clamped = min(max(gridSpacing, Self.minGridSpacing), Self.maxGridSpacing)
            if clamped != gridSpacing {
                gridSpacing = clamped
                return
            }
            guard oldValue != gridSpacing else { return }
            updateSliderLabel()
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.reloadData()
        }
    }

    private static let minGridSpacing: CGFloat = 1
    private static let maxGridSpacing: CGFloat = 5
    private static let cardHorizontalInset: CGFloat = 12
    private static let interCellSpacing: CGFloat = 10
    private static let horizontalInset: CGFloat = 16
    private static let cardHeaderTopInset: CGFloat = 10
    private static let cardTitleToGridSpacing: CGFloat = 8
    private static let cardBottomInset: CGFloat = 12
    private static let cardTitleHeight: CGFloat = 18

    private var lastLaidOutCollectionWidth: CGFloat = 0

    init(progressStore: KanaProgressStore = .shared) {
        self.progressStore = progressStore
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewLayout())
        super.init(nibName: nil, bundle: nil)
        self.collectionView.collectionViewLayout = makeLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Kana progress"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground

        configureCollectionView()
        configureSliderPanel()
        layoutViews()
        reloadProgress()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        progressStore.reload()
        reloadProgress()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = collectionView.bounds.width
        guard width > 0, width != lastLaidOutCollectionWidth else { return }
        lastLaidOutCollectionWidth = width
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.reloadData()
    }

    private func itemWidth(forCollectionWidth totalWidth: CGFloat) -> CGFloat {
        guard totalWidth > 0 else { return 0 }
        let available = totalWidth - Self.horizontalInset * 2 - Self.interCellSpacing
        return floor(max(available, 0) / 2)
    }

    private func gridWidth(forCollectionWidth totalWidth: CGFloat) -> CGFloat {
        max(0, itemWidth(forCollectionWidth: totalWidth) - Self.cardHorizontalInset * 2)
    }

    private func configureCollectionView() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isScrollEnabled = false
        collectionView.register(KanaProgressGridCell.self, forCellWithReuseIdentifier: KanaProgressGridCell.reuseID)
    }

    private func configureSliderPanel() {
        sliderPanel.translatesAutoresizingMaskIntoConstraints = false
        sliderPanel.backgroundColor = ExperimentPalette.cardSurface
        sliderPanel.layer.cornerRadius = 14
        sliderPanel.layer.cornerCurve = .continuous
        sliderPanel.layer.borderWidth = 1
        sliderPanel.layer.borderColor = ExperimentPalette.cardBorder.cgColor

        sliderLabel.translatesAutoresizingMaskIntoConstraints = false
        sliderLabel.font = .preferredFont(forTextStyle: .footnote)
        sliderLabel.textColor = .secondaryLabel

        squareSizeSlider.translatesAutoresizingMaskIntoConstraints = false
        squareSizeSlider.minimumValue = Float(Self.minGridSpacing)
        squareSizeSlider.maximumValue = Float(Self.maxGridSpacing)
        squareSizeSlider.value = Float(gridSpacing)
        squareSizeSlider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.gridSpacing = CGFloat(self.squareSizeSlider.value.rounded())
        }, for: .valueChanged)

        sliderPanel.addSubview(sliderLabel)
        sliderPanel.addSubview(squareSizeSlider)
    }

    private func layoutViews() {
        view.addSubview(collectionView)
        view.addSubview(sliderPanel)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: sliderPanel.topAnchor, constant: -16),

            sliderPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.horizontalInset),
            sliderPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.horizontalInset),
            sliderPanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            sliderLabel.topAnchor.constraint(equalTo: sliderPanel.topAnchor, constant: 12),
            sliderLabel.leadingAnchor.constraint(equalTo: sliderPanel.leadingAnchor, constant: 14),
            sliderLabel.trailingAnchor.constraint(equalTo: sliderPanel.trailingAnchor, constant: -14),

            squareSizeSlider.topAnchor.constraint(equalTo: sliderLabel.bottomAnchor, constant: 6),
            squareSizeSlider.leadingAnchor.constraint(equalTo: sliderPanel.leadingAnchor, constant: 14),
            squareSizeSlider.trailingAnchor.constraint(equalTo: sliderPanel.trailingAnchor, constant: -14),
            squareSizeSlider.bottomAnchor.constraint(equalTo: sliderPanel.bottomAnchor, constant: -12),
        ])

        updateSliderLabel()
    }

    private func updateSliderLabel() {
        sliderLabel.text = String(format: "Square spacing · %.0f pt", gridSpacing)
    }

    private func reloadProgress() {
        collectionView.reloadData()
    }

    private func studyCounts(for glyphs: [KanaGlyph], script: KanaScript) -> [String: Int] {
        let stored = Dictionary(uniqueKeysWithValues: glyphs.map { glyph in
            (glyph.kana, progressStore.studyCount(for: glyph.kana))
        })
        let demo = KanaProgressGridDemo.studyCounts(for: glyphs, script: script)
        return Dictionary(uniqueKeysWithValues: glyphs.map { glyph in
            (glyph.kana, max(stored[glyph.kana, default: 0], demo[glyph.kana, default: 0]))
        })
    }

    private func cellHeight(for itemWidth: CGFloat) -> CGFloat {
        guard itemWidth > 0 else { return 1 }
        let gridWidth = itemWidth - Self.cardHorizontalInset * 2
        let gridHeight = KanaProgressGridView.gridHeight(
            forGridWidth: gridWidth,
            spacing: gridSpacing,
            glyphCount: KanaProgressSquareStyle.glyphCount
        )
        let cardChrome = Self.cardHeaderTopInset
            + Self.cardTitleHeight
            + Self.cardTitleToGridSpacing
            + Self.cardBottomInset
        return cardChrome + gridHeight
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] _, environment in
            guard let self else { return nil }

            let totalWidth = environment.container.effectiveContentSize.width
            guard totalWidth > 0 else {
                let emptyItem = NSCollectionLayoutItem(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(0.5),
                        heightDimension: .absolute(1)
                    )
                )
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1),
                        heightDimension: .absolute(1)
                    ),
                    subitems: [emptyItem, emptyItem]
                )
                return NSCollectionLayoutSection(group: group)
            }

            let available = totalWidth - Self.horizontalInset * 2 - Self.interCellSpacing
            let itemWidth = floor(available / 2)
            let itemHeight = self.cellHeight(for: itemWidth)

            let itemSize = NSCollectionLayoutSize(
                widthDimension: .absolute(itemWidth),
                heightDimension: .absolute(itemHeight)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(itemHeight)
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item, item])
            group.interItemSpacing = .fixed(Self.interCellSpacing)

            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(
                top: 0,
                leading: Self.horizontalInset,
                bottom: 0,
                trailing: Self.horizontalInset
            )
            return section
        }
    }
}

extension KanaProgressGridExperimentViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        ScriptItem.allCases.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: KanaProgressGridCell.reuseID,
            for: indexPath
        ) as! KanaProgressGridCell

        let item = ScriptItem.allCases[indexPath.item]
        let glyphs = KanaCurriculum.progressGridGlyphs(script: item.script)
        let gridWidth = gridWidth(forCollectionWidth: collectionView.bounds.width)
        cell.configure(
            script: item.script,
            glyphs: glyphs,
            studyCounts: studyCounts(for: glyphs, script: item.script),
            spacing: gridSpacing,
            gridWidth: gridWidth
        )
        return cell
    }
}

extension KanaProgressGridExperimentViewController: UICollectionViewDelegate {

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        (cell as? KanaProgressGridCell)?.applyGridWidth(gridWidth(forCollectionWidth: collectionView.bounds.width))
    }
}

// MARK: - Shared grid helpers

enum KanaProgressGridSupport {

    static func studyCounts(
        for glyphs: [KanaGlyph],
        progressStore: KanaProgressStore
    ) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: glyphs.map { glyph in
            (glyph.kana, progressStore.studyCount(for: glyph.kana))
        })
    }
}
