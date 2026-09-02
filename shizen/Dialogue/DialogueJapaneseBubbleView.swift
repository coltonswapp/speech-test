//
//  DialogueJapaneseBubbleView.swift
//  shizen
//
//  Rounded iMessage-style bubble behind spoken Japanese dialogue lines.
//

import InteractionKit
import UIKit

enum DialogueBubbleBackgroundStyle {
    case solid
    case glass
}

enum DialogueBubbleTailEdge: Equatable {
    case none
    case leading
    case trailing
}

/// Wraps a furigana label in a padded glass bubble. The chrome stays visible;
/// emphasis drives underglow, while the host scales the bubble and recolors text.
final class DialogueJapaneseBubbleView: UIView {

    private(set) var label: FuriganaTranscriptLabel

    private let solidBackgroundView = UIView()
    private let solidMaskLayer = CAShapeLayer()
    private let glassGlowView = UIView()
    private let underglowGradientLayer = CAGradientLayer()
    private let glassBackgroundView = LiquidGlassEffectView.makeContainer()
    private var highlightGradientLayer: CAGradientLayer?
    private var emphasisAmount: CGFloat = 0
    private var swipeRevealAmount: CGFloat = 0
    private var backgroundStyle: DialogueBubbleBackgroundStyle = .glass
    private var underglowConfiguration = DialogueBubbleUnderglowConfiguration.default
    private var tailEdge: DialogueBubbleTailEdge = .none
    private var solidFillColor: UIColor = .systemBlue
    /// When true, the solid fill stays fully opaque even at zero emphasis.
    private var solidFillStaysVisible = false
    /// Label edge pins that size the bubble. Deactivated while a live meter owns layout.
    private var labelEdgeConstraints: [NSLayoutConstraint] = []
    private var labelLeadingConstraint: NSLayoutConstraint!
    private var labelTrailingConstraint: NSLayoutConstraint!
    private var labelContributesToLayout = true

    private static let cornerRadius: CGFloat = 18
    private static let contentPadding = UIEdgeInsets(top: 6, left: 12, bottom: 10, right: 12)
    /// Extra width reserved for an iMessage-style tail on one side.
    private static let tailProtrusion: CGFloat = 6

    static var horizontalContentPadding: CGFloat {
        contentPadding.left + contentPadding.right
    }

    /// Horizontal padding that currently sizes the label, including a tail if shown.
    var layoutHorizontalContentPadding: CGFloat {
        Self.horizontalContentPadding + (tailEdge == .none ? 0 : Self.tailProtrusion)
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
        solidMaskLayer.fillColor = UIColor.black.cgColor

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

        labelLeadingConstraint = label.leadingAnchor.constraint(
            equalTo: leadingAnchor,
            constant: Self.contentPadding.left
        )
        labelTrailingConstraint = label.trailingAnchor.constraint(
            equalTo: trailingAnchor,
            constant: -Self.contentPadding.right
        )
        labelEdgeConstraints = [
            label.topAnchor.constraint(equalTo: topAnchor, constant: Self.contentPadding.top),
            labelLeadingConstraint,
            labelTrailingConstraint,
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.contentPadding.bottom),
        ]

        NSLayoutConstraint.activate([
            solidBackgroundView.topAnchor.constraint(equalTo: topAnchor),
            solidBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            solidBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            solidBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            glassBackgroundView.topAnchor.constraint(equalTo: topAnchor),
            glassBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ] + labelEdgeConstraints)

        applyEmphasisVisuals()
    }

    /// When false, the label stops driving bubble size so a sibling (e.g. live
    /// meter) can own layout without fighting the label's edge pins.
    func setLabelContributesToLayout(_ contributes: Bool) {
        guard labelContributesToLayout != contributes else { return }
        labelContributesToLayout = contributes
        labelEdgeConstraints.forEach { $0.isActive = contributes }
        // Keep the label out of hit-testing / drawing while it's detached from layout.
        label.isHidden = !contributes
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutUnderglow()
        solidBackgroundView.layoutIfNeeded()
        updateSolidMask()
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

    func setSolidFillColor(_ color: UIColor) {
        solidFillColor = color
        applyEmphasisVisuals()
    }

    func setSolidFillStaysVisible(_ staysVisible: Bool) {
        guard solidFillStaysVisible != staysVisible else { return }
        solidFillStaysVisible = staysVisible
        applyEmphasisVisuals()
        setNeedsLayout()
    }

    func setTailEdge(_ edge: DialogueBubbleTailEdge) {
        guard tailEdge != edge else { return }
        tailEdge = edge
        let leadingExtra = edge == .leading ? Self.tailProtrusion : 0
        let trailingExtra = edge == .trailing ? Self.tailProtrusion : 0
        labelLeadingConstraint.constant = Self.contentPadding.left + leadingExtra
        labelTrailingConstraint.constant = -(Self.contentPadding.right + trailingExtra)
        applySolidCornerChrome()
        invalidateIntrinsicContentSize()
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

    /// Token karaoke fill — same hue as this bubble's underglow.
    var tokenHighlightColor: UIColor {
        underglowConfiguration.tokenHighlightUIColor
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

    private var showsSolidFill: Bool {
        solidFillStaysVisible || isBubbleActive
    }

    private var usesMessageTail: Bool {
        tailEdge != .none
    }

    private func applyEmphasisVisuals() {
        let glassAmount = combinedGlassAmount
        switch backgroundStyle {
        case .solid:
            solidBackgroundView.isHidden = !showsSolidFill
            solidBackgroundView.alpha = solidFillStaysVisible ? 1 : glassAmount
            solidBackgroundView.backgroundColor = showsSolidFill
                ? solidFillColor
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
            glassBackgroundView.isHidden = false
            glassBackgroundView.alpha = 1
        }
    }

    private func solidSilhouettePath(in rect: CGRect) -> UIBezierPath {
        if usesMessageTail {
            return Self.messageBubblePath(in: rect, tailEdge: tailEdge)
        }
        return UIBezierPath(roundedRect: rect, cornerRadius: Self.cornerRadius)
    }

    private func applySolidCornerChrome() {
        if usesMessageTail {
            solidBackgroundView.layer.cornerRadius = 0
            solidBackgroundView.clipsToBounds = false
        } else {
            solidBackgroundView.layer.mask = nil
            solidBackgroundView.layer.cornerRadius = Self.cornerRadius
            solidBackgroundView.layer.cornerCurve = .continuous
            solidBackgroundView.clipsToBounds = true
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

    private func updateSolidMask() {
        guard usesMessageTail,
              backgroundStyle == .solid,
              solidBackgroundView.bounds.width > 0,
              solidBackgroundView.bounds.height > 0 else {
            solidBackgroundView.layer.mask = nil
            return
        }

        solidMaskLayer.frame = solidBackgroundView.bounds
        solidMaskLayer.path = solidSilhouettePath(in: solidBackgroundView.bounds).cgPath
        solidBackgroundView.layer.mask = solidMaskLayer
    }

    private func updateHighlightDecoration() {
        highlightGradientLayer?.removeFromSuperlayer()
        highlightGradientLayer = nil
        guard backgroundStyle == .solid,
              !solidFillStaysVisible,
              !usesMessageTail,
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

    /// iOS Messages incoming-bubble silhouette, mirrored for a trailing tail.
    private static func messageBubblePath(
        in rect: CGRect,
        tailEdge: DialogueBubbleTailEdge
    ) -> UIBezierPath {
        let width = rect.width
        let height = rect.height
        let path = UIBezierPath()
        guard width > 44, height > 32, tailEdge != .none else {
            path.append(
                UIBezierPath(
                    roundedRect: rect,
                    cornerRadius: cornerRadius
                )
            )
            return path
        }

        // Classic Messages tail: body inset ~6pt, beak along the bottom corner.
        path.move(to: CGPoint(x: 22, y: height))
        path.addLine(to: CGPoint(x: width - 17, y: height))
        path.addCurve(
            to: CGPoint(x: width, y: height - 17),
            controlPoint1: CGPoint(x: width - 7.61, y: height),
            controlPoint2: CGPoint(x: width, y: height - 7.61)
        )
        path.addLine(to: CGPoint(x: width, y: 17))
        path.addCurve(
            to: CGPoint(x: width - 17, y: 0),
            controlPoint1: CGPoint(x: width, y: 7.61),
            controlPoint2: CGPoint(x: width - 7.61, y: 0)
        )
        path.addLine(to: CGPoint(x: 21, y: 0))
        path.addCurve(
            to: CGPoint(x: 4, y: 17),
            controlPoint1: CGPoint(x: 11.61, y: 0),
            controlPoint2: CGPoint(x: 4, y: 7.61)
        )
        path.addLine(to: CGPoint(x: 4, y: height - 11))
        path.addCurve(
            to: CGPoint(x: 0, y: height),
            controlPoint1: CGPoint(x: 4, y: height - 1),
            controlPoint2: CGPoint(x: 0, y: height)
        )
        path.addLine(to: CGPoint(x: -0.05, y: height - 0.01))
        path.addCurve(
            to: CGPoint(x: 11.04, y: height - 4.04),
            controlPoint1: CGPoint(x: 4.07, y: height + 0.43),
            controlPoint2: CGPoint(x: 8.16, y: height - 1.06)
        )
        path.addCurve(
            to: CGPoint(x: 22, y: height),
            controlPoint1: CGPoint(x: 16, y: height),
            controlPoint2: CGPoint(x: 19, y: height)
        )
        path.close()

        if tailEdge == .trailing {
            path.apply(CGAffineTransform(scaleX: -1, y: 1))
            path.apply(CGAffineTransform(translationX: width, y: 0))
        }
        path.apply(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return path
    }
}

extension DialogueJapaneseBubbleView: SwipeRevealGlassAdjusting {}
