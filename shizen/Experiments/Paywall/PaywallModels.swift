//
//  PaywallModels.swift
//  shizen
//
//  Offering / package shapes for the custom paywall experiments. They mirror
//  RevenueCat's `Offering` and `Package` so the variants can swap the mock
//  provider for a RevenueCat-backed one without touching their layout.
//

import Foundation

struct PaywallPackage: Equatable {
    enum Period: Equatable {
        case weekly, monthly, annual

        var title: String {
            switch self {
            case .weekly: return "Weekly"
            case .monthly: return "Monthly"
            case .annual: return "Yearly"
            }
        }

        var unit: String {
            switch self {
            case .weekly: return "week"
            case .monthly: return "month"
            case .annual: return "year"
            }
        }

        var shortUnit: String {
            switch self {
            case .weekly: return "wk"
            case .monthly: return "mo"
            case .annual: return "yr"
            }
        }

        var weeks: Decimal {
            switch self {
            case .weekly: return 1
            case .monthly: return Decimal(52) / Decimal(12)
            case .annual: return 52
            }
        }

        var months: Decimal {
            switch self {
            case .weekly: return Decimal(12) / Decimal(52)
            case .monthly: return 1
            case .annual: return 12
            }
        }
    }

    /// RevenueCat package identifier, e.g. `$rc_annual`.
    let identifier: String
    let productIdentifier: String
    let period: Period
    let price: Decimal
    let currencyCode: String
    /// Free-trial length when the user is eligible for the intro offer.
    let trialDays: Int?

    var hasTrial: Bool { trialDays != nil }
    var localizedPrice: String { PaywallPriceFormatter.string(price, currencyCode: currencyCode) }
    var pricePerWeek: String { PaywallPriceFormatter.string(price / period.weeks, currencyCode: currencyCode) }
    var pricePerMonth: String { PaywallPriceFormatter.string(price / period.months, currencyCode: currencyCode) }

    /// Whole-percent saving per week against `other`, or nil when there is none.
    func savingsPercent(comparedTo other: PaywallPackage) -> Int? {
        let mine = NSDecimalNumber(decimal: price / period.weeks).doubleValue
        let theirs = NSDecimalNumber(decimal: other.price / other.period.weeks).doubleValue
        guard theirs > 0, mine < theirs else { return nil }
        return Int(((1 - mine / theirs) * 100).rounded())
    }
}

struct PaywallOffering {
    let identifier: String
    let packages: [PaywallPackage]
    /// RevenueCat offering metadata, so an experiment can change copy without a release.
    let metadata: [String: String]

    var annual: PaywallPackage? { packages.first { $0.period == .annual } }
    var monthly: PaywallPackage? { packages.first { $0.period == .monthly } }
    var defaultPackage: PaywallPackage? { annual ?? packages.first }

    func string(_ key: String, default fallback: String) -> String {
        metadata[key] ?? fallback
    }
}

enum PaywallPriceFormatter {
    private static var cache: [String: NumberFormatter] = [:]

    static func string(_ value: Decimal, currencyCode: String) -> String {
        let formatter = cache[currencyCode] ?? {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = currencyCode
            cache[currencyCode] = formatter
            return formatter
        }()
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }
}

/// Everything a paywall needs from the purchases backend.
///
/// The RevenueCat implementation (iOS SDK 5.66.0+ so existing customers enroll
/// in experiments) maps to:
/// - `fetchOffering` → `Purchases.shared.offerings()`, using the placement
///   offering when one is configured, else `current` (the experiment variant).
/// - `trackImpression` → `trackCustomPaywallImpression`, called on every appearance.
/// - `purchase` / `restorePurchases` → `purchase(package:)` / `restorePurchases()`.
protocol PaywallProviding: AnyObject {
    func fetchOffering(placement: String?) async throws -> PaywallOffering
    func trackImpression(offering: PaywallOffering)
    func purchase(_ package: PaywallPackage) async throws -> Bool
    func restorePurchases() async throws -> Bool
}

final class MockPaywallProvider: PaywallProviding {
    enum Currency: String, CaseIterable {
        case usd = "USD"
        case jpy = "JPY"
    }

    var isTrialEligible = true
    var currency: Currency = .usd
    private(set) var impressionCount = 0

    func fetchOffering(placement: String?) async throws -> PaywallOffering {
        let (annual, monthly): (Decimal, Decimal) = switch currency {
        case .usd: (Decimal(string: "59.99")!, Decimal(string: "12.99")!)
        case .jpy: (8800, 1800)
        }
        return PaywallOffering(
            identifier: "mock_default",
            packages: [
                PaywallPackage(
                    identifier: "$rc_annual",
                    productIdentifier: "shizen_pro_annual",
                    period: .annual,
                    price: annual,
                    currencyCode: currency.rawValue,
                    trialDays: isTrialEligible ? 7 : nil
                ),
                PaywallPackage(
                    identifier: "$rc_monthly",
                    productIdentifier: "shizen_pro_monthly",
                    period: .monthly,
                    price: monthly,
                    currencyCode: currency.rawValue,
                    trialDays: nil
                ),
            ],
            metadata: [:]
        )
    }

    func trackImpression(offering: PaywallOffering) {
        impressionCount += 1
        print("[Paywall] impression #\(impressionCount) offering=\(offering.identifier)")
    }

    func purchase(_ package: PaywallPackage) async throws -> Bool {
        try await Task.sleep(for: .seconds(1))
        return true
    }

    func restorePurchases() async throws -> Bool {
        try await Task.sleep(for: .seconds(0.6))
        return false
    }
}
