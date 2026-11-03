//
//  ListenFirstSquashViews.swift
//  shizen
//
//  Views for "Textbooks vs. real life": a glass bubble whose textbook line squashes into
//  what people actually say (dropped sounds fly off, changed ones swap in), and bars that
//  time each version live while it plays.
//

import InteractionKit
import NNKit
import UIKit

/// The color of anything that changed in speech.
enum ListenFirstSquashPalette {
    static let real = UIColor { $0.userInterfaceStyle == .dark ? .systemYellow : .systemOrange }
}

// MARK: - Bubble

/// A glass bubble showing a line piece by piece. `squash` turns the textbook line into the
/// real one in place; `reset` puts the textbook line back.
final class ListenFirstSquashBubble: UIView {

    private let squash: ListenFirstSquash
    private let glass = LiquidGlassEffectView.makeContainer()
    private let row = UIStackView()
    private var labels: [UILabel] = []
    private(set) var isSquashed = false

    init(squash: ListenFirstSquash, fontSize: CGFloat) {
        self.squash = squash
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false

        LiquidGlassEffectView.applyBubbleStyle(to: glass, cornerRadius: 22)
        glass.isUserInteractionEnabled = false
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)

        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 0
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        labels = squash.pieces.map { _ in
            let label = UILabel()
            label.font = .systemFont(ofSize: fontSize, weight: .semibold)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            row.addArrangedSubview(label)
            return label
        }

        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),

            row.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
        ])

        isAccessibilityElement = true
        reset()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The biggest font, up to `maxSize`, that fits the textbook line in `width`.
    static func fontSize(fitting squash: ListenFirstSquash, in width: CGFloat, maxSize: CGFloat = 28) -> CGFloat {
        let text = squash.pieces.map(\.textbook).joined() as NSString
        let measured = text.size(withAttributes: [.font: UIFont.systemFont(ofSize: maxSize, weight: .semibold)]).width
        let room = width - 40
        guard measured > room, measured > 0 else { return maxSize }
        return floor(maxSize * room / measured)
    }

    func reset() {
        isSquashed = false
        for (piece, label) in zip(squash.pieces, labels) {
            label.layer.removeAllAnimations()
            label.text = piece.textbook
            label.textColor = .label
            label.alpha = 1
            label.transform = .identity
            label.isHidden = false
        }
        accessibilityLabel = squash.pieces.map(\.textbook).joined()
    }

    /// Lands on the real line with no animation.
    func showSquashed() {
        isSquashed = true
        for (piece, label) in zip(squash.pieces, labels) {
            label.text = piece.real
            label.textColor = piece.changes ? ListenFirstSquashPalette.real : .label
            label.isHidden = piece.drops
            label.alpha = 1
            label.transform = .identity
        }
        accessibilityLabel = squash.real
    }

    /// Dropped pieces lift off and fade while the bubble closes up around them, then the
    /// changed ones swap in. `layoutRoot` is laid out alongside so the bubble's neighbors
    /// follow. Returns how long it takes.
    @discardableResult
    func playSquash(layoutRoot: UIView) -> TimeInterval {
        guard !isSquashed else { return 0 }
        isSquashed = true
        accessibilityLabel = squash.real
        layoutRoot.layoutIfNeeded()

        if UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.3) {
                self.showSquashed()
                layoutRoot.layoutIfNeeded()
            }
            return 0.3
        }

        // Ghosts of the dropped pieces fly up from where they sat; the real labels collapse.
        for (index, (piece, label)) in zip(squash.pieces, labels).enumerated() where piece.drops {
            guard let ghost = label.snapshotView(afterScreenUpdates: false) else { continue }
            ghost.frame = label.convert(label.bounds, to: layoutRoot)
            layoutRoot.addSubview(ghost)
            label.alpha = 0
            let tilt: CGFloat = index.isMultiple(of: 2) ? -0.25 : 0.2
            UIView.animate(withDuration: 0.6, delay: 0.04 * Double(index), options: [.curveEaseOut]) {
                ghost.transform = CGAffineTransform(translationX: 0, y: -46).rotated(by: tilt).scaledBy(x: 0.8, y: 0.8)
                ghost.alpha = 0
            } completion: { _ in
                ghost.removeFromSuperview()
            }
        }
        if squash.pieces.contains(where: \.drops) {
            HapticsHelper.lightHaptic()
        }
        UIView.animate(springDuration: 0.5, bounce: 0.25) {
            for (piece, label) in zip(self.squash.pieces, self.labels) where piece.drops {
                label.isHidden = true
            }
            layoutRoot.layoutIfNeeded()
        }

        // Then the pieces that changed shape swap in, in the "real" color, with a pop.
        let swapDelay = 0.32
        for (piece, label) in zip(squash.pieces, labels) where piece.changes {
            DispatchQueue.main.asyncAfter(deadline: .now() + swapDelay) {
                UIView.transition(with: label, duration: 0.22, options: [.transitionCrossDissolve]) {
                    label.text = piece.real
                    label.textColor = ListenFirstSquashPalette.real
                }
                label.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
                UIView.animate(springDuration: 0.45, bounce: 0.5) {
                    label.transform = .identity
                    layoutRoot.layoutIfNeeded()
                }
            }
        }
        if squash.pieces.contains(where: \.changes) {
            DispatchQueue.main.asyncAfter(deadline: .now() + swapDelay) { HapticsHelper.superLightHaptic() }
        }
        return 0.85
    }
}

// MARK: - Length bars

/// Two bars, textbook and real, that fill in real time while each version plays, so the
/// difference in length is something you watch happen.
final class ListenFirstLengthBars: UIView {

    enum Version: Int {
        case textbook, real
    }

    /// A bar is full at this many seconds.
    private static let fullScale: TimeInterval = 3

    private let tracks = [UIView(), UIView()]
    private let fills = [UIView(), UIView()]
    private let timeLabels = [UILabel(), UILabel()]
    private var fillWidths: [NSLayoutConstraint] = []
    private var running: (version: Version, start: CFTimeInterval)?
    private var displayLink: CADisplayLink?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for (index, title) in ["Textbook", "Real"].enumerated() {
            let name = UILabel()
            name.text = title
            name.font = .systemFont(ofSize: 13, weight: .semibold)
            name.textColor = index == 0 ? .secondaryLabel : ListenFirstSquashPalette.real
            name.widthAnchor.constraint(equalToConstant: 66).isActive = true

            let track = tracks[index]
            track.backgroundColor = UIColor.label.withAlphaComponent(0.08)
            track.layer.cornerRadius = 4
            track.heightAnchor.constraint(equalToConstant: 8).isActive = true

            let fill = fills[index]
            fill.backgroundColor = index == 0 ? .tertiaryLabel : ListenFirstSquashPalette.real
            fill.layer.cornerRadius = 4
            fill.translatesAutoresizingMaskIntoConstraints = false
            track.addSubview(fill)
            let width = fill.widthAnchor.constraint(equalToConstant: 0)
            fillWidths.append(width)
            NSLayoutConstraint.activate([
                fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
                fill.topAnchor.constraint(equalTo: track.topAnchor),
                fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
                width,
            ])

            let time = timeLabels[index]
            time.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            time.textColor = .secondaryLabel
            time.textAlignment = .right
            time.widthAnchor.constraint(equalToConstant: 40).isActive = true

            let row = UIStackView(arrangedSubviews: [name, track, time])
            row.spacing = 10
            row.alignment = .center
            stack.addArrangedSubview(row)
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        isAccessibilityElement = true
        reset()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() }
    }

    func reset() {
        stop()
        fillWidths.forEach { $0.constant = 0 }
        timeLabels.forEach { $0.text = "" }
        accessibilityLabel = nil
    }

    func start(_ version: Version) {
        stop()
        fillWidths[version.rawValue].constant = 0
        running = (version, CACurrentMediaTime())
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Freezes the running bar at its length.
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        if running != nil { tick() }
        running = nil
        updateAccessibility()
    }

    @objc private func tick() {
        guard let running else { return }
        let elapsed = CACurrentMediaTime() - running.start
        let index = running.version.rawValue
        let full = tracks[index].bounds.width
        fillWidths[index].constant = min(full, full * CGFloat(elapsed / Self.fullScale))
        timeLabels[index].text = String(format: "%.1fs", elapsed)
    }

    private func updateAccessibility() {
        let parts = zip(["Textbook", "Real"], timeLabels).compactMap { name, label -> String? in
            guard let text = label.text, !text.isEmpty else { return nil }
            return "\(name) \(text)"
        }
        accessibilityLabel = parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

// MARK: - Panel

/// One pair: a tag (TEXTBOOK → REAL), the squash bubble, the English, and the length bars.
final class ListenFirstSquashPanel: UIView {

    let squash: ListenFirstSquash
    let bubble: ListenFirstSquashBubble
    let bars = ListenFirstLengthBars()
    /// Right swipe on the bubble; told whether the real line is showing.
    var onBreakdown: ((_ showingReal: Bool) -> Void)?
    private let versionTag = UILabel()
    private let englishLabel = UILabel()

    init(squash: ListenFirstSquash, width: CGFloat) {
        self.squash = squash
        bubble = ListenFirstSquashBubble(
            squash: squash,
            fontSize: ListenFirstSquashBubble.fontSize(fitting: squash, in: width)
        )
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        versionTag.font = .systemFont(ofSize: 12, weight: .heavy)
        versionTag.textAlignment = .center

        englishLabel.text = squash.english
        englishLabel.font = .preferredFont(forTextStyle: .body)
        englishLabel.textColor = .secondaryLabel
        englishLabel.textAlignment = .center
        englishLabel.numberOfLines = 0

        let swipe = TutorChatView.dissectible(bubble) { [weak self] in
            guard let self else { return }
            self.onBreakdown?(self.bubble.isSquashed)
        }
        let stack = UIStackView(arrangedSubviews: [versionTag, swipe, englishLabel, bars])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.setCustomSpacing(12, after: swipe)
        stack.setCustomSpacing(32, after: englishLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
            bars.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        reset()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Back to the textbook line, bars empty.
    func reset() {
        bubble.reset()
        bars.reset()
        setTag(real: false, animated: false)
        englishLabel.alpha = 0
    }

    /// Squashes the line and brings in the English. Returns how long it takes.
    @discardableResult
    func playSquash() -> TimeInterval {
        let duration = bubble.playSquash(layoutRoot: self)
        setTag(real: true, animated: true)
        UIView.animate(withDuration: 0.4, delay: 0.3) { self.englishLabel.alpha = 1 }
        return duration
    }

    /// The finished state, for revisiting a pair: real line, English, bars as they were.
    func showSquashed() {
        bubble.showSquashed()
        setTag(real: true, animated: false)
        englishLabel.alpha = 1
    }

    private func setTag(real: Bool, animated: Bool) {
        let apply = {
            self.versionTag.text = real ? "HOW PEOPLE SAY IT" : "TEXTBOOK"
            self.versionTag.textColor = real ? ListenFirstSquashPalette.real : .tertiaryLabel
        }
        if animated {
            UIView.transition(with: versionTag, duration: 0.25, options: [.transitionCrossDissolve], animations: apply)
        } else {
            apply()
        }
    }
}
