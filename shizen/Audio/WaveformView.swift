//
//  WaveformView.swift
//  shizen
//
//  Two small waveform-style UIViews:
//
//  • `LiveWaveformView` takes a stream of RMS level values (one per
//    audio frame captured from AVAudioEngine) and draws the last N of
//    them as mirrored vertical bars that scroll left over time. Used
//    for the "live" visualizer at the top of the TTS tab.
//
//  • `StaticWaveformView` renders a fixed array of precomputed peak
//    values. Used inside each chunk table-cell to summarise that
//    chunk's shape.
//

import UIKit

/// Per-bar height scale for a symmetric diamond profile (center tallest, edges clamped).
private enum VUMeterDiamond {
    static func heightScale(barIndex: Int, barCount: Int, falloff: CGFloat) -> CGFloat {
        guard barCount > 1, falloff > 0 else { return 1 }
        let center = CGFloat(barCount - 1) / 2
        let distance = abs(CGFloat(barIndex) - center) / max(center, 1)
        return max(0.22, 1 - falloff * distance)
    }
}

/// A scrolling waveform driven by `append(level:)` calls.
///
/// Keeps a ring buffer of recent levels and redraws on a display-link
/// pulse so rendering is smooth regardless of how often levels arrive.
final class LiveWaveformView: UIView {

    private var levels: [Float]
    private var writeIndex = 0
    private var maxObservedLevel: Float = 0.001 // avoid divide-by-zero
    private var lastAppendTime: CFTimeInterval = 0
    private var displayLink: CADisplayLink?
    private var speakingLevel: Float = 0
    private var speakingGrowth: CGFloat = 0

    private let glowLayer = CAShapeLayer()
    private let barsLayer = CAShapeLayer()

    /// Multiplier applied to incoming levels before clamping to 0…1.
    var levelGain: Float = 1 {
        didSet { levelGain = max(0.1, levelGain) }
    }

    /// Exponent applied when mapping normalised level → bar height on screen.
    var displayCurve: Float = 1 {
        didSet { displayCurve = max(0.2, min(3, displayCurve)) }
    }

    /// When true, bars decay toward silence whenever levels stop arriving.
    var decaysWhenIdle: Bool = false

    /// Exponent applied to incoming levels before they enter the ring buffer.
    /// Values below 1 punch up quiet audio.
    var peakCurve: Float = 1 {
        didSet { peakCurve = max(0.2, min(3, peakCurve)) }
    }

    /// Minimum normalisation denominator so peaks can fill the view when emphatic.
    var normalizationFloor: Float = 0.05 {
        didSet { normalizationFloor = max(0.01, normalizationFloor) }
    }

    /// How quickly the auto-gain ceiling falls after loud peaks (closer to 1 = slower).
    var peakDecay: Float = 0.98 {
        didSet { peakDecay = max(0.9, min(0.999, peakDecay)) }
    }

    var barWidth: CGFloat = 3 {
        didSet {
            guard barWidth != oldValue else { return }
            barWidth = max(2, barWidth)
            setNeedsLayout()
        }
    }

    var barSpacing: CGFloat = 2 {
        didSet {
            guard barSpacing != oldValue else { return }
            barSpacing = max(1, barSpacing)
            setNeedsLayout()
        }
    }

    /// When false, bar heights use `fixedNormalization` instead of auto-gain.
    var usesAdaptiveNormalization = true

    /// Fixed ceiling for bar scaling when adaptive normalisation is off.
    var fixedNormalization: Float = 0.42 {
        didSet { fixedNormalization = max(0.05, fixedNormalization) }
    }

    /// Per-bar time stagger as a fraction of one envelope step — adds shape without leaving the envelope.
    var barTimeStagger: Float = 0 {
        didSet { barTimeStagger = max(0, min(0.45, barTimeStagger)) }
    }

    /// Boosts bar height after normalization; lower values punch harder.
    var emphasisCurve: Float = 1 {
        didSet { emphasisCurve = max(0.3, min(2.5, emphasisCurve)) }
    }

    /// Extra gain for transients (quick attacks) to create spikes.
    var spikeGain: Float = 0 {
        didSet { spikeGain = max(0, min(3, spikeGain)) }
    }

    /// Adds per-bar wobble proportional to each bar's level.
    var barSpread: Float = 0 {
        didSet { barSpread = max(0, min(0.6, barSpread)) }
    }

    var barColor: UIColor = .systemTeal {
        didSet { barsLayer.fillColor = barColor.cgColor }
    }

    /// Soft bloom behind bars — off by default.
    var showsGlow: Bool = false {
        didSet {
            glowLayer.isHidden = !showsGlow
            setNeedsDisplayInRing()
        }
    }

    var glowColor: UIColor = .white {
        didSet { setNeedsDisplayInRing() }
    }

    override init(frame: CGRect) {
        // Start with a zero-filled ring; it'll be sized for real in layout.
        self.levels = Array(repeating: 0, count: 1)
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        self.levels = Array(repeating: 0, count: 1)
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        isOpaque = false
        layer.cornerRadius = 10
        layer.masksToBounds = true

        glowLayer.fillColor = UIColor.white.cgColor
        glowLayer.isHidden = true
        glowLayer.shadowOffset = .zero
        glowLayer.shadowOpacity = 0.85
        glowLayer.shadowRadius = 10
        layer.addSublayer(glowLayer)

        barsLayer.fillColor = barColor.cgColor
        layer.addSublayer(barsLayer)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        let targetGrowth = CGFloat(max(0, min(1, (speakingLevel - 0.04) / 0.5)))
        let growthDelta = targetGrowth - speakingGrowth
        if abs(growthDelta) > 0.001 {
            let smoothing: CGFloat = growthDelta > 0 ? 0.28 : 0.09
            speakingGrowth += growthDelta * smoothing
        }

        if decaysWhenIdle {
            let now = CACurrentMediaTime()
            if now - lastAppendTime > 0.05 {
                fadeToZero(step: 0.92)
            }
        }
        setNeedsDisplayInRing()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuildBuffer()
        setNeedsDisplayInRing()
    }

    private func rebuildBuffer() {
        let spacing = barWidth + barSpacing
        let count = max(1, Int(floor(bounds.width / spacing)))
        if levels.count != count {
            levels = Array(repeating: 0, count: count)
            writeIndex = 0
        }
    }

    /// Push a new level in [0, 1]. Call this from the main thread as
    /// often as you like — we ring-buffer it for the next redraw.
    func append(level: Float) {
        guard !levels.isEmpty else { return }
        let boosted = max(0, min(1, level * levelGain))
        let curved = pow(boosted, peakCurve)
        let clamped = max(0, min(1, curved))

        lastAppendTime = CACurrentMediaTime()

        if clamped > maxObservedLevel {
            maxObservedLevel = clamped
        } else {
            maxObservedLevel = max(clamped, maxObservedLevel * peakDecay)
        }

        levels[writeIndex] = clamped
        writeIndex = (writeIndex + 1) % levels.count
    }

    /// Decays all values toward zero; call when playback is idle so the
    /// visualizer relaxes to flat rather than sticking at the last level.
    func fadeToZero(step: Float = 0.85) {
        for i in 0..<levels.count {
            levels[i] *= step
        }
        maxObservedLevel *= step
    }

    func reset() {
        for i in 0..<levels.count {
            levels[i] = 0
        }
        writeIndex = 0
        maxObservedLevel = 0.001
        speakingLevel = 0
        speakingGrowth = 0
        setNeedsDisplayInRing()
    }

    /// Pushes a live speaking level to drive growth/widening behavior.
    func setSpeakingLevel(_ level: Float) {
        speakingLevel = max(0, min(1, level))
    }

    /// Fills the bar window from a pre-analyzed envelope aligned to `playbackTime`.
    /// The rightmost bar is always "now" in the audio.
    func displayEnvelope(_ envelope: PlaybackEnvelope, at playbackTime: TimeInterval) {
        guard !levels.isEmpty else { return }

        let norm = max(envelope.peak, normalizationFloor)
        let count = levels.count
        writeIndex = 0

        var localPeak: Float = 0
        for index in 0..<count {
            let age = Double(count - 1 - index) * envelope.interval
            let stagger = Double(sin(Float(index) * 1.21 + Float(count) * 0.07)) * envelope.interval * Double(barTimeStagger)
            let sampleTime = playbackTime - age + stagger
            let raw = envelope.level(at: sampleTime)
            let prevRaw = envelope.level(at: sampleTime - envelope.interval)
            let transient = max(0, raw - prevRaw * 0.92)
            var boosted = max(0, min(1, raw * levelGain + transient * spikeGain))
            boosted = pow(boosted, peakCurve)
            if barSpread > 0, boosted > 0.02 {
                let wobble = sin(Float(index) * 1.63 + Float(sampleTime) * 8.5) * barSpread
                boosted = max(0, min(1, boosted * (1 + wobble)))
            }
            let emphasized = pow(boosted, emphasisCurve)
            levels[index] = emphasized
            localPeak = max(localPeak, emphasized)
        }

        maxObservedLevel = max(norm, localPeak)
        lastAppendTime = CACurrentMediaTime()
    }

    private func setNeedsDisplayInRing() {
        guard bounds.width > 0, bounds.height > 0, !levels.isEmpty else { return }
        let path = UIBezierPath()

        let midY = bounds.height / 2
        let maxHalf = bounds.height / 2 - 2
        let widthScale = 1 + speakingGrowth * 0.35
        let heightScale = 1 + speakingGrowth * 0.28
        let drawnBarWidth = min(barWidth * widthScale, max(2, bounds.width / CGFloat(max(levels.count, 1)) - barSpacing))
        let spacing = drawnBarWidth + barSpacing
        let norm: Float
        if usesAdaptiveNormalization {
            norm = max(maxObservedLevel, normalizationFloor)
        } else {
            norm = fixedNormalization
        }

        for i in 0..<levels.count {
            // Read oldest -> newest: start at writeIndex (the slot we'd
            // write to next, which is therefore the oldest value).
            let idx = (writeIndex + i) % levels.count
            var raw = levels[idx] / norm
            if barSpread > 0 {
                let wobble = sin(Float(i) * 1.37 + Float(idx) * 0.61) * barSpread
                raw = max(0, min(1, raw + wobble * raw))
            }
            let value = CGFloat(pow(raw, displayCurve))
            let minHeight = decaysWhenIdle ? drawnBarWidth : 2
            let emphasisBoost = 1 + value * 0.18 + speakingGrowth * 0.12
            let h = min(maxHalf, max(minHeight, value * maxHalf * heightScale * emphasisBoost))
            let x = CGFloat(i) * spacing + 1
            let rect = CGRect(x: x, y: midY - h, width: drawnBarWidth, height: h * 2)
            let rounded = UIBezierPath(roundedRect: rect, cornerRadius: drawnBarWidth / 2)
            path.append(rounded)
        }

        barsLayer.frame = bounds
        barsLayer.path = path.cgPath

        if showsGlow {
            glowLayer.frame = bounds
            glowLayer.path = path.cgPath
            glowLayer.shadowColor = glowColor.cgColor
            glowLayer.shadowRadius = 6 + CGFloat(maxObservedLevel) * 10
        }
    }
}

/// Five fixed-width bars whose heights track recent audio levels.
///
/// Near silence the bars rest at minimum height with a subtle breathing
/// animation; they grow once audio activity arrives.
final class AudioLevelBarsView: UIView {

    private let barCount = 5

    /// Per-bar history offsets and wobble phase — stagger keeps motion alive while
    /// the diamond profile shapes the overall silhouette.
    private let barHistoryOffsets = [0, 2, 1, 4, 2]
    private let barGain: [CGFloat] = [0.88, 0.94, 1.0, 0.94, 0.88]
    private let barWobblePhase: [CGFloat] = [0, 1.7, 3.1, 4.8, 2.3]
    private let barWobbleSpeed: [CGFloat] = [2.2, 2.8, 3.4, 2.5, 2.0]

    private var levelHistory: [Float] = []
    private let levelHistoryCapacity = 12

    private var targetLevels: [CGFloat]
    private var displayedLevels: [CGFloat]
    private var animationTime: CGFloat = 0
    private var displayLink: CADisplayLink?

    var barWidth: CGFloat = 6 {
        didSet {
            barWidth = max(2, barWidth)
            guard barWidth != oldValue else { return }
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    var barSpacing: CGFloat = 10 {
        didSet {
            barSpacing = max(1, barSpacing)
            guard barSpacing != oldValue else { return }
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    /// How tall the meter draws inside its bounds.
    var meterHeight: CGFloat = 48 {
        didSet {
            meterHeight = max(12, meterHeight)
            guard meterHeight != oldValue else { return }
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    /// Minimum bar height at rest / during quiet audio.
    var minBarHeight: CGFloat = 6 {
        didSet {
            minBarHeight = max(2, minBarHeight)
            setNeedsDisplay()
        }
    }

    /// Fraction of `meterHeight` loud audio can reach.
    var heightFill: CGFloat = 1 {
        didSet {
            heightFill = max(0.15, min(1, heightFill))
            setNeedsDisplay()
        }
    }

    /// Multiplier on incoming RMS before distributing across bars.
    var levelGain: Float = 1 {
        didSet { levelGain = max(0.1, min(4, levelGain)) }
    }

    /// Exponent applied when mapping level → bar height. Below 1 punches up quiet audio.
    var displayCurve: Float = 1 {
        didSet { displayCurve = max(0.2, min(3, displayCurve)) }
    }

    /// How quickly bars chase their targets (higher = snappier).
    var smoothing: CGFloat = 0.31 {
        didSet { smoothing = max(0.05, min(0.85, smoothing)) }
    }

    /// Live wobble amplitude while speaking.
    var wobbleAmount: CGFloat = 0.07 {
        didSet { wobbleAmount = max(0, min(0.35, wobbleAmount)) }
    }

    /// How much outer bars are clamped vs. the center (0 = flat, 1 = strong diamond).
    var diamondFalloff: CGFloat = 0.48 {
        didSet {
            diamondFalloff = max(0, min(1, diamondFalloff))
            setNeedsDisplay()
        }
    }

    var barColor: UIColor = UIColor(red: 0.45, green: 0.78, blue: 0.98, alpha: 1) {
        didSet { setNeedsDisplay() }
    }

    private(set) var isIdle = true

    override init(frame: CGRect) {
        targetLevels = Array(repeating: 0, count: barCount)
        displayedLevels = Array(repeating: 0, count: barCount)
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        targetLevels = Array(repeating: 0, count: barCount)
        displayedLevels = Array(repeating: 0, count: barCount)
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
    }

    override var intrinsicContentSize: CGSize {
        let width = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        return CGSize(width: width, height: meterHeight)
    }

    /// Push a new RMS level in [0, 1].
    func setLevel(_ level: Float) {
        let boosted = max(0, min(1, level * levelGain))
        let wasIdle = isIdle

        levelHistory.append(boosted)
        if levelHistory.count > levelHistoryCapacity {
            levelHistory.removeFirst(levelHistory.count - levelHistoryCapacity)
        }

        for i in 0..<barCount {
            let offset = min(barHistoryOffsets[i], max(0, levelHistory.count - 1))
            let sampleIndex = levelHistory.count - 1 - offset
            let sample = CGFloat(levelHistory[sampleIndex])
            targetLevels[i] = sample * barGain[i]
        }

        isIdle = boosted < 0.012
        if isIdle != wasIdle || !isIdle {
            setNeedsDisplay()
        }
    }

    /// Decays all bar targets toward silence.
    func fadeToMinimum() {
        let wasIdle = isIdle
        targetLevels = targetLevels.map { $0 * 0.82 }
        isIdle = (targetLevels.max() ?? 0) < 0.012
        if isIdle != wasIdle {
            setNeedsDisplay()
        }
    }

    func reset() {
        targetLevels = Array(repeating: 0, count: barCount)
        displayedLevels = Array(repeating: 0, count: barCount)
        levelHistory.removeAll(keepingCapacity: true)
        animationTime = 0
        isIdle = true
        setNeedsDisplay()
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        animationTime += CGFloat(link.duration > 0 ? link.duration : 1.0 / 60.0)

        var changed = false
        for i in 0..<barCount {
            var target = targetLevels[i]
            if isIdle {
                // Gentle idle breathing so the dots feel alive between turns.
                let breathe = sin(animationTime * 1.6 + barWobblePhase[i]) * 0.5 + 0.5
                target = breathe * 0.018
            } else if target > 0.02 {
                let wobble = sin(animationTime * barWobbleSpeed[i] + barWobblePhase[i])
                target += wobble * wobbleAmount * target
            }

            let delta = target - displayedLevels[i]
            if abs(delta) > 0.001 {
                displayedLevels[i] += delta * smoothing
                changed = true
            }
        }
        if changed || isIdle {
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        var x = (rect.width - totalWidth) / 2
        let centerY = rect.midY

        ctx.setFillColor(barColor.cgColor)
        let drawableHeight = min(rect.height, meterHeight)
        let maxBarHeight = max(minBarHeight, drawableHeight * heightFill - 2)

        for (index, level) in displayedLevels.enumerated() {
            let normalized = max(0, min(1, level))
            let curved = pow(normalized, CGFloat(displayCurve))
            let eased = curved * curved * (3 - 2 * curved)
            let diamondScale = VUMeterDiamond.heightScale(
                barIndex: index,
                barCount: barCount,
                falloff: diamondFalloff
            )
            let barHeight = minBarHeight + eased * (maxBarHeight - minBarHeight) * diamondScale
            let barRect = CGRect(
                x: x,
                y: centerY - barHeight / 2,
                width: barWidth,
                height: barHeight
            )
            let path = UIBezierPath(roundedRect: barRect, cornerRadius: barWidth / 2)
            ctx.addPath(path.cgPath)
            ctx.fillPath()
            x += barWidth + barSpacing
        }
    }
}

/// Five bars driven by clip envelope timing plus live level — reads more
/// like speech rhythm than a raw volume meter.
final class SpeechEnvelopeBarsView: UIView {

    private let barCount = 5
    private let lookbackOffsets: [TimeInterval] = [0.11, 0.055, 0, 0, 0]
    private let barWobblePhase: [CGFloat] = [0, 1.4, 2.8, 4.1, 5.5]
    private let barWobbleSpeed: [CGFloat] = [1.9, 2.4, 3.0, 3.6, 2.7]

    private var targetLevels: [CGFloat]
    private var displayedLevels: [CGFloat]
    private var animationTime: CGFloat = 0
    private var displayLink: CADisplayLink?
    private var isSettlingToRest = false
    private var settleCompletionHandler: (() -> Void)?

    var barWidth: CGFloat = 6 {
        didSet {
            barWidth = max(2, barWidth)
            guard barWidth != oldValue else { return }
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    var barSpacing: CGFloat = 10 {
        didSet {
            barSpacing = max(1, barSpacing)
            guard barSpacing != oldValue else { return }
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    var meterHeight: CGFloat = 48 {
        didSet {
            meterHeight = max(12, meterHeight)
            guard meterHeight != oldValue else { return }
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    var minBarHeight: CGFloat = 6 {
        didSet {
            minBarHeight = max(2, minBarHeight)
            setNeedsDisplay()
        }
    }

    var heightFill: CGFloat = 1 {
        didSet {
            heightFill = max(0.15, min(1, heightFill))
            setNeedsDisplay()
        }
    }

    /// Gain on envelope samples (bars 0–2).
    var envelopeGain: Float = 1.25 {
        didSet { envelopeGain = max(0.1, min(4, envelopeGain)) }
    }

    /// Gain on the live tap (bar 3).
    var liveGain: Float = 1.1 {
        didSet { liveGain = max(0.1, min(4, liveGain)) }
    }

    /// Gain on attack transients (bar 4).
    var attackGain: Float = 1.6 {
        didSet { attackGain = max(0, min(4, attackGain)) }
    }

    var displayCurve: Float = 0.68 {
        didSet { displayCurve = max(0.2, min(3, displayCurve)) }
    }

    var smoothing: CGFloat = 0.38 {
        didSet { smoothing = max(0.05, min(0.85, smoothing)) }
    }

    /// Slower smoothing while bars fall back to rest after audio stops.
    var decaySmoothing: CGFloat = 0.14 {
        didSet { decaySmoothing = max(0.05, min(0.5, decaySmoothing)) }
    }

    var wobbleAmount: CGFloat = 0.05 {
        didSet { wobbleAmount = max(0, min(0.35, wobbleAmount)) }
    }

    /// How much outer bars are clamped vs. the center (0 = flat, 1 = strong diamond).
    var diamondFalloff: CGFloat = 0.48 {
        didSet {
            diamondFalloff = max(0, min(1, diamondFalloff))
            setNeedsDisplay()
        }
    }

    var barColor: UIColor = .systemTeal {
        didSet { setNeedsDisplay() }
    }

    private(set) var isIdle = true

    override init(frame: CGRect) {
        targetLevels = Array(repeating: 0, count: barCount)
        displayedLevels = Array(repeating: 0, count: barCount)
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        targetLevels = Array(repeating: 0, count: barCount)
        displayedLevels = Array(repeating: 0, count: barCount)
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
    }

    override var intrinsicContentSize: CGSize {
        let width = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        return CGSize(width: width, height: meterHeight)
    }

    /// Updates targets from pre-analyzed envelope + live tap.
    func setPlayback(envelope: PlaybackEnvelope, at time: TimeInterval, liveLevel: Float) {
        let envNow = envelope.level(at: time)
        let envPrev = envelope.level(at: max(0, time - 0.045))
        let attack = max(0, liveLevel - envPrev * 0.88)
        let speaking = max(envNow, liveLevel)

        targetLevels[0] = CGFloat(envelope.level(at: max(0, time - lookbackOffsets[0])) * envelopeGain)
        targetLevels[1] = CGFloat(envelope.level(at: max(0, time - lookbackOffsets[1])) * envelopeGain)
        targetLevels[2] = CGFloat(envNow * envelopeGain)
        targetLevels[3] = CGFloat(liveLevel * liveGain)
        targetLevels[4] = CGFloat(attack * attackGain)

        let wasIdle = isIdle
        isIdle = speaking < 0.015
        if isIdle, !wasIdle {
            beginSettlingToRest()
        }
        if isIdle != wasIdle || !isIdle {
            setNeedsDisplay()
        }
    }

    /// Drops audio targets to zero but keeps displayed bar heights so they can ease down.
    func releaseToRest(completion: (() -> Void)? = nil) {
        settleCompletionHandler = completion
        targetLevels = Array(repeating: 0, count: barCount)
        isIdle = true
        beginSettlingToRest()
        notifySettleIfNeeded()
    }

    func reset() {
        settleCompletionHandler = nil
        targetLevels = Array(repeating: 0, count: barCount)
        displayedLevels = Array(repeating: 0, count: barCount)
        animationTime = 0
        isIdle = true
        isSettlingToRest = false
        setNeedsDisplay()
    }

    private func beginSettlingToRest() {
        isSettlingToRest = (displayedLevels.max() ?? 0) > 0.015
    }

    private func notifySettleIfNeeded() {
        guard settleCompletionHandler != nil, isIdle, !isSettlingToRest else { return }
        let handler = settleCompletionHandler
        settleCompletionHandler = nil
        handler?()
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        animationTime += CGFloat(link.duration > 0 ? link.duration : 1.0 / 60.0)

        var changed = false
        for i in 0..<barCount {
            var target = targetLevels[i]
            if isIdle {
                if isSettlingToRest {
                    let peak = displayedLevels.max() ?? 0
                    if peak > 0.015 {
                        target = 0
                    } else {
                        if isSettlingToRest {
                            isSettlingToRest = false
                            notifySettleIfNeeded()
                        }
                        let breathe = sin(animationTime * 1.5 + barWobblePhase[i]) * 0.5 + 0.5
                        target = breathe * 0.016
                    }
                } else {
                    let breathe = sin(animationTime * 1.5 + barWobblePhase[i]) * 0.5 + 0.5
                    target = breathe * 0.016
                }
            } else if target > 0.02 {
                let wobble = sin(animationTime * barWobbleSpeed[i] + barWobblePhase[i])
                target += wobble * wobbleAmount * target
            }

            let delta = target - displayedLevels[i]
            if abs(delta) > 0.001 {
                let rate = delta > 0 ? smoothing : decaySmoothing
                displayedLevels[i] += delta * rate
                changed = true
            }
        }
        if changed || isIdle {
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        var x = (rect.width - totalWidth) / 2
        let centerY = rect.midY

        ctx.setFillColor(barColor.cgColor)
        let drawableHeight = min(rect.height, meterHeight)
        let maxBarHeight = max(minBarHeight, drawableHeight * heightFill - 2)

        for (index, level) in displayedLevels.enumerated() {
            let normalized = max(0, min(1, level))
            let curved = pow(normalized, CGFloat(displayCurve))
            let eased = curved * curved * (3 - 2 * curved)
            let diamondScale = VUMeterDiamond.heightScale(
                barIndex: index,
                barCount: barCount,
                falloff: diamondFalloff
            )
            let barHeight = minBarHeight + eased * (maxBarHeight - minBarHeight) * diamondScale
            let barRect = CGRect(
                x: x,
                y: centerY - barHeight / 2,
                width: barWidth,
                height: barHeight
            )
            let path = UIBezierPath(roundedRect: barRect, cornerRadius: barWidth / 2)
            ctx.addPath(path.cgPath)
            ctx.fillPath()
            x += barWidth + barSpacing
        }
    }
}

/// Renders a fixed array of peak values as mirrored bars. Used inside
/// each chunks-table row.
final class StaticWaveformView: UIView {

    var peaks: [Float] = [] {
        didSet { setNeedsDisplay() }
    }
    var barColor: UIColor = .systemTeal {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), !peaks.isEmpty else { return }
        ctx.setFillColor(barColor.cgColor)

        let barSpacing: CGFloat = 1
        let totalSpacing = barSpacing * CGFloat(peaks.count - 1)
        let barWidth = max(1, (rect.width - totalSpacing) / CGFloat(peaks.count))

        let midY = rect.height / 2
        let maxHalf = rect.height / 2 - 1

        // Normalise against the local max so tiny chunks are still visible.
        let localMax = max(peaks.max() ?? 0, 0.05)

        for (i, peak) in peaks.enumerated() {
            let value = CGFloat(peak) / CGFloat(localMax)
            let h = max(1, value * maxHalf)
            let x = CGFloat(i) * (barWidth + barSpacing)
            let barRect = CGRect(x: x, y: midY - h, width: barWidth, height: h * 2)
            let path = UIBezierPath(roundedRect: barRect, cornerRadius: min(barWidth / 2, 1.5))
            ctx.addPath(path.cgPath)
            ctx.fillPath()
        }
    }
}
