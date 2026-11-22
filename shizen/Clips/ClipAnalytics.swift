//
//  ClipAnalytics.swift
//  shizen
//
//  Funnel events for one clip visit: played, completed, and swiped each fire at most
//  once and share clip id, source, and on-screen seconds. The feed owns the visit for
//  the clip on screen; a standalone player owns its own. Neighbors are not given a visit,
//  so a preloaded page never counts.
//

import Foundation

enum ClipAnalytics {
    static let mainTab = "main_tab"
    static let explore = "explore"
    static let search = "search"
    static let tag = "tag"
    static let channel = "channel"
    static let moreFromVideo = "more_from_video"
    static let deepLink = "deep_link"
    /// Debug clip list (Experiments → Clip transcripts).
    static let list = "list"
    /// Profile → Saved Clips.
    static let saved = "saved"
    /// Onboarding's real-clips step.
    static let onboarding = "onboarding"
    /// Dictionary, breakdown, and gloss events opened from a clip.
    static let clip = "clip"
}

/// One clip on screen. `seconds` is time the visit was actually on screen (a pushed
/// breakdown or another tab doesn't count). `watched` matches `ClipSeenStore`: one
/// uninterrupted stretch of `watchedAfter`, not a sum of shorter looks.
@MainActor
final class ClipVisitAnalytics {
    let clipID: String
    let source: String

    private let jlptLevel: Int?
    private let orientation: String?
    private let alreadySeen: Bool
    private var played = false
    private var didComplete = false
    private var didSwipe = false
    private var didShowHighlights = false
    private var didWatch = false
    private var accumulated: TimeInterval = 0
    private var windowStarted: Date?

    init(
        clipID: String,
        source: String,
        jlptLevel: Int?,
        orientation: String?,
        alreadySeen: Bool
    ) {
        self.clipID = clipID
        self.source = source
        self.jlptLevel = jlptLevel
        self.orientation = orientation
        self.alreadySeen = alreadySeen
    }

    /// Starts a fresh on-screen stretch. A stretch already running is left alone;
    /// callers close it first when the clock should restart (same as the seen timer).
    func openWatchWindow() {
        guard windowStarted == nil else { return }
        windowStarted = Date()
    }

    /// Ends the current stretch. A stretch of `ClipSeenStore.watchedAfter` latches `watched`.
    func closeWatchWindow() {
        guard let windowStarted else { return }
        let delta = Date().timeIntervalSince(windowStarted)
        accumulated += delta
        if delta >= Self.watchThreshold {
            didWatch = true
            // The feed's timer is cancelled by the same leave, so count it here too.
            // `markSeen` is a no-op once the timer has already recorded the clip.
            ClipSeenStore.markSeen(clipID)
        }
        self.windowStarted = nil
    }

    func notePlaying(jlptLevel: Int?, orientation: String?) {
        guard !played else { return }
        played = true
        var properties = base
        if let level = jlptLevel ?? self.jlptLevel { properties["jlpt_level"] = level }
        if let shape = orientation ?? self.orientation { properties["orientation"] = shape }
        properties["already_seen"] = alreadySeen
        Analytics.track(.clipPlayed, properties)
    }

    func noteCompleted(speed: Double) {
        guard !didComplete else { return }
        didComplete = true
        var properties = base
        properties["seconds"] = onScreenSeconds
        properties["speed"] = speed
        Analytics.track(.clipCompleted, properties)
    }

    /// The learner moved to another clip. Not used when leaving the feed.
    func swiped(direction: String) {
        guard !didSwipe else { return }
        didSwipe = true
        closeWatchWindow()
        var properties = base
        properties["direction"] = direction
        properties["seconds"] = onScreenSeconds
        properties["completed"] = didComplete
        properties["watched"] = watched
        Analytics.track(.clipSwiped, properties)
    }

    func noteHighlightsViewed() {
        guard !didShowHighlights else { return }
        didShowHighlights = true
        Analytics.track(.clipHighlightsViewed, base)
    }

    private var watched: Bool {
        if let windowStarted, Date().timeIntervalSince(windowStarted) >= Self.watchThreshold {
            return true
        }
        return didWatch
    }

    private var onScreenSeconds: Int {
        var total = accumulated
        if let windowStarted { total += Date().timeIntervalSince(windowStarted) }
        return Int(total.rounded())
    }

    private var base: [String: Any] {
        ["clip_id": clipID, "source": source]
    }

    /// Same duration `ClipSeenStore` waits before a clip counts as watched.
    private static var watchThreshold: TimeInterval {
        let parts = ClipSeenStore.watchedAfter.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
