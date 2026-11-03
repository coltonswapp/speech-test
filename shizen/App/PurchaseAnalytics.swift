//
//  PurchaseAnalytics.swift
//  The one place `trial_started` and `purchased` fire from. RevenueCat (SHZ-8) is the source of
//  truth: call `customerInfoDidUpdate` from its customer-info updates (`PurchasesDelegate`
//  `purchases(_:receivedUpdated:)` or `Purchases.shared.customerInfoStream`), never from paywall taps.
//
//  If RevenueCat's native PostHog integration is ever turned on, it sends its own purchase events:
//  disable this hook then (set `isEnabled` to false), or every trial and purchase is counted twice.
//

import Foundation

enum PurchaseAnalytics {
    static let isEnabled = true

    /// RevenueCat `PeriodType`, mapped by the caller.
    enum PeriodType: String {
        case trial, intro, normal
    }

    private static let lastStateKey = "analytics.purchase.lastEntitlementState"

    /// Reports an entitlement turning active: `trial_started` for a trial period, `purchased` otherwise.
    /// A trial that converts to paid (trial → normal) also reports `purchased`. Repeat updates with the
    /// same state report nothing. State is on-device, so a reinstall + restore can report once more.
    ///
    /// - Parameters:
    ///   - isActive: `customerInfo.entitlements[id]?.isActive`.
    ///   - periodType: that entitlement's `periodType`.
    ///   - purchase: product/package/price details for the entitlement's product.
    static func customerInfoDidUpdate(isActive: Bool, periodType: PeriodType, purchase: Analytics.Purchase) {
        guard isEnabled else { return }
        let state = isActive ? periodType.rawValue : "inactive"
        let previous = UserDefaults.standard.string(forKey: lastStateKey) ?? "inactive"
        guard state != previous else { return }
        UserDefaults.standard.set(state, forKey: lastStateKey)
        guard isActive else { return }

        switch periodType {
        case .trial:
            if previous == "inactive" { Analytics.trialStarted(purchase) }
        case .intro, .normal:
            Analytics.purchased(purchase)
        }
    }
}
