//
//  RolePlayTurnPromptView.swift
//  shizen
//
//  Glass "Your Turn" pill for Role Play without speech recognition — sits
//  where the speaking meter would, shown only while the learner should talk.
//

import InteractionKit
import UIKit

final class RolePlayTurnPromptView: UIView {

    private static let hiddenScale: CGFloat = 0.9

    private let pillBackground = LiquidGlassEffectView.makeLightPillContainer()
    private let label = UILabel()

    var tintedTextColor: UIColor = .systemBlue {
        didSet { label.textColor = tintedTextColor }
    }

    private(set) var isShowingPrompt = false

    override init(frame: CGRect) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setShowingPrompt(_ showing: Bool, animated: Bool) {
        guard showing != isShowingPrompt else { return }
        isShowingPrompt = showing
        accessibilityElementsHidden = !showing
        if showing {
            UIAccessibility.post(notification: .announcement, argument: label.text)
        }

        let changes = {
            self.alpha = showing ? 1 : 0
            let scale = showing ? 1 : Self.hiddenScale
            self.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
        guard animated, window != nil else {
            changes()
            return
        }
        UIView.animate(
            withDuration: showing ? 0.42 : 0.22,
            delay: 0,
            usingSpringWithDamping: showing ? 0.72 : 1,
            initialSpringVelocity: 0.35,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: changes
        )
    }

    private func configure() {
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityElementsHidden = true
        alpha = 0
        transform = CGAffineTransform(scaleX: Self.hiddenScale, y: Self.hiddenScale)

        LiquidGlassEffectView.applyPillStyle(
            to: pillBackground,
            cornerRadius: SpeakingMeterPillView.pillHeight / 2
        )
        pillBackground.isUserInteractionEnabled = false
        addSubview(pillBackground)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Your Turn"
        label.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: .systemFont(ofSize: 17, weight: .semibold),
            maximumPointSize: 22
        )
        label.adjustsFontForContentSizeCategory = true
        label.textColor = tintedTextColor
        label.textAlignment = .center
        addSubview(label)
        accessibilityLabel = label.text

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: SpeakingMeterPillView.pillHeight),

            pillBackground.topAnchor.constraint(equalTo: topAnchor),
            pillBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            pillBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            pillBackground.bottomAnchor.constraint(equalTo: bottomAnchor),

            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
        ])
    }
}
