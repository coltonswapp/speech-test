//
//  ClipAmbientBackdrop.swift
//  shizen
//
//  Experiment: "ambient mode" for clips. The video's thumbnail, blurred and
//  scaled up from the player, fills the page behind it, after Seb Vidal's Apple
//  Music recipe. Toggle and tune from a clip's options menu → Experiments.
//
//  A live mirror of the video (`_UIPortalView` on the player) was tried and
//  dropped (2026-11-14): WebKit draws the video out of process, so the portal
//  showed nothing over it.
//

import UIKit

// MARK: - Settings

/// Shared by every clip player; any change posts `didChange` so open players re-apply live.
enum ClipAmbientSettings {
    static let didChange = Notification.Name("ClipAmbientSettings.didChange")

    enum Toggle: String, CaseIterable {
        case enabled
        /// Karaoke marker tinted from the thumbnail (ClipThumbnailAccent.swift).
        case thumbnailHighlight

        var title: String {
            switch self {
            case .enabled: "Ambient backdrop"
            case .thumbnailHighlight: "Highlight from thumbnail"
            }
        }

        var defaultValue: Bool {
            switch self {
            // The ambient backdrop shipped on; the thumbnail-tinted marker is still an experiment.
            case .enabled: true
            case .thumbnailHighlight: false
            }
        }
    }

    enum Tunable: String, CaseIterable {
        case blurRadius
        case washAlpha
        case overscan
        case reach
        case fadeLength
        case sideReach
        case sideFadeLength
        case opacity
        case highlightSaturation
        case highlightOpacity

        var title: String {
            switch self {
            case .blurRadius: "Blur radius"
            case .washAlpha: "Background wash"
            case .overscan: "Overscan"
            case .reach: "Reach below player (× player height)"
            case .fadeLength: "Fade length (× player height)"
            case .sideReach: "Side by side: reach past player (× player width)"
            case .sideFadeLength: "Side by side: fade length (× player width)"
            case .opacity: "Glow opacity"
            case .highlightSaturation: "Thumbnail highlight saturation"
            case .highlightOpacity: "Thumbnail highlight opacity"
            }
        }

        var range: ClosedRange<Float> {
            switch self {
            case .blurRadius: 0 ... 40
            case .washAlpha: 0 ... 0.9
            case .overscan: 1 ... 2.5
            case .reach: 0 ... 1.5
            case .fadeLength: 0 ... 1.5
            case .sideReach: 0 ... 1
            case .sideFadeLength: 0 ... 1.5
            case .opacity: 0 ... 1
            case .highlightSaturation: 0.2 ... 1
            case .highlightOpacity: 0.2 ... 0.9
            }
        }

        var defaultValue: Float {
            switch self {
            // Tuned on device 2026-11-14.
            case .blurRadius: 20
            case .washAlpha: 0.29
            case .overscan: 1.25
            case .reach: 0
            case .fadeLength: 0.8
            // Untuned: ends a little past the player's trailing edge, short of the transcript.
            case .sideReach: 0.05
            case .sideFadeLength: 0.85
            case .opacity: 1
            // Untuned starting point: about as strong as the yellow marker (0.55).
            case .highlightSaturation: 0.7
            case .highlightOpacity: 0.5
            }
        }

        func format(_ value: Float) -> String {
            switch self {
            case .blurRadius: String(format: "%.0f pt", value)
            case .overscan, .reach, .fadeLength, .sideReach, .sideFadeLength: String(format: "%.2f×", value)
            default: String(format: "%.0f%%", value * 100)
            }
        }
    }

    private static func key(_ name: String) -> String { "clipAmbient.\(name)" }

    static subscript(toggle: Toggle) -> Bool {
        get {
            let stored = UserDefaults.standard.object(forKey: key(toggle.rawValue)) as? Bool
            return stored ?? toggle.defaultValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key(toggle.rawValue))
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static subscript(tunable: Tunable) -> Float {
        get {
            let stored = UserDefaults.standard.object(forKey: key(tunable.rawValue)) as? Float
            return stored ?? tunable.defaultValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key(tunable.rawValue))
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static var isEnabled: Bool {
        get { self[.enabled] }
        set { self[.enabled] = newValue }
    }

    static var thumbnailHighlight: Bool {
        get { self[.thumbnailHighlight] }
        set { self[.thumbnailHighlight] = newValue }
    }

    /// Back to defaults (keeps the on/off switches).
    static func resetTuning() {
        for tunable in Tunable.allCases {
            UserDefaults.standard.removeObject(forKey: key(tunable.rawValue))
        }
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}

// MARK: - Backdrop

/// Back to front: the video's thumbnail, scaled up from the player's center and
/// blurred with a `gaussianBlur` CAFilter (private API, experiment only); then a
/// wash of the page background. A gradient mask ends a little below the player and
/// is sized from the player's height, so it grows and shrinks with the Shorts detent.
final class ClipAmbientBackdropView: UIView {
    /// Player-sized, then scaled up to cover the page.
    private let glow = UIView()
    private let thumbnail = UIImageView()
    private let wash = UIView()
    /// A view (not a bare layer) so its frame animates inside detent snap animations.
    private let coverageMask = ClipAmbientGradientView()
    private var thumbnailVideoID: String?
    private var thumbnailTask: Task<Void, Never>?
    private var lastSourceFrame: CGRect?
    /// Side-by-side layout: the glow stays left of this x, fading out horizontally.
    /// Nil: covers the full width and fades out vertically below the player.
    private var lastCoverageMaxX: CGFloat?

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        clipsToBounds = true

        glow.isUserInteractionEnabled = false
        addSubview(glow)
        thumbnail.contentMode = .scaleAspectFill
        thumbnail.clipsToBounds = true
        glow.addSubview(thumbnail)

        wash.frame = bounds
        wash.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(wash)

        mask = coverageMask
        applySettings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        thumbnailTask?.cancel()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let lastSourceFrame { track(sourceFrame: lastSourceFrame, coverageMaxX: lastCoverageMaxX) }
    }

    /// Re-reads `ClipAmbientSettings` (live while tuning).
    func applySettings() {
        let blurRadius = CGFloat(ClipAmbientSettings[.blurRadius])
        thumbnail.layer.filters = blurRadius > 0 ? Self.gaussianBlur(radius: blurRadius).map { [$0] } : nil
        glow.alpha = CGFloat(ClipAmbientSettings[.opacity])
        wash.backgroundColor = ExperimentPalette.pageBackground
            .withAlphaComponent(CGFloat(ClipAmbientSettings[.washAlpha]))
        if let lastSourceFrame { track(sourceFrame: lastSourceFrame, coverageMaxX: lastCoverageMaxX) }
    }

    /// Glow runs from the top of the page to `reach` player-heights below the
    /// player, fading over the last `fadeLength` player-heights.
    private func coveredHeight(for sourceFrame: CGRect) -> CGFloat {
        let reach = sourceFrame.height * CGFloat(ClipAmbientSettings[.reach])
        return min(bounds.height, max(sourceFrame.maxY + reach, 1))
    }

    /// Side by side: the glow runs from the leading edge to `sideReach` player-widths past
    /// the player (never past `coverageMaxX`), fading over the last `sideFadeLength`
    /// player-widths.
    private func coveredWidth(for sourceFrame: CGRect, coverageMaxX: CGFloat?) -> CGFloat {
        guard let coverageMaxX else { return bounds.width }
        let reach = sourceFrame.width * CGFloat(ClipAmbientSettings[.sideReach])
        return min(bounds.width, coverageMaxX, max(sourceFrame.maxX + reach, 1))
    }

    private func updateMask(sourceFrame: CGRect, coverageMaxX: CGFloat?) {
        if coverageMaxX != nil {
            let covered = coveredWidth(for: sourceFrame, coverageMaxX: coverageMaxX)
            let fade = min(sourceFrame.width * CGFloat(ClipAmbientSettings[.sideFadeLength]), covered)
            coverageMask.axis = .horizontal
            coverageMask.frame = CGRect(x: 0, y: 0, width: covered, height: bounds.height)
            coverageMask.setFade(start: Double((covered - fade) / covered))
            return
        }
        coverageMask.axis = .vertical
        let covered = coveredHeight(for: sourceFrame)
        let fade = min(sourceFrame.height * CGFloat(ClipAmbientSettings[.fadeLength]), covered)
        coverageMask.frame = CGRect(x: 0, y: 0, width: bounds.width, height: covered)
        coverageMask.setFade(start: Double((covered - fade) / covered))
    }

    /// `CAFilter(type: "gaussianBlur")` (private), or nil if unavailable.
    private static func gaussianBlur(radius: CGFloat) -> NSObject? {
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type else { return nil }
        let selector = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: selector),
              let filter = filterClass.perform(selector, with: "gaussianBlur")?.takeUnretainedValue() as? NSObject
        else { return nil }
        filter.setValue(radius, forKey: "inputRadius")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        return filter
    }

    /// YouTube's hqdefault frame, cropped to the player like the poster.
    func loadThumbnail(videoID: String) {
        guard videoID != thumbnailVideoID else { return }
        thumbnailVideoID = videoID
        thumbnailTask?.cancel()
        if let image = ClipThumbnail.cached(videoID: videoID) {
            thumbnail.image = image
            return
        }
        thumbnailTask = Task { @MainActor [weak self] in
            guard let image = await ClipThumbnail.image(videoID: videoID),
                  !Task.isCancelled,
                  let self, self.thumbnailVideoID == videoID else { return }
            UIView.transition(with: self.thumbnail, duration: 0.3, options: .transitionCrossDissolve) {
                self.thumbnail.image = image
            }
        }
    }

    /// Centers the glow on the player and scales it until it covers the masked
    /// (top) part of the page. `sourceFrame` is in this view's coordinates.
    /// With `coverageMaxX` (side-by-side layout), the glow stays left of that x and
    /// fades out horizontally instead of below the player.
    func track(sourceFrame: CGRect, coverageMaxX: CGFloat? = nil) {
        lastSourceFrame = sourceFrame
        lastCoverageMaxX = coverageMaxX
        guard sourceFrame.width > 0, sourceFrame.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        updateMask(sourceFrame: sourceFrame, coverageMaxX: coverageMaxX)
        let coveredWidth = coveredWidth(for: sourceFrame, coverageMaxX: coverageMaxX)
        let coveredHeight = coverageMaxX == nil ? coveredHeight(for: sourceFrame) : bounds.height
        let center = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        let reachX = max(center.x, coveredWidth - center.x) * 2
        let reachY = max(center.y, coveredHeight - center.y) * 2
        let scale = max(1, max(reachX / sourceFrame.width, reachY / sourceFrame.height))
            * CGFloat(ClipAmbientSettings[.overscan])
        let size = CGRect(origin: .zero, size: sourceFrame.size)
        glow.transform = .identity
        glow.bounds = size
        glow.center = center
        thumbnail.frame = size
        glow.transform = CGAffineTransform(scaleX: scale, y: scale)
    }
}

/// Opaque at the top (or leading edge), fading to clear at the bottom (or trailing) edge.
private final class ClipAmbientGradientView: UIView {
    enum Axis { case vertical, horizontal }

    override class var layerClass: AnyClass { CAGradientLayer.self }
    private var gradient: CAGradientLayer { layer as! CAGradientLayer }

    var axis: Axis = .vertical {
        didSet {
            guard axis != oldValue else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            gradient.startPoint = axis == .vertical ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0, y: 0.5)
            gradient.endPoint = axis == .vertical ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 1, y: 0.5)
            CATransaction.commit()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        gradient.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        gradient.locations = [0, 0.5, 1]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setFade(start: Double) {
        let start = NSNumber(value: min(max(start, 0), 1))
        guard gradient.locations?[1] != start else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.locations = [0, start, 1]
        CATransaction.commit()
    }
}

// MARK: - Tuning screen

/// Half-height sheet over a playing Short: sliders apply live to the glow above.
final class ClipAmbientTuningViewController: UIViewController {
    private let stack = UIStackView()
    private var sliders: [ClipAmbientSettings.Tunable: (slider: UISlider, value: UILabel)] = [:]
    private var switches: [ClipAmbientSettings.Toggle: UISwitch] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Ambient backdrop"
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Reset", primaryAction: UIAction { [weak self] _ in
            ClipAmbientSettings.resetTuning()
            self?.refresh()
        })
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
        ])

        for toggle in ClipAmbientSettings.Toggle.allCases {
            stack.addArrangedSubview(makeSwitchRow(toggle))
        }
        for tunable in ClipAmbientSettings.Tunable.allCases {
            stack.addArrangedSubview(makeSliderRow(tunable))
        }
        refresh()
    }

    private func makeSwitchRow(_ toggle: ClipAmbientSettings.Toggle) -> UIView {
        let label = UILabel()
        label.text = toggle.title
        label.font = .preferredFont(forTextStyle: .body)
        let control = UISwitch()
        control.addAction(UIAction { [weak control] _ in
            guard let control else { return }
            ClipAmbientSettings[toggle] = control.isOn
        }, for: .valueChanged)
        switches[toggle] = control
        let row = UIStackView(arrangedSubviews: [label, control])
        row.alignment = .center
        return row
    }

    private func makeSliderRow(_ tunable: ClipAmbientSettings.Tunable) -> UIView {
        let title = UILabel()
        title.text = tunable.title
        title.font = .preferredFont(forTextStyle: .subheadline)
        title.numberOfLines = 0
        let value = UILabel()
        value.font = .monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .medium)
        value.textColor = .secondaryLabel
        value.setContentHuggingPriority(.required, for: .horizontal)
        let slider = UISlider()
        slider.minimumValue = tunable.range.lowerBound
        slider.maximumValue = tunable.range.upperBound
        slider.addAction(UIAction { [weak slider, weak value] _ in
            guard let slider else { return }
            ClipAmbientSettings[tunable] = slider.value
            value?.text = tunable.format(slider.value)
        }, for: .valueChanged)
        sliders[tunable] = (slider, value)
        let header = UIStackView(arrangedSubviews: [title, value])
        header.alignment = .firstBaseline
        header.spacing = 8
        let row = UIStackView(arrangedSubviews: [header, slider])
        row.axis = .vertical
        row.spacing = 6
        return row
    }

    private func refresh() {
        for (toggle, control) in switches {
            control.isOn = ClipAmbientSettings[toggle]
        }
        for (tunable, row) in sliders {
            let current = ClipAmbientSettings[tunable]
            row.slider.value = current
            row.value.text = tunable.format(current)
        }
    }
}
