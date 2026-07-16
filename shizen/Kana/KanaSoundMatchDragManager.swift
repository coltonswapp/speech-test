//
//  KanaSoundMatchDragManager.swift
//  shizen
//
//  Custom pan-gesture drag coordinator for the kana ↔ romaji match experiment.
//  Pattern follows hardway-craps BetDragManager (ghost view, center hit-test, target highlight).
//

import UIKit

// MARK: - Protocols

protocol KanaSoundDropTarget: AnyObject {
    var choiceValue: String { get }
    func highlightAsDropTarget()
    func unhighlightAsDropTarget()
    func hitFrameInContainer(_ container: UIView) -> CGRect
    func kanaLandingCenter(in container: UIView) -> CGPoint
    func placeDraggedContent(_ text: String)
    func clearPlacedContent()
}

protocol KanaSoundDragSource: AnyObject {
    var draggedText: String { get }
    var correctChoice: String { get }
    func hideForDrag()
    func showAfterDrag()
    func homeCenter(in container: UIView) -> CGPoint
    func makeDragGhostView() -> UIView
}

// MARK: - Drag manager

final class KanaSoundMatchDragManager {

    static let shared = KanaSoundMatchDragManager()

    private(set) var isDragging = false

    private var dropTargets: [KanaSoundDropTarget] = []
    private weak var source: KanaSoundDragSource?
    private weak var highlightedTarget: KanaSoundDropTarget?
    private weak var containerView: UIView?

    private var ghostView: UIView?
    private var ghostTouchOffset = CGPoint.zero
    private var homeCenter = CGPoint.zero
    private let hoverHaptic = UIImpactFeedbackGenerator(style: .light)

    private init() {}

    func registerDropTarget(_ target: KanaSoundDropTarget) {
        guard !dropTargets.contains(where: { $0 === target }) else { return }
        dropTargets.append(target)
    }

    func unregisterDropTarget(_ target: KanaSoundDropTarget) {
        dropTargets.removeAll { $0 === target }
    }

    func startDragging(from source: KanaSoundDragSource, touchLocation: CGPoint, in container: UIView) {
        cancelDrag(animated: false)

        self.source = source
        containerView = container
        homeCenter = source.homeCenter(in: container)
        isDragging = true
        hoverHaptic.prepare()
        ExperimentFeedbackSound.prepareDragHoverClick()

        let ghost = source.makeDragGhostView()
        ghost.translatesAutoresizingMaskIntoConstraints = true
        let ghostSize: CGSize
        if let sourceView = source as? UIView, sourceView.bounds.width > 0 {
            ghostSize = sourceView.bounds.size
        } else {
            ghostSize = CGSize(
                width: KanaSoundMatchMetrics.kanaCardSide,
                height: KanaSoundMatchMetrics.kanaCardSide
            )
        }
        ghost.bounds = CGRect(origin: .zero, size: ghostSize)
        ghost.center = homeCenter
        ghost.layer.zPosition = 1000
        ghost.layer.shadowPath = UIBezierPath(
            roundedRect: ghost.bounds,
            cornerRadius: KanaSoundMatchMetrics.kanaCardCornerRadius
        ).cgPath
        container.addSubview(ghost)
        ghostView = ghost

        ghostTouchOffset = CGPoint(
            x: touchLocation.x - ghost.center.x,
            y: touchLocation.y - ghost.center.y
        )

        source.hideForDrag()

        UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            ghost.transform = CGAffineTransform(
                scaleX: KanaSoundMatchMetrics.kanaCardDragScale,
                y: KanaSoundMatchMetrics.kanaCardDragScale
            )
        }
    }

    func updateDrag(to touchLocation: CGPoint) {
        guard let ghost = ghostView, let container = containerView else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ghost.center = CGPoint(
            x: touchLocation.x - ghostTouchOffset.x,
            y: touchLocation.y - ghostTouchOffset.y
        )
        CATransaction.commit()

        let newTarget = resolveHoverTarget(at: ghost.center, in: container)

        if let previous = highlightedTarget, previous !== newTarget {
            previous.unhighlightAsDropTarget()
        }
        if let newTarget, newTarget !== highlightedTarget {
            newTarget.highlightAsDropTarget()
            playHoverFeedback()
        }
        highlightedTarget = newTarget
    }

    func endDrag(at touchLocation: CGPoint, in container: UIView) {
        updateDrag(to: touchLocation)

        guard let ghost = ghostView, let source else {
            cancelDrag(animated: true)
            return
        }

        let target = highlightedTarget
        if target == nil {
            highlightedTarget?.unhighlightAsDropTarget()
        }
        highlightedTarget = nil

        if let target {
            animateGhostSnap(
                ghost: ghost,
                center: target.kanaLandingCenter(in: container),
                transform: placedTransform(from: source),
                duration: 0.3,
                damping: 0.86
            ) { _ in
                (source as? KanaSoundMatchDragDelegate)?.dragDidPlace(
                    draggedText: source.draggedText,
                    on: target
                )
                self.cleanup(restoreSource: false)
            }
        } else if let placedTarget = (source as? KanaSoundMatchDragDelegate)?.placedDropTargetForSnapBack() {
            animateGhostSnap(
                ghost: ghost,
                center: placedTarget.kanaLandingCenter(in: container),
                transform: placedTransform(from: source),
                duration: 0.3,
                damping: 0.86
            ) { _ in
                (source as? KanaSoundDragSource)?.showAfterDrag()
                placedTarget.placeDraggedContent(source.draggedText)
                self.cleanup(restoreSource: false)
            }
        } else {
            snapBackGhost(from: ghost, source: source)
        }
    }

    private func playHoverFeedback() {
        hoverHaptic.impactOccurred()
        hoverHaptic.prepare()
        ExperimentFeedbackSound.playDragHoverClick()
    }

    func cancelDrag(animated: Bool = true) {
        highlightedTarget?.unhighlightAsDropTarget()
        highlightedTarget = nil

        if let ghost = ghostView, let source, animated {
            snapBackGhost(from: ghost, source: source)
        } else {
            cleanup(restoreSource: true)
        }
    }

    private func resolveHoverTarget(at point: CGPoint, in container: UIView) -> KanaSoundDropTarget? {
        let visibleTargets = dropTargets.filter { isVisibleTarget($0) }

        if let current = highlightedTarget, isVisibleTarget(current) {
            let stayFrame = current.hitFrameInContainer(container).insetBy(
                dx: KanaSoundMatchMetrics.hoverExitContraction,
                dy: KanaSoundMatchMetrics.hoverExitContraction
            )
            if stayFrame.contains(point) {
                return current
            }
        }

        return visibleTargets.last { target in
            let enterFrame = target.hitFrameInContainer(container).insetBy(
                dx: -KanaSoundMatchMetrics.hoverEnterExpansion,
                dy: -KanaSoundMatchMetrics.hoverEnterExpansion
            )
            return enterFrame.contains(point)
        }
    }

    private func isVisibleTarget(_ target: KanaSoundDropTarget) -> Bool {
        guard let view = target as? UIView,
              view.window != nil,
              !view.isHidden,
              view.alpha > 0.01
        else { return false }
        return true
    }

    private func placedTransform(from source: KanaSoundDragSource) -> CGAffineTransform {
        if let delegate = source as? KanaSoundMatchDragDelegate {
            return delegate.placedTransformForDrop()
        }
        let scale = KanaSoundMatchMetrics.placedCardScale
        return CGAffineTransform(scaleX: scale, y: scale)
    }

    private func animateGhostSnap(
        ghost: UIView,
        center: CGPoint,
        transform: CGAffineTransform,
        duration: TimeInterval,
        damping: CGFloat,
        completion: @escaping (Bool) -> Void
    ) {
        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: damping,
            initialSpringVelocity: 0.35,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: {
                ghost.center = center
                ghost.transform = transform
                ghost.alpha = 1
            },
            completion: completion
        )
    }

    private func snapBackGhost(from ghost: UIView, source: KanaSoundDragSource) {
        guard let container = containerView else {
            cleanup(restoreSource: true)
            return
        }
        let destination = source.homeCenter(in: container)
        let dockTransform = (source as? KanaSoundMatchDragDelegate)?.dockTransformForDrag() ?? .identity
        animateGhostSnap(
            ghost: ghost,
            center: destination,
            transform: dockTransform,
            duration: 0.32,
            damping: 0.82
        ) { _ in
            self.cleanup(restoreSource: true)
        }
    }

    private func cleanup(restoreSource: Bool) {
        ghostView?.removeFromSuperview()
        ghostView = nil
        if restoreSource {
            source?.showAfterDrag()
        }
        source = nil
        containerView = nil
        isDragging = false
        ghostTouchOffset = .zero
    }
}

protocol KanaSoundMatchDragDelegate: KanaSoundDragSource {
    func dragDidPlace(draggedText: String, on target: KanaSoundDropTarget)
    func placedDropTargetForSnapBack() -> KanaSoundDropTarget?
    /// Final transform for the ghost while snapping onto a slot (scale + rotation).
    func placedTransformForDrop() -> CGAffineTransform
    /// Transform when snapping the ghost back to the dock.
    func dockTransformForDrag() -> CGAffineTransform
}
