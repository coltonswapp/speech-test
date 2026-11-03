//
//  PaywallComponents.swift
//  shizen
//
//  Building blocks shared by the paywall variants: CTA, plan rows, feature rows, badges.
//

import UIKit

enum PaywallCopy {
    struct Feature {
        /// Raw values are the `card` names in paywall analytics.
        enum Kind: String {
            case lessons, dialogue, insights, quizzes, flashcards
        }

        let kind: Kind
        let symbol: String
        let title: String
        let detail: String
        let tint: UIColor
    }

    static let features: [Feature] = [
        Feature(
            kind: .lessons,
            symbol: "play.square.stack.fill",
            title: "All 36 lessons",
            detail: "173 scenes and 2+ hours of dialogue audio, with more on the way",
            tint: .systemPink
        ),
        Feature(
            kind: .dialogue,
            symbol: "bubble.left.and.bubble.right.fill",
            title: "Japanese as it's really spoken",
            detail: "Dialogue written around how people actually talk, not textbook phrasing",
            tint: .systemOrange
        ),
        Feature(
            kind: .insights,
            symbol: "sparkles",
            title: "Smart insights",
            detail: "Tap any word for its meaning, grammar, and usage tips",
            tint: .systemBlue
        ),
        Feature(
            kind: .quizzes,
            symbol: "checkmark.bubble.fill",
            title: "Quizzes for every scene",
            detail: "Check you caught what was said before moving on",
            tint: .systemGreen
        ),
        Feature(
            kind: .flashcards,
            symbol: "rectangle.stack.fill",
            title: "Save flashcards",
            detail: "Keep the words you want and study them later",
            tint: .systemPurple
        ),
    ]

    static func ctaTitle(for package: PaywallPackage?) -> String {
        guard let package else { return "Continue" }
        if let days = package.trialDays { return "Start \(days)-day free trial" }
        return "Continue"
    }

    static func finePrint(for package: PaywallPackage?) -> String {
        guard let package else { return " " }
        if let days = package.trialDays {
            return "\(days) days free, then \(package.localizedPrice)/\(package.period.unit). Cancel anytime."
        }
        return "\(package.localizedPrice)/\(package.period.unit). Auto-renews until cancelled."
    }
}

func paywallDynamicColor(light: UIColor, dark: UIColor) -> UIColor {
    UIColor { $0.userInterfaceStyle == .dark ? dark : light }
}

// MARK: - CTA

final class PaywallCTAButton: UIButton {
    var title: String? {
        get { configuration?.title }
        set {
            guard newValue != configuration?.title else { return }
            UIView.transition(with: self, duration: 0.2, options: .transitionCrossDissolve) {
                self.configuration?.title = newValue
            }
        }
    }

    var isLoading = false {
        didSet {
            configuration?.showsActivityIndicator = isLoading
            isUserInteractionEnabled = !isLoading
        }
    }

    init(background: UIColor, foreground: UIColor, height: CGFloat = 56) {
        super.init(frame: .zero)
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = background
        config.baseForegroundColor = foreground
        config.imagePlacement = .trailing
        config.imagePadding = 8
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 17, weight: .semibold)
            return attributes
        }
        configuration = config
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Badge

final class PaywallBadgeLabel: UILabel {
    var insets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)

    init(text: String, fill: UIColor, textColor: UIColor, font: UIFont = .systemFont(ofSize: 11, weight: .bold)) {
        super.init(frame: .zero)
        self.text = text
        self.font = font
        self.textColor = textColor
        backgroundColor = fill
        layer.cornerCurve = .continuous
        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}

// MARK: - Plan row

/// A tappable control that stands for one package, so `bind(_:)` can wire any plan layout.
protocol PaywallPlanControl: UIControl {
    var package: PaywallPackage { get }
}

/// A full-width tappable plan: indicator, title + subtitle, trailing price, optional badge
/// straddling the top border.
final class PaywallPlanRow: UIControl, PaywallPlanControl {
    enum Indicator {
        case radio, check, none
    }

    struct Palette {
        var fill: UIColor
        var selectedFill: UIColor
        var border: UIColor
        var selectedBorder: UIColor
        var title: UIColor
        var detail: UIColor
        var indicator: UIColor
        var badgeFill: UIColor
        var badgeText: UIColor
    }

    let package: PaywallPackage
    private let palette: Palette
    private let indicator: Indicator
    private let indicatorView = UIImageView()
    /// Fill and border live here, not on `self`: a layer's border draws over its
    /// sublayers, so it would cut through a badge straddling the top edge.
    private let surface = UIView()
    private var glassView: UIVisualEffectView?

    init(
        package: PaywallPackage,
        title: String,
        subtitle: String?,
        trailing: String?,
        trailingDetail: String? = nil,
        badge: String? = nil,
        indicator: Indicator,
        palette: Palette,
        cornerRadius: CGFloat = 18,
        usesGlass: Bool = false
    ) {
        self.package = package
        self.palette = palette
        self.indicator = indicator
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        surface.layer.cornerRadius = cornerRadius
        surface.layer.cornerCurve = .continuous
        surface.isUserInteractionEnabled = false
        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        if usesGlass {
            let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
            glass.cornerConfiguration = .corners(radius: .fixed(cornerRadius))
            glass.isUserInteractionEnabled = false
            glass.translatesAutoresizingMaskIntoConstraints = false
            surface.addSubview(glass)
            NSLayoutConstraint.activate([
                glass.topAnchor.constraint(equalTo: surface.topAnchor),
                glass.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
                glass.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            ])
            glassView = glass
        }
        accessibilityTraits = .button
        isAccessibilityElement = true
        accessibilityLabel = [title, subtitle, trailing, trailingDetail, badge].compactMap { $0 }.joined(separator: ", ")

        let titleLabel = Self.label(title, font: .systemFont(ofSize: 17, weight: .semibold), color: palette.title)
        let leading = UIStackView(arrangedSubviews: [titleLabel])
        leading.axis = .vertical
        leading.spacing = 2
        if let subtitle {
            leading.addArrangedSubview(Self.label(subtitle, font: .systemFont(ofSize: 13), color: palette.detail))
        }

        let trailingStack = UIStackView()
        trailingStack.axis = .vertical
        trailingStack.alignment = .trailing
        trailingStack.spacing = 2
        if let trailing {
            trailingStack.addArrangedSubview(
                Self.label(trailing, font: .systemFont(ofSize: 15, weight: .semibold), color: palette.title)
            )
        }
        if let trailingDetail {
            trailingStack.addArrangedSubview(Self.label(trailingDetail, font: .systemFont(ofSize: 12), color: palette.detail))
        }

        let row = UIStackView(arrangedSubviews: [leading, trailingStack])
        row.alignment = .center
        row.spacing = 12
        if indicator != .none {
            indicatorView.translatesAutoresizingMaskIntoConstraints = false
            indicatorView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
            indicatorView.contentMode = .center
            NSLayoutConstraint.activate([
                indicatorView.widthAnchor.constraint(equalToConstant: 26),
                indicatorView.heightAnchor.constraint(equalToConstant: 26),
            ])
            row.insertArrangedSubview(indicatorView, at: 0)
        }
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
        ])

        if let badge {
            let badgeLabel = PaywallBadgeLabel(text: badge, fill: palette.badgeFill, textColor: palette.badgeText)
            addSubview(badgeLabel)
            NSLayoutConstraint.activate([
                badgeLabel.centerYAnchor.constraint(equalTo: topAnchor),
                badgeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            ])
        }
        updateAppearance()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (row: PaywallPlanRow, _: UITraitCollection) in
            row.updateAppearance()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isSelected: Bool {
        didSet {
            accessibilityTraits = isSelected ? [.button, .selected] : .button
            UIView.animate(withDuration: 0.2) { self.updateAppearance() }
        }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
            }
        }
    }

    private func updateAppearance() {
        surface.backgroundColor = isSelected ? palette.selectedFill : palette.fill
        surface.layer.borderWidth = isSelected ? 2 : 1
        surface.layer.borderColor = (isSelected ? palette.selectedBorder : palette.border).resolvedColor(with: traitCollection).cgColor
        if let glassView {
            let glass = UIGlassEffect(style: .regular)
            glass.tintColor = isSelected ? palette.selectedBorder.withAlphaComponent(0.22) : nil
            glassView.effect = glass
        }
        switch indicator {
        case .radio:
            indicatorView.image = UIImage(systemName: isSelected ? "largecircle.fill.circle" : "circle")
        case .check:
            indicatorView.image = UIImage(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        case .none:
            break
        }
        indicatorView.tintColor = isSelected ? palette.selectedBorder : palette.indicator
    }

    private static func label(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }
}

// MARK: - Plan tile

/// A glass plan tile meant to sit side by side with the others: period, big price,
/// per-week price, and a trial line, with an optional badge straddling the top border.
/// Selected tiles get a yellow border, a yellow-tinted glass, and a check in the corner.
/// `compact` trims the type and padding for tiles that share space with the CTA.
/// `inlineUnit` folds the period into the price ("$59.99/yr") for a shorter tile.
final class PaywallPlanTile: UIControl, PaywallPlanControl {
    let package: PaywallPackage
    private let accent: UIColor
    /// Border lives here, under the badge, for the same reason as `PaywallPlanRow`.
    private let surface = UIView()
    private let glassView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))

    init(package: PaywallPackage, badge: String?, compact: Bool = false, inlineUnit: Bool = false, accent: UIColor = Colors.ctaYellow, badgeText: UIColor = Colors.ctaDarkYellow) {
        self.package = package
        self.accent = accent
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let radius: CGFloat = compact ? 20 : 22
        surface.layer.cornerRadius = radius
        surface.layer.cornerCurve = .continuous
        surface.isUserInteractionEnabled = false
        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)
        glassView.cornerConfiguration = .corners(radius: .fixed(radius))
        glassView.isUserInteractionEnabled = false
        glassView.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(glassView)

        let period = Self.label(package.period.title, font: .systemFont(ofSize: compact ? 14 : 15, weight: .semibold), color: .label)
        let price = Self.label(package.localizedPrice, font: .systemFont(ofSize: compact ? 22 : 26, weight: .bold), color: .label)
        price.adjustsFontSizeToFitWidth = true
        price.minimumScaleFactor = 0.6
        price.numberOfLines = 1
        let detailSize: CGFloat = compact ? 12 : 13
        let perWeek = Self.label("\(package.pricePerWeek)/week", font: .systemFont(ofSize: detailSize, weight: .medium), color: .secondaryLabel)

        let stack = UIStackView(arrangedSubviews: [period, price])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        if inlineUnit {
            let text = NSMutableAttributedString(attributedString: price.attributedText ?? NSAttributedString())
            text.append(NSAttributedString(string: "/\(package.period.shortUnit)", attributes: [
                .font: UIFont.systemFont(ofSize: compact ? 15 : 17, weight: .semibold),
                .foregroundColor: UIColor.secondaryLabel,
            ]))
            price.attributedText = text
            stack.addArrangedSubview(perWeek)
            stack.setCustomSpacing(2, after: period)
            stack.setCustomSpacing(6, after: price)
        } else {
            let unit = Self.label("per \(package.period.unit)", font: .systemFont(ofSize: detailSize), color: .secondaryLabel)
            stack.addArrangedSubview(unit)
            stack.addArrangedSubview(perWeek)
            stack.setCustomSpacing(compact ? 6 : 10, after: period)
            stack.setCustomSpacing(compact ? 8 : 12, after: unit)
        }
        if let days = package.trialDays {
            stack.addArrangedSubview(Self.label("\(days) days free", font: .systemFont(ofSize: detailSize, weight: .semibold), color: Colors.deepYellow))
        }
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        check.tintColor = accent
        check.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: compact ? 18 : 20, weight: .semibold)
        check.translatesAutoresizingMaskIntoConstraints = false
        addSubview(check)

        let inset: CGFloat = inlineUnit ? 12 : compact ? 14 : 16
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.topAnchor.constraint(equalTo: surface.topAnchor),
            glassView.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
            glassView.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: surface.trailingAnchor),

            stack.topAnchor.constraint(equalTo: topAnchor, constant: inset + 2),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -inset),

            check.topAnchor.constraint(equalTo: topAnchor, constant: inset - 2),
            check.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(inset - 2)),
        ])
        // The stack's bottom is only an upper bound, so hug the content; otherwise a tile
        // next to an unsized view (like a scroll view) stretches to fill the space.
        let hug = heightAnchor.constraint(equalToConstant: 0)
        hug.priority = .fittingSizeLevel
        hug.isActive = true

        if let badge {
            let badgeLabel = PaywallBadgeLabel(text: badge, fill: accent, textColor: badgeText)
            addSubview(badgeLabel)
            NSLayoutConstraint.activate([
                badgeLabel.centerYAnchor.constraint(equalTo: topAnchor),
                badgeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            ])
        }

        isAccessibilityElement = true
        accessibilityLabel = [
            package.period.title,
            "\(package.localizedPrice) per \(package.period.unit)",
            package.trialDays.map { "\($0) days free" },
            badge,
        ].compactMap { $0 }.joined(separator: ", ")
        updateAppearance()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (tile: PaywallPlanTile, _: UITraitCollection) in
            tile.updateAppearance()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isSelected: Bool {
        didSet {
            accessibilityTraits = isSelected ? [.button, .selected] : .button
            UIView.animate(withDuration: 0.2) { self.updateAppearance() }
        }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
            }
        }
    }

    private func updateAppearance() {
        surface.layer.borderWidth = isSelected ? 2 : 1
        surface.layer.borderColor = (isSelected ? accent : UIColor.label.withAlphaComponent(0.08))
            .resolvedColor(with: traitCollection).cgColor
        let glass = UIGlassEffect(style: .regular)
        glass.tintColor = isSelected ? accent.withAlphaComponent(0.22) : nil
        glassView.effect = glass
        check.alpha = isSelected ? 1 : 0
        check.transform = isSelected ? .identity : CGAffineTransform(scaleX: 0.5, y: 0.5)
    }

    private static func label(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }
}

/// One tile per package, badged with its saving against monthly.
func makePaywallPlanTiles(
    for offering: PaywallOffering,
    compact: Bool = false,
    inlineUnit: Bool = false,
    accent: UIColor = Colors.ctaYellow,
    badgeText: UIColor = Colors.ctaDarkYellow
) -> [PaywallPlanTile] {
    let monthly = offering.monthly
    return offering.packages.map { package in
        let savings = monthly.flatMap { package == $0 ? nil : package.savingsPercent(comparedTo: $0) }
        return PaywallPlanTile(package: package, badge: savings.map { "SAVE \($0)%" }, compact: compact, inlineUnit: inlineUnit, accent: accent, badgeText: badgeText)
    }
}

/// Plan tiles side by side at equal widths; the row's `.fill` stretches each to the tallest.
func makePaywallPlanTileRow(_ tiles: [PaywallPlanTile]) -> UIStackView {
    let row = UIStackView(arrangedSubviews: tiles)
    row.spacing = 12
    row.distribution = .fillEqually
    row.alignment = .fill
    return row
}

// MARK: - Token highlight

/// An inline word drawn like a selected token in sentence scrub: white text on a rounded
/// system-blue fill. It's an image attachment so it wraps with the rest of the title;
/// give the label an `accessibilityLabel` with the plain text.
func makePaywallTokenHighlight(_ text: String, font: UIFont, traitCollection: UITraitCollection) -> NSAttributedString {
    let hPad = (font.pointSize * 0.14).rounded()
    let vPad: CGFloat = 2
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
    let textSize = (text as NSString).size(withAttributes: attributes)
    let height = font.ascender - font.descender + vPad * 2
    let size = CGSize(width: ceil(textSize.width + hPad * 2), height: ceil(height))
    let fill = UIColor.systemBlue.resolvedColor(with: traitCollection)
    let image = UIGraphicsImageRenderer(size: size).image { _ in
        // Same proportions as the scrub pill: soft corners, never a full capsule.
        let radius = min(font.pointSize * 0.2, size.height * 0.45)
        fill.setFill()
        UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: radius).fill()
        (text as NSString).draw(at: CGPoint(x: hPad, y: vPad), withAttributes: attributes)
    }
    let attachment = NSTextAttachment(image: image)
    // Sit the drawn text on the line's baseline.
    attachment.bounds = CGRect(x: 0, y: font.descender - vPad, width: size.width, height: size.height)
    return NSAttributedString(attachment: attachment)
}

// MARK: - Feature row

enum PaywallFeatureRowStyle {
    /// Colored rounded-square tile behind the symbol.
    case tile
    /// Bare symbol in the text color.
    case plain
}

func makePaywallFeatureRow(
    _ feature: PaywallCopy.Feature,
    style: PaywallFeatureRowStyle,
    titleColor: UIColor = .label,
    detailColor: UIColor = .secondaryLabel,
    showsDetail: Bool = true
) -> UIView {
    let icon = UIImageView(image: UIImage(systemName: feature.symbol))
    icon.translatesAutoresizingMaskIntoConstraints = false
    icon.contentMode = .center

    let iconHolder: UIView
    switch style {
    case .tile:
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        icon.tintColor = .white
        let tile = UIView()
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.backgroundColor = feature.tint
        tile.layer.cornerRadius = 10
        tile.layer.cornerCurve = .continuous
        tile.addSubview(icon)
        NSLayoutConstraint.activate([
            tile.widthAnchor.constraint(equalToConstant: 36),
            tile.heightAnchor.constraint(equalToConstant: 36),
            icon.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
        ])
        iconHolder = tile
    case .plain:
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        icon.tintColor = titleColor
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 24),
        ])
        iconHolder = icon
    }

    let title = UILabel()
    title.text = feature.title
    title.font = .systemFont(ofSize: 16, weight: .semibold)
    title.textColor = titleColor
    title.numberOfLines = 0
    title.adjustsFontForContentSizeCategory = true

    let text = UIStackView(arrangedSubviews: [title])
    text.axis = .vertical
    text.spacing = 2
    if showsDetail {
        let detail = UILabel()
        detail.text = feature.detail
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = detailColor
        detail.numberOfLines = 0
        detail.adjustsFontForContentSizeCategory = true
        text.addArrangedSubview(detail)
    }

    let row = UIStackView(arrangedSubviews: [iconHolder, text])
    row.alignment = showsDetail ? .top : .center
    row.spacing = 14
    return row
}
