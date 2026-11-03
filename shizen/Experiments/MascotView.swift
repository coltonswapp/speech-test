//
//  MascotView.swift
//  shizen
//
//  Procedural flower mascot drawn with Core Animation. Every knob in
//  `MascotExpression` is driven by a per-value spring, so any expression
//  can blend into any other mid-flight. Idle sway and blinking are layered on top.
//
//      mascot.set(MascotPreset.happy.expression)
//      mascot.look(at: touchPoint)
//

import UIKit

final class MascotView: UIView {

    // MARK: - Tunables

    /// Spring stiffness. Higher is snappier.
    var stiffness: CGFloat = 220
    /// 1 = no overshoot, around 0.5 = bouncy.
    var dampingRatio: CGFloat = 0.62
    /// Petal breathing, body bob and sway.
    var idleMotionEnabled = true { didSet { wakeDisplayLink() } }
    var autoBlinkEnabled = true { didSet { wakeDisplayLink() } }
    /// 0 = petals melt into one blob, 1 = deep notches where neighbors barely touch.
    var petalSpread: CGFloat = 0.6 { didSet { setNeedsLayout() } }
    /// 0 = perfectly even petals, 1 = hand-drawn size and angle jitter.
    var petalWobble: CGFloat = 0.6 { didSet { setNeedsLayout() } }
    /// Petal size relative to the face. The face stays put; petals shrink or grow around it.
    var petalScale: CGFloat = 0.88 { didSet { setNeedsLayout() } }
    /// Face diameter relative to the built-in size. 1 keeps the current face.
    var faceScale: CGFloat = 1 { didSet { setNeedsLayout() } }
    /// Soft taps during the spin.
    var hapticsEnabled = true
    /// Petals and the face disc only. Eyes, smile arcs, lids, and brows stay hidden.
    var showsEyes = true { didSet { if showsEyes != oldValue { setNeedsLayout() } } }
    /// Solid white eyes with no separate whites and pupils: the house style. Turn off for
    /// the classic whites-and-pupils look. Crossfades when changed. New mascots start
    /// with `savedSolidWhiteEyes`.
    var solidWhiteEyes = MascotView.savedSolidWhiteEyes {
        didSet {
            guard solidWhiteEyes != oldValue else { return }
            let now = CACurrentMediaTime()
            solidEyesFrom = solidEyesAmount(at: now)
            solidEyesStart = now
            wakeDisplayLink()
        }
    }

    /// The expression the mascot is springing toward.
    private(set) var expression = MascotExpression()
    /// Colors. Setting it crossfades; use `setTheme(_:animated:)` to snap.
    var theme: MascotTheme {
        get { themeTarget }
        set { setTheme(newValue) }
    }

    // MARK: - Layers

    private final class EyeLayers {
        let sclera = CAShapeLayer()
        let pupil = CAShapeLayer()
        /// Same path as the whites, so the pupil never leaves the eyeball.
        let pupilMask = CAShapeLayer()
        let arc = CAShapeLayer()
        let lid = CAShapeLayer()
        let brow = CAShapeLayer()

        var all: [CAShapeLayer] { [sclera, pupil, arc, lid, brow] }

        init() {
            sclera.fillColor = UIColor.white.cgColor
            pupil.mask = pupilMask
            for stroke in [arc, brow] {
                stroke.fillColor = nil
                stroke.lineCap = .round
            }
        }
    }

    /// Rotates, bobs and slides down for the peek. Local origin is the flower center.
    private let body = CALayer()
    private let petals = CAShapeLayer()
    private let face = CALayer()
    private let leftEye = EyeLayers()
    private let rightEye = EyeLayers()
    private let sparks = CAShapeLayer()
    private let questionLabel = UILabel()
    private let exclaimLabel = UILabel()
    private var questionFontSize: CGFloat = 0
    /// Recycled Z's that drift up while snoozing.
    private let zLabels = (0..<3).map { _ in UILabel() }

    // MARK: - Animation state

    private var current = MascotExpression()
    private var velocity = [CGFloat](repeating: 0, count: MascotParam.allCases.count)
    private var displayLink: CADisplayLink?
    private var blinkStart: CFTimeInterval?
    private var winkStart: CFTimeInterval?
    private var winkSide: CGFloat = -1
    /// Head lean that rides along with a wink: a small lift away, then a dip toward it.
    private var lean: CGFloat = 0
    private var leanVelocity: CGFloat = 0
    private let spinHaptic = UIImpactFeedbackGenerator(style: .soft)
    private var nextBlink: CFTimeInterval = CACurrentMediaTime() + 2

    private var themeTarget = MascotTheme.saved
    private var themeFrom = MascotTheme.saved
    private var themeStart: CFTimeInterval = 0
    private let themeDuration: CFTimeInterval = 0.45

    private var solidEyesFrom: CGFloat = 0
    private var solidEyesStart: CFTimeInterval = 0

    /// Petal-only rotation, in radians. Springs toward the target after a spin.
    private var petalAngle: CGFloat = 0
    private var petalAngleVelocity: CGFloat = 0
    private var petalAngleTarget: CGFloat = 0
    private var wasBusy = false

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        isOpaque = false
        // Clipping to our bounds is what makes the peek work.
        clipsToBounds = true

        face.masksToBounds = true
        face.cornerCurve = .circular

        body.addSublayer(petals)
        body.addSublayer(face)
        // Stack by kind (all whites, then pupils, arcs, lids, brows) so one eye's lid
        // can never paint over the other eye's brow.
        let kinds: [(EyeLayers) -> CAShapeLayer] = [{ $0.sclera }, { $0.pupil }, { $0.arc }, { $0.lid }, { $0.brow }]
        for kind in kinds {
            for eye in [leftEye, rightEye] {
                face.addSublayer(kind(eye))
            }
        }

        sparks.fillColor = nil
        sparks.lineCap = .round
        sparks.opacity = 0

        layer.addSublayer(body)
        layer.addSublayer(sparks)

        questionLabel.text = "?"
        questionLabel.textAlignment = .center
        questionLabel.alpha = 0
        addSubview(questionLabel)

        exclaimLabel.text = "!"
        exclaimLabel.textAlignment = .center
        exclaimLabel.alpha = 0
        addSubview(exclaimLabel)

        for label in zLabels {
            label.text = "z"
            label.textAlignment = .center
            label.alpha = 0
            addSubview(label)
        }

        isAccessibilityElement = false
    }

    // MARK: - Public API

    /// Springs toward `newValue`. With `animated: false` it snaps.
    func set(_ newValue: MascotExpression, animated: Bool = true) {
        expression = newValue
        if !animated || window == nil {
            current = newValue
            velocity = [CGFloat](repeating: 0, count: velocity.count)
            render(at: CACurrentMediaTime())
        }
        wakeDisplayLink()
    }

    func set(_ param: MascotParam, to value: CGFloat) {
        var next = expression
        next[param] = value
        set(next)
    }

    /// Sets a preset's expression and plays its one-shot flourish, if any.
    func play(_ preset: MascotPreset) {
        set(preset.expression)
        switch preset.flourish {
        case .spin: spinPetals()
        // Give the eyes a moment to spring open first, so the wink reads.
        case .wink: wink(.left, after: 0.3)
        case nil: break
        }
    }

    /// Lifts the head slightly away (anticipation), dips toward `side` as that eye
    /// closes into an arc, holds, then reopens and springs back to rest.
    func wink(_ side: MascotEyeSide = .left, after delay: CFTimeInterval = 0) {
        winkSide = side.sign
        winkStart = CACurrentMediaTime() + delay
        wakeDisplayLink()
    }

    /// Fidget-spinner flick. Spins by whole petals so it lands looking the same.
    func spinPetals(by petalSteps: Int = 3) {
        let step = 2 * CGFloat.pi / 5 * CGFloat(petalSteps)
        petalAngleTarget += step
        // Start fast and let the spring brake it, rather than winding up.
        petalAngleVelocity += step * 4.5
        wakeDisplayLink()
        playSpinHaptics()
    }

    /// Three soft taps that fade, like a spinner winding down.
    private func playSpinHaptics() {
        guard hapticsEnabled else { return }
        spinHaptic.prepare()
        for (delay, intensity) in [(0.0, 0.55), (0.11, 0.4), (0.24, 0.25)] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.spinHaptic.impactOccurred(intensity: intensity)
            }
        }
    }

    /// Blinks once now, whether or not auto blink is on.
    func blink() {
        blinkStart = CACurrentMediaTime()
        wakeDisplayLink()
    }

    func setTheme(_ newTheme: MascotTheme, animated: Bool = true) {
        let now = CACurrentMediaTime()
        themeFrom = animated && window != nil ? currentTheme(at: now) : newTheme
        themeTarget = newTheme
        themeStart = now
        render(at: now)
        wakeDisplayLink()
    }

    /// Points the eyes at `point` (in this view's coordinates), keeping every other knob.
    func look(at point: CGPoint) {
        let size = min(bounds.width, bounds.height)
        guard size > 0 else { return }
        var dx = (point.x - bounds.midX) / (size * 0.35)
        var dy = (point.y - bounds.midY) / (size * 0.35)
        let length = hypot(dx, dy)
        if length > 1 {
            dx /= length
            dy /= length
        }
        var next = expression
        next[.lookX] = dx
        next[.lookY] = dy
        // A finger beats daydreaming.
        next[.ponder] = 0
        set(next)
    }

    // MARK: - Lifecycle

    override func layoutSubviews() {
        super.layoutSubviews()
        render(at: CACurrentMediaTime())
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            displayLink?.invalidate()
            displayLink = nil
        } else {
            wakeDisplayLink()
        }
    }

    /// Keeps the display link from retaining the view.
    private final class DisplayLinkProxy: NSObject {
        weak var view: MascotView?
        init(_ view: MascotView) {
            self.view = view
            super.init()
        }
        @objc func step(_ link: CADisplayLink) { view?.step(link) }
    }

    private func wakeDisplayLink() {
        guard window != nil else { return }
        if displayLink == nil {
            let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.step(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        displayLink?.isPaused = false
    }

    // MARK: - Spring

    fileprivate func step(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let frame = link.targetTimestamp - link.timestamp
        let dt = CGFloat(min(max(frame, 1.0 / 240.0), 1.0 / 30.0))

        let k = stiffness
        let damping = 2 * dampingRatio * k.squareRoot()
        let substeps = max(1, Int((dt / (1.0 / 240.0)).rounded(.up)))
        let h = dt / CGFloat(substeps)

        var settled = true
        for i in current.values.indices {
            var x = current.values[i]
            var v = velocity[i]
            let goal = expression.values[i]
            for _ in 0..<substeps {
                let acceleration = k * (goal - x) - damping * v
                v += acceleration * h
                x += v * h
            }
            if abs(goal - x) < 0.0008, abs(v) < 0.002 {
                x = goal
                v = 0
            } else {
                settled = false
            }
            current.values[i] = x
            velocity[i] = v
        }

        // Busy: the petal target turns steadily like a gear. When work stops, it rounds up
        // to the next whole petal so the flower settles looking the same as before.
        if current.busy > 0.01 {
            petalAngleTarget += current.busy * 1.6 * dt
            wasBusy = true
        } else if wasBusy {
            wasBusy = false
            let petal = 2 * CGFloat.pi / 5
            petalAngleTarget = (petalAngleTarget / petal).rounded(.up) * petal
        }

        // Petal spin: a stiffer, less bouncy spring of its own.
        let spinK: CGFloat = 70
        let spinDamping = 2 * 0.72 * spinK.squareRoot()
        for _ in 0..<substeps {
            let acceleration = spinK * (petalAngleTarget - petalAngle) - spinDamping * petalAngleVelocity
            petalAngleVelocity += acceleration * h
            petalAngle += petalAngleVelocity * h
        }
        if abs(petalAngleTarget - petalAngle) < 0.0005, abs(petalAngleVelocity) < 0.002 {
            // Wrap so the angle never grows without bound.
            petalAngleTarget = petalAngleTarget.truncatingRemainder(dividingBy: 2 * .pi)
            petalAngle = petalAngleTarget
            petalAngleVelocity = 0
        } else {
            settled = false
        }

        // Wink lean: a bouncy spring chasing the wink timeline.
        let leanK: CGFloat = 160
        let leanDamping = 2 * 0.5 * leanK.squareRoot()
        let leanGoal = winkLeanTarget(at: now)
        for _ in 0..<substeps {
            let acceleration = leanK * (leanGoal - lean) - leanDamping * leanVelocity
            leanVelocity += acceleration * h
            lean += leanVelocity * h
        }
        if abs(leanGoal - lean) < 0.0005, abs(leanVelocity) < 0.002 {
            lean = leanGoal
            leanVelocity = 0
        } else {
            settled = false
        }

        if blinkStart != nil || winkStart != nil || now - themeStart < themeDuration || now - solidEyesStart < themeDuration || current.snooze > 0 || current.ponder > 0 || current.busy > 0 {
            settled = false
        }

        render(at: now)

        if settled, !idleMotionEnabled, !autoBlinkEnabled {
            link.isPaused = true
        }
    }

    private func blinkFactor(at time: CFTimeInterval) -> CGFloat {
        if blinkStart == nil, autoBlinkEnabled, time >= nextBlink {
            blinkStart = time
        }
        guard let start = blinkStart else { return 1 }
        let progress = (time - start) / 0.17
        if progress >= 1 {
            blinkStart = nil
            // Occasionally double-blink.
            nextBlink = time + (Int.random(in: 0..<5) == 0 ? 0.28 : Double.random(in: 2.2...5.5))
            return 1
        }
        return 1 - CGFloat(sin(progress * .pi))
    }

    private enum WinkTiming {
        static let anticipation = 0.14
        static let close = 0.12
        static let hold = 0.40
        static let reopen = 0.22
    }

    /// Lift away during the anticipation, dip toward the winking eye while it is shut.
    private func winkLeanTarget(at time: CFTimeInterval) -> CGFloat {
        guard let start = winkStart else { return 0 }
        let elapsed = time - start
        if elapsed < 0 { return 0 }
        if elapsed < WinkTiming.anticipation { return -winkSide * 0.05 }
        if elapsed < WinkTiming.anticipation + WinkTiming.close + WinkTiming.hold { return winkSide * 0.13 }
        return 0
    }

    /// 0 to 1 to 0: quick close, hold, slower reopen. Starts after the anticipation.
    private func winkFactor(at time: CFTimeInterval) -> CGFloat {
        guard let start = winkStart else { return 0 }
        let elapsed = time - start - WinkTiming.anticipation
        let close = WinkTiming.close, hold = WinkTiming.hold, reopen = WinkTiming.reopen
        func ease(_ x: Double) -> CGFloat {
            let x = CGFloat(min(1, max(0, x)))
            return x * x * (3 - 2 * x)
        }
        if elapsed < 0 { return 0 }
        if elapsed < close { return ease(elapsed / close) }
        if elapsed < close + hold { return 1 }
        if elapsed < close + hold + reopen { return 1 - ease((elapsed - close - hold) / reopen) }
        winkStart = nil
        return 0
    }

    // MARK: - Rendering

    /// -1 to 1. Holds on each side, with an eased glance between, on wall time.
    private func ponderGlance(at time: CFTimeInterval) -> CGFloat {
        let cycle = 2.8
        let p = CGFloat((time / cycle).truncatingRemainder(dividingBy: 1))
        func ease(_ x: CGFloat) -> CGFloat {
            let x = min(1, max(0, x))
            return x * x * (3 - 2 * x)
        }
        // 0–0.35 hold left, 0.35–0.5 glance right, 0.5–0.85 hold right, 0.85–1 glance back.
        if p < 0.35 { return -1 }
        if p < 0.5 { return -1 + 2 * ease((p - 0.35) / 0.15) }
        if p < 0.85 { return 1 }
        return 1 - 2 * ease((p - 0.85) / 0.15)
    }

    private static let solidWhiteEyesKey = "MascotView.solidWhiteEyes"

    /// The eye style new mascots start with, everywhere the mascot appears (the Playground
    /// toggle sets it). Solid white unless someone turned it off.
    static var savedSolidWhiteEyes: Bool {
        get { UserDefaults.standard.object(forKey: solidWhiteEyesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: solidWhiteEyesKey) }
    }

    /// 0 = classic eyes, 1 = solid white eyes, eased between on a toggle.
    private func solidEyesAmount(at time: CFTimeInterval) -> CGFloat {
        let goal: CGFloat = solidWhiteEyes ? 1 : 0
        let linear = CGFloat(min(1, max(0, (time - solidEyesStart) / themeDuration)))
        let p = linear * linear * (3 - 2 * linear)
        return solidEyesFrom + (goal - solidEyesFrom) * p
    }

    private func currentTheme(at time: CFTimeInterval) -> MascotTheme {
        let linear = CGFloat(min(1, max(0, (time - themeStart) / themeDuration)))
        guard linear < 1 else { return themeTarget }
        let p = linear * linear * (3 - 2 * linear)    // smoothstep
        var mixed = themeTarget
        mixed.petal = themeFrom.petal.mixed(with: themeTarget.petal, p)
        mixed.face = themeFrom.face.mixed(with: themeTarget.face, p)
        mixed.ink = themeFrom.ink.mixed(with: themeTarget.ink, p)
        mixed.spark = themeFrom.spark.mixed(with: themeTarget.spark, p)
        return mixed
    }

    private func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(value, low), high)
    }

    private func render(at time: CFTimeInterval) {
        let side = min(bounds.width, bounds.height)
        guard side > 1 else { return }

        let flower = side * 0.70                       // flower width
        var c = current
        // Ponder: eyes glance left, hold, glance right, hold. The head leans a little with them.
        let ponder = clamp(c.ponder, 0, 1)
        // Busy: eyes scan back and forth like reading, on wall time.
        let busy = clamp(c.busy, 0, 1)
        if busy > 0 {
            c[.lookX] += sin(CGFloat(time) * 2.4) * 0.45 * busy
        }
        if ponder > 0 {
            let glance = ponderGlance(at: time)
            c[.lookX] = c.lookX * (1 - ponder) + glance * 0.8 * ponder
            c[.tilt] += glance * 0.08 * ponder
        }
        let idle: CGFloat = idleMotionEnabled ? 1 : 0
        let t = CGFloat(time)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // Body: bob, sway, tilt, peek.
        let restCenter = CGPoint(x: bounds.midX, y: bounds.midY + 0.02 * flower)
        // Busy adds a quick little nod, like typing.
        let bob = idle * sin(t * 1.7) * 0.012 * flower + busy * abs(sin(t * 6)) * 0.014 * flower
        let sway = idle * sin(t * 0.9) * 0.03
        let peekOffset = c.peek * (bounds.height / 2 - 0.04 * flower)
        body.bounds = CGRect(x: 0, y: 0, width: flower, height: flower)
        // Leaning toward a side also drops the head a touch; leaning away lifts it.
        let leanDrop = lean * winkSide * 0.15 * flower
        body.position = CGPoint(x: restCenter.x, y: restCenter.y + bob + peekOffset + leanDrop)
        body.transform = CATransform3DMakeRotation(c.tilt * 0.35 + sway + lean, 0, 0, 1)

        // Petals: five slightly uneven ovals around a hub that breathe a little.
        // Spread trades petal size for distance so the outer edge stays put while the
        // notches between neighbors deepen. The hub keeps deep notches from opening holes.
        petals.bounds = body.bounds
        petals.position = CGPoint(x: flower / 2, y: flower / 2)
        petals.transform = CATransform3DMakeRotation(petalAngle, 0, 0, 1)
        let spread = clamp(petalSpread, 0, 1)
        let irregularity = clamp(petalWobble, 0, 1)
        let petalSize = clamp(petalScale, 0.5, 1.2)
        let baseRadius = (0.235 - 0.075 * spread) * flower * petalSize
        // Separated petals read better a little longer than wide.
        let elongation = 1 + 0.10 * irregularity + 0.08 * spread
        let baseDistance = 0.50 * flower * petalSize - baseRadius * (1 + 0.08 * spread)
        let hub = max(0.20, 0.21 * petalSize) * flower
        let petalPath = CGMutablePath()
        petalPath.addEllipse(in: CGRect(x: flower / 2 - hub, y: flower / 2 - hub, width: hub * 2, height: hub * 2))
        for i in 0..<5 {
            let index = CGFloat(i)
            let jitter = Self.petalJitter[i]
            let angle = -CGFloat.pi / 2 + index * 2 * .pi / 5 + irregularity * jitter.angle * .pi / 180
            let distance = baseDistance * (1 + idle * 0.035 * sin(t * 1.4 + index * 2.2))
            let radius = baseRadius * (1 + irregularity * jitter.size) * (1 + idle * 0.03 * sin(t * 1.9 + index * 1.3))
            let length = radius * elongation
            let width = radius * (1 - 0.04 * irregularity)
            let transform = CGAffineTransform(translationX: flower / 2 + cos(angle) * distance,
                                              y: flower / 2 + sin(angle) * distance)
                .rotated(by: angle)
            petalPath.addEllipse(in: CGRect(x: -length, y: -width, width: length * 2, height: width * 2),
                                 transform: transform)
        }
        petals.path = petalPath

        // Face: slides slightly toward where the eyes look.
        // Small mascots get a bigger face so the eyes keep their detail:
        // full size at 220pt and up, about 25% bigger by 72pt.
        let smallness = 1 - clamp((side - 72) / (220 - 72), 0, 1)
        let faceBoost = 1 + 0.25 * smallness * smallness * (3 - 2 * smallness)
        let u = 0.36 * flower * faceBoost * clamp(faceScale, 0.35, 1.8)
        face.bounds = CGRect(x: 0, y: 0, width: u, height: u)
        face.cornerRadius = u / 2
        face.position = CGPoint(
            x: flower / 2 + clamp(c.lookX, -1.2, 1.2) * 0.035 * flower,
            y: flower / 2 + clamp(c.lookY, -1.2, 1.2) * 0.035 * flower
        )

        // Colors.
        let palette = currentTheme(at: time)
        petals.fillColor = palette.petal.cgColor
        face.backgroundColor = palette.face.cgColor
        sparks.strokeColor = palette.spark.cgColor
        questionLabel.textColor = palette.spark.uiColor
        exclaimLabel.textColor = palette.spark.uiColor
        // Solid white eyes: white ink, and the whites fade out so the pupil is the whole eye.
        let solid = solidEyesAmount(at: time)
        let ink = palette.ink.mixed(with: MascotTheme.RGB(0xFFFFFF), solid)
        var eyes = c
        eyes[.sclera] = clamp(c.sclera, 0, 1) * (1 - solid)
        for eye in [leftEye, rightEye] {
            eye.lid.fillColor = palette.face.cgColor
            eye.arc.strokeColor = ink.cgColor
            eye.brow.strokeColor = ink.cgColor
            // On the whites the pupil is always dark, even for white-ink themes.
            eye.pupil.fillColor = ink.mixed(with: MascotTheme.darkInk, eyes.sclera).cgColor
        }

        // Eyes.
        let blink = blinkFactor(at: time)
        // The wink knob holds the left eye; a wink flourish closes whichever side it was given.
        let flourishWink = winkFactor(at: time)
        let winkLeft = clamp(c.wink + (winkSide < 0 ? flourishWink : 0), 0, 1)
        let winkRight = winkSide > 0 ? flourishWink : 0
        let smileLeft = clamp(c.smile + winkLeft * (1 - c.smile), -1.4, 1.4)
        let smileRight = clamp(c.smile + winkRight * (1 - c.smile), -1.4, 1.4)
        if showsEyes {
            layoutEye(leftEye, side: -1, smile: smileLeft, u: u, c: eyes, blink: blink)
            layoutEye(rightEye, side: 1, smile: smileRight, u: u, c: eyes, blink: blink)
        } else {
            for eye in [leftEye, rightEye] {
                for layer in eye.all { layer.opacity = 0 }
            }
        }

        // Sparks: four radial dashes that pop out around the head.
        sparks.frame = bounds
        let sparkAmount = max(0, c.sparks)
        let twinkle = 1 + idle * 0.10 * sin(t * 11)
        let sparkPath = CGMutablePath()
        for degrees in [-128.0, -154.0, -26.0, -2.0] {
            let angle = CGFloat(degrees) * .pi / 180
            let inner = 0.58 * flower
            let outer = inner + 0.10 * flower * sparkAmount * twinkle
            sparkPath.move(to: CGPoint(x: restCenter.x + cos(angle) * inner, y: restCenter.y + sin(angle) * inner))
            sparkPath.addLine(to: CGPoint(x: restCenter.x + cos(angle) * outer, y: restCenter.y + sin(angle) * outer))
        }
        sparks.path = sparkPath
        sparks.lineWidth = 0.034 * flower
        sparks.opacity = Float(min(1, sparkAmount * 1.5) * (1 - clamp(c.peek, 0, 1)))

        // Question mark: scales in with a wobble.
        let questionAmount = max(0, c.question)
        let fontSize = (0.34 * flower).rounded()
        if abs(fontSize - questionFontSize) > 0.5 {
            questionFontSize = fontSize
            let base = UIFont.systemFont(ofSize: fontSize, weight: .black)
            let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
            questionLabel.font = UIFont(descriptor: descriptor, size: fontSize)
            questionLabel.bounds = CGRect(x: 0, y: 0, width: fontSize, height: fontSize * 1.3)
            exclaimLabel.font = questionLabel.font
            exclaimLabel.bounds = questionLabel.bounds

            let zSize = (fontSize * 0.55).rounded()
            let zBase = UIFont.systemFont(ofSize: zSize, weight: .heavy)
            let zFont = UIFont(descriptor: zBase.fontDescriptor.withDesign(.rounded) ?? zBase.fontDescriptor, size: zSize)
            for label in zLabels {
                label.font = zFont
                label.bounds = CGRect(x: 0, y: 0, width: zSize * 1.2, height: zSize * 1.3)
            }
        }
        questionLabel.center = CGPoint(x: restCenter.x + 0.46 * flower, y: restCenter.y - 0.44 * flower)
        questionLabel.alpha = min(1, questionAmount * 1.5) * (1 - clamp(c.peek, 0, 1))
        let wobble = 0.25 + idle * 0.08 * sin(t * 2.6)
        let questionScale = max(questionAmount, 0.001)
        questionLabel.transform = CGAffineTransform(rotationAngle: wobble).scaledBy(x: questionScale, y: questionScale)

        // Exclamation mark: pops up off the top right, standing nearly upright. The face
        // spring's overshoot gives it a bounce on the way in.
        let exclaimAmount = max(0, c.exclaim)
        exclaimLabel.center = CGPoint(
            x: restCenter.x + 0.40 * flower,
            y: restCenter.y - (0.40 + 0.08 * min(1, exclaimAmount)) * flower
        )
        exclaimLabel.alpha = min(1, exclaimAmount * 1.5) * (1 - clamp(c.peek, 0, 1))
        let exclaimScale = max(exclaimAmount, 0.001)
        exclaimLabel.transform = CGAffineTransform(rotationAngle: 0.18 + idle * 0.05 * sin(t * 3.1))
            .scaledBy(x: exclaimScale, y: exclaimScale)

        // Z's: each one rises from the top right of the head, drifting and growing, then
        // fades and loops. Runs on wall time so it keeps going with idle motion off.
        let snooze = clamp(c.snooze, 0, 1)
        for (i, label) in zLabels.enumerated() {
            label.textColor = palette.face.uiColor
            guard snooze > 0.001 else {
                label.alpha = 0
                continue
            }
            let cycle = 2.6
            let p = CGFloat((time / cycle + Double(i) / Double(zLabels.count)).truncatingRemainder(dividingBy: 1))
            let drift = sin(p * 2 * .pi + CGFloat(i)) * 0.03 * flower
            label.center = CGPoint(
                x: restCenter.x + (0.24 + 0.26 * p) * flower + drift,
                y: restCenter.y - (0.30 + 0.34 * p) * flower
            )
            let scale = 0.5 + 0.7 * p
            label.transform = CGAffineTransform(rotationAngle: -0.25 + 0.15 * sin(p * .pi)).scaledBy(x: scale, y: scale)
            // Fade in fast, out slow.
            let fade = min(1, p * 6) * (1 - p)
            label.alpha = snooze * fade * 1.4 * (1 - clamp(c.peek, 0, 1))
        }
    }

    /// Fixed per-petal offsets (degrees, fraction of radius) so the flower looks hand-drawn.
    private static let petalJitter: [(angle: CGFloat, size: CGFloat)] = [
        (3, 0.05), (-4, -0.04), (2, 0.06), (-3, -0.06), (4, 0.01),
    ]

    private func layoutEye(
        _ eye: EyeLayers,
        side: CGFloat,                                  // -1 left, +1 right
        smile: CGFloat,
        u: CGFloat,
        c: MascotExpression,
        blink: CGFloat
    ) {
        let faceBounds = face.bounds
        eye.all.forEach { $0.frame = faceBounds }
        eye.pupilMask.frame = faceBounds

        // 1.2 scales every eye part up from the original sheet proportions.
        let size = max(0.3, c.eyeSize) * 1.2
        let sclera = clamp(c.sclera, 0, 1)
        let look = CGPoint(x: clamp(c.lookX, -1.1, 1.1), y: clamp(c.lookY, -1.1, 1.1))

        // 0 = round eye, 1 = smile arc. Squashes the eye while the arc fades in.
        let arcAmount = min(1, abs(smile) * 2.5)
        let ballAlpha = 1 - arcAmount
        let open = max(0.04, min(1.15, c.openness) * blink) * (1 - 0.55 * arcAmount)

        let center = CGPoint(
            x: u / 2 + side * (0.17 + 0.04 * sclera) * u + look.x * 0.04 * u,
            y: u / 2 + look.y * 0.04 * u
        )

        // Whites.
        let scleraWidth = 0.30 * u * size
        let scleraHeight = 0.38 * u * size * open
        eye.sclera.path = CGPath(
            ellipseIn: CGRect(x: center.x - scleraWidth / 2, y: center.y - scleraHeight / 2,
                              width: scleraWidth, height: scleraHeight),
            transform: nil
        )
        eye.sclera.opacity = Float(sclera * ballAlpha)
        eye.pupilMask.path = eye.sclera.path

        // Pupil: with no whites it is the whole eye.
        let pupilWidth = 0.15 * u * size * (1 - 0.3 * arcAmount)
        let pupilHeight = 0.29 * u * size * open * (1 - 0.3 * arcAmount)
        // With whites, a full look puts the pupil flush against the rim of the eyeball.
        // Without them the pupil is the eye, so it only nudges.
        let nudge = 0.03 * u
        let reachX = nudge + ((scleraWidth - pupilWidth) / 2 - nudge) * sclera
        let reachY = nudge + (max(0, scleraHeight - pupilHeight) / 2 - nudge) * sclera
        // Keep diagonals on the rim too, instead of overshooting into the corner.
        let lookLength = hypot(look.x, look.y)
        let pupilLook = lookLength > 1 ? CGPoint(x: look.x / lookLength, y: look.y / lookLength) : look
        let pupilCenter = CGPoint(x: center.x + pupilLook.x * reachX, y: center.y + pupilLook.y * reachY)
        eye.pupil.path = CGPath(
            ellipseIn: CGRect(x: pupilCenter.x - pupilWidth / 2, y: pupilCenter.y - pupilHeight / 2,
                              width: pupilWidth, height: pupilHeight),
            transform: nil
        )
        eye.pupil.opacity = Float(ballAlpha)

        // Smile arc: ^ when positive, u when negative.
        let arcWidth = 0.21 * u * size
        let arcHeight = 0.11 * u * size
        let arcPath = CGMutablePath()
        arcPath.move(to: CGPoint(x: center.x - arcWidth / 2, y: center.y + 0.5 * arcHeight * smile))
        arcPath.addQuadCurve(
            to: CGPoint(x: center.x + arcWidth / 2, y: center.y + 0.5 * arcHeight * smile),
            control: CGPoint(x: center.x, y: center.y - 1.5 * arcHeight * smile)
        )
        eye.arc.path = arcPath
        eye.arc.lineWidth = 0.07 * u
        eye.arc.opacity = Float(arcAmount)

        // Eyelid: a face-colored wedge that cuts the top of the eye.
        let lidFactor = 1 - arcAmount
        let eyeHeight = 0.38 * u * size
        let cutY = center.y - eyeHeight / 2 + clamp(c.lid, 0, 1) * eyeHeight * lidFactor
        let tilt = c.lidTilt * 0.12 * u * lidFactor
        let halfWidth = scleraWidth / 2 + 0.02 * u
        let lidPath = CGMutablePath()
        lidPath.move(to: CGPoint(x: center.x - halfWidth, y: cutY - tilt))
        lidPath.addLine(to: CGPoint(x: center.x + halfWidth, y: cutY + tilt))
        lidPath.addLine(to: CGPoint(x: center.x + halfWidth, y: center.y - 0.7 * u))
        lidPath.addLine(to: CGPoint(x: center.x - halfWidth, y: center.y - 0.7 * u))
        lidPath.closeSubpath()
        eye.lid.path = lidPath

        // Brow: mirrored, inner end drops when browTilt is positive (angry).
        let browHalf = 0.105 * u
        let browY = center.y - 0.22 * u * size
        let browDrop = c.browTilt * 0.065 * u
        let browPath = CGMutablePath()
        browPath.move(to: CGPoint(x: center.x - side * browHalf, y: browY + browDrop))   // inner
        browPath.addLine(to: CGPoint(x: center.x + side * browHalf, y: browY - browDrop)) // outer
        eye.brow.path = browPath
        eye.brow.lineWidth = 0.075 * u
        eye.brow.opacity = Float(min(1, abs(c.browTilt) * 4))
    }
}
