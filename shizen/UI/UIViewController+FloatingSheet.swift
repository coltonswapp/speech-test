//
//  UIViewController+FloatingSheet.swift
//  shizen
//

import UIKit

/// Which bottom corner a regular-width floating sheet pins to (Maps-style).
enum FloatingSheetCorner {
    case bottomLeft
    case bottomRight

    /// Value for the sheet's private `horizontalAlignment`. Left (1) is confirmed;
    /// right (2) is a best guess at the next value.
    var horizontalAlignment: Int {
        switch self {
        case .bottomLeft: return 1
        case .bottomRight: return 2
        }
    }
}

/// How a corner-attached floating sheet sits on iPad.
struct FloatingSheetStyle {
    var corner: FloatingSheetCorner
    var width: CGFloat = 390
    /// Extra room above the sheet at its tallest height, past the system's own top gap.
    /// Nil keeps the system `.large()` height.
    var topMargin: CGFloat?
    /// Gap between the sheet and the window edges it sits along (private
    /// `marginInRegularWidthRegularHeight`).
    var edgeMargin: CGFloat = 10
}

extension UISheetPresentationController.Detent.Identifier {
    /// `.large()` lowered by `FloatingSheetStyle.topMargin`.
    static let floatingTall = Self("floatingTall")
}

extension UIViewController {
    /// `presentFloatingSheet` with a corner attachment's settings bundled.
    func presentFloatingSheet(
        _ content: UIViewController,
        style: FloatingSheetStyle,
        detents: [UISheetPresentationController.Detent] = [.medium(), .large()],
        undimmedThrough: UISheetPresentationController.Detent.Identifier = .large,
        animated: Bool = true
    ) {
        presentFloatingSheet(
            content,
            detents: detents,
            undimmedThrough: undimmedThrough,
            width: style.width,
            attachedCorner: style.corner,
            topMargin: style.topMargin,
            edgeMargin: style.edgeMargin,
            animated: animated
        )
    }

    /// Presents `content` as a resizable, non-dimmed sheet (Maps-style).
    ///
    /// With `attachedCorner` in a regular-width window (iPad), the sheet is `width` wide
    /// and pinned to that bottom corner, using private sheet properties; each is set only
    /// if this iPadOS still has it. It's shown in a navigation controller (wrapping
    /// `content` if needed) with a close button at the bar's leading edge, since the
    /// undimmed screen behind doesn't dismiss it on tap.
    func presentFloatingSheet(
        _ original: UIViewController,
        detents: [UISheetPresentationController.Detent] = [.medium(), .large()],
        undimmedThrough: UISheetPresentationController.Detent.Identifier = .large,
        width: CGFloat = 390,
        attachedCorner: FloatingSheetCorner? = nil,
        topMargin: CGFloat? = nil,
        edgeMargin: CGFloat = 10,
        animated: Bool = true
    ) {
        let regularWidth = traitCollection.horizontalSizeClass == .regular
        let corner = regularWidth ? attachedCorner : nil
        // The close button lives in a navigation bar, so content above the fold (furigana
        // included) starts below it rather than under a floating button.
        let content = corner == nil
            ? original
            : (original as? UINavigationController) ?? UINavigationController(rootViewController: original)
        // In a regular-width window a plain page sheet takes the system's width and ignores
        // `preferredContentSize` (that only applies when edge-attached), so without a corner
        // attachment iPad uses a form sheet, which does honor it.
        content.modalPresentationStyle = regularWidth && corner == nil ? .formSheet : .pageSheet
        let size = CGSize(width: width, height: corner != nil ? view.bounds.height : 0)
        content.preferredContentSize = size
        // A navigation controller can take its size from its root, so size that too.
        (content as? UINavigationController)?.viewControllers.first?.preferredContentSize = size

        // A top margin swaps `.large()` for a custom height that much shorter.
        var resolvedDetents = detents
        var resolvedUndimmed = undimmedThrough
        if corner != nil, let topMargin {
            resolvedDetents = detents.map { detent in
                guard detent.identifier == .large else { return detent }
                return .custom(identifier: .floatingTall) { context in
                    max(context.maximumDetentValue - topMargin, 0)
                }
            }
            if undimmedThrough == .large { resolvedUndimmed = .floatingTall }
        }

        if let sheet = content.sheetPresentationController {
            sheet.detents = resolvedDetents
            sheet.largestUndimmedDetentIdentifier = resolvedUndimmed
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
            // Solid, not Liquid Glass, at every height: with a `topMargin` even the tallest
            // detent is custom, and iOS only turns sheets solid at `.large()`.
            sheet.applySolidNonLargeBackground()

            if let corner {
                sheet.setPrivateValueIfAvailable(corner.horizontalAlignment, forKey: "horizontalAlignment")
                sheet.setPrivateValueIfAvailable(true, forKey: "wantsBottomAttached")
                sheet.setPrivateValueIfAvailable(edgeMargin, forKey: "marginInRegularWidthRegularHeight")
                // Bottom-attached counterpart of the public edge-attached width flag (KVC also
                // finds an underscored `_setWidthFollows…:` setter under this key). Off, the
                // sheet goes full width.
                sheet.setPrivateValueIfAvailable(true, forKey: "widthFollowsPreferredContentSizeWhenBottomAttached")
                // Public: a page sheet sizes to the readable width (936 pt in a 1210 pt window)
                // and ignores `preferredContentSize`; off, the sheet follows `preferredContentSize`.
                sheet.prefersPageSizing = false
            }
        }

        guard corner != nil else {
            present(content, animated: animated)
            return
        }
        Self.addFloatingSheetCloseButton(to: content)
        present(content, animated: animated) {
            // The bottom-attached width is read when the size changes, not at the first
            // layout: nudge the size so the sheet re-measures with the flags above set.
            content.preferredContentSize = CGSize(width: width, height: size.height - 1)
            content.preferredContentSize = size
            content.sheetPresentationController?.animateChanges {
                content.sheetPresentationController?.invalidateDetents()
            }
        }
    }

    /// A close button at the leading end of the sheet's navigation bar, unless its root
    /// already has a leading item.
    private static func addFloatingSheetCloseButton(to content: UIViewController) {
        guard let nav = content as? UINavigationController,
              let root = nav.viewControllers.first,
              root.navigationItem.leftBarButtonItem == nil else { return }
        root.navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak nav] _ in nav?.dismiss(animated: true) }
        )
    }
}

private extension NSObject {
    /// KVC on a private property, skipped (instead of crashing) if this OS doesn't have it.
    /// Checks the same places `setValue(_:forKey:)` looks: `setKey:`, `_setKey:`, then
    /// the instance variables `_key`, `_isKey`, `key`, `isKey`.
    func setPrivateValueIfAvailable(_ value: Any, forKey key: String) {
        let capitalized = key.prefix(1).uppercased() + key.dropFirst()
        let hasSetter = ["set\(capitalized):", "_set\(capitalized):"]
            .contains { responds(to: NSSelectorFromString($0)) }
        let hasIvar = ["_\(key)", "_is\(capitalized)", key, "is\(capitalized)"]
            .contains { name in
                var cls: AnyClass? = type(of: self)
                while let current = cls {
                    if class_getInstanceVariable(current, name) != nil { return true }
                    cls = class_getSuperclass(current)
                }
                return false
            }
        guard hasSetter || (hasIvar && type(of: self).accessInstanceVariablesDirectly) else {
            print("[FloatingSheet] \(type(of: self)) has no \(key); skipping it")
            return
        }
        setValue(value, forKey: key)
    }
}
