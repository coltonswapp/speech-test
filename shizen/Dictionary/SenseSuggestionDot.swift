//
//  SenseSuggestionDot.swift
//  shizen
//
//  Yellow circle beside the dictionary sense that best fits the source sentence.
//  A ring expands outward from the circle so the row is easy to find.
//

import UIKit

/// Pulses while a sense ranker has marked this row. Stays a solid dot when Reduce Motion is on.
final class SenseSuggestionDot: UIView {
    private static let diameter: CGFloat = 9
    private static let ringScale: CGFloat = 2.7

    private let fill = CALayer()
    private let ring = CAShapeLayer()
    private var showingSuggestion = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = false
        isAccessibilityElement = false
        alpha = 0
        translatesAutoresizingMaskIntoConstraints = false

        fill.backgroundColor = UIColor.systemYellow.cgColor
        layer.addSublayer(fill)

        ring.fillColor = nil
        ring.strokeColor = UIColor.systemYellow.cgColor
        ring.lineWidth = 1.5
        ring.opacity = 0
        layer.addSublayer(ring)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.diameter),
            heightAnchor.constraint(equalToConstant: Self.diameter),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        fill.bounds = bounds
        fill.position = center
        fill.cornerRadius = bounds.width / 2

        let strokeInset = ring.lineWidth / 2
        ring.bounds = bounds
        ring.position = center
        ring.path = UIBezierPath(ovalIn: bounds.insetBy(dx: strokeInset, dy: strokeInset)).cgPath
        applyYellow()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyYellow()
    }

    func setSuggested(_ suggested: Bool) {
        guard suggested != showingSuggestion else { return }
        showingSuggestion = suggested
        fill.removeAnimation(forKey: "pulse")
        ring.removeAnimation(forKey: "ring")
        guard suggested else {
            alpha = 0
            ring.opacity = 0
            return
        }
        alpha = 1
        fill.opacity = 1
        guard !UIAccessibility.isReduceMotionEnabled else {
            ring.opacity = 0
            return
        }

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.2
        pulse.duration = 0.85
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        fill.add(pulse, forKey: "pulse")

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = Self.ringScale
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.85
        fade.toValue = 0
        let ringPulse = CAAnimationGroup()
        ringPulse.animations = [scale, fade]
        ringPulse.duration = 1.15
        ringPulse.repeatCount = .infinity
        ringPulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(ringPulse, forKey: "ring")
    }

    private func applyYellow() {
        let color = UIColor.systemYellow.resolvedColor(with: traitCollection).cgColor
        fill.backgroundColor = color
        ring.strokeColor = color
    }
}
