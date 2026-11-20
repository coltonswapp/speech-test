//
//  ClipSeenStore.swift
//  shizen
//
//  Clips this device has watched, so the feed can put them last. Local only:
//  one learner's history on one device, no server.
//

import Foundation

@MainActor
enum ClipSeenStore {
    /// On screen this long (playing or paused) and it counts as watched; a
    /// swipe straight past doesn't.
    static let watchedAfter: Duration = .seconds(5)

    /// Oldest ids drop off past this. Well above the catalog, so nothing
    /// resurfaces early; low enough that UserDefaults stays small.
    private static let limit = 2000
    private static let key = "clips.seenIDs"

    /// Oldest first.
    private static var order: [String] = UserDefaults.standard.stringArray(forKey: key) ?? []
    private static var ids = Set(order)

    static func contains(_ clipID: String) -> Bool {
        ids.contains(clipID)
    }

    static func markSeen(_ clipID: String) {
        guard ids.insert(clipID).inserted else { return }
        order.append(clipID)
        if order.count > limit {
            let dropped = order.prefix(order.count - limit)
            ids.subtract(dropped)
            order.removeFirst(dropped.count)
        }
        UserDefaults.standard.set(order, forKey: key)
    }
}
