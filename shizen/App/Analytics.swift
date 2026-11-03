//
//  Analytics.swift
//  Funnel analytics (onboarding → paywall → purchase) on PostHog. The only file that imports PostHog.
//
//  Key and host come from the Xcode scheme environment, then shizen/Secrets.plist (gitignored):
//  POSTHOG_API_KEY, POSTHOG_HOST. No key → every call no-ops.
//  DEBUG builds don't send unless the scheme sets POSTHOG_DEBUG_SEND=1; events are logged to the
//  console either way, and debug sends carry `is_debug = true` so they can be filtered out.
//  No IDFA, no ATT, no session replay, no screen autocapture. See docs/analytics-privacy.md.
//

import Foundation
import PostHog

enum Analytics {
    enum Event: String {
        // Onboarding
        case onboardingStepViewed = "onboarding_step_viewed"
        case onboardingCompleted = "onboarding_completed"

        // Lessons (dialogue, grammar, kana). `lesson_type` tells them apart.
        case lessonStarted = "lesson_started"
        case lessonCompleted = "lesson_completed"
        /// Ran out of lives (grammar, kana).
        case lessonFailed = "lesson_failed"
        /// Left before finishing; `furthest_stage` says how far they got.
        case lessonAbandoned = "lesson_abandoned"
        case dialogueListened = "dialogue_listened"
        case quizStarted = "quiz_started"
        case quizCompleted = "quiz_completed"
        case highlightsViewed = "highlights_viewed"

        // Interactions
        case sentenceBreakdownOpened = "sentence_breakdown_opened"
        /// One summary per breakdown visit, so scrubbing doesn't send an event per token.
        case sentenceBreakdownClosed = "sentence_breakdown_closed"
        /// Deliberate gloss requests: `kind` is multi_token or nuance.
        case glossViewed = "gloss_viewed"
        case wordDetailOpened = "word_detail_opened"
        case kanjiDetailOpened = "kanji_detail_opened"
        case dictionaryResultOpened = "dictionary_result_opened"
        case flashcardAdded = "flashcard_added"
        case audioReplayed = "audio_replayed"
        case playbackSpeedChanged = "playback_speed_changed"

        // Paywall & purchase
        case paywallViewed = "paywall_viewed"
        case paywallCarouselSwiped = "paywall_carousel_swiped"
        case paywallPlanSelected = "paywall_plan_selected"
        case paywallCTATapped = "paywall_cta_tapped"
        case paywallDismissed = "paywall_dismissed"
        case purchaseCancelled = "purchase_cancelled"
        case purchaseFailed = "purchase_failed"
        case restoreCompleted = "restore_completed"
        case proGateHit = "pro_gate_hit"
        case trialStarted = "trial_started"
        case purchased = "purchased"

        // Quality
        case lessonIssueReported = "lesson_issue_reported"
        case lessonFeedbackRated = "lesson_feedback_rated"
        case llmFeedback = "llm_feedback"
        case gatewayRequestFailed = "gateway_request_failed"
        case lessonAudioFailed = "lesson_audio_failed"
    }

    /// What `trial_started` / `purchased` report. Built by `PurchaseAnalytics` from RevenueCat's customer info.
    struct Purchase {
        let productId: String
        let packageId: String?
        /// "weekly", "monthly", "annual".
        let period: String?
        let price: Decimal?
        let currency: String?
    }

    private static var isEnabled = false

    /// Call once at launch, before `AuthService.shared.start()` so a restored session is identified.
    static func configure() {
        let key = value(for: "POSTHOG_API_KEY")
        guard !key.isEmpty else { return }
        #if DEBUG
        guard ProcessInfo.processInfo.environment["POSTHOG_DEBUG_SEND"] == "1" else {
            print("[Analytics] DEBUG build: not sending (set POSTHOG_DEBUG_SEND=1 to send)")
            return
        }
        #endif
        let host = value(for: "POSTHOG_HOST")
        let config = PostHogConfig(apiKey: key, host: host.isEmpty ? PostHogConfig.defaultHost : host)
        config.captureScreenViews = false
        config.captureApplicationLifecycleEvents = true
        config.captureElementInteractions = false
        config.sessionReplay = false
        PostHogSDK.shared.setup(config)
        #if DEBUG
        PostHogSDK.shared.register(["is_debug": true])
        #endif
        isEnabled = true
        setPersonProperties(["is_pro": ProMembership.isPro])
    }

    // MARK: Identity

    /// Firebase uid only; no email or name.
    static func identify(userId: String) {
        log("identify \(userId)")
        guard isEnabled else { return }
        PostHogSDK.shared.identify(userId, userProperties: ["is_pro": ProMembership.isPro])
    }

    static func reset() {
        log("reset")
        guard isEnabled else { return }
        PostHogSDK.shared.reset()
    }

    /// Person-profile properties (onboarding answers, plan), so any chart can be split by them.
    /// Answers only; never free text, email, or name.
    static func setPersonProperties(_ properties: [String: Any]) {
        guard !properties.isEmpty else { return }
        log("set person \(properties)")
        guard isEnabled else { return }
        PostHogSDK.shared.setPersonProperties(userPropertiesToSet: properties)
    }

    // MARK: Events

    /// Sends a typed event. Property keys are snake_case; values are counts, ids, and enums,
    /// never user-typed text.
    static func track(_ event: Event, _ properties: [String: Any] = [:]) {
        capture(event, properties)
    }

    // MARK: Onboarding

    static func onboardingStepViewed(index: Int, name: String, flow: String) {
        capture(.onboardingStepViewed, ["step_index": index, "step_name": name, "flow": flow])
    }

    static func onboardingCompleted(flow: String) {
        capture(.onboardingCompleted, ["flow": flow])
    }

    // MARK: Paywall & purchase

    static func paywallViewed(variant: String, offeringId: String, source: String) {
        capture(.paywallViewed, ["variant": variant, "offering_id": offeringId, "source": source])
    }

    /// Call where a Pro-only feature blocks a free user. Nothing is gated yet (`ProMembership`).
    static func proGateHit(feature: String) {
        capture(.proGateHit, ["feature": feature])
    }

    /// Only `PurchaseAnalytics` calls these, so RevenueCat stays the source of truth.
    static func trialStarted(_ purchase: Purchase) {
        capture(.trialStarted, properties(of: purchase))
    }

    static func purchased(_ purchase: Purchase) {
        capture(.purchased, properties(of: purchase))
    }

    // MARK: Private

    private static func capture(_ event: Event, _ properties: [String: Any]) {
        log("\(event.rawValue) \(properties)")
        guard isEnabled else { return }
        PostHogSDK.shared.capture(event.rawValue, properties: properties)
    }

    private static func properties(of purchase: Purchase) -> [String: Any] {
        var properties: [String: Any] = ["product_id": purchase.productId]
        properties["package_id"] = purchase.packageId
        properties["period"] = purchase.period
        properties["price"] = purchase.price.map { NSDecimalNumber(decimal: $0).doubleValue }
        properties["currency"] = purchase.currency
        return properties
    }

    private static func value(for key: String) -> String {
        if let env = ProcessInfo.processInfo.environment[key], !env.isEmpty {
            return env
        }
        return SecretsPlist.value(for: key) ?? ""
    }

    private static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[Analytics] \(message())")
        #endif
    }
}
