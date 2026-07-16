//
//  GlassProgressVoiceOverlayExperimentViewController.swift
//  shizen
//
//  DEBUG: UIKit Liquid Glass morphing — UIGlassContainerEffect with spacing,
//  sibling UIGlassEffect views placed at the same frame, then animated apart
//  (WWDC25 “Build a UIKit app with the new design” pattern).
//

import UIKit

final class GlassProgressVoiceOverlayExperimentViewController: UIViewController {

    private let containerEffect: UIGlassContainerEffect = {
        let effect = UIGlassContainerEffect()
        effect.spacing = CGFloat(GlassProgressVoiceOverlayExperimentViewController.defaultContainerSpacing)
        return effect
    }()
    private lazy var glassContainerView = UIVisualEffectView(effect: containerEffect)
    private let progressGlassView = UIVisualEffectView(effect: UIGlassEffect(style: .clear))
    private let overlayGlassView = UIVisualEffectView(effect: UIGlassEffect(style: .clear))
    private let speechBars = SpeechEnvelopeBarsView()

    private let progressView = UIProgressView(progressViewStyle: .bar)

    private let toggleButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let spacingSlider = UISlider()
    private let overlayGapSlider = UISlider()
    private let controlStack = UIStackView()

    private let audioPlayer = MeteredAudioPlayer()
    private var isOverlayVisible = false
    private var isGlassAnimating = false
    private var glassContainerHeightConstraint: NSLayoutConstraint?

    private static let spacingSliderMin: Float = 0
    private static let spacingSliderMax: Float = 120
    private static let defaultContainerSpacing: Float = 20
    private static let overlayGapSliderMin: Float = 0
    private static let overlayGapSliderMax: Float = 80
    private static let defaultOverlayGap: Float = 16
    private static let progressBarHeight: CGFloat = 6
    private static let progressHorizontalInset: CGFloat = 12
    private static let progressVerticalInset: CGFloat = 14
    private static let glassInset: CGFloat = 8
    private static let progressRowHeight: CGFloat = progressBarHeight + progressVerticalInset * 2
    private static let expandedOverlayHeight: CGFloat = 68
    private static let expandedOverlayWidth: CGFloat = 150
    private static let glassCornerRadius: CGFloat = 12
    private static let overlayCornerRadius: CGFloat = expandedOverlayHeight / 2
    private static let collapsedOverlayCornerRadius: CGFloat = progressRowHeight / 2
    private static let collapsedContainerHeight: CGFloat = glassInset * 2 + progressRowHeight

    private var currentOverlayGap: CGFloat {
        CGFloat(overlayGapSlider.value)
    }

    private func expandedContainerHeight(for gap: CGFloat) -> CGFloat {
        Self.glassInset + Self.progressRowHeight + gap + Self.expandedOverlayHeight + Self.glassInset
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Glass progress + voice"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground

        audioPlayer.onPlaybackUpdate = { [weak self] time, envelope, liveLevel in
            self?.speechBars.setPlayback(envelope: envelope, at: time, liveLevel: liveLevel)
        }
        audioPlayer.onFinished = { [weak self] in
            self?.speechBars.releaseToRest()
            self?.statusLabel.text = "Overlay visible · idle"
        }

        configureGlassContainer()
        configureProgressHeader()
        configureOverlayGlass()
        configureControls()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyRoundedProgressAppearance()
        syncGlassFramesIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || isBeingDismissed {
            audioPlayer.stop()
        }
    }

    private func configureGlassContainer() {
        glassContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(glassContainerView)

        progressGlassView.cornerConfiguration = .corners(radius: .fixed(Self.glassCornerRadius))
        overlayGlassView.cornerConfiguration = .corners(radius: .fixed(Self.glassCornerRadius))

        glassContainerView.contentView.addSubview(overlayGlassView)
        glassContainerView.contentView.addSubview(progressGlassView)
        progressGlassView.translatesAutoresizingMaskIntoConstraints = true
        overlayGlassView.translatesAutoresizingMaskIntoConstraints = true

        glassContainerHeightConstraint = glassContainerView.heightAnchor.constraint(
            equalToConstant: Self.collapsedContainerHeight
        )

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            glassContainerView.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            glassContainerView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            glassContainerView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            glassContainerHeightConstraint!,
        ])
    }

    private func configureProgressHeader() {
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progressTintColor = .systemYellow
        progressView.trackTintColor = ExperimentPalette.progressBarTrack
        progressView.clipsToBounds = true
        progressView.setProgress(0.3, animated: false)

        progressGlassView.contentView.addSubview(progressView)

        NSLayoutConstraint.activate([
            progressView.leadingAnchor.constraint(
                equalTo: progressGlassView.contentView.leadingAnchor,
                constant: Self.progressHorizontalInset
            ),
            progressView.trailingAnchor.constraint(
                equalTo: progressGlassView.contentView.trailingAnchor,
                constant: -Self.progressHorizontalInset
            ),
            progressView.centerYAnchor.constraint(equalTo: progressGlassView.contentView.centerYAnchor),
            progressView.heightAnchor.constraint(equalToConstant: Self.progressBarHeight),
        ])
    }

    private func configureOverlayGlass() {
        applySpeechProfilePreset()

        speechBars.translatesAutoresizingMaskIntoConstraints = false
        speechBars.alpha = 0

        overlayGlassView.contentView.addSubview(speechBars)
        NSLayoutConstraint.activate([
            speechBars.centerXAnchor.constraint(equalTo: overlayGlassView.contentView.centerXAnchor),
            speechBars.centerYAnchor.constraint(equalTo: overlayGlassView.contentView.centerYAnchor),
            speechBars.leadingAnchor.constraint(
                greaterThanOrEqualTo: overlayGlassView.contentView.leadingAnchor,
                constant: 20
            ),
            speechBars.trailingAnchor.constraint(
                lessThanOrEqualTo: overlayGlassView.contentView.trailingAnchor,
                constant: -20
            ),
        ])
    }

    private func configureControls() {
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .tertiaryLabel
        statusLabel.textAlignment = .center
        statusLabel.text = "Voice overlay merged into progress bar"

        spacingSlider.minimumValue = Self.spacingSliderMin
        spacingSlider.maximumValue = Self.spacingSliderMax
        spacingSlider.value = Self.defaultContainerSpacing
        spacingSlider.addTarget(self, action: #selector(spacingChanged), for: .valueChanged)
        applyContainerSpacing()

        overlayGapSlider.minimumValue = Self.overlayGapSliderMin
        overlayGapSlider.maximumValue = Self.overlayGapSliderMax
        overlayGapSlider.value = Self.defaultOverlayGap
        overlayGapSlider.addTarget(self, action: #selector(overlayGapChanged), for: .valueChanged)

        var toggleConfig = UIButton.Configuration.filled()
        toggleConfig.cornerStyle = .capsule
        toggleConfig.title = "Show voice overlay"
        toggleConfig.image = UIImage(systemName: "waveform.circle.fill")
        toggleConfig.imagePadding = 8
        toggleConfig.baseBackgroundColor = .systemBlue
        toggleButton.configuration = toggleConfig
        toggleButton.addTarget(self, action: #selector(toggleOverlayTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            ExperimentSliderRow.make(
                title: "Container spacing",
                slider: spacingSlider,
                format: "%.0f"
            ),
            ExperimentSliderRow.make(
                title: "Overlay drop",
                slider: overlayGapSlider,
                format: "%.0f"
            ),
            statusLabel,
            toggleButton,
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
            toggleButton.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    @objc private func spacingChanged() {
        applyContainerSpacing()
    }

    @objc private func overlayGapChanged() {
        applyOverlayGap(animated: isOverlayVisible && !isGlassAnimating)
    }

    private func applyContainerSpacing() {
        containerEffect.spacing = CGFloat(spacingSlider.value)
        glassContainerView.effect = containerEffect
        view.setNeedsLayout()
    }

    private func applyOverlayGap(animated: Bool) {
        guard isOverlayVisible else { return }

        glassContainerHeightConstraint?.constant = expandedContainerHeight(for: currentOverlayGap)

        let updates = {
            self.syncGlassFramesIfNeeded()
            self.view.layoutIfNeeded()
        }

        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut], animations: updates)
        } else {
            updates()
        }
    }

    @objc private func toggleOverlayTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if isOverlayVisible {
            hideOverlay()
        } else {
            showOverlay()
        }
    }

    private func showOverlay() {
        isGlassAnimating = true
        isOverlayVisible = true
        updateToggleButtonTitle()
        statusLabel.text = "Dividing glass…"

        let progressFrame = progressGlassFrame()
        speechBars.reset()

        UIView.performWithoutAnimation {
            self.progressGlassView.frame = progressFrame
            self.overlayGlassView.frame = self.overlayCollapsedFrame(basedOn: progressFrame)
            self.overlayGlassView.cornerConfiguration = .corners(radius: .fixed(Self.collapsedOverlayCornerRadius))
            self.speechBars.alpha = 0
        }

        glassContainerHeightConstraint?.constant = expandedContainerHeight(for: currentOverlayGap)

        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            usingSpringWithDamping: 0.7,
            initialSpringVelocity: 0.5
        ) {
            self.overlayGlassView.frame = self.overlayExpandedFrame(basedOn: progressFrame)
            self.overlayGlassView.cornerConfiguration = .corners(radius: .fixed(Self.overlayCornerRadius))
            self.speechBars.alpha = 1
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.isGlassAnimating = false
            self.statusLabel.text = "Playing encouragement clip"
            self.audioPlayer.play(assetNamed: MeteredAudioPlayer.encouragementClipNames[0])
        }
    }

    private func hideOverlay() {
        isGlassAnimating = true
        isOverlayVisible = false
        updateToggleButtonTitle()
        statusLabel.text = "Merging glass…"
        audioPlayer.stop()
        speechBars.releaseToRest()

        let progressFrame = progressGlassFrame()
        glassContainerHeightConstraint?.constant = Self.collapsedContainerHeight

        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            usingSpringWithDamping: 0.7,
            initialSpringVelocity: 0.5
        ) {
            self.overlayGlassView.frame = self.overlayCollapsedFrame(basedOn: progressFrame)
            self.overlayGlassView.cornerConfiguration = .corners(radius: .fixed(Self.collapsedOverlayCornerRadius))
            self.speechBars.alpha = 0
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.isGlassAnimating = false
            self.statusLabel.text = "Voice overlay merged into progress bar"
        }
    }

    /// Keeps progress pinned and re-syncs the overlay when not mid-transition.
    private func syncGlassFramesIfNeeded() {
        guard glassContainerView.bounds.width > 0 else { return }

        let progressFrame = progressGlassFrame()
        progressGlassView.frame = progressFrame

        guard !isGlassAnimating else { return }

        if isOverlayVisible {
            overlayGlassView.frame = overlayExpandedFrame(basedOn: progressFrame)
            overlayGlassView.cornerConfiguration = .corners(radius: .fixed(Self.overlayCornerRadius))
        } else {
            overlayGlassView.frame = overlayCollapsedFrame(basedOn: progressFrame)
            overlayGlassView.cornerConfiguration = .corners(radius: .fixed(Self.collapsedOverlayCornerRadius))
        }
    }

    private func overlayCollapsedFrame(basedOn progressFrame: CGRect) -> CGRect {
        centeredOverlayFrame(
            originY: progressFrame.origin.y,
            height: Self.progressRowHeight
        )
    }

    private func overlayExpandedFrame(basedOn progressFrame: CGRect) -> CGRect {
        centeredOverlayFrame(
            originY: progressFrame.maxY + currentOverlayGap,
            height: Self.expandedOverlayHeight
        )
    }

    private func centeredOverlayFrame(originY: CGFloat, height: CGFloat) -> CGRect {
        let contentBounds = glassContainerView.contentView.bounds
        let originX = (contentBounds.width - Self.expandedOverlayWidth) / 2
        return CGRect(
            x: originX,
            y: originY,
            width: Self.expandedOverlayWidth,
            height: height
        )
    }

    private func progressGlassFrame() -> CGRect {
        let contentBounds = glassContainerView.contentView.bounds
        return CGRect(
            x: Self.glassInset,
            y: Self.glassInset,
            width: contentBounds.width - Self.glassInset * 2,
            height: Self.progressRowHeight
        )
    }

    private func updateToggleButtonTitle() {
        var config = toggleButton.configuration
        config?.title = isOverlayVisible ? "Hide voice overlay" : "Show voice overlay"
        config?.image = UIImage(systemName: isOverlayVisible ? "waveform.slash" : "waveform.circle.fill")
        toggleButton.configuration = config
    }

    private func applySpeechProfilePreset() {
        speechBars.barColor = .systemBlue
        speechBars.barWidth = 7
        speechBars.barSpacing = 10
        speechBars.minBarHeight = 6
        speechBars.heightFill = 0.94
        speechBars.envelopeGain = sliderValue(min: 0.4, max: 3.5, percent: 0.10)
        speechBars.liveGain = sliderValue(min: 0.4, max: 3.5, percent: 0.80)
        speechBars.attackGain = sliderValue(min: 0, max: 3.5, percent: 0.80)
        speechBars.smoothing = CGFloat(sliderValue(min: 0.08, max: 0.75, percent: 0.30))
        speechBars.diamondFalloff = 0.75
        speechBars.meterHeight = Self.expandedOverlayHeight * 0.45
    }

    private func sliderValue(min: Float, max: Float, percent: Float) -> Float {
        min + percent * (max - min)
    }

    private func applyRoundedProgressAppearance() {
        let radius = progressView.bounds.height / 2
        progressView.layer.cornerRadius = radius
        for subview in progressView.subviews {
            subview.clipsToBounds = true
            subview.layer.cornerRadius = radius
        }
    }
}
