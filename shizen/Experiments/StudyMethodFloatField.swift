//
//  StudyMethodFloatField.swift
//  shizen
//
//  First onboarding stage: study-method capsules at mixed depths.
//  On-screen capsules pop in one by one, then the field drifts.
//  Farther capsules are smaller and blurred. On drop, on-screen
//  capsules fall under gravity.
//

import UIKit

struct StudyMethodFieldTuning: Equatable {
    var size: CGFloat = 1.15
    var depth: CGFloat = 0.06
    var blur: CGFloat = 3.7
    var hapticStrength: Float = 1.00
    var flowSpeed: CGFloat = 0.016
    var gravity: CGFloat = 3.0
    var gravityStagger: CGFloat = 0.50
    var rotation: CGFloat = 7.6
    var count: Int = 120
    var glow: CGFloat = 1.01
    /// Minimum fraction of a pill still on screen for it to fall. Lower keeps slivers in the drop.
    var dropCutoff: CGFloat = 0.05
    /// One haptic when the drop starts, instead of a tap for every other pill.
    var singleHaptic: Bool = true
    /// Drift downward instead of upward.
    var flowReversed: Bool = true
    /// Seconds between the first pops. Later pops arrive faster.
    var popGap: CGFloat = 0.06
    /// How many times faster the last pops are than the first. The rate multiplies along the way.
    var popRamp: CGFloat = 9.2
    /// Spring frequency. Higher snaps to size sooner.
    var popSpring: CGFloat = 23.7
    /// Damping ratio. Lower overshoots and bounces; 1 settles without bounce.
    var popDamping: CGFloat = 0.50
    /// Scale at the moment a pill appears, before the spring carries it to 1.
    var popFrom: CGFloat = 0.10
    /// Opening pops drawn from the middle of the screen, so the first taps aren't offstage.
    var popCenterCount: Int = 24

    var sourceText: String {
        """
        StudyMethodFieldTuning(
            size: \(Self.decimal(size, places: 2)),
            depth: \(Self.decimal(depth, places: 2)),
            blur: \(Self.decimal(blur, places: 1)),
            hapticStrength: \(Self.decimal(hapticStrength, places: 2)),
            flowSpeed: \(Self.decimal(flowSpeed, places: 3)),
            gravity: \(Self.decimal(gravity, places: 1)),
            gravityStagger: \(Self.decimal(gravityStagger, places: 2)),
            rotation: \(Self.decimal(rotation, places: 1)),
            count: \(count),
            glow: \(Self.decimal(glow, places: 2)),
            dropCutoff: \(Self.decimal(dropCutoff, places: 2)),
            singleHaptic: \(singleHaptic),
            flowReversed: \(flowReversed),
            popGap: \(Self.decimal(popGap, places: 2)),
            popRamp: \(Self.decimal(popRamp, places: 1)),
            popSpring: \(Self.decimal(popSpring, places: 1)),
            popDamping: \(Self.decimal(popDamping, places: 2)),
            popFrom: \(Self.decimal(popFrom, places: 2)),
            popCenterCount: \(popCenterCount)
        )
        """
    }

    private static func decimal(_ value: some BinaryFloatingPoint, places: Int) -> String {
        String(format: "%.\(places)f", Double(value))
    }
}

final class StudyMethodFloatField: UIView {

    private struct Floater {
        let view: StudyMethodBubbleView
        let centerX: NSLayoutConstraint
        let centerY: NSLayoutConstraint
        var unitX: CGFloat
        var unitY: CGFloat
        let homeX: CGFloat
        let homeY: CGFloat
        let depth: CGFloat
        var scale: CGFloat
        /// -1...1, multiplied by the tuning rotation in degrees.
        let rotationUnit: CGFloat
        var rotation: CGFloat
        var velocityY: CGFloat
        var fallDelay: CGFloat
        var gravityActive: Bool
        var playsFallHaptic: Bool
        var retired: Bool
        var tiltTarget: CGFloat
        var tiltProgress: CGFloat
        var spawned: Bool
        var popScale: CGFloat
        var popVelocity: CGFloat
    }

    private enum Motion {
        case floating
        case falling
    }

    private final class TickProxy: NSObject {
        weak var field: StudyMethodFloatField?
        @objc func tick(_ link: CADisplayLink) {
            field?.tick(link)
        }
    }

    private var floaters: [Floater] = []
    private var displayLink: CADisplayLink?
    private let tickProxy = TickProxy()
    private var isPositioning = false
    private var motion: Motion = .floating
    private var motionGeneration = 0
    private var fallCompletion: (() -> Void)?
    private var fallElapsed: CGFloat = 0
    private let fallHaptic = UIImpactFeedbackGenerator(style: .light)
    private let popHaptic = UIImpactFeedbackGenerator(style: .soft)
    private(set) var tuning = StudyMethodFieldTuning()
    private var introPending = false
    private var introActive = false
    private var spawnQueue: [Int] = []
    private var spawnElapsed: CGFloat = 0
    private var nextSpawnAt: CGFloat = 0
    private var spawnedCount = 0
    /// Pills this far on screen join the one-by-one pop. The rest wait offstage for the drift.
    private static let entranceVisibleFraction: CGFloat = 0.08
    /// Fastest gap. Low enough that an exponential ramp can rush, still one pop at a time.
    private static let minimumPopGap: CGFloat = 0.008
    /// How many pops a single frame may release when the ramp is ahead of the display.
    private static let maxSpawnsPerFrame = 6
    /// How far, in points, a pill starts above its rest before the spring lands it.
    private static let popLift: CGFloat = 12
    /// Centers live on this loop, including a strip above and below the screen, so wrapping never opens a hole.
    private static let loopMin: CGFloat = -0.24
    /// Extra tilt, in radians, added in the pill's existing lean once gravity starts.
    private static let gravityTilt: CGFloat = 2.5 * .pi / 180
    private static let gravityTiltDuration: CGFloat = 0.45
    /// Quiet moment after the last pill leaves before the drop is considered finished.
    private static let settlePause: TimeInterval = 0.4
    private static let loopSpan: CGFloat = 1.48
    private static let ciContext = CIContext()

    override init(frame: CGRect) {
        super.init(frame: frame)
        tickProxy.field = self
        isUserInteractionEnabled = false
        clipsToBounds = false
        backgroundColor = .clear
        accessibilityElementsHidden = true
        buildFloaters()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
    }

    func prepareSnapshotsIfNeeded() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        applyPositions()
    }

    func apply(_ tuning: StudyMethodFieldTuning) {
        let previous = self.tuning
        self.tuning = tuning
        let structural = previous.count != tuning.count
            || abs(previous.blur - tuning.blur) > 0.05
            || abs(previous.depth - tuning.depth) > 0.01
        if structural {
            rebuildFloaters()
            return
        }
        for index in floaters.indices {
            floaters[index].scale = scale(for: floaters[index].depth)
            floaters[index].rotation = floaters[index].rotationUnit * tuning.rotation * .pi / 180
            floaters[index].view.setGlowStrength(tuning.glow)
        }
        applyPositions()
    }

    /// Starts the entrance if the field was stopped. A live field is left alone.
    func resumeFloatingIfNeeded() {
        guard displayLink == nil else { return }
        startFloating()
    }

    /// Pops on-screen pills in one by one, then drifts. Replaying restarts the entrance.
    func startFloating() {
        motionGeneration += 1
        fallCompletion = nil
        motion = .floating
        introActive = false
        spawnQueue = []
        for index in floaters.indices {
            floaters[index].unitX = floaters[index].homeX
            floaters[index].unitY = floaters[index].homeY
            floaters[index].velocityY = 0
            floaters[index].fallDelay = 0
            floaters[index].gravityActive = false
            floaters[index].playsFallHaptic = false
            floaters[index].retired = false
            floaters[index].tiltTarget = 0
            floaters[index].tiltProgress = 0
            floaters[index].spawned = false
            floaters[index].popScale = 0
            floaters[index].popVelocity = 0
            floaters[index].view.setGlowVisible(false, animated: false)
        }
        fallElapsed = 0
        if bounds.height > 1 {
            beginIntro()
        } else {
            introPending = true
        }
        applyPositions()
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: tickProxy, selector: #selector(TickProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Visible pills lose the float and drop straight down. Slivers already off screen just disappear.
    func dropUnderGravity(completion: @escaping () -> Void) {
        if motion == .falling {
            let pending = fallCompletion
            fallCompletion = {
                pending?()
                completion()
            }
            return
        }
        motionGeneration += 1
        let generation = motionGeneration
        motion = .falling
        introActive = false
        introPending = false
        spawnQueue = []
        fallCompletion = { [weak self] in
            guard let self, generation == self.motionGeneration else { return }
            completion()
        }

        let height = bounds.height
        var falling: [Int] = []
        for index in floaters.indices {
            floaters[index].gravityActive = false
            floaters[index].playsFallHaptic = false
            floaters[index].velocityY = 0
            if !floaters[index].spawned || height <= 1 || isBarelyOffscreen(floaters[index], height: height) {
                floaters[index].retired = true
                floaters[index].fallDelay = 0
            } else {
                floaters[index].popScale = 1
                floaters[index].popVelocity = 0
                falling.append(index)
            }
        }
        var rng = SplitMix64(state: UInt64(CACurrentMediaTime() * 1000))
        for slot in stride(from: falling.count - 1, through: 1, by: -1) {
            let swap = Int(rng.next() % UInt64(slot + 1))
            falling.swapAt(slot, swap)
        }
        for (step, index) in falling.enumerated() {
            let spread = falling.count <= 1 ? 0 : tuning.gravityStagger * CGFloat(step) / CGFloat(falling.count - 1)
            floaters[index].fallDelay = spread
            floaters[index].playsFallHaptic = !tuning.singleHaptic && step.isMultiple(of: 2)
        }
        fallElapsed = 0
        if !falling.isEmpty, tuning.hapticStrength > 0.02 {
            fallHaptic.prepare()
            if tuning.singleHaptic {
                fallHaptic.impactOccurred(intensity: min(1, CGFloat(tuning.hapticStrength)))
            }
        }
        applyPositions()
        guard !falling.isEmpty else {
            finishFall()
            return
        }
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: tickProxy, selector: #selector(TickProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopFloating() {
        displayLink?.invalidate()
        displayLink = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if introPending, bounds.height > 1 {
            beginIntro()
        }
        applyPositions()
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let dt = CGFloat(min(link.targetTimestamp - link.timestamp, 1.0 / 30.0))
        guard bounds.height > 0 else { return }
        switch motion {
        case .floating:
            if introPending, bounds.height > 1 {
                beginIntro()
            }
            if introActive {
                tickSpawn(dt)
            } else if !introPending {
                for index in floaters.indices {
                    advanceFlow(index, dt: dt)
                }
            }
            for index in floaters.indices {
                stepPop(index, dt: dt)
            }
            applyPositions()
        case .falling:
            tickFalling(dt)
        }
    }

    private func tickFalling(_ dt: CGFloat) {
        fallElapsed += dt
        let height = bounds.height
        var stillFalling = false
        for index in floaters.indices where !floaters[index].retired {
            if !floaters[index].gravityActive {
                if fallElapsed >= floaters[index].fallDelay {
                    floaters[index].gravityActive = true
                    floaters[index].velocityY = 0
                    let lean: CGFloat = floaters[index].rotationUnit < 0 ? -1 : 1
                    floaters[index].tiltTarget = lean * Self.gravityTilt
                    floaters[index].view.setGlowVisible(true, animated: true)
                    if floaters[index].playsFallHaptic, tuning.hapticStrength > 0.02 {
                        fallHaptic.impactOccurred(intensity: min(1, CGFloat(tuning.hapticStrength)))
                        fallHaptic.prepare()
                    }
                } else {
                    advanceFlow(index, dt: dt)
                    stillFalling = true
                    continue
                }
            }
            floaters[index].velocityY += tuning.gravity * dt
            floaters[index].unitY += floaters[index].velocityY * dt
            floaters[index].tiltProgress = min(1, floaters[index].tiltProgress + dt / Self.gravityTiltDuration)
            let top = floaters[index].unitY * height - pillHalfHeight(floaters[index])
            if top > height {
                floaters[index].retired = true
            } else {
                stillFalling = true
            }
        }
        applyPositions()
        if !stillFalling {
            finishFall()
        }
    }

    private func finishFall() {
        guard motion == .falling else { return }
        stopFloating()
        motion = .floating
        let generation = motionGeneration
        let done = fallCompletion
        fallCompletion = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settlePause) { [weak self] in
            guard let self, generation == self.motionGeneration else { return }
            done?()
        }
    }

    private func applyPositions() {
        let width = bounds.width
        let height = bounds.height
        guard width > 1, height > 1, !isPositioning else { return }
        isPositioning = true
        defer { isPositioning = false }

        for index in floaters.indices {
            let floater = floaters[index]
            floater.view.transform = .identity
            let lift = floater.spawned ? (1 - floater.popScale) * Self.popLift : 0
            floater.centerX.constant = floater.unitX * width - width / 2
            floater.centerY.constant = floater.unitY * height - height / 2 - lift
        }
        layoutIfNeeded()

        for floater in floaters {
            if floater.retired || !floater.spawned {
                floater.view.alpha = 0
                continue
            }
            let remaining = 1 - floater.tiltProgress
            let tilt = floater.tiltTarget * (1 - remaining * remaining)
            let pop = min(1.35, max(0, floater.popScale))
            floater.view.transform = CGAffineTransform(rotationAngle: floater.rotation + tilt)
                .scaledBy(x: floater.scale * pop, y: floater.scale * pop)
            floater.view.setPassageBlur(0)
            floater.view.alpha = min(1, max(0, (pop - 0.08) / 0.42))
        }
    }

    private func advanceFlow(_ index: Int, dt: CGFloat) {
        let direction: CGFloat = tuning.flowReversed ? 1 : -1
        floaters[index].unitY += tuning.flowSpeed * dt * direction
        let loopMax = Self.loopMin + Self.loopSpan
        if tuning.flowReversed {
            if floaters[index].unitY >= loopMax {
                floaters[index].unitY -= Self.loopSpan
            }
        } else if floaters[index].unitY < Self.loopMin {
            floaters[index].unitY += Self.loopSpan
        }
    }

    private func pillHalfHeight(_ floater: Floater) -> CGFloat {
        let height = floater.view.bounds.height > 1 ? floater.view.bounds.height : floater.view.preferredSize.height
        return height * floater.scale / 2
    }

    private func isBarelyOffscreen(_ floater: Floater, height: CGFloat) -> Bool {
        let half = pillHalfHeight(floater)
        let center = floater.unitY * height
        let visible = max(0, min(center + half, height) - max(center - half, 0))
        return visible / max(half * 2, 1) < tuning.dropCutoff
    }

    private func blurRadius(for depth: CGFloat) -> CGFloat {
        (1 - presentedDepth(depth)) * tuning.blur
    }

    private func presentedDepth(_ raw: CGFloat) -> CGFloat {
        let anchor: CGFloat = 0.66
        return min(1, max(0, anchor + (raw - anchor) * tuning.depth))
    }

    private func scale(for depth: CGFloat) -> CGFloat {
        (0.79 + presentedDepth(depth) * 0.26) * tuning.size
    }

    private func beginIntro() {
        introPending = false
        var onStage: [Int] = []
        for index in floaters.indices {
            floaters[index].popVelocity = 0
            if isOnStage(floaters[index]) {
                floaters[index].spawned = false
                floaters[index].popScale = 0
                onStage.append(index)
            } else {
                floaters[index].spawned = true
                floaters[index].popScale = 1
            }
        }
        var rng = SplitMix64(state: UInt64(CACurrentMediaTime() * 1000) | 1)
        spawnQueue = scatteredRevealOrder(onStage, rng: &rng)
        spawnElapsed = 0
        spawnedCount = 0
        nextSpawnAt = max(0.04, tuning.popGap * 0.35)
        introActive = !spawnQueue.isEmpty
        if introActive, tuning.hapticStrength > 0.02 {
            popHaptic.prepare()
        }
    }

    /// Gaps shrink exponentially: each step multiplies the rate, so the field starts sparse and then rushes.
    private func tickSpawn(_ dt: CGFloat) {
        spawnElapsed += dt
        var spawnedThisFrame = 0
        while spawnElapsed >= nextSpawnAt, !spawnQueue.isEmpty, spawnedThisFrame < Self.maxSpawnsPerFrame {
            let index = spawnQueue.removeFirst()
            let total = spawnedCount + 1 + spawnQueue.count
            let progress = total <= 1 ? 1 : CGFloat(spawnedCount) / CGFloat(total - 1)
            spawn(index, progress: progress)
            spawnedCount += 1
            spawnedThisFrame += 1
            guard !spawnQueue.isEmpty else {
                introActive = false
                return
            }
            let placed = spawnedCount + spawnQueue.count
            let along = CGFloat(spawnedCount) / CGFloat(max(placed - 1, 1))
            let speed = pow(max(tuning.popRamp, 1), along)
            nextSpawnAt = spawnElapsed + max(Self.minimumPopGap, tuning.popGap / speed)
        }
        if spawnQueue.isEmpty {
            introActive = false
        }
    }

    private func spawn(_ index: Int, progress: CGFloat) {
        let from = min(0.92, max(0.02, tuning.popFrom))
        floaters[index].spawned = true
        floaters[index].popScale = from
        floaters[index].popVelocity = (1 - from) * max(tuning.popSpring, 1) * 0.45
        guard tuning.hapticStrength > 0.02, playsPopHaptic(index) else { return }
        let depthBoost = 0.6 + 0.4 * floaters[index].depth
        let rampBoost = 0.75 + 0.25 * progress
        let intensity = min(1, CGFloat(tuning.hapticStrength) * depthBoost * rampBoost)
        popHaptic.impactOccurred(intensity: intensity)
        popHaptic.prepare()
    }

    private func stepPop(_ index: Int, dt: CGFloat) {
        guard floaters[index].spawned else { return }
        if floaters[index].popVelocity == 0, abs(floaters[index].popScale - 1) < 0.001 { return }
        let omega = max(1, tuning.popSpring)
        let zeta = min(1.15, max(0.2, tuning.popDamping))
        let step = min(dt, 0.25 / omega)
        var scale = floaters[index].popScale
        var velocity = floaters[index].popVelocity
        var remaining = dt
        while remaining > 0 {
            let h = min(step, remaining)
            let acceleration = -omega * omega * (scale - 1) - 2 * zeta * omega * velocity
            velocity += acceleration * h
            scale += velocity * h
            remaining -= h
        }
        if abs(scale - 1) < 0.004, abs(velocity) < 0.02 {
            scale = 1
            velocity = 0
        }
        floaters[index].popScale = min(1.35, max(0, scale))
        floaters[index].popVelocity = velocity
    }

    private func isOnStage(_ floater: Floater) -> Bool {
        visibleFraction(floater) >= Self.entranceVisibleFraction
    }

    /// Share of the pill's area that sits inside the screen.
    private func visibleFraction(_ floater: Floater) -> CGFloat {
        let width = bounds.width
        let height = bounds.height
        guard width > 1, height > 1 else { return 0 }
        let halfW = pillHalfWidth(floater)
        let halfH = pillHalfHeight(floater)
        let centerX = floater.unitX * width
        let centerY = floater.unitY * height
        let visibleW = max(0, min(centerX + halfW, width) - max(centerX - halfW, 0))
        let visibleH = max(0, min(centerY + halfH, height) - max(centerY - halfH, 0))
        return (visibleW / max(halfW * 2, 1)) * (visibleH / max(halfH * 2, 1))
    }

    private func pillHalfWidth(_ floater: Floater) -> CGFloat {
        let width = floater.view.bounds.width > 1 ? floater.view.bounds.width : floater.view.preferredSize.width
        return width * floater.scale / 2
    }

    /// Opening pops: mostly on screen, and in the open middle under the title.
    private func isInCenterBand(_ index: Int) -> Bool {
        let floater = floaters[index]
        guard visibleFraction(floater) >= 0.72 else { return false }
        return floater.unitX >= 0.14 && floater.unitX <= 0.86
            && floater.unitY >= 0.32 && floater.unitY <= 0.80
    }

    /// Skip taps for pills tucked under the title, past the bottom chrome, or mostly off the glass.
    private func playsPopHaptic(_ index: Int) -> Bool {
        let floater = floaters[index]
        guard visibleFraction(floater) >= 0.7 else { return false }
        return floater.unitX >= 0.08 && floater.unitX <= 0.92
            && floater.unitY >= 0.28 && floater.unitY <= 0.88
    }

    /// The first pops are scattered through the middle. Later pops fill the rest of the field.
    private func scatteredRevealOrder(_ indices: [Int], rng: inout SplitMix64) -> [Int] {
        var remaining = indices
        guard !remaining.isEmpty else { return [] }
        var center = remaining.filter { isInCenterBand($0) }
        var order: [Int] = []
        var last: Int?
        let lead = max(0, tuning.popCenterCount)
        while order.count < lead, !center.isEmpty {
            let pick = nextScatterPick(from: center, last: last, preferCenter: last == nil, rng: &rng)
            center.removeAll { $0 == pick }
            remaining.removeAll { $0 == pick }
            order.append(pick)
            last = pick
        }
        while !remaining.isEmpty {
            let pick = nextScatterPick(from: remaining, last: last, preferCenter: false, rng: &rng)
            remaining.removeAll { $0 == pick }
            order.append(pick)
            last = pick
        }
        return order
    }

    private func nextScatterPick(
        from pool: [Int],
        last: Int?,
        preferCenter: Bool,
        rng: inout SplitMix64
    ) -> Int {
        if preferCenter || last == nil {
            var nearest = pool
            nearest.sort { centerDistance($0) < centerDistance($1) }
            let poolCount = max(1, nearest.count / 3)
            return nearest[Int(rng.next() % UInt64(poolCount))]
        }
        guard let last, pool.count > 1 else {
            return pool[0]
        }
        var farthest = pool
        farthest.sort { separation($0, last) > separation($1, last) }
        let poolCount = max(1, farthest.count / 3)
        return farthest[Int(rng.next() % UInt64(poolCount))]
    }

    /// Distance from the open middle of the canvas, a bit below center so the title doesn't cover it.
    private func centerDistance(_ index: Int) -> CGFloat {
        let dx = floaters[index].unitX - 0.5
        let dy = floaters[index].unitY - 0.56
        return dx * dx + dy * dy
    }

    private func separation(_ lhs: Int, _ rhs: Int) -> CGFloat {
        let dx = floaters[lhs].unitX - floaters[rhs].unitX
        let dy = floaters[lhs].unitY - floaters[rhs].unitY
        return dx * dx + dy * dy
    }

    private func rebuildFloaters() {
        stopFloating()
        motion = .floating
        fallCompletion = nil
        for floater in floaters {
            floater.view.removeFromSuperview()
        }
        floaters = []
        buildFloaters()
        for floater in floaters {
            floater.view.setGlowStrength(tuning.glow)
        }
        startFloating()
    }

    private func buildFloaters() {
        let methods = StudyMethodCatalog.items(count: tuning.count)
        var rng = SplitMix64(state: 0xC0FFEE)
        var unitYs: [CGFloat] = (0..<methods.count).map { index in
            let slot = (CGFloat(index) + CGFloat.random(in: 0.25...0.75, using: &rng)) / CGFloat(methods.count)
            return Self.loopMin + Self.loopSpan * slot
        }
        unitYs.shuffle(using: &rng)
        var anchors: [CGPoint] = []
        var placed: [Floater] = []

        for index in 0..<methods.count {
            let method = methods[index]
            let unit = CGPoint(x: scatteredX(at: unitYs[index], existing: anchors, rng: &rng), y: unitYs[index])
            anchors.append(unit)

            let depth = depthValue(slot: (index + 1) % 3, rng: &rng)
            let scale = scale(for: depth)
            let rotationUnit = CGFloat.random(in: -1...1, using: &rng)
            let rotation = rotationUnit * tuning.rotation * .pi / 180
            let bubble = StudyMethodBubbleView(title: method.title, emoji: method.emoji, glow: method.glow)
            bubble.setDepth(depth)
            let depthBlur = blurRadius(for: depth)
            bubble.installDistanceBlurIfNeeded(radius: depthBlur)
            bubble.preparePassageBlur(radius: depthBlur + 16)
            bubble.translatesAutoresizingMaskIntoConstraints = false
            addSubview(bubble)

            let size = bubble.preferredSize
            let centerX = bubble.centerXAnchor.constraint(equalTo: centerXAnchor)
            let centerY = bubble.centerYAnchor.constraint(equalTo: centerYAnchor)
            NSLayoutConstraint.activate([
                centerX,
                centerY,
                bubble.widthAnchor.constraint(equalToConstant: size.width),
                bubble.heightAnchor.constraint(equalToConstant: size.height),
            ])
            placed.append(Floater(
                view: bubble,
                centerX: centerX,
                centerY: centerY,
                unitX: unit.x,
                unitY: unit.y,
                homeX: unit.x,
                homeY: unit.y,
                depth: depth,
                scale: scale,
                rotationUnit: rotationUnit,
                rotation: rotation,
                velocityY: 0,
                fallDelay: 0,
                gravityActive: false,
                playsFallHaptic: false,
                retired: false,
                tiltTarget: 0,
                tiltProgress: 0,
                spawned: false,
                popScale: 0,
                popVelocity: 0
            ))
        }

        placed.sort { $0.depth < $1.depth }
        for floater in placed {
            bringSubviewToFront(floater.view)
        }
        floaters = placed
    }

    private func scatteredX(at unitY: CGFloat, existing: [CGPoint], rng: inout SplitMix64) -> CGFloat {
        var best: CGFloat = 0.5
        var bestDistance: CGFloat = -1
        for _ in 0..<40 {
            let x = CGFloat.random(in: -0.02...1.02, using: &rng)
            let nearest = existing.map { hypot($0.x - x, $0.y - unitY) }.min() ?? 1
            if nearest > bestDistance {
                best = x
                bestDistance = nearest
            }
            if nearest > 0.14 { return x }
        }
        return best
    }

    private func depthValue(slot: Int, rng: inout SplitMix64) -> CGFloat {
        switch slot {
        case 0: return CGFloat.random(in: 0.08...0.34, using: &rng)
        case 1: return CGFloat.random(in: 0.4...0.66, using: &rng)
        default: return CGFloat.random(in: 0.72...1, using: &rng)
        }
    }

    static func blurredImage(_ source: UIImage, radius: CGFloat) -> UIImage? {
        guard radius >= 0.5, let sourceImage = CIImage(image: source) else { return source }
        let blurred = sourceImage
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(radius))
            .cropped(to: sourceImage.extent)
        guard let cgImage = ciContext.createCGImage(blurred, from: sourceImage.extent) else { return source }
        return solidBlurredImage(cgImage, scale: source.scale) ?? UIImage(cgImage: cgImage, scale: source.scale, orientation: .up)
    }

    /// Blur mixes the white capsule with clear pixels and turns the body translucent. Lift alpha so the fill stays solid.
    private static func solidBlurredImage(_ image: CGImage, scale: CGFloat) -> UIImage? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        for index in stride(from: 0, to: data.count, by: 4) {
            let alpha = Int(data[index + 3])
            guard alpha > 8 else { continue }
            let boosted = min(255, alpha * 2)
            data[index] = UInt8(min(255, Int(data[index]) * boosted / alpha))
            data[index + 1] = UInt8(min(255, Int(data[index + 1]) * boosted / alpha))
            data[index + 2] = UInt8(min(255, Int(data[index + 2]) * boosted / alpha))
            data[index + 3] = UInt8(boosted)
        }
        guard let solid = context.makeImage() else { return nil }
        return UIImage(cgImage: solid, scale: scale, orientation: .up)
    }
}

private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

private enum StudyMethodCatalog {
    struct Item {
        let title: String
        let emoji: String
        let glow: UIColor
    }

    private static let prototypes: [(String, String)] = [
        ("Learning Streaks", "☄️"),
        ("Kana Drills", "🌲"),
        ("Textbooks", "📚"),
        ("\"Just watch anime...\"", "👺"),
        ("Anki Decks", "📦"),
        ("Grammar Lists", "📝"),
        ("\"I got fluent in 2 weeks\"", "🤡"),
        ("Flashcards", "🗂️"),
        ("YouTube", "▶️"),
        ("Podcasts", "🎧"),
        ("WaniKani", "🦀"),
        ("Genki", "📗"),
        ("JLPT Drills", "✏️"),
        ("Shadowing", "🗣️"),
        ("Phrase books", "📕"),
        ("Spreadsheets", "📊"),
        ("Sticky notes", "🗒️"),
        ("Discord servers", "💬"),
        ("Tutor hour", "🧑‍🏫"),
        ("Duolingo", "🦉"),
    ]

    private static let glows: [UIColor] = [
        UIColor(red: 1, green: 0.23, blue: 0.19, alpha: 1),
        UIColor(red: 1, green: 0.45, blue: 0.08, alpha: 1),
        .black,
    ]

    static func items(count: Int) -> [Item] {
        (0..<count).map { index in
            let prototype = prototypes[index % prototypes.count]
            return Item(title: prototype.0, emoji: prototype.1, glow: glows[index % glows.count])
        }
    }
}

private final class StudyMethodBubbleView: UIView {

    private static let font = UIFont.systemFont(ofSize: 22, weight: .semibold)
    private static let horizontalPadding: CGFloat = 20
    private static let verticalPadding: CGFloat = 14

    private static let liftShadowOpacity: Float = 0.22
    private static let liftShadowRadius: CGFloat = 8

    private let titleText: String
    private let titleLabel = UILabel()
    private var distanceImageView: UIImageView?
    private let passageImageView = UIImageView()
    private let glowColor: CGColor
    private let glowOpacity: Float
    private var glowStrength: CGFloat = 1
    private var glowShown = false
    private var depth: CGFloat = 0

    let preferredSize: CGSize

    init(title: String, emoji: String, glow: UIColor) {
        titleText = "\(title)  \(emoji)"
        let textSize = (titleText as NSString).size(withAttributes: [.font: Self.font])
        preferredSize = CGSize(
            width: ceil(textSize.width) + Self.horizontalPadding * 2,
            height: ceil(textSize.height) + Self.verticalPadding * 2
        )
        glowColor = glow.cgColor
        glowOpacity = glow == .black ? 0.34 : 0.5
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        clipsToBounds = false
        backgroundColor = .secondarySystemBackground
        layer.masksToBounds = false
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = Self.liftShadowOpacity
        layer.shadowRadius = Self.liftShadowRadius
        layer.shadowOffset = CGSize(width: 0, height: 4)

        titleLabel.text = titleText
        titleLabel.font = Self.font
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        passageImageView.alpha = 0
        passageImageView.contentMode = .scaleToFill
        passageImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        addSubview(passageImageView)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalPadding),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalPadding),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalPadding),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalPadding),

            passageImageView.topAnchor.constraint(equalTo: topAnchor),
            passageImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            passageImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            passageImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func preparePassageBlur(radius: CGFloat) {
        let sharp = renderSharpPill()
        passageImageView.image = StudyMethodFloatField.blurredImage(sharp, radius: max(radius, 8)) ?? sharp
    }

    func setPassageBlur(_ amount: CGFloat) {
        let clamped = min(1, max(0, amount))
        passageImageView.alpha = clamped
        let contentAlpha = 1 - clamped
        titleLabel.alpha = contentAlpha
        distanceImageView?.alpha = contentAlpha
        if distanceImageView == nil {
            backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(contentAlpha)
        }
    }

    func setDepth(_ depth: CGFloat) {
        self.depth = depth
        updateStackBorder()
    }

    func setGlowStrength(_ strength: CGFloat) {
        glowStrength = strength
        setGlowVisible(glowShown, animated: false)
    }

    func setGlowVisible(_ visible: Bool, animated: Bool) {
        glowShown = visible
        let base: Float = visible ? glowOpacity : Self.liftShadowOpacity
        let opacity = min(1, base * Float(glowStrength))
        let radius: CGFloat = visible ? 18 : Self.liftShadowRadius
        let color = visible ? glowColor : UIColor.black.cgColor
        let offset = visible ? CGSize(width: 0, height: 7) : CGSize(width: 0, height: 4)
        guard animated else {
            layer.removeAnimation(forKey: "shadowOpacity")
            layer.removeAnimation(forKey: "shadowRadius")
            layer.removeAnimation(forKey: "shadowColor")
            layer.removeAnimation(forKey: "shadowOffset")
            layer.shadowOpacity = opacity
            layer.shadowRadius = radius
            layer.shadowColor = color
            layer.shadowOffset = offset
            return
        }
        animateShadow("shadowOpacity", from: layer.presentation()?.shadowOpacity ?? layer.shadowOpacity, to: opacity)
        animateShadow("shadowRadius", from: layer.presentation()?.shadowRadius ?? layer.shadowRadius, to: radius)
        animateShadow("shadowColor", from: layer.presentation()?.shadowColor ?? layer.shadowColor, to: color)
        let presentedOffset = layer.presentation()?.shadowOffset ?? layer.shadowOffset
        animateShadow("shadowOffset", from: NSValue(cgSize: presentedOffset), to: NSValue(cgSize: offset))
        layer.shadowOpacity = opacity
        layer.shadowRadius = radius
        layer.shadowColor = color
        layer.shadowOffset = offset
    }

    private func animateShadow(_ keyPath: String, from: Any?, to: Any) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = 0.28
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: keyPath)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func installDistanceBlurIfNeeded(radius: CGFloat) {
        guard radius >= 3.5 else { return }
        let image = StudyMethodFloatField.blurredImage(renderSharpPill(), radius: radius) ?? renderSharpPill()
        titleLabel.removeFromSuperview()
        backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleToFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(imageView, belowSubview: passageImageView)
        distanceImageView = imageView
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func renderSharpPill() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(size: preferredSize, format: format)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: preferredSize)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
            UIColor.secondarySystemBackground.resolvedColor(with: traitCollection).setFill()
            path.fill()

            let text = titleText as NSString
            let textSize = text.size(withAttributes: [.font: Self.font])
            let textRect = CGRect(
                x: (rect.width - textSize.width) / 2,
                y: (rect.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: [
                .font: Self.font,
                .foregroundColor: UIColor.label.resolvedColor(with: traitCollection),
            ])
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.height > 1 else { return }
        let radius = bounds.height / 2
        layer.cornerRadius = radius
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateStackBorder()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle else { return }
        updateStackBorder()
    }

    /// Near capsules need an edge in dark mode, where the fill matches the pills stacked behind them.
    private func updateStackBorder() {
        let front = depth >= 0.7 && traitCollection.userInterfaceStyle == .dark
        layer.borderWidth = front ? 1 : 0
        layer.borderColor = front ? UIColor.white.withAlphaComponent(0.32).cgColor : nil
    }
}
