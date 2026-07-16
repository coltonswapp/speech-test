//
//  DialogueProgressGridView.swift
//  shizen
//
//  Daily dialogue consistency squares for the Dialogue hub header.
//

import UIKit

// MARK: - Square styling

enum DialogueProgressSquareStyle {

    static let scenariosPerDay = 5
    static let dialogueBase = UIColor.systemYellow

    static let unstudiedFill = KanaProgressSquareStyle.unstudiedFill

    static func fillColor(completedCount: Int, scenariosPerDay: Int = scenariosPerDay) -> UIColor {
        guard completedCount > 0 else { return unstudiedFill }
        let clamped = min(max(completedCount, 0), scenariosPerDay)
        if clamped >= scenariosPerDay {
            return dialogueBase
        }
        let fraction = CGFloat(clamped) / CGFloat(scenariosPerDay)
        let alpha = 0.28 + fraction * 0.52
        return dialogueBase.withAlphaComponent(alpha)
    }
}

// MARK: - Grid view

enum DialogueProgressGridLayout {

    static let gridSpacing: CGFloat = 4
    static let cardHorizontalInset: CGFloat = 12
    static let dayCount = 21

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
        let gridWidth = max(0, contentWidth - cardInset * 2)
        let referenceColumns = CGFloat(min(itemCount, 7))
        let squareSide = max(
            1,
            floor((gridWidth - spacing * (referenceColumns - 1)) / referenceColumns)
        )
        let columns = max(
            1,
            min(itemCount, Int(floor((gridWidth + spacing) / (squareSide + spacing))))
        )
        let rows = max(1, Int(ceil(Double(itemCount) / Double(columns))))
        let gridHeight = CGFloat(rows) * squareSide + CGFloat(max(rows - 1, 0)) * spacing
        return Metrics(
            columnCount: columns,
            spacing: spacing,
            squareSide: squareSide,
            gridWidth: gridWidth,
            gridHeight: gridHeight
        )
    }
}

final class DialogueProgressGridView: UIView {

    var dayKeys: [String] = [] {
        didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() }
    }

    var completedCounts: [String: Int] = [:] {
        didSet { setNeedsDisplay() }
    }

    var onSelectDay: ((String) -> Void)?

    var layoutMetrics = DialogueProgressGridLayout.metrics(forContentWidth: 0, itemCount: 0) {
        didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() }
    }

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

        for (index, dayKey) in dayKeys.enumerated() {
            let column = index % columns
            let row = index / columns
            let x = CGFloat(column) * (squareSide + spacing)
            let y = CGFloat(row) * (squareSide + spacing)
            let squareRect = CGRect(x: x, y: y, width: squareSide, height: squareSide)

            let path = UIBezierPath(roundedRect: squareRect, cornerRadius: cornerRadius)
            DialogueProgressSquareStyle.fillColor(
                completedCount: completedCounts[dayKey, default: 0]
            ).setFill()
            path.fill()
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, let dayKey = dayKey(at: gesture.location(in: self)) else { return }
        onSelectDay?(dayKey)
    }

    private func dayKey(at location: CGPoint) -> String? {
        let squareSide = layoutMetrics.squareSide
        guard squareSide > 0 else { return nil }

        let spacing = layoutMetrics.spacing
        let columns = layoutMetrics.columnCount
        let cellStride = squareSide + spacing

        let column = Int((location.x + spacing * 0.5) / cellStride)
        let row = Int((location.y + spacing * 0.5) / cellStride)
        guard column >= 0, row >= 0 else { return nil }

        let index = row * columns + column
        guard dayKeys.indices.contains(index) else { return nil }

        let x = CGFloat(column) * cellStride
        let y = CGFloat(row) * cellStride
        let squareRect = CGRect(x: x, y: y, width: squareSide, height: squareSide)
        guard squareRect.contains(location) else { return nil }

        return dayKeys[index]
    }
}

// MARK: - Card wrapper

final class DialogueProgressGridCardView: UIView {

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let gridView = DialogueProgressGridView()
    private var gridHeightConstraint: NSLayoutConstraint?
    var onSelectDay: ((String) -> Void)? {
        didSet { gridView.onSelectDay = onSelectDay }
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

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .preferredFont(forTextStyle: .footnote)
        subtitleLabel.textColor = .tertiaryLabel
        subtitleLabel.numberOfLines = 0

        gridView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(cardView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(subtitleLabel)
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

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            subtitleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),

            gridView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 8),
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
        let metrics = DialogueProgressGridLayout.metrics(
            forContentWidth: resolvedWidth + DialogueProgressGridLayout.cardHorizontalInset * 2,
            itemCount: gridView.dayKeys.count
        )
        gridView.layoutMetrics = metrics

        if gridHeightConstraint?.constant != metrics.gridHeight {
            gridHeightConstraint?.constant = metrics.gridHeight
            gridView.invalidateIntrinsicContentSize()
        }
        gridView.setNeedsDisplay()
    }

    func configure(
        dayKeys: [String],
        completedCounts: [String: Int],
        title: String,
        subtitle: String?,
        contentWidth: CGFloat
    ) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle?.isEmpty != false
        gridView.dayKeys = dayKeys
        gridView.completedCounts = completedCounts
        applyGridWidth(max(0, contentWidth - DialogueProgressGridLayout.cardHorizontalInset * 2))
    }
}

// MARK: - Progress helpers

enum DialogueProgressGridSupport {

    static func recentDayKeys(
        count: Int = DialogueProgressGridLayout.dayCount,
        calendar: Calendar = .current
    ) -> [String] {
        let today = calendar.startOfDay(for: Date())
        return (0 ..< count).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DialogueProgressStore.dateKey(for: date, calendar: calendar)
        }
    }

    static func completedCounts(
        for dayKeys: [String],
        progressStore: DialogueProgressStore
    ) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: dayKeys.map { key in
            (key, progressStore.completedCount(for: key))
        })
    }

    static func cardTitle(
        completedToday: Int,
        scenariosPerDay: Int,
        streak: Int
    ) -> String {
        if streak > 0 {
            return "Today · \(completedToday)/\(scenariosPerDay) · \(streak)-day streak"
        }
        return "Today · \(completedToday)/\(scenariosPerDay)"
    }

    static func cardSubtitle(dayKeys: [String]) -> String {
        guard let first = dayKeys.first, let last = dayKeys.last else {
            return "Daily consistency"
        }
        return "Last \(dayKeys.count) days · lighter squares mean fewer scenarios finished"
    }
}
