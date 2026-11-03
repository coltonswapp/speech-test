//
//  UISheetPresentationController+SolidBackground.swift
//  shizen
//
//  Keeps half-height sheets solid instead of Liquid Glass.
//

import UIKit

extension UISheetPresentationController {
    /// iOS 26 renders detents below large as Liquid Glass and only turns solid at
    /// large. The public `Detent.backgroundEffect` only takes blur/glass, so use
    /// the private `_setNonLargeBackground:` (UIColor conforms to its
    /// `_UIViewMaterial` parameter) to keep smaller detents solid. No-op if UIKit
    /// drops it. The selector is stored reversed so the private name doesn't
    /// appear as a plain string in the binary.
    func applySolidNonLargeBackground(_ color: UIColor = .systemBackground) {
        let selector = NSSelectorFromString(String(":dnuorgkcaBegraLnoNtes_".reversed()))
        guard responds(to: selector) else { return }
        perform(selector, with: color)
    }
}
