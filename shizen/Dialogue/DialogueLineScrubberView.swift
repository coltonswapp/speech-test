//
//  DialogueLineScrubberView.swift
//  shizen
//
//  Clip progress for text-hidden listening. At rest it's a quiet monochrome
//  capsule with a small thumb and hairline notches where the speaker changes;
//  touching it swells the track and thumb and tints the line under the finger
//  with its speaker.
//  Dragging snaps to line starts — the useful seek is "hear that line again".
//

import UIKit

final class DialogueLineScrubberView: UIControl {

    struct Segment: Equatable {
        let start: TimeInterval
        let end: TimeInterval
        let speaker: String
        let color: UIColor
    }

    /// Fires on release with the spoken-line index the learner landed on.
    var onSelectLine: ((Int) -> Void)?

    private(set) var segments: [Segment] = []
    private var duration: TimeInterval = 0
    private var currentTime: TimeInterval = 0
    /// Line the fill is snapped to while dragging; `nil` when not scrubbing.
    private var scrubLineIndex: Int?
    /// Track times where the speaker changes; drawn as notches.
    private var speakerChangeTimes: [TimeInterval] = []

    /// 0 = resting thin track, 1 = swollen while touched. Eased per frame.
    private var expansion: CGFloat = 0
    private var expansionTarget: CGFloat = 0
    private var expansionLink: CADisplayLink?

    private let elapsedLabel = UILabel()
    private let remainingLabel = UILabel()
    private let selectionFeedback = UISelectionFeedbackGenerator()

    private static let restingTrackHeight: CGFloat = 6
    private static let expandedTrackHeight: CGFloat = 16
    private static let notchWidth: CGFloat = 2
    private static let restingThumbDiameter: CGFloat = 18
    private static let expandedThumbDiameter: CGFloat = 28
    /// Track ends sit in by the largest thumb radius so it never clips.
    private static let trackInset: CGFloat = expandedThumbDiameter / 2
    private static let trackCenterY: CGFloat = expandedThumbDiameter / 2
    private static let labelTopSpacing: CGFloat = 7
    private static let expansionSeconds: CGFloat = 0.09

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw

        for label in [elapsedLabel, remainingLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabel
            addSubview(label)
        }
        remainingLabel.textAlignment = .right

        NSLayoutConstraint.activate([
            elapsedLabel.topAnchor.constraint(
                equalTo: topAnchor,
                constant: Self.expandedThumbDiameter + Self.labelTopSpacing
            ),
            elapsedLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.trackInset),
            elapsedLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            remainingLabel.firstBaselineAnchor.constraint(equalTo: elapsedLabel.firstBaselineAnchor),
            remainingLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.trackInset),
        ])

        isAccessibilityElement = true
        accessibilityLabel = "Dialogue progress"
        accessibilityTraits = .adjustable
        updateTimeLabels()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopExpansionLink()
        }
    }

    func configure(segments: [Segment], duration: TimeInterval) {
        guard segments != self.segments || duration != self.duration else { return }
        self.segments = segments
        self.duration = duration
        speakerChangeTimes = zip(segments, segments.dropFirst())
            .filter { $0.speaker != $1.speaker }
            .map { $1.start }
        updateTimeLabels()
        setNeedsDisplay()
    }

    func setCurrentTime(_ time: TimeInterval) {
        let clamped = max(0, min(duration, time))
        guard abs(clamped - currentTime) > 0.001 else { return }
        currentTime = clamped
        guard scrubLineIndex == nil else { return }
        updateTimeLabels()
        setNeedsDisplay()
    }

    // MARK: - Geometry

    private var trackWidth: CGFloat {
        max(0, bounds.width - Self.trackInset * 2)
    }

    private func x(for time: TimeInterval) -> CGFloat {
        guard duration > 0 else { return Self.trackInset }
        return Self.trackInset + trackWidth * CGFloat(max(0, min(1, time / duration)))
    }

    private func time(for x: CGFloat) -> TimeInterval {
        guard trackWidth > 0 else { return 0 }
        return duration * TimeInterval(max(0, min(1, (x - Self.trackInset) / trackWidth)))
    }

    /// The line whose stretch holds `time`; in a silent gap, the line before it.
    private func lineIndex(at time: TimeInterval) -> Int? {
        guard !segments.isEmpty else { return nil }
        return segments.lastIndex(where: { $0.start <= time }) ?? 0
    }

    private var displayedTime: TimeInterval {
        if let scrubLineIndex, segments.indices.contains(scrubLineIndex) {
            return segments[scrubLineIndex].start
        }
        return currentTime
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), duration > 0, trackWidth > 0 else { return }

        let height = Self.restingTrackHeight
            + (Self.expandedTrackHeight - Self.restingTrackHeight) * expansion
        let trackRect = CGRect(
            x: Self.trackInset,
            y: Self.trackCenterY - height / 2,
            width: trackWidth,
            height: height
        )
        let trackPath = UIBezierPath(roundedRect: trackRect, cornerRadius: height / 2)

        ctx.saveGState()
        // Notches cut through the whole track via even-odd clipping.
        let clip = UIBezierPath(rect: bounds)
        for time in speakerChangeTimes {
            clip.append(UIBezierPath(rect: CGRect(
                x: x(for: time) - Self.notchWidth / 2,
                y: trackRect.minY - 1,
                width: Self.notchWidth,
                height: trackRect.height + 2
            )))
        }
        clip.usesEvenOddFillRule = true
        clip.addClip()

        UIColor.label.withAlphaComponent(0.14).setFill()
        trackPath.fill()

        // The line under the finger takes its speaker's tint.
        if let scrubLineIndex, segments.indices.contains(scrubLineIndex) {
            let segment = segments[scrubLineIndex]
            let x0 = x(for: segment.start)
            let x1 = x(for: segment.end)
            ctx.saveGState()
            ctx.clip(to: CGRect(x: x0, y: trackRect.minY, width: max(0, x1 - x0), height: trackRect.height))
            segment.color.withAlphaComponent(0.55).setFill()
            trackPath.fill()
            ctx.restoreGState()
        }

        let playheadX = x(for: displayedTime)
        if playheadX > trackRect.minX {
            ctx.saveGState()
            ctx.clip(to: CGRect(
                x: trackRect.minX,
                y: trackRect.minY,
                width: playheadX - trackRect.minX,
                height: trackRect.height
            ))
            UIColor.label.withAlphaComponent(0.8).setFill()
            trackPath.fill()
            ctx.restoreGState()
        }
        ctx.restoreGState()

        // Thumb sits outside the notch clip so a notch never bites into it.
        let diameter = Self.restingThumbDiameter
            + (Self.expandedThumbDiameter - Self.restingThumbDiameter) * expansion
        let thumbRect = CGRect(
            x: playheadX - diameter / 2,
            y: Self.trackCenterY - diameter / 2,
            width: diameter,
            height: diameter
        )
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: 1),
            blur: 3,
            color: UIColor.black.withAlphaComponent(0.25).cgColor
        )
        UIColor.white.setFill()
        UIBezierPath(ovalIn: thumbRect).fill()
        ctx.restoreGState()
        UIColor.separator.setStroke()
        let ring = UIBezierPath(ovalIn: thumbRect.insetBy(dx: 0.25, dy: 0.25))
        ring.lineWidth = 0.5
        ring.stroke()
    }

    private func updateTimeLabels() {
        let shown = displayedTime
        elapsedLabel.text = Self.format(shown)
        remainingLabel.text = "-" + Self.format(max(0, duration - shown), roundingUp: true)
        accessibilityValue = segments.isEmpty
            ? nil
            : "Line \((lineIndex(at: shown) ?? 0) + 1) of \(segments.count), \(Self.format(shown)) of \(Self.format(duration))"
    }

    private static func format(_ time: TimeInterval, roundingUp: Bool = false) -> String {
        let seconds = Int(roundingUp ? time.rounded(.up) : time.rounded(.down))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Expansion

    private func setExpanded(_ expanded: Bool) {
        expansionTarget = expanded ? 1 : 0
        guard expansionLink == nil, abs(expansionTarget - expansion) > 0.001 else { return }
        let link = CADisplayLink(target: self, selector: #selector(stepExpansion))
        link.add(to: .main, forMode: .common)
        expansionLink = link
    }

    @objc private func stepExpansion(_ link: CADisplayLink) {
        let dt = CGFloat(link.duration > 0 ? link.duration : 1.0 / 60.0)
        let alpha = 1 - exp(-dt / Self.expansionSeconds)
        expansion += (expansionTarget - expansion) * alpha
        if abs(expansionTarget - expansion) < 0.005 {
            expansion = expansionTarget
            stopExpansionLink()
        }
        setNeedsDisplay()
    }

    private func stopExpansionLink() {
        expansionLink?.invalidate()
        expansionLink = nil
    }

    // MARK: - Tracking

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard !segments.isEmpty, duration > 0 else { return false }
        selectionFeedback.prepare()
        scrubLineIndex = lineIndex(at: time(for: touch.location(in: self).x))
        setExpanded(true)
        updateTimeLabels()
        setNeedsDisplay()
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let index = lineIndex(at: time(for: touch.location(in: self).x))
        if index != scrubLineIndex {
            scrubLineIndex = index
            selectionFeedback.selectionChanged()
            selectionFeedback.prepare()
            updateTimeLabels()
            setNeedsDisplay()
        }
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        let landed = scrubLineIndex
        finishScrubbing()
        if let landed {
            // Show the line start until playback ticks catch up.
            currentTime = segments[landed].start
            updateTimeLabels()
            onSelectLine?(landed)
        }
    }

    override func cancelTracking(with event: UIEvent?) {
        finishScrubbing()
    }

    private func finishScrubbing() {
        scrubLineIndex = nil
        setExpanded(false)
        updateTimeLabels()
        setNeedsDisplay()
    }

    /// Generous hit area so a thin track is easy to grab.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -8, dy: -14).contains(point)
    }

    override var intrinsicContentSize: CGSize {
        let labelHeight = elapsedLabel.font.lineHeight.rounded(.up)
        return CGSize(
            width: UIView.noIntrinsicMetric,
            height: Self.expandedThumbDiameter + Self.labelTopSpacing + labelHeight
        )
    }

    // MARK: - Accessibility

    override func accessibilityIncrement() {
        stepLine(by: 1)
    }

    override func accessibilityDecrement() {
        stepLine(by: -1)
    }

    private func stepLine(by delta: Int) {
        guard let current = lineIndex(at: currentTime) else { return }
        let target = current + delta
        guard segments.indices.contains(target) else { return }
        currentTime = segments[target].start
        updateTimeLabels()
        setNeedsDisplay()
        onSelectLine?(target)
    }
}
