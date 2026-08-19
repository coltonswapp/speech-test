//
//  KanjiDecompositionCardViews.swift
//  shizen
//
//  Card faces for the kanji decomposition pager: intro, per-character slides,
//  a combined teaser (?), then the final reveal. Built with Auto Layout so the
//  same instance can be shown live or rebuilt at a fixed frame for export.
//

import UIKit

/// Scales readings/compounds list typography and padding on character cards.
private enum KanjiDecompositionListMetrics {
    static let scale: CGFloat = 1.2

    static func size(_ base: CGFloat) -> CGFloat {
        (base * scale).rounded()
    }

    static func inset(_ base: CGFloat) -> CGFloat {
        (base * scale).rounded()
    }
}

// MARK: - Shared hero card chrome

private final class KanjiDecompositionHeroCard: UIView {
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

// MARK: - Floating meaning badge

enum KanjiDecompositionMeaningBadgeStyle {
    case standard
    case compact

    fileprivate var wrapWidth: CGFloat {
        switch self {
        case .standard: return 120
        case .compact: return 96
        }
    }

    fileprivate var horizontalPadding: CGFloat {
        switch self {
        case .standard: return 24
        case .compact: return 20
        }
    }

    fileprivate var basePointSize: CGFloat {
        switch self {
        case .standard: return 13
        case .compact: return 11
        }
    }

    fileprivate var labelHorizontalInset: CGFloat {
        switch self {
        case .standard: return 12
        case .compact: return 10
        }
    }

    fileprivate var verticalInset: CGFloat {
        switch self {
        case .standard: return 6
        case .compact: return 5
        }
    }

    fileprivate var cornerRadius: CGFloat {
        switch self {
        case .standard: return 10
        case .compact: return 8
        }
    }
}

private final class KanjiDecompositionMeaningBadge: UIView {
    private let style: KanjiDecompositionMeaningBadgeStyle
    private let label = UILabel()
    private var widthConstraint: NSLayoutConstraint!
    private static let minimumFontScale: CGFloat = 0.62

    private var textWidth: CGFloat { style.wrapWidth - style.horizontalPadding }

    init(style: KanjiDecompositionMeaningBadgeStyle = .standard) {
        self.style = style
        super.init(frame: .zero)
        setup()
    }

    override init(frame: CGRect) {
        self.style = .standard
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        self.style = .standard
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = ExperimentPalette.cardSurface
        layer.borderWidth = ExperimentCardStroke.normalWidth
        layer.cornerRadius = style.cornerRadius
        layer.cornerCurve = .continuous
        applyBorderColor()

        label.font = Self.badgeFont(size: KanjiDecompositionListMetrics.size(style.basePointSize))
        label.textColor = ExperimentPalette.meaningBadgeText
        label.textAlignment = .center
        label.numberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        widthConstraint = widthAnchor.constraint(equalToConstant: style.wrapWidth)

        NSLayoutConstraint.activate([
            widthConstraint,
            label.topAnchor.constraint(equalTo: topAnchor, constant: style.verticalInset),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -style.verticalInset),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: style.labelHorizontalInset),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -style.labelHorizontalInset),
        ])

        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentHuggingPriority(.required, for: .horizontal)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.preferredMaxLayoutWidth = textWidth
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyBorderColor()
    }

    private func applyBorderColor() {
        layer.borderColor = ExperimentPalette.cardBorder
            .resolvedColor(with: traitCollection).cgColor
    }

    func configure(text: String) {
        let parts = Self.meaningParts(from: text)
        let fitted = fittedDisplay(for: parts)
        label.font = fitted.font
        label.text = fitted.text
        label.numberOfLines = 2
        label.lineBreakMode = fitted.text.contains("\n") ? .byWordWrapping : .byTruncatingTail
        label.preferredMaxLayoutWidth = textWidth
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func setEditingSelected(_ selected: Bool) {
        layer.borderWidth = selected ? 2.5 : ExperimentCardStroke.normalWidth
        if selected {
            layer.borderColor = UIColor.systemBlue.cgColor
        } else {
            applyBorderColor()
        }
    }

    private struct FittedDisplay {
        let text: String
        let font: UIFont
    }

    private static func badgeFont(size: CGFloat) -> UIFont {
        .systemFont(ofSize: size, weight: .semibold)
    }

    /// Up to two glosses from comma-separated badge copy.
    private static func meaningParts(from text: String) -> [String] {
        let parts = text
            .split(separator: ",", omittingEmptySubsequences: true)
            .prefix(2)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.isEmpty { return [text] }
        return parts
    }

    private func fittedDisplay(for parts: [String]) -> FittedDisplay {
        let maxWidth = textWidth
        let baseSize = KanjiDecompositionListMetrics.size(style.basePointSize)
        let minSize = max(8, baseSize * Self.minimumFontScale)

        let candidates: [String]
        if parts.count <= 1 {
            candidates = [parts[0]]
        } else {
            candidates = [
                parts.joined(separator: ", "),
                "\(parts[0]),\n\(parts[1])",
            ]
        }

        var size = baseSize
        while size >= minSize {
            let font = Self.badgeFont(size: size)
            if let text = candidates.first(where: { Self.textFits($0, font: font, maxWidth: maxWidth) }) {
                return FittedDisplay(text: text, font: font)
            }
            size -= 0.5
        }

        let font = Self.badgeFont(size: minSize)
        let fallback = candidates.last ?? parts.joined(separator: ", ")
        return FittedDisplay(text: fallback, font: font)
    }

    private static func textFits(_ text: String, font: UIFont, maxWidth: CGFloat) -> Bool {
        let lines = text.components(separatedBy: "\n")
        guard lines.count <= 2 else { return false }

        for line in lines {
            let lineWidth = (line as NSString).size(withAttributes: [.font: font]).width
            if lineWidth > maxWidth + 0.5 {
                return false
            }
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 1

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
        ]
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let maxHeight = ceil(font.lineHeight * CGFloat(lines.count)) + CGFloat(max(0, lines.count - 1)) * 2 + 6
        return ceil(bounds.height) <= maxHeight
    }
}

// MARK: - Character hero (glyph card + floating meaning badge)

enum KanjiDecompositionBadgePlacement {
    /// Centered under the hero (solo character cards).
    case center
    /// Badge center sits on the hero card's trailing edge.
    case trailingEdgeCentered
    /// Biased to the left / outer edge (left card in A + B reveal).
    case outsideLeading
    /// Biased to the right / outer edge (right card in A + B reveal).
    case outsideTrailing
}

final class KanjiDecompositionCharacterHeroView: UIView {
    let layoutIdentifier: KanjiDecompositionBadgeIdentifier
    private let heroCard = KanjiDecompositionHeroCard()
    private let glyphLabel = UILabel()
    private let badge: KanjiDecompositionMeaningBadge

    private(set) var userOffset: CGPoint = .zero

    /// `cardWidth`/height ratio (1.24) matches KanjiDetailViewController's KanjiDetailCard exactly.
    init(
        layoutIdentifier: KanjiDecompositionBadgeIdentifier,
        cardWidth: CGFloat = 118,
        glyphFontSize: CGFloat = 64,
        badgeStyle: KanjiDecompositionMeaningBadgeStyle = .standard,
        badgePlacement: KanjiDecompositionBadgePlacement = .center
    ) {
        self.layoutIdentifier = layoutIdentifier
        self.badge = KanjiDecompositionMeaningBadge(style: badgeStyle)
        super.init(frame: .zero)
        setup(cardWidth: cardWidth, glyphFontSize: glyphFontSize, badgePlacement: badgePlacement)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup(
        cardWidth: CGFloat,
        glyphFontSize: CGFloat,
        badgePlacement: KanjiDecompositionBadgePlacement
    ) {
        translatesAutoresizingMaskIntoConstraints = false

        glyphLabel.textAlignment = .center
        glyphLabel.adjustsFontSizeToFitWidth = true
        glyphLabel.minimumScaleFactor = 0.5
        glyphLabel.textColor = .label
        glyphLabel.font = .systemFont(ofSize: glyphFontSize, weight: .bold)
        glyphLabel.translatesAutoresizingMaskIntoConstraints = false

        heroCard.translatesAutoresizingMaskIntoConstraints = false
        heroCard.addSubview(glyphLabel)
        addSubview(heroCard)

        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)

        clipsToBounds = false
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.defaultHigh, for: .horizontal)

        var constraints: [NSLayoutConstraint] = [
            heroCard.topAnchor.constraint(equalTo: topAnchor),
            heroCard.centerXAnchor.constraint(equalTo: centerXAnchor),
            heroCard.widthAnchor.constraint(equalToConstant: cardWidth),
            heroCard.heightAnchor.constraint(equalTo: heroCard.widthAnchor, multiplier: 1.24),

            glyphLabel.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: 6),
            glyphLabel.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor, constant: -6),
            glyphLabel.centerYAnchor.constraint(equalTo: heroCard.centerYAnchor),

            badge.centerYAnchor.constraint(equalTo: heroCard.bottomAnchor),

            leadingAnchor.constraint(lessThanOrEqualTo: heroCard.leadingAnchor),
            trailingAnchor.constraint(greaterThanOrEqualTo: heroCard.trailingAnchor),
            leadingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor),
            trailingAnchor.constraint(greaterThanOrEqualTo: badge.trailingAnchor),

            bottomAnchor.constraint(equalTo: badge.bottomAnchor),
        ]

        switch badgePlacement {
        case .center:
            constraints.append(badge.centerXAnchor.constraint(equalTo: centerXAnchor))
        case .trailingEdgeCentered:
            constraints.append(badge.centerXAnchor.constraint(equalTo: heroCard.trailingAnchor))
        case .outsideLeading:
            constraints.append(badge.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: -14))
        case .outsideTrailing:
            constraints.append(badge.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor, constant: 14))
        }

        NSLayoutConstraint.activate(constraints)
    }

    func configure(character: Character, meaning: String) {
        glyphLabel.text = String(character)
        applyMeaning(meaning)
        applyUserOffset(userOffset)
    }

    func applyMeaning(_ meaning: String) {
        badge.configure(text: meaning.isEmpty ? "—" : meaning)
    }

    func applyUserOffset(_ offset: CGPoint) {
        userOffset = offset
        badge.transform = CGAffineTransform(translationX: offset.x, y: offset.y)
    }

    func setEditingSelected(_ selected: Bool) {
        badge.setEditingSelected(selected)
    }

    func badgeContains(point: CGPoint, in coordinateSpace: UIView) -> Bool {
        let frame = badge.convert(badge.bounds, to: coordinateSpace).insetBy(dx: -12, dy: -12)
        return frame.contains(point)
    }
}

// MARK: - Combined preview row (teaser + reveal)

private enum KanjiDecompositionPreviewRowMetrics {
    static func layout(for characterCount: Int) -> (
        cardWidth: CGFloat,
        glyphFontSize: CGFloat,
        spacing: CGFloat,
        compactBadges: Bool
    ) {
        let isThreeUp = characterCount == 3
        return (
            cardWidth: isThreeUp ? 72 : 90,
            glyphFontSize: isThreeUp ? 32 : 40,
            spacing: isThreeUp ? 8 : 12,
            compactBadges: isThreeUp
        )
    }
}

private func kanjiDecompositionMakePlusContainer(height: CGFloat) -> UIView {
    let plusLabel = UILabel()
    plusLabel.text = "+"
    plusLabel.font = .preferredFont(forTextStyle: .title1)
    plusLabel.textColor = .secondaryLabel
    plusLabel.textAlignment = .center

    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false
    plusLabel.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(plusLabel)
    NSLayoutConstraint.activate([
        container.heightAnchor.constraint(equalToConstant: height),
        plusLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        plusLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
    ])
    container.setContentHuggingPriority(.required, for: .horizontal)
    return container
}

private func kanjiDecompositionPreviewBadgePlacement(for index: Int, count: Int) -> KanjiDecompositionBadgePlacement {
    guard count > 1 else { return .center }
    if index == 0 { return .outsideLeading }
    if index == count - 1 { return .outsideTrailing }
    return .center
}

@discardableResult
private func kanjiDecompositionPopulatePreviewRow(
    _ row: UIStackView,
    word: KanjiDecompositionWord,
    heroes: inout [KanjiDecompositionCharacterHeroView]
) -> CGFloat {
    row.arrangedSubviews.forEach { view in
        row.removeArrangedSubview(view)
        view.removeFromSuperview()
    }
    heroes.removeAll()

    let metrics = KanjiDecompositionPreviewRowMetrics.layout(for: word.characters.count)
    row.spacing = metrics.spacing

    let heroHeight = metrics.cardWidth * 1.24
    var arrangedSubviews: [UIView] = []

    for (index, character) in word.characters.enumerated() {
        if index > 0 {
            arrangedSubviews.append(kanjiDecompositionMakePlusContainer(height: heroHeight))
        }

        let hero = KanjiDecompositionCharacterHeroView(
            layoutIdentifier: .combinedPreview(index: index),
            cardWidth: metrics.cardWidth,
            glyphFontSize: metrics.glyphFontSize,
            badgeStyle: metrics.compactBadges ? .compact : .standard,
            badgePlacement: kanjiDecompositionPreviewBadgePlacement(for: index, count: word.characters.count)
        )
        let detail = KanjidicStore.shared.detail(forKanji: String(character))
        hero.configure(character: character, meaning: detail?.badgeMeaning ?? "")
        hero.setContentCompressionResistancePriority(.required, for: .horizontal)
        heroes.append(hero)
        arrangedSubviews.append(hero)
    }

    arrangedSubviews.forEach { row.addArrangedSubview($0) }
    return heroHeight
}

private func kanjiDecompositionInstallPreviewContainer(
    _ container: UIView,
    row: UIStackView
) {
    container.translatesAutoresizingMaskIntoConstraints = false
    row.axis = .horizontal
    row.alignment = .top
    row.distribution = .fillProportionally
    row.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(row)
    NSLayoutConstraint.activate([
        row.topAnchor.constraint(equalTo: container.topAnchor),
        row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        row.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        row.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
        row.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
    ])
}

// MARK: - Word hero (furigana-annotated combined word, no meaning)

private final class KanjiDecompositionWordHeroCard: UIView {
    private let heroCard = KanjiDecompositionHeroCard()
    private let wordLabel = FuriganaTranscriptLabel()
    private let fixedWidth: CGFloat?
    private let heightToWidthRatio: CGFloat

    init(fixedWidth: CGFloat? = nil, heightToWidthRatio: CGFloat = 1.24) {
        self.fixedWidth = fixedWidth
        self.heightToWidthRatio = heightToWidthRatio
        super.init(frame: .zero)
        setup()
    }

    override init(frame: CGRect) {
        self.fixedWidth = nil
        self.heightToWidthRatio = 1.24
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        self.fixedWidth = nil
        self.heightToWidthRatio = 1.24
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        wordLabel.clipsToBounds = false
        wordLabel.numberOfLines = 1
        wordLabel.textAlignment = .center
        wordLabel.translatesAutoresizingMaskIntoConstraints = false
        heroCard.addSubview(wordLabel)
        heroCard.translatesAutoresizingMaskIntoConstraints = false
        addSubview(heroCard)

        var constraints: [NSLayoutConstraint] = []

        if fixedWidth != nil {
            constraints.append(contentsOf: [
                wordLabel.centerXAnchor.constraint(equalTo: heroCard.centerXAnchor),
                wordLabel.centerYAnchor.constraint(equalTo: heroCard.centerYAnchor),
                wordLabel.leadingAnchor.constraint(greaterThanOrEqualTo: heroCard.leadingAnchor, constant: 16),
                wordLabel.trailingAnchor.constraint(lessThanOrEqualTo: heroCard.trailingAnchor, constant: -16),
            ])
            wordLabel.setContentHuggingPriority(.required, for: .horizontal)
            wordLabel.setContentHuggingPriority(.required, for: .vertical)
            wordLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            wordLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        } else {
            constraints.append(contentsOf: [
                wordLabel.topAnchor.constraint(equalTo: heroCard.topAnchor, constant: 24),
                wordLabel.bottomAnchor.constraint(equalTo: heroCard.bottomAnchor, constant: -24),
                wordLabel.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: 24),
                wordLabel.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor, constant: -24),
            ])
        }

        if let fixedWidth {
            constraints.append(contentsOf: [
                widthAnchor.constraint(equalToConstant: fixedWidth),
                heroCard.topAnchor.constraint(equalTo: topAnchor),
                heroCard.bottomAnchor.constraint(equalTo: bottomAnchor),
                heroCard.centerXAnchor.constraint(equalTo: centerXAnchor),
                heroCard.widthAnchor.constraint(equalToConstant: fixedWidth),
                heroCard.heightAnchor.constraint(equalTo: heroCard.widthAnchor, multiplier: heightToWidthRatio),
            ])
            setContentHuggingPriority(.required, for: .horizontal)
        } else {
            constraints.append(contentsOf: [
                heroCard.topAnchor.constraint(equalTo: topAnchor),
                heroCard.leadingAnchor.constraint(equalTo: leadingAnchor),
                heroCard.trailingAnchor.constraint(equalTo: trailingAnchor),
                heroCard.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        NSLayoutConstraint.activate(constraints)
    }

    func configure(expression: String, showFurigana: Bool = true) {
        let font = UIFontMetrics(forTextStyle: .largeTitle)
            .scaledFont(for: .systemFont(ofSize: 44, weight: .bold))
        if showFurigana {
            JapaneseFuriganaBuilder.applyScrubDisplay(
                to: wordLabel,
                attributed: JapaneseFuriganaBuilder.attributedString(
                    for: expression,
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
        } else {
            wordLabel.textInsets = .zero
            wordLabel.attributedText = nil
            wordLabel.font = font
            wordLabel.text = expression
            wordLabel.textColor = .label
        }
    }
}

// MARK: - Watermark

private func kanjiDecompositionWatermarkLabel() -> UILabel {
    let label = UILabel()
    label.text = "shizenapp.com"
    label.font = .systemFont(ofSize: 11, weight: .medium)
    label.textColor = UIColor.secondaryLabel.withAlphaComponent(0.65)
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}

/// Pins a `shizenapp.com` watermark to the bottom center of `host`.
private func installKanjiDecompositionWatermark(in host: UIView) {
    let label = kanjiDecompositionWatermarkLabel()
    host.addSubview(label)
    NSLayoutConstraint.activate([
        label.centerXAnchor.constraint(equalTo: host.centerXAnchor),
        label.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -14),
    ])
}

// MARK: - Readings list cell (On + Kun on one row)

private final class KanjiDecompositionReadingsCell: UICollectionViewListCell {
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
        rowStack.spacing = KanjiDecompositionListMetrics.inset(16)
        rowStack.distribution = .fillEqually
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: KanjiDecompositionListMetrics.inset(8)),
            rowStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -KanjiDecompositionListMetrics.inset(8)),
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
        titleLabel.font = .systemFont(ofSize: KanjiDecompositionListMetrics.size(10), weight: .semibold)
        titleLabel.textColor = .tertiaryLabel

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: KanjiDecompositionListMetrics.size(14), weight: .medium)
        valueLabel.textColor = .label
        valueLabel.numberOfLines = 1
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.65
        valueLabel.lineBreakMode = .byTruncatingTail

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        return stack
    }
}

// MARK: - Compound list cell (expression • gloss)

private final class KanjiDecompositionCompoundCell: UICollectionViewListCell {
    private let furiganaLabel = FuriganaTranscriptLabel()
    private let bulletLabel = UILabel()
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
        furiganaLabel.clipsToBounds = false
        furiganaLabel.numberOfLines = 1
        furiganaLabel.setContentHuggingPriority(.required, for: .horizontal)
        furiganaLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        bulletLabel.text = "•"
        bulletLabel.font = .systemFont(ofSize: KanjiDecompositionListMetrics.size(12), weight: .semibold)
        bulletLabel.textColor = .tertiaryLabel
        bulletLabel.setContentHuggingPriority(.required, for: .horizontal)

        glossLabel.font = .systemFont(ofSize: KanjiDecompositionListMetrics.size(13), weight: .regular)
        glossLabel.textColor = .secondaryLabel
        glossLabel.numberOfLines = 1
        glossLabel.lineBreakMode = .byTruncatingTail
        glossLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [furiganaLabel, bulletLabel, glossLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = KanjiDecompositionListMetrics.inset(6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: KanjiDecompositionListMetrics.inset(6)),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -KanjiDecompositionListMetrics.inset(6)),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }

    func configure(with entry: JMDictEntry) {
        let font = UIFont.systemFont(ofSize: KanjiDecompositionListMetrics.size(15), weight: .medium)
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
                bottom: 1,
                right: 0
            )
        )
        glossLabel.text = entry.firstGloss
    }
}

// MARK: - Intro card (page 1: teaser question, meaning withheld)

final class KanjiDecompositionIntroCardView: UIView {
    private let eyebrowLabel = UILabel()
    private let questionLabel = UILabel()
    private let wordHero = KanjiDecompositionWordHeroCard(fixedWidth: 200, heightToWidthRatio: 1.0)

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

        eyebrowLabel.font = .preferredFont(forTextStyle: .subheadline)
        eyebrowLabel.textColor = .secondaryLabel
        eyebrowLabel.textAlignment = .center
        eyebrowLabel.numberOfLines = 1

        questionLabel.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .systemFont(ofSize: 22, weight: .bold))
        questionLabel.textColor = .label
        questionLabel.textAlignment = .center
        questionLabel.numberOfLines = 0

        let contentStack = UIStackView(arrangedSubviews: [eyebrowLabel, questionLabel, wordHero])
        contentStack.axis = .vertical
        contentStack.alignment = .center
        contentStack.spacing = 12
        contentStack.setCustomSpacing(48, after: questionLabel)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)
        installKanjiDecompositionWatermark(in: self)

        NSLayoutConstraint.activate([
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    func configure(word: KanjiDecompositionWord, partLabel: String = "Kanji is literal, part 1") {
        applyPartLabel(partLabel)
        questionLabel.text = "Do you know the meaning of this kanji?"
        wordHero.configure(expression: word.expression, showFurigana: false)
    }

    func applyPartLabel(_ text: String) {
        eyebrowLabel.text = text
    }

    func eyebrowContains(point: CGPoint, in coordinateSpace: UIView) -> Bool {
        eyebrowLabel.convert(eyebrowLabel.bounds, to: coordinateSpace)
            .insetBy(dx: -10, dy: -8)
            .contains(point)
    }
}

// MARK: - Character card (pages 2 & 3)

final class KanjiDecompositionCharacterCardView: UIView, KanjiDecompositionBadgeLayoutHost {
    private enum Section: Int, CaseIterable {
        case readings
        case compounds

        var title: String {
            switch self {
            case .readings: return "Readings"
            case .compounds: return "Compounds"
            }
        }
    }

    private let heroView: KanjiDecompositionCharacterHeroView
    private let contentStack = UIStackView()
    private var collectionView: UICollectionView!
    private var collectionHeightConstraint: NSLayoutConstraint!

    private var onReading: String?
    private var kunReading: String?
    private var compounds: [JMDictEntry] = []

    private var headerRegistration: UICollectionView.SupplementaryRegistration<UICollectionViewListCell>!
    private var readingsCellRegistration: UICollectionView.CellRegistration<KanjiDecompositionReadingsCell, Void>!
    private var compoundCellRegistration: UICollectionView.CellRegistration<KanjiDecompositionCompoundCell, Int>!

    init(badgeIdentifier: KanjiDecompositionBadgeIdentifier) {
        heroView = KanjiDecompositionCharacterHeroView(
            layoutIdentifier: badgeIdentifier,
            badgePlacement: .trailingEdgeCentered
        )
        super.init(frame: .zero)
        setup()
    }

    override init(frame: CGRect) {
        heroView = KanjiDecompositionCharacterHeroView(
            layoutIdentifier: .character(index: 0),
            badgePlacement: .trailingEdgeCentered
        )
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        heroView = KanjiDecompositionCharacterHeroView(
            layoutIdentifier: .character(index: 0),
            badgePlacement: .trailingEdgeCentered
        )
        super.init(coder: coder)
        setup()
    }

    func characterHeroViews() -> [KanjiDecompositionCharacterHeroView] {
        [heroView]
    }

    func setBadgeEditingSelection(_ selectedIdentifier: KanjiDecompositionBadgeIdentifier?) {
        heroView.setEditingSelected(heroView.layoutIdentifier == selectedIdentifier)
    }

    private func setup() {
        backgroundColor = ExperimentPalette.pageBackground
        configureCollectionView()

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(heroView)
        contentStack.addArrangedSubview(collectionView)
        addSubview(contentStack)
        installKanjiDecompositionWatermark(in: self)

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
                ofSize: KanjiDecompositionListMetrics.size(11),
                weight: .semibold
            )
            configuration.textProperties.color = .secondaryLabel
            supplementaryView.contentConfiguration = configuration
        }

        readingsCellRegistration = UICollectionView.CellRegistration<KanjiDecompositionReadingsCell, Void> {
            [weak self] cell, _, _ in
            guard let self else { return }
            cell.configure(on: self.onReading, kun: self.kunReading)
        }

        compoundCellRegistration = UICollectionView.CellRegistration<KanjiDecompositionCompoundCell, Int> {
            [weak self] cell, _, row in
            guard let self, row < self.compounds.count else { return }
            cell.configure(with: self.compounds[row])
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
            // Pull the grouped cards in a bit past the default inset-grouped margins.
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
        case .readings: return 1
        case .compounds: return compounds.count
        }
    }

    private func updateCollectionHeightIfNeeded() {
        let width = bounds.width
        guard width > 0 else { return }

        let previousHeight = collectionHeightConstraint.constant

        // Measure with an expanded height first — when the height constraint is too
        // small, list cells clip and collectionViewContentSize under-reports.
        collectionHeightConstraint.constant = 10_000
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.layoutIfNeeded()

        let measured = collectionView.collectionViewLayout.collectionViewContentSize.height
        // Small buffer for section headers / separator insets the layout can under-count.
        let target = max(measured.rounded(.up) + 4, 1)
        collectionHeightConstraint.constant = target

        if abs(previousHeight - target) > 0.5 {
            setNeedsLayout()
        }
    }

    /// - Parameter excludingExpression: the combined word this character belongs to,
    ///   filtered out of the compounds list so it doesn't circularly appear as "a compound of itself".
    func configure(character: Character, excludingExpression: String) {
        let characterString = String(character)
        let detail = KanjidicStore.shared.detail(forKanji: characterString)

        heroView.configure(character: character, meaning: detail?.badgeMeaning ?? "")

        let on = detail?.onReadingList ?? []
        let kun = detail?.kunReadingList ?? []
        onReading = on.isEmpty ? nil : on.joined(separator: "、")
        kunReading = kun.isEmpty ? nil : kun.joined(separator: "、")

        compounds = Array(
            JMDictStore.shared.compounds(forSurface: characterString, limit: 6)
                .filter { $0.expression != excludingExpression }
                .prefix(3)
        )

        collectionView.reloadData()
        collectionView.collectionViewLayout.invalidateLayout()
        setNeedsLayout()
        layoutIfNeeded()
    }
}

extension KanjiDecompositionCharacterCardView: UICollectionViewDataSource {
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
        case .readings:
            return collectionView.dequeueConfiguredReusableCell(
                using: readingsCellRegistration,
                for: indexPath,
                item: ()
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

// MARK: - Teaser card (penultimate slide: parts + ?)

final class KanjiDecompositionTeaserCardView: UIView, KanjiDecompositionBadgeLayoutHost {
    private var previewHeroes: [KanjiDecompositionCharacterHeroView] = []
    private let previewContainer = UIView()
    private let previewRow = UIStackView()
    private let questionLabel = UILabel()

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
        kanjiDecompositionInstallPreviewContainer(previewContainer, row: previewRow)

        questionLabel.text = "?"
        questionLabel.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(
            for: .systemFont(ofSize: 72, weight: .bold)
        )
        questionLabel.textColor = .secondaryLabel
        questionLabel.textAlignment = .center

        let contentStack = UIStackView(arrangedSubviews: [previewContainer, questionLabel])
        contentStack.axis = .vertical
        contentStack.alignment = .center
        contentStack.spacing = 32
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)
        installKanjiDecompositionWatermark(in: self)

        NSLayoutConstraint.activate([
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            previewContainer.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
        ])
    }

    func configure(word: KanjiDecompositionWord) {
        kanjiDecompositionPopulatePreviewRow(previewRow, word: word, heroes: &previewHeroes)
    }

    func characterHeroViews() -> [KanjiDecompositionCharacterHeroView] {
        previewHeroes
    }

    func setBadgeEditingSelection(_ selectedIdentifier: KanjiDecompositionBadgeIdentifier?) {
        for hero in previewHeroes {
            hero.setEditingSelected(hero.layoutIdentifier == selectedIdentifier)
        }
    }
}

// MARK: - Combined card (final slide: reveal)

final class KanjiDecompositionCombinedCardView: UIView, KanjiDecompositionBadgeLayoutHost {
    private var previewHeroes: [KanjiDecompositionCharacterHeroView] = []
    private let previewContainer = UIView()
    private let previewRow = UIStackView()
    private let wordHero = KanjiDecompositionWordHeroCard(fixedWidth: 200, heightToWidthRatio: 1.0)
    private let meaningLabel = UILabel()

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
        kanjiDecompositionInstallPreviewContainer(previewContainer, row: previewRow)

        meaningLabel.font = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .systemFont(ofSize: 22, weight: .semibold)
        )
        meaningLabel.textColor = .label
        meaningLabel.textAlignment = .center
        meaningLabel.numberOfLines = 2
        meaningLabel.lineBreakMode = .byWordWrapping
        meaningLabel.adjustsFontSizeToFitWidth = true
        meaningLabel.minimumScaleFactor = 0.75

        let contentStack = UIStackView(arrangedSubviews: [previewContainer, wordHero, meaningLabel])
        contentStack.axis = .vertical
        contentStack.alignment = .center
        contentStack.spacing = 24
        contentStack.setCustomSpacing(32, after: previewContainer)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)
        installKanjiDecompositionWatermark(in: self)

        NSLayoutConstraint.activate([
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            previewContainer.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            meaningLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
        ])
    }

    func configure(word: KanjiDecompositionWord) {
        kanjiDecompositionPopulatePreviewRow(previewRow, word: word, heroes: &previewHeroes)
        wordHero.configure(expression: word.expression)
        meaningLabel.text = word.entry.firstGloss
    }

    func characterHeroViews() -> [KanjiDecompositionCharacterHeroView] {
        previewHeroes
    }

    func setBadgeEditingSelection(_ selectedIdentifier: KanjiDecompositionBadgeIdentifier?) {
        for hero in previewHeroes {
            hero.setEditingSelected(hero.layoutIdentifier == selectedIdentifier)
        }
    }
}
