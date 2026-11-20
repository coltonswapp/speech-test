//
//  MainFeedTabViewController.swift
//  shizen
//
//  The clip feed as a main-screen tab. It starts as a page like the others, under the
//  category tab bar, playing the current clip. After a few seconds on a clip (or right
//  away, from the expand button in the main navigation bar) it fades into the full feed:
//  the tab bar fades out, side-swiping between tabs turns off, and settings swaps for the
//  clip menu. The collapse button comes back out.
//
//  The feed is built the first time the tab becomes active, so launch loads no players.
//

import UIKit

final class MainFeedTabViewController: UIViewController {

    /// How long the viewer stays on a clip before the feed goes immersive.
    static let immersiveDelay: TimeInterval = 2.5
    static let immersiveFadeDuration: TimeInterval = 0.6
    /// Extra room under the navigation bar when immersive, before the clip's info line.
    static let immersiveTopPadding: CGFloat = 8

    /// Height of the floating category tab bar the feed sits under when not immersive.
    var topOverlayHeight: CGFloat = 0 {
        didSet { applySafeArea() }
    }
    /// Asks the main screen to switch its chrome to the immersive feed (true) or back
    /// (false). Called inside the fade's animation block.
    var onImmersiveChange: ((Bool) -> Void)?

    /// The current clip's options, for the main navigation bar while immersive. Built when
    /// opened, so it always follows the clip on screen.
    var currentClipMenu: UIMenu? { feed?.currentClipMenu }
    /// The clip on screen changed, so `currentClipMenu` did too.
    var onClipMenuChanged: (() -> Void)?

    private var feed: ClipFeedViewController?
    private(set) var isActive = false
    private(set) var isImmersive = false
    private var immersiveTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ExperimentPalette.pageBackground
    }

    /// Called by `MainViewController` when this page becomes (or stops being) the nearest page.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active, feed == nil { installFeed() }
        feed?.setActive(active)
        if active {
            scheduleImmersive()
        } else {
            cancelImmersiveTimer()
            if isImmersive { setImmersive(false, animated: false) }
        }
    }

    // MARK: - Immersive

    /// The expand / collapse button in the main navigation bar.
    func toggleImmersive() {
        cancelImmersiveTimer()
        setImmersive(!isImmersive, animated: true)
    }

    private func scheduleImmersive() {
        cancelImmersiveTimer()
        guard isActive, !isImmersive else { return }
        immersiveTimer = Timer.scheduledTimer(withTimeInterval: Self.immersiveDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.immersiveTimerFired() }
        }
    }

    private func cancelImmersiveTimer() {
        immersiveTimer?.invalidate()
        immersiveTimer = nil
    }

    private func immersiveTimerFired() {
        immersiveTimer = nil
        guard isActive, !isImmersive, view.window != nil, presentedViewController == nil else { return }
        // Still loading: try again once there's a clip on screen.
        guard feed?.hasClips == true else {
            scheduleImmersive()
            return
        }
        setImmersive(true, animated: true)
    }

    private func setImmersive(_ immersive: Bool, animated: Bool) {
        guard immersive != isImmersive else { return }
        isImmersive = immersive
        let changes = { [self] in
            onImmersiveChange?(immersive)
            applySafeArea()
            view.window?.layoutIfNeeded()
        }
        if animated {
            UIView.animate(
                withDuration: Self.immersiveFadeDuration,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
                animations: changes
            )
        } else {
            changes()
        }
    }

    /// Under the tab bar normally; straight under the navigation bar when immersive.
    private func applySafeArea() {
        feed?.additionalSafeAreaInsets.top = isImmersive ? Self.immersiveTopPadding : topOverlayHeight
    }

    // MARK: - Feed

    private func installFeed() {
        let feed = ClipFeedViewController(learnerLevel: nil, presentation: .mainTab)
        feed.onClipChanged = { [weak self] in
            // A new clip restarts the countdown (e.g. after collapsing back to the tabs).
            self?.scheduleImmersive()
            self?.onClipMenuChanged?()
        }
        self.feed = feed
        applySafeArea()
        addChild(feed)
        feed.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(feed.view)
        NSLayoutConstraint.activate([
            feed.view.topAnchor.constraint(equalTo: view.topAnchor),
            feed.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            feed.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            feed.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        feed.didMove(toParent: self)
    }
}
