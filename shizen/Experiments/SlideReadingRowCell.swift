//
//  SlideReadingRowCell.swift
//  shizen
//
//  One reading type per list row ("On", "Kun") with a shared label column, so
//  values line up. Used by the Kanji Spotlight and Kanji Decomposition slides.
//

import UIKit

/// Up to four readings per row, each annotated with romaji, e.g. "にち (nichi)、じつ (jitsu)".
func slideReadingRows(for detail: KanjidicDetail?) -> [(title: String, value: String)] {
    var rows: [(title: String, value: String)] = []
    if let readings = detail?.spotlightReadingLines {
        if let on = readings.on { rows.append(("On", on)) }
        if let kun = readings.kun { rows.append(("Kun", kun)) }
    }
    if rows.isEmpty { rows.append(("Reading", "—")) }
    return rows
}

/// Height of a non-scrolling list's content, for sizing it to fit on a slide.
/// Self-sizing cells report their real height a layout pass after they're first
/// laid out, so a single pass under-counts any row taller than the estimate
/// (e.g. a Kun line that wraps) and clips the last row. Lay out until it settles.
func slideListContentHeight(of collectionView: UICollectionView) -> CGFloat {
    collectionView.collectionViewLayout.invalidateLayout()
    collectionView.layoutIfNeeded()
    var height = collectionView.collectionViewLayout.collectionViewContentSize.height
    for _ in 0..<4 {
        collectionView.layoutIfNeeded()
        let next = collectionView.collectionViewLayout.collectionViewContentSize.height
        if abs(next - height) < 0.5 { break }
        height = next
    }
    return height
}

final class SlideReadingRowCell: UICollectionViewListCell {
    /// Matches the 1.2× list scale on slideshow cards.
    private static func scaled(_ base: CGFloat) -> CGFloat {
        (base * 1.2).rounded()
    }

    private let titleLabel = UILabel()
    private let valueLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        titleLabel.font = .systemFont(ofSize: SlideReadingRowCell.scaled(11), weight: .semibold)
        titleLabel.textColor = .tertiaryLabel
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        valueLabel.font = .systemFont(ofSize: SlideReadingRowCell.scaled(14), weight: .medium)
        valueLabel.textColor = .label
        valueLabel.numberOfLines = 2
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7
        valueLabel.lineBreakMode = .byWordWrapping

        let rowStack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        rowStack.axis = .horizontal
        rowStack.alignment = .firstBaseline
        rowStack.spacing = SlideReadingRowCell.scaled(12)
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: SlideReadingRowCell.scaled(8)
            ),
            rowStack.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -SlideReadingRowCell.scaled(8)
            ),
            rowStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            // Shared column so On and Kun values start at the same x.
            titleLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: SlideReadingRowCell.scaled(34)),
        ])
    }

    func configure(title: String, value: String) {
        titleLabel.text = title
        valueLabel.text = value
    }
}
