//
//  DefinitionTipPresenter.swift
//  shizen
//
//  Shows a `DefinitionTipView` anchored to a source view, tip-style, without a full-screen sheet.
//

import UIKit

enum DefinitionTipPresenter {
    private static weak var current: DefinitionTipView?
    private static var onRemoved: (() -> Void)?

    /// Dismisses any visible definition tip, then shows a new one.
    /// Does **not** run a prior `onAnchorRemoved`—the host view controller is expected to replace
    /// its own anchor (e.g. clear `definitionAnchor` before re-adding) so we avoid removing a newly attached anchor.
    static func show(surface: String, sourceView: UIView, in viewController: UIViewController, onAnchorRemoved: (() -> Void)? = nil) {
        removeCurrentTipViewOnly(animateOut: false)
        onRemoved = onAnchorRemoved
        let entries = JMDictStore.shared.entries(forSurface: surface)
        // Scroll area: use most of the screen height (safe layout still clamps the real frame).
        let h = viewController.view.bounds.height
        // Large cap so scroll’s internal limit never wins over the real layout height.
        let maxBody = min(3000, max(800, h * 0.95))
        let tip = DefinitionTipView(surface: surface, entries: entries, maxScrollHeight: maxBody, dismissHandler: nil)
        tip.translatesAutoresizingMaskIntoConstraints = false
        tip.setDismissHandler { [weak tip] in
            guard let tip else { return }
            let r = onRemoved
            onRemoved = nil
            r?()
            current = nil
            tip.dismissWithAnimation()
        }
        current = tip
        viewController.view.addSubview(tip)
        tip.setSourceView(sourceView)
        applyConstraints(tip, sourceView: sourceView, in: viewController)
        viewController.view.layoutIfNeeded()
        tip.updateArrowPosition()
        tip.showWithAnimation()
    }

    /// Dismiss the current definition tip, if any (e.g. on navigation or second tap to cancel).
    static func dismiss(animateOut: Bool) {
        tearDown(animateOut: animateOut)
    }

    private static func removeCurrentTipViewOnly(animateOut: Bool) {
        guard let tip = current else { return }
        current = nil
        if animateOut {
            tip.dismissWithAnimation()
        } else {
            tip.removeFromSuperview()
        }
    }

    private static func tearDown(animateOut: Bool) {
        let r = onRemoved
        onRemoved = nil
        r?()
        guard let tip = current else { return }
        current = nil
        if animateOut {
            tip.dismissWithAnimation()
        } else {
            tip.removeFromSuperview()
        }
    }

    private static func applyConstraints(
        _ tipView: UIView,
        sourceView: UIView,
        in viewController: UIViewController
    ) {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let maxW: CGFloat = 300
        let widthFraction: CGFloat = 0.70
        let offset = CGPoint(x: 0, y: 3)
        let vc = viewController.view!
        let h = vc.bounds.height
        let maxH = min(2000, max(520, h * 0.97))

        let sourceRect = sourceView.convert(sourceView.bounds, to: vc)
        let safeFrame = vc.safeAreaLayoutGuide.layoutFrame
        let safeMaxY = (safeFrame.maxY > 0.5) ? safeFrame.maxY : (vc.bounds.maxY - vc.safeAreaInsets.bottom)
        let tipTopY = sourceRect.maxY + offset.y
        var available = safeMaxY - tipTopY - 4
        if available < 160 {
            available = min(maxH, max(200, h * 0.40))
        }
        // Split the difference: full `available` read as too tall; use ~midway between ½ and 100% of space below the word.
        let targetH = min(maxH, max(200, available * 0.75))

        let vcWidth = vc.bounds.width
        let barWidth: CGFloat
        if isIPad {
            barWidth = min(vcWidth * widthFraction, maxW)
        } else {
            barWidth = vcWidth * widthFraction
        }
        let tooltipWidth = barWidth
        let ideal = sourceRect.midX
        let lo = tooltipWidth / 2 + 8
        let hi = vcWidth - tooltipWidth / 2 - 8
        let clamped = max(lo, min(hi, ideal))
        var constraints: [NSLayoutConstraint] = [
            // Hard height: `<= maxH` alone lets the view hug short content so it never *looks* tall.
            tipView.heightAnchor.constraint(equalToConstant: targetH),
            tipView.widthAnchor.constraint(equalToConstant: barWidth),
            tipView.bottomAnchor.constraint(lessThanOrEqualTo: vc.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            tipView.centerXAnchor.constraint(equalTo: vc.centerXAnchor, constant: clamped - vcWidth / 2),
            tipView.topAnchor.constraint(equalTo: sourceView.bottomAnchor, constant: offset.y)
        ]

        NSLayoutConstraint.activate(constraints)
    }
}
