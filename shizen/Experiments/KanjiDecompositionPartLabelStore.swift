//
//  KanjiDecompositionPartLabelStore.swift
//  shizen
//
//  Persists the last exported intro "part N" label so the next decomposition
//  session starts at part N + 1.
//

import Foundation

enum KanjiDecompositionPartLabelStore {
    private static let lastExportedPartKey = "KanjiDecompositionLastExportedPart"
    static let defaultPrefix = "Kanji is literal, part "

    /// Last part number written to an exported slide, or 0 when none saved yet.
    static var lastExportedPart: Int {
        get { max(0, UserDefaults.standard.integer(forKey: lastExportedPartKey)) }
        set { UserDefaults.standard.set(max(0, newValue), forKey: lastExportedPartKey) }
    }

    /// Intro eyebrow for a new decomposition session.
    static func nextPartLabel() -> String {
        defaultPrefix + "\(lastExportedPart + 1)"
    }

    /// Call after a successful photo export; parses `part N` from the live label.
    static func recordExport(from partLabel: String) {
        guard let part = parsePartNumber(from: partLabel) else { return }
        lastExportedPart = part
    }

    static func parsePartNumber(from label: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)part\s*(\d+)"#) else { return nil }
        let range = NSRange(label.startIndex..., in: label)
        guard
            let match = regex.firstMatch(in: label, range: range),
            match.numberOfRanges > 1,
            let partRange = Range(match.range(at: 1), in: label)
        else { return nil }
        return Int(label[partRange])
    }
}
