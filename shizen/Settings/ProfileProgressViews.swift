//
//  ProfileProgressViews.swift
//  shizen
//
//  Profile cards: the stat tiles, one colored row per JLPT level with a
//  progress bar, and Hana at the bottom, who changes mood when tapped.
//

import UIKit

// MARK: - Shared styling

enum ProfileProgressStyle {
    enum Variant {
        /// One color per stat and per level.
        case colorful
        /// Solid brand badges with white glyphs: yellow levels; yellow, blue
        /// and pink stats.
        case yellow
    }

    static var variant: Variant = .yellow

    enum Stat {
        case stars, scenes, days
    }

    struct TileColors {
        var background: UIColor
        var badge: UIColor
        var symbol: UIColor
        var value: UIColor
        var caption: UIColor
    }

    struct LevelColors {
        var badge: UIColor
        var badgeText: UIColor
        var barFill: UIColor
        var barTrack: UIColor
    }

    /// Corner radius of an iOS 26 inset-grouped section. Stat tiles use it so they
    /// read as siblings of the sections; level badges nest inside it.
    static let sectionCornerRadius: CGFloat = 26

    /// Radius for a shape inset from the section edge, so its corner follows the
    /// section's curve instead of fighting it.
    static func concentricRadius(inset: CGFloat, minimum: CGFloat = 8) -> CGFloat {
        max(sectionCornerRadius - inset, minimum)
    }

    /// Extra leading and trailing padding on level rows, beyond the cell margins.
    static let levelRowExtraInset: CGFloat = 6

    static var starColor: UIColor {
        variant == .yellow ? Colors.ctaYellow : .systemYellow
    }

    static func colors(for stat: Stat) -> TileColors {
        switch variant {
        case .colorful:
            let tint: UIColor
            switch stat {
            case .stars: tint = .systemYellow
            case .scenes: tint = .systemGreen
            case .days: tint = .systemPink
            }
            return TileColors(
                background: .secondarySystemGroupedBackground,
                badge: tint.withAlphaComponent(0.16),
                symbol: tint,
                value: .label,
                caption: .secondaryLabel
            )
        case .yellow:
            let badge: UIColor
            switch stat {
            case .stars: badge = Colors.ctaYellow
            case .scenes: badge = Colors.petalBlue
            case .days: badge = Colors.petalPink
            }
            return TileColors(
                background: .secondarySystemGroupedBackground,
                badge: badge,
                symbol: .white,
                value: .label,
                caption: .secondaryLabel
            )
        }
    }

    static func colors(forLevel level: Int) -> LevelColors {
        switch variant {
        case .colorful:
            let tint: UIColor
            switch level {
            case 5: tint = .systemGreen
            case 4: tint = .systemBlue
            case 3: tint = .systemPurple
            case 2: tint = .systemOrange
            default: tint = .systemPink
            }
            return LevelColors(
                badge: tint.withAlphaComponent(0.16),
                badgeText: tint,
                barFill: tint,
                barTrack: tint.withAlphaComponent(0.16)
            )
        case .yellow:
            return LevelColors(
                badge: Colors.ctaYellow,
                badgeText: .white,
                barFill: Colors.ctaYellow,
                barTrack: Colors.ctaYellow.withAlphaComponent(0.22)
            )
        }
    }

    static func roundedFont(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let font = UIFont.systemFont(ofSize: base.pointSize, weight: weight)
        guard let rounded = font.fontDescriptor.withDesign(.rounded) else { return font }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: rounded, size: 0))
    }
}

/// Capsule bar. Fill width is a fraction of the track.
final class ProfileProgressBar: UIView {
    private let fill = UIView()

    var progress: CGFloat = 0 {
        didSet { setNeedsLayout() }
    }

    var fillColor: UIColor = .systemGreen {
        didSet { applyColors() }
    }

    var trackColor: UIColor = UIColor.systemGreen.withAlphaComponent(0.16) {
        didSet { applyColors() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(fill)
        applyColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 8)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        let clamped = min(max(progress, 0), 1)
        // A sliver of color even at a few percent, so started levels look started.
        let width = clamped > 0 ? max(bounds.width * clamped, bounds.height) : 0
        fill.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        fill.layer.cornerRadius = bounds.height / 2
    }

    private func applyColors() {
        backgroundColor = trackColor
        fill.backgroundColor = fillColor
    }
}

// MARK: - Stat tiles

struct ProfileStatsContentConfiguration: UIContentConfiguration, Hashable {
    var stars: Int
    var scenesCompleted: Int
    /// Nil when the join date is unknown; the days tile is left out.
    var daysSinceJoining: Int?

    func makeContentView() -> UIView & UIContentView {
        ProfileStatsContentView(configuration: self)
    }

    func updated(for state: UIConfigurationState) -> Self { self }
}

private final class ProfileStatsContentView: UIView, UIContentView {
    private let stack = UIStackView()
    private var current: ProfileStatsContentConfiguration

    var configuration: UIContentConfiguration {
        get { current }
        set {
            guard let config = newValue as? ProfileStatsContentConfiguration, config != current else { return }
            current = config
            rebuild()
        }
    }

    init(configuration: ProfileStatsContentConfiguration) {
        current = configuration
        super.init(frame: .zero)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .fill
        stack.spacing = 10
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        rebuild()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stack.addArrangedSubview(makeTile(
            symbol: "star.fill",
            colors: ProfileProgressStyle.colors(for: .stars),
            value: current.stars.formatted(),
            caption: "Stars\ncollected"
        ))
        stack.addArrangedSubview(makeTile(
            symbol: "checkmark.seal.fill",
            colors: ProfileProgressStyle.colors(for: .scenes),
            value: current.scenesCompleted.formatted(),
            caption: "Scenes\ncompleted"
        ))
        if let days = current.daysSinceJoining {
            stack.addArrangedSubview(makeTile(
                symbol: "leaf.fill",
                colors: ProfileProgressStyle.colors(for: .days),
                value: days == 0 ? "New" : days.formatted(),
                caption: "Days as\na member"
            ))
        }
    }

    private func makeTile(
        symbol: String,
        colors: ProfileProgressStyle.TileColors,
        value: String,
        caption: String
    ) -> UIView {
        let tile = UIView()
        tile.backgroundColor = colors.background
        tile.layer.cornerRadius = ProfileProgressStyle.sectionCornerRadius
        tile.layer.cornerCurve = .continuous

        let badge = UIView()
        badge.backgroundColor = colors.badge
        badge.layer.cornerRadius = 15
        badge.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        ))
        icon.tintColor = colors.symbol
        icon.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(icon)

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = ProfileProgressStyle.roundedFont(.title1, weight: .bold)
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.6
        valueLabel.textColor = colors.value

        let captionLabel = UILabel()
        captionLabel.text = caption
        captionLabel.numberOfLines = 2
        captionLabel.font = .preferredFont(forTextStyle: .caption1)
        captionLabel.adjustsFontForContentSizeCategory = true
        captionLabel.textColor = colors.caption

        let column = UIStackView(arrangedSubviews: [badge, valueLabel, captionLabel])
        column.axis = .vertical
        column.alignment = .leading
        column.spacing = 6
        column.setCustomSpacing(10, after: badge)
        column.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(column)

        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 30),
            badge.heightAnchor.constraint(equalToConstant: 30),
            icon.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            column.topAnchor.constraint(equalTo: tile.topAnchor, constant: 14),
            column.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 14),
            column.trailingAnchor.constraint(lessThanOrEqualTo: tile.trailingAnchor, constant: -10),
            column.bottomAnchor.constraint(equalTo: tile.bottomAnchor, constant: -14),
        ])

        tile.isAccessibilityElement = true
        tile.accessibilityLabel = "\(value), \(caption.replacingOccurrences(of: "\n", with: " "))"
        return tile
    }
}

// MARK: - Level row

struct ProfileLevelContentConfiguration: UIContentConfiguration, Hashable {
    var level: Int
    var completed: Int
    var total: Int
    var stars: Int

    func makeContentView() -> UIView & UIContentView {
        ProfileLevelContentView(configuration: self)
    }

    func updated(for state: UIConfigurationState) -> Self { self }
}

private final class ProfileLevelContentView: UIView, UIContentView {
    private let badge = UIView()
    private let badgeLabel = UILabel()
    private let percentLabel = UILabel()
    private let bar = ProfileProgressBar()
    private let detailLabel = UILabel()
    private var current: ProfileLevelContentConfiguration

    var configuration: UIContentConfiguration {
        get { current }
        set {
            guard let config = newValue as? ProfileLevelContentConfiguration else { return }
            current = config
            apply()
        }
    }

    init(configuration: ProfileLevelContentConfiguration) {
        current = configuration
        super.init(frame: .zero)
        layout()
        apply()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func layout() {
        badge.layer.cornerCurve = .continuous
        badge.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = ProfileProgressStyle.roundedFont(.headline, weight: .heavy)
        badgeLabel.adjustsFontForContentSizeCategory = true
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(badgeLabel)

        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel

        percentLabel.font = ProfileProgressStyle.roundedFont(.footnote, weight: .semibold)
        percentLabel.textColor = .secondaryLabel
        percentLabel.adjustsFontForContentSizeCategory = true
        percentLabel.setContentHuggingPriority(.required, for: .horizontal)
        percentLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let barRow = UIStackView(arrangedSubviews: [bar, percentLabel])
        barRow.spacing = 10
        barRow.alignment = .center

        let column = UIStackView(arrangedSubviews: [detailLabel, barRow])
        column.axis = .vertical
        column.spacing = 8

        let row = UIStackView(arrangedSubviews: [badge, column])
        row.spacing = 14
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 44),
            badge.heightAnchor.constraint(equalToConstant: 44),
            badgeLabel.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            badgeLabel.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            row.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor, constant: 6),
            row.leadingAnchor.constraint(
                equalTo: layoutMarginsGuide.leadingAnchor,
                constant: ProfileProgressStyle.levelRowExtraInset
            ),
            row.trailingAnchor.constraint(
                equalTo: layoutMarginsGuide.trailingAnchor,
                constant: -ProfileProgressStyle.levelRowExtraInset
            ),
            row.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor, constant: -6),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Inset of the badge from the cell's (and so the section's) leading edge.
        var cell = superview
        while let view = cell, !(view is UICollectionViewCell) { cell = view.superview }
        let inset = cell.map { badge.convert(CGPoint.zero, to: $0).x } ?? badge.frame.minX
        badge.layer.cornerRadius = ProfileProgressStyle.concentricRadius(inset: inset)
    }

    private func apply() {
        let colors = ProfileProgressStyle.colors(forLevel: current.level)
        let fraction = Double(current.completed) / Double(max(current.total, 1))

        badge.backgroundColor = colors.badge
        badgeLabel.textColor = colors.badgeText
        badgeLabel.text = "N\(current.level)"

        bar.fillColor = colors.barFill
        bar.trackColor = colors.barTrack
        bar.progress = CGFloat(fraction)
        percentLabel.text = fraction.formatted(.percent.precision(.fractionLength(0)))

        let scenes = "\(current.completed) of \(current.total) scenes"
        let star = NSTextAttachment(image: UIImage(
            systemName: "star.fill",
            withConfiguration: UIImage.SymbolConfiguration(textStyle: .caption2, scale: .small)
        )!.withTintColor(ProfileProgressStyle.starColor, renderingMode: .alwaysOriginal))
        let detail = NSMutableAttributedString(string: "\(scenes) • ")
        detail.append(NSAttributedString(attachment: star))
        detail.append(NSAttributedString(string: " \(current.stars)"))
        detailLabel.attributedText = detail

        isAccessibilityElement = true
        let starWord = current.stars == 1 ? "star" : "stars"
        accessibilityLabel = "N\(current.level), \(scenes), \(current.stars) \(starWord)"
        accessibilityValue = percentLabel.text
    }
}

// MARK: - Hana

struct ProfileHanaContentConfiguration: UIContentConfiguration, Hashable {
    func makeContentView() -> UIView & UIContentView {
        ProfileHanaContentView(configuration: self)
    }

    func updated(for state: UIConfigurationState) -> Self { self }
}

/// Hana sits under the list. Each tap moves her to the next mood.
private final class ProfileHanaContentView: UIView, UIContentView {
    private static let moods: [MascotPreset] = [.happy, .excited, .wink]

    var configuration: UIContentConfiguration = ProfileHanaContentConfiguration()

    private let mascot = MascotView(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
    private var moodIndex = 0
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    init(configuration: ProfileHanaContentConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)

        mascot.setTheme(.pink, animated: false)
        mascot.hapticsEnabled = false
        mascot.isUserInteractionEnabled = false
        mascot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mascot)

        NSLayoutConstraint.activate([
            mascot.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            mascot.centerXAnchor.constraint(equalTo: centerXAnchor),
            mascot.widthAnchor.constraint(equalToConstant: 120),
            mascot.heightAnchor.constraint(equalToConstant: 120),
            mascot.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "Changes Hana's mood."
        showMood(animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func tapped() {
        moodIndex = (moodIndex + 1) % Self.moods.count
        haptics.impactOccurred()
        showMood(animated: true)
    }

    private func showMood(animated: Bool) {
        let mood = Self.moods[moodIndex]
        if animated {
            mascot.play(mood)
        } else {
            mascot.set(mood.expression, animated: false)
        }
        accessibilityLabel = "Hana, \(mood.title.lowercased())"
    }
}
