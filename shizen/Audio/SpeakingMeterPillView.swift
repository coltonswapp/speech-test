//
//  SpeakingMeterPillView.swift
//  shizen
//
//  Glass meter pill from Repeat After Me — live bars while the learner
//  should speak, idle breathe otherwise.
//

import AVFoundation
import InteractionKit
import UIKit

/// Peak-normalized RMS in [0, 1] from a mic tap buffer.
enum MicrophoneInputLevel {
    static func rms(from buffer: AVAudioPCMBuffer) -> Float {
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return 0 }

        var sum: Float = 0
        var sampleCount = 0

        if let channels = buffer.floatChannelData {
            for ch in 0..<channelCount {
                let channel = channels[ch]
                for i in 0..<frameLength {
                    let sample = channel[i]
                    sum += sample * sample
                    sampleCount += 1
                }
            }
        } else if let channels = buffer.int16ChannelData {
            let scale: Float = 1.0 / 32_768.0
            for ch in 0..<channelCount {
                let channel = channels[ch]
                for i in 0..<frameLength {
                    let sample = Float(channel[i]) * scale
                    sum += sample * sample
                    sampleCount += 1
                }
            }
        }

        guard sampleCount > 0 else { return 0 }
        return min(1, sqrt(sum / Float(sampleCount)) * 4)
    }
}

final class SpeakingMeterPillView: UIView {

    enum Mode {
        case idle
        case listening
        case playback
    }

    static let pillHeight: CGFloat = 64
    static let preferredWidthMultiplier: CGFloat = 0.52
    static let maxWidth: CGFloat = 220

    private static let listeningBarColor = UIColor.systemYellow
    private static let idleMeterColor = UIColor.tertiaryLabel
    private static let playbackMeterColor = UIColor.label
    private static let idleScale: CGFloat = 0.9
    private static let activeScale: CGFloat = 1.0

    private static let glowRestRadius: CGFloat = 6
    private static let glowEnergyRadiusBoost: CGFloat = 8
    private static let glowBreathOpacity: ClosedRange<Float> = 0.14...0.26
    private static let glowBreathDuration: CFTimeInterval = 1.4
    private static let ringAlpha: CGFloat = 0.28
    private static let glowBreathKey = "glowBreath"

    private let glowView = UIView()
    private let ringLayer = CAShapeLayer()
    private let pillBackground = LiquidGlassEffectView.makeLightPillContainer()
    private let levelMeterView = AudioLevelBarsView()

    /// Soft halo + ring in ``listeningBarColor`` while listening, so it reads as
    /// "your turn". Off by default; other screens keep the plain pill.
    var glowsWhileListening = false {
        didSet {
            guard glowsWhileListening != oldValue else { return }
            applyGlow(animated: window != nil)
        }
    }

    /// Maps mic RMS on a decibel curve and uses the bars' voice motion, so
    /// normal speaking volume fills the meter instead of barely moving it.
    var reactsToVoice = false {
        didSet { levelMeterView.voiceMotion = reactsToVoice }
    }

    /// Color of the bars while the learner should speak.
    var listeningBarColor: UIColor = SpeakingMeterPillView.listeningBarColor {
        didSet {
            if mode == .listening {
                levelMeterView.barColor = listeningBarColor
            }
            glowView.layer.shadowColor = listeningBarColor.cgColor
            ringLayer.strokeColor = listeningBarColor.withAlphaComponent(Self.ringAlpha).cgColor
        }
    }

    private(set) var mode: Mode = .idle

    override init(frame: CGRect) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configure()
        applyMode(.idle)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setMode(_ mode: Mode) {
        guard mode != self.mode else { return }
        applyMode(mode)
    }

    /// RMS in [0, 1]. Ignored unless ``mode`` is `.listening` or `.playback`.
    func pushLevel(_ level: Float) {
        switch mode {
        case .idle:
            return
        case .listening, .playback:
            let clamped = max(0, min(1, level))
            if reactsToVoice, mode == .listening {
                levelMeterView.setLevel(Self.voiceLevel(fromMeterLevel: clamped))
            } else {
                let eased = clamped * clamped * (3 - 2 * clamped)
                levelMeterView.setLevel(eased)
            }
        }
    }

    func releaseToRest() {
        levelMeterView.releaseToRest()
    }

    func fadeToMinimum() {
        levelMeterView.fadeToMinimum()
    }

    func reset() {
        levelMeterView.reset()
    }

    private func configure() {
        isAccessibilityElement = true
        accessibilityLabel = "Speaking meter"
        accessibilityValue = "Idle"
        clipsToBounds = false
        transform = CGAffineTransform(scaleX: Self.idleScale, y: Self.idleScale)

        glowView.translatesAutoresizingMaskIntoConstraints = false
        glowView.isUserInteractionEnabled = false
        glowView.backgroundColor = .clear
        glowView.alpha = 0
        glowView.layer.shadowColor = listeningBarColor.cgColor
        glowView.layer.shadowOffset = .zero
        glowView.layer.shadowRadius = Self.glowRestRadius
        glowView.layer.shadowOpacity = Self.glowBreathOpacity.upperBound
        addSubview(glowView)

        LiquidGlassEffectView.applyPillStyle(to: pillBackground, cornerRadius: Self.pillHeight / 2)
        pillBackground.isUserInteractionEnabled = false
        addSubview(pillBackground)

        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.strokeColor = listeningBarColor.withAlphaComponent(Self.ringAlpha).cgColor
        ringLayer.lineWidth = 1
        ringLayer.opacity = 0
        layer.addSublayer(ringLayer)

        levelMeterView.translatesAutoresizingMaskIntoConstraints = false
        levelMeterView.isUserInteractionEnabled = false
        levelMeterView.barWidth = 8
        levelMeterView.barSpacing = 10
        levelMeterView.meterHeight = 28
        levelMeterView.minBarHeight = 8
        levelMeterView.heightFill = 0.95
        levelMeterView.levelGain = 1.6
        levelMeterView.displayCurve = 1.05
        levelMeterView.smoothing = 0.66
        levelMeterView.wobbleAmount = 0.08
        levelMeterView.diamondFalloff = 0.25
        levelMeterView.springiness = 0.5
        levelMeterView.historyStride = 2
        levelMeterView.barColor = Self.idleMeterColor
        levelMeterView.onEnergyChange = { [weak self] energy in
            self?.updateGlowEnergy(energy)
        }
        addSubview(levelMeterView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.pillHeight),

            glowView.topAnchor.constraint(equalTo: topAnchor),
            glowView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glowView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glowView.bottomAnchor.constraint(equalTo: bottomAnchor),

            pillBackground.topAnchor.constraint(equalTo: topAnchor),
            pillBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            pillBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            pillBackground.bottomAnchor.constraint(equalTo: bottomAnchor),

            levelMeterView.centerXAnchor.constraint(equalTo: centerXAnchor),
            levelMeterView.centerYAnchor.constraint(equalTo: centerYAnchor),
            levelMeterView.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    private func applyMode(_ mode: Mode) {
        self.mode = mode
        let scale: CGFloat
        switch mode {
        case .idle:
            levelMeterView.barColor = Self.idleMeterColor
            levelMeterView.releaseToRest()
            accessibilityValue = "Idle"
            scale = Self.idleScale
        case .listening:
            levelMeterView.barColor = listeningBarColor
            accessibilityValue = "Listening"
            scale = Self.activeScale
        case .playback:
            levelMeterView.barColor = Self.playbackMeterColor
            accessibilityValue = "Playback"
            scale = Self.activeScale
        }

        let animations = {
            self.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
        applyGlow(animated: window != nil)
        if window != nil {
            UIView.animate(
                withDuration: 0.42,
                delay: 0,
                usingSpringWithDamping: 0.72,
                initialSpringVelocity: 0.35,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: animations
            )
        } else {
            animations()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
        glowView.layer.shadowPath = path
        ringLayer.frame = bounds
        ringLayer.path = UIBezierPath(
            roundedRect: bounds.insetBy(dx: ringLayer.lineWidth / 2, dy: ringLayer.lineWidth / 2),
            cornerRadius: (bounds.height - ringLayer.lineWidth) / 2
        ).cgPath
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Core Animation drops the breath when the view leaves the window.
        if window != nil { applyGlow(animated: false) }
    }

    private var isGlowing: Bool {
        glowsWhileListening && mode == .listening
    }

    /// `MicrophoneInputLevel` is RMS × 4. Undo that and map about −52 dBFS
    /// (room noise) → 0 and −18 dBFS (close, clear speech) → 1.
    private static func voiceLevel(fromMeterLevel level: Float) -> Float {
        let rms = max(level / 4, 0.000_01)
        let decibels = 20 * log10(rms)
        return max(0, min(1, (decibels + 52) / 34))
    }

    /// The halo widens with the bars' eased loudness, so it swells as they talk.
    private func updateGlowEnergy(_ energy: CGFloat) {
        guard isGlowing else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glowView.layer.shadowRadius = Self.glowRestRadius + Self.glowEnergyRadiusBoost * energy
        CATransaction.commit()
    }

    private func applyGlow(animated: Bool) {
        let on = isGlowing
        let changes = {
            self.glowView.alpha = on ? 1 : 0
        }
        if animated {
            UIView.animate(
                withDuration: on ? 0.35 : 0.25,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut],
                animations: changes
            )
        } else {
            changes()
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.3 : 0)
        ringLayer.opacity = on ? 1 : 0
        CATransaction.commit()

        let glowLayer = glowView.layer
        glowLayer.removeAnimation(forKey: Self.glowBreathKey)
        guard on else {
            glowLayer.shadowRadius = Self.glowRestRadius
            return
        }
        guard !UIAccessibility.isReduceMotionEnabled else {
            glowLayer.shadowOpacity = Self.glowBreathOpacity.upperBound
            return
        }
        glowLayer.shadowOpacity = Self.glowBreathOpacity.lowerBound
        let breath = CABasicAnimation(keyPath: "shadowOpacity")
        breath.fromValue = Self.glowBreathOpacity.lowerBound
        breath.toValue = Self.glowBreathOpacity.upperBound
        breath.duration = Self.glowBreathDuration
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glowLayer.add(breath, forKey: Self.glowBreathKey)
    }
}
