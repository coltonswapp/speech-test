//
//  DefinitionCalloutOutline.swift
//  InteractionKit
//
//  Chrome shared by the compact and rich definition callouts: a raised fill and a
//  hairline rim. A black shadow alone is invisible on a black page and too soft on a
//  light grey one, so without these the callout melted into the content behind it.
//

import UIKit

enum DefinitionCalloutOutline {

    /// One step above the page in either mode: ≈ #3A3A3C over black in dark, white
    /// over the light grey page in light (the old #F2F2F7 matched the page itself).
    static let bubbleFill = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 58 / 255, green: 58 / 255, blue: 60 / 255, alpha: 1)
            : .white
    }

    /// Hairline rim: light on dark, a faint dark edge on light so white-on-white
    /// (the bubbles) still separates.
    static func rimColor(for traits: UITraitCollection) -> UIColor {
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.14)
            : UIColor.black.withAlphaComponent(0.08)
    }

    static let rimWidth: CGFloat = 1

    /// Single outline around the box and its pointer, so the rim has no seam where they meet.
    ///
    /// Matches the arrow as drawn: a `arrowSize` square, rotated 45°, centered on the
    /// box edge, with `arrowCornerRadius` rounding. Its visible half is a right-angled
    /// triangle reaching half the square's diagonal past the edge.
    static func path(
        container: CGRect,
        cornerRadius: CGFloat,
        arrowMidX: CGFloat,
        arrowSize: CGFloat,
        arrowCornerRadius: CGFloat = 3,
        arrowPointsDown: Bool
    ) -> UIBezierPath {
        let r = min(cornerRadius, container.width / 2, container.height / 2)
        let halfDiagonal = arrowSize / 2 * 2.squareRoot()
        // The callouts already keep the arrow off the corners; follow it exactly.
        let midX = arrowMidX
        // Tangent points of the rounded tip sit `arrowCornerRadius` back along each 45° edge.
        let tipInset = arrowCornerRadius / 2.squareRoot()

        let path = UIBezierPath()
        path.move(to: CGPoint(x: container.minX + r, y: container.minY))

        // Top edge (left → right), pointer up when the callout sits below the word.
        if !arrowPointsDown {
            let edge = container.minY
            let tip = edge - halfDiagonal
            path.addLine(to: CGPoint(x: midX - halfDiagonal, y: edge))
            path.addLine(to: CGPoint(x: midX - tipInset, y: tip + tipInset))
            path.addQuadCurve(to: CGPoint(x: midX + tipInset, y: tip + tipInset), controlPoint: CGPoint(x: midX, y: tip))
            path.addLine(to: CGPoint(x: midX + halfDiagonal, y: edge))
        }
        path.addLine(to: CGPoint(x: container.maxX - r, y: container.minY))
        path.addArc(withCenter: CGPoint(x: container.maxX - r, y: container.minY + r),
                    radius: r, startAngle: -.pi / 2, endAngle: 0, clockwise: true)

        // Right edge.
        path.addLine(to: CGPoint(x: container.maxX, y: container.maxY - r))
        path.addArc(withCenter: CGPoint(x: container.maxX - r, y: container.maxY - r),
                    radius: r, startAngle: 0, endAngle: .pi / 2, clockwise: true)

        // Bottom edge (right → left), pointer down when the callout sits above the word.
        if arrowPointsDown {
            let edge = container.maxY
            let tip = edge + halfDiagonal
            path.addLine(to: CGPoint(x: midX + halfDiagonal, y: edge))
            path.addLine(to: CGPoint(x: midX + tipInset, y: tip - tipInset))
            path.addQuadCurve(to: CGPoint(x: midX - tipInset, y: tip - tipInset), controlPoint: CGPoint(x: midX, y: tip))
            path.addLine(to: CGPoint(x: midX - halfDiagonal, y: edge))
        }
        path.addLine(to: CGPoint(x: container.minX + r, y: container.maxY))
        path.addArc(withCenter: CGPoint(x: container.minX + r, y: container.maxY - r),
                    radius: r, startAngle: .pi / 2, endAngle: .pi, clockwise: true)

        // Left edge.
        path.addLine(to: CGPoint(x: container.minX, y: container.minY + r))
        path.addArc(withCenter: CGPoint(x: container.minX + r, y: container.minY + r),
                    radius: r, startAngle: .pi, endAngle: 3 * .pi / 2, clockwise: true)
        path.close()
        return path
    }

    static func makeRimLayer() -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = rimWidth
        layer.lineJoin = .round
        // Above the fill subviews, which are added before this layer.
        layer.zPosition = 1
        return layer
    }
}
