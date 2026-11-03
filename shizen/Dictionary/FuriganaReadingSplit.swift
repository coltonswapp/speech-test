//
//  FuriganaReadingSplit.swift
//  shizen
//
//  Pure helpers for splitting a token reading across kanji with a strict
//  “joins back exactly” check. Used by JapaneseTokenizer furigana and unit tests.
//  Keep in sync with ../FuriganaTests/Sources/FuriganaReadingSplit/FuriganaReadingSplit.swift.
//

import Foundation

enum RubyReadingSplit {
    private static let ideographicSpace: Character = "\u{3000}"

    /// Splits on U+3000 only when every piece is non-empty and rejoins to the
    /// reading with spaces removed.
    static func ideographicSpaceParts(for reading: String) -> [String]? {
        guard reading.contains(ideographicSpace) else { return nil }
        let parts = reading
            .split(separator: ideographicSpace, omittingEmptySubsequences: true)
            .map(String.init)
        guard parts.count >= 2 else { return nil }
        let joined = parts.joined()
        let normalized = reading.replacingOccurrences(of: String(ideographicSpace), with: "")
        guard joined == normalized else { return nil }
        return parts
    }

    /// All ways to partition `reading` into `kanjiCount` non-empty strings (grapheme-wise).
    static func allExactPartitions(reading: String, kanjiCount: Int) -> [[String]] {
        guard kanjiCount >= 1, !reading.isEmpty else { return [] }
        if kanjiCount == 1 { return [[reading]] }
        let chars = Array(reading)
        guard chars.count >= kanjiCount else { return [] }
        var out: [[String]] = []
        func rec(_ start: Int, _ partsLeft: Int, _ acc: [String]) {
            if partsLeft == 1 {
                let tail = String(chars[start...])
                guard !tail.isEmpty else { return }
                out.append(acc + [tail])
                return
            }
            let maxEndExclusive = chars.count - (partsLeft - 1)
            guard start + 1 <= maxEndExclusive else { return }
            for end in (start + 1)...maxEndExclusive {
                let piece = String(chars[start..<end])
                rec(end, partsLeft - 1, acc + [piece])
            }
        }
        rec(0, kanjiCount, [])
        return out
    }

    /// Per-kanji readings only when there is exactly one exact partition.
    static func confidentKanjiReadingPieces(fullKanjiReading: String, kanjiCount: Int) -> [String]? {
        guard kanjiCount >= 2 else { return nil }
        let partitions = allExactPartitions(reading: fullKanjiReading, kanjiCount: kanjiCount)
        guard partitions.count == 1 else { return nil }
        return partitions[0]
    }

    // MARK: - Okurigana alignment (mirrors JapaneseTokenizer; covered by unit tests)

    enum SurfaceRun: Equatable {
        case kanji(Int)
        case kana(String)
    }

    /// Maps each single-kanji slot and kana tail to a reading piece (e.g. 感じ/かんじ → 感=かん).
    static func alignReadingToKanjiAndKana(
        runs: [SurfaceRun],
        reading: String
    ) -> [(reading: String, kanjiIndex: Int)]? {
        var remaining = Substring(reading)
        var pendingKanji: [Int] = []
        var result: [(reading: String, kanjiIndex: Int)] = []

        func flushPending(with piece: String) -> Bool {
            guard !piece.isEmpty, !pendingKanji.isEmpty else { return false }
            if pendingKanji.count == 1 {
                result.append((piece, pendingKanji[0]))
            } else if let parts = confidentKanjiReadingPieces(
                fullKanjiReading: piece,
                kanjiCount: pendingKanji.count
            ), parts.count == pendingKanji.count {
                for (part, idx) in zip(parts, pendingKanji) {
                    result.append((part, idx))
                }
            } else {
                return false
            }
            pendingKanji.removeAll()
            return true
        }

        for run in runs {
            switch run {
            case .kanji(let index):
                pendingKanji.append(index)
            case .kana(let kana):
                guard let match = remaining.range(of: kana) else { return nil }
                if !pendingKanji.isEmpty {
                    let piece = String(remaining[..<match.lowerBound])
                    guard flushPending(with: piece) else { return nil }
                } else if match.lowerBound != remaining.startIndex {
                    return nil
                }
                remaining = remaining[match.upperBound...]
            }
        }
        if !pendingKanji.isEmpty {
            let piece = String(remaining)
            guard flushPending(with: piece) else { return nil }
            remaining = Substring()
        }
        guard remaining.isEmpty, !result.isEmpty else { return nil }
        return result
    }
}
