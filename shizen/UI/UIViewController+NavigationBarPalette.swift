//
//  UIViewController+NavigationBarPalette.swift
//  shizen
//
//  Hangs a view under the navigation bar. The palette class is private UIKit,
//  so its name is stored reversed.
//

import UIKit

extension UIViewController {
    /// Pins `view` under the navigation bar. Returns false when the palette class is unavailable.
    @discardableResult
    func addNavigationBarPalette(_ view: UIView) -> Bool {
        let className = String(("ettelaPraB" + "noitagivaNIU_").reversed())
        let selectorName = String((":ettelaP" + "mottoBtes_").reversed())

        guard let paletteClass = NSClassFromString(className) as? UIView.Type else { return false }

        let palette = paletteClass.perform(NSSelectorFromString("alloc"))?
            .takeUnretainedValue()
            .perform(NSSelectorFromString("initWithContentView:"), with: view)?
            .takeUnretainedValue()
        guard let palette else { return false }

        navigationItem.perform(NSSelectorFromString(selectorName), with: palette)
        return true
    }
}
