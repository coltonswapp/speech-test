//
//  CharacterSpeakingExperimentViewController.swift
//  shizen
//
//  DEBUG experiment: tune the live speaking meter driven by encouragement tutor clips.
//

import UIKit

final class CharacterSpeakingExperimentViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let liveMeterCard = CharacterCardView(
        title: "Live meter",
        subtitle: "Fidelity: spectral bands low→high. Off: diamond VU with staggered history."
    )

    private let levelBars = AudioLevelBarsView()
    private let liveDebugLabel = UILabel()

    private let widthSlider = UISlider()
    private let spacingSlider = UISlider()
    private let heightSlider = UISlider()
    private let levelGainSlider = UISlider()
    private let smoothingSlider = UISlider()
    private let wobbleSlider = UISlider()
    private let heightFillSlider = UISlider()
    private let diamondSlider = UISlider()

    private var liveMeterHeightConstraint: NSLayoutConstraint?

    private let floatingDock = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let clipSelector = UISegmentedControl(items: (1...6).map { "\($0)" })
    private let fidelitySwitch = UISwitch()
    private let playButton = UIButton(type: .system)

    private let audioPlayer = MeteredAudioPlayer()
    private var selectedClipIndex = 0
    private var playingClipIndex: Int?
    private var lastLiveLevel: Float = 0
    private var lastBands: [Float] = Array(repeating: 0, count: MeteredAudioPlayer.bandCount)
    private var fidelityMode = true

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Speaking meters"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground

        audioPlayer.onPlaybackUpdate = { [weak self] frame in
            self?.pushPlayback(frame)
        }
        audioPlayer.onFinished = { [weak self] in
            self?.handlePlaybackFinished()
        }

        configureScrollView()
        configureMeters()
        configureFloatingDock()
        applyFidelityMode()
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

    private func configureMeters() {
        let intro = UILabel()
        intro.text = "Pick a clip and tap play. Fidelity mode drives bars from the live tap — player time, level history, and FFT bands."
        intro.font = .preferredFont(forTextStyle: .subheadline)
        intro.textColor = .secondaryLabel
        intro.numberOfLines = 0
        contentStack.addArrangedSubview(intro)

        configureLiveMeterCard()
    }

    private func configureLiveMeterCard() {
        levelBars.translatesAutoresizingMaskIntoConstraints = false
        levelBars.barColor = .systemYellow
        levelBars.barWidth = 8
        levelBars.barSpacing = 6
        levelBars.meterHeight = 77
        levelBars.minBarHeight = 8
        levelBars.heightFill = 0.82
        levelBars.levelGain = 0.6
        levelBars.displayCurve = 1.05
        levelBars.smoothing = 0.08
        levelBars.wobbleAmount = 0.25
        levelBars.diamondFalloff = 0.25

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

        fidelitySwitch.isOn = fidelityMode
        fidelitySwitch.addTarget(self, action: #selector(fidelityToggled), for: .valueChanged)

        let fidelityRow = UIStackView()
        fidelityRow.axis = .horizontal
        fidelityRow.alignment = .center
        fidelityRow.distribution = .equalSpacing
        let fidelityLabel = UILabel()
        fidelityLabel.text = "Fidelity mode"
        fidelityLabel.font = .preferredFont(forTextStyle: .subheadline)
        fidelityRow.addArrangedSubview(fidelityLabel)
        fidelityRow.addArrangedSubview(fidelitySwitch)

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
        dockStack.addArrangedSubview(fidelityRow)
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

        levelBars.releaseToRest()
        lastLiveLevel = 0
        lastBands = Array(repeating: 0, count: MeteredAudioPlayer.bandCount)

        let assetName = MeteredAudioPlayer.encouragementClipNames[index]
        audioPlayer.play(assetNamed: assetName)
    }

    private func pushPlayback(_ frame: PlaybackMeterFrame) {
        lastLiveLevel = frame.liveLevel
        lastBands = frame.bands

        if fidelityMode {
            levelBars.setBands(frame.bands)
            liveDebugLabel.text = String(
                format: "bands: %.2f %.2f %.2f %.2f %.2f",
                frame.bands.count > 0 ? frame.bands[0] : 0,
                frame.bands.count > 1 ? frame.bands[1] : 0,
                frame.bands.count > 2 ? frame.bands[2] : 0,
                frame.bands.count > 3 ? frame.bands[3] : 0,
                frame.bands.count > 4 ? frame.bands[4] : 0
            )
        } else {
            levelBars.setLevel(frame.liveLevel)
            liveDebugLabel.text = String(format: "live: %.2f", frame.liveLevel)
        }
    }

    private func handlePlaybackFinished() {
        playingClipIndex = nil
        updatePlayButtonAppearance()
        levelBars.releaseToRest()
        lastLiveLevel = 0
        lastBands = Array(repeating: 0, count: MeteredAudioPlayer.bandCount)
    }

    @objc private func fidelityToggled() {
        fidelityMode = fidelitySwitch.isOn
        applyFidelityMode()
        refreshLiveMeter()
    }

    private func applyFidelityMode() {
        levelBars.fidelityMode = fidelityMode
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
        if fidelityMode {
            levelBars.setBands(lastBands)
        } else {
            levelBars.setLevel(lastLiveLevel)
        }
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
