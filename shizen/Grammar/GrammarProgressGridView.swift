//
//  GrammarProgressGridView.swift
//  shizen
//
//  Full-width N5 grammar progress heatmap for the grammar tab header.
//

import UIKit

// MARK: - Square styling

enum GrammarProgressSquareStyle {

    static let grammarBase = UIColor(red: 0.45, green: 0.28, blue: 0.92, alpha: 1)

    static let unstudiedFill = KanaProgressSquareStyle.unstudiedFill

    static func fillColor(level: GrammarPointProgressLevel) -> UIColor {
        switch level {
        case .new:
            return unstudiedFill
        case .seen:
            return grammarBase.withAlphaComponent(0.45)
        case .known:
            return grammarBase
        }
    }
}

enum GrammarPointProgressLevel: Equatable {
    case new
    case seen
    case known
}

// MARK: - Grid view

enum GrammarProgressGridLayout {

    static let gridSpacing: CGFloat = 4
    static let cardHorizontalInset: CGFloat = 12
    static let interCellSpacing: CGFloat = 10

    struct Metrics: Equatable {
        let columnCount: Int
        let spacing: CGFloat
        let squareSide: CGFloat
        let gridWidth: CGFloat
        let gridHeight: CGFloat
    }

    static func metrics(forContentWidth contentWidth: CGFloat, itemCount: Int) -> Metrics {
        let spacing = gridSpacing
        let cardInset = cardHorizontalInset

        // Match the square size from one kana progress tile.
        let kanaItemWidth = floor(max(contentWidth - interCellSpacing, 0) / 2)
        let kanaGridWidth = max(0, kanaItemWidth - cardInset * 2)
        let referenceColumns = CGFloat(KanaProgressSquareStyle.columnCount)
        let referenceSquareSide = max(
            0,
            (kanaGridWidth - max(referenceColumns - 1, 0) * spacing) / referenceColumns
        )

        let gridWidth = max(0, contentWidth - cardInset * 2)
        guard itemCount > 0 else {
            return Metrics(
                columnCount: KanaProgressSquareStyle.columnCount,
                spacing: spacing,
                squareSide: referenceSquareSide,
                gridWidth: gridWidth,
                gridHeight: 0
            )
        }

        let columnCount = max(
            KanaProgressSquareStyle.columnCount,
            referenceSquareSide > 0
                ? Int(floor((gridWidth + spacing) / (referenceSquareSide + spacing)))
                : KanaProgressSquareStyle.columnCount
        )
        let rows = Int(ceil(Double(itemCount) / Double(columnCount)))
        let squareSide = referenceSquareSide > 0
            ? referenceSquareSide
            : max(0, (gridWidth - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount))
        let gridHeight = CGFloat(rows) * squareSide + CGFloat(max(rows - 1, 0)) * spacing

        return Metrics(
            columnCount: columnCount,
            spacing: spacing,
            squareSide: squareSide,
            gridWidth: gridWidth,
            gridHeight: gridHeight
        )
    }
}

final class GrammarProgressGridView: UIView {

    var points: [GrammarPoint] = [] {
        didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() }
    }

    var progressLevels: [String: GrammarPointProgressLevel] = [:] {
        didSet { setNeedsDisplay() }
    }

    var onSelectPoint: ((GrammarPoint) -> Void)?

    var layoutMetrics = GrammarProgressGridLayout.metrics(forContentWidth: 0, itemCount: 0) {
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
        isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: layoutMetrics.gridHeight)
    }

    override func draw(_ rect: CGRect) {
        let squareSide = layoutMetrics.squareSide
        guard squareSide > 0 else { return }

        let spacing = layoutMetrics.spacing
        let columns = layoutMetrics.columnCount
        let cornerRadius = max(squareSide * 0.22, 1)

        for (index, point) in points.enumerated() {
            let column = index % columns
            let row = index / columns
            let x = CGFloat(column) * (squareSide + spacing)
            let y = CGFloat(row) * (squareSide + spacing)
            let squareRect = CGRect(x: x, y: y, width: squareSide, height: squareSide)

            let path = UIBezierPath(roundedRect: squareRect, cornerRadius: cornerRadius)
            GrammarProgressSquareStyle.fillColor(
                level: progressLevels[point.id, default: .new]
            ).setFill()
            path.fill()
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, let point = point(at: gesture.location(in: self)) else { return }
        onSelectPoint?(point)
    }

    private func point(at location: CGPoint) -> GrammarPoint? {
        let squareSide = layoutMetrics.squareSide
        guard squareSide > 0 else { return nil }

        let spacing = layoutMetrics.spacing
        let columns = layoutMetrics.columnCount
        let cellStride = squareSide + spacing

        let column = Int((location.x + spacing * 0.5) / cellStride)
        let row = Int((location.y + spacing * 0.5) / cellStride)
        guard column >= 0, row >= 0 else { return nil }

        let index = row * columns + column
        guard points.indices.contains(index) else { return nil }

        let x = CGFloat(column) * cellStride
        let y = CGFloat(row) * cellStride
        let squareRect = CGRect(x: x, y: y, width: squareSide, height: squareSide)
        guard squareRect.contains(location) else { return nil }

        return points[index]
    }
}

// MARK: - Card wrapper

final class GrammarProgressGridCardView: UIView {

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let gridView = GrammarProgressGridView()
    private var gridHeightConstraint: NSLayoutConstraint?
    var onSelectPoint: ((GrammarPoint) -> Void)? {
        didSet { gridView.onSelectPoint = onSelectPoint }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyGridWidth(preferredGridWidth)
    }

    private var preferredGridWidth: CGFloat = 0

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = ExperimentPalette.cardSurface
        cardView.layer.cornerRadius = 14
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = ExperimentPalette.cardBorder.cgColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = .secondaryLabel

        gridView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(cardView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(gridView)

        let gridHeight = gridView.heightAnchor.constraint(equalToConstant: 1)
        gridHeightConstraint = gridHeight

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),

            gridView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            gridView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            gridView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            gridHeight,
            cardView.bottomAnchor.constraint(equalTo: gridView.bottomAnchor, constant: 12),
        ])
    }

    func applyGridWidth(_ width: CGFloat) {
        preferredGridWidth = width
        let resolvedWidth = gridView.bounds.width > 0 ? gridView.bounds.width : width
        guard resolvedWidth > 0 else { return }

        gridView.layoutWidth = resolvedWidth
        let metrics = GrammarProgressGridLayout.metrics(
            forContentWidth: resolvedWidth + GrammarProgressGridLayout.cardHorizontalInset * 2,
            itemCount: gridView.points.count
        )
        gridView.layoutMetrics = metrics

        if gridHeightConstraint?.constant != metrics.gridHeight {
            gridHeightConstraint?.constant = metrics.gridHeight
            gridView.invalidateIntrinsicContentSize()
        }
        gridView.setNeedsDisplay()
    }

    func configure(
        points: [GrammarPoint],
        progressLevels: [String: GrammarPointProgressLevel],
        title: String,
        contentWidth: CGFloat
    ) {
        titleLabel.text = title
        gridView.points = points
        gridView.progressLevels = progressLevels
        applyGridWidth(max(0, contentWidth - GrammarProgressGridLayout.cardHorizontalInset * 2))
    }
}

// MARK: - Progress helpers

enum GrammarProgressGridSupport {

    static func progressLevels(
        for points: [GrammarPoint],
        masteryStore: GrammarMasteryStore
    ) -> [String: GrammarPointProgressLevel] {
        Dictionary(uniqueKeysWithValues: points.map { point in
            let level: GrammarPointProgressLevel
            switch masteryStore.masteryState(for: point.id) {
            case .new: level = .new
            case .seen: level = .seen
            case .known: level = .known
            }
            return (point.id, level)
        })
    }

    static func cardTitle(known: Int, total: Int) -> String {
        "N5 Grammar · \(known)/\(total) known"
    }
}
