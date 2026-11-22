//
//  ContentColumn.swift
//  shizen
//
//  Max widths for content on wide windows (iPad, power-user landscape). Phones
//  never reach these widths, so their layouts are unchanged.
//

import UIKit

enum ContentColumn {
    /// Text-led screens: lesson transcript, quiz, practice.
    static let readableWidth: CGFloat = 680
    /// Lesson detail (hero + scene list).
    static let lessonDetailWidth: CGFloat = 720
    /// Lesson path: stones on the left of the column, titles beside them.
    static let lessonPathWidth: CGFloat = 620

    /// Side inset that keeps content within `maxWidth`, never less than `minimum`.
    static func sideInset(forWidth width: CGFloat, minimum: CGFloat, maxWidth: CGFloat = readableWidth) -> CGFloat {
        max(minimum, (width - maxWidth) / 2)
    }

    /// The centered column within `width`: its leading x and its width.
    static func column(inWidth width: CGFloat, maxWidth: CGFloat) -> (minX: CGFloat, width: CGFloat) {
        let columnWidth = min(width, maxWidth)
        return (max(0, (width - columnWidth) / 2), columnWidth)
    }

    /// Horizontal constraints for `content` in a vertically scrolling `scrollView`:
    /// centered, `inset` from each edge, and no wider than `maxWidth`. The caller
    /// still pins top and bottom to the content layout guide.
    static func horizontalConstraints(
        for content: UIView,
        in scrollView: UIScrollView,
        inset: CGFloat,
        maxWidth: CGFloat = readableWidth
    ) -> [NSLayoutConstraint] {
        let frame = scrollView.frameLayoutGuide
        return [
            scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: frame.widthAnchor),
        ] + horizontalConstraints(
            for: content,
            centerX: frame.centerXAnchor,
            width: frame.widthAnchor,
            inset: inset,
            maxWidth: maxWidth
        )
    }

    /// Horizontal constraints for `content` in a non-scrolling `container`:
    /// centered, `inset` from each edge, and no wider than `maxWidth`.
    static func horizontalConstraints(
        for content: UIView,
        in container: UIView,
        inset: CGFloat,
        maxWidth: CGFloat = readableWidth
    ) -> [NSLayoutConstraint] {
        horizontalConstraints(
            for: content,
            centerX: container.centerXAnchor,
            width: container.widthAnchor,
            inset: inset,
            maxWidth: maxWidth
        )
    }

    private static func horizontalConstraints(
        for content: UIView,
        centerX: NSLayoutXAxisAnchor,
        width: NSLayoutDimension,
        inset: CGFloat,
        maxWidth: CGFloat
    ) -> [NSLayoutConstraint] {
        let fill = content.widthAnchor.constraint(equalTo: width, constant: -inset * 2)
        fill.priority = .required - 1
        return [
            content.centerXAnchor.constraint(equalTo: centerX),
            content.widthAnchor.constraint(lessThanOrEqualTo: width, constant: -inset * 2),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
            fill,
        ]
    }
}
