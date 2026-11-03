//
//  TutorOnboardingComponents.swift
//  shizen
//
//  Shared step base and chat pieces for the Hana tutor onboarding.
//

import InteractionKit
import NNKit
import UIKit

/// Step that plays scripted beats in place: header morphs, chat, then the CTA rises in.
/// Popping the step tears the stage down so it replays cleanly next time it is pushed.
///
/// Tap-to-advance: a tap on empty background (never a control, bubble, or slider) snaps running
/// animations to their end state and fires the next waiting beat. Picks, the name field, and
/// audio are never skipped; the CTA still only appears once the last beat lands.
class TutorStepViewController: OnboardingViewController, UIGestureRecognizerDelegate {

    /// UIView-animation keys that are safe to snap; repeating effects (typing dots, meters) use custom keys and keep running.
    private static let snappableAnimationKeys: Set<String> = [
        "opacity", "position", "bounds", "bounds.size", "bounds.origin", "transform", "backgroundColor",
    ]
    private static let skipHintShownKey = "onboarding.skipHintShown"

    static var reducesMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    let session: TutorOnboardingSession
    let timeline = TutorTimeline()
    let stage = UIView()

    private var hasStarted = false
    private var needsRebuild = false
    /// Scroll views that run up under the header with a soft edge effect.
    private var underHeaderScrollViews: [UIScrollView] = []
    private let headerEdgeInteraction: UIScrollEdgeElementContainerInteraction = {
        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.edge = .top
        return interaction
    }()

    init(session: TutorOnboardingSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addCTAButton()
        ctaButton?.alpha = 0
        ctaButton?.isUserInteractionEnabled = false

        let bottom = stage.bottomAnchor.constraint(equalTo: contentBottomAnchor, constant: -12)
        bottom.priority = .init(999)
        bottom.isActive = true

        labelStack.alpha = 0
        installTapToAdvance()
        headerContainerView.addInteraction(headerEdgeInteraction)
        buildStage()
    }

    // MARK: Scrolling under the header

    /// Lets a scrolling stage element run up behind the title, so scrolled content stays faintly
    /// visible through a soft edge effect instead of being cut off. `container` is pinned to the
    /// stage's top; it's re-pinned to the screen's top and `scrollView` is inset by the header height.
    func scrollUnderHeader(_ container: UIView, scrollView: UIScrollView) {
        let stageTopPins = stage.constraints.filter { constraint in
            (constraint.firstItem === container && constraint.firstAttribute == .top && constraint.secondItem === stage)
                || (constraint.secondItem === container && constraint.secondAttribute == .top && constraint.firstItem === stage)
        }
        NSLayoutConstraint.deactivate(stageTopPins)
        container.topAnchor.constraint(equalTo: view.topAnchor).isActive = true

        stage.clipsToBounds = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.topEdgeEffect.style = .soft
        scrollView.topEdgeEffect.isHidden = false
        headerEdgeInteraction.scrollView = scrollView
        view.bringSubviewToFront(headerContainerView)
        underHeaderScrollViews.append(scrollView)
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let headerInset = stage.frame.minY
        for scrollView in underHeaderScrollViews where scrollView.contentInset.top != headerInset {
            let wasAtTop = scrollView.contentOffset.y <= -scrollView.contentInset.top + 1
            scrollView.contentInset.top = headerInset
            scrollView.verticalScrollIndicatorInsets.top = headerInset
            if wasAtTop {
                scrollView.contentOffset.y = -headerInset
            }
        }
    }

    /// Scrolls to the newest content, honoring any under-header inset.
    func scrollToBottom(of scrollView: UIScrollView, animated: Bool = true) {
        scrollView.layoutIfNeeded()
        let inset = scrollView.adjustedContentInset
        let minY = -inset.top
        let maxY = max(minY, scrollView.contentSize.height + inset.bottom - scrollView.bounds.height)
        guard abs(scrollView.contentOffset.y - maxY) > 0.5 else { return }
        scrollView.setContentOffset(CGPoint(x: 0, y: maxY), animated: animated)
    }

    // MARK: Tap to advance

    private func installTapToAdvance() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)
        view.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Skip animation") { [weak self] _ in
                self?.fastForwardBeat()
                return true
            },
        ]
    }

    @objc private func backgroundTapped() {
        fastForwardBeat()
    }

    /// Lands everything in flight on its end state, then fires whatever beat was waiting on a timer.
    func fastForwardBeat() {
        snapAnimations(in: view)
        timeline.fastForward()
        view.layoutIfNeeded()
        snapAnimations(in: view)
    }

    private func snapAnimations(in root: UIView) {
        for key in root.layer.animationKeys() ?? [] where Self.snappableAnimationKeys.contains(key) {
            root.layer.removeAnimation(forKey: key)
        }
        root.subviews.forEach { snapAnimations(in: $0) }
    }

    /// Only empty background counts: anything interactive under the finger does its own job.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var candidate = touch.view
        while let current = candidate, current !== view {
            if current is UIControl || current is UITextField { return false }
            let ownsGesture = current.gestureRecognizers?.contains { recognizer in
                recognizer !== gestureRecognizer && recognizer.isEnabled && (
                    recognizer is UITapGestureRecognizer
                        || (recognizer is UIPanGestureRecognizer && !(current is UIScrollView))
                )
            } ?? false
            if ownsGesture { return false }
            candidate = current.superview
        }
        return true
    }

    /// A faint "Tap to skip ahead" caption, shown once ever, across every onboarding flow.
    func showSkipHintIfFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.skipHintShownKey) else { return }
        defaults.set(true, forKey: Self.skipHintShownKey)

        let hint = UILabel()
        hint.text = "Tap to skip ahead"
        hint.font = .preferredFont(forTextStyle: .caption1)
        hint.textColor = .tertiaryLabel
        hint.alpha = 0
        hint.isUserInteractionEnabled = false
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
        ])
        UIView.animate(withDuration: 0.6, delay: 0, options: [.allowUserInteraction]) {
            hint.alpha = 1
        }
        UIView.animate(withDuration: 0.8, delay: 4, options: [.allowUserInteraction], animations: {
            hint.alpha = 0
        }, completion: { _ in
            hint.removeFromSuperview()
        })
    }

    /// The stage is the one content area on every step: below the header, above the CTA, and clipped,
    /// so scrolled content never draws over the title. Anything living in the CTA slot goes on `view`.
    override func setupContent() {
        stage.translatesAutoresizingMaskIntoConstraints = false
        stage.clipsToBounds = true
        view.addSubview(stage)
        NSLayoutConstraint.activate([
            stage.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: 4),
            stage.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard needsRebuild else { return }
        needsRebuild = false
        resetStage()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hanaStageDidAppear(firstTime: !hasStarted)
        guard !hasStarted else { return }
        hasStarted = true
        start()
    }

    /// Steps are reused when pushed again, so a popped step rebuilds from the latest answers next time.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isMovingFromParent else { return }
        timeline.cancelAll()
        hasStarted = false
        needsRebuild = true
    }

    /// Install header text and stage subviews. Called on load and on every reset.
    func buildStage() {}

    /// Kick off the scripted beats once the header has started rising.
    func play() {}

    func restart() {
        resetStage()
        hasStarted = true
        start()
    }

    func resetStage() {
        timeline.cancelAll()
        underHeaderScrollViews.removeAll()
        stage.clipsToBounds = true
        stage.subviews.forEach { $0.removeFromSuperview() }
        hideCTA(animated: false)
        labelStack.layer.removeAllAnimations()
        labelStack.transform = .identity
        labelStack.alpha = 0
        advanceProgressBeat(to: 0)
        buildStage()
    }

    /// Slide distance for entrances; zero under Reduce Motion so things only cross-fade.
    static func slideDistance(_ distance: CGFloat) -> CGFloat {
        reducesMotion ? 0 : distance
    }

    private func start() {
        labelStack.prepareForSlideIn(slideDistance: Self.slideDistance(14))
        labelStack.animateSlideIn(duration: 0.55)
        play()
    }

    // MARK: Header

    func transitionHeader(title: String, subtitle: String?, completion: (() -> Void)? = nil) {
        let fadeOut = UIViewPropertyAnimator(duration: AnimationDefaults.fastDuration, curve: .easeIn) {
            self.labelStack.alpha = 0
        }
        fadeOut.addCompletion { [weak self] _ in
            guard let self else { return }
            self.setupOnboarding(title: title, subtitle: subtitle)
            UIViewPropertyAnimator(duration: 0.45, dampingRatio: 0.9) {
                self.view.layoutIfNeeded()
            }.startAnimation()
            self.labelStack.prepareForSlideIn(slideDistance: Self.slideDistance(14))
            self.labelStack.animateSlideIn(duration: 0.55, completion: completion)
        }
        fadeOut.startAnimation()
    }

    // MARK: CTA

    func revealCTA(_ title: String) {
        guard let button = ctaButton else { return }
        button.setTitle(title, for: .normal)
        button.isUserInteractionEnabled = true
        guard button.alpha < 1 else { return }
        button.prepareForSlideIn(slideDistance: Self.slideDistance(24))
        button.animateSlideIn(duration: 0.55)
    }

    func hideCTA(animated: Bool) {
        guard let button = ctaButton else { return }
        button.isUserInteractionEnabled = false
        guard animated else {
            button.alpha = 0
            return
        }
        UIView.animate(withDuration: AnimationDefaults.fastDuration) {
            button.alpha = 0
        }
    }

    // MARK: Fake generation

    /// Types `text` into `label` a few characters at a time, like a streamed model response.
    /// A tap-to-advance finishes the text instantly.
    func stream(_ text: String, into label: UILabel, onTick: (() -> Void)? = nil, completion: (() -> Void)? = nil) {
        label.text = nil
        let timeline = timeline
        let generation = timeline.skipGeneration
        timeline.run {
            var shown = ""
            for character in text {
                if timeline.skipGeneration != generation {
                    shown = text
                    label.text = text
                    onTick?()
                    break
                }
                shown.append(character)
                label.text = shown
                onTick?()
                try? await Task.sleep(for: .milliseconds(14))
                if Task.isCancelled { return }
            }
            completion?()
        }
    }

    /// A chat for this flow: listen-first v2 swaps the 🌸 avatars for the moving mascot.
    /// If the floating Hana is out when the chat first types, she flies into its slot.
    func makeChat() -> TutorChatView {
        let chat = TutorChatView(timeline: timeline, avatars: session.showsMascot ? .mascot : .emoji)
        chat.breakdownAction = { [weak self] line in self?.breakdownAction(for: line) }
        if let stage = session.hanaStage {
            chat.mascotEntrance = { [weak stage] frame, reveal in
                guard let stage, stage.isVisible else {
                    reveal()
                    return
                }
                stage.handOff(to: frame, reveal: reveal)
            }
        }
        return chat
    }

    /// The flow's floating Hana, if it has one (listen-first v2).
    var hanaStage: OnboardingHanaStage? { session.hanaStage }

    /// Each time the screen appears. Screens that park the floating Hana override this
    /// to dock her; by default she steps out.
    func hanaStageDidAppear(firstTime: Bool) {
        hanaStage?.hide()
    }

    func slideIn(_ views: [UIView], stagger: TimeInterval = 0.06, initialDelay: TimeInterval = 0) {
        views.forEach { $0.prepareForSlideIn(slideDistance: Self.slideDistance(18)) }
        UIView.animateSlideIn(views, duration: 0.55, stagger: stagger, initialDelay: initialDelay)
    }

    /// Demos a line's swipe until it's done, starting as a gentle lean and building slowly:
    /// each hint pulls a little further and waits a little longer before the next. Skips a beat
    /// while something is presented over the screen. A background tap fires the next one early.
    func nudge(_ line: TutorSwipeLine, toward gesture: TutorSwipeLine.Gesture, after delay: TimeInterval, attempt: Int = 0) {
        timeline.after(delay) { [weak self, weak line] in
            guard let self, let line, !line.isDone(gesture) else { return }
            var next = attempt
            if self.presentedViewController == nil {
                line.playHint(gesture, strength: min(1, 0.2 + 0.25 * CGFloat(attempt)))
                next += 1
            }
            self.nudge(line, toward: gesture, after: min(7, 3.5 + 1.25 * Double(attempt)), attempt: next)
        }
    }

    /// What a right swipe on `line` should do: open its breakdown. Nil when the flow has none
    /// for it, which asserts in a flow where every line must come apart.
    func breakdownAction(for line: TutorLine, onDismiss: (() -> Void)? = nil) -> (() -> Void)? {
        guard let script = session.breakdown(for: line.japanese) else {
            assert(!session.dissectsEveryLine, "No breakdown written for \(line.japanese)")
            return nil
        }
        return { [weak self] in self?.presentBreakdown(of: line, script: script, onDismiss: onDismiss) }
    }

    /// The lesson breakdown for a line, as a sheet: scripted, so nothing calls the gateway.
    /// Opens at half height. `onDismiss` runs once it's swiped away.
    func presentBreakdown(of line: TutorLine, script: SentenceScrubScript, onDismiss: (() -> Void)? = nil) {
        // Phrase English can carry a " · textbook: …" aside; the breakdown shows just the meaning.
        let english = line.english.components(separatedBy: " · ").first ?? line.english
        let scrub = SentenceScrubExperimentViewController(
            sentence: line.japanese,
            englishTranslation: english,
            script: script
        )
        scrub.title = "Line Preview"
        let sheet = TutorBreakdownSheet(rootViewController: scrub)
        sheet.onDismiss = onDismiss
        HapticsHelper.lightHaptic()
        present(sheet, animated: true)
    }
}

/// Page sheet for a scripted breakdown: opens at half height, pulls up to full, and reports
/// when it's swiped away.
final class TutorBreakdownSheet: UINavigationController, UIAdaptivePresentationControllerDelegate {

    var onDismiss: (() -> Void)?

    override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .medium
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            sheet.applySolidNonLargeBackground()
        }
        presentationController?.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish()
    }

    private func finish() {
        let onDismiss = onDismiss
        self.onDismiss = nil
        onDismiss?()
    }
}

/// A Japanese glass bubble that swipes like a lesson line. With `hidesEnglish`, a left swipe
/// drops the English in under it (and the next one hides it again). With `onBreakdown`, a right
/// swipe opens the line's breakdown. `side` nil is a tailless display line.
final class TutorSwipeLine: UIStackView {

    enum Gesture {
        /// Left swipe: show or hide the English.
        case revealEnglish
        /// Right swipe: open the breakdown.
        case breakdown
    }

    var onFirstReveal: (() -> Void)?
    /// Runs on a right swipe. Nil leaves the right swipe off.
    var onBreakdown: (() -> Void)? {
        didSet {
            swipe.allowsExpand = onBreakdown != nil
            updateAccessibility()
        }
    }
    private(set) var isRevealed = false
    private(set) var hasOpenedBreakdown = false
    private var hasRevealed = false

    /// The left swipe. Off until the instruction is on screen; always off with the English showing.
    var isRevealEnabled: Bool {
        get { swipe.allowsProgressiveReveal }
        set {
            swipe.allowsProgressiveReveal = newValue && hidesEnglish
            updateAccessibility()
        }
    }

    var hostScrollView: UIScrollView? {
        get { swipe.hostScrollView }
        set { swipe.hostScrollView = newValue }
    }

    private let line: TutorLine
    private let hidesEnglish: Bool
    private let swipe: SwipeRevealContainer
    private let english: UIView

    init(line: TutorLine, side: DialogueSpeakerSide?, hidesEnglish: Bool = true) {
        self.line = line
        self.hidesEnglish = hidesEnglish
        let bubble = OnboardingChrome.makeDialogueBubble(
            text: line.japanese,
            font: TutorChatView.japaneseFont,
            side: side,
            showsTail: side != nil
        )
        bubble.setContentHuggingPriority(.required, for: .horizontal)
        bubble.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        swipe = SwipeRevealContainer(bubbleView: bubble)
        swipe.allowsExpand = false
        swipe.allowsProgressiveReveal = false
        english = TutorChatView.englishLine(line.english, under: bubble, side: side)
        english.isHidden = hidesEnglish
        english.alpha = hidesEnglish ? 0 : 1
        super.init(frame: .zero)
        axis = .vertical
        spacing = 4
        alignment = side == .trailing ? .trailing : .leading
        translatesAutoresizingMaskIntoConstraints = false
        addArrangedSubview(swipe)
        addArrangedSubview(english)

        swipe.onProgressiveRevealCommit = { [weak self] in self?.toggleEnglish() }
        swipe.onCommit = { [weak self] in self?.openBreakdown() }

        isAccessibilityElement = true
        updateAccessibility()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func playHint(_ gesture: Gesture, strength: CGFloat) {
        switch gesture {
        case .revealEnglish: swipe.playProgressiveRevealHint(strength: strength)
        case .breakdown: swipe.playExpandHint(strength: strength)
        }
    }

    func isDone(_ gesture: Gesture) -> Bool {
        switch gesture {
        case .revealEnglish: return isRevealed
        case .breakdown: return hasOpenedBreakdown
        }
    }

    /// VoiceOver can't swipe a bubble: a double-tap does the line's main gesture, and the
    /// rotor offers both.
    override func accessibilityActivate() -> Bool {
        if isRevealEnabled {
            toggleEnglish()
            return true
        }
        guard onBreakdown != nil else { return false }
        openBreakdown()
        return true
    }

    private func openBreakdown() {
        guard let onBreakdown else { return }
        hasOpenedBreakdown = true
        onBreakdown()
    }

    private func toggleEnglish() {
        isRevealed.toggle()
        if isRevealed { english.isHidden = false }
        let apply = {
            self.english.alpha = self.isRevealed ? 1 : 0
            self.english.isHidden = !self.isRevealed
            self.window?.layoutIfNeeded()
        }
        if UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.2, animations: apply)
        } else {
            UIView.animate(
                withDuration: 0.34,
                delay: 0,
                usingSpringWithDamping: 0.9,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: apply
            )
        }
        updateAccessibility()
        if isRevealed {
            UIAccessibility.post(notification: .announcement, argument: line.english)
        }
        if isRevealed, !hasRevealed {
            hasRevealed = true
            onFirstReveal?()
        }
    }

    private func updateAccessibility() {
        let showsEnglish = !hidesEnglish || isRevealed
        accessibilityLabel = showsEnglish ? "\(line.japanese). \(line.english)" : line.japanese
        accessibilityTraits = isRevealEnabled || onBreakdown != nil ? .button : .staticText
        if isRevealEnabled {
            accessibilityHint = isRevealed ? "Double-tap to hide the English" : "Double-tap to show the English"
        } else if onBreakdown != nil {
            accessibilityHint = "Double-tap to break it down"
        } else {
            accessibilityHint = nil
        }
        var actions: [UIAccessibilityCustomAction] = []
        if isRevealEnabled, onBreakdown != nil {
            actions.append(UIAccessibilityCustomAction(name: "Break it down") { [weak self] _ in
                self?.openBreakdown()
                return true
            })
        }
        accessibilityCustomActions = actions
    }
}

enum TutorPalette {
    static let sakura = UIColor(red: 1, green: 0.45, blue: 0.62, alpha: 1)
}

// MARK: - Chat

final class TutorChatView: UIView {

    enum Message {
        case tutorJapanese(TutorLine)
        case tutorText(String)
        case userJapanese(TutorLine)
        case userText(String)

        var isTutor: Bool {
            switch self {
            case .tutorJapanese, .tutorText: return true
            case .userJapanese, .userText: return false
            }
        }

        var spokenText: String {
            switch self {
            case .tutorJapanese(let line), .userJapanese(let line): return "\(line.japanese). \(line.english)"
            case .tutorText(let text), .userText(let text): return text
            }
        }

        var length: Int {
            switch self {
            case .tutorJapanese(let line), .userJapanese(let line): return line.japanese.count + line.english.count
            case .tutorText(let text), .userText(let text): return text.count
            }
        }
    }

    static let japaneseFont = UIFont.systemFont(ofSize: 20, weight: .medium)

    /// The flower mascot's view size. It's wider than the avatar gutter and overhangs it.
    static let mascotSize: CGFloat = 46

    private let timeline: TutorTimeline
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var typingRow: UIView?
    private var lastLaidOutHeight: CGFloat = 0
    /// One mascot in place of the per-row 🌸 avatars. It springs to the line Hana is
    /// typing or just said. It lives in the scroll content, so it scrolls with the rows.
    private let mascot: MascotView?
    private weak var mascotAnchor: UIView?
    /// Hidden while another Hana flies into its slot; revealed when she lands.
    private var isMascotArriving = false

    private static let typingExpression = MascotPreset.thinking.expression
    /// Looking over at the bubble she just sent.
    private static let saidExpression = MascotExpression([.lookX: 0.55, .lookY: 0.1])

    enum Avatars {
        /// A 🌸 circle beside each of Hana's lines.
        case emoji
        /// One flower mascot that springs to whichever line Hana is on.
        case mascot
        /// No avatar at all; the screen shows Hana somewhere else.
        case none
    }

    private let avatars: Avatars
    /// What a right swipe on a Japanese line does; nil for none. Set by the step that owns the chat.
    var breakdownAction: ((TutorLine) -> (() -> Void)?)?
    /// True while the typing indicator is up, false once the line lands. For a Hana shown outside the chat.
    var onTypingChanged: ((Bool) -> Void)?
    /// Called instead of the pop-in the first time the mascot appears, with where it will sit
    /// (window coordinates). Call the closure to show it there. For a Hana flying in from elsewhere.
    var mascotEntrance: ((CGRect, @escaping () -> Void) -> Void)?

    init(timeline: TutorTimeline, avatars: Avatars = .emoji) {
        self.timeline = timeline
        self.avatars = avatars
        mascot = avatars == .mascot ? TutorChatView.makeMascot() : nil
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        let content = scrollView.contentLayoutGuide
        let frame = scrollView.frameLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: frame.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: frame.trailingAnchor, constant: -20),
        ])

        if let mascot {
            // Hidden until Hana first types, so it never sits over a custom card.
            mascot.alpha = 0
            scrollView.addSubview(mascot)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Basic pink, no haptics, and out of the way of taps.
    static func makeMascot() -> MascotView {
        let mascot = MascotView(frame: CGRect(x: 0, y: 0, width: mascotSize, height: mascotSize))
        mascot.setTheme(.pink, animated: false)
        mascot.hapticsEnabled = false
        mascot.isUserInteractionEnabled = false
        return mascot
    }

    /// Plays messages in order. Tutor lines get a typing indicator sized to their length.
    func play(_ messages: [Message], completion: (() -> Void)? = nil) {
        guard let first = messages.first else {
            completion?()
            return
        }
        let rest = Array(messages.dropFirst())

        guard first.isTutor else {
            append(first)
            timeline.after(0.3) { [weak self] in self?.play(rest, completion: completion) }
            return
        }

        showTyping()
        let typing = min(1.3, 0.55 + Double(first.length) * 0.012)
        timeline.after(typing) { [weak self] in
            guard let self else { return }
            self.hideTyping()
            self.append(first)
            HapticsHelper.superLightHaptic()
            self.timeline.after(0.45) { [weak self] in self?.play(rest, completion: completion) }
        }
    }

    func append(_ message: Message) {
        let row = makeRow(for: message)
        insert(row)
        if message.isTutor {
            moveMascot(to: row, expression: Self.saidExpression)
        }
        if message.isTutor, UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: message.spokenText)
        }
    }

    func appendCustom(_ view: UIView) {
        insert(view)
    }

    /// Slides every message up and out, then empties the chat so a new set can start from the top.
    func clear(completion: (() -> Void)? = nil) {
        hideTyping()
        let rows = stack.arrangedSubviews
        guard !rows.isEmpty else {
            completion?()
            return
        }
        let lift = max(bounds.height, stack.bounds.height) * 0.35
        for (index, row) in rows.reversed().enumerated() {
            UIView.animate(
                withDuration: 0.45,
                delay: Double(index) * 0.04,
                options: [.curveEaseIn, .beginFromCurrentState]
            ) {
                row.alpha = 0
                row.transform = CGAffineTransform(translationX: 0, y: -lift)
            }
        }
        // The mascot stays put on screen and rises to the top, where the next line will start.
        moveMascot(to: nil, expression: MascotExpression())
        let total = 0.45 + Double(rows.count - 1) * 0.04
        timeline.after(total) { [weak self] in
            guard let self else { return }
            rows.forEach { $0.removeFromSuperview() }
            self.scrollView.setContentOffset(CGPoint(x: 0, y: -self.scrollView.contentInset.top), animated: false)
            if let mascot = self.mascot {
                mascot.layer.removeAllAnimations()
                mascot.center = self.mascotCenter(for: nil)
            }
            completion?()
        }
    }

    /// The chat's own scroll view, for running it up under the header.
    var scrollContainer: UIScrollView { scrollView }

    func scrollToBottom(animated: Bool) {
        scrollView.layoutIfNeeded()
        let inset = scrollView.contentInset
        let minY = -inset.top
        let maxY = max(minY, scrollView.contentSize.height + inset.bottom - scrollView.bounds.height)
        guard abs(scrollView.contentOffset.y - maxY) > 0.5 else { return }
        scrollView.setContentOffset(CGPoint(x: 0, y: maxY), animated: animated)
    }

    /// The keyboard resizes the stage mid-animation; keep the newest line in view as it does.
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.height != lastLaidOutHeight else { return }
        let isFirstLayout = lastLaidOutHeight == 0
        lastLaidOutHeight = bounds.height
        guard !isFirstLayout, !scrollView.isDragging else { return }
        scrollToBottom(animated: false)
        // Width changes can reflow rows above the anchor; follow when not mid-spring.
        if let mascot, mascot.alpha > 0, mascot.layer.animationKeys()?.isEmpty ?? true,
           let anchor = mascotAnchor, anchor.superview != nil {
            mascot.center = mascotCenter(for: anchor)
        }
    }

    /// The mascot's frame in window coordinates. With `settledScroll`, where it will be once
    /// the scroll to the newest line finishes.
    private func mascotFrameInWindow(settledScroll: Bool) -> CGRect {
        guard let mascot else { return .zero }
        var frame = scrollView.convert(mascot.frame, to: nil)
        if settledScroll {
            let inset = scrollView.contentInset
            let maxY = max(-inset.top, scrollView.contentSize.height + inset.bottom - scrollView.bounds.height)
            frame.origin.y -= maxY - scrollView.contentOffset.y
        }
        return frame
    }

    /// Hides the chat's mascot and returns where it was (window coordinates), so a Hana
    /// elsewhere can take over from the same spot. Nil if it wasn't showing.
    func detachMascot() -> CGRect? {
        guard let mascot, mascot.alpha > 0 else { return nil }
        let frame = mascotFrameInWindow(settledScroll: false)
        mascot.layer.removeAllAnimations()
        mascot.alpha = 0
        return frame
    }

    /// Center for the mascot beside `row`, lined up where the old avatar sat (top of the row).
    /// With no row, the top of what's on screen.
    private func mascotCenter(for row: UIView?) -> CGPoint {
        let gutter = TutorAvatarView.size
        let top: CGFloat
        if let row {
            top = stack.frame.minY + row.frame.minY
        } else {
            top = scrollView.contentOffset.y + scrollView.contentInset.top + stack.frame.minY
        }
        return CGPoint(x: stack.frame.minX + gutter / 2, y: top + gutter / 2)
    }

    private func moveMascot(to row: UIView?, expression: MascotExpression) {
        guard let mascot else { return }
        mascotAnchor = row
        mascot.set(expression)
        scrollView.layoutIfNeeded()
        let target = mascotCenter(for: row)
        if isMascotArriving {
            mascot.center = target
            return
        }

        if mascot.alpha == 0 {
            // First appearance: pop in where she starts typing, unless someone flies her in.
            guard row != nil else { return }
            mascot.center = target
            if let entrance = mascotEntrance {
                mascotEntrance = nil
                isMascotArriving = true
                entrance(mascotFrameInWindow(settledScroll: true)) { [weak self] in
                    self?.isMascotArriving = false
                    mascot.alpha = 1
                }
                return
            }
            mascot.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            UIView.animate(springDuration: 0.5, bounce: 0.35) {
                mascot.alpha = 1
                mascot.transform = .identity
            }
            return
        }
        UIView.animate(
            springDuration: 0.55,
            bounce: 0.25,
            initialSpringVelocity: 0,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            mascot.center = target
        }
    }

    private func insert(_ row: UIView) {
        stack.addArrangedSubview(row)
        scrollToBottom(animated: true)
        row.prepareForSlideIn(slideDistance: TutorStepViewController.slideDistance(14))
        row.animateSlideIn(duration: 0.5)
    }

    private func showTyping() {
        guard typingRow == nil else { return }
        let row = Self.tutorRow(content: TutorTypingIndicatorView(), avatar: rowAvatar)
        typingRow = row
        insert(row)
        moveMascot(to: row, expression: Self.typingExpression)
        onTypingChanged?(true)
    }

    /// With the moving mascot, rows keep the avatar's gutter but leave it empty.
    private var rowAvatar: RowAvatar {
        switch avatars {
        case .emoji: return .emoji
        case .mascot: return .gutter
        case .none: return .none
        }
    }

    private func hideTyping() {
        guard let typingRow else { return }
        typingRow.removeFromSuperview()
        self.typingRow = nil
        onTypingChanged?(false)
    }

    private func makeRow(for message: Message) -> UIView {
        switch message {
        case .tutorJapanese(let line):
            let column = Self.japaneseColumn(
                line,
                side: .leading,
                onBreakdown: breakdownAction?(line) ?? nil,
                hostScrollView: scrollView
            )
            return Self.tutorRow(content: column, avatar: rowAvatar)
        case .tutorText(let text):
            return Self.tutorRow(content: Self.textBubble(text, side: .leading), avatar: rowAvatar)
        case .userJapanese(let line):
            let column = Self.japaneseColumn(
                line,
                side: .trailing,
                onBreakdown: breakdownAction?(line) ?? nil,
                hostScrollView: scrollView
            )
            return Self.userRow(content: column)
        case .userText(let text):
            return Self.userRow(content: Self.textBubble(text, side: .trailing))
        }
    }

    /// English chat lines wear the same glass bubble as Japanese ones, so a chat reads as one surface.
    static func textBubble(_ text: String, side: DialogueSpeakerSide) -> DialogueJapaneseBubbleView {
        let bubble = OnboardingChrome.makeDialogueBubble(
            text: text,
            font: .systemFont(ofSize: 16, weight: side == .trailing ? .semibold : .regular),
            side: side,
            showsTail: true
        )
        bubble.setContentHuggingPriority(.required, for: .horizontal)
        bubble.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return bubble
    }

    /// A Japanese bubble with its English under it. With `onBreakdown`, a right swipe on the
    /// bubble opens the line's breakdown.
    static func japaneseColumn(
        _ line: TutorLine,
        side: DialogueSpeakerSide?,
        showsEnglish: Bool = true,
        onBreakdown: (() -> Void)? = nil,
        hostScrollView: UIScrollView? = nil
    ) -> UIStackView {
        let bubble = OnboardingChrome.makeDialogueBubble(
            text: line.japanese,
            font: japaneseFont,
            side: side,
            showsTail: side != nil
        )
        bubble.setContentHuggingPriority(.required, for: .horizontal)
        bubble.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let swipeTarget = onBreakdown.map { dissectible(bubble, onBreakdown: $0, hostScrollView: hostScrollView) }
        let column = UIStackView(arrangedSubviews: [swipeTarget ?? bubble])
        column.axis = .vertical
        column.spacing = 4
        column.alignment = side == .trailing ? .trailing : .leading
        column.translatesAutoresizingMaskIntoConstraints = false

        if showsEnglish {
            column.addArrangedSubview(englishLine(line.english, under: bubble, side: side))
        }
        return column
    }

    /// Wraps any Japanese view so a right swipe opens its breakdown, the way lesson lines do.
    static func dissectible(_ view: UIView, onBreakdown: @escaping () -> Void, hostScrollView: UIScrollView? = nil) -> SwipeRevealContainer {
        let swipe = SwipeRevealContainer(bubbleView: view)
        swipe.allowsExpand = true
        swipe.allowsProgressiveReveal = false
        swipe.hostScrollView = hostScrollView
        swipe.expandAccessibilityHint = "Swipe right to break this line down"
        swipe.onCommit = onBreakdown
        swipe.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Break it down") { _ in
                onBreakdown()
                return true
            },
        ]
        return swipe
    }

    /// The English under a Japanese bubble, inset so it starts where the Japanese text does,
    /// not at the bubble's edge.
    static func englishLine(_ text: String, under bubble: DialogueJapaneseBubbleView, side: DialogueSpeakerSide?) -> UIView {
        let english = UILabel()
        english.text = text
        english.font = .preferredFont(forTextStyle: .subheadline)
        english.textColor = .secondaryLabel
        english.numberOfLines = 0
        english.textAlignment = side == .trailing ? .right : .left
        english.translatesAutoresizingMaskIntoConstraints = false

        let insets = bubble.labelHorizontalInsets
        let host = UIView()
        host.addSubview(english)
        NSLayoutConstraint.activate([
            english.topAnchor.constraint(equalTo: host.topAnchor),
            english.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            english.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: side == .trailing ? 0 : insets.leading),
            english.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: side == .trailing ? -insets.trailing : 0),
        ])
        return host
    }

    enum RowAvatar {
        /// The 🌸 circle.
        case emoji
        /// A standalone flower mascot, for a lone row outside a chat.
        case mascot
        /// Empty space the width of the avatar; the chat's moving mascot covers it.
        case gutter
        /// Flush left, no avatar or gutter.
        case none
    }

    static func tutorRow(content: UIView, avatar avatarKind: RowAvatar = .emoji) -> UIView {
        let row = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        if avatarKind == .none {
            row.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                content.topAnchor.constraint(equalTo: row.topAnchor),
                content.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                content.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -28),
            ])
            return row
        }
        let avatar: UIView
        switch avatarKind {
        case .emoji:
            avatar = TutorAvatarView()
        case .mascot:
            avatar = TutorMascotAvatarView()
        case .gutter, .none:
            avatar = UIView()
            avatar.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                avatar.widthAnchor.constraint(equalToConstant: TutorAvatarView.size),
                avatar.heightAnchor.constraint(equalToConstant: TutorAvatarView.size),
            ])
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(avatar)
        row.addSubview(content)
        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            avatar.topAnchor.constraint(equalTo: row.topAnchor),
            avatar.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor),

            content.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 8),
            content.topAnchor.constraint(equalTo: row.topAnchor),
            content.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            content.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -28),
        ])
        return row
    }

    static func userRow(content: UIView) -> UIView {
        let row = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(content)
        NSLayoutConstraint.activate([
            content.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            content.topAnchor.constraint(equalTo: row.topAnchor),
            content.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: row.leadingAnchor, constant: 56),
        ])
        return row
    }
}

final class TutorAvatarView: UIView {

    static let size: CGFloat = 30

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = Self.size / 2
        layer.borderWidth = 1.5
        isAccessibilityElement = true
        accessibilityLabel = "Hana"

        let label = UILabel()
        label.text = "🌸"
        label.font = .systemFont(ofSize: 16)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.size),
            heightAnchor.constraint(equalToConstant: Self.size),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        applyChrome()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TutorAvatarView, _) in
            view.applyChrome()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applyChrome() {
        backgroundColor = ExperimentPalette.highlightFill
        layer.borderColor = ExperimentPalette.highlightBorder.cgColor
    }
}

/// The flower mascot sized into the avatar slot, overhanging it a little like the chat's.
final class TutorMascotAvatarView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityLabel = "Hana"

        let mascot = TutorChatView.makeMascot()
        mascot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mascot)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: TutorAvatarView.size),
            heightAnchor.constraint(equalToConstant: TutorAvatarView.size),
            mascot.centerXAnchor.constraint(equalTo: centerXAnchor),
            mascot.centerYAnchor.constraint(equalTo: centerYAnchor),
            mascot.widthAnchor.constraint(equalToConstant: TutorChatView.mascotSize),
            mascot.heightAnchor.constraint(equalToConstant: TutorChatView.mascotSize),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Plain chat bubble for English asides (Japanese lines use DialogueJapaneseBubbleView).
final class TutorTypingIndicatorView: UIView {

    private var dots: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityLabel = "Hana is typing"

        // Glass, like the bubble it turns into.
        let glass = LiquidGlassEffectView.makeContainer()
        LiquidGlassEffectView.applyBubbleStyle(to: glass, cornerRadius: 18)
        glass.isUserInteractionEnabled = false
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for _ in 0..<3 {
            let dot = UIView()
            dot.backgroundColor = .secondaryLabel
            dot.layer.cornerRadius = 4
            dot.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 8),
                dot.heightAnchor.constraint(equalToConstant: 8),
            ])
            stack.addArrangedSubview(dot)
            dots.append(dot)
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Reduce Motion: a static "…" bubble.
        guard window != nil, !UIAccessibility.isReduceMotionEnabled else { return }
        let now = CACurrentMediaTime()
        for (index, dot) in dots.enumerated() {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.25
            pulse.toValue = 1
            pulse.duration = 0.42
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.beginTime = now + Double(index) * 0.15
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dot.layer.add(pulse, forKey: "typing")
        }
    }
}

// MARK: - Controls

final class TutorReplyChip: UIControl {

    let line: TutorLine

    var isChosen = false {
        didSet { applyChrome() }
    }

    init(line: TutorLine) {
        self.line = line
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        accessibilityLabel = "\(line.japanese), \(line.english)"
        accessibilityTraits = .button

        let japanese = UILabel()
        japanese.text = line.japanese
        japanese.font = .systemFont(ofSize: 18, weight: .semibold)
        japanese.textColor = .label
        japanese.numberOfLines = 0

        let english = UILabel()
        english.text = line.english
        english.font = .preferredFont(forTextStyle: .footnote)
        english.textColor = .secondaryLabel
        english.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [japanese, english])
        stack.axis = .vertical
        stack.spacing = 2
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let icon = UIImageView(image: UIImage(systemName: "mic.fill"))
        icon.tintColor = .tertiaryLabel
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: icon.leadingAnchor, constant: -12),

            icon.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
        ])
        applyChrome()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (chip: TutorReplyChip, _) in
            chip.applyChrome()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
            }
        }
    }

    private func applyChrome() {
        layer.borderWidth = isChosen ? ExperimentCardStroke.emphasisWidth : ExperimentCardStroke.normalWidth
        layer.borderColor = (isChosen ? ExperimentPalette.highlightBorder : ExperimentPalette.cardBorder).cgColor
        backgroundColor = isChosen ? ExperimentPalette.highlightFill : ExperimentPalette.cardSurface
    }
}

/// Fake mic capture: pulsing bars and the line to say. No audio is recorded.
final class TutorListeningView: UIView {

    private var bars: [UIView] = []

    init(prompt: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = ExperimentPalette.cardSurface
        layer.cornerRadius = 28
        layer.cornerCurve = .continuous
        layer.borderWidth = ExperimentCardStroke.normalWidth
        layer.borderColor = ExperimentPalette.cardBorder.cgColor

        let mic = UIImageView(image: UIImage(
            systemName: "mic.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        ))
        mic.tintColor = .systemRed
        mic.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "Say it: \(prompt)"
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .label
        label.numberOfLines = 2
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        label.translatesAutoresizingMaskIntoConstraints = false

        let barStack = UIStackView()
        barStack.axis = .horizontal
        barStack.alignment = .center
        barStack.spacing = 3
        barStack.translatesAutoresizingMaskIntoConstraints = false
        for _ in 0..<5 {
            let bar = UIView()
            bar.backgroundColor = .systemRed
            bar.layer.cornerRadius = 1.5
            bar.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                bar.widthAnchor.constraint(equalToConstant: 3),
                bar.heightAnchor.constraint(equalToConstant: 22),
            ])
            barStack.addArrangedSubview(bar)
            bars.append(bar)
        }

        addSubview(mic)
        addSubview(label)
        addSubview(barStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            mic.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            mic.centerYAnchor.constraint(equalTo: centerYAnchor),

            label.leadingAnchor.constraint(equalTo: mic.trailingAnchor, constant: 12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: barStack.leadingAnchor, constant: -12),

            barStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            barStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        let durations: [CFTimeInterval] = [0.32, 0.45, 0.27, 0.5, 0.38]
        for (index, bar) in bars.enumerated() {
            let wobble = CABasicAnimation(keyPath: "transform.scale.y")
            wobble.fromValue = 0.25
            wobble.toValue = 1
            wobble.duration = durations[index % durations.count]
            wobble.autoreverses = true
            wobble.repeatCount = .infinity
            wobble.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.layer.add(wobble, forKey: "listening")
        }
    }
}

final class TutorCapsuleLabel: UIView {

    init(text: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 17
        layer.cornerCurve = .continuous
        layer.borderWidth = ExperimentCardStroke.normalWidth

        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
        ])
        applyChrome()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TutorCapsuleLabel, _) in
            view.applyChrome()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applyChrome() {
        backgroundColor = ExperimentPalette.cardSurface
        layer.borderColor = ExperimentPalette.cardBorder.cgColor
    }
}

/// Name field that rides the keyboard up and down; the stage above it shrinks to
/// match, so the chat never sits underneath the field.
///
/// Tracks keyboard frame notifications rather than `keyboardLayoutGuide`: inside the
/// onboarding container (a nav controller embedded in a presented nav controller) the
/// guide stays at the home-indicator height and the field ends up under the keyboard.
final class TutorNameComposer: UIView, UITextFieldDelegate {

    var onSubmit: ((String) -> Void)?

    private static let restingGap: CGFloat = 8

    private let field = UITextField()
    private let sendButton = UIButton(type: .system)
    private var stageAboveComposer: NSLayoutConstraint?
    private var bottomToSafeArea: NSLayoutConstraint?
    private var keyboardObserver: NSObjectProtocol?

    init(placeholder: String = "Your first name") {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = ExperimentPalette.cardSurface
        layer.cornerRadius = 26
        layer.cornerCurve = .continuous
        layer.borderWidth = ExperimentCardStroke.normalWidth
        layer.borderColor = ExperimentPalette.cardBorder.cgColor

        field.placeholder = placeholder
        field.font = .systemFont(ofSize: 17, weight: .medium)
        field.autocapitalizationType = .words
        field.autocorrectionType = .no
        field.textContentType = .givenName
        field.returnKeyType = .send
        field.delegate = self
        field.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)

        sendButton.setImage(UIImage(
            systemName: "arrow.up.circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
        ), for: .normal)
        sendButton.tintColor = .systemYellow
        sendButton.accessibilityLabel = "Send"
        sendButton.addTarget(self, action: #selector(submit), for: .touchUpInside)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sendButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 52),

            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),

            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            sendButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 40),
            sendButton.heightAnchor.constraint(equalToConstant: 40),
        ])
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (composer: TutorNameComposer, _) in
            composer.layer.borderColor = ExperimentPalette.cardBorder.cgColor
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let keyboardObserver {
            NotificationCenter.default.removeObserver(keyboardObserver)
        }
    }

    /// Adds the composer to `view` above the keyboard, and keeps `stage` above it while it is open.
    func install(in view: UIView, above stage: UIView) {
        guard superview == nil else { return }
        view.addSubview(self)
        stageAboveComposer = stage.bottomAnchor.constraint(lessThanOrEqualTo: topAnchor, constant: -8)
        let bottom = bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Self.restingGap)
        bottomToSafeArea = bottom
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            bottom,
        ])
        keyboardObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.followKeyboard(note) }
        }
    }

    /// Lifts the composer by however much of the keyboard overlaps the host view, in step with the keyboard's own animation.
    private func followKeyboard(_ note: Notification) {
        guard let host = superview, let window = host.window,
              let endFrame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let keyboardTop = host.convert(window.convert(endFrame, from: window.screen.coordinateSpace), from: window).minY
        let safeBottom = host.bounds.maxY - host.safeAreaInsets.bottom
        let lift = max(0, safeBottom - keyboardTop)
        bottomToSafeArea?.constant = -(Self.restingGap + lift)

        let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        let curveRaw = note.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int ?? UIView.AnimationCurve.easeInOut.rawValue
        let curve = UIView.AnimationCurve(rawValue: curveRaw) ?? .easeInOut
        let animator = UIViewPropertyAnimator(duration: duration, curve: curve) {
            host.layoutIfNeeded()
        }
        animator.startAnimation()
    }

    /// Hidden but holding its slot, so the stage is already sized for it before it slides in.
    func reset() {
        field.resignFirstResponder()
        field.text = nil
        alpha = 0
        isUserInteractionEnabled = false
        stageAboveComposer?.isActive = true
        updateSendEnabled()
    }

    func open() {
        isUserInteractionEnabled = true
        prepareForSlideIn(slideDistance: 20)
        animateSlideIn(duration: 0.5)
        field.becomeFirstResponder()
    }

    /// Fades out and drops the keyboard; the stage grows back into the freed space.
    func close(in view: UIView) {
        isUserInteractionEnabled = false
        field.resignFirstResponder()
        stageAboveComposer?.isActive = false
        UIView.animate(withDuration: AnimationDefaults.standardDuration) {
            self.alpha = 0
            view.layoutIfNeeded()
        }
    }

    func dismissKeyboard() {
        field.resignFirstResponder()
    }

    private var trimmedText: String {
        (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @objc private func textChanged() {
        updateSendEnabled()
    }

    private func updateSendEnabled() {
        let hasName = !trimmedText.isEmpty
        sendButton.isEnabled = hasName
        sendButton.alpha = hasName ? 1 : 0.4
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submit()
        return false
    }

    @objc private func submit() {
        guard isUserInteractionEnabled, !trimmedText.isEmpty else { return }
        HapticsHelper.lightHaptic()
        onSubmit?(String(trimmedText.prefix(24)))
    }
}
