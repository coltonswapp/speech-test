//
//  PrimaryButton.swift
//  shizen
//

import UIKit

/// Full-width CTA with blue (Check) and yellow (Next) style presets.
final class PrimaryButton: UIButton {

    static let preferredHeight: CGFloat = 55
    static let horizontalInset: CGFloat = 16

    private enum ControlTappedState {
        case touchDown
        case touchCancel
        case touchUp
    }

    enum Style {
        case blue
        case yellow
    }

    struct Appearance {
        var backgroundColor: UIColor
        var titleColor: UIColor
        var strokeColor: UIColor
        var strokeWidth: CGFloat
        var cornerRadius: CGFloat
        var highlightedBackgroundColor: UIColor
        var disabledBackgroundColor: UIColor
        var disabledTitleColor: UIColor
    }

    var primaryStyle: Style = .blue {
        didSet { applyAppearance() }
    }

    override var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            if !isEnabled {
                resetPressAnimation(animated: false)
            }
            applyAppearance()
        }
    }

    private var restingBackgroundColor: UIColor = .clear
    private var isPressAnimating = false
    private var touchDownTimestamp: TimeInterval?
    private let hapticThreshold: TimeInterval = 0.15
    private let pressHaptic = UIImpactFeedbackGenerator(style: .soft)
    private let releaseHaptic = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        pressHaptic.prepare()
        releaseHaptic.prepare()
    }

    static func appearance(for style: Style) -> Appearance {
        switch style {
        case .blue:
            Appearance(
                backgroundColor: UIColor(red: 1 / 255, green: 140 / 255, blue: 253 / 255, alpha: 1),
                titleColor: .white,
                strokeColor: UIColor(red: 0 / 255, green: 118 / 255, blue: 214 / 255, alpha: 1),
                strokeWidth: 0,
                cornerRadius: 14,
                highlightedBackgroundColor: UIColor(red: 0 / 255, green: 122 / 255, blue: 222 / 255, alpha: 1),
                disabledBackgroundColor: UIColor(red: 168 / 255, green: 184 / 255, blue: 201 / 255, alpha: 1),
                disabledTitleColor: UIColor(red: 244 / 255, green: 247 / 255, blue: 250 / 255, alpha: 1)
            )
        case .yellow:
            Appearance(
                backgroundColor: UIColor(red: 253 / 255, green: 200 / 255, blue: 1 / 255, alpha: 1),
                titleColor: UIColor(red: 144 / 255, green: 114 / 255, blue: 2 / 255, alpha: 1),
                strokeColor: UIColor(red: 210 / 255, green: 166 / 255, blue: 0 / 255, alpha: 1),
                strokeWidth: 0,
                cornerRadius: 14,
                highlightedBackgroundColor: UIColor(red: 245 / 255, green: 190 / 255, blue: 0 / 255, alpha: 1),
                disabledBackgroundColor: UIColor(red: 210 / 255, green: 205 / 255, blue: 188 / 255, alpha: 1),
                disabledTitleColor: UIColor(red: 132 / 255, green: 124 / 255, blue: 108 / 255, alpha: 1)
            )
        }
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        setupTouchHandling()
        applyAppearance()
    }

    override func setTitle(_ title: String?, for state: UIControl.State) {
        super.setTitle(title, for: state)
        guard state == .normal else { return }
        applyAppearance()
    }

    private func setupTouchHandling() {
        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchDragExit), for: .touchDragExit)
        addTarget(self, action: #selector(touchUpOutside), for: .touchUpOutside)
        addTarget(self, action: #selector(touchCancel), for: .touchCancel)
        addTarget(self, action: #selector(touchUpInside), for: .touchUpInside)
    }

    @objc private func touchDown() {
        guard isEnabled else { return }
        touchDownTimestamp = Date().timeIntervalSince1970
        pressHaptic.impactOccurred()
        standardControlAnimation(.touchDown)
    }

    @objc private func touchDragExit() {
        touchDownTimestamp = nil
        standardControlAnimation(.touchCancel)
    }

    @objc private func touchUpOutside() {
        touchDownTimestamp = nil
        standardControlAnimation(.touchCancel)
    }

    @objc private func touchCancel() {
        touchDownTimestamp = nil
        standardControlAnimation(.touchCancel)
    }

    @objc private func touchUpInside() {
        if let timestamp = touchDownTimestamp {
            let elapsed = Date().timeIntervalSince1970 - timestamp
            if elapsed > hapticThreshold {
                releaseHaptic.impactOccurred()
            }
        }
        standardControlAnimation(.touchUp)
        touchDownTimestamp = nil
    }

    private func standardControlAnimation(_ tappedState: ControlTappedState) {
        guard isEnabled else {
            resetPressAnimation(animated: true)
            return
        }

        switch tappedState {
        case .touchDown:
            isPressAnimating = true
            let pressedBackground = Self.appearance(for: primaryStyle).highlightedBackgroundColor
            UIView.animate(withDuration: 0.075, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
                self.updateBackgroundColor(pressedBackground)
            }
        case .touchCancel, .touchUp:
            resetPressAnimation(animated: true)
        }
    }

    private func resetPressAnimation(animated: Bool) {
        isPressAnimating = false
        let restore = {
            self.transform = .identity
            self.updateBackgroundColor(self.restingBackgroundColor)
        }
        guard animated else {
            restore()
            return
        }
        UIView.animate(withDuration: 0.1, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            restore()
        }
    }

    private func updateBackgroundColor(_ color: UIColor) {
        guard var config = configuration else { return }
        config.background.backgroundColor = color
        configuration = config
    }

    private func applyAppearance() {
        let appearance = Self.appearance(for: primaryStyle)
        let background = isEnabled ? appearance.backgroundColor : appearance.disabledBackgroundColor
        restingBackgroundColor = background
        let titleColor = isEnabled ? appearance.titleColor : appearance.disabledTitleColor
        let displayBackground = isEnabled && isPressAnimating
            ? appearance.highlightedBackgroundColor
            : background

        var config = UIButton.Configuration.filled()
        config.cornerStyle = .fixed
        config.background.cornerRadius = appearance.cornerRadius
        config.background.strokeColor = isEnabled ? appearance.strokeColor : .clear
        config.background.strokeWidth = appearance.strokeWidth
        config.background.backgroundColor = displayBackground
        config.baseForegroundColor = titleColor
        config.title = title(for: .normal)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var attributes = incoming
            attributes.font = .systemFont(ofSize: 17, weight: .bold)
            attributes.foregroundColor = titleColor
            return attributes
        }
        configuration = config
    }
}
