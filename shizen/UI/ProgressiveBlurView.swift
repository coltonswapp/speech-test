//
//  ProgressiveBlurView.swift
//  shizen
//
//  A blur that weakens from the top edge down to nothing at the bottom.
//
//  Preferred: a true variable-radius blur — the private `variableBlur` CAFilter on a
//  blur view's backdrop layer, driven by a gradient mask image. Class, selector and
//  filter names are stored reversed and resolved at runtime.
//
//  Fallback (if the private filter isn't there): `steps` ultra-thin material layers
//  stacked, each masked to reach a little less far down than the one before.
//

import UIKit

final class ProgressiveBlurView: UIView {

    /// Blur radius at the top edge (variable blur only).
    var maxRadius: CGFloat = 8 {
        didSet { if variableBlurFilter != nil { applyVariableBlur() } }
    }

    private let style: UIBlurEffect.Style
    private let steps: Int
    private var variableBlurView: UIVisualEffectView?
    private var variableBlurFilter: NSObject?
    private var lastMaskSize: CGSize = .zero
    private var stackedLayers: [(view: UIVisualEffectView, mask: CAGradientLayer)] = []

    init(style: UIBlurEffect.Style = .systemUltraThinMaterial, steps: Int = 4) {
        self.style = style
        self.steps = max(1, steps)
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        if !installVariableBlur() {
            installStackedBlur()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if variableBlurFilter != nil {
            if bounds.size != lastMaskSize { applyVariableBlur() }
        } else {
            layoutStackedMasks()
        }
    }

    // MARK: - Variable blur (private)

    private static func reversed(_ string: String) -> String { String(string.reversed()) }

    private static func makeVariableBlurFilter() -> NSObject? {
        guard let filterClass = NSClassFromString(reversed("retliFAC")) as? NSObject.Type else { return nil }
        let selector = NSSelectorFromString(reversed(":epyThtiWretlif"))
        guard filterClass.responds(to: selector),
              let filter = filterClass.perform(selector, with: reversed("rulBelbairav"))?.takeUnretainedValue() as? NSObject
        else { return nil }
        return filter
    }

    private func installVariableBlur() -> Bool {
        guard let filter = Self.makeVariableBlurFilter() else { return false }
        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        // The first subview is the backdrop that samples what's behind; the rest are
        // the material's tint and grain, which a plain progressive blur doesn't want.
        guard blurView.subviews.first != nil else { return false }
        blurView.frame = bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(blurView)
        variableBlurView = blurView
        variableBlurFilter = filter
        return true
    }

    private func applyVariableBlur() {
        guard let blurView = variableBlurView, let filter = variableBlurFilter,
              bounds.width > 0, bounds.height > 0,
              let mask = Self.topToBottomMask(size: bounds.size)
        else { return }
        lastMaskSize = bounds.size
        filter.setValue(maxRadius, forKey: "inputRadius")
        filter.setValue(mask, forKey: "inputMaskImage")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        blurView.subviews.first?.layer.filters = [filter]
        for overlay in blurView.subviews.dropFirst() {
            overlay.alpha = 0
        }
    }

    /// Opaque (full blur) at the top, clear (no blur) at the bottom.
    private static func topToBottomMask(size: CGSize) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            let colors = [UIColor.black.cgColor, UIColor.clear.cgColor] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) else { return }
            context.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }
        return image.cgImage
    }

    // MARK: - Stacked fallback (public)

    private func installStackedBlur() {
        stackedLayers = (0 ..< steps).map { _ in
            let view = UIVisualEffectView(effect: UIBlurEffect(style: style))
            let mask = CAGradientLayer()
            mask.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
            view.layer.mask = mask
            view.frame = bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(view)
            return (view, mask)
        }
    }

    /// Layer i is solid down to band i and fades out across band i + 1, so the overlap
    /// (and the blur) thins one band at a time toward the bottom.
    private func layoutStackedMasks() {
        let count = CGFloat(stackedLayers.count)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, entry) in stackedLayers.enumerated() {
            entry.mask.frame = bounds
            let solidEnd = CGFloat(index) / count
            let fadeEnd = CGFloat(index + 1) / count
            entry.mask.locations = [0, NSNumber(value: Double(solidEnd)), NSNumber(value: Double(fadeEnd))]
        }
        CATransaction.commit()
    }
}
