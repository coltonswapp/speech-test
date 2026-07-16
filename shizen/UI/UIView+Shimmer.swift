//
//  UIView+Shimmer.swift
//  shizen
//
//  One-shot shimmer sweep (CAGradientLayer + locations animation).
//  Matches hardway-craps UIView.playShimmer().
//

import UIKit

extension UIView {

    /// Brief highlight sweep across the view bounds. Call after `layoutIfNeeded()` when bounds are final.
    func playShimmer(highlightAlpha: CGFloat = 0.72, duration: TimeInterval = 0.42) {
        let shimmer = CAGradientLayer()
        shimmer.colors = [
            UIColor.clear.cgColor,
            UIColor.white.withAlphaComponent(highlightAlpha).cgColor,
            UIColor.white.withAlphaComponent(highlightAlpha).cgColor,
            UIColor.clear.cgColor,
        ]
        shimmer.locations = [0, 0.3, 0.7, 1]

        let angle = 10 * CGFloat.pi / 180
        shimmer.startPoint = CGPoint(x: 0.5 - cos(angle) * 0.5, y: 0.5 - sin(angle) * 0.5)
        shimmer.endPoint = CGPoint(x: 0.5 + cos(angle) * 0.5, y: 0.5 + sin(angle) * 0.5)

        shimmer.frame = bounds
        shimmer.cornerRadius = layer.cornerRadius
        shimmer.masksToBounds = true
        layer.addSublayer(shimmer)

        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-0.8, -0.6, -0.4, -0.2]
        animation.toValue = [1.2, 1.4, 1.6, 1.8]
        animation.duration = duration
        animation.repeatCount = 1
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            shimmer.removeFromSuperlayer()
        }
        shimmer.add(animation, forKey: "shimmer")
        CATransaction.commit()
    }
}
