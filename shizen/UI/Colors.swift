//
//  Colors.swift
//  shizen
//
//  Common brand colors shared across the app.
//

import UIKit

enum Colors {
    static let brandYellow: UIColor = .systemYellow
    static let textYellow = UIColor(red: 139/255, green: 110/255, blue: 0/255, alpha: 1)
    /// The yellow CTA's fill and title colors (see `PrimaryButton`).
    static let ctaYellow = UIColor(red: 253/255, green: 200/255, blue: 1/255, alpha: 1)
    static let ctaDarkYellow = UIColor(red: 144/255, green: 114/255, blue: 2/255, alpha: 1)
    /// Hana's sky and pink petals (see `MascotTheme`), light enough to pair with `ctaYellow`.
    static let petalBlue = MascotTheme.sky.petal.uiColor
    static let petalPink = MascotTheme.pink.petal.uiColor
    /// CTA dark yellow on light backgrounds; a brighter gold in dark mode so it stays readable.
    static let deepYellow = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 232/255, green: 182/255, blue: 12/255, alpha: 1)
            : ctaDarkYellow
    }
}
