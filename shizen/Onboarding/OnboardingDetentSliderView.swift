import UIKit

/// Glass track + large pan-able knob with snapping detents.
/// Visual and haptic language follows NestNote's `HorizontalSliderView`.
final class OnboardingDetentSliderView: UIVisualEffectView {

    private static let height: CGFloat = 72
    private static let knobSize: CGFloat = 72
    private static let knobInset: CGFloat = 8
    private static let trackPadding: CGFloat = 5

    var onIndexChanged: ((Int) -> Void)?

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

    private var lastHapticProgress: Float = 0
    private var currentProgress: Float = 0
    private let hapticInterval: Float = 1.0
    private let hapticIntensity: CGFloat = 0.8

    private let dragHaptic = UIImpactFeedbackGenerator(style: .light)
    private let detentHaptic = UISelectionFeedbackGenerator()
    private let snapHaptic = UIImpactFeedbackGenerator(style: .soft)

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
        dragHaptic.prepare()
        detentHaptic.prepare()
        snapHaptic.prepare()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutTicks()
        if !didInstallInitialOffset, bounds.width > 0 {
            didInstallInitialOffset = true
            offset = offset(for: selectedIndex)
            knobLeadingConstraint.constant = offset
        }
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
            }
        } else {
            knobLeadingConstraint.constant = target
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        cornerConfiguration = .corners(radius: .fixed(Self.height / 2))

        ticksContainer.translatesAutoresizingMaskIntoConstraints = false
        ticksContainer.isUserInteractionEnabled = false
        contentView.addSubview(ticksContainer)

        knobView.backgroundColor = .white
        knobView.layer.cornerRadius = (Self.knobSize - Self.knobInset) / 2
        knobView.translatesAutoresizingMaskIntoConstraints = false

        knobContainer.translatesAutoresizingMaskIntoConstraints = false
        knobContainer.isUserInteractionEnabled = true

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
            knobView.widthAnchor.constraint(equalToConstant: Self.knobSize - Self.knobInset),
            knobView.heightAnchor.constraint(equalToConstant: Self.knobSize - Self.knobInset),
        ])

        rebuildTicks()

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        knobContainer.addGestureRecognizer(pan)
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
            resetHapticProgress()
            dragHaptic.prepare()
            detentHaptic.prepare()

        case .changed:
            let translation = gesture.translation(in: self).x
            let range = travelRange
            offset = min(range.upperBound, max(range.lowerBound, gestureStartOffset + translation))
            knobLeadingConstraint.constant = offset
            layoutIfNeeded()

            let span = range.upperBound - range.lowerBound
            currentProgress = span > 0 ? Float((offset - range.lowerBound) / span * 100) : 0
            checkForDragHaptic()

            let nearest = nearestIndex(for: offset)
            if nearest != selectedIndex {
                selectedIndex = nearest
                detentHaptic.selectionChanged()
                onIndexChanged?(nearest)
            }

        case .ended, .cancelled, .failed:
            resetHapticProgress()
            snapHaptic.impactOccurred()
            setSelectedIndex(nearestIndex(for: offset), animated: true)

        default:
            break
        }
    }

    private func checkForDragHaptic() {
        let progressDifference = abs(currentProgress - lastHapticProgress)
        guard progressDifference >= hapticInterval else { return }
        dragHaptic.impactOccurred(intensity: hapticIntensity)
        lastHapticProgress = currentProgress
    }

    private func resetHapticProgress() {
        lastHapticProgress = 0
        currentProgress = 0
    }
}
