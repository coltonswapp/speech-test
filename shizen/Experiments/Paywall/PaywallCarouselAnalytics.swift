//
//  PaywallCarouselAnalytics.swift
//  shizen
//
//  How one paywall visit moved through the feature carousel: which cards were seen, how long
//  each stayed up, and whether the learner drove it or let it auto-advance. User-driven page
//  changes send `paywall_carousel_swiped`; `summary` rides on the CTA tap and the dismiss.
//

import Foundation

struct PaywallCarouselAnalytics {
    private let features = PaywallCopy.features
    private var visibleSince: Date?
    private var currentIndex = 0
    private var seen: Set<Int> = []
    private var dwell: [Int: TimeInterval] = [:]
    private var swipes = 0
    private var pageControlTaps = 0
    private var autoAdvances = 0
    private var firstInteractionSeconds: Int?
    private var appearedAt: Date?

    /// The paywall appeared; the current card starts counting again.
    mutating func appeared() {
        let now = Date()
        if appearedAt == nil { appearedAt = now }
        visibleSince = now
        seen.insert(currentIndex)
    }

    /// The paywall went off screen; stop the clock on the current card.
    mutating func disappeared() {
        closeDwell(at: Date())
        visibleSince = nil
    }

    /// Returns the properties for `paywall_carousel_swiped` when the learner drove the change.
    mutating func pageChanged(to index: Int, trigger: PaywallFeatureCarouselView.PageChangeTrigger) -> [String: Any]? {
        let now = Date()
        let from = currentIndex
        closeDwell(at: now)
        currentIndex = index
        seen.insert(index)
        if visibleSince != nil { visibleSince = now }

        switch trigger {
        case .auto:
            autoAdvances += 1
            return nil
        case .swipe: swipes += 1
        case .pageControl: pageControlTaps += 1
        }
        if firstInteractionSeconds == nil, let appearedAt {
            firstInteractionSeconds = Int(now.timeIntervalSince(appearedAt).rounded())
        }
        return [
            "card": cardName(index),
            "card_index": index,
            "from_card": cardName(from),
            "direction": index > from ? "forward" : "back",
            "trigger": trigger.rawValue,
        ]
    }

    /// Carousel state for `paywall_cta_tapped` and `paywall_dismissed`.
    var summary: [String: Any] {
        var dwellSoFar = dwell
        if let visibleSince {
            dwellSoFar[currentIndex, default: 0] += Date().timeIntervalSince(visibleSince)
        }
        var properties: [String: Any] = [
            "current_card": cardName(currentIndex),
            "cards_seen": seen.sorted().map(cardName),
            "cards_seen_count": seen.count,
            "card_count": features.count,
            "max_card_index": seen.max() ?? 0,
            "user_swipes": swipes,
            "page_control_taps": pageControlTaps,
            "auto_advances": autoAdvances,
            "user_drove_carousel": swipes + pageControlTaps > 0,
        ]
        properties["seconds_to_first_swipe"] = firstInteractionSeconds
        for (index, seconds) in dwellSoFar {
            properties["dwell_\(cardName(index))_s"] = (seconds * 10).rounded() / 10
        }
        return properties
    }

    private mutating func closeDwell(at now: Date) {
        guard let visibleSince else { return }
        dwell[currentIndex, default: 0] += now.timeIntervalSince(visibleSince)
    }

    private func cardName(_ index: Int) -> String {
        features.indices.contains(index) ? features[index].kind.rawValue : "unknown"
    }
}
