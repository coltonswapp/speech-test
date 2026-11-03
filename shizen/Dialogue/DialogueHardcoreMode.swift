//
//  DialogueHardcoreMode.swift
//  shizen
//
//  Learner preference: first listens show only per-speaker live meters,
//  no transcript, until playback finishes.
//

import UIKit

enum DialogueHardcoreMode {
    private static let isEnabledKey = "DialogueHardcoreModeEnabled"

    /// Feature flag: DEBUG builds only for now. Release builds hide the menu
    /// toggle and badge and treat the mode as off even if the default is set.
    #if DEBUG
    static let isAvailable = true
    #else
    static let isAvailable = false
    #endif

    static var isEnabled: Bool {
        get { isAvailable && UserDefaults.standard.bool(forKey: isEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: isEnabledKey) }
    }

    /// Skull mark for menus, badges, and the score receipt. SF Symbols has no
    /// skull, so a `HardcoreSkull` template asset wins when present and the
    /// drawn fallback covers it otherwise.
    static let icon: UIImage = UIImage(named: "HardcoreSkull")?.withRenderingMode(.alwaysTemplate)
        ?? drawnSkull(side: 24)

    /// Filled skull on a 24pt grid: rounded cranium and jaw, with eyes, nose,
    /// and tooth gaps knocked out so the tint reads as the bone.
    private static func drawnSkull(side: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { context in
            let ctx = context.cgContext
            ctx.scaleBy(x: side / 24, y: side / 24)
            UIColor.black.setFill()

            UIBezierPath(roundedRect: CGRect(x: 3, y: 2, width: 18, height: 15.5), cornerRadius: 8.5).fill()
            UIBezierPath(roundedRect: CGRect(x: 6.5, y: 13, width: 11, height: 9), cornerRadius: 2.5).fill()

            ctx.setBlendMode(.clear)
            UIBezierPath(ovalIn: CGRect(x: 6, y: 8, width: 5, height: 5.2)).fill()
            UIBezierPath(ovalIn: CGRect(x: 13, y: 8, width: 5, height: 5.2)).fill()

            let nose = UIBezierPath()
            nose.move(to: CGPoint(x: 12, y: 13.6))
            nose.addLine(to: CGPoint(x: 13.3, y: 16))
            nose.addLine(to: CGPoint(x: 10.7, y: 16))
            nose.close()
            nose.fill()

            for x in [9.6, 11.55, 13.5] as [CGFloat] {
                UIBezierPath(roundedRect: CGRect(x: x, y: 18.2, width: 0.9, height: 3.8), cornerRadius: 0.45).fill()
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}
