//
//  CharacterSpeakingExperimentViewController.swift
//  shizen
//
//  DEBUG experiment: compare speaking-character visualizers driven by
//  encouragement tutor audio clips.
//

import UIKit

final class CharacterSpeakingExperimentViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let liveMeterCard = CharacterCardView(
        title: "Live meter",
        subtitle: "Diamond silhouette — center bar tallest, edges clamped — with smooth grow and decay."
    )
    private let speechMeterCard = CharacterCardView(
        title: "Speech profile",
        subtitle: "Same diamond shape · envelope rhythm in the middle, live punch and attacks on the sides."
    )
    private let dotFieldCard = CharacterCardView(
        title: "Dot field",
        subtitle: "Random dots scale with audio inside a circular character."
    )
    private let audioBlobCard = CharacterCardView(
        title: "Audio blob",
        subtitle: "Glowing icosahedron wireframe — Perlin noise displacement driven by audio level."
    )

    private let levelBars = AudioLevelBarsView()
    private let speechBars = SpeechEnvelopeBarsView()
    private let dotFieldCharacter = DotFieldCharacterView()
    private let audioBlobCharacter = AudioBlobCharacterView()
    private let liveDebugLabel = UILabel()
    private let speechDebugLabel = UILabel()

    private let widthSlider = UISlider()
    private let spacingSlider = UISlider()
    private let heightSlider = UISlider()
    private let levelGainSlider = UISlider()
    private let smoothingSlider = UISlider()
    private let wobbleSlider = UISlider()
    private let heightFillSlider = UISlider()
    private let diamondSlider = UISlider()

    private let speechWidthSlider = UISlider()
    private let speechHeightSlider = UISlider()
    private let envelopeGainSlider = UISlider()
    private let liveGainSlider = UISlider()
    private let attackGainSlider = UISlider()
    private let speechSmoothingSlider = UISlider()
    private let speechDiamondSlider = UISlider()

    private let blobNoiseSlider = UISlider()
    private let blobDisplacementSlider = UISlider()
    private var liveMeterHeightConstraint: NSLayoutConstraint?
    private var speechMeterHeightConstraint: NSLayoutConstraint?

    private let floatingDock = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let clipSelector = UISegmentedControl(items: (1...6).map { "\($0)" })
    private let playButton = UIButton(type: .system)

    private let audioPlayer = MeteredAudioPlayer()
    private var selectedClipIndex = 0
    private var playingClipIndex: Int?
    private var lastLiveLevel: Float = 0
    private var lastPlaybackTime: TimeInterval = 0
    private var lastPlaybackEnvelope: PlaybackEnvelope?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Speaking characters"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground

        audioPlayer.onPlaybackUpdate = { [weak self] time, envelope, liveLevel in
            self?.pushPlayback(time: time, envelope: envelope, liveLevel: liveLevel)
        }
        audioPlayer.onFinished = { [weak self] in
            self?.handlePlaybackFinished()
        }

        configureScrollView()
        configureCharacters()
        configureFloatingDock()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || isBeingDismissed {
            audioPlayer.stop()
        }
    }

    // MARK: - Layout

    private func configureScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 20
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
        ])
    }

    private func configureCharacters() {
        let intro = UILabel()
        intro.text = "Pick a clip and tap play below. Compare two VU-meter personalities on the same audio."
        intro.font = .preferredFont(forTextStyle: .subheadline)
        intro.textColor = .secondaryLabel
        intro.numberOfLines = 0
        contentStack.addArrangedSubview(intro)

        configureLiveMeterCard()
        configureSpeechMeterCard()
        configureAudioBlobCard()

        dotFieldCharacter.translatesAutoresizingMaskIntoConstraints = false
        dotFieldCard.setCharacterContent(dotFieldCharacter)
        contentStack.addArrangedSubview(dotFieldCard)

        NSLayoutConstraint.activate([
            dotFieldCharacter.heightAnchor.constraint(equalToConstant: 210),
        ])
    }

    private func configureAudioBlobCard() {
        audioBlobCharacter.translatesAutoresizingMaskIntoConstraints = false
        audioBlobCharacter.noiseScale = 3.2
        audioBlobCharacter.displacementScale = 1.25

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill

        configureSlider(blobNoiseSlider, min: 1.0, max: 6.0, value: audioBlobCharacter.noiseScale, action: #selector(blobNoiseChanged))
        configureSlider(blobDisplacementSlider, min: 0.4, max: 2.5, value: audioBlobCharacter.displacementScale, action: #selector(blobDisplacementChanged))

        stack.addArrangedSubview(audioBlobCharacter)
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Noise roughness", slider: blobNoiseSlider, format: "%.1f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Displacement", slider: blobDisplacementSlider, format: "%.1f"))
        audioBlobCard.setCharacterContent(stack)
        contentStack.addArrangedSubview(audioBlobCard)

        NSLayoutConstraint.activate([
            audioBlobCharacter.heightAnchor.constraint(equalToConstant: 240),
        ])
    }

    private func configureLiveMeterCard() {
        levelBars.translatesAutoresizingMaskIntoConstraints = false
        levelBars.barColor = .systemYellow
        levelBars.barWidth = 8
        levelBars.barSpacing = 12
        levelBars.meterHeight = 72
        levelBars.minBarHeight = 8
        levelBars.heightFill = 0.92
        levelBars.levelGain = 1.35
        levelBars.displayCurve = 0.72
        levelBars.smoothing = 0.34
        levelBars.wobbleAmount = 0.08
        levelBars.diamondFalloff = 0.52

        let meterContainer = UIView()
        meterContainer.translatesAutoresizingMaskIntoConstraints = false
        meterContainer.addSubview(levelBars)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill

        liveDebugLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        liveDebugLabel.textColor = .secondaryLabel
        liveDebugLabel.numberOfLines = 0
        liveDebugLabel.textAlignment = .center
        liveDebugLabel.text = "live: 0.00"

        configureSlider(widthSlider, min: 3, max: 18, value: Float(levelBars.barWidth), action: #selector(widthChanged))
        configureSlider(spacingSlider, min: 2, max: 24, value: Float(levelBars.barSpacing), action: #selector(spacingChanged))
        configureSlider(heightSlider, min: 24, max: 160, value: Float(levelBars.meterHeight), action: #selector(heightChanged))
        configureSlider(levelGainSlider, min: 0.4, max: 3.5, value: levelBars.levelGain, action: #selector(levelGainChanged))
        configureSlider(heightFillSlider, min: 0.2, max: 1.0, value: Float(levelBars.heightFill), action: #selector(heightFillChanged))
        configureSlider(smoothingSlider, min: 0.08, max: 0.75, value: Float(levelBars.smoothing), action: #selector(smoothingChanged))
        configureSlider(wobbleSlider, min: 0, max: 0.25, value: Float(levelBars.wobbleAmount), action: #selector(wobbleChanged))
        configureSlider(diamondSlider, min: 0, max: 1.0, value: Float(levelBars.diamondFalloff), action: #selector(diamondChanged))

        stack.addArrangedSubview(meterContainer)
        stack.addArrangedSubview(liveDebugLabel)
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Bar width", slider: widthSlider, format: "%.0f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Bar spacing", slider: spacingSlider, format: "%.0f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Meter height", slider: heightSlider, format: "%.0f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Level gain", slider: levelGainSlider, format: "%.2f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Height fill", slider: heightFillSlider, format: "%.2f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Smoothing", slider: smoothingSlider, format: "%.2f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Wobble", slider: wobbleSlider, format: "%.2f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Diamond clamp", slider: diamondSlider, format: "%.2f"))
        liveMeterCard.setCharacterContent(stack)
        contentStack.addArrangedSubview(liveMeterCard)

        liveMeterHeightConstraint = meterContainer.heightAnchor.constraint(equalToConstant: levelBars.meterHeight)
        NSLayoutConstraint.activate([
            levelBars.centerXAnchor.constraint(equalTo: meterContainer.centerXAnchor),
            levelBars.centerYAnchor.constraint(equalTo: meterContainer.centerYAnchor),
            levelBars.leadingAnchor.constraint(greaterThanOrEqualTo: meterContainer.leadingAnchor),
            levelBars.trailingAnchor.constraint(lessThanOrEqualTo: meterContainer.trailingAnchor),
            liveMeterHeightConstraint!,
        ])
    }

    private func configureSpeechMeterCard() {
        speechBars.translatesAutoresizingMaskIntoConstraints = false
        speechBars.barColor = .systemYellow
        speechBars.barWidth = 7
        speechBars.barSpacing = 10
        speechBars.meterHeight = 80
        speechBars.minBarHeight = 7
        speechBars.heightFill = 0.94
        speechBars.envelopeGain = 1.25
        speechBars.liveGain = 1.15
        speechBars.attackGain = 1.7
        speechBars.smoothing = 0.38
        speechBars.wobbleAmount = 0.05
        speechBars.diamondFalloff = 0.52

        let meterContainer = UIView()
        meterContainer.translatesAutoresizingMaskIntoConstraints = false
        meterContainer.addSubview(speechBars)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill

        speechDebugLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        speechDebugLabel.textColor = .secondaryLabel
        speechDebugLabel.numberOfLines = 0
        speechDebugLabel.textAlignment = .center
        speechDebugLabel.text = "envelope: 0.00  live: 0.00  attack: 0.00"

        configureSlider(speechWidthSlider, min: 3, max: 18, value: Float(speechBars.barWidth), action: #selector(speechWidthChanged))
        configureSlider(speechHeightSlider, min: 24, max: 160, value: Float(speechBars.meterHeight), action: #selector(speechHeightChanged))
        configureSlider(envelopeGainSlider, min: 0.4, max: 3.5, value: speechBars.envelopeGain, action: #selector(envelopeGainChanged))
        configureSlider(liveGainSlider, min: 0.4, max: 3.5, value: speechBars.liveGain, action: #selector(liveGainChanged))
        configureSlider(attackGainSlider, min: 0, max: 3.5, value: speechBars.attackGain, action: #selector(attackGainChanged))
        configureSlider(speechSmoothingSlider, min: 0.08, max: 0.75, value: Float(speechBars.smoothing), action: #selector(speechSmoothingChanged))
        configureSlider(speechDiamondSlider, min: 0, max: 1.0, value: Float(speechBars.diamondFalloff), action: #selector(speechDiamondChanged))

        stack.addArrangedSubview(meterContainer)
        stack.addArrangedSubview(speechDebugLabel)
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Bar width", slider: speechWidthSlider, format: "%.0f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Meter height", slider: speechHeightSlider, format: "%.0f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Envelope gain", slider: envelopeGainSlider, format: "%.2f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Live gain", slider: liveGainSlider, format: "%.2f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Attack gain", slider: attackGainSlider, format: "%.2f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Smoothing", slider: speechSmoothingSlider, format: "%.2f"))
        stack.addArrangedSubview(ExperimentSliderRow.make(title: "Diamond clamp", slider: speechDiamondSlider, format: "%.2f"))
        speechMeterCard.setCharacterContent(stack)
        contentStack.addArrangedSubview(speechMeterCard)

        speechMeterHeightConstraint = meterContainer.heightAnchor.constraint(equalToConstant: speechBars.meterHeight)
        NSLayoutConstraint.activate([
            speechBars.centerXAnchor.constraint(equalTo: meterContainer.centerXAnchor),
            speechBars.centerYAnchor.constraint(equalTo: meterContainer.centerYAnchor),
            speechBars.leadingAnchor.constraint(greaterThanOrEqualTo: meterContainer.leadingAnchor),
            speechBars.trailingAnchor.constraint(lessThanOrEqualTo: meterContainer.trailingAnchor),
            speechMeterHeightConstraint!,
        ])
    }

    private func configureSlider(_ slider: UISlider, min: Float, max: Float, value: Float, action: Selector) {
        slider.minimumValue = min
        slider.maximumValue = max
        slider.value = value
        slider.addTarget(self, action: action, for: .valueChanged)
    }

    private func configureFloatingDock() {
        floatingDock.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingDock)

        let dockStack = UIStackView()
        dockStack.translatesAutoresizingMaskIntoConstraints = false
        dockStack.axis = .vertical
        dockStack.spacing = 12
        floatingDock.contentView.addSubview(dockStack)

        clipSelector.selectedSegmentIndex = selectedClipIndex
        clipSelector.addTarget(self, action: #selector(clipSelectionChanged), for: .valueChanged)

        var playConfig = UIButton.Configuration.filled()
        playConfig.cornerStyle = .capsule
        playConfig.image = UIImage(systemName: "play.fill")
        playConfig.imagePadding = 8
        playConfig.title = "Play clip 1"
        playConfig.baseBackgroundColor = .systemYellow
        playConfig.baseForegroundColor = .black
        playConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(scale: .medium)
        playButton.configuration = playConfig
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)

        dockStack.addArrangedSubview(clipSelector)
        dockStack.addArrangedSubview(playButton)

        NSLayoutConstraint.activate([
            floatingDock.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            floatingDock.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            floatingDock.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            scrollView.bottomAnchor.constraint(equalTo: floatingDock.topAnchor),

            dockStack.topAnchor.constraint(equalTo: floatingDock.contentView.topAnchor, constant: 12),
            dockStack.leadingAnchor.constraint(equalTo: floatingDock.contentView.leadingAnchor, constant: 20),
            dockStack.trailingAnchor.constraint(equalTo: floatingDock.contentView.trailingAnchor, constant: -20),
            dockStack.bottomAnchor.constraint(equalTo: floatingDock.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            playButton.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    // MARK: - Playback

    @objc private func clipSelectionChanged() {
        selectedClipIndex = clipSelector.selectedSegmentIndex
        updatePlayButtonAppearance()

        if audioPlayer.isPlaying, playingClipIndex != selectedClipIndex {
            startPlayback(for: selectedClipIndex)
        }
    }

    @objc private func playTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if audioPlayer.isPlaying, playingClipIndex == selectedClipIndex {
            audioPlayer.stop()
            handlePlaybackFinished()
            return
        }

        startPlayback(for: selectedClipIndex)
    }

    private func startPlayback(for index: Int) {
        selectedClipIndex = index
        clipSelector.selectedSegmentIndex = index
        playingClipIndex = index
        updatePlayButtonAppearance()

        levelBars.reset()
        speechBars.reset()
        audioBlobCharacter.reset()
        lastLiveLevel = 0
        lastPlaybackEnvelope = nil
        dotFieldCharacter.reset()

        let assetName = MeteredAudioPlayer.encouragementClipNames[index]
        audioPlayer.play(assetNamed: assetName)
    }

    private func pushPlayback(time: TimeInterval, envelope: PlaybackEnvelope, liveLevel: Float) {
        lastLiveLevel = liveLevel
        lastPlaybackTime = time
        lastPlaybackEnvelope = envelope

        let envelopeNow = envelope.level(at: time)
        let envPrev = envelope.level(at: max(0, time - 0.045))
        let attack = max(0, liveLevel - envPrev * 0.88)

        levelBars.setLevel(liveLevel)
        speechBars.setPlayback(envelope: envelope, at: time, liveLevel: liveLevel)

        liveDebugLabel.text = String(format: "live: %.2f", liveLevel)
        speechDebugLabel.text = String(
            format: "envelope: %.2f  live: %.2f  attack: %.2f",
            envelopeNow,
            liveLevel,
            attack
        )
        dotFieldCharacter.setLevel(max(liveLevel, envelopeNow))
        audioBlobCharacter.setLevel(max(liveLevel, envelopeNow))
    }

    private func handlePlaybackFinished() {
        playingClipIndex = nil
        updatePlayButtonAppearance()
        levelBars.reset()
        speechBars.releaseToRest()
        audioBlobCharacter.reset()
        lastLiveLevel = 0
        lastPlaybackEnvelope = nil
        dotFieldCharacter.reset()
    }

    private func updatePlayButtonAppearance() {
        let clipNumber = selectedClipIndex + 1
        let isPlayingSelection = audioPlayer.isPlaying && playingClipIndex == selectedClipIndex

        var config = playButton.configuration
        config?.title = isPlayingSelection ? "Stop clip \(clipNumber)" : "Play clip \(clipNumber)"
        config?.image = UIImage(systemName: isPlayingSelection ? "stop.fill" : "play.fill")
        playButton.configuration = config
    }

    private func refreshLiveMeter() {
        levelBars.setLevel(lastLiveLevel)
    }

    private func refreshSpeechMeter() {
        guard let envelope = lastPlaybackEnvelope else { return }
        speechBars.setPlayback(envelope: envelope, at: lastPlaybackTime, liveLevel: lastLiveLevel)
    }

    @objc private func widthChanged() {
        levelBars.barWidth = CGFloat(widthSlider.value)
        refreshLiveMeter()
    }

    @objc private func spacingChanged() {
        levelBars.barSpacing = CGFloat(spacingSlider.value)
        refreshLiveMeter()
    }

    @objc private func heightChanged() {
        levelBars.meterHeight = CGFloat(heightSlider.value)
        liveMeterHeightConstraint?.constant = levelBars.meterHeight
        refreshLiveMeter()
    }

    @objc private func levelGainChanged() {
        levelBars.levelGain = levelGainSlider.value
        refreshLiveMeter()
    }

    @objc private func heightFillChanged() {
        levelBars.heightFill = CGFloat(heightFillSlider.value)
        levelBars.setNeedsDisplay()
    }

    @objc private func smoothingChanged() {
        levelBars.smoothing = CGFloat(smoothingSlider.value)
    }

    @objc private func wobbleChanged() {
        levelBars.wobbleAmount = CGFloat(wobbleSlider.value)
    }

    @objc private func diamondChanged() {
        levelBars.diamondFalloff = CGFloat(diamondSlider.value)
    }

    @objc private func speechWidthChanged() {
        speechBars.barWidth = CGFloat(speechWidthSlider.value)
        refreshSpeechMeter()
    }

    @objc private func speechHeightChanged() {
        speechBars.meterHeight = CGFloat(speechHeightSlider.value)
        speechMeterHeightConstraint?.constant = speechBars.meterHeight
        refreshSpeechMeter()
    }

    @objc private func envelopeGainChanged() {
        speechBars.envelopeGain = envelopeGainSlider.value
        refreshSpeechMeter()
    }

    @objc private func liveGainChanged() {
        speechBars.liveGain = liveGainSlider.value
        refreshSpeechMeter()
    }

    @objc private func attackGainChanged() {
        speechBars.attackGain = attackGainSlider.value
        refreshSpeechMeter()
    }

    @objc private func speechSmoothingChanged() {
        speechBars.smoothing = CGFloat(speechSmoothingSlider.value)
    }

    @objc private func speechDiamondChanged() {
        speechBars.diamondFalloff = CGFloat(speechDiamondSlider.value)
    }

    @objc private func blobNoiseChanged() {
        audioBlobCharacter.noiseScale = blobNoiseSlider.value
    }

    @objc private func blobDisplacementChanged() {
        audioBlobCharacter.displacementScale = blobDisplacementSlider.value
    }
}

// MARK: - Character card

private final class CharacterCardView: UIView {

    private let innerStack = UIStackView()
    private let characterSlot = UIStackView()

    init(title: String, subtitle: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        backgroundColor = ExperimentPalette.cardSurface
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = ExperimentPalette.cardBorder.cgColor

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .title3).pointSize, weight: .semibold)

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .preferredFont(forTextStyle: .footnote)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        innerStack.translatesAutoresizingMaskIntoConstraints = false
        innerStack.axis = .vertical
        innerStack.spacing = 14
        addSubview(innerStack)

        characterSlot.axis = .vertical
        characterSlot.alignment = .fill

        innerStack.addArrangedSubview(titleLabel)
        innerStack.addArrangedSubview(subtitleLabel)
        innerStack.addArrangedSubview(characterSlot)

        NSLayoutConstraint.activate([
            innerStack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            innerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            innerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            innerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setCharacterContent(_ view: UIView) {
        characterSlot.arrangedSubviews.forEach { $0.removeFromSuperview() }
        characterSlot.addArrangedSubview(view)
    }
}
