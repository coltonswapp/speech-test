//
//  NotchDropPresenter.swift
//  shizen
//
//  Presents glass panels that peel out from the notch for streaks, life changes, etc.
//

import UIKit

enum NotchDropContent {
    /// Voice meter peels from the notch and plays a tutor encouragement clip — no combo screen.
    case encouragement(clipIndex: Int)
    /// Full streak presentation with combo + praise badges (debug / experiments).
    case streak(comboCount: Int, praisePhrase: String)
    case lifeLost(remaining: Int)
    case points(amount: Int)
}

struct NotchDropStyle {
    var containerSpacing: CGFloat = 20
    var firstRowGap: CGFloat = 16
    var rowSpacing: CGFloat = 14
    var bottomInset: CGFloat = 8
    var voiceMeterWidth: CGFloat = 150
    var voiceMeterHeight: CGFloat = 68
    var showDuration: TimeInterval = 0.5
    var displayDuration: TimeInterval = 2.8
    var springDamping: CGFloat = 0.7
}

final class NotchDropPresenter {

    var style = NotchDropStyle()
    private(set) var isPresenting = false

    private let topNotchManager = TopNotchManager.shared
    private let audioPlayer = MeteredAudioPlayer()

    private let containerEffect = UIGlassContainerEffect()
    private lazy var glassContainerView = UIVisualEffectView(effect: containerEffect)
    private let shelfGlassView = UIVisualEffectView(effect: UIGlassEffect(style: .clear))
    private let speechBars = SpeechEnvelopeBarsView()

    private var rowGlassViews: [UIVisualEffectView] = []
    private var rowBadges: [EncouragementBadgeView] = []
    private var isAnimating = false
    private var isExpanded = false
    private var dismissWorkItem: DispatchWorkItem?
    private var preferredWindowScene: UIWindowScene?
    private var currentContent: NotchDropContent?
    private var onDidDismiss: (() -> Void)?
    private var autoDismissWhenFinished = true

    private static let comboFill = UIColor(red: 0.87, green: 0.94, blue: 1.0, alpha: 1)
    private static let comboText = UIColor(red: 0.05, green: 0.58, blue: 0.96, alpha: 1)
    private static let tensaiFill = UIColor(red: 1.0, green: 0.97, blue: 0.86, alpha: 1)
    private static let tensaiText = UIColor(red: 0.93, green: 0.72, blue: 0.0, alpha: 1)
    private static let lifeLostFill = UIColor(red: 1.0, green: 0.92, blue: 0.92, alpha: 1)
    private static let pointsFill = UIColor(red: 0.90, green: 1.0, blue: 0.92, alpha: 1)

    init() {
        containerEffect.spacing = style.containerSpacing
        shelfGlassView.translatesAutoresizingMaskIntoConstraints = true
        glassContainerView.translatesAutoresizingMaskIntoConstraints = true
        speechBars.translatesAutoresizingMaskIntoConstraints = false
        speechBars.alpha = 0
        configureSpeechBars()
    }

    func present(
        _ content: NotchDropContent,
        windowScene: UIWindowScene,
        onDismiss: (() -> Void)? = nil,
        autoDismissWhenFinished: Bool = true
    ) {
        onDidDismiss = onDismiss
        self.autoDismissWhenFinished = autoDismissWhenFinished

        guard TopNotchManager.exclusionRect != .zero else {
            currentContent = content
            isPresenting = true
            playAudioIfNeeded(for: content)
            return
        }

        dismissWorkItem?.cancel()
        if isExpanded {
            dismissImmediately(notify: false)
        }

        preferredWindowScene = windowScene
        currentContent = content
        rebuildRows(for: content)
        containerEffect.spacing = style.containerSpacing
        glassContainerView.effect = containerEffect

        var config = TopNotchConfiguration()
        config.shouldHideForTaskSwitcher = true
        topNotchManager.show(
            customView: glassContainerView,
            extensionHeight: 0,
            configuration: config,
            windowScene: windowScene
        )

        isAnimating = true
        isExpanded = true
        isPresenting = true

        UIView.performWithoutAnimation {
            self.updateExtensionHeight(for: content)
            self.glassContainerView.layoutIfNeeded()
            self.applyCollapsedLayout()
        }

        let expandedFrames = expandedRowFrames(for: content)
        UIView.animate(
            withDuration: style.showDuration,
            delay: 0,
            usingSpringWithDamping: style.springDamping,
            initialSpringVelocity: 0.5
        ) {
            self.applyExpandedFrames(expandedFrames, content: content)
        } completion: { _ in
            self.isAnimating = false
            self.playShimmers(for: content)
            self.playAudioIfNeeded(for: content)
            self.scheduleAutoDismiss(for: content)
        }
    }

    func dismiss() {
        dismissWorkItem?.cancel()

        guard isExpanded else {
            audioPlayer.stop()
            finishDismissal()
            return
        }

        if isAnimating {
            dismissImmediately()
            return
        }

        isAnimating = true
        audioPlayer.stop()
        speechBars.releaseToRest()

        let collapsed = collapsedShelfFrame()
        let collapsedFrame = collapsedRowFrame(basedOn: collapsed)

        UIView.animate(
            withDuration: style.showDuration,
            delay: 0,
            usingSpringWithDamping: style.springDamping,
            initialSpringVelocity: 0.5
        ) {
            self.applyCollapsedFrames(collapsedFrame: collapsedFrame, shelfFrame: collapsed)
        } completion: { _ in
            UIView.performWithoutAnimation {
                self.topNotchManager.updateExtensionHeight(0)
            }
            self.topNotchManager.hide()
            self.clearRows()
            self.currentContent = nil
            self.isAnimating = false
            self.isExpanded = false
            self.finishDismissal()
        }
    }

    private func finishDismissal() {
        isPresenting = false
        let callback = onDidDismiss
        onDidDismiss = nil
        callback?()
    }

    // MARK: - Private

    private func configureSpeechBars() {
        speechBars.barColor = .systemBlue
        speechBars.barWidth = 7
        speechBars.barSpacing = 10
        speechBars.minBarHeight = 6
        speechBars.heightFill = 0.94
        speechBars.envelopeGain = 1.0
        speechBars.liveGain = 2.4
        speechBars.attackGain = 2.4
        speechBars.smoothing = 0.28
        speechBars.diamondFalloff = 0.75
        speechBars.meterHeight = style.voiceMeterHeight * 0.45

        audioPlayer.onPlaybackUpdate = { [weak self] time, envelope, liveLevel in
            self?.speechBars.setPlayback(envelope: envelope, at: time, liveLevel: liveLevel)
        }
        audioPlayer.onFinished = { [weak self] in
            guard let self else { return }
            self.speechBars.releaseToRest()
            if case .encouragement = self.currentContent, self.autoDismissWhenFinished {
                self.dismissWorkItem?.cancel()
                self.dismiss()
            }
        }
    }

    private func includesVoiceMeter(_ content: NotchDropContent) -> Bool {
        switch content {
        case .encouragement, .streak: true
        default: false
        }
    }

    private func rebuildRows(for content: NotchDropContent) {
        clearRows()
        glassContainerView.contentView.subviews.forEach { $0.removeFromSuperview() }

        glassContainerView.contentView.addSubview(shelfGlassView)

        switch content {
        case .encouragement, .streak:
            let voiceGlass = makeRowGlassView()
            voiceGlass.contentView.addSubview(speechBars)
            NSLayoutConstraint.activate([
                speechBars.centerXAnchor.constraint(equalTo: voiceGlass.contentView.centerXAnchor),
                speechBars.centerYAnchor.constraint(equalTo: voiceGlass.contentView.centerYAnchor),
            ])
            rowGlassViews.append(voiceGlass)

            if case .streak(let comboCount, let praisePhrase) = content {
                rowBadges.append(makeBadge(
                    text: "COMBO \(comboCount)x!",
                    fill: Self.comboFill,
                    textColor: Self.comboText
                ))
                rowBadges.append(makeBadge(
                    text: praisePhrase,
                    fill: Self.tensaiFill,
                    textColor: Self.tensaiText
                ))
            }

        case .lifeLost(let remaining):
            let text = remaining == 1 ? "1 LIFE LEFT" : "\(remaining) LIVES LEFT"
            rowBadges.append(makeBadge(
                text: text,
                fill: Self.lifeLostFill,
                textColor: .systemRed
            ))

        case .points(let amount):
            rowBadges.append(makeBadge(
                text: "+\(amount) PTS",
                fill: Self.pointsFill,
                textColor: .systemGreen
            ))
        }

        for badge in rowBadges {
            let glass = makeRowGlassView()
            glass.contentView.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.topAnchor.constraint(equalTo: glass.contentView.topAnchor),
                badge.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor),
                badge.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor),
                badge.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor),
            ])
            rowGlassViews.append(glass)
        }

        for row in rowGlassViews {
            glassContainerView.contentView.addSubview(row)
        }
        ensureZOrder()
    }

    private func clearRows() {
        rowGlassViews.removeAll()
        rowBadges.removeAll()
    }

    private func makeRowGlassView() -> UIVisualEffectView {
        let glass = UIVisualEffectView(effect: UIGlassEffect(style: .clear))
        glass.translatesAutoresizingMaskIntoConstraints = true
        glass.cornerConfiguration = .corners(radius: .fixed(24))
        return glass
    }

    private func makeBadge(text: String, fill: UIColor, textColor: UIColor) -> EncouragementBadgeView {
        EncouragementBadgeView(text: text, fillColor: fill, textColor: textColor)
    }

    private func ensureZOrder() {
        glassContainerView.contentView.sendSubviewToBack(shelfGlassView)
        for row in rowGlassViews {
            glassContainerView.contentView.bringSubviewToFront(row)
        }
    }

    private func expansionHeight(for content: NotchDropContent) -> CGFloat {
        let shelfH = topNotchManager.adjustedExclusionFrame.height
        let width = preferredWindowScene?.coordinateSpace.bounds.width ?? UIScreen.main.bounds.width
        let frames = expandedRowFrames(for: content, contentWidth: width, shelfHeight: shelfH)
        guard let last = frames.last else { return style.bottomInset }
        return last.maxY + style.bottomInset
    }

    private func updateExtensionHeight(for content: NotchDropContent) {
        topNotchManager.updateExtensionHeight(expansionHeight(for: content))
    }

    private func collapsedShelfFrame() -> CGRect {
        let bounds = glassContainerView.contentView.bounds
        let exclusion = topNotchManager.adjustedExclusionFrame
        if topNotchManager.extensionHeight > 0 {
            return CGRect(x: exclusion.origin.x, y: 0, width: exclusion.width, height: exclusion.height)
        }
        return CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
    }

    private func collapsedRowFrame(basedOn shelfFrame: CGRect) -> CGRect {
        let width = min(style.voiceMeterWidth, shelfFrame.width)
        let originX = shelfFrame.midX - width / 2
        return CGRect(x: originX, y: shelfFrame.origin.y, width: width, height: shelfFrame.height)
    }

    private func expandedRowFrames(
        for content: NotchDropContent,
        contentWidth: CGFloat? = nil,
        shelfHeight: CGFloat? = nil
    ) -> [CGRect] {
        let shelfH = shelfHeight ?? collapsedShelfFrame().height
        let width = contentWidth
            ?? max(glassContainerView.contentView.bounds.width, preferredWindowScene?.coordinateSpace.bounds.width ?? UIScreen.main.bounds.width)
        var frames: [CGRect] = []
        var cursorY = shelfH + style.firstRowGap

        for index in rowGlassViews.indices {
            let size = rowSize(at: index, content: content)
            let originX = (width - size.width) / 2
            frames.append(CGRect(x: originX, y: cursorY, width: size.width, height: size.height))
            cursorY += size.height + style.rowSpacing
        }
        return frames
    }

    private func rowSize(at index: Int, content: NotchDropContent) -> CGSize {
        if includesVoiceMeter(content), index == 0 {
            return CGSize(width: style.voiceMeterWidth, height: style.voiceMeterHeight)
        }
        let badgeIndex = badgeIndex(forRow: index, content: content)
        guard badgeIndex < rowBadges.count else {
            return CGSize(width: style.voiceMeterWidth, height: style.voiceMeterHeight)
        }
        return measuredBadgeSize(rowBadges[badgeIndex])
    }

    private func badgeIndex(forRow index: Int, content: NotchDropContent) -> Int {
        if includesVoiceMeter(content) {
            return index - 1
        }
        return index
    }

    private func measuredBadgeSize(_ badge: EncouragementBadgeView) -> CGSize {
        let limit = max(glassContainerView.contentView.bounds.width, UIScreen.main.bounds.width) - 32
        return badge.systemLayoutSizeFitting(
            CGSize(width: max(limit, 100), height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel
        )
    }

    private func applyCollapsedLayout() {
        let shelfFrame = collapsedShelfFrame()
        let rowFrame = collapsedRowFrame(basedOn: shelfFrame)

        shelfGlassView.frame = shelfFrame
        let radius = topNotchManager.adjustedExclusionFrame.height / 2
        shelfGlassView.cornerConfiguration = .corners(radius: .fixed(radius))

        for row in rowGlassViews {
            row.frame = rowFrame
            row.cornerConfiguration = .corners(radius: .fixed(radius))
        }
        speechBars.alpha = 0
        ensureZOrder()
    }

    private func applyExpandedFrames(_ frames: [CGRect], content: NotchDropContent) {
        let shelfFrame = collapsedShelfFrame()
        shelfGlassView.frame = shelfFrame

        for (index, frame) in frames.enumerated() {
            guard index < rowGlassViews.count else { break }
            rowGlassViews[index].frame = frame
            if includesVoiceMeter(content), index == 0 {
                rowGlassViews[index].cornerConfiguration = .corners(
                    radius: .fixed(style.voiceMeterHeight / 2)
                )
                speechBars.alpha = 1
            }
        }
        ensureZOrder()
    }

    private func applyCollapsedFrames(collapsedFrame: CGRect, shelfFrame: CGRect) {
        shelfGlassView.frame = shelfFrame
        for row in rowGlassViews {
            row.frame = collapsedFrame
        }
        speechBars.alpha = 0
    }

    private func playShimmers(for content: NotchDropContent) {
        guard case .streak = content else { return }
        for badge in rowBadges {
            badge.playEntryShimmer()
        }
    }

    private func playAudioIfNeeded(for content: NotchDropContent) {
        let names = MeteredAudioPlayer.encouragementClipNames
        guard !names.isEmpty else { return }

        switch content {
        case .encouragement(let clipIndex):
            speechBars.reset()
            let index = min(max(clipIndex, 0), names.count - 1)
            audioPlayer.play(assetNamed: names[index])
        case .streak:
            speechBars.reset()
            audioPlayer.play(assetNamed: names[0])
        default:
            break
        }
    }

    private func scheduleAutoDismiss(for content: NotchDropContent) {
        if case .encouragement = content {
            guard autoDismissWhenFinished else { return }
            // Safety cap so a failed clip cannot block lesson flow.
            let work = DispatchWorkItem { [weak self] in
                self?.dismiss()
            }
            dismissWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + style.displayDuration, execute: work)
    }

    private func dismissImmediately(notify: Bool = true) {
        dismissWorkItem?.cancel()
        audioPlayer.stop()
        topNotchManager.hide()
        clearRows()
        currentContent = nil
        isExpanded = false
        isAnimating = false
        if notify {
            finishDismissal()
        } else {
            isPresenting = false
            onDidDismiss = nil
        }
    }
}
