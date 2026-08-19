//
//  SpeechOverlayPresenter.swift
//  shizen
//
//  Global presenter for showing the speech-profile overlay in a passthrough
//  window above any screen without blocking underlying interactions.
//

import UIKit

final class SpeechOverlayPresenter {

    enum BarColor {
        case yellow
        case blue

        var uiColor: UIColor {
            switch self {
            case .yellow: return .systemYellow
            case .blue: return .systemBlue
            }
        }
    }

    struct Configuration {
        var edge: SpeechProfileOverlayEdge = .top
        var barColor: BarColor = .blue
    }

    static let shared = SpeechOverlayPresenter()

    /// Clean call site for use anywhere in app code.
    static func showClip(
        _ clipIndex: Int,
        from presentingViewController: UIViewController? = nil,
        edge: SpeechProfileOverlayEdge = .top,
        barColor: BarColor = .blue
    ) {
        shared.showClip(
            clipIndex,
            from: presentingViewController,
            configuration: Configuration(edge: edge, barColor: barColor)
        )
    }

    private let audioPlayer = MeteredAudioPlayer()
    private let overlay = SpeechProfileGlassOverlay()

    private weak var activeScene: UIWindowScene?
    private var overlayWindow: PassthroughWindow?
    private var overlayHostController: UIViewController?

    private init() {
        audioPlayer.onPlaybackUpdate = { [weak self] frame in
            self?.overlay.pushPlayback(envelope: frame.envelope, at: frame.time, liveLevel: frame.liveLevel)
        }
        audioPlayer.onFinished = { [weak self] in
            self?.handlePlaybackFinished()
        }
    }

    func showClip(
        _ clipIndex: Int,
        from presentingViewController: UIViewController? = nil,
        configuration: Configuration = Configuration()
    ) {
        DispatchQueue.main.async {
            self.presentClip(clipIndex, from: presentingViewController, configuration: configuration)
        }
    }

    func dismiss() {
        DispatchQueue.main.async {
            self.audioPlayer.stop()
            self.overlay.dismiss { [weak self] in
                self?.hideWindow()
            }
        }
    }

    private func presentClip(
        _ clipIndex: Int,
        from presentingViewController: UIViewController?,
        configuration: Configuration
    ) {
        let normalizedIndex = min(max(clipIndex, 0), MeteredAudioPlayer.encouragementClipNames.count - 1)
        let assetName = MeteredAudioPlayer.encouragementClipNames[normalizedIndex]

        if audioPlayer.isPlaying {
            audioPlayer.stop()
        }
        overlay.dismiss()

        guard let scene = resolveScene(from: presentingViewController) else { return }
        ensureWindow(in: scene)
        guard let hostView = overlayHostController?.view else { return }

        overlay.install(in: hostView, edge: configuration.edge)
        overlay.setCapsuleSize(
            width: SpeechProfileGlassOverlay.Style.defaultWidth,
            height: SpeechProfileGlassOverlay.Style.defaultHeight
        )
        overlay.setBarColor(configuration.barColor.uiColor)
        overlay.prepareForPlayback()
        overlay.present { [weak self] in
            self?.audioPlayer.play(assetNamed: assetName)
        }
    }

    private func handlePlaybackFinished() {
        overlay.releaseToRest { [weak self] in
            guard let self else { return }
            self.overlay.dismiss { [weak self] in
                self?.hideWindow()
            }
        }
    }

    private func resolveScene(from presentingViewController: UIViewController?) -> UIWindowScene? {
        if let scene = presentingViewController?.view.window?.windowScene {
            return scene
        }

        let active = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        if let active {
            return active
        }

        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
    }

    private func ensureWindow(in scene: UIWindowScene) {
        if let activeScene, activeScene == scene, overlayWindow != nil, overlayHostController != nil {
            overlayWindow?.isHidden = false
            return
        }

        overlayWindow?.isHidden = true
        overlayWindow = nil
        overlayHostController = nil

        let host = UIViewController()
        host.view.backgroundColor = .clear

        let window = PassthroughWindow(windowScene: scene)
        window.windowLevel = .statusBar + 1
        window.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false

        activeScene = scene
        overlayHostController = host
        overlayWindow = window
    }

    private func hideWindow() {
        overlayWindow?.isHidden = true
    }
}
