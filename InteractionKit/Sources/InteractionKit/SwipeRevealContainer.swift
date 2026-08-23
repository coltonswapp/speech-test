//
//  SwipeRevealContainer.swift
//  InteractionKit
//
//  Swipe a content view right to reveal a magnifying glass and enter focus.
//  In reveal mode, swipe left to peel back the next detail level, with a
//  yellow sparkles affordance on the trailing edge.
//

import UIKit

/// Optional hook so language-specific bubbles can dim/brighten glass while swiping.
public protocol SwipeRevealGlassAdjusting: AnyObject {
    func setSwipeRevealAmount(_ amount: CGFloat)
}

public typealias DialogueBubbleSwipeRevealContainer = SwipeRevealContainer

public final class SwipeRevealContainer: UIView, UIGestureRecognizerDelegate {

    public static let commitThreshold: CGFloat = 30
    public static let visualMax: CGFloat = 44
    /// A fast flick commits from a shorter travel — without this, a quick swipe
    /// that lifts before `commitThreshold` snaps back and the gesture reads as
    /// dropped.
    private static let flickCommitVelocity: CGFloat = 650
    private static let flickCommitMinTranslation: CGFloat = 12
    private static let rubberBandFactor: CGFloat = 0.12
    private static let edgeExclusionWidth: CGFloat = 35
    private static let horizontalVelocityDominance: CGFloat = 1.5
    private static let iconMinScale: CGFloat = 0.38
    private static let iconMaxScale: CGFloat = 1.0

    private static let inactiveIconColor = UIColor.secondaryLabel
    private static let expandActiveIconColor = UIColor.systemBlue
    private static let progressiveRevealActiveIconColor = UIColor.systemYellow

    /// Only one bubble may stay offset at a time.
    private static weak var activelyDragging: SwipeRevealContainer?
    private static weak var committedContainer: SwipeRevealContainer?

    public static func resetCommittedContainer(animated: Bool) {
        committedContainer?.reset(animated: animated)
    }

    /// Swipe right past threshold → sentence focus.
    public var onCommit: (() -> Void)?
    /// Swipe left past threshold → progressive reveal (reveal mode only).
    public var onProgressiveRevealCommit: (() -> Void)?

    /// When true, leftward pans drive the progressive-reveal affordance.
    public var allowsProgressiveReveal = false {
        didSet {
            updateAccessibilityHint()
        }
    }

    /// Disabled while a horizontal swipe is active so vertical scroll does not fight the reveal.
    public weak var hostScrollView: UIScrollView?

    public var panGestureRecognizer: UIPanGestureRecognizer { panGesture }

    private let bubbleView: UIView
    private let expandBackdrop = LiquidGlassEffectView.makeContainer()
    private let expandIcon = UIImageView()
    private let progressiveRevealBackdrop = LiquidGlassEffectView.makeContainer()
    private let progressiveRevealIcon = UIImageView()
    private let panGesture = UIPanGestureRecognizer()

    private let thresholdHaptic = UIImpactFeedbackGenerator(style: .light)
    private let commitHaptic = UIImpactFeedbackGenerator(style: .medium)

    /// Signed: positive = swipe right (expand), negative = swipe left (progressive reveal).
    private var rawTranslation: CGFloat = 0
    private var didCrossThreshold = false
    private var hostScrollWasEnabled = true
    private var isCommitted = false
    private var configuredContentPopDeferral = false

    public init(bubbleView: UIView) {
        self.bubbleView = bubbleView
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false

        configureIconChrome(
            backdrop: expandBackdrop,
            icon: expandIcon,
            systemName: "magnifyingglass"
        )
        configureIconChrome(
            backdrop: progressiveRevealBackdrop,
            icon: progressiveRevealIcon,
            systemName: "sparkles"
        )

        addSubview(expandBackdrop)
        addSubview(expandIcon)
        addSubview(progressiveRevealBackdrop)
        addSubview(progressiveRevealIcon)
        addSubview(bubbleView)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: topAnchor),
            bubbleView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor),

            expandBackdrop.widthAnchor.constraint(equalToConstant: 32),
            expandBackdrop.heightAnchor.constraint(equalToConstant: 32),
            expandBackdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            expandBackdrop.centerYAnchor.constraint(equalTo: centerYAnchor),

            expandIcon.centerXAnchor.constraint(equalTo: expandBackdrop.centerXAnchor),
            expandIcon.centerYAnchor.constraint(equalTo: expandBackdrop.centerYAnchor),
            expandIcon.widthAnchor.constraint(equalToConstant: 18),
            expandIcon.heightAnchor.constraint(equalToConstant: 18),

            progressiveRevealBackdrop.widthAnchor.constraint(equalToConstant: 32),
            progressiveRevealBackdrop.heightAnchor.constraint(equalToConstant: 32),
            progressiveRevealBackdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            progressiveRevealBackdrop.centerYAnchor.constraint(equalTo: centerYAnchor),

            progressiveRevealIcon.centerXAnchor.constraint(equalTo: progressiveRevealBackdrop.centerXAnchor),
            progressiveRevealIcon.centerYAnchor.constraint(equalTo: progressiveRevealBackdrop.centerYAnchor),
            progressiveRevealIcon.widthAnchor.constraint(equalToConstant: 18),
            progressiveRevealIcon.heightAnchor.constraint(equalToConstant: 18),
        ])

        panGesture.addTarget(self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        addGestureRecognizer(panGesture)

        thresholdHaptic.prepare()
        commitHaptic.prepare()
        updateAccessibilityHint()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// iOS 26+: content-area back swipe waits for the bubble reply pan to fail first.
    public func configureContentPopGestureDeferral(from viewController: UIViewController?) {
        guard !configuredContentPopDeferral else { return }
        if #available(iOS 26.0, *),
           let contentPop = viewController?.navigationController?.interactiveContentPopGestureRecognizer {
            contentPop.require(toFail: panGesture)
            configuredContentPopDeferral = true
        }
    }

    public func reset(animated: Bool, completion: (() -> Void)? = nil) {
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
            didCrossThreshold = abs(rawTranslation) >= Self.commitThreshold
            lockHostScrollIfNeeded()

        case .changed:
            let translation = gesture.translation(in: self).x
            if allowsProgressiveReveal {
                rawTranslation = translation
            } else {
                rawTranslation = max(0, translation)
            }
            applyVisuals(forRawTranslation: rawTranslation)
            updateThresholdHaptic(for: abs(rawTranslation))

        case .ended:
            let velocityX = gesture.velocity(in: self).x
            if rawTranslation > 0 {
                let isFlick = velocityX >= Self.flickCommitVelocity
                    && rawTranslation >= Self.flickCommitMinTranslation
                let shouldCommit = rawTranslation >= Self.commitThreshold || isFlick
                if shouldCommit {
                    commitExpand(animated: true)
                } else {
                    reset(animated: true)
                }
            } else if allowsProgressiveReveal, rawTranslation < 0 {
                let travel = abs(rawTranslation)
                let isFlick = velocityX <= -Self.flickCommitVelocity
                    && travel >= Self.flickCommitMinTranslation
                let shouldCommit = travel >= Self.commitThreshold || isFlick
                if shouldCommit {
                    commitProgressiveReveal(animated: true)
                } else {
                    reset(animated: true)
                }
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

    private func commitExpand(animated: Bool) {
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

    private func commitProgressiveReveal(animated: Bool) {
        Self.activelyDragging = nil
        didCrossThreshold = true
        commitHaptic.impactOccurred(intensity: 0.9)
        restoreHostScrollIfNeeded()
        onProgressiveRevealCommit?()
        // Snap back after peeling a level — progressive reveal does not stay open.
        reset(animated: animated)
    }

    private func applyVisuals(forRawTranslation raw: CGFloat) {
        let mapped = Self.mappedTranslation(raw)
        bubbleView.transform = CGAffineTransform(translationX: mapped, y: 0)

        let expandProgress = min(1, max(raw, 0) / Self.visualMax)
        let progressiveProgress = min(1, max(-raw, 0) / Self.visualMax)

        expandBackdrop.alpha = expandProgress
        expandIcon.alpha = expandProgress
        expandIcon.tintColor = Self.inactiveIconColor.interpolated(
            to: Self.expandActiveIconColor,
            progress: expandProgress
        )
        let expandScale = Self.iconMinScale
            + (Self.iconMaxScale - Self.iconMinScale) * expandProgress
        expandBackdrop.transform = CGAffineTransform(scaleX: expandScale, y: expandScale)
        expandIcon.transform = CGAffineTransform(scaleX: expandScale, y: expandScale)

        progressiveRevealBackdrop.alpha = progressiveProgress
        progressiveRevealIcon.alpha = progressiveProgress
        progressiveRevealIcon.tintColor = Self.inactiveIconColor.interpolated(
            to: Self.progressiveRevealActiveIconColor,
            progress: progressiveProgress
        )
        let progressiveScale = Self.iconMinScale
            + (Self.iconMaxScale - Self.iconMinScale) * progressiveProgress
        progressiveRevealBackdrop.transform = CGAffineTransform(
            scaleX: progressiveScale,
            y: progressiveScale
        )
        progressiveRevealIcon.transform = CGAffineTransform(
            scaleX: progressiveScale,
            y: progressiveScale
        )

        let glassAmount = isCommitted ? 1 : max(expandProgress, progressiveProgress)
        (bubbleView as? SwipeRevealGlassAdjusting)?.setSwipeRevealAmount(glassAmount)
    }

    private static func mappedTranslation(_ raw: CGFloat) -> CGFloat {
        let magnitude = abs(raw)
        let sign: CGFloat = raw < 0 ? -1 : 1
        guard magnitude > visualMax else { return raw }
        let excess = magnitude - visualMax
        return sign * (visualMax + excess * rubberBandFactor)
    }

    private func updateThresholdHaptic(for travel: CGFloat) {
        let crossed = travel >= Self.commitThreshold
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

    private func configureIconChrome(
        backdrop: UIVisualEffectView,
        icon: UIImageView,
        systemName: String
    ) {
        LiquidGlassEffectView.applyBubbleStyle(to: backdrop, cornerRadius: 16)
        backdrop.isUserInteractionEnabled = false
        backdrop.alpha = 0

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = UIImage(systemName: systemName, withConfiguration: symbolConfig)
        icon.tintColor = Self.inactiveIconColor
        icon.contentMode = .scaleAspectFit
        icon.isUserInteractionEnabled = false
        icon.alpha = 0
    }

    private func updateAccessibilityHint() {
        if allowsProgressiveReveal {
            accessibilityHint = "Swipe right to focus this sentence, or swipe left to reveal more"
        } else {
            accessibilityHint = "Swipe right to focus this sentence"
        }
    }

    // MARK: UIGestureRecognizerDelegate

    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture,
              let pan = gestureRecognizer as? UIPanGestureRecognizer
        else { return true }

        guard let coordinateView = window else { return false }
        let location = pan.location(in: coordinateView)
        guard location.x > Self.edgeExclusionWidth else { return false }

        let velocity = pan.velocity(in: self)
        let isHorizontal = abs(velocity.x) > abs(velocity.y) * Self.horizontalVelocityDominance
        guard isHorizontal else { return false }

        if allowsProgressiveReveal {
            return abs(velocity.x) > 0
        }
        return velocity.x > 0
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
