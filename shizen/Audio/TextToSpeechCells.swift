//
//  TextToSpeechCells.swift
//  shizen
//
//  Collection view cells for the Text to Speech screen (inset grouped list style).
//

import TTSCore
import UIKit

/// Matches inset-grouped list rows on `systemGroupedBackground` (same idea as Settings).
class TTSListCell: UICollectionViewListCell {

    override func updateConfiguration(using state: UICellConfigurationState) {
        super.updateConfiguration(using: state)
        var bg: UIBackgroundConfiguration
        if #available(iOS 18.0, *) {
            bg = UIBackgroundConfiguration.listCell()
        } else {
            bg = UIBackgroundConfiguration.listGroupedCell()
        }
        bg.backgroundColor = .secondarySystemGroupedBackground
        backgroundConfiguration = bg.updated(for: state)
    }
}

// MARK: - Input (same list chrome as Actions / Sentences)

final class TTSInputCollectionViewCell: TTSListCell {

    let textView = UITextView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureInputContent()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureInputContent()
    }

    private func configureInputContent() {
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.keyboardDismissMode = .interactive

        contentView.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            textView.heightAnchor.constraint(equalToConstant: 220),
        ])
    }
}

// MARK: - Actions

final class TTSActionsCollectionViewCell: TTSListCell {

    let voiceButton = UIButton(type: .system)
    let speakButton = UIButton(type: .system)
    let stopButton = UIButton(type: .system)
    let waveform = LiveWaveformView()
    let statusLabel = UILabel()
    let playPauseButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureContentView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureContentView()
    }

    private func configureContentView() {
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)

        waveform.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.text = "Idle"

        var voiceCfg = UIButton.Configuration.bordered()
        voiceCfg.title = "Voice"
        voiceCfg.image = UIImage(systemName: "chevron.down")
        voiceCfg.imagePlacement = .trailing
        voiceCfg.imagePadding = 6
        voiceCfg.cornerStyle = .capsule
        voiceButton.configuration = voiceCfg

        var speakCfg = UIButton.Configuration.borderedProminent()
        speakCfg.title = "Speak"
        speakCfg.image = UIImage(systemName: "speaker.wave.2.fill")
        speakCfg.imagePlacement = .leading
        speakCfg.imagePadding = 6
        speakCfg.cornerStyle = .large
        speakButton.configuration = speakCfg
        speakButton.tintColor = .systemGreen

        var stopCfg = UIButton.Configuration.bordered()
        stopCfg.title = "Stop"
        stopCfg.cornerStyle = .large
        stopButton.configuration = stopCfg

        var playPauseCfg = UIButton.Configuration.tinted()
        playPauseCfg.image = UIImage(systemName: "play.fill")
        playPauseCfg.title = "Play / Pause"
        playPauseCfg.imagePadding = 6
        playPauseCfg.cornerStyle = .large
        playPauseButton.configuration = playPauseCfg

        let speakStopRow = UIStackView(arrangedSubviews: [speakButton, stopButton])
        speakStopRow.axis = .horizontal
        speakStopRow.spacing = 12
        speakStopRow.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [
            voiceButton,
            speakStopRow,
            waveform,
            statusLabel,
            playPauseButton,
        ])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            waveform.heightAnchor.constraint(equalToConstant: 72),
        ])
    }
}

// MARK: - Chunk toolbar (sentences section header row)

final class TTSChunkToolbarCollectionViewCell: TTSListCell {

    let replayAllButton = UIButton(type: .system)
    let lyricsButton = UIButton(type: .system)
    let saveButton = UIButton(type: .system)
    let summaryLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureContentView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureContentView()
    }

    private func configureContentView() {
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)

        var replayCfg = UIButton.Configuration.borderedProminent()
        replayCfg.image = UIImage(systemName: "arrow.counterclockwise")
        replayCfg.title = "Replay all"
        replayCfg.imagePadding = 8
        replayCfg.cornerStyle = .large
        replayAllButton.configuration = replayCfg

        var lyricsCfg = UIButton.Configuration.bordered()
        lyricsCfg.image = UIImage(systemName: "text.quote")
        lyricsCfg.title = "Lyrics"
        lyricsCfg.imagePadding = 8
        lyricsCfg.cornerStyle = .large
        lyricsButton.configuration = lyricsCfg

        var saveCfg = UIButton.Configuration.bordered()
        saveCfg.image = UIImage(systemName: "square.and.arrow.down")
        saveCfg.title = "Save"
        saveCfg.imagePadding = 8
        saveCfg.cornerStyle = .large
        saveButton.configuration = saveCfg

        summaryLabel.font = .preferredFont(forTextStyle: .footnote)
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.numberOfLines = 0

        let buttonRow = UIStackView(arrangedSubviews: [replayAllButton, lyricsButton, saveButton])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 8
        buttonRow.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [buttonRow, summaryLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }
}

// MARK: - Single chunk row

final class ChunkCollectionViewCell: TTSListCell {

    private let groupStripe = UIView()
    private let indexLabel = UILabel()
    private let timingLabel = UILabel()
    private let durationLabel = UILabel()
    private let waveform = StaticWaveformView()
    private let playButton = UIButton(type: .system)

    var onPlay: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureContentView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureContentView()
    }

    private func configureContentView() {
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)

        groupStripe.translatesAutoresizingMaskIntoConstraints = false
        groupStripe.layer.cornerRadius = 2
        groupStripe.clipsToBounds = true

        indexLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        indexLabel.textColor = .secondaryLabel
        indexLabel.setContentHuggingPriority(.required, for: .horizontal)

        timingLabel.font = .preferredFont(forTextStyle: .caption2)
        timingLabel.textColor = .tertiaryLabel
        timingLabel.numberOfLines = 0

        durationLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        durationLabel.textColor = .tertiaryLabel
        durationLabel.textAlignment = .right
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)

        waveform.translatesAutoresizingMaskIntoConstraints = false
        waveform.barColor = .systemTeal

        var playCfg = UIButton.Configuration.tinted()
        playCfg.image = UIImage(systemName: "play.fill")
        playCfg.cornerStyle = .capsule
        playButton.configuration = playCfg
        playButton.setContentHuggingPriority(.required, for: .horizontal)
        playButton.addAction(UIAction { [weak self] _ in
            self?.onPlay?()
        }, for: .primaryActionTriggered)

        let titleColumn = UIStackView(arrangedSubviews: [indexLabel, timingLabel])
        titleColumn.axis = .vertical
        titleColumn.spacing = 2
        titleColumn.alignment = .leading

        let topRow = UIStackView(arrangedSubviews: [titleColumn, waveform, durationLabel, playButton])
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.spacing = 10

        let root = UIStackView(arrangedSubviews: [groupStripe, topRow])
        root.axis = .horizontal
        root.alignment = .top
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            groupStripe.widthAnchor.constraint(equalToConstant: 4),
            groupStripe.heightAnchor.constraint(greaterThanOrEqualTo: topRow.heightAnchor),
            waveform.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    /// One row per parsed sentence (slice within one utterance). Content reflects whichever load state the sentence is in
    /// (`.pending` / `.streaming` / `.ready` / `.failed`).
    func apply(sentence: SpeechSentence, isPlaying: Bool, trait: UITraitCollection) {
        groupStripe.backgroundColor = Self.stripeColor(for: sentence.index, trait: trait)

        indexLabel.text = "\(sentence.index + 1). \(sentence.text)"
        indexLabel.numberOfLines = 0
        indexLabel.font = .preferredFont(forTextStyle: .body)
        indexLabel.textColor = .label

        switch sentence.state {
        case .pending:
            timingLabel.text = "Queued…"
            durationLabel.text = "—"
        case .streaming:
            timingLabel.text = "Generating…"
            durationLabel.text = "…"
        case .ready:
            timingLabel.text = "Ready · tap to replay"
            durationLabel.text = String(format: "%.2fs", sentence.duration)
        case .failed(let msg):
            timingLabel.text = "Failed: \(msg)"
            durationLabel.text = "—"
        }

        waveform.peaks = sentence.peaks
        playButton.isEnabled = {
            if case .ready = sentence.state { return sentence.sampleCount > 0 }
            return false
        }()
        setPlaying(isPlaying)
    }

    func setPlaying(_ playing: Bool) {
        var cfg = playButton.configuration ?? .tinted()
        cfg.image = UIImage(systemName: playing ? "stop.fill" : "play.fill")
        playButton.configuration = cfg
        waveform.barColor = playing ? .systemGreen : .systemTeal
    }

    private static func stripeColor(for index: Int, trait: UITraitCollection) -> UIColor {
        let n = 6
        let hue = CGFloat(index % n) / CGFloat(n)
        let isDark = trait.userInterfaceStyle == .dark
        return UIColor(
            hue: hue,
            saturation: isDark ? 0.42 : 0.38,
            brightness: isDark ? 0.92 : 0.55,
            alpha: 1
        )
    }
}
