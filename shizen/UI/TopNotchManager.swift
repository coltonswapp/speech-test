//
//  TopNotchManager.swift
//  shizen
//
//  Hosts views in the screen exclusion area (behind the notch / Dynamic Island)
//  via KVC, in a dedicated overlay window. Supports growing downward when content
//  peels out, and hiding during task switcher.
//

import UIKit

final class TopNotchManager {

    static let shared = TopNotchManager()

    /// The exclusion area (“notch” / Dynamic Island cutout) in screen coordinates.
    static var exclusionRect: CGRect = {
        let screen = UIScreen.main
        print("[TopNotchManager] UIScreen.main.bounds: \(screen.bounds) scale: \(screen.scale)")
        guard let exclusionArea = screen.value(forKey: "_" + "exclusion" + "Area") as? NSObject else {
            print("[TopNotchManager] KVC _exclusionArea unavailable — returning .zero")
            return .zero
        }
        print("[TopNotchManager] exclusionArea type: \(type(of: exclusionArea))")
        for key in ["rect", "frame", "bounds"] {
            if exclusionArea.responds(to: NSSelectorFromString(key)),
               let value = exclusionArea.value(forKey: key) {
                print("[TopNotchManager] exclusionArea.\(key): \(value)")
            }
        }
        guard let rect = exclusionArea.value(forKey: "rect") as? CGRect else {
            print("[TopNotchManager] exclusionArea.rect missing or wrong type — returning .zero")
            return .zero
        }
        print("[TopNotchManager] raw exclusionRect: \(rect)")
        return rect
    }()

    private(set) var isVisible = false
    private(set) var currentExclusionRect: CGRect = .zero
    private(set) var cannotShowReason: String?
    /// Extra height below the exclusion rect for content that peels out (Y axis).
    private(set) var extensionHeight: CGFloat = 0

    private var hostedView: UIView?
    private var config = TopNotchConfiguration()
    private var overlayWindow: UIWindow?
    private var storedExclusionRect: CGRect?
    private var preferredWindowScene: UIWindowScene?

    private let modelOverrides: [String: (scale: CGFloat, heightFactor: CGFloat, radius: CGFloat)] = [:]
    private let modelSeriesOverrides: [String: (scale: CGFloat, heightFactor: CGFloat, radius: CGFloat)] = [
        "iPhone13": (scale: 0.95, heightFactor: 1.0, radius: 27),
        "iPhone14": (scale: 0.75, heightFactor: 0.75, radius: 24),
    ]

    private init() {}

    /// Model-adjusted exclusion frame in screen coordinates.
    var adjustedExclusionFrame: CGRect {
        computeAdjustedExclusionFrame()
    }

    func show(
        customView: UIView,
        extensionHeight: CGFloat = 0,
        configuration: TopNotchConfiguration = TopNotchConfiguration(),
        windowScene: UIWindowScene? = nil
    ) {
        config = configuration
        self.extensionHeight = extensionHeight
        preferredWindowScene = windowScene

        guard Self.exclusionRect != .zero else {
            cannotShowReason = "No exclusion area detected."
            hide()
            return
        }

        cannotShowReason = nil
        storedExclusionRect = Self.exclusionRect
        currentExclusionRect = Self.exclusionRect
        hostedView = customView
        hostedView?.isUserInteractionEnabled = false

        hostedView?.alpha = 0
        installHostedViewInOverlayWindow()

        UIView.animate(withDuration: config.animationDuration) {
            self.hostedView?.alpha = 1
        }
        isVisible = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateHostedFrame),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )

        if config.shouldHideForTaskSwitcher {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(sceneWillDeactivateNotification(_:)),
                name: UIScene.willDeactivateNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(sceneDidActivateNotification(_:)),
                name: UIScene.didActivateNotification,
                object: nil
            )
        }
    }

    func updateExtensionHeight(_ height: CGFloat) {
        let clamped = max(0, height)
        print("[TopNotchManager] updateExtensionHeight \(extensionHeight) → \(clamped)")
        extensionHeight = clamped
        updateHostedFrame()
    }

    func hide() {
        NotificationCenter.default.removeObserver(self)
        UIView.animate(withDuration: config.animationDuration, animations: {
            self.hostedView?.alpha = 0
        }) { _ in
            self.hostedView?.removeFromSuperview()
            self.overlayWindow?.isHidden = true
            self.overlayWindow = nil
            self.hostedView = nil
            self.extensionHeight = 0
            self.isVisible = false
        }
    }

    // MARK: - Private

    private final class OverlayContainerViewController: UIViewController {
        override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
        override var shouldAutorotate: Bool { false }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
    }

    private func installHostedViewInOverlayWindow() {
        guard attachHostedViewToWindow() else {
            print("[TopNotchManager] installHostedViewInOverlayWindow: attach failed, retrying next run loop")
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isVisible || self.hostedView != nil else { return }
                if self.attachHostedViewToWindow() {
                    self.updateHostedFrame()
                    self.printExclusionDiagnostics(context: "show(retry after attach)")
                } else {
                    print("[TopNotchManager] installHostedViewInOverlayWindow: attach failed on retry")
                }
            }
            return
        }

        updateHostedFrame()
        printExclusionDiagnostics(context: "show(after updateHostedFrame)")
    }

    @discardableResult
    private func attachHostedViewToWindow() -> Bool {
        if overlayWindow == nil {
            guard let windowScene = resolveWindowScene() else {
                print("[TopNotchManager] attachHostedViewToWindow failed: no UIWindowScene")
                cannotShowReason = "No UIWindowScene available."
                return false
            }

            let window = UIWindow(windowScene: windowScene)
            window.backgroundColor = .clear
            window.windowLevel = UIWindow.Level.statusBar + 100
            window.rootViewController = OverlayContainerViewController()
            window.isUserInteractionEnabled = false
            window.isHidden = false
            overlayWindow = window
            window.frame = windowScene.coordinateSpace.bounds
            print("[TopNotchManager] created overlayWindow on scene activationState=\(windowScene.activationState.rawValue)")
        }

        guard let window = overlayWindow,
              let container = window.rootViewController?.view,
              let view = hostedView else {
            print("[TopNotchManager] attachHostedViewToWindow failed: missing window, container, or hostedView")
            return false
        }

        container.frame = window.bounds
        view.removeFromSuperview()
        container.addSubview(view)
        container.bringSubviewToFront(view)
        return true
    }

    private func resolveWindowScene() -> UIWindowScene? {
        if let preferredWindowScene {
            print("[TopNotchManager] resolveWindowScene: using caller-provided scene")
            return preferredWindowScene
        }

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        if let scene = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.windowScene {
            print("[TopNotchManager] resolveWindowScene: keyWindow scene")
            return scene
        }

        for state: UIScene.ActivationState in [.foregroundActive, .foregroundInactive] {
            if let scene = scenes.first(where: { $0.activationState == state }) {
                print("[TopNotchManager] resolveWindowScene: activationState=\(state.rawValue)")
                return scene
            }
        }

        if let scene = scenes.first {
            print("[TopNotchManager] resolveWindowScene: first connected scene")
            return scene
        }

        print("[TopNotchManager] resolveWindowScene: no scene found")
        return nil
    }

    @objc private func updateHostedFrame() {
        guard let view = hostedView else {
            print("[TopNotchManager] updateHostedFrame skipped: no hostedView")
            return
        }
        guard let window = overlayWindow else {
            print("[TopNotchManager] updateHostedFrame skipped: no overlayWindow")
            return
        }

        let exclusion = computeAdjustedExclusionFrame()
        guard exclusion != .zero else {
            view.frame = .zero
            return
        }

        let sceneBounds = window.windowScene?.coordinateSpace.bounds ?? UIScreen.main.bounds
        let cornerRadius = cornerRadius(for: exclusion)

        // Keep the overlay window full-screen; position content via hostedView.frame so
        // expand/collapse doesn't animate the window origin from the island to (0, 0).
        window.frame = sceneBounds
        window.rootViewController?.view.frame = window.bounds

        if extensionHeight <= 0 {
            view.frame = exclusion
            applyCornerStyling(to: view, radius: cornerRadius, roundBottomOnly: exclusion.origin.y == 0)
            print(
                "[TopNotchManager] updateHostedFrame collapsed"
                + " hostedView.frame=\(view.frame)"
                + " hostedView.screenFrame=\(view.convert(view.bounds, to: nil))"
                + " cornerRadius=\(cornerRadius)"
            )
        } else {
            view.frame = CGRect(
                x: 0,
                y: exclusion.origin.y,
                width: sceneBounds.width,
                height: exclusion.height + extensionHeight
            )
            view.layer.mask = nil
            print(
                "[TopNotchManager] updateHostedFrame expanded"
                + " hostedView.frame=\(view.frame)"
                + " exclusion=\(exclusion)"
                + " extensionHeight=\(extensionHeight)"
            )
        }
    }

    private func printExclusionDiagnostics(context: String) {
        let modelId = UIDevice.modelIdentifier
        let raw = storedExclusionRect ?? Self.exclusionRect
        let adjusted = computeAdjustedExclusionFrame()
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        let safeArea = keyWindow?.safeAreaInsets ?? .zero

        print("[TopNotchManager] — \(context) —")
        print("[TopNotchManager]   modelIdentifier: \(modelId)")
        print("[TopNotchManager]   raw exclusionRect: \(raw)")
        print("[TopNotchManager]   adjusted exclusionFrame: \(adjusted)")
        if raw != adjusted {
            print("[TopNotchManager]   (adjusted via model series override)")
        }
        print("[TopNotchManager]   keyWindow.safeAreaInsets: \(safeArea)")
        print("[TopNotchManager]   overlayWindow.frame: \(overlayWindow?.frame.debugDescription ?? "nil")")
        print("[TopNotchManager]   hostedView.frame: \(hostedView?.frame.debugDescription ?? "nil")")
        if let hostedView {
            print("[TopNotchManager]   hostedView.screenFrame: \(hostedView.convert(hostedView.bounds, to: nil))")
        }
    }

    private func computeAdjustedExclusionFrame() -> CGRect {
        guard let rawRect = storedExclusionRect ?? Optional(Self.exclusionRect), rawRect != .zero else {
            return .zero
        }

        let modelId = UIDevice.modelIdentifier

        if let override = modelOverrides[modelId] {
            let result = scaledFrame(rawRect, override: override, label: "modelOverride(\(modelId))")
            return result
        }

        if let seriesOverride = modelSeriesOverrides.first(where: { modelId.hasPrefix($0.key) }) {
            let result = scaledFrame(
                rawRect,
                override: seriesOverride.value,
                label: "seriesOverride(\(seriesOverride.key))"
            )
            return result
        }

        return rawRect
    }

    private func scaledFrame(
        _ rawRect: CGRect,
        override: (scale: CGFloat, heightFactor: CGFloat, radius: CGFloat),
        label: String
    ) -> CGRect {
        let newWidth = rawRect.width * override.scale
        let newX = rawRect.origin.x + (rawRect.width - newWidth) / 2
        let newHeight = rawRect.height * override.heightFactor
        let result = CGRect(x: newX, y: rawRect.origin.y, width: newWidth, height: newHeight)
        print(
            "[TopNotchManager] scaledFrame \(label)"
            + " scale=\(override.scale) heightFactor=\(override.heightFactor)"
            + " \(rawRect) → \(result)"
        )
        return result
    }

    private func cornerRadius(for bounds: CGRect) -> CGFloat {
        guard let rawRect = storedExclusionRect else { return 16 }
        let modelId = UIDevice.modelIdentifier

        if let override = modelOverrides[modelId] {
            return override.radius
        }
        if let seriesOverride = modelSeriesOverrides.first(where: { modelId.hasPrefix($0.key) }) {
            return seriesOverride.value.radius
        }
        if rawRect.origin.y > 0 {
            return rawRect.height / 2
        }
        return 21
    }

    private func applyCornerStyling(to view: UIView, radius: CGFloat, roundBottomOnly: Bool = false) {
        view.clipsToBounds = false
        view.layoutIfNeeded()

        let path: UIBezierPath
        if roundBottomOnly {
            path = UIBezierPath(
                roundedRect: view.bounds,
                byRoundingCorners: [.bottomLeft, .bottomRight],
                cornerRadii: CGSize(width: radius, height: radius)
            )
        } else {
            path = UIBezierPath(roundedRect: view.bounds, cornerRadius: radius)
        }

        let maskLayer = CAShapeLayer()
        maskLayer.frame = view.bounds
        maskLayer.path = path.cgPath
        view.layer.mask = maskLayer
    }

    @objc private func sceneWillDeactivateNotification(_ notification: Notification) {
        guard config.shouldHideForTaskSwitcher, isVisible else { return }
        UIView.animate(withDuration: config.animationDuration) {
            self.hostedView?.alpha = 0
        }
    }

    @objc private func sceneDidActivateNotification(_ notification: Notification) {
        guard config.shouldHideForTaskSwitcher, isVisible else { return }
        UIView.animate(withDuration: config.animationDuration) {
            self.hostedView?.alpha = 1
        }
    }
}
