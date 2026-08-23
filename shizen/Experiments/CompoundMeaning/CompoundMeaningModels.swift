//
//  CompoundMeaningModels.swift
//  shizen
//
//  Throwaway POC: hand-ranked compound-meaning guessing loop.
//  Config lives in CompoundMeaningPuzzles.json — no embeddings.
//

import Foundation
import UIKit

// MARK: - Config models

struct CompoundMeaningConfig: Codable {
    var knobs: CompoundMeaningKnobs
    var puzzles: [CompoundMeaningPuzzle]
}

struct CompoundMeaningKnobs: Codable, Equatable {
    var maxGuesses: Int
    var unlockComponentAAfterGuess: Int
    var unlockComponentBAfterGuess: Int
    var showCommitInterstitial: Bool
    var commitAfterGuess: Int
    var audioPayoff: Bool
    var colorBands: [CompoundMeaningColorBand]

    static let fallback = CompoundMeaningKnobs(
        maxGuesses: 6,
        unlockComponentAAfterGuess: 3,
        unlockComponentBAfterGuess: 4,
        showCommitInterstitial: true,
        commitAfterGuess: 5,
        audioPayoff: false,
        colorBands: [
            .init(maxRank: 1, name: "exact", hex: "#2EAD5B"),
            .init(maxRank: 5, name: "close", hex: "#C9A227"),
            .init(maxRank: 15, name: "related", hex: "#D97706"),
            .init(maxRank: 999, name: "far", hex: "#8E8E93"),
        ]
    )
}

struct CompoundMeaningColorBand: Codable, Equatable {
    var maxRank: Int
    var name: String
    var hex: String

    var color: UIColor {
        UIColor(compoundMeaningHex: hex) ?? .secondaryLabel
    }
}

struct CompoundMeaningPuzzle: Codable, Equatable {
    var id: String
    var kanji: String
    var reading: String
    var acceptedGlosses: [String]
    var components: [CompoundMeaningComponent]
    var literalBlurb: String
    var dialogueLine: String
    var nearMissGlosses: [CompoundMeaningRankedGloss]
    var rankHints: [CompoundMeaningRankedGloss]

    var componentA: CompoundMeaningComponent? { components.first }
    var componentB: CompoundMeaningComponent? { components.count > 1 ? components[1] : nil }

    var primaryGloss: String { acceptedGlosses.first ?? "" }
}

struct CompoundMeaningComponent: Codable, Equatable {
    var char: String
    var gloss: String
    var readings: [String]
}

struct CompoundMeaningRankedGloss: Codable, Equatable {
    var gloss: String
    var rank: Int
}

// MARK: - Runtime guess history

struct CompoundMeaningGuess: Equatable {
    let text: String
    let rank: Int
    let isExact: Bool
}

enum CompoundMeaningPhase: Equatable {
    case playing
    case commitInterstitial
    case revealed(won: Bool)
}

// MARK: - Ranking

enum CompoundMeaningRanker {
    /// Far-bucket default when a guess is not in any authored table.
    static let defaultFarRank = 50

    static func normalize(_ raw: String) -> String {
        var s = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        let punctuation = CharacterSet.punctuationCharacters.union(.symbols)
        s = s.components(separatedBy: punctuation).joined(separator: " ")
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        for article in ["a ", "an ", "the ", "to "] {
            if s.hasPrefix(article) {
                s = String(s.dropFirst(article.count))
            }
        }
        return s
    }

    static func rank(guess raw: String, in puzzle: CompoundMeaningPuzzle) -> CompoundMeaningGuess {
        let normalized = normalize(raw)
        guard !normalized.isEmpty else {
            return CompoundMeaningGuess(text: raw, rank: defaultFarRank, isExact: false)
        }

        let accepted = Set(puzzle.acceptedGlosses.map(normalize))
        if accepted.contains(normalized) {
            return CompoundMeaningGuess(text: raw, rank: 1, isExact: true)
        }

        var table: [String: Int] = [:]
        for item in puzzle.nearMissGlosses {
            let key = normalize(item.gloss)
            table[key] = min(table[key] ?? item.rank, item.rank)
        }
        for item in puzzle.rankHints {
            let key = normalize(item.gloss)
            table[key] = min(table[key] ?? item.rank, item.rank)
        }

        if let exactTable = table[normalized] {
            return CompoundMeaningGuess(text: raw, rank: max(2, exactTable), isExact: false)
        }

        // Soft containment: guess contains an accepted gloss or vice versa.
        for gloss in accepted {
            if !gloss.isEmpty, normalized.contains(gloss) || gloss.contains(normalized) {
                return CompoundMeaningGuess(text: raw, rank: 3, isExact: false)
            }
        }

        // Soft containment against near-misses (take best).
        var best: Int?
        for (key, value) in table {
            if normalized.contains(key) || key.contains(normalized) {
                let softened = min(defaultFarRank - 1, value + 3)
                best = min(best ?? softened, softened)
            }
        }
        if let best {
            return CompoundMeaningGuess(text: raw, rank: max(2, best), isExact: false)
        }

        return CompoundMeaningGuess(text: raw, rank: defaultFarRank, isExact: false)
    }

    static func band(for rank: Int, knobs: CompoundMeaningKnobs) -> CompoundMeaningColorBand {
        let sorted = knobs.colorBands.sorted { $0.maxRank < $1.maxRank }
        for band in sorted where rank <= band.maxRank {
            return band
        }
        return sorted.last ?? CompoundMeaningColorBand(maxRank: 999, name: "far", hex: "#8E8E93")
    }
}

// MARK: - Loader + knob overrides

enum CompoundMeaningCatalog {
    private static let knobsDefaultsKey = "CompoundMeaningKnobsOverride"

    static func load() -> CompoundMeaningConfig {
        var config = loadFromBundle() ?? CompoundMeaningConfig(knobs: .fallback, puzzles: [])
        if let override = loadKnobOverride() {
            config.knobs = override
        }
        return config
    }

    static func saveKnobs(_ knobs: CompoundMeaningKnobs) {
        guard let data = try? JSONEncoder().encode(knobs) else { return }
        UserDefaults.standard.set(data, forKey: knobsDefaultsKey)
    }

    static func resetKnobsToBundleDefaults() {
        UserDefaults.standard.removeObject(forKey: knobsDefaultsKey)
    }

    private static func loadKnobOverride() -> CompoundMeaningKnobs? {
        guard let data = UserDefaults.standard.data(forKey: knobsDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(CompoundMeaningKnobs.self, from: data)
    }

    private static func loadFromBundle() -> CompoundMeaningConfig? {
        let candidates = [
            Bundle.main.url(forResource: "CompoundMeaningPuzzles", withExtension: "json"),
            Bundle.main.url(
                forResource: "CompoundMeaningPuzzles",
                withExtension: "json",
                subdirectory: "Experiments/CompoundMeaning"
            ),
            Bundle.main.url(
                forResource: "CompoundMeaningPuzzles",
                withExtension: "json",
                subdirectory: "CompoundMeaning"
            ),
        ]
        guard let url = candidates.compactMap({ $0 }).first else {
            assertionFailure("CompoundMeaningPuzzles.json missing from bundle")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(CompoundMeaningConfig.self, from: data)
        } catch {
            assertionFailure("Failed to decode CompoundMeaningPuzzles.json: \(error)")
            return nil
        }
    }
}

// MARK: - Hex color helper

private extension UIColor {
    convenience init?(compoundMeaningHex hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = CGFloat((value & 0xFF0000) >> 16) / 255
        let g = CGFloat((value & 0x00FF00) >> 8) / 255
        let b = CGFloat(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
