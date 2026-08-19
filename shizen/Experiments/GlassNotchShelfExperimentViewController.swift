//
//  GlassNotchShelfExperimentViewController.swift
//  shizen
//
//  DEBUG: glass hosted in the exclusion rect (behind the notch on Z) via TopNotchManager;
//  voice overlay morphs/peels out downward from that shelf.
//

import UIKit

final class GlassNotchShelfExperimentViewController: UIViewController {

    private let containerEffect: UIGlassContainerEffect = {
        let effect = UIGlassContainerEffect()
        effect.spacing = CGFloat(GlassNotchShelfExperimentViewController.defaultContainerSpacing)
        return effect
    }()
    private lazy var glassContainerView = UIVisualEffectView(effect: containerEffect)
    private let shelfGlassView = UIVisualEffectView(effect: UIGlassEffect(style: .clear))
    private let overlayGlassView = UIVisualEffectView(effect: UIGlassEffect(style: .clear))
    private let comboGlassView = UIVisualEffectView(effect: UIGlassEffect(style: .clear))
    private let praiseGlassView = UIVisualEffectView(effect: UIGlassEffect(style: .clear))
    private let speechBars = SpeechEnvelopeBarsView()
    private let comboBadge: EncouragementBadgeView
    private let praiseBadge: EncouragementBadgeView

    private let introLabel = UILabel()
    private let toggleButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let spacingSlider = UISlider()
    private let overlayGapSlider = UISlider()
    private let controlStack = UIStackView()

    private let audioPlayer = MeteredAudioPlayer()
    private let topNotchManager = TopNotchManager.shared
    private var isOverlayVisible = false
    private var isGlassAnimating = false
    private var usesTopNotchOverlay = false
    private var hostedExtensionHeight: CGFloat = 0
    private var glassContainerHeightConstraint: NSLayoutConstraint?
    private var wasNavigationBarHidden = false

    private static let spacingSliderMin: Float = 0
    private static let spacingSliderMax: Float = 120
    private static let defaultContainerSpacing: Float = 20
    private static let overlayGapSliderMin: Float = 0
    private static let overlayGapSliderMax: Float = 80
    private static let defaultOverlayGap: Float = 16
    private static let badgeStackGap: CGFloat = 16
    private static let badgeStackSpacing: CGFloat = 14
    private static let demoComboStreak = 5
    private static let comboFill = UIColor(red: 0.87, green: 0.94, blue: 1.0, alpha: 1)
    private static let comboText = UIColor(red: 0.05, green: 0.58, blue: 0.96, alpha: 1)
    private static let tensaiFill = UIColor(red: 1.0, green: 0.97, blue: 0.86, alpha: 1)
    private static let tensaiText = UIColor(red: 0.93, green: 0.72, blue: 0.0, alpha: 1)
    private static let glassInset: CGFloat = 8
    private static let shelfHeight: CGFloat = 38
    private static let expandedOverlayHeight: CGFloat = 68
    private static let expandedOverlayWidth: CGFloat = 150
    private static let shelfCornerRadius: CGFloat = 16
    private static let overlayCornerRadius: CGFloat = expandedOverlayHeight / 2
    private static let collapsedOverlayCornerRadius: CGFloat = shelfHeight / 2
    private static let badgeGlassCornerRadius: CGFloat = 24
    private static let fallbackNotchBandHeight: CGFloat = 54

    private var cachedComboBadgeSize: CGSize = .zero
    private var cachedPraiseBadgeSize: CGSize = .zero

    private var currentOverlayGap: CGFloat {
        CGFloat(overlayGapSlider.value)
    }

    private var collapsedExtensionHeight: CGFloat { 0 }

    private func expandedExtensionHeight(for gap: CGFloat) -> CGFloat {
        gap + Self.expandedOverlayHeight + badgeBlockHeight() + Self.glassInset
    }

    init() {
        comboBadge = EncouragementBadgeView(
            text: "COMBO \(Self.demoComboStreak)x!",
            fillColor: Self.comboFill,
            textColor: Self.comboText
        )
        praiseBadge = EncouragementBadgeView(
            text: KanaLessonEncouragementPhraseBank.randomPhrase(),
            fillColor: Self.tensaiFill,
            textColor: Self.tensaiText
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Notch shelf glass"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = ExperimentPalette.pageBackground

        audioPlayer.onPlaybackUpdate = { [weak self] frame in
            self?.speechBars.setPlayback(envelope: frame.envelope, at: frame.time, liveLevel: frame.liveLevel)
        }
        audioPlayer.onFinished = { [weak self] in
            self?.speechBars.releaseToRest()
            self?.statusLabel.text = "Overlay visible · idle"
        }

        configureIntro()
        configureGlassContainer()
        configureBadgeGlass()
        configureOverlayGlass()
        configureControls()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        wasNavigationBarHidden = navigationController?.isNavigationBarHidden ?? false
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installShelfOverlay()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        syncGlassFramesIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || isBeingDismissed {
            audioPlayer.stop()
            topNotchManager.hide()
            glassContainerView.removeFromSuperview()
            navigationController?.setNavigationBarHidden(wasNavigationBarHidden, animated: animated)
        }
    }

    private func configureIntro() {
        introLabel.font = .preferredFont(forTextStyle: .body)
        introLabel.textColor = .secondaryLabel
        introLabel.textAlignment = .center
        introLabel.numberOfLines = 0
        introLabel.text = "Glass sits behind the notch (exclusion rect).\nToggle to peel the voice meter and cascade badges out from underneath."
        introLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(introLabel)

        NSLayoutConstraint.activate([
            introLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            introLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            introLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
        ])
    }

    private func configureGlassContainer() {
        shelfGlassView.cornerConfiguration = .corners(radius: .fixed(Self.shelfCornerRadius))
        overlayGlassView.cornerConfiguration = .corners(radius: .fixed(Self.collapsedOverlayCornerRadius))

        glassContainerView.contentView.addSubview(overlayGlassView)
        glassContainerView.contentView.addSubview(comboGlassView)
        glassContainerView.contentView.addSubview(praiseGlassView)
        glassContainerView.contentView.addSubview(shelfGlassView)
        shelfGlassView.translatesAutoresizingMaskIntoConstraints = true
        overlayGlassView.translatesAutoresizingMaskIntoConstraints = true
        comboGlassView.translatesAutoresizingMaskIntoConstraints = true
        praiseGlassView.translatesAutoresizingMaskIntoConstraints = true
        hostedExtensionHeight = collapsedExtensionHeight
    }

    private func configureBadgeGlass() {
        comboGlassView.cornerConfiguration = .corners(radius: .fixed(Self.badgeGlassCornerRadius))
        praiseGlassView.cornerConfiguration = .corners(radius: .fixed(Self.badgeGlassCornerRadius))

        comboBadge.translatesAutoresizingMaskIntoConstraints = false
        praiseBadge.translatesAutoresizingMaskIntoConstraints = false

        comboGlassView.contentView.addSubview(comboBadge)
        praiseGlassView.contentView.addSubview(praiseBadge)

        NSLayoutConstraint.activate([
            comboBadge.topAnchor.constraint(equalTo: comboGlassView.contentView.topAnchor),
            comboBadge.leadingAnchor.constraint(equalTo: comboGlassView.contentView.leadingAnchor),
            comboBadge.trailingAnchor.constraint(equalTo: comboGlassView.contentView.trailingAnchor),
            comboBadge.bottomAnchor.constraint(equalTo: comboGlassView.contentView.bottomAnchor),

            praiseBadge.topAnchor.constraint(equalTo: praiseGlassView.contentView.topAnchor),
            praiseBadge.leadingAnchor.constraint(equalTo: praiseGlassView.contentView.leadingAnchor),
            praiseBadge.trailingAnchor.constraint(equalTo: praiseGlassView.contentView.trailingAnchor),
            praiseBadge.bottomAnchor.constraint(equalTo: praiseGlassView.contentView.bottomAnchor),
        ])

        ensureContentZOrder()
    }

    private func ensureContentZOrder() {
        glassContainerView.contentView.sendSubviewToBack(shelfGlassView)
        glassContainerView.contentView.bringSubviewToFront(comboGlassView)
        glassContainerView.contentView.bringSubviewToFront(praiseGlassView)
        glassContainerView.contentView.bringSubviewToFront(overlayGlassView)
    }

    private func installShelfOverlay() {
        glassContainerView.removeFromSuperview()
        glassContainerHeightConstraint?.isActive = false

        if TopNotchManager.exclusionRect != .zero {
            usesTopNotchOverlay = true
            glassContainerView.translatesAutoresizingMaskIntoConstraints = true
            glassContainerView.backgroundColor = .clear
            var config = TopNotchConfiguration()
            config.shouldHideForTaskSwitcher = true
            topNotchManager.show(
                customView: glassContainerView,
                extensionHeight: hostedExtensionHeight,
                configuration: config,
                windowScene: view.window?.windowScene
            )
            printGlassLayout(context: "installShelfOverlay")
            statusLabel.text = "Glass behind notch · exclusion rect"
        } else {
            usesTopNotchOverlay = false
            glassContainerView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(glassContainerView)
            glassContainerHeightConstraint = glassContainerView.heightAnchor.constraint(
                equalToConstant: Self.fallbackNotchBandHeight + Self.shelfHeight
            )
            NSLayoutConstraint.activate([
                glassContainerView.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.fallbackNotchBandHeight),
                glassContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                glassContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                glassContainerHeightConstraint!,
            ])
            print("[GlassNotchShelf] installShelfOverlay — no exclusion rect, using fallback band")
            statusLabel.text = "No exclusion rect — using safe-area fallback"
        }

        syncGlassFramesIfNeeded()
    }

    private func printGlassLayout(context: String) {
        let containerBounds = glassContainerView.bounds
        let contentBounds = glassContainerView.contentView.bounds
        let shelfFrame = shelfGlassFrame()
        let exclusion = topNotchManager.adjustedExclusionFrame

        print("[GlassNotchShelf] — \(context) —")
        print("[GlassNotchShelf]   adjustedExclusionFrame: \(exclusion)")
        print("[GlassNotchShelf]   topNotchManager.extensionHeight: \(topNotchManager.extensionHeight)")
        print("[GlassNotchShelf]   glassContainerView.bounds: \(containerBounds)")
        print("[GlassNotchShelf]   glassContainerView.frame: \(glassContainerView.frame)")
        print("[GlassNotchShelf]   glassContainerView.screenFrame: \(glassContainerView.convert(glassContainerView.bounds, to: nil))")
        print("[GlassNotchShelf]   contentView.bounds: \(contentBounds)")
        print("[GlassNotchShelf]   shelfGlassView.frame: \(shelfFrame)")
        print("[GlassNotchShelf]   overlayGlassView.frame: \(overlayGlassView.frame)")
        print("[GlassNotchShelf]   isOverlayVisible: \(isOverlayVisible) isGlassAnimating: \(isGlassAnimating)")
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

    private func updateHostedExtensionHeight(_ height: CGFloat) {
        hostedExtensionHeight = height
        if usesTopNotchOverlay {
            topNotchManager.updateExtensionHeight(height)
            printGlassLayout(context: "updateHostedExtensionHeight(\(height))")
        } else {
            glassContainerHeightConstraint?.constant = Self.fallbackNotchBandHeight + Self.shelfHeight + height
            view.layoutIfNeeded()
        }
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

        let height = expandedExtensionHeight(for: currentOverlayGap)
        let updates = {
            self.updateHostedExtensionHeight(height)
            self.syncGlassFramesIfNeeded()
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
        statusLabel.text = "Peeling out…"

        speechBars.reset()

        UIView.performWithoutAnimation {
            self.updateHostedExtensionHeight(self.expandedExtensionHeight(for: self.currentOverlayGap))
            self.glassContainerView.layoutIfNeeded()
            self.applyCollapsedGlassLayout()
            self.speechBars.alpha = 0
        }

        let shelfFrame = shelfGlassFrame()
        let expandedOverlayFrame = overlayExpandedFrame(basedOn: shelfFrame)
        let expandedBadgeFrames = badgeGlassFrames(basedOn: expandedOverlayFrame)

        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            usingSpringWithDamping: 0.7,
            initialSpringVelocity: 0.5
        ) {
            self.overlayGlassView.frame = expandedOverlayFrame
            self.overlayGlassView.cornerConfiguration = .corners(radius: .fixed(Self.overlayCornerRadius))
            self.comboGlassView.frame = expandedBadgeFrames.combo
            self.praiseGlassView.frame = expandedBadgeFrames.praise
            self.speechBars.alpha = 1
        } completion: { _ in
            self.comboBadge.playEntryShimmer()
            self.praiseBadge.playEntryShimmer()
            self.isGlassAnimating = false
            self.printGlassLayout(context: "showOverlay complete")
            self.statusLabel.text = "Playing encouragement clip"
            self.audioPlayer.play(assetNamed: MeteredAudioPlayer.encouragementClipNames[0])
        }
    }

    private func hideOverlay() {
        isGlassAnimating = true
        isOverlayVisible = false
        updateToggleButtonTitle()
        statusLabel.text = "Tucking back…"
        audioPlayer.stop()
        speechBars.releaseToRest()

        let collapsedFrame = overlayCollapsedFrame(basedOn: shelfGlassFrame())

        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            usingSpringWithDamping: 0.7,
            initialSpringVelocity: 0.5
        ) {
            self.overlayGlassView.frame = collapsedFrame
            self.overlayGlassView.cornerConfiguration = .corners(radius: .fixed(Self.collapsedOverlayCornerRadius))
            self.comboGlassView.frame = collapsedFrame
            self.praiseGlassView.frame = collapsedFrame
            self.speechBars.alpha = 0
        } completion: { _ in
            UIView.performWithoutAnimation {
                self.updateHostedExtensionHeight(self.collapsedExtensionHeight)
                self.syncGlassFramesIfNeeded()
            }
            self.isGlassAnimating = false
            self.printGlassLayout(context: "hideOverlay complete")
            self.statusLabel.text = "Voice overlay tucked under shelf"
        }
    }

    private func applyCollapsedGlassLayout() {
        let shelfFrame = shelfGlassFrame()
        let collapsedFrame = overlayCollapsedFrame(basedOn: shelfFrame)

        shelfGlassView.frame = shelfFrame
        if usesTopNotchOverlay {
            let radius = topNotchManager.adjustedExclusionFrame.height / 2
            shelfGlassView.cornerConfiguration = .corners(radius: .fixed(radius))
        }

        overlayGlassView.frame = collapsedFrame
        overlayGlassView.cornerConfiguration = .corners(radius: .fixed(Self.collapsedOverlayCornerRadius))
        comboGlassView.frame = collapsedFrame
        praiseGlassView.frame = collapsedFrame
        ensureContentZOrder()
    }

    private func applyExpandedGlassLayout(basedOn shelfFrame: CGRect) {
        if usesTopNotchOverlay {
            let radius = topNotchManager.adjustedExclusionFrame.height / 2
            shelfGlassView.cornerConfiguration = .corners(radius: .fixed(radius))
        }
        shelfGlassView.frame = shelfFrame

        let overlayFrame = overlayExpandedFrame(basedOn: shelfFrame)
        let badgeFrames = badgeGlassFrames(basedOn: overlayFrame)

        overlayGlassView.frame = overlayFrame
        overlayGlassView.cornerConfiguration = .corners(radius: .fixed(Self.overlayCornerRadius))
        comboGlassView.frame = badgeFrames.combo
        praiseGlassView.frame = badgeFrames.praise
        speechBars.alpha = 1
        ensureContentZOrder()
    }

    private func badgeGlassFrames(basedOn overlayFrame: CGRect) -> (combo: CGRect, praise: CGRect) {
        let comboSize = measuredBadgeSize(comboBadge)
        let praiseSize = measuredBadgeSize(praiseBadge)

        let comboFrame = CGRect(
            x: overlayFrame.midX - comboSize.width / 2,
            y: overlayFrame.maxY + Self.badgeStackGap,
            width: comboSize.width,
            height: comboSize.height
        )
        let praiseFrame = CGRect(
            x: overlayFrame.midX - praiseSize.width / 2,
            y: comboFrame.maxY + Self.badgeStackSpacing,
            width: praiseSize.width,
            height: praiseSize.height
        )
        return (comboFrame, praiseFrame)
    }

    private func badgeBlockHeight() -> CGFloat {
        refreshBadgeSizeCacheIfNeeded()
        return Self.badgeStackGap
            + cachedComboBadgeSize.height
            + Self.badgeStackSpacing
            + cachedPraiseBadgeSize.height
    }

    private func refreshBadgeSizeCacheIfNeeded() {
        guard cachedComboBadgeSize == .zero else { return }
        let maxWidth = max(view.bounds.width, UIScreen.main.bounds.width) - 32
        cachedComboBadgeSize = measuredBadgeSize(comboBadge, maxWidth: maxWidth)
        cachedPraiseBadgeSize = measuredBadgeSize(praiseBadge, maxWidth: maxWidth)
    }

    private func measuredBadgeSize(_ badge: EncouragementBadgeView, maxWidth: CGFloat? = nil) -> CGSize {
        let limit = maxWidth ?? max(glassContainerView.contentView.bounds.width, view.bounds.width) - 32
        return badge.systemLayoutSizeFitting(
            CGSize(width: max(limit, 100), height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel
        )
    }

    private func syncGlassFramesIfNeeded() {
        guard glassContainerView.bounds.width > 0 else { return }
        guard !isGlassAnimating else { return }

        let shelfFrame = shelfGlassFrame()

        if !isOverlayVisible {
            updateHostedExtensionHeight(collapsedExtensionHeight)
            applyCollapsedGlassLayout()
        } else {
            applyExpandedGlassLayout(basedOn: shelfFrame)
        }
    }

    private func shelfGlassFrame() -> CGRect {
        let contentBounds = glassContainerView.contentView.bounds

        if usesTopNotchOverlay {
            let exclusion = topNotchManager.adjustedExclusionFrame
            if extensionHeight > 0 {
                return CGRect(
                    x: exclusion.origin.x,
                    y: 0,
                    width: exclusion.width,
                    height: exclusion.height
                )
            }
            return CGRect(x: 0, y: 0, width: contentBounds.width, height: contentBounds.height)
        }

        return CGRect(
            x: Self.glassInset,
            y: Self.glassInset,
            width: contentBounds.width - Self.glassInset * 2,
            height: Self.shelfHeight
        )
    }

    private var extensionHeight: CGFloat {
        usesTopNotchOverlay ? topNotchManager.extensionHeight : hostedExtensionHeight
    }

    private func overlayCollapsedFrame(basedOn shelfFrame: CGRect) -> CGRect {
        let height = usesTopNotchOverlay ? shelfFrame.height : Self.shelfHeight
        if usesTopNotchOverlay, extensionHeight > 0 {
            let width = min(Self.expandedOverlayWidth, shelfFrame.width)
            let originX = shelfFrame.midX - width / 2
            return CGRect(x: originX, y: shelfFrame.origin.y, width: width, height: height)
        }
        return centeredOverlayFrame(originY: shelfFrame.origin.y, height: height)
    }

    private func overlayExpandedFrame(basedOn shelfFrame: CGRect) -> CGRect {
        centeredOverlayFrame(
            originY: shelfFrame.maxY + currentOverlayGap,
            height: Self.expandedOverlayHeight
        )
    }

    private func centeredOverlayFrame(originY: CGFloat, height: CGFloat) -> CGRect {
        let contentBounds = glassContainerView.contentView.bounds
        let width = min(Self.expandedOverlayWidth, contentBounds.width)
        let originX = (contentBounds.width - width) / 2
        return CGRect(x: originX, y: originY, width: width, height: height)
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
}
