//
//  MainTabScrollable.swift
//  shizen-chinese
//
//  Main-tab pages expose scroll views so MainViewController can apply top content inset
//  for the category tab bar.
//

import UIKit

protocol MainTabScrollable: UIViewController {
    /// Vertical scroll surfaces that should clear the main category tab bar.
    var mainTabScrollViews: [UIScrollView] { get }
}

extension UIScrollView {
    func applyMainTabTopInset(_ topInset: CGFloat) {
        guard abs(contentInset.top - topInset) >= 0.5 else { return }
        contentInsetAdjustmentBehavior = .never
        let wasShowingTop = contentOffset.y <= -contentInset.top + 1
        var inset = contentInset
        inset.top = topInset
        contentInset = inset
        var indicatorInset = verticalScrollIndicatorInsets
        indicatorInset.top = topInset
        verticalScrollIndicatorInsets = indicatorInset
        if wasShowingTop {
            contentOffset.y = -topInset
        }
    }
}
