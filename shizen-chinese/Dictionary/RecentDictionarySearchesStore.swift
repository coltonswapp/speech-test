//
//  RecentDictionarySearchesStore.swift
//  shizen-chinese
//
//  Local history of dictionary search queries (UserDefaults).
//

import Foundation

enum RecentDictionarySearchesStore {
    private static let key = "com.Swappfunc.shizen-chinese.recent-dictionary-searches"
    private static let maxCount = 12

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func save(_ queries: [String]) {
        UserDefaults.standard.set(queries, forKey: key)
    }

    static func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var queries = load().filter { $0 != trimmed }
        queries.insert(trimmed, at: 0)
        if queries.count > maxCount {
            queries = Array(queries.prefix(maxCount))
        }
        save(queries)
    }

    static func remove(_ query: String) {
        save(load().filter { $0 != query })
    }
}
