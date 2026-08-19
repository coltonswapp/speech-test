//
//  SpeechProfileOverlayExperimentViewController.swift
//  shizen
//
//  DEBUG: speech-profile meter in a liquid-glass capsule that slides in while
//  encouragement audio plays, then retreats off screen the same way it entered.
//

import UIKit

final class SpeechProfileOverlayExperimentViewController: UIViewController {

    private let overlay = SpeechProfileGlassOverlay()
    private let introLabel = UILabel()
    private let edgeSelector = UISegmentedControl(items: ["From top", "From bottom"])
    private let colorSelector = UISegmentedControl(items: ["Yellow", "Blue"])
    private let widthSlider = UISlider()
    private let heightSlider = UISlider()
    private let clipSelector = UISegmentedControl(items: (1...6).map { "\($0)" })
    private let playButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    private let controlStack = UIStackView()
    private let audioPlayer = MeteredAudioPlayer()
    private var selectedClipIndex = 0
    private var entryEdge: SpeechProfileOverlayEdge = .top

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Speech profile overlay"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground

        audioPlayer.onPlaybackUpdate = { [weak self] frame in
            self?.overlay.pushPlayback(envelope: frame.envelope, at: frame.time, liveLevel: frame.liveLevel)
        }
        audioPlayer.onFinished = { [weak self] in
            self?.handlePlaybackFinished()
        }

        configureUI()
        reinstallOverlay()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || isBeingDismissed {
            audioPlayer.stop()
            overlay.dismiss()
        }
    }

    private func configureUI() {
        introLabel.font = .preferredFont(forTextStyle: .body)
        introLabel.textColor = .secondaryLabel
        introLabel.numberOfLines = 0
        introLabel.textAlignment = .center
        updateIntroCopy()

        edgeSelector.selectedSegmentIndex = 0
        edgeSelector.addTarget(self, action: #selector(edgeChanged), for: .valueChanged)

        colorSelector.selectedSegmentIndex = 1
        colorSelector.addTarget(self, action: #selector(colorChanged), for: .valueChanged)
        applySelectedBarColor()

        configureSlider(
            widthSlider,
            min: Float(SpeechProfileGlassOverlay.Style.sizeSliderMin),
            max: Float(SpeechProfileGlassOverlay.Style.sizeSliderMax),
            value: Float(SpeechProfileGlassOverlay.Style.defaultWidth),
            action: #selector(sizeChanged)
        )
        configureSlider(
            heightSlider,
            min: Float(SpeechProfileGlassOverlay.Style.sizeSliderMin),
            max: Float(SpeechProfileGlassOverlay.Style.sizeSliderMax),
            value: Float(SpeechProfileGlassOverlay.Style.defaultHeight),
            action: #selector(sizeChanged)
        )
        applyCapsuleSize()

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .tertiaryLabel
        statusLabel.textAlignment = .center
        statusLabel.text = "Idle"

        clipSelector.selectedSegmentIndex = selectedClipIndex
        clipSelector.addTarget(self, action: #selector(clipChanged), for: .valueChanged)

        var playConfig = UIButton.Configuration.filled()
        playConfig.cornerStyle = .capsule
        playConfig.image = UIImage(systemName: "play.fill")
        playConfig.imagePadding = 8
        playConfig.title = "Play clip 1"
        playConfig.baseBackgroundColor = .systemYellow
        playConfig.baseForegroundColor = .black
        playButton.configuration = playConfig
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            introLabel,
            edgeSelector,
            colorSelector,
            ExperimentSliderRow.make(title: "Capsule width", slider: widthSlider, format: "%.0f"),
            ExperimentSliderRow.make(title: "Capsule height", slider: heightSlider, format: "%.0f"),
            clipSelector,
            playButton,
            statusLabel,
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        controlStack.axis = .vertical
        controlStack.translatesAutoresizingMaskIntoConstraints = false
        controlStack.addArrangedSubview(stack)
        view.addSubview(controlStack)

        NSLayoutConstraint.activate([
            controlStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            controlStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            controlStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            playButton.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    private func reinstallOverlay() {
        overlay.install(in: view, edge: entryEdge)
    }

    private func updateIntroCopy() {
        switch entryEdge {
        case .top:
            introLabel.text = "Tap play — the meter drops in from the top, holds while the clip plays, then slides back up off screen."
        case .bottom:
            introLabel.text = "Tap play — the meter rises from the bottom, holds while the clip plays, then slides back down off screen."
        }
    }

    @objc private func edgeChanged() {
        entryEdge = edgeSelector.selectedSegmentIndex == 0 ? .top : .bottom
        updateIntroCopy()
        reinstallOverlay()
    }

    @objc private func colorChanged() {
        applySelectedBarColor()
    }

    @objc private func sizeChanged() {
        applyCapsuleSize()
    }

    @objc private func clipChanged() {
        selectedClipIndex = clipSelector.selectedSegmentIndex
        updatePlayButtonTitle()
    }

    @objc private func playTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if audioPlayer.isPlaying {
            audioPlayer.stop()
            handlePlaybackFinished()
            return
        }

        startPlayback()
    }

    private func startPlayback() {
        overlay.prepareForPlayback()
        statusLabel.text = "Presenting…"
        updatePlayButtonTitle(isPlaying: true)

        overlay.present { [weak self] in
            guard let self else { return }
            let assetName = MeteredAudioPlayer.encouragementClipNames[self.selectedClipIndex]
            self.statusLabel.text = "Playing clip \(self.selectedClipIndex + 1)"
            self.audioPlayer.play(assetNamed: assetName)
        }
    }

    private func handlePlaybackFinished() {
        statusLabel.text = "Settling…"
        updatePlayButtonTitle(isPlaying: false)

        overlay.releaseToRest { [weak self] in
            guard let self else { return }
            self.statusLabel.text = "Dismissing…"
            self.overlay.dismiss { [weak self] in
                self?.statusLabel.text = "Idle"
            }
        }
    }

    private func updatePlayButtonTitle(isPlaying: Bool? = nil) {
        let playing = isPlaying ?? audioPlayer.isPlaying
        let clipNumber = selectedClipIndex + 1
        var config = playButton.configuration
        config?.title = playing ? "Stop clip \(clipNumber)" : "Play clip \(clipNumber)"
        config?.image = UIImage(systemName: playing ? "stop.fill" : "play.fill")
        playButton.configuration = config
    }

    private func applySelectedBarColor() {
        let color: UIColor = colorSelector.selectedSegmentIndex == 0 ? .systemYellow : .systemBlue
        overlay.setBarColor(color)
    }

    private func applyCapsuleSize() {
        overlay.setCapsuleSize(
            width: CGFloat(widthSlider.value),
            height: CGFloat(heightSlider.value)
        )
    }

    private func configureSlider(_ slider: UISlider, min: Float, max: Float, value: Float, action: Selector) {
        slider.minimumValue = min
        slider.maximumValue = max
        slider.value = value
        slider.addTarget(self, action: action, for: .valueChanged)
    }
}
