//
//  SpeakingMeterPillView.swift
//  shizen
//
//  Glass meter pill from Repeat After Me — live bars while the learner
//  should speak, idle breathe otherwise.
//

import AVFoundation
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

    private let pillBackground = LiquidGlassEffectView.makeLightPillContainer()
    private let levelMeterView = AudioLevelBarsView()

    /// Color of the bars while the learner should speak.
    var listeningBarColor: UIColor = SpeakingMeterPillView.listeningBarColor {
        didSet {
            if mode == .listening {
                levelMeterView.barColor = listeningBarColor
            }
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
            let eased = clamped * clamped * (3 - 2 * clamped)
            levelMeterView.setLevel(eased)
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

        LiquidGlassEffectView.applyPillStyle(to: pillBackground, cornerRadius: Self.pillHeight / 2)
        pillBackground.isUserInteractionEnabled = false
        addSubview(pillBackground)

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
        addSubview(levelMeterView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.pillHeight),

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
}
