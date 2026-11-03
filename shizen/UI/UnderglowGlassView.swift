//
//  UnderglowGlassView.swift
//  shizen
//
//  Liquid-glass plate with a colored underglow behind it (see
//  docs/underglow-glass-component.md). Add content with `addSubview`; the glow
//  and glass are installed first, so they always sit behind it.
//

import InteractionKit
import UIKit

final class UnderglowGlassView: UIView {
    /// Clips the glow to the glass shape so its falloff can't tint past the corners.
    private let glowClipView = UIView()
    private let glowView = UIView()
    private let gradientLayer = CAGradientLayer()
    private let glassView: UIVisualEffectView
    private let glassCornerRadius: CGFloat

    var configuration: DialogueBubbleUnderglowConfiguration {
        didSet {
            applyGlowAppearance()
            setNeedsLayout()
        }
    }

    /// Static plates (slides, cards) use non-interactive glass; tappable chrome can opt in.
    init(
        configuration: DialogueBubbleUnderglowConfiguration = .default,
        cornerRadius: CGFloat = 18,
        isInteractive: Bool = false
    ) {
        self.configuration = configuration
        self.glassCornerRadius = cornerRadius
        glassView = isInteractive ? LiquidGlassEffectView.makeContainer() : LiquidGlassEffectView.makeLightPillContainer()
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        clipsToBounds = false
        backgroundColor = .clear

        glowClipView.translatesAutoresizingMaskIntoConstraints = false
        glowClipView.isUserInteractionEnabled = false
        glowClipView.backgroundColor = .clear
        glowClipView.clipsToBounds = true
        glowClipView.layer.cornerRadius = glassCornerRadius
        glowClipView.layer.cornerCurve = .continuous

        glowView.translatesAutoresizingMaskIntoConstraints = true
        glowView.isUserInteractionEnabled = false
        glowView.backgroundColor = .clear
        glowView.clipsToBounds = false
        gradientLayer.type = .radial
        glowView.layer.addSublayer(gradientLayer)

        LiquidGlassEffectView.applyBubbleStyle(to: glassView, cornerRadius: glassCornerRadius)
        glassView.isUserInteractionEnabled = false

        glowClipView.addSubview(glowView)
        addSubview(glowClipView)
        addSubview(glassView)
        NSLayoutConstraint.activate([
            glowClipView.topAnchor.constraint(equalTo: topAnchor),
            glowClipView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glowClipView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glowClipView.bottomAnchor.constraint(equalTo: bottomAnchor),

            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        applyGlowAppearance()
        applyBorderColor()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutGlow()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyBorderColor()
    }

    /// The bubble hairline is white, which disappears on pale slide pages.
    private func applyBorderColor() {
        guard traitCollection.userInterfaceStyle != .dark else { return }
        glassView.layer.borderColor = ExperimentPalette.cardBorder.resolvedColor(with: traitCollection).cgColor
    }

    private func applyGlowAppearance() {
        let color = configuration.glowUIColor
        let blur = configuration.blurRadius
        glowView.alpha = configuration.opacity

        if blur <= 0 {
            gradientLayer.colors = [color.cgColor, color.cgColor]
            gradientLayer.locations = [0, 1]
            glowView.layer.shadowOpacity = 0
            glowView.layer.shadowPath = nil
        } else {
            let midStop = max(0.2, min(0.8, 0.55 - blur / 80))
            gradientLayer.colors = [
                color.cgColor,
                color.withAlphaComponent(0.4).cgColor,
                UIColor.clear.cgColor,
            ]
            gradientLayer.locations = [0, NSNumber(value: Float(midStop)), 1]
            glowView.layer.shadowColor = color.cgColor
            glowView.layer.shadowRadius = blur
            glowView.layer.shadowOpacity = Float(configuration.shadowOpacity)
            glowView.layer.shadowOffset = .zero
        }

        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.cornerCurve = .continuous
    }

    private func layoutGlow() {
        let coreFrame = configuration.glowFrame(in: bounds)
        guard coreFrame.width > 0, coreFrame.height > 0 else {
            glowView.frame = .zero
            gradientLayer.frame = .zero
            glowView.layer.shadowPath = nil
            return
        }

        let blur = configuration.blurRadius
        let padding = blur > 0 ? blur * 0.75 : 0
        glowView.frame = coreFrame.insetBy(dx: -padding, dy: -padding)
        gradientLayer.frame = glowView.bounds
        gradientLayer.cornerRadius = configuration.cornerRadius

        if blur > 0 {
            let shapeRect = configuration.shadowShapeRect(coreSize: coreFrame.size, padding: padding)
            glowView.layer.shadowPath = UIBezierPath(
                roundedRect: shapeRect,
                cornerRadius: configuration.cornerRadius
            ).cgPath
        }
    }
}
