//
//  DialogueJapaneseBubbleView.swift
//  shizen
//
//  Rounded iMessage-style bubble behind spoken Japanese dialogue lines.
//

import UIKit

enum DialogueBubbleBackgroundStyle {
    case solid
    case glass
}

/// Wraps a furigana label in a padded bubble that highlights while the line is active.
final class DialogueJapaneseBubbleView: UIView {

    private(set) var label: FuriganaTranscriptLabel

    private let solidBackgroundView = UIView()
    private let glassGlowView = UIView()
    private let underglowGradientLayer = CAGradientLayer()
    private let glassBackgroundView = LiquidGlassEffectView.makeContainer()
    private var highlightGradientLayer: CAGradientLayer?
    private var emphasisAmount: CGFloat = 0
    private var swipeRevealAmount: CGFloat = 0
    private var backgroundStyle: DialogueBubbleBackgroundStyle = .glass
    private var underglowConfiguration = DialogueBubbleUnderglowConfiguration.default

    private static let cornerRadius: CGFloat = 18
    private static let contentPadding = UIEdgeInsets(top: 6, left: 12, bottom: 3, right: 12)
    private static let bubbleFillColor = UIColor.systemBlue

    static var horizontalContentPadding: CGFloat {
        contentPadding.left + contentPadding.right
    }

    init(label: FuriganaTranscriptLabel) {
        self.label = label
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false

        solidBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        solidBackgroundView.isUserInteractionEnabled = false
        solidBackgroundView.layer.cornerRadius = Self.cornerRadius
        solidBackgroundView.layer.cornerCurve = .continuous
        solidBackgroundView.clipsToBounds = true
        solidBackgroundView.backgroundColor = .clear

        glassGlowView.translatesAutoresizingMaskIntoConstraints = true
        glassGlowView.isUserInteractionEnabled = false
        glassGlowView.backgroundColor = .clear
        glassGlowView.clipsToBounds = false
        underglowGradientLayer.type = .radial
        glassGlowView.layer.addSublayer(underglowGradientLayer)
        applyUnderglowAppearance()
        glassGlowView.isHidden = true
        glassGlowView.alpha = 0

        LiquidGlassEffectView.applyBubbleStyle(to: glassBackgroundView, cornerRadius: Self.cornerRadius)
        glassBackgroundView.isUserInteractionEnabled = false
        glassBackgroundView.isHidden = true
        glassBackgroundView.alpha = 0

        addSubview(solidBackgroundView)
        addSubview(glassGlowView)
        addSubview(glassBackgroundView)
        addSubview(label)

        NSLayoutConstraint.activate([
            solidBackgroundView.topAnchor.constraint(equalTo: topAnchor),
            solidBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            solidBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            solidBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            glassBackgroundView.topAnchor.constraint(equalTo: topAnchor),
            glassBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            label.topAnchor.constraint(equalTo: topAnchor, constant: Self.contentPadding.top),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.contentPadding.left),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.contentPadding.right),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.contentPadding.bottom),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutUnderglow()
        solidBackgroundView.layoutIfNeeded()
        updateHighlightDecoration()
    }

    override var forFirstBaselineLayout: UIView {
        label
    }

    override var forLastBaselineLayout: UIView {
        label
    }

    func setBackgroundStyle(_ style: DialogueBubbleBackgroundStyle) {
        guard style != backgroundStyle else { return }
        backgroundStyle = style
        applyEmphasisVisuals()
        setNeedsLayout()
    }

    func setUnderglowConfiguration(_ configuration: DialogueBubbleUnderglowConfiguration) {
        underglowConfiguration = configuration
        applyUnderglowAppearance()
        setNeedsLayout()
    }

    var currentUnderglowConfiguration: DialogueBubbleUnderglowConfiguration {
        underglowConfiguration
    }

    func setActive(_ active: Bool) {
        setEmphasis(active ? 1 : 0)
    }

    func setEmphasis(_ emphasis: CGFloat) {
        let clamped = max(0, min(1, emphasis))
        let changed = abs(clamped - emphasisAmount) > 0.001
        emphasisAmount = clamped
        applyEmphasisVisuals()
        if changed {
            setNeedsLayout()
        }
    }

    func setSwipeRevealAmount(_ amount: CGFloat) {
        let clamped = max(0, min(1, amount))
        guard abs(clamped - swipeRevealAmount) > 0.001 else { return }
        swipeRevealAmount = clamped
        applyEmphasisVisuals()
        setNeedsLayout()
    }

    private var combinedGlassAmount: CGFloat {
        max(emphasisAmount, swipeRevealAmount)
    }

    private var isBubbleActive: Bool {
        combinedGlassAmount > 0.001
    }

    private func applyEmphasisVisuals() {
        let glassAmount = combinedGlassAmount
        switch backgroundStyle {
        case .solid:
            solidBackgroundView.isHidden = !isBubbleActive
            solidBackgroundView.alpha = glassAmount
            solidBackgroundView.backgroundColor = isBubbleActive
                ? Self.bubbleFillColor
                : .clear
            glassGlowView.isHidden = true
            glassGlowView.alpha = 0
            glassBackgroundView.isHidden = true
            glassBackgroundView.alpha = 0
        case .glass:
            solidBackgroundView.isHidden = true
            solidBackgroundView.alpha = 0
            solidBackgroundView.backgroundColor = .clear
            glassGlowView.isHidden = !isBubbleActive
            glassGlowView.alpha = glassAmount * underglowConfiguration.opacity
            glassBackgroundView.isHidden = !isBubbleActive
            glassBackgroundView.alpha = glassAmount
        }
    }

    private func applyUnderglowAppearance() {
        let color = underglowConfiguration.glowUIColor
        let blur = underglowConfiguration.blurRadius

        if blur <= 0 {
            underglowGradientLayer.colors = [color.cgColor, color.cgColor]
            underglowGradientLayer.locations = [0, 1]
            glassGlowView.layer.shadowOpacity = 0
            glassGlowView.layer.shadowPath = nil
        } else {
            let midStop = max(0.2, min(0.8, 0.55 - blur / 80))
            underglowGradientLayer.colors = [
                color.cgColor,
                color.withAlphaComponent(0.4).cgColor,
                UIColor.clear.cgColor,
            ]
            underglowGradientLayer.locations = [0, NSNumber(value: Float(midStop)), 1]
            glassGlowView.layer.shadowColor = color.cgColor
            glassGlowView.layer.shadowRadius = blur
            glassGlowView.layer.shadowOpacity = 0.5
            glassGlowView.layer.shadowOffset = .zero
        }

        underglowGradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        underglowGradientLayer.endPoint = CGPoint(x: 1, y: 1)
        underglowGradientLayer.cornerCurve = .continuous
    }

    private func layoutUnderglow() {
        let coreFrame = underglowConfiguration.glowFrame(in: bounds)
        guard coreFrame.width > 0, coreFrame.height > 0 else {
            glassGlowView.frame = .zero
            underglowGradientLayer.frame = .zero
            glassGlowView.layer.shadowPath = nil
            return
        }

        let blur = underglowConfiguration.blurRadius
        let padding = blur > 0 ? blur * 0.75 : 0
        glassGlowView.frame = coreFrame.insetBy(dx: -padding, dy: -padding)
        underglowGradientLayer.frame = glassGlowView.bounds
        underglowGradientLayer.cornerRadius = underglowConfiguration.cornerRadius

        if blur > 0 {
            let shapeRect = CGRect(
                x: padding,
                y: padding,
                width: coreFrame.width,
                height: coreFrame.height
            )
            glassGlowView.layer.shadowPath = UIBezierPath(
                roundedRect: shapeRect,
                cornerRadius: underglowConfiguration.cornerRadius
            ).cgPath
        }
    }

    private func updateHighlightDecoration() {
        highlightGradientLayer?.removeFromSuperlayer()
        highlightGradientLayer = nil
        guard backgroundStyle == .solid,
              isBubbleActive,
              solidBackgroundView.bounds.width > 0,
              solidBackgroundView.bounds.height > 0 else { return }

        let shapeLayer = CAShapeLayer()
        let inset: CGFloat = 0.25
        let path = UIBezierPath(
            roundedRect: solidBackgroundView.bounds.insetBy(dx: inset, dy: inset),
            cornerRadius: Self.cornerRadius - inset
        )
        shapeLayer.path = path.cgPath
        shapeLayer.strokeColor = UIColor.white.withAlphaComponent(0.3).cgColor
        shapeLayer.lineWidth = 4
        shapeLayer.fillColor = UIColor.clear.cgColor

        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = solidBackgroundView.bounds
        gradientLayer.colors = [
            UIColor.white.withAlphaComponent(0.8).cgColor,
            UIColor.clear.cgColor,
            UIColor.clear.cgColor,
            UIColor.blue.withAlphaComponent(0.8).cgColor,
        ]
        gradientLayer.locations = [0.0, 0.25, 0.75, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        gradientLayer.mask = shapeLayer
        gradientLayer.opacity = Float(emphasisAmount)

        solidBackgroundView.layer.addSublayer(gradientLayer)
        highlightGradientLayer = gradientLayer
    }
}
