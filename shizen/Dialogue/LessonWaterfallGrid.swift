//
//  LessonWaterfallGrid.swift
//  shizen
//
//  Shared waterfall cascade grid for lesson thumbnail cards. Each cell is a
//  lesson thumbnail card; locked lessons show a yellow-tinted lock badge and
//  render their thumbnail in grayscale.
//

import CoreImage
import UIKit

// MARK: - Lesson model

struct WaterfallLesson {
    /// CMS / catalog lesson id when known (e.g. `train-station`).
    let id: String?
    let title: String
    let conversationCount: Int
    let thumbnailName: String
    /// Remote CDN thumbnail URL when provided by the CMS.
    let thumbnailURL: URL?
    let isLocked: Bool

    init(
        id: String? = nil,
        title: String,
        conversationCount: Int,
        thumbnailName: String,
        thumbnailURL: URL? = nil,
        isLocked: Bool
    ) {
        self.id = id
        self.title = title
        self.conversationCount = conversationCount
        self.thumbnailName = thumbnailName
        self.thumbnailURL = thumbnailURL
        self.isLocked = isLocked
    }
}

// MARK: - Layout delegate

protocol LessonWaterfallLayoutDelegate: AnyObject {
    func collectionView(
        _ collectionView: UICollectionView,
        heightForItemAt indexPath: IndexPath,
        columnWidth: CGFloat
    ) -> CGFloat
}

// MARK: - Waterfall layout

final class LessonWaterfallLayout: UICollectionViewLayout {
    weak var delegate: LessonWaterfallLayoutDelegate?

    var columnCount: Int = 2
    var columnSpacing: CGFloat = 12
    var rowSpacing: CGFloat = 12
    /// Bottom inset defaults to enough room for the card's drop shadow so the
    /// last row doesn't get visually clipped by the collection view's own bounds.
    var sectionInset: UIEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 12, right: 0)

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
            ) ?? 220

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

// MARK: - Lock badge

/// Yellow-tinted liquid glass circle with a lock glyph, shown on locked lesson thumbnails.
final class LessonLockBadgeView: UIView {
    private static let diameter: CGFloat = 36

    private let backgroundView = UIView()
    private let lockImageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: Self.diameter, height: Self.diameter)
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = .systemYellow
        backgroundView.layer.cornerRadius = Self.diameter / 2
        backgroundView.layer.cornerCurve = .continuous
        addSubview(backgroundView)

        lockImageView.translatesAutoresizingMaskIntoConstraints = false
        lockImageView.image = UIImage(systemName: "lock.fill")
        lockImageView.tintColor = Colors.textYellow
        lockImageView.contentMode = .scaleAspectFit
        lockImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        backgroundView.addSubview(lockImageView)

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.diameter),
            heightAnchor.constraint(equalToConstant: Self.diameter),

            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            lockImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            lockImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            lockImageView.widthAnchor.constraint(equalToConstant: 18),
            lockImageView.heightAnchor.constraint(equalToConstant: 18),
        ])
    }
}

// MARK: - Lesson card cell

final class LessonWaterfallCardCell: UICollectionViewCell {
    static let reuseId = "LessonWaterfallCardCell"

    private let cardView = UIView()
    private let thumbnailImageView = UIImageView()
    private let thumbnailLoadingPlaceholder = ImageLoadingPlaceholderView()
    private let lockBadge = LessonLockBadgeView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let textStack = UIStackView()

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

        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailImageView.contentMode = .scaleAspectFill
        thumbnailImageView.clipsToBounds = true
        thumbnailImageView.layer.cornerRadius = ImageLoadingPlaceholderMetrics.defaultCornerRadius
        thumbnailImageView.layer.cornerCurve = .continuous
        thumbnailImageView.backgroundColor = ExperimentPalette.pageBackground

        thumbnailLoadingPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        thumbnailLoadingPlaceholder.message = nil
        thumbnailLoadingPlaceholder.syncCornerRadius(with: thumbnailImageView)
        thumbnailLoadingPlaceholder.isHidden = true

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2

        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1

        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 6
        textStack.alignment = .fill
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)

        cardView.addSubview(thumbnailImageView)
        cardView.addSubview(thumbnailLoadingPlaceholder)
        cardView.addSubview(textStack)
        cardView.addSubview(lockBadge)
        contentView.addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            thumbnailImageView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            thumbnailImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 10),
            thumbnailImageView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),
            thumbnailImageView.heightAnchor.constraint(equalTo: thumbnailImageView.widthAnchor, multiplier: 0.82),

            thumbnailLoadingPlaceholder.topAnchor.constraint(equalTo: thumbnailImageView.topAnchor),
            thumbnailLoadingPlaceholder.leadingAnchor.constraint(equalTo: thumbnailImageView.leadingAnchor),
            thumbnailLoadingPlaceholder.trailingAnchor.constraint(equalTo: thumbnailImageView.trailingAnchor),
            thumbnailLoadingPlaceholder.bottomAnchor.constraint(equalTo: thumbnailImageView.bottomAnchor),

            lockBadge.topAnchor.constraint(equalTo: thumbnailImageView.topAnchor, constant: 10),
            lockBadge.trailingAnchor.constraint(equalTo: thumbnailImageView.trailingAnchor, constant: -10),

            textStack.topAnchor.constraint(equalTo: thumbnailImageView.bottomAnchor, constant: 12),
            textStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            textStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
        ])
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            cardView.layer.borderColor = ExperimentPalette.cardBorder.cgColor
        }
    }

    override var isHighlighted: Bool {
        didSet {
            guard oldValue != isHighlighted else { return }
            let animator = UIViewPropertyAnimator(duration: 0.2, dampingRatio: 0.7) { [weak self] in
                guard let self else { return }
                self.cardView.backgroundColor = self.isHighlighted ? Self.pressedCardSurface : ExperimentPalette.cardSurface
            }
            animator.startAnimation()
        }
    }

    /// `cardSurface` darkened slightly for the pressed state, adaptive for light/dark.
    private static let pressedCardSurface = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .tertiarySystemGroupedBackground
            : UIColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailLoadingPlaceholder.stopAnimating()
        thumbnailLoadingPlaceholder.isHidden = true
        thumbnailImageView.image = nil
        thumbnailImageView.accessibilityIdentifier = nil
    }

    func configure(with lesson: WaterfallLesson) {
        titleLabel.text = lesson.title
        titleLabel.textColor = lesson.isLocked ? .secondaryLabel : .label
        subtitleLabel.text = "\(lesson.conversationCount) conversations"
        lockBadge.isHidden = !lesson.isLocked

        let applyImage: (UIImage?) -> Void = { [weak self] source in
            guard let self else { return }
            self.thumbnailLoadingPlaceholder.stopAnimating()
            self.thumbnailLoadingPlaceholder.isHidden = true
            if lesson.isLocked, let source {
                self.thumbnailImageView.image = Self.grayscaleImage(from: source) ?? source
            } else {
                self.thumbnailImageView.image = source
            }
        }

        thumbnailImageView.image = nil
        if let remoteURL = lesson.thumbnailURL {
            let token = remoteURL.absoluteString
            thumbnailImageView.accessibilityIdentifier = token
            if let cached = LessonThumbnailLoader.cachedImage(for: remoteURL) {
                applyImage(cached)
            } else {
                thumbnailLoadingPlaceholder.isHidden = false
                thumbnailLoadingPlaceholder.startAnimating()
                LessonThumbnailLoader.load(url: remoteURL) { [weak self] image in
                    guard let self,
                          self.thumbnailImageView.accessibilityIdentifier == token else { return }
                    applyImage(image ?? UIImage(named: lesson.thumbnailName))
                }
            }
        } else {
            applyImage(UIImage(named: lesson.thumbnailName))
        }
    }

    private static let ciContext = CIContext()

    private static func grayscaleImage(from image: UIImage) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        guard let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)
        guard
            let output = filter.outputImage,
            let cgImage = ciContext.createCGImage(output, from: ciImage.extent)
        else { return nil }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
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

// MARK: - Reusable grid controller helper

/// Owns a `LessonWaterfallLayout` + `UICollectionView` and answers data source /
/// delegate / layout-delegate calls for a fixed list of `WaterfallLesson`s.
/// Embed this collection view directly inside a parent scroll view (non-scrolling)
/// or use it standalone as a full-screen grid.
final class LessonWaterfallGridController: NSObject {
    let collectionView: UICollectionView
    private let layout = LessonWaterfallLayout()
    private var lessons: [WaterfallLesson] = []
    private var heightCache: [IndexPath: CGFloat] = [:]
    private var lastReportedContentHeight: CGFloat = -1
    var onSelect: ((Int, WaterfallLesson) -> Void)?

    /// Fires whenever the waterfall's measured content height changes, so an
    /// embedding parent (with `isScrollEnabled = false`) can update its height
    /// constraint to fit all cards without clipping.
    var onContentHeightChanged: ((CGFloat) -> Void)?

    /// Insets around the grid content. Defaults to zero, suitable for embedding
    /// inside a parent that already provides horizontal page insets. Pass a
    /// non-zero inset when using the grid as a standalone full-screen surface.
    var sectionInset: UIEdgeInsets {
        get { layout.sectionInset }
        set { layout.sectionInset = newValue }
    }

    override init() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init()
        layout.delegate = self
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(
            LessonWaterfallCardCell.self,
            forCellWithReuseIdentifier: LessonWaterfallCardCell.reuseId
        )
    }

    func setLessons(_ lessons: [WaterfallLesson]) {
        self.lessons = lessons
        heightCache.removeAll()
        collectionView.reloadData()
        layout.invalidateLayout()
    }

    /// Call from the parent's `viewDidLayoutSubviews` when embedding non-scrolling.
    func refreshContentHeightIfNeeded() {
        collectionView.layoutIfNeeded()
        let height = collectionView.collectionViewLayout.collectionViewContentSize.height
        guard height > 0, abs(height - lastReportedContentHeight) >= 0.5 else { return }
        lastReportedContentHeight = height
        onContentHeightChanged?(height)
    }

    private func measuredHeight(for indexPath: IndexPath, columnWidth: CGFloat) -> CGFloat {
        if let cached = heightCache[indexPath] {
            return cached
        }

        let lesson = lessons[indexPath.item]
        let cell = LessonWaterfallCardCell(frame: CGRect(x: 0, y: 0, width: columnWidth, height: 0))
        cell.configure(with: lesson)

        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.size = CGSize(width: columnWidth, height: 0)
        let fitted = cell.preferredLayoutAttributesFitting(attributes)
        heightCache[indexPath] = fitted.size.height
        return fitted.size.height
    }
}

extension LessonWaterfallGridController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        lessons.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: LessonWaterfallCardCell.reuseId,
            for: indexPath
        ) as! LessonWaterfallCardCell
        cell.configure(with: lessons[indexPath.item])
        return cell
    }
}

extension LessonWaterfallGridController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard lessons.indices.contains(indexPath.item) else { return }
        let lesson = lessons[indexPath.item]
        guard !lesson.isLocked else { return }
        onSelect?(indexPath.item, lesson)
    }
}

extension LessonWaterfallGridController: LessonWaterfallLayoutDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        heightForItemAt indexPath: IndexPath,
        columnWidth: CGFloat
    ) -> CGFloat {
        measuredHeight(for: indexPath, columnWidth: columnWidth)
    }
}

// MARK: - Remote thumbnail loader

enum LessonThumbnailLoader {
    private static let cache = NSCache<NSString, UIImage>()
    private static let session = URLSession.shared

    static func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    static func load(url: URL, completion: @escaping (UIImage?) -> Void) {
        let key = url.absoluteString as NSString
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return
        }
        session.dataTask(with: url) { data, response, _ in
            let image: UIImage?
            if let data,
               let http = response as? HTTPURLResponse,
               (200 ... 299).contains(http.statusCode),
               let decoded = UIImage(data: data) {
                cache.setObject(decoded, forKey: key)
                image = decoded
            } else {
                image = nil
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }.resume()
    }
}
