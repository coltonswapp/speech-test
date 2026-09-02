//
//  DialogueBubbleUnderglowConfiguration.swift
//  shizen
//
//  Layout and appearance for the speaker-tinted band behind glass dialogue bubbles.
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
    case pink
    case orange
    case green
    case teal
    case purple
    case mint
    case indigo
    case red

    var title: String {
        switch self {
        case .yellow: return "Yellow"
        case .blue: return "Blue"
        case .pink: return "Pink"
        case .orange: return "Orange"
        case .green: return "Green"
        case .teal: return "Teal"
        case .purple: return "Purple"
        case .mint: return "Mint"
        case .indigo: return "Indigo"
        case .red: return "Red"
        }
    }

    var storageKey: String {
        switch self {
        case .yellow: return "yellow"
        case .blue: return "blue"
        case .pink: return "pink"
        case .orange: return "orange"
        case .green: return "green"
        case .teal: return "teal"
        case .purple: return "purple"
        case .mint: return "mint"
        case .indigo: return "indigo"
        case .red: return "red"
        }
    }

    init?(storageKey: String) {
        guard let match = Self.allCases.first(where: { $0.storageKey == storageKey }) else { return nil }
        self = match
    }

    var uiColor: UIColor {
        switch self {
        case .yellow: return .systemYellow
        case .blue: return .systemBlue
        case .pink: return .systemPink
        case .orange: return .systemOrange
        case .green: return .systemGreen
        case .teal: return .systemTeal
        case .purple: return .systemPurple
        case .mint: return .systemMint
        case .indigo: return .systemIndigo
        case .red: return .systemRed
        }
    }

    /// Karaoke wash: same hue as the bubble glow, translucent so glyphs stay readable.
    var tokenHighlightUIColor: UIColor {
        uiColor.withAlphaComponent(0.55)
    }
}

/// Named left/right highlight pairs for Dialogue Recording.
enum DialogueHighlightColorPreset: String, CaseIterable {
    case classic
    case sunset
    case ocean
    case berry
    case forest
    case neon
    case soft
    case warm

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .sunset: return "Sunset"
        case .ocean: return "Ocean"
        case .berry: return "Berry"
        case .forest: return "Forest"
        case .neon: return "Neon"
        case .soft: return "Soft"
        case .warm: return "Warm"
        }
    }

    var subtitle: String {
        "\(leading.title) · \(trailing.title)"
    }

    var leading: DialogueBubbleUnderglowColor {
        switch self {
        case .classic: return .blue
        case .sunset: return .orange
        case .ocean: return .teal
        case .berry: return .purple
        case .forest: return .green
        case .neon: return .indigo
        case .soft: return .mint
        case .warm: return .yellow
        }
    }

    var trailing: DialogueBubbleUnderglowColor {
        switch self {
        case .classic: return .yellow
        case .sunset: return .pink
        case .ocean: return .blue
        case .berry: return .pink
        case .forest: return .mint
        case .neon: return .orange
        case .soft: return .purple
        case .warm: return .orange
        }
    }

    static func matching(leading: DialogueBubbleUnderglowColor, trailing: DialogueBubbleUnderglowColor) -> DialogueHighlightColorPreset? {
        allCases.first { $0.leading == leading && $0.trailing == trailing }
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

    /// Speaker tint from the current Dialogue highlight color settings.
    static func forSpeaker(_ side: DialogueSpeakerSide) -> DialogueBubbleUnderglowConfiguration {
        var config = DialogueBubbleUnderglowConfiguration.default
        config.color = ExperimentSettings.dialogueHighlightColor(for: side)
        return config
    }

    /// Tighter glow for meter pills so blur doesn't bleed past the silhouette.
    static func compactMeter(for side: DialogueSpeakerSide) -> DialogueBubbleUnderglowConfiguration {
        var config = forSpeaker(side)
        config.horizontalInset = 12
        config.blurRadius = 8
        config.offsetX = 0
        return config
    }

    var glowUIColor: UIColor { color.uiColor }

    var tokenHighlightUIColor: UIColor { color.tokenHighlightUIColor }

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
        color: .\(color.title.lowercased())
        """
    }

    private func clampedRatio(_ value: CGFloat) -> CGFloat {
        max(0, min(1, value))
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }
}
