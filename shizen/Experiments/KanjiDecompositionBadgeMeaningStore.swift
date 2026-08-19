//
//  KanjiDecompositionBadgeMeaningStore.swift
//  shizen
//
//  Per-kanji selection of which Kanjidic meanings appear on decomposition
//  meaning badges. Persisted so picks survive across sessions and exports.
//

import Foundation

final class KanjiDecompositionBadgeMeaningStore {
    static let shared = KanjiDecompositionBadgeMeaningStore()

    /// Badge layout fits at most two glosses.
    static let maxSelections = 2

    private let defaultsKey = "KanjiDecompositionBadgeMeanings"
    private var selections: [String: [String]] = [:]

    private init() {
        load()
    }

    /// Explicit user selection for `kanji`, or `nil` when using defaults.
    func selectedMeanings(for kanji: String) -> [String]? {
        selections[kanji]
    }

    /// Saves an ordered selection (capped at `maxSelections`). Pass `nil` or empty to restore defaults.
    func setSelectedMeanings(_ meanings: [String]?, for kanji: String) {
        if let meanings, !meanings.isEmpty {
            selections[kanji] = Array(meanings.prefix(Self.maxSelections))
        } else {
            selections.removeValue(forKey: kanji)
        }
        save()
    }

    /// Text shown on the badge: selected meanings when set, otherwise the first two from Kanjidic.
    func displayMeaning(for kanji: String, from meaningList: [String]) -> String {
        let parts = resolvedMeanings(for: kanji, from: meaningList)
        return parts.joined(separator: ", ")
    }

    func resolvedMeanings(for kanji: String, from meaningList: [String]) -> [String] {
        if let selected = selections[kanji], !selected.isEmpty {
            let stillValid = selected.filter { meaningList.contains($0) }
            if !stillValid.isEmpty {
                return Array(stillValid.prefix(Self.maxSelections))
            }
        }
        return Array(meaningList.prefix(Self.maxSelections))
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return }
        selections = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(selections) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
