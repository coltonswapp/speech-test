//
//  DefinitionCalloutPresenter.swift
//  shizen
//
//  Shows the compact definition callout on the hosting view controller's root view.
//  Placement uses the scrubber's bounds (converted into host coordinates) to pick above vs below.
//

import UIKit

final class DefinitionCalloutPresenter {

    static let shared = DefinitionCalloutPresenter()
    private static let horizontalMargin: CGFloat = 8
    private static let maxWidthFraction: CGFloat = 0.70

    private var calloutView: CompactDefinitionCalloutView?
    private weak var hostView: UIView?
    private weak var anchorView: UIView?
    private weak var hostingViewController: UIViewController?
    private var lifecycleChild: CalloutLifecycleChild?

    private init() {}

    func isShowingCallout(at point: CGPoint, in coordinateView: UIView) -> Bool {
        guard let callout = calloutView, let hostView else { return false }
        let pointInHost = coordinateView.convert(point, to: hostView)
        return callout.frame.contains(pointInHost)
    }

    func presentOrUpdate(
        text: String,
        surface: String,
        lineFragments: [CGRect],
        in anchorView: UIView,
        gap: CGFloat = 4,
        onDetailTapped: @escaping (String) -> Void
    ) {
        guard let firstFragment = lineFragments.first, let lastFragment = lineFragments.last else { return }
        guard let hostView = resolveHostView(from: anchorView),
              let viewController = resolveHostingViewController(from: anchorView) else { return }
        attachLifecycle(to: viewController)

        self.hostView = hostView
        self.anchorView = anchorView

        let callout: CompactDefinitionCalloutView
        let isNew: Bool
        if let existing = calloutView {
            callout = existing
            isNew = false
            callout.setText(text)
            if callout.superview !== hostView {
                callout.removeFromSuperview()
                hostView.addSubview(callout)
            }
        } else {
            callout = CompactDefinitionCalloutView(text: text)
            calloutView = callout
            hostView.addSubview(callout)
            isNew = true
        }

        callout.onDetailTapped = { onDetailTapped(surface) }

        let firstLineInHost = anchorView.convert(firstFragment, to: hostView)
        let lastLineInHost = anchorView.convert(lastFragment, to: hostView)
        let anchorBoundsInHost = lineFragments
            .map { anchorView.convert($0, to: hostView) }
            .reduce(firstLineInHost) { $0.union($1) }
        let scrubFrameInHost = anchorView.convert(anchorView.bounds, to: hostView)
        let hostWidth = hostView.bounds.width
        let anchorMidX = anchorBoundsInHost.midX
        let maxCalloutWidth = maxCalloutWidth(hostWidth: hostWidth)
        let size = callout.fittingSize(maxWidth: maxCalloutWidth)
        let width = min(ceil(size.width), maxCalloutWidth)
        let height = ceil(size.height)

        let layout = calloutLayout(
            firstLineInHost: firstLineInHost,
            lastLineInHost: lastLineInHost,
            anchorMidX: anchorMidX,
            scrubFrameInHost: scrubFrameInHost,
            calloutSize: CGSize(width: width, height: height),
            safeFrame: hostView.safeAreaLayoutGuide.layoutFrame,
            hostWidth: hostWidth,
            gap: gap
        )

        callout.setPlacement(layout.placement)
        callout.prepareLayout(width: width)
        callout.frame = layout.frame
        callout.layoutIfNeeded()
        callout.updateArrowPosition(toward: anchorMidX - layout.frame.minX)
        hostView.bringSubviewToFront(callout)

        if isNew {
            callout.showWithAnimation()
        } else {
            UIView.animate(withDuration: 0.15) {
                callout.alpha = 1
            }
        }
    }

    func dismiss(animated: Bool) {
        guard let callout = calloutView else {
            detachLifecycle()
            hostView = nil
            anchorView = nil
            return
        }

        calloutView = nil
        hostView = nil
        anchorView = nil

        if animated {
            callout.dismissWithAnimation { [weak self] in
                self?.detachLifecycle()
            }
        } else {
            callout.layer.removeAllAnimations()
            callout.removeFromSuperview()
            detachLifecycle()
        }
    }

    // MARK: - Layout

    private struct CalloutLayout {
        let placement: CompactDefinitionCalloutView.Placement
        let frame: CGRect
        let arrowAnchorX: CGFloat
    }

    private func maxCalloutWidth(hostWidth: CGFloat) -> CGFloat {
        let margin = Self.horizontalMargin
        let cap = min(hostWidth * Self.maxWidthFraction, hostWidth - margin * 2)
        return max(120, cap)
    }

    private func calloutLayout(
        firstLineInHost: CGRect,
        lastLineInHost: CGRect,
        anchorMidX: CGFloat,
        scrubFrameInHost: CGRect,
        calloutSize: CGSize,
        safeFrame: CGRect,
        hostWidth: CGFloat,
        gap: CGFloat
    ) -> CalloutLayout {
        let margin: CGFloat = 4
        let width = calloutSize.width
        let height = calloutSize.height

        let aboveY = firstLineInHost.minY - height - gap
        let belowY = lastLineInHost.maxY + gap
        let fitsAboveSafe = aboveY >= safeFrame.minY + margin
        let fitsBelowSafe = belowY + height <= safeFrame.maxY - margin

        // Prefer below when the first line sits near the top of the scrubber.
        let nearScrubTop = firstLineInHost.minY - scrubFrameInHost.minY < height + gap + margin

        let placement: CompactDefinitionCalloutView.Placement
        let originY: CGFloat

        if fitsAboveSafe && !nearScrubTop {
            placement = .above
            originY = aboveY
        } else if fitsBelowSafe {
            placement = .below
            originY = belowY
        } else if fitsAboveSafe {
            placement = .above
            originY = max(safeFrame.minY + margin, aboveY)
        } else {
            let spaceAbove = firstLineInHost.minY - safeFrame.minY
            let spaceBelow = safeFrame.maxY - lastLineInHost.maxY
            if spaceAbove >= spaceBelow {
                placement = .above
                originY = max(safeFrame.minY + margin, aboveY)
            } else {
                placement = .below
                originY = min(safeFrame.maxY - margin - height, belowY)
            }
        }

        let edgeMargin = Self.horizontalMargin
        var originX = anchorMidX - width / 2
        let minX = edgeMargin
        let maxX = max(minX, hostWidth - width - edgeMargin)
        originX = max(minX, min(maxX, originX))

        return CalloutLayout(
            placement: placement,
            frame: CGRect(x: originX, y: originY, width: width, height: height),
            arrowAnchorX: anchorMidX
        )
    }

    // MARK: - Host & lifecycle

    private func resolveHostView(from view: UIView) -> UIView? {
        var responder: UIResponder? = view
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController.view
            }
            responder = current.next
        }
        return view.window?.rootViewController?.view
    }

    private func resolveHostingViewController(from view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }

    private func attachLifecycle(to viewController: UIViewController) {
        guard hostingViewController !== viewController else { return }
        detachLifecycle()

        hostingViewController = viewController
        let child = CalloutLifecycleChild()
        child.onHostLeaving = { [weak self] in
            self?.dismiss(animated: false)
        }
        viewController.addChild(child)
        child.view.isHidden = true
        child.view.frame = .zero
        child.view.isUserInteractionEnabled = false
        viewController.view.addSubview(child.view)
        child.didMove(toParent: viewController)
        lifecycleChild = child
    }

    private func detachLifecycle() {
        lifecycleChild?.willMove(toParent: nil)
        lifecycleChild?.view.removeFromSuperview()
        lifecycleChild?.removeFromParent()
        lifecycleChild = nil
        hostingViewController = nil
    }
}
