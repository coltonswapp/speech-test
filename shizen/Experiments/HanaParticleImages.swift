//
//  HanaParticleImages.swift
//  shizen
//
//  Still snapshots of Hana for SpriteKit bursts. Eyes are left off so a
//  handful of particles stays readable at emoji size.
//

import UIKit

struct HanaParticleSettings: Equatable {
    /// One saved-theme color. Size and spin still vary. Off mixes every theme.
    var consistent = false
    /// Sprite size in points. Varied bursts scatter around this.
    var particleSize: CGFloat = 52
    var petalScale: CGFloat = 0.88
    var faceScale: CGFloat = 1
    var petalSpread: CGFloat = 0.6
    var petalWobble: CGFloat = 0.6
}

enum HanaParticleImages {
    private static var cacheKey: HanaParticleSettings?
    private static var cacheThemeName: String?
    private static var cache: [UIImage] = []

    static func images(for settings: HanaParticleSettings) -> [UIImage] {
        let themeName = settings.consistent ? MascotTheme.saved.name : nil
        if cacheKey == settings, cacheThemeName == themeName, !cache.isEmpty {
            return cache
        }
        let themes = settings.consistent ? [MascotTheme.saved] : MascotTheme.all
        let images = themes.map { render($0, settings: settings) }
        cacheKey = settings
        cacheThemeName = themeName
        cache = images
        return images
    }

    private static func render(_ theme: MascotTheme, settings: HanaParticleSettings) -> UIImage {
        let side: CGFloat = 128
        let mascot = MascotView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        mascot.idleMotionEnabled = false
        mascot.autoBlinkEnabled = false
        mascot.hapticsEnabled = false
        mascot.showsEyes = false
        mascot.petalScale = settings.petalScale
        mascot.faceScale = settings.faceScale
        mascot.petalSpread = settings.petalSpread
        mascot.petalWobble = settings.petalWobble
        mascot.setTheme(theme, animated: false)
        mascot.set(MascotExpression(), animated: false)
        mascot.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(bounds: mascot.bounds, format: format)
        return renderer.image { context in
            mascot.layer.render(in: context.cgContext)
        }
    }
}
