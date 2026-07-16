//
//  ExperimentPalette.swift
//  shizen
//
//  Shared adaptive colors used by debug experiments so light/dark feel consistent.
//

import UIKit

enum ExperimentPalette {
    /// Page background used behind the kana charts. The light variant is a warm gray
    /// (`#F2F2F2`) — `systemGroupedBackground` is too dim in light mode against the
    /// white cards but is the right base in dark.
    static let pageBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemGroupedBackground
            : UIColor(red: 0.949, green: 0.949, blue: 0.949, alpha: 1)
    }

    /// Card / tile surface — white in light, raised secondary-grouped in dark.
    static let cardSurface = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .secondarySystemGroupedBackground
            : .white
    }

    /// Drag card surface — one step lighter than `cardSurface` in dark so it stands out
    /// from the background without relying on shadows.
    static let dragCardSurface = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .tertiarySystemGroupedBackground
            : .white
    }

    /// Card border for outlined tiles across kana learning steps.
    static let cardBorder = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.12)
            : UIColor(red: 0.88, green: 0.88, blue: 0.88, alpha: 1)
    }

    /// Unfilled background of lesson header and kana-card progress bars.
    static let progressBarTrack = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.36, blue: 0.12, alpha: 1)
            : UIColor(red: 1, green: 0.93, blue: 0.65, alpha: 1)
    }

    /// Selected / drop-highlight fill (warm yellow tinted for both modes).
    static let highlightFill = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.55, green: 0.46, blue: 0.10, alpha: 0.55)
            : UIColor(red: 1, green: 0.97, blue: 0.82, alpha: 1)
    }

    /// Border that pairs with `highlightFill`.
    static let highlightBorder = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.85, blue: 0.30, alpha: 1)
            : UIColor(red: 0.85, green: 0.72, blue: 0.18, alpha: 1)
    }

    /// Success-state fill (soft green).
    static let successFill = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.20, green: 0.42, blue: 0.22, alpha: 0.55)
            : UIColor(red: 0.86, green: 0.95, blue: 0.86, alpha: 1)
    }

    /// Success-state border.
    static let successBorder = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.55, green: 0.85, blue: 0.58, alpha: 1)
            : UIColor(red: 0.35, green: 0.72, blue: 0.38, alpha: 1)
    }

    /// Incorrect-answer fill (soft red).
    static let errorFill = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.52, green: 0.22, blue: 0.18, alpha: 0.55)
            : UIColor(red: 1, green: 0.90, blue: 0.88, alpha: 1)
    }

    /// Incorrect-answer border.
    static let errorBorder = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.55, blue: 0.45, alpha: 1)
            : UIColor(red: 0.92, green: 0.35, blue: 0.28, alpha: 1)
    }

    /// Subtle separator / underline (denser than `.separator` for emphasis lines).
    static let prominentSeparator = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.45, alpha: 1)
            : UIColor(white: 0.78, alpha: 1)
    }
}

/// Shared stroke geometry for kana cards, choice tiles, and drag cards.
enum ExperimentCardStroke {
    static let normalWidth: CGFloat = 1
    static let emphasisWidth: CGFloat = 3

    /// Romaji/sound choice panels and tap-to-spell kana tiles.
    static let choiceCornerRadius: CGFloat = 12
    /// Square hiragana drag cards in sound match.
    static let kanaDragCornerRadius: CGFloat = 14
}
