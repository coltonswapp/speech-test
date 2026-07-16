//
//  KanaSoundMatchBounceAnimation.swift
//  shizen
//
//  Shared success-bounce animation for kana sound matching.
//

import UIKit

struct KanaSoundMatchBounceConfiguration: Equatable {
    var height: CGFloat
    var anticipationDrop: CGFloat
    var duration: TimeInterval
    /// Height multiplier for the first rebound off the floor.
    var firstReboundRatio: CGFloat
    /// Height multiplier for the second (tiny) rebound.
    var secondReboundRatio: CGFloat
    /// Horizontal scale at anticipation squash (y uses `anticipationSquashY`).
    var anticipationSquashX: CGFloat
    var anticipationSquashY: CGFloat
    /// Horizontal scale at peak stretch (y uses `peakStretchY`).
    var peakStretchX: CGFloat
    var peakStretchY: CGFloat
    /// Horizontal scale on primary floor impact (y uses `floorSquashY`).
    var floorSquashX: CGFloat
    var floorSquashY: CGFloat
    /// Horizontal scale on first rebound stretch (y uses `firstReboundStretchY`).
    var firstReboundStretchX: CGFloat
    var firstReboundStretchY: CGFloat
    /// Horizontal scale on second floor (y uses `secondFloorSquashY`).
    var secondFloorSquashX: CGFloat
    var secondFloorSquashY: CGFloat

    static let production = KanaSoundMatchBounceConfiguration(
        height: KanaSoundMatchMetrics.successBounceHeight,
        anticipationDrop: KanaSoundMatchMetrics.successBounceAnticipationDrop,
        duration: KanaSoundMatchMetrics.successBounceDuration,
        firstReboundRatio: 0.10,
        secondReboundRatio: 0.03125,
        anticipationSquashX: 1.06,
        anticipationSquashY: 0.95,
        peakStretchX: 0.96,
        peakStretchY: 1.04,
        floorSquashX: 1.07,
        floorSquashY: 0.94,
        firstReboundStretchX: 0.97,
        firstReboundStretchY: 1.03,
        secondFloorSquashX: 1.03,
        secondFloorSquashY: 0.98
    )
}

extension UIView {
    /// Vertical bounce using `transform` so Auto Layout and an existing placed rotation are preserved.
    func animateKanaSoundMatchBounce(
        configuration: KanaSoundMatchBounceConfiguration = .production,
        baseTransform: CGAffineTransform = .identity,
        successSound: ExperimentFeedbackSound.PreparedSuccessSound? = nil,
        successChimeKeyTime: TimeInterval? = nil,
        completion: (() -> Void)? = nil
    ) {
        layer.removeAllAnimations()

        let height = configuration.height
        let drop = configuration.anticipationDrop
        let duration = configuration.duration

        if let successSound {
            let keyTime = successChimeKeyTime ?? KanaSoundMatchMetrics.successChimeKeyTime
            let chimeDelay = duration * keyTime
            DispatchQueue.main.asyncAfter(deadline: .now() + chimeDelay) {
                ExperimentFeedbackSound.playPreparedSuccessSound(successSound)
            }
        }

        func t(_ dy: CGFloat, sx: CGFloat = 1, sy: CGFloat = 1) -> NSValue {
            let xform = baseTransform.translatedBy(x: 0, y: dy).scaledBy(x: sx, y: sy)
            return NSValue(caTransform3D: CATransform3DMakeAffineTransform(xform))
        }

        let anim = CAKeyframeAnimation(keyPath: "transform")
        anim.values = [
            t(0),
            t(drop, sx: configuration.anticipationSquashX, sy: configuration.anticipationSquashY),
            t(-height, sx: configuration.peakStretchX, sy: configuration.peakStretchY),
            t(0, sx: configuration.floorSquashX, sy: configuration.floorSquashY),
            t(
                -height * configuration.firstReboundRatio,
                sx: configuration.firstReboundStretchX,
                sy: configuration.firstReboundStretchY
            ),
            t(0, sx: configuration.secondFloorSquashX, sy: configuration.secondFloorSquashY),
            t(-height * configuration.secondReboundRatio),
            t(0),
        ]
        anim.keyTimes = [0, 0.12, 0.34, 0.54, 0.68, 0.80, 0.90, 1.0]
        anim.timingFunctions = [
            CAMediaTimingFunction(name: .easeIn),
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn),
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn),
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn),
        ]
        anim.duration = duration
        anim.isRemovedOnCompletion = true

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            self.transform = baseTransform
            completion?()
        }
        transform = baseTransform
        layer.add(anim, forKey: "bounceAnimation")
        CATransaction.commit()
    }
}
