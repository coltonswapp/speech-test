//
//  GlassChipControl.swift
//  shizen-chinese
//
//  Glass-backed tappable chip: primary glyph over an optional caption.
//

import InteractionKit
import UIKit

final class GlassChipControl: UIControl {

    private static let cornerRadius: CGFloat = 14
    private static let contentInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

    private let glassView: UIVisualEffectView
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let stack = UIStackView()

    init(title: String, subtitle: String?, titleFont: UIFont, subtitleFont: UIFont) {
        glassView = LiquidGlassEffectView.makeLightPillContainer()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = [title, subtitle].compactMap { $0 }.joined(separator: ", ")

        LiquidGlassEffectView.applyPillStyle(to: glassView, cornerRadius: Self.cornerRadius)
        glassView.isUserInteractionEnabled = false

        titleLabel.text = title
        titleLabel.font = titleFont
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        subtitleLabel.text = subtitle
        subtitleLabel.font = subtitleFont
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 2
        subtitleLabel.isHidden = (subtitle?.isEmpty ?? true)

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(subtitleLabel)

        addSubview(glassView)
        addSubview(stack)

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.topAnchor.constraint(equalTo: topAnchor, constant: Self.contentInsets.top),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.contentInsets.bottom),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.contentInsets.left),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.contentInsets.right),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            guard oldValue != isHighlighted else { return }
            animatePress(down: isHighlighted)
        }
    }

    private func animatePress(down: Bool) {
        UIView.animate(
            withDuration: down ? 0.12 : 0.28,
            delay: 0,
            usingSpringWithDamping: down ? 1 : 0.6,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.transform = down ? CGAffineTransform(scaleX: 0.93, y: 0.93) : .identity
            self.alpha = down ? 0.7 : 1
        }
    }
}
