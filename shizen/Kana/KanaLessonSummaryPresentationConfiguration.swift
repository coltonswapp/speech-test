//
//  KanaLessonSummaryPresentationConfiguration.swift
//  shizen
//

import UIKit

struct KanaLessonSummaryPresentationConfiguration: Equatable {

    // MARK: Layout

    var titleFontSize: CGFloat = 28
    var stackSpacing: CGFloat = 32
    var contentTopInset: CGFloat = 32
    var horizontalInset: CGFloat = 20
    var metricCardCornerRadius: CGFloat = 14
    var metricCardBorderWidth: CGFloat = 2
    var metricsStackSpacing: CGFloat = 10
    var metricCardWidth: CGFloat = 220

    // MARK: Entry animation

    var entryAnimationEnabled = true

    var titleDelay: TimeInterval = 0
    var titleInitialScale: CGFloat = 0.85
    var titleAnimationDuration: TimeInterval = 0.55
    var titleSpringDamping: CGFloat = 0.72

    var cardStaggerDelay: TimeInterval = 0.12
    var cardInitialOffsetY: CGFloat = 24
    var cardAnimationDuration: TimeInterval = 0.45
    var cardSpringDamping: CGFloat = 0.8

    var streakDelay: TimeInterval = 0.25
    var streakAnimationDuration: TimeInterval = 0.35

    var buttonDelay: TimeInterval = 0.35
    var buttonAnimationDuration: TimeInterval = 0.4
    var buttonSpringDamping: CGFloat = 0.78

    static let production = KanaLessonSummaryPresentationConfiguration()
}
