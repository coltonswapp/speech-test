//
//  MascotTheme.swift
//  shizen
//
//  Color themes for the flower mascot, taken from the design sheet.
//  `ink` draws eyes, arcs and brows; dark faces use white ink.
//

import UIKit

struct MascotTheme: Equatable {

    /// Plain RGB so themes can be blended frame by frame.
    struct RGB: Equatable {
        var r: CGFloat
        var g: CGFloat
        var b: CGFloat

        init(_ hex: UInt32) {
            r = CGFloat((hex >> 16) & 0xFF) / 255
            g = CGFloat((hex >> 8) & 0xFF) / 255
            b = CGFloat(hex & 0xFF) / 255
        }

        init(r: CGFloat, g: CGFloat, b: CGFloat) {
            self.r = r
            self.g = g
            self.b = b
        }

        func mixed(with other: RGB, _ t: CGFloat) -> RGB {
            RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
        }

        var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
        var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
    }

    var name: String
    var petal: RGB
    var face: RGB
    var ink: RGB
    var spark = RGB(0xFFC80D)

    /// Pupils sitting on the whites always use this, even when `ink` is white.
    static let darkInk = RGB(0x0F0809)
    private static let whiteInk = RGB(0xFFFFFF)

    static let pink = MascotTheme(name: "Pink", petal: RGB(0xFFA3C2), face: RGB(0xF2334A), ink: darkInk)
    static let blush = MascotTheme(name: "Blush", petal: RGB(0xFDDCDD), face: RGB(0xF45A6E), ink: darkInk)
    static let cream = MascotTheme(name: "Cream", petal: RGB(0xFFF3DA), face: RGB(0xF7B30F), ink: darkInk)
    static let sunflower = MascotTheme(name: "Sunflower", petal: RGB(0xFFE287), face: RGB(0xF47C14), ink: darkInk)
    static let mint = MascotTheme(name: "Mint", petal: RGB(0xBEE8C4), face: RGB(0x3E9A58), ink: darkInk)
    static let sky = MascotTheme(name: "Sky", petal: RGB(0xA9D1FA), face: RGB(0x1E7BD8), ink: darkInk)
    static let lavender = MascotTheme(name: "Lavender", petal: RGB(0xD4A6F2), face: RGB(0x7B2FB8), ink: darkInk)
    static let lilac = MascotTheme(name: "Lilac", petal: RGB(0xD9BDF8), face: RGB(0x8640C8), ink: darkInk)
    static let night = MascotTheme(name: "Night", petal: RGB(0xA9D3FB), face: RGB(0x0F2A6E), ink: whiteInk)
    static let peach = MascotTheme(name: "Peach", petal: RGB(0xFFD4B2), face: RGB(0xF07A12), ink: darkInk)
    static let coral = MascotTheme(name: "Coral", petal: RGB(0xFBA48A), face: RGB(0xE23A2E), ink: darkInk)
    static let stone = MascotTheme(name: "Stone", petal: RGB(0xCFCAC6), face: RGB(0x2A2828), ink: whiteInk)

    static let all: [MascotTheme] = [
        pink, blush, cream, sunflower, mint, sky,
        lavender, lilac, night, peach, coral, stone,
    ]

    private static let savedKey = "MascotTheme.selected"

    /// The user's chosen theme, persisted by name. New mascots start with it.
    static var saved: MascotTheme {
        get {
            let name = UserDefaults.standard.string(forKey: savedKey)
            return all.first { $0.name == name } ?? .pink
        }
        set { UserDefaults.standard.set(newValue.name, forKey: savedKey) }
    }
}
