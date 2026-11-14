//
//  ProMembership.swift
//  shizen
//

import Foundation

/// Single hook for Pro entitlement. Local state per uid until a RevenueCat check replaces it.
enum ProMembership {
    enum State: String {
        case none
        case trial
        case paid
        /// Tells a lapsed trial or subscription from never-subscribed. Nothing sets it yet.
        case expired
    }

    private static let statesKey = "proMembershipStates"

    static var state: State {
        guard let uid = AuthService.shared.userId, let raw = storedStates[uid] else { return State.none }
        return State(rawValue: raw) ?? State.none
    }

    static var hasAccess: Bool {
        #if DEBUG
        // TEMP: skips the access gate in debug builds. Remove to test the gate.
        return true
        #else
        return state == .trial || state == .paid
        #endif
    }

    static var isPro: Bool { hasAccess }

    /// A purchase or restore that found access: trial when the package has one, otherwise paid.
    static func recordAccess(for package: PaywallPackage?) {
        guard let uid = AuthService.shared.userId else { return }
        var states = storedStates
        states[uid] = (package?.hasTrial == true ? State.trial : State.paid).rawValue
        UserDefaults.standard.set(states, forKey: statesKey)
        Analytics.setPersonProperties(["is_pro": isPro])
    }

    private static var storedStates: [String: String] {
        UserDefaults.standard.dictionary(forKey: statesKey) as? [String: String] ?? [:]
    }
}
