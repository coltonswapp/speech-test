//
//  SpeechProfileGlassOverlay.swift
//  shizen
//
//  Liquid-glass capsule with a speech-profile VU meter. Slides in from the top
//  or bottom while encouragement audio plays, then retreats the same way.
//

import UIKit

enum SpeechProfileOverlayEdge {
    case top
    case bottom
}

final class SpeechProfileGlassOverlay: UIVisualEffectView {

    enum Style {
        static let sizeSliderMin: CGFloat = 64
        static let sizeSliderMax: CGFloat = 300
        static let defaultWidth: CGFloat = 170
        static let defaultHeight: CGFloat = 110
    }

    private let speechBars = SpeechEnvelopeBarsView()
    private var edgeConstraint: NSLayoutConstraint?
    private var centerXConstraint: NSLayoutConstraint?
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private weak var hostView: UIView?
    private var isVisible = false
    private var runningAnimator: UIViewPropertyAnimator?

    private(set) var entryEdge: SpeechProfileOverlayEdge = .top

    private var shownEdgeConstant: CGFloat {
        entryEdge == .top ? 12 : -12
    }

    private var hiddenEdgeConstant: CGFloat {
        entryEdge == .top ? -120 : 120
    }

    convenience init() {
        self.init(effect: LiquidGlassEffectView.makeContainer().effect)
    }

    override init(effect: UIVisualEffect?) {
        super.init(effect: effect)
        setupView()
        applySpeechProfilePreset()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        applySpeechProfilePreset()
    }

    private func setupView() {
        LiquidGlassEffectView.applyCapsuleStyle(to: self, cornerRadius: 44)

        speechBars.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(speechBars)

        widthConstraint = widthAnchor.constraint(equalToConstant: Style.defaultWidth)
        heightConstraint = heightAnchor.constraint(equalToConstant: Style.defaultHeight)

        NSLayoutConstraint.activate([
            speechBars.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            speechBars.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            speechBars.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20),
            speechBars.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),
            widthConstraint,
            heightConstraint,
        ].compactMap { $0 })

        applyCapsuleCornerRadius(forHeight: Style.defaultHeight)
        setCapsuleSize(width: Style.defaultWidth, height: Style.defaultHeight)

        applyOffscreenAppearance()
    }

    /// Tuned speech-profile preset from the speaking-characters experiment.
    func applySpeechProfilePreset() {
        speechBars.barColor = .systemBlue
        speechBars.barWidth = 7
        speechBars.barSpacing = 10
        speechBars.minBarHeight = 6
        speechBars.heightFill = 0.94
        speechBars.envelopeGain = Self.sliderValue(min: 0.4, max: 3.5, percent: 0.10)
        speechBars.liveGain = Self.sliderValue(min: 0.4, max: 3.5, percent: 0.80)
        speechBars.attackGain = Self.sliderValue(min: 0, max: 3.5, percent: 0.80)
        speechBars.smoothing = CGFloat(Self.sliderValue(min: 0.08, max: 0.75, percent: 0.30))
        speechBars.diamondFalloff = 0.75
        speechBars.meterHeight = 80 * 0.70
    }

    func setBarColor(_ color: UIColor) {
        speechBars.barColor = color
    }

    func setCapsuleSize(width: CGFloat, height: CGFloat) {
        widthConstraint?.constant = max(Style.sizeSliderMin, width)
        heightConstraint?.constant = max(Style.sizeSliderMin, height)
        applyCapsuleCornerRadius(forHeight: heightConstraint?.constant ?? height)
        speechBars.meterHeight = (heightConstraint?.constant ?? height) * 0.55
    }

    func install(in view: UIView, edge: SpeechProfileOverlayEdge) {
        hostView = view
        entryEdge = edge

        if superview !== view {
            if superview != nil {
                removeFromSuperview()
            }
            view.addSubview(self)
        }

        rebuildEdgeConstraints()
        if isVisible {
            edgeConstraint?.constant = shownEdgeConstant
            transform = .identity
            alpha = 1
        } else {
            applyOffscreenAppearance()
        }
    }

    func setEntryEdge(_ edge: SpeechProfileOverlayEdge) {
        guard edge != entryEdge else { return }
        entryEdge = edge
        guard hostView != nil else { return }
        rebuildEdgeConstraints()
        if isVisible {
            edgeConstraint?.constant = shownEdgeConstant
            transform = .identity
            alpha = 1
        } else {
            applyOffscreenAppearance()
        }
    }

    func pushPlayback(envelope: PlaybackEnvelope, at time: TimeInterval, liveLevel: Float) {
        speechBars.setPlayback(envelope: envelope, at: time, liveLevel: liveLevel)
    }

    func prepareForPlayback() {
        speechBars.reset()
    }

    func releaseToRest(completion: (() -> Void)? = nil) {
        speechBars.releaseToRest(completion: completion)
    }

    func present(completion: (() -> Void)? = nil) {
        guard !isVisible else {
            completion?()
            return
        }

        runningAnimator?.stopAnimation(true)
        runningAnimator = nil

        isVisible = true
        edgeConstraint?.constant = hiddenEdgeConstant
        transform = .identity
        alpha = 0
        hostView?.layoutIfNeeded()

        let animator = UIViewPropertyAnimator(
            duration: 0.34,
            controlPoint1: CGPoint(x: 0.85, y: 0),
            controlPoint2: CGPoint(x: 0.22, y: 1.18)
        ) {
            self.edgeConstraint?.constant = self.shownEdgeConstant
            self.hostView?.layoutIfNeeded()
            self.alpha = 1
        }
        animator.addCompletion { [weak self] position in
            guard position == .end else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            self?.runningAnimator = nil
            completion?()
        }
        runningAnimator = animator
        animator.startAnimation()
    }

    func dismiss(completion: (() -> Void)? = nil) {
        guard isVisible else {
            completion?()
            return
        }

        runningAnimator?.stopAnimation(true)
        runningAnimator = nil

        edgeConstraint?.constant = shownEdgeConstant
        transform = .identity
        alpha = 1
        hostView?.layoutIfNeeded()

        let animator = UIViewPropertyAnimator(
            duration: 0.28,
            controlPoint1: CGPoint(x: 1.12, y: -0.1),
            controlPoint2: CGPoint(x: 0.38, y: 1.17)
        ) {
            self.edgeConstraint?.constant = self.hiddenEdgeConstant
            self.hostView?.layoutIfNeeded()
            self.transform = .identity
            self.alpha = 1
        }
        animator.addCompletion { [weak self] _ in
            guard let self else {
                completion?()
                return
            }
            self.runningAnimator = nil
            self.isVisible = false
            self.applyOffscreenAppearance()
            completion?()
        }
        runningAnimator = animator
        animator.startAnimation()
    }

    private func rebuildEdgeConstraints() {
        guard let hostView else { return }

        NSLayoutConstraint.deactivate(
            [edgeConstraint, centerXConstraint, leadingConstraint, trailingConstraint].compactMap { $0 }
        )

        let safeArea = hostView.safeAreaLayoutGuide
        switch entryEdge {
        case .top:
            edgeConstraint = topAnchor.constraint(equalTo: safeArea.topAnchor, constant: shownEdgeConstant)
        case .bottom:
            edgeConstraint = bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: shownEdgeConstant)
        }

        centerXConstraint = centerXAnchor.constraint(equalTo: hostView.centerXAnchor)
        leadingConstraint = leadingAnchor.constraint(greaterThanOrEqualTo: hostView.leadingAnchor, constant: 24)
        trailingConstraint = trailingAnchor.constraint(lessThanOrEqualTo: hostView.trailingAnchor, constant: -24)

        NSLayoutConstraint.activate([
            edgeConstraint,
            centerXConstraint,
            leadingConstraint,
            trailingConstraint,
        ].compactMap { $0 })
    }

    private func applyOffscreenAppearance() {
        edgeConstraint?.constant = hiddenEdgeConstant
        hostView?.layoutIfNeeded()
        transform = .identity
        alpha = 0
    }

    private func applyCapsuleCornerRadius(forHeight height: CGFloat) {
        layer.cornerRadius = height / 2
    }

    private static func sliderValue(min: Float, max: Float, percent: Float) -> Float {
        min + percent * (max - min)
    }
}
