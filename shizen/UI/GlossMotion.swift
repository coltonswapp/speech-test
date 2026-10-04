//
//  GlossMotion.swift
//  shizen
//
//  Shared timing and helpers for gloss cards (Deeper Meaning, Common Uses,
//  Break down, In this sentence) so they open, resize, and close alike.
//

import UIKit

enum GlossMotion {
    static let reveal = (duration: 0.38 as TimeInterval, damping: 0.9 as CGFloat)
    static let dismiss = (duration: 0.28 as TimeInterval, damping: 1.0 as CGFloat)
    static let resize = (duration: 0.32 as TimeInterval, damping: 0.92 as CGFloat)
    static let contentFade: TimeInterval = 0.18
    static let collapsedScale: CGFloat = 0.94
    /// Fraction of a dismiss that passes before the card starts fading.
    static let dismissFadeDelay: CGFloat = 0.15

    private static let reducedMotionDuration: TimeInterval = 0.2

    static var reducesMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    static func revealAnimator(_ animations: @escaping () -> Void) -> UIViewPropertyAnimator {
        if reducesMotion {
            return UIViewPropertyAnimator(duration: reducedMotionDuration, curve: .easeInOut, animations: animations)
        }
        return UIViewPropertyAnimator(duration: reveal.duration, dampingRatio: reveal.damping, animations: animations)
    }

    static func dismissAnimator(_ animations: @escaping () -> Void) -> UIViewPropertyAnimator {
        if reducesMotion {
            return UIViewPropertyAnimator(duration: reducedMotionDuration, curve: .easeInOut, animations: animations)
        }
        return UIViewPropertyAnimator(duration: dismiss.duration, dampingRatio: dismiss.damping, animations: animations)
    }

    /// Animates `host.layoutIfNeeded()` for a card whose content height changed.
    /// When `joining` is still running forward, the layout rides that animator
    /// so the card never has two competing animations.
    static func animateResize(
        in host: UIView,
        joining animator: UIViewPropertyAnimator? = nil,
        completion: (() -> Void)? = nil
    ) {
        if let animator, animator.state == .active {
            if !animator.isReversed {
                animator.addAnimations { host.layoutIfNeeded() }
            }
            if let completion {
                animator.addCompletion { _ in completion() }
            }
            return
        }
        let animations = { host.layoutIfNeeded() }
        let finished: (Bool) -> Void = { _ in completion?() }
        if reducesMotion {
            UIView.animate(
                withDuration: reducedMotionDuration,
                delay: 0,
                options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState],
                animations: animations,
                completion: finished
            )
        } else {
            UIView.animate(
                withDuration: resize.duration,
                delay: 0,
                usingSpringWithDamping: resize.damping,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: animations,
                completion: finished
            )
        }
    }

    /// Crossfades a content swap (loading row to result or message) inside `container`.
    /// A layer fade rather than `UIView.transition`, so frames set by `changes` aren't animated.
    static func crossfade(_ container: UIView, animated: Bool = true, _ changes: () -> Void) {
        if animated {
            fadeNextContentChange(in: container)
        }
        changes()
    }

    /// Fades whatever `container` renders next, for swaps spread across several calls.
    static func fadeNextContentChange(in container: UIView) {
        guard container.window != nil else { return }
        let fade = CATransition()
        fade.type = .fade
        fade.duration = contentFade
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        container.layer.add(fade, forKey: "glossCrossfade")
    }

    /// Collapsed pose for a card: a uniform scale toward the point on the card
    /// nearest `origin`, given in the card's superview coordinates.
    static func collapsedTransform(for card: UIView, toward origin: CGPoint) -> CGAffineTransform {
        guard !reducesMotion else { return .identity }
        // `center` and `bounds` stay on the layout frame. `frame` is the
        // axis-aligned box after the current transform, so it can't be used
        // to build the next one.
        let center = card.center
        let size = card.bounds.size
        guard size.width > 1, size.height > 1 else { return .identity }
        let anchor = CGPoint(
            x: min(max(origin.x, center.x - size.width / 2), center.x + size.width / 2),
            y: min(max(origin.y, center.y - size.height / 2), center.y + size.height / 2)
        )
        let scale = collapsedScale
        return CGAffineTransform(
            translationX: (1 - scale) * (anchor.x - center.x),
            y: (1 - scale) * (anchor.y - center.y)
        ).scaledBy(x: scale, y: scale)
    }

    /// Sets a rounded-rect `shadowPath` for `layer`. If its bounds are
    /// animating, the path follows on the same timing instead of snapping.
    static func syncShadowPath(_ layer: CALayer, cornerRadius: CGFloat) {
        let path = UIBezierPath(roundedRect: layer.bounds, cornerRadius: cornerRadius).cgPath
        let boundsAnimation = (layer.animation(forKey: "bounds.size")
            ?? layer.animation(forKey: "bounds")) as? CABasicAnimation
        if let boundsAnimation, let follow = boundsAnimation.copy() as? CABasicAnimation {
            follow.keyPath = "shadowPath"
            follow.isAdditive = false
            follow.byValue = nil
            follow.fromValue = layer.presentation()?.shadowPath ?? layer.shadowPath
            follow.toValue = path
            layer.add(follow, forKey: "shadowPath")
        }
        layer.shadowPath = path
    }
}

/// Rounded gloss card background whose shadow tracks its own bounds, including mid-animation.
final class GlossCardSurfaceView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        GlossMotion.syncShadowPath(layer, cornerRadius: layer.cornerRadius)
    }
}
