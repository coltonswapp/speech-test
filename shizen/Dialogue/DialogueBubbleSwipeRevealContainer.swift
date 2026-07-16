//
//  DialogueBubbleSwipeRevealContainer.swift
//  shizen
//
//  Swipe a dialogue bubble right to reveal a magnifying glass on the leading edge;
//  commit past a threshold to enter sentence focus mode.
//

import UIKit

final class DialogueBubbleSwipeRevealContainer: UIView, UIGestureRecognizerDelegate {

    static let commitThreshold: CGFloat = 30
    static let visualMax: CGFloat = 44
    private static let rubberBandFactor: CGFloat = 0.12
    private static let edgeExclusionWidth: CGFloat = 35
    private static let horizontalVelocityDominance: CGFloat = 1.5
    private static let magnifierMinScale: CGFloat = 0.38
    private static let magnifierMaxScale: CGFloat = 1.0

    private static let inactiveIconColor = UIColor.secondaryLabel
    private static let activeIconColor = UIColor.systemBlue

    /// Only one bubble may stay offset at a time.
    private static weak var activelyDragging: DialogueBubbleSwipeRevealContainer?
    private static weak var committedContainer: DialogueBubbleSwipeRevealContainer?

    static func resetCommittedContainer(animated: Bool) {
        committedContainer?.reset(animated: animated)
    }

    var onCommit: (() -> Void)?

    /// Disabled while a horizontal swipe is active so vertical scroll does not fight the reveal.
    weak var hostScrollView: UIScrollView?

    var panGestureRecognizer: UIPanGestureRecognizer { panGesture }

    private let bubbleView: UIView
    private let magnifierBackdrop = LiquidGlassEffectView.makeContainer()
    private let magnifierIcon = UIImageView()
    private let panGesture = UIPanGestureRecognizer()

    private let thresholdHaptic = UIImpactFeedbackGenerator(style: .light)
    private let commitHaptic = UIImpactFeedbackGenerator(style: .medium)

    private var rawTranslation: CGFloat = 0
    private var didCrossThreshold = false
    private var hostScrollWasEnabled = true
    private var isCommitted = false
    private var configuredContentPopDeferral = false

    init(bubbleView: UIView) {
        self.bubbleView = bubbleView
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false

        LiquidGlassEffectView.applyBubbleStyle(to: magnifierBackdrop, cornerRadius: 16)
        magnifierBackdrop.isUserInteractionEnabled = false
        magnifierBackdrop.alpha = 0

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        magnifierIcon.translatesAutoresizingMaskIntoConstraints = false
        magnifierIcon.image = UIImage(systemName: "magnifyingglass", withConfiguration: symbolConfig)
        magnifierIcon.tintColor = Self.inactiveIconColor
        magnifierIcon.contentMode = .scaleAspectFit
        magnifierIcon.isUserInteractionEnabled = false
        magnifierIcon.alpha = 0

        addSubview(magnifierBackdrop)
        addSubview(magnifierIcon)
        addSubview(bubbleView)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: topAnchor),
            bubbleView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor),

            magnifierBackdrop.widthAnchor.constraint(equalToConstant: 32),
            magnifierBackdrop.heightAnchor.constraint(equalToConstant: 32),
            magnifierBackdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            magnifierBackdrop.centerYAnchor.constraint(equalTo: centerYAnchor),

            magnifierIcon.centerXAnchor.constraint(equalTo: magnifierBackdrop.centerXAnchor),
            magnifierIcon.centerYAnchor.constraint(equalTo: magnifierBackdrop.centerYAnchor),
            magnifierIcon.widthAnchor.constraint(equalToConstant: 18),
            magnifierIcon.heightAnchor.constraint(equalToConstant: 18),
        ])

        panGesture.addTarget(self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        addGestureRecognizer(panGesture)

        thresholdHaptic.prepare()
        commitHaptic.prepare()

        accessibilityHint = "Swipe right to focus this sentence"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// iOS 26+: content-area back swipe waits for the bubble reply pan to fail first.
    func configureContentPopGestureDeferral(from viewController: UIViewController?) {
        guard !configuredContentPopDeferral else { return }
        if #available(iOS 26.0, *),
           let contentPop = viewController?.navigationController?.interactiveContentPopGestureRecognizer {
            contentPop.require(toFail: panGesture)
            configuredContentPopDeferral = true
        }
    }

    func reset(animated: Bool, completion: (() -> Void)? = nil) {
        isCommitted = false
        if Self.committedContainer === self {
            Self.committedContainer = nil
        }
        rawTranslation = 0
        didCrossThreshold = false
        restoreHostScrollIfNeeded()

        if Self.activelyDragging === self {
            Self.activelyDragging = nil
        }

        let applyReset = {
            self.applyVisuals(forRawTranslation: 0)
        }

        guard animated else {
            applyReset()
            completion?()
            return
        }

        UIView.animate(
            withDuration: 0.34,
            delay: 0,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            applyReset()
        } completion: { _ in
            completion?()
        }
    }

    // MARK: - Pan

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            if Self.committedContainer !== self {
                Self.committedContainer?.reset(animated: true)
            }
            if Self.activelyDragging !== self {
                Self.activelyDragging?.reset(animated: false)
            }
            Self.activelyDragging = self
            didCrossThreshold = rawTranslation >= Self.commitThreshold
            lockHostScrollIfNeeded()

        case .changed:
            let translation = max(0, gesture.translation(in: self).x)
            rawTranslation = translation
            applyVisuals(forRawTranslation: translation)
            updateThresholdHaptic(for: translation)

        case .ended:
            let shouldCommit = rawTranslation >= Self.commitThreshold
            if shouldCommit {
                commit(animated: true)
            } else {
                reset(animated: true)
            }

        case .cancelled, .failed:
            if isCommitted {
                restoreHostScrollIfNeeded()
            } else {
                reset(animated: true)
            }

        default:
            break
        }
    }

    private func commit(animated: Bool) {
        isCommitted = true
        Self.committedContainer = self
        Self.activelyDragging = nil
        rawTranslation = Self.visualMax
        didCrossThreshold = true
        commitHaptic.impactOccurred(intensity: 0.9)
        restoreHostScrollIfNeeded()

        let applyCommit = {
            self.applyVisuals(forRawTranslation: Self.visualMax)
        }

        guard animated else {
            applyCommit()
            onCommit?()
            return
        }

        // Push immediately rather than waiting for the reveal spring to settle —
        // otherwise the transition feels laggy. The animation plays out behind
        // the pushed screen.
        onCommit?()

        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            applyCommit()
        }
    }

    private func applyVisuals(forRawTranslation raw: CGFloat) {
        let mapped = Self.mappedTranslation(raw)
        bubbleView.transform = CGAffineTransform(translationX: mapped, y: 0)

        let progress = min(1, max(raw, 0) / Self.visualMax)
        magnifierBackdrop.alpha = progress
        magnifierIcon.alpha = progress
        magnifierIcon.tintColor = Self.inactiveIconColor.interpolated(
            to: Self.activeIconColor,
            progress: progress
        )

        let scale = Self.magnifierMinScale + (Self.magnifierMaxScale - Self.magnifierMinScale) * progress
        magnifierBackdrop.transform = CGAffineTransform(scaleX: scale, y: scale)
        magnifierIcon.transform = CGAffineTransform(scaleX: scale, y: scale)

        (bubbleView as? DialogueJapaneseBubbleView)?.setSwipeRevealAmount(isCommitted ? 1 : progress)
    }

    private static func mappedTranslation(_ raw: CGFloat) -> CGFloat {
        let clamped = max(0, raw)
        guard clamped > visualMax else { return clamped }
        let excess = clamped - visualMax
        return visualMax + excess * rubberBandFactor
    }

    private func updateThresholdHaptic(for translation: CGFloat) {
        let crossed = translation >= Self.commitThreshold
        guard crossed != didCrossThreshold else { return }
        didCrossThreshold = crossed
        if crossed {
            thresholdHaptic.impactOccurred(intensity: 0.75)
            thresholdHaptic.prepare()
        }
    }

    private func lockHostScrollIfNeeded() {
        guard let hostScrollView else { return }
        hostScrollWasEnabled = hostScrollView.isScrollEnabled
        hostScrollView.isScrollEnabled = false
    }

    private func restoreHostScrollIfNeeded() {
        guard let hostScrollView else { return }
        hostScrollView.isScrollEnabled = hostScrollWasEnabled
    }

    // MARK: UIGestureRecognizerDelegate

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture,
              let pan = gestureRecognizer as? UIPanGestureRecognizer
        else { return true }

        guard let coordinateView = window else { return false }
        let location = pan.location(in: coordinateView)
        guard location.x > Self.edgeExclusionWidth else { return false }

        let velocity = pan.velocity(in: self)
        return velocity.x > 0 && abs(velocity.x) > abs(velocity.y) * Self.horizontalVelocityDominance
    }
}

private extension UIColor {
    func interpolated(to color: UIColor, progress: CGFloat) -> UIColor {
        let t = min(max(progress, 0), 1)
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0

        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        color.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        return UIColor(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            alpha: a1 + (a2 - a1) * t
        )
    }
}
