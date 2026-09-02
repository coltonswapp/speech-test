//
//  LiquidGlassEffectView.swift
//  InteractionKit
//
//  Shared liquid-glass / blur container styling used by overlay chrome.
//

import UIKit

public enum LiquidGlassEffectView {

    public static func makeContainer() -> UIVisualEffectView {
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.isInteractive = true
            return UIVisualEffectView(effect: glassEffect)
        } else {
            return UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        }
    }

    public static func applyCapsuleStyle(to view: UIVisualEffectView, cornerRadius: CGFloat = 40) {
        applyRoundedStyle(to: view, cornerRadius: cornerRadius, showsShadow: true)
    }

    /// Rounded-rect liquid-glass styling for chat-style dialogue bubbles.
    public static func applyBubbleStyle(to view: UIVisualEffectView, cornerRadius: CGFloat = 18) {
        applyRoundedStyle(to: view, cornerRadius: cornerRadius, showsShadow: false)
    }

    /// Light-surface glass for vocabulary / grammar pills on learning pages.
    public static func makeLightPillContainer() -> UIVisualEffectView {
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.isInteractive = false
            return UIVisualEffectView(effect: glassEffect)
        } else {
            return UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialLight))
        }
    }

    public static func applyPillStyle(to view: UIVisualEffectView, cornerRadius: CGFloat = 14) {
        applyRoundedStyle(to: view, cornerRadius: cornerRadius, showsShadow: true)
    }

    private static func applyRoundedStyle(
        to view: UIVisualEffectView,
        cornerRadius: CGFloat,
        showsShadow: Bool
    ) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = cornerRadius
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor

        if showsShadow {
            view.clipsToBounds = false
            view.layer.masksToBounds = false
            view.layer.shadowColor = UIColor.black.cgColor
            view.layer.shadowOffset = CGSize(width: 0, height: 4)
            view.layer.shadowRadius = 12
            view.layer.shadowOpacity = 0.3
        } else {
            view.clipsToBounds = true
            view.layer.masksToBounds = true
        }

        if #available(iOS 26.0, *) {
            view.cornerConfiguration = .corners(radius: .fixed(cornerRadius))
        } else {
            view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.82)
        }
    }
}
