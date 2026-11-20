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
//  The blur view rebuilds its backdrop and material layers whenever its traits change,
//  which drops the filter and brings the tint back as a solid, hard-edged band. iOS
//  changes traits when the app goes to the background (it snapshots the app in light
//  and dark), so the filter is put back after every trait change and on foreground.
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
    private var maskImage: CGImage?
    private var stackedLayers: [(view: UIVisualEffectView, mask: CAGradientLayer)] = []

    init(style: UIBlurEffect.Style = .systemUltraThinMaterial, steps: Int = 4) {
        self.style = style
        self.steps = max(1, steps)
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        if installVariableBlur() {
            registerForTraitChanges(UITraitCollection.systemTraitsAffectingColorAppearance) { (self: Self, _: UITraitCollection) in
                self.reassertVariableBlurSoon()
            }
            for name in [UIApplication.willEnterForegroundNotification, UIApplication.didBecomeActiveNotification] {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(reassertVariableBlurSoon),
                    name: name,
                    object: nil
                )
            }
        } else {
            installStackedBlur()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if variableBlurFilter != nil {
            if bounds.size != lastMaskSize { applyVariableBlur() } else { reassertVariableBlur() }
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
        guard variableBlurFilter != nil,
              bounds.width > 0, bounds.height > 0,
              let mask = Self.topToBottomMask(size: bounds.size)
        else { return }
        lastMaskSize = bounds.size
        maskImage = mask
        reassertVariableBlur(force: true)
    }

    /// Puts the filter back on the backdrop and hides the material layers, if the blur
    /// view replaced or reset them. Looks the subviews up each time: they can be new ones.
    private func reassertVariableBlur(force: Bool = false) {
        guard let blurView = variableBlurView, let filter = variableBlurFilter, let maskImage,
              let backdrop = blurView.subviews.first
        else { return }
        // Core Animation may hold a copy, so match by the filter's name, not identity.
        let filterName = Self.reversed("rulBelbairav")
        let hasFilter = (backdrop.layer.filters as? [NSObject])?.contains {
            $0 === filter || ($0.responds(to: NSSelectorFromString("name")) && $0.value(forKey: "name") as? String == filterName)
        } == true
        if force || !hasFilter {
            filter.setValue(maxRadius, forKey: "inputRadius")
            filter.setValue(maskImage, forKey: "inputMaskImage")
            filter.setValue(true, forKey: "inputNormalizeEdges")
            backdrop.layer.filters = [filter]
        }
        for overlay in blurView.subviews.dropFirst() where overlay.alpha != 0 {
            overlay.alpha = 0
        }
    }

    /// After the blur view has rebuilt itself for the new traits (it updates after us).
    @objc private func reassertVariableBlurSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.reassertVariableBlur()
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
