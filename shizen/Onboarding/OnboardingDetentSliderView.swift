import UIKit

/// Glass track + large pan-able knob with snapping detents.
final class OnboardingDetentSliderView: UIVisualEffectView {

    private static let height: CGFloat = 72
    private static let thumbInset: CGFloat = 8
    private static let knobSize: CGFloat = height - thumbInset * 2
    private static let trackPadding: CGFloat = thumbInset

    var onIndexChanged: ((Int) -> Void)?
    /// Fires when a drag ends, with the detent the knob settles on.
    var onRelease: ((Int) -> Void)?
    /// Fires whenever the knob moves (drag, snap, or initial placement). Read `knobCenterInWindow()`.
    var onKnobMoved: (() -> Void)?

    /// Optional label inside the track (e.g. "Slide to promise"); fades as the knob travels.
    var trackTitle: String? {
        didSet {
            trackTitleLabel.text = trackTitle
            trackTitleLabel.isHidden = trackTitle == nil
        }
    }
    private let trackTitleLabel = UILabel()

    /// Hide the detent ticks, e.g. for a two-position slide-to-confirm.
    var showsTicks = true {
        didSet { ticksContainer.isHidden = !showsTicks }
    }

    /// Slide-to-confirm feel: ticks come closer together and hit harder as the knob nears the end,
    /// in place of the detent bump.
    var rampsHaptics = false

    private(set) var selectedIndex = 0
    private var detentCount = 2

    private let ticksContainer = UIView()
    private var tickViews: [UIView] = []

    private let knobContainer = UIView()
    private let knobView = UIView()

    private var knobLeadingConstraint: NSLayoutConstraint!
    private var didInstallInitialOffset = false

    private var gestureStartOffset: CGFloat = 0
    private var offset: CGFloat = 0

    private let detentHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let rampHaptic = UIImpactFeedbackGenerator(style: .medium)
    /// Where the last ramp tick fired; the next fires once the knob has moved the current spacing.
    private var lastRampTickOffset: CGFloat = 0
    private static let rampSpacing: ClosedRange<CGFloat> = 5...30
    private static let rampIntensity: ClosedRange<CGFloat> = 0.2...1

    init(detentCount: Int, selectedIndex: Int = 0) {
        let glassEffect = UIGlassEffect(style: .regular)
        glassEffect.isInteractive = true
        glassEffect.tintColor = UIColor.systemGray3.withAlphaComponent(0.4)
        super.init(effect: glassEffect)
        self.detentCount = max(detentCount, 2)
        self.selectedIndex = min(max(selectedIndex, 0), self.detentCount - 1)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        detentHaptic.prepare()
        if rampsHaptics { rampHaptic.prepare() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutTicks()
        if !didInstallInitialOffset, bounds.width > 0 {
            didInstallInitialOffset = true
            offset = offset(for: selectedIndex)
            knobLeadingConstraint.constant = offset
            onKnobMoved?()
        }
    }

    func knobCenterInWindow() -> CGPoint? {
        guard let window else { return nil }
        return knobContainer.convert(
            CGPoint(x: knobContainer.bounds.midX, y: knobContainer.bounds.midY),
            to: window
        )
    }

    func setSelectedIndex(_ index: Int, animated: Bool) {
        let clamped = min(max(index, 0), detentCount - 1)
        selectedIndex = clamped
        let target = offset(for: clamped)
        offset = target
        guard didInstallInitialOffset else { return }
        if animated {
            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                usingSpringWithDamping: 0.82,
                initialSpringVelocity: 0.4,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                self.knobLeadingConstraint.constant = target
                self.layoutIfNeeded()
                self.updateTrackTitleFade()
            }
        } else {
            knobLeadingConstraint.constant = target
        }
        onKnobMoved?()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        cornerConfiguration = .corners(radius: .fixed(Self.height / 2))

        ticksContainer.translatesAutoresizingMaskIntoConstraints = false
        ticksContainer.isUserInteractionEnabled = false
        contentView.addSubview(ticksContainer)

        knobView.backgroundColor = .secondarySystemBackground
        knobView.layer.cornerRadius = Self.knobSize / 2
        knobView.translatesAutoresizingMaskIntoConstraints = false

        knobContainer.translatesAutoresizingMaskIntoConstraints = false
        knobContainer.isUserInteractionEnabled = true

        trackTitleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        trackTitleLabel.textColor = .secondaryLabel
        trackTitleLabel.textAlignment = .center
        trackTitleLabel.adjustsFontSizeToFitWidth = true
        trackTitleLabel.minimumScaleFactor = 0.8
        trackTitleLabel.isHidden = true
        trackTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(trackTitleLabel)
        NSLayoutConstraint.activate([
            trackTitleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            trackTitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.knobSize + 16),
            trackTitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
        ])

        contentView.addSubview(knobContainer)
        knobContainer.addSubview(knobView)

        knobLeadingConstraint = knobContainer.leadingAnchor.constraint(
            equalTo: contentView.leadingAnchor,
            constant: Self.trackPadding
        )

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),

            ticksContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            ticksContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            ticksContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            ticksContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            knobContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            knobContainer.widthAnchor.constraint(equalToConstant: Self.knobSize),
            knobContainer.heightAnchor.constraint(equalToConstant: Self.knobSize),
            knobLeadingConstraint,

            knobView.centerXAnchor.constraint(equalTo: knobContainer.centerXAnchor),
            knobView.centerYAnchor.constraint(equalTo: knobContainer.centerYAnchor),
            knobView.widthAnchor.constraint(equalToConstant: Self.knobSize),
            knobView.heightAnchor.constraint(equalToConstant: Self.knobSize),
        ])

        rebuildTicks()

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        knobContainer.addGestureRecognizer(pan)

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: OnboardingDetentSliderView, _) in
            view.knobView.backgroundColor = .secondarySystemBackground
        }
    }

    /// Stops the knob from moving, e.g. once a commitment slide has landed.
    func lock() {
        knobContainer.isUserInteractionEnabled = false
    }

    private func updateTrackTitleFade() {
        trackTitleLabel.alpha = max(0, 1 - progress(at: knobLeadingConstraint.constant) * 1.6)
    }

    /// 0 at the start of the track, 1 at the end.
    private func progress(at offset: CGFloat) -> CGFloat {
        let range = travelRange
        let span = range.upperBound - range.lowerBound
        return span > 0 ? (offset - range.lowerBound) / span : 0
    }

    private func playRampTickIfDue() {
        let t = min(1, max(0, progress(at: offset)))
        let spacing = Self.rampSpacing.upperBound - (Self.rampSpacing.upperBound - Self.rampSpacing.lowerBound) * t
        guard abs(offset - lastRampTickOffset) >= spacing else { return }
        lastRampTickOffset = offset
        let intensity = Self.rampIntensity.lowerBound + (Self.rampIntensity.upperBound - Self.rampIntensity.lowerBound) * t * t
        rampHaptic.impactOccurred(intensity: intensity)
        rampHaptic.prepare()
    }

    private func rebuildTicks() {
        tickViews.forEach { $0.removeFromSuperview() }
        tickViews = (0..<detentCount).map { _ in
            let tick = UIView()
            tick.backgroundColor = UIColor.label.withAlphaComponent(0.18)
            tick.layer.cornerRadius = 1.5
            ticksContainer.addSubview(tick)
            return tick
        }
        setNeedsLayout()
    }

    private func layoutTicks() {
        let travel = travelRange
        guard travel.upperBound > travel.lowerBound else { return }
        let tickWidth: CGFloat = 3
        let tickHeight: CGFloat = 10
        for (index, tick) in tickViews.enumerated() {
            let centerX = offset(for: index) + Self.knobSize / 2
            tick.frame = CGRect(
                x: centerX - tickWidth / 2,
                y: (bounds.height - tickHeight) / 2,
                width: tickWidth,
                height: tickHeight
            )
        }
    }

    private var travelRange: ClosedRange<CGFloat> {
        let start = Self.trackPadding
        let end = max(start, bounds.width - Self.knobSize - Self.trackPadding)
        return start...end
    }

    private func offset(for index: Int) -> CGFloat {
        let range = travelRange
        guard detentCount > 1 else { return range.lowerBound }
        let t = CGFloat(index) / CGFloat(detentCount - 1)
        return range.lowerBound + (range.upperBound - range.lowerBound) * t
    }

    private func nearestIndex(for offset: CGFloat) -> Int {
        guard detentCount > 1 else { return 0 }
        let range = travelRange
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        let progress = (offset - range.lowerBound) / span
        return min(detentCount - 1, max(0, Int((progress * CGFloat(detentCount - 1)).rounded())))
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            gestureStartOffset = offset
            lastRampTickOffset = offset
            detentHaptic.prepare()
            if rampsHaptics { rampHaptic.prepare() }

        case .changed:
            let translation = gesture.translation(in: self).x
            let range = travelRange
            offset = min(range.upperBound, max(range.lowerBound, gestureStartOffset + translation))
            knobLeadingConstraint.constant = offset
            layoutIfNeeded()
            updateTrackTitleFade()
            onKnobMoved?()
            if rampsHaptics { playRampTickIfDue() }

            let nearest = nearestIndex(for: offset)
            if nearest != selectedIndex {
                selectedIndex = nearest
                if !rampsHaptics {
                    detentHaptic.impactOccurred(intensity: 0.85)
                    detentHaptic.prepare()
                }
                onIndexChanged?(nearest)
            }

        case .ended, .cancelled, .failed:
            let settled = nearestIndex(for: offset)
            setSelectedIndex(settled, animated: true)
            onRelease?(settled)

        default:
            break
        }
    }
}
