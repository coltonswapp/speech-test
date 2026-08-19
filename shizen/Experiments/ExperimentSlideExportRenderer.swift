//
//  ExperimentSlideExportRenderer.swift
//  shizen
//
//  Shared export canvas presets and offscreen rendering for social slideshow
//  experiments (kanji decomposition, register ladder, etc.).
//

import UIKit

/// Export canvas presets for different sharing surfaces. Point sizes are all @3x,
/// matching common social-post pixel dimensions.
enum ExperimentExportSize: CaseIterable {
    case feedPortrait
    case square
    case story

    var title: String {
        switch self {
        case .feedPortrait: return "Post (4:5)"
        case .square: return "Square (1:1)"
        case .story: return "Story (9:16)"
        }
    }

    /// Short label for the on-screen export-size control.
    var shortTitle: String {
        switch self {
        case .feedPortrait: return "4:5"
        case .square: return "1:1"
        case .story: return "9:16"
        }
    }

    /// Point size; @3x renders to the pixel size noted below.
    var canvasSize: CGSize {
        switch self {
        case .feedPortrait: return CGSize(width: 360, height: 450) // -> 1080x1350
        case .square: return CGSize(width: 360, height: 360) // -> 1080x1080
        case .story: return CGSize(width: 360, height: 640) // -> 1080x1920
        }
    }
}

enum ExperimentSlideExportRenderer {
    private static let scale: CGFloat = 3

    /// `view` is rendered at `size` regardless of its current frame. Auto Layout views
    /// need a real window to resolve constraints/rendering correctly, so `view` is briefly
    /// hosted in a window scened off `windowScene` (or an unscened fallback window), then
    /// removed once the image is captured.
    @MainActor
    static func image(for view: UIView, size: CGSize, in windowScene: UIWindowScene?) -> UIImage {
        let window: UIWindow
        if let windowScene {
            window = UIWindow(windowScene: windowScene)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: size))
        }
        window.frame = CGRect(origin: .zero, size: size)
        window.isHidden = false

        view.frame = CGRect(origin: .zero, size: size)
        window.addSubview(view)
        window.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }

        view.removeFromSuperview()
        window.isHidden = true

        return image
    }
}

typealias KanjiDecompositionExportSize = ExperimentExportSize
typealias KanjiDecompositionExportRenderer = ExperimentSlideExportRenderer
