//
//  SlideHeroCardView.swift
//  shizen
//
//  The rounded plate behind the main subject on every slideshow card (kanji
//  glyph, word, hook verb, register sentence). Solid is the original white card;
//  glass is liquid glass over a colored underglow. Style and glow color come
//  from ExperimentSettings, so live slides and export rebuilds always match.
//

import UIKit

enum SlideHeroStyle: String, CaseIterable {
    case solid
    case glass

    var title: String {
        switch self {
        case .solid: return "Solid card"
        case .glass: return "Glass + underglow"
        }
    }
}

final class SlideHeroCardView: UIView {
    private static let solidCornerRadius: CGFloat = 10
    private static let glassCornerRadius: CGFloat = 18

    let style: SlideHeroStyle
    private var glassView: UnderglowGlassView?

    init(
        style: SlideHeroStyle = ExperimentSettings.slideHeroStyle,
        glowColor: DialogueBubbleUnderglowColor = ExperimentSettings.slideHeroGlowColor
    ) {
        self.style = style
        super.init(frame: .zero)
        switch style {
        case .solid:
            configureSolid()
        case .glass:
            configureGlass(glowColor: glowColor)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard style == .solid else { return }
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Self.solidCornerRadius).cgPath
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard style == .solid else { return }
        applySolidBorderAndShadow()
        setNeedsLayout()
    }

    /// Recolors the underglow; no-op on solid cards.
    func setGlowColor(_ color: DialogueBubbleUnderglowColor) {
        glassView?.configuration.color = color
    }

    // MARK: Solid

    private func configureSolid() {
        clipsToBounds = false
        layer.cornerRadius = Self.solidCornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = false
        backgroundColor = ExperimentPalette.cardSurface
        layer.borderWidth = ExperimentCardStroke.normalWidth
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 1)
        applySolidBorderAndShadow()
    }

    private func applySolidBorderAndShadow() {
        layer.borderColor = ExperimentPalette.cardBorder.resolvedColor(with: traitCollection).cgColor
        layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.35 : 0.08
    }

    // MARK: Glass

    /// Installed as the first subview, so content the card hosts lands on top of the glass.
    private func configureGlass(glowColor: DialogueBubbleUnderglowColor) {
        clipsToBounds = false
        backgroundColor = .clear

        var configuration = DialogueBubbleUnderglowConfiguration.default
        configuration.color = glowColor
        let glass = UnderglowGlassView(configuration: configuration, cornerRadius: Self.glassCornerRadius)
        glass.translatesAutoresizingMaskIntoConstraints = false
        glassView = glass
        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
