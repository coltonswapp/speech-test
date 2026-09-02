//
//  SwipeRevealContainer.swift
//  InteractionKit
//
//  Swipe a dialogue bubble right to focus the sentence. Swipe left to reveal
//  the next detail (English, or meter → Japanese → English in reveal mode).
//  Role Play adds Hear chrome on revealed lines (hidden after a learner
//  turn completes); Skip is the transport checkmark.
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

    /// When false, rightward pans are ignored (no expand / sentence focus).
    var allowsExpand = true {
        didSet {
            updateAccessibilityHint()
        }
    }

    /// When true, leftward pans drive the progressive-reveal affordance.
    public var allowsProgressiveReveal = false {
        didSet {
            updateAccessibilityHint()
        }
    }

    /// Symbol shown while swiping left. Defaults to reveal-mode sparkles.
    var progressiveRevealSymbolName = "sparkles" {
        didSet {
            applyProgressiveRevealSymbol()
        }
    }

    /// Color the right-swipe icon interpolates toward at commit.
    var expandActiveColor = UIColor.systemBlue

    /// Symbol shown while swiping right. Defaults to sentence-focus magnifying glass.
    var expandSymbolName = "magnifyingglass" {
        didSet {
            applyExpandSymbol()
        }
    }

    /// When true, a right-swipe commit snaps back instead of staying offset
    /// (used when the action is not a push, e.g. Role Play checkmark).
    var expandResetsAfterCommit = false

    /// After a focus push, hold the offset briefly then snap back so the bubble
    /// is centered again when the user returns from sentence scrub.
    private static let expandResetDelay: TimeInterval = 0.5
    private var expandResetGeneration = 0

    /// When true, a left-swipe commit snaps back. When false, the affordance
    /// stays exposed until `reset` (Role Play keeps the speaker icon up while
    /// the line plays).
    var progressiveRevealResetsAfterCommit = true

    /// Replaces the default “focus this sentence” hint when right-swipe means something else.
    var expandAccessibilityHint: String? {
        didSet {
            updateAccessibilityHint()
        }
    }

    /// Color the left-swipe icon interpolates toward at commit.
    var progressiveRevealActiveColor = UIColor.systemYellow

    /// Replaces the default “reveal more” hint when left-swipe means something else.
    var progressiveRevealAccessibilityHint: String? {
        didSet {
            updateAccessibilityHint()
        }
    }

    /// Disabled while a horizontal swipe is active so vertical scroll does not fight the reveal.
    public weak var hostScrollView: UIScrollView?

    public var panGestureRecognizer: UIPanGestureRecognizer { panGesture }

    /// Leading-edge status chrome (Role Play microphone / completion check).
    /// Moves with the bubble so a left-swipe replay carries it along.
    enum LeadingAccessory: Equatable {
        case hidden
        case microphone
        case microphoneOff
        case checkmark
    }

    /// Trailing-edge Hear chrome on revealed Role Play lines.
    enum TrailingAccessory: Equatable {
        case hidden
        case speaker
    }

    /// Cluster Hear (and Role Play mic) on the inner edge of the bubble,
    /// bottom-aligned with the speaker label.
    enum ChromeEdge {
        case leading
        case trailing
    }

    var chromeEdge: ChromeEdge = .trailing {
        didSet {
            guard oldValue != chromeEdge else { return }
            updateChromeEdgeConstraints()
        }
    }

    private(set) var leadingAccessory: LeadingAccessory = .hidden
    private(set) var trailingAccessory: TrailingAccessory = .hidden

    var leadingAccessoryActiveColor = UIColor.systemBlue
    var trailingAccessoryActiveColor = UIColor.systemYellow
    var onTrailingAccessoryTap: (() -> Void)?

    /// Diameter of Role Play mic / Hear chrome. Hosts use this to keep
    /// inter-row spacing from clipping the buttons that sit above the bubble.
    static let accessoryChromeSize: CGFloat = 38
    private static var chromeButtonSize: CGFloat { accessoryChromeSize }
    private static let chromeIconSize: CGFloat = 19
    private static let chromeSpacing: CGFloat = 6
    private static var chromeRadius: CGFloat { chromeButtonSize / 2 }

    private let bubbleView: UIView
    private let expandBackdrop = LiquidGlassEffectView.makeContainer()
    private let expandIcon = UIImageView()
    private let progressiveRevealBackdrop = LiquidGlassEffectView.makeContainer()
    private let progressiveRevealIcon = UIImageView()
    /// Fixed-slot chrome (mic / hear). Hosted on the container — not the bubble —
    /// so swipe translate and emphasis scale leave them put. Each button is pinned
    /// independently so hiding one never shifts the other.
    private let leadingAccessoryHost = UIView()
    private let leadingAccessoryBackdrop = LiquidGlassEffectView.makeContainer()
    private let leadingAccessoryIcon = UIImageView()
    private let trailingAccessoryButton = UIButton(type: .custom)
    private let trailingAccessoryBackdrop = LiquidGlassEffectView.makeContainer()
    private let trailingAccessoryIcon = UIImageView()
    private var chromeEdgeConstraints: [NSLayoutConstraint] = []
    private var chromeBottomConstraints: [NSLayoutConstraint] = []
    private let panGesture = UIPanGestureRecognizer()
    private var bubbleTranslationX: CGFloat = 0
    /// Focus scale applied by the host; composed with swipe translation so
    /// highlighting a line cannot slide the bubble back over the reveal icon.
    private var baseBubbleTransform: CGAffineTransform = .identity

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
        bubbleView.clipsToBounds = false

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

        configureIconChrome(
            backdrop: leadingAccessoryBackdrop,
            icon: leadingAccessoryIcon,
            systemName: "mic.fill",
            cornerRadius: Self.chromeRadius
        )
        leadingAccessoryHost.translatesAutoresizingMaskIntoConstraints = false
        leadingAccessoryHost.isUserInteractionEnabled = false
        leadingAccessoryHost.clipsToBounds = false
        leadingAccessoryHost.alpha = 0
        leadingAccessoryHost.isHidden = true
        leadingAccessoryBackdrop.alpha = 1
        leadingAccessoryIcon.alpha = 1

        configureIconChrome(
            backdrop: trailingAccessoryBackdrop,
            icon: trailingAccessoryIcon,
            systemName: "speaker.wave.2.fill",
            cornerRadius: Self.chromeRadius
        )
        trailingAccessoryButton.translatesAutoresizingMaskIntoConstraints = false
        trailingAccessoryButton.clipsToBounds = false
        trailingAccessoryButton.alpha = 0
        trailingAccessoryButton.isHidden = true
        trailingAccessoryButton.isUserInteractionEnabled = false
        trailingAccessoryButton.accessibilityLabel = "Hear this line"
        trailingAccessoryBackdrop.alpha = 1
        trailingAccessoryIcon.alpha = 1
        trailingAccessoryButton.addAction(
            UIAction { [weak self] _ in self?.onTrailingAccessoryTap?() },
            for: .primaryActionTriggered
        )

        addSubview(expandBackdrop)
        addSubview(expandIcon)
        addSubview(progressiveRevealBackdrop)
        addSubview(progressiveRevealIcon)
        addSubview(bubbleView)
        // Chrome sits above the bubble, aligned with the speaker label — not
        // nested in the bubble so swipe/emphasis transforms don't move it.
        addSubview(leadingAccessoryHost)
        leadingAccessoryHost.addSubview(leadingAccessoryBackdrop)
        leadingAccessoryHost.addSubview(leadingAccessoryIcon)
        addSubview(trailingAccessoryButton)
        trailingAccessoryButton.addSubview(trailingAccessoryBackdrop)
        trailingAccessoryButton.addSubview(trailingAccessoryIcon)

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

            leadingAccessoryHost.widthAnchor.constraint(equalToConstant: Self.chromeButtonSize),
            leadingAccessoryHost.heightAnchor.constraint(equalToConstant: Self.chromeButtonSize),

            leadingAccessoryBackdrop.topAnchor.constraint(equalTo: leadingAccessoryHost.topAnchor),
            leadingAccessoryBackdrop.leadingAnchor.constraint(equalTo: leadingAccessoryHost.leadingAnchor),
            leadingAccessoryBackdrop.trailingAnchor.constraint(equalTo: leadingAccessoryHost.trailingAnchor),
            leadingAccessoryBackdrop.bottomAnchor.constraint(equalTo: leadingAccessoryHost.bottomAnchor),

            leadingAccessoryIcon.centerXAnchor.constraint(equalTo: leadingAccessoryHost.centerXAnchor),
            leadingAccessoryIcon.centerYAnchor.constraint(equalTo: leadingAccessoryHost.centerYAnchor),
            leadingAccessoryIcon.widthAnchor.constraint(equalToConstant: Self.chromeIconSize),
            leadingAccessoryIcon.heightAnchor.constraint(equalToConstant: Self.chromeIconSize),

            trailingAccessoryButton.widthAnchor.constraint(equalToConstant: Self.chromeButtonSize),
            trailingAccessoryButton.heightAnchor.constraint(equalToConstant: Self.chromeButtonSize),

            trailingAccessoryBackdrop.topAnchor.constraint(equalTo: trailingAccessoryButton.topAnchor),
            trailingAccessoryBackdrop.leadingAnchor.constraint(equalTo: trailingAccessoryButton.leadingAnchor),
            trailingAccessoryBackdrop.trailingAnchor.constraint(equalTo: trailingAccessoryButton.trailingAnchor),
            trailingAccessoryBackdrop.bottomAnchor.constraint(equalTo: trailingAccessoryButton.bottomAnchor),

            trailingAccessoryIcon.centerXAnchor.constraint(equalTo: trailingAccessoryButton.centerXAnchor),
            trailingAccessoryIcon.centerYAnchor.constraint(equalTo: trailingAccessoryButton.centerYAnchor),
            trailingAccessoryIcon.widthAnchor.constraint(equalToConstant: Self.chromeIconSize),
            trailingAccessoryIcon.heightAnchor.constraint(equalToConstant: Self.chromeIconSize),
        ])
        // Default: sit just above the bubble until the host pins to a speaker label.
        alignChromeBottom(to: nil)
        updateChromeEdgeConstraints()

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

    func setLeadingAccessory(_ style: LeadingAccessory, animated: Bool, bounce: Bool = false) {
        let previous = leadingAccessory
        let styleChanged = previous != style
        leadingAccessory = style
        // Stop the listening pulse before a replace so the morph starts at full opacity.
        if style != .microphone {
            setLeadingAccessoryPulse(false)
        }
        if styleChanged {
            applyLeadingAccessoryAppearance(from: previous, animated: animated, bounce: bounce)
        } else if bounce, style == .checkmark {
            playLeadingAccessoryBounce()
        }
    }

    func setLeadingAccessoryPulse(_ on: Bool) {
        let key = "leadingAccessoryPulse"
        if on, leadingAccessory == .microphone {
            guard leadingAccessoryIcon.layer.animation(forKey: key) == nil else { return }
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.35
            pulse.duration = 0.7
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            leadingAccessoryIcon.layer.add(pulse, forKey: key)
        } else {
            leadingAccessoryIcon.layer.removeAnimation(forKey: key)
            if leadingAccessory != .hidden {
                leadingAccessoryIcon.alpha = 1
            }
        }
    }

    func setTrailingAccessory(_ style: TrailingAccessory, animated: Bool) {
        let styleChanged = trailingAccessory != style
        trailingAccessory = style
        guard styleChanged else { return }
        applyTrailingAccessoryAppearance(animated: animated)
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

    /// Host-applied emphasis (scale / edge-plant). Swipe translation is layered on top.
    func setBaseBubbleTransform(_ transform: CGAffineTransform) {
        baseBubbleTransform = transform
        applyComposedBubbleTransform()
    }

    func reset(animated: Bool, completion: (() -> Void)? = nil) {
        expandResetGeneration += 1
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
            if allowsExpand, allowsProgressiveReveal {
                rawTranslation = translation
            } else if allowsProgressiveReveal {
                rawTranslation = min(0, translation)
            } else if allowsExpand {
                rawTranslation = max(0, translation)
            } else {
                rawTranslation = 0
            }
            applyVisuals(forRawTranslation: rawTranslation)
            updateThresholdHaptic(for: abs(rawTranslation))

        case .ended:
            let velocityX = gesture.velocity(in: self).x
            if allowsExpand, rawTranslation > 0 {
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
        if expandResetsAfterCommit {
            Self.activelyDragging = nil
            didCrossThreshold = true
            commitHaptic.impactOccurred(intensity: 0.9)
            restoreHostScrollIfNeeded()
            onCommit?()
            reset(animated: animated)
            return
        }

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

        // Push immediately rather than waiting for the reveal spring to settle —
        // otherwise the transition feels laggy. The animation plays out behind
        // the pushed screen, then we snap the bubble home so return isn't offset.
        onCommit?()
        scheduleExpandReset()

        guard animated else {
            applyCommit()
            return
        }

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

    private func scheduleExpandReset() {
        expandResetGeneration += 1
        let generation = expandResetGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.expandResetDelay) { [weak self] in
            guard let self, self.expandResetGeneration == generation else { return }
            guard Self.committedContainer === self else { return }
            self.reset(animated: true)
        }
    }

    private func commitProgressiveReveal(animated: Bool) {
        Self.activelyDragging = nil
        didCrossThreshold = true
        commitHaptic.impactOccurred(intensity: 0.9)
        restoreHostScrollIfNeeded()
        onProgressiveRevealCommit?()
        if progressiveRevealResetsAfterCommit {
            reset(animated: animated)
            return
        }

        rawTranslation = -Self.visualMax
        let applyHold = {
            self.applyVisuals(forRawTranslation: -Self.visualMax)
        }
        guard animated else {
            applyHold()
            return
        }
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            applyHold()
        }
    }

    private func applyVisuals(forRawTranslation raw: CGFloat) {
        // Swipe direction and icon edge are the same for A and B: right-swipe
        // reveals leading chrome, left-swipe reveals trailing chrome.
        bubbleTranslationX = Self.mappedTranslation(raw)
        applyComposedBubbleTransform()

        let expandProgress = min(1, max(raw, 0) / Self.visualMax)
        let progressiveProgress = min(1, max(-raw, 0) / Self.visualMax)

        expandBackdrop.alpha = expandProgress
        expandIcon.alpha = expandProgress
        expandIcon.tintColor = Self.inactiveIconColor.interpolated(
            to: expandActiveColor,
            progress: expandProgress
        )
        let expandScale = Self.iconMinScale
            + (Self.iconMaxScale - Self.iconMinScale) * expandProgress
        expandBackdrop.transform = CGAffineTransform(scaleX: expandScale, y: expandScale)
        expandIcon.transform = CGAffineTransform(scaleX: expandScale, y: expandScale)

        progressiveRevealBackdrop.alpha = progressiveProgress
        progressiveRevealIcon.alpha = progressiveProgress
        progressiveRevealIcon.tintColor = Self.inactiveIconColor.interpolated(
            to: progressiveRevealActiveColor,
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

        let accessoryVisible: CGFloat = leadingAccessory == .hidden ? 0 : 1
        leadingAccessoryHost.alpha = accessoryVisible
        let trailingVisible: CGFloat = trailingAccessory == .hidden ? 0 : 1
        trailingAccessoryButton.alpha = trailingVisible

        let glassAmount = isCommitted ? 1 : max(expandProgress, progressiveProgress)
        (bubbleView as? SwipeRevealGlassAdjusting)?.setSwipeRevealAmount(glassAmount)
    }

    private func applyComposedBubbleTransform() {
        let swipe = CGAffineTransform(translationX: bubbleTranslationX, y: 0)
        bubbleView.transform = baseBubbleTransform.concatenating(swipe)
    }

    /// Pin chrome bottoms to the speaker name so the cluster reads with the label.
    /// Pass `nil` to sit flush above the bubble (no overlap).
    ///
    /// The speaker label must already share a hierarchy with this container
    /// (e.g. both in the message column) before calling — activating a
    /// cross-hierarchy constraint crashes Auto Layout.
    func alignChromeBottom(to speakerLabel: UIView?) {
        NSLayoutConstraint.deactivate(chromeBottomConstraints)
        let anchor: NSLayoutYAxisAnchor
        if let speakerLabel, Self.sharesCommonAncestor(speakerLabel, with: self) {
            anchor = speakerLabel.bottomAnchor
        } else {
            anchor = bubbleView.topAnchor
        }
        chromeBottomConstraints = [
            leadingAccessoryHost.bottomAnchor.constraint(equalTo: anchor),
            trailingAccessoryButton.bottomAnchor.constraint(equalTo: anchor),
        ]
        NSLayoutConstraint.activate(chromeBottomConstraints)
    }

    private static func sharesCommonAncestor(_ a: UIView, with b: UIView) -> Bool {
        var seen = Set<ObjectIdentifier>()
        var walk: UIView? = a
        while let view = walk {
            seen.insert(ObjectIdentifier(view))
            walk = view.superview
        }
        walk = b
        while let view = walk {
            if seen.contains(ObjectIdentifier(view)) { return true }
            walk = view.superview
        }
        return false
    }

    private func updateChromeEdgeConstraints() {
        NSLayoutConstraint.deactivate(chromeEdgeConstraints)
        let size = Self.chromeButtonSize
        let gap = Self.chromeSpacing
        switch chromeEdge {
        case .trailing:
            // Hear stays on the bubble's trailing edge; mic is a fixed slot inward.
            chromeEdgeConstraints = [
                trailingAccessoryButton.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor),
                leadingAccessoryHost.trailingAnchor.constraint(
                    equalTo: bubbleView.trailingAnchor,
                    constant: -(size + gap)
                ),
            ]
        case .leading:
            // Mic stays on the bubble's leading edge; hear is a fixed slot inward.
            chromeEdgeConstraints = [
                leadingAccessoryHost.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor),
                trailingAccessoryButton.leadingAnchor.constraint(
                    equalTo: bubbleView.leadingAnchor,
                    constant: size + gap
                ),
            ]
        }
        NSLayoutConstraint.activate(chromeEdgeConstraints)
    }

    private func applyTrailingAccessoryAppearance(animated: Bool) {
        applyTrailingAccessorySymbol()
        let visible = trailingAccessory != .hidden
        trailingAccessoryButton.isUserInteractionEnabled = visible
        if visible { trailingAccessoryButton.isHidden = false }
        let apply = {
            self.trailingAccessoryButton.alpha = visible ? 1 : 0
        }
        trailingAccessoryBackdrop.alpha = 1
        trailingAccessoryIcon.alpha = 1
        guard animated else {
            apply()
            if !visible { trailingAccessoryButton.isHidden = true }
            return
        }
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
        ) {
            apply()
        } completion: { [weak self] _ in
            guard let self else { return }
            if self.trailingAccessory == .hidden {
                self.trailingAccessoryButton.isHidden = true
            }
        }
    }

    private func applyTrailingAccessorySymbol() {
        switch trailingAccessory {
        case .hidden:
            break
        case .speaker:
            applySymbol("speaker.wave.2.fill", to: trailingAccessoryIcon)
            trailingAccessoryIcon.tintColor = trailingAccessoryActiveColor
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) { return true }
        return chromeContains(point)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if trailingAccessory != .hidden, trailingAccessoryButton.isUserInteractionEnabled,
           trailingAccessoryContains(point) {
            let local = trailingAccessoryButton.convert(point, from: self)
            return trailingAccessoryButton.hitTest(local, with: event) ?? trailingAccessoryButton
        }
        return super.hitTest(point, with: event)
    }

    private func chromeContains(_ point: CGPoint) -> Bool {
        if leadingAccessory != .hidden {
            let local = leadingAccessoryHost.convert(point, from: self)
            if leadingAccessoryHost.bounds.insetBy(dx: -6, dy: -6).contains(local) {
                return true
            }
        }
        return trailingAccessoryContains(point)
    }

    private func trailingAccessoryContains(_ point: CGPoint) -> Bool {
        guard trailingAccessory != .hidden else { return false }
        let local = trailingAccessoryButton.convert(point, from: self)
        return trailingAccessoryButton.bounds.insetBy(dx: -6, dy: -6).contains(local)
    }

    private func applyLeadingAccessoryBounceScale(_ bounceScale: CGFloat) {
        leadingAccessoryHost.transform = bounceScale == 1
            ? .identity
            : CGAffineTransform(scaleX: bounceScale, y: bounceScale)
    }

    private func applyLeadingAccessoryAppearance(
        from previous: LeadingAccessory,
        animated: Bool,
        bounce: Bool
    ) {
        let visible = leadingAccessory != .hidden
        if visible { leadingAccessoryHost.isHidden = false }

        let replacingMicrophoneWithCheckmark = animated
            && leadingAccessory == .checkmark
            && (previous == .microphone || previous == .microphoneOff)
        if replacingMicrophoneWithCheckmark {
            applyLeadingAccessorySymbol(replacing: true)
            leadingAccessoryHost.alpha = 1
            applyLeadingAccessoryBounceScale(1)
            if bounce { playLeadingAccessoryBounce() }
            return
        }

        applyLeadingAccessorySymbol()
        let apply = {
            self.leadingAccessoryHost.alpha = visible ? 1 : 0
            self.applyLeadingAccessoryBounceScale(1)
        }

        if animated {
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
            ) {
                apply()
            } completion: { _ in
                if bounce { self.playLeadingAccessoryBounce() }
                if self.leadingAccessory == .hidden {
                    self.leadingAccessoryHost.isHidden = true
                }
            }
        } else {
            apply()
            if bounce { playLeadingAccessoryBounce() }
            if !visible { leadingAccessoryHost.isHidden = true }
        }
    }

    private func applyLeadingAccessorySymbol(replacing: Bool = false) {
        switch leadingAccessory {
        case .hidden:
            break
        case .microphone:
            leadingAccessoryIcon.tintColor = leadingAccessoryActiveColor
            applySymbol("mic.fill", to: leadingAccessoryIcon, replacing: replacing)
        case .microphoneOff:
            leadingAccessoryIcon.tintColor = .systemGray
            applySymbol("mic.fill", to: leadingAccessoryIcon, replacing: replacing)
        case .checkmark:
            leadingAccessoryIcon.tintColor = leadingAccessoryActiveColor
            applySymbol("checkmark", to: leadingAccessoryIcon, replacing: replacing)
        }
    }

    private func playLeadingAccessoryBounce() {
        commitHaptic.impactOccurred(intensity: 0.85)
        applyLeadingAccessoryBounceScale(1.28)
        UIView.animate(
            withDuration: 0.42,
            delay: 0,
            usingSpringWithDamping: 0.42,
            initialSpringVelocity: 0.7,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.applyLeadingAccessoryBounceScale(1)
        }
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
        systemName: String,
        cornerRadius: CGFloat = 16
    ) {
        LiquidGlassEffectView.applyBubbleStyle(to: backdrop, cornerRadius: cornerRadius)
        // Perfect circles: continuous curve softens into a squircle at half-size.
        backdrop.layer.cornerCurve = .circular
        if #available(iOS 26.0, *) {
            backdrop.cornerConfiguration = .corners(radius: .fixed(cornerRadius))
        }
        backdrop.isUserInteractionEnabled = false
        backdrop.alpha = 0

        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = Self.inactiveIconColor
        icon.contentMode = .scaleAspectFit
        icon.isUserInteractionEnabled = false
        icon.alpha = 0
        if icon === progressiveRevealIcon {
            applyProgressiveRevealSymbol()
        } else if icon === expandIcon {
            applyExpandSymbol()
        } else if icon === trailingAccessoryIcon {
            applySymbol("speaker.wave.2.fill", to: icon)
        } else {
            applySymbol(systemName, to: icon)
        }
    }

    private func applyProgressiveRevealSymbol() {
        applySymbol(progressiveRevealSymbolName, to: progressiveRevealIcon)
    }

    private func applyExpandSymbol() {
        applySymbol(expandSymbolName, to: expandIcon)
    }

    private func applySymbol(_ systemName: String, to icon: UIImageView, replacing: Bool = false) {
        let pointSize: CGFloat = (icon === leadingAccessoryIcon || icon === trailingAccessoryIcon)
            ? Self.chromeIconSize
            : 15
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let image = UIImage(systemName: systemName, withConfiguration: symbolConfig)
        icon.preferredSymbolConfiguration = symbolConfig
        if replacing, let image {
            icon.setSymbolImage(image, contentTransition: .replace)
        } else {
            icon.image = image
        }
    }

    private func updateAccessibilityHint() {
        let rightHint = allowsExpand
            ? (expandAccessibilityHint ?? "Swipe right to focus this sentence")
            : nil
        let leftHint = allowsProgressiveReveal
            ? (progressiveRevealAccessibilityHint ?? "swipe left to reveal more")
            : nil
        switch (rightHint, leftHint) {
        case let (right?, left?):
            accessibilityHint = "\(right), or \(left)"
        case let (right?, nil):
            accessibilityHint = right
        case let (nil, left?):
            accessibilityHint = left
        case (nil, nil):
            accessibilityHint = nil
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

        if chromeContains(pan.location(in: self)) {
            return false
        }

        if allowsProgressiveReveal, allowsExpand {
            return abs(velocity.x) > 0
        }
        if allowsProgressiveReveal {
            return velocity.x < 0
        }
        if allowsExpand {
            return velocity.x > 0
        }
        return false
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

/// Full-width dialogue row. Role Play chrome can sit above the bubble (aligned
/// with the speaker label), so the row forwards hits that land outside the
/// bubble bounds into the swipe container.
final class DialogueLineRowView: UIView {
    weak var swipeContainer: DialogueBubbleSwipeRevealContainer?

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) { return true }
        if let swipeContainer {
            let converted = swipeContainer.convert(point, from: self)
            if swipeContainer.point(inside: converted, with: event) { return true }
        }
        return bounds.insetBy(dx: -48, dy: 0).contains(point)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let swipeContainer {
            let converted = swipeContainer.convert(point, from: self)
            if let hit = swipeContainer.hitTest(converted, with: event) {
                return hit
            }
        }
        return super.hitTest(point, with: event)
    }
}
