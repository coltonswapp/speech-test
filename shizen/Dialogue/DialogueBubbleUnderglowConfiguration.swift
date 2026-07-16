//
//  DialogueBubbleUnderglowConfiguration.swift
//  shizen
//
//  Layout and appearance for the yellow band behind glass dialogue bubbles.
//

import UIKit

enum DialogueBubbleUnderglowVerticalEdge: Int, CaseIterable {
    case top
    case center
    case bottom

    var title: String {
        switch self {
        case .top: return "Top"
        case .center: return "Center"
        case .bottom: return "Bottom"
        }
    }
}

enum DialogueBubbleUnderglowColor: Int, CaseIterable {
    case yellow
    case blue

    var title: String {
        switch self {
        case .yellow: return "Yellow"
        case .blue: return "Blue"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .yellow: return .systemYellow
        case .blue: return .systemBlue
        }
    }
}

struct DialogueBubbleUnderglowConfiguration {
    var verticalEdge: DialogueBubbleUnderglowVerticalEdge = .bottom
    var heightRatio: CGFloat = 0.12
    var widthRatio: CGFloat = 1.0
    var horizontalInset: CGFloat = 0
    var offsetX: CGFloat = -2.86
    var offsetY: CGFloat = -5.88
    var opacity: CGFloat = 0.39
    var cornerRadius: CGFloat = 36
    /// Softens the underglow edges via radial falloff and outer shadow blur.
    var blurRadius: CGFloat = 14
    var color: DialogueBubbleUnderglowColor = .yellow

    static let `default` = DialogueBubbleUnderglowConfiguration()

    var glowUIColor: UIColor { color.uiColor }

    func glowFrame(in bubbleBounds: CGRect) -> CGRect {
        guard bubbleBounds.width > 0, bubbleBounds.height > 0 else { return .zero }

        let availableWidth = max(0, bubbleBounds.width - horizontalInset * 2)
        let glowWidth = availableWidth * clampedRatio(widthRatio)
        let glowHeight = bubbleBounds.height * clampedRatio(heightRatio)

        let centerX = bubbleBounds.midX + offsetX
        let centerY: CGFloat
        switch verticalEdge {
        case .top:
            centerY = glowHeight / 2 + offsetY
        case .center:
            centerY = bubbleBounds.midY + offsetY
        case .bottom:
            centerY = bubbleBounds.height - glowHeight / 2 + offsetY
        }

        return CGRect(
            x: centerX - glowWidth / 2,
            y: centerY - glowHeight / 2,
            width: glowWidth,
            height: glowHeight
        )
    }

    func debugSummary() -> String {
        let edgeName: String
        switch verticalEdge {
        case .top: edgeName = ".top"
        case .center: edgeName = ".center"
        case .bottom: edgeName = ".bottom"
        }
        return """
        verticalEdge: \(edgeName)
        heightRatio: \(format(heightRatio))
        widthRatio: \(format(widthRatio))
        horizontalInset: \(format(horizontalInset))
        offsetX: \(format(offsetX))
        offsetY: \(format(offsetY))
        opacity: \(format(opacity))
        cornerRadius: \(format(cornerRadius))
        blurRadius: \(format(blurRadius))
        color: .\(color == .yellow ? "yellow" : "blue")
        """
    }

    private func clampedRatio(_ value: CGFloat) -> CGFloat {
        max(0, min(1, value))
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }
}
