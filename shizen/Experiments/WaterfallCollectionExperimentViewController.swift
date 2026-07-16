//
//  WaterfallCollectionExperimentViewController.swift
//  shizen
//
//  DEBUG experiment: two-column cascade grid with key/value cards.
//

import UIKit

// MARK: - Layout delegate

protocol WaterfallCollectionLayoutDelegate: AnyObject {
    func collectionView(
        _ collectionView: UICollectionView,
        heightForItemAt indexPath: IndexPath,
        columnWidth: CGFloat
    ) -> CGFloat
}

// MARK: - Waterfall layout

private final class WaterfallCollectionLayout: UICollectionViewLayout {
    weak var delegate: WaterfallCollectionLayoutDelegate?

    var columnCount: Int = 2
    var columnSpacing: CGFloat = 12
    var rowSpacing: CGFloat = 12
    var sectionInset: UIEdgeInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

    private var cache: [UICollectionViewLayoutAttributes] = []
    private var contentHeight: CGFloat = 0

    override var collectionViewContentSize: CGSize {
        guard let collectionView else { return .zero }
        return CGSize(width: collectionView.bounds.width, height: contentHeight)
    }

    override func prepare() {
        guard
            let collectionView,
            columnCount > 0
        else { return }

        cache.removeAll()
        contentHeight = 0

        let availableWidth = collectionView.bounds.width
            - sectionInset.left
            - sectionInset.right
            - CGFloat(columnCount - 1) * columnSpacing
        let columnWidth = floor(availableWidth / CGFloat(columnCount))

        var columnHeights = Array(repeating: sectionInset.top, count: columnCount)
        let itemCount = collectionView.numberOfItems(inSection: 0)

        for item in 0 ..< itemCount {
            let indexPath = IndexPath(item: item, section: 0)
            let itemHeight = delegate?.collectionView(
                collectionView,
                heightForItemAt: indexPath,
                columnWidth: columnWidth
            ) ?? 120

            let shortestColumn = columnHeights.enumerated().min(by: { $0.element < $1.element })!.offset
            let x = sectionInset.left + CGFloat(shortestColumn) * (columnWidth + columnSpacing)
            let y = columnHeights[shortestColumn]

            let frame = CGRect(x: x, y: y, width: columnWidth, height: itemHeight)
            let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            attributes.frame = frame
            cache.append(attributes)

            columnHeights[shortestColumn] = y + itemHeight + rowSpacing
        }

        contentHeight = (columnHeights.max() ?? sectionInset.top) - rowSpacing + sectionInset.bottom
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        cache.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        cache.first { $0.indexPath == indexPath }
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView else { return false }
        return newBounds.width != collectionView.bounds.width
    }
}

// MARK: - Card cell

private final class WaterfallCardCell: UICollectionViewCell {
    static let reuseId = "WaterfallCardCell"

    private let cardView = UIView()
    private let keyLabel = UILabel()
    private let valueLabel = UILabel()
    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureViews() {
        contentView.backgroundColor = .clear
        backgroundColor = .clear

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = ExperimentPalette.cardSurface
        cardView.layer.cornerRadius = 28
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = ExperimentCardStroke.normalWidth
        cardView.layer.borderColor = ExperimentPalette.cardBorder.cgColor
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.06
        cardView.layer.shadowRadius = 8
        cardView.layer.shadowOffset = CGSize(width: 0, height: 2)

        keyLabel.font = .preferredFont(forTextStyle: .headline)
        keyLabel.textColor = .label
        keyLabel.numberOfLines = 0

        valueLabel.font = .preferredFont(forTextStyle: .subheadline)
        valueLabel.textColor = .secondaryLabel
        valueLabel.numberOfLines = 0

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.alignment = .fill
        stackView.addArrangedSubview(keyLabel)
        stackView.addArrangedSubview(valueLabel)

        cardView.addSubview(stackView)
        contentView.addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
        ])
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            cardView.layer.borderColor = ExperimentPalette.cardBorder.cgColor
        }
    }

    func configure(key: String, value: String) {
        keyLabel.text = key
        valueLabel.text = value
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
        let targetWidth = layoutAttributes.size.width
        let fittingSize = CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height)
        let measured = contentView.systemLayoutSizeFitting(
            fittingSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        attributes.size = CGSize(width: targetWidth, height: ceil(measured.height))
        return attributes
    }
}

// MARK: - View controller

final class WaterfallCollectionExperimentViewController: UIViewController {
    private struct Item {
        let key: String
        let value: String
    }

    private let layout = WaterfallCollectionLayout()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private var heightCache: [IndexPath: CGFloat] = [:]

    private let items: [Item] = [
        Item(
            key: "Weather in Okinawa January",
            value: "Average highs around 19°C with mild, breezy days. Rain is infrequent but pack a light jacket for evenings near the coast."
        ),
        Item(
            key: "Clark Hymas Phone Number",
            value: "(801) 555-0142"
        ),
        Item(
            key: "Grocery list",
            value: "Eggs\nMilk\nSourdough bread\nCherry tomatoes\nOlive oil"
        ),
        Item(
            key: "Train to Kyoto",
            value: "Shinkansen Nozomi · platform 14 · departs 09:12 · reserved seat 7C"
        ),
        Item(
            key: "Meeting notes",
            value: "Discussed onboarding flow, agreed to simplify the first lesson path, and scheduled a follow-up for next Tuesday."
        ),
        Item(
            key: "Wi-Fi password",
            value: "sakura-guest-2026"
        ),
        Item(
            key: "Book recommendation",
            value: "Kitchen by Banana Yoshimoto — short, quiet, and perfect for rainy afternoons. The prose stays simple but the mood lingers."
        ),
        Item(
            key: "Pharmacy hours",
            value: "Mon–Sat 9:00–20:00 · Sun 10:00–18:00"
        ),
        Item(
            key: "Kanji drill",
            value: "食 · 飲 · 見 · 行 · 来\nReview stroke order before tomorrow's quiz."
        ),
        Item(
            key: "Coffee order",
            value: "Oat milk latte, extra hot"
        ),
        Item(
            key: "Apartment viewing",
            value: "Saturday at 2:30 PM. Bring ID and proof of income. Ask about bicycle parking and whether utilities are included."
        ),
        Item(
            key: "Reminder",
            value: "Call dentist"
        ),
        Item(
            key: "Recipe — miso soup",
            value: "Simmer dashi, whisk in miso off heat, add tofu and wakame. Finish with sliced green onion. Keep it gentle — never boil the miso."
        ),
        Item(
            key: "Locker code",
            value: "4829"
        ),
        Item(
            key: "Weekend plan",
            value: "Saturday: farmers market and kana review. Sunday: long walk, then flashcards in the park if the weather holds."
        ),
        Item(
            key: "Quote",
            value: "\"The real voyage of discovery consists not in seeking new landscapes, but in having new eyes.\""
        ),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Waterfall grid"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground

        layout.delegate = self

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.register(WaterfallCardCell.self, forCellWithReuseIdentifier: WaterfallCardCell.reuseId)

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func measuredHeight(for indexPath: IndexPath, columnWidth: CGFloat) -> CGFloat {
        if let cached = heightCache[indexPath] {
            return cached
        }

        let item = items[indexPath.item]
        let cell = WaterfallCardCell(frame: CGRect(x: 0, y: 0, width: columnWidth, height: 0))
        cell.configure(key: item.key, value: item.value)

        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.size = CGSize(width: columnWidth, height: 0)
        let fitted = cell.preferredLayoutAttributesFitting(attributes)
        heightCache[indexPath] = fitted.size.height
        return fitted.size.height
    }
}

extension WaterfallCollectionExperimentViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: WaterfallCardCell.reuseId,
            for: indexPath
        ) as! WaterfallCardCell
        let item = items[indexPath.item]
        cell.configure(key: item.key, value: item.value)
        return cell
    }
}

extension WaterfallCollectionExperimentViewController: WaterfallCollectionLayoutDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        heightForItemAt indexPath: IndexPath,
        columnWidth: CGFloat
    ) -> CGFloat {
        measuredHeight(for: indexPath, columnWidth: columnWidth)
    }
}
