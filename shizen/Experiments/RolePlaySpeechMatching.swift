//
//  RolePlaySpeechMatching.swift
//  shizen
//
//  Soft Japanese line matching for Role Play ASR partials.
//  Paint is generous (particles/mora drops). Completion is strict: one
//  hypothesis has to cover the whole line within a small kana error budget.
//

import Foundation

enum RolePlaySpeechMatching {
    struct Match {
        let matchedNormalizedCount: Int
        let isSoftComplete: Bool
    }

    static func evaluate(heard: String, target: String, alreadyMatched: Int = 0) -> Match {
        let t = normalizeForMatch(target)
        let h = normalizeForMatch(heard)
        guard !t.isEmpty else { return Match(matchedNormalizedCount: 0, isSoftComplete: true) }

        let clampedAlready = min(max(alreadyMatched, 0), t.count)
        guard !h.isEmpty else {
            return Match(matchedNormalizedCount: clampedAlready, isSoftComplete: false)
        }

        let tChars = Array(t)
        let hChars = Array(h)
        let fromSurface = bestOrderedMatch(target: tChars, heard: hChars)

        var fromResume = clampedAlready
        if clampedAlready < tChars.count {
            let rest = Array(tChars.dropFirst(clampedAlready))
            fromResume = clampedAlready + bestOrderedMatch(target: rest, heard: hChars)
        }

        let matched = min(tChars.count, max(fromSurface, fromResume, clampedAlready))
        let isSoftComplete = isLineSpoken(heard: heard, target: target)
        return Match(matchedNormalizedCount: matched, isSoftComplete: isSoftComplete)
    }

    /// Maps normalized match count back onto the trimmed display string as UTF-16 length.
    static func displayUTF16PrefixLength(in original: String, matchedNormalizedCount: Int) -> Int {
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard matchedNormalizedCount > 0, !trimmed.isEmpty else { return 0 }

        var remaining = matchedNormalizedCount
        var end = trimmed.startIndex
        for idx in trimmed.indices {
            end = trimmed.index(after: idx)
            let piece = normalizeForMatch(String(trimmed[idx]))
            if !piece.isEmpty {
                remaining -= piece.count
                if remaining <= 0 { break }
            }
        }
        while end < trimmed.endIndex, isIgnorablePunctuation(trimmed[end]) {
            end = trimmed.index(after: end)
        }
        return String(trimmed[..<end]).utf16.count
    }

    /// Ideographic stops are not reliably in `CharacterSet.punctuationCharacters`.
    private static let ignorablePunctuation = CharacterSet(charactersIn: "。．.｡､、，,！!？?…⋯‥〜~・･：:；;")
        .union(.punctuationCharacters)
        .union(.whitespacesAndNewlines)

    private static func isIgnorablePunctuation(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { ignorablePunctuation.contains($0) }
    }

    static func normalizeForMatch(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let scalars = trimmed.unicodeScalars.filter { scalar in
            !ignorablePunctuation.contains(scalar)
                && scalar != "\u{3000}"
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Kanji expanded to their MeCab/JMDict reading and katakana folded to
    /// hiragana, so ASR kana can match written kanji (学生 ↔ がくせい).
    static func phoneticHiragana(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let reading = JapaneseTokenizer.hiraganaReading(for: trimmed)
        let hiragana = reading.applyingTransform(.hiraganaToKatakana, reverse: true) ?? reading
        return normalizeForMatch(hiragana)
    }

    /// True when some stretch of `heard` reads as the whole target, as written
    /// or as kana. Filler before or after is free; dropped, swapped, or extra
    /// mora inside the line each cost one error.
    static func isLineSpoken(heard: String, target: String) -> Bool {
        let t = Array(normalizeForMatch(target))
        guard !t.isEmpty else { return true }
        let h = Array(normalizeForMatch(heard))
        guard !h.isEmpty else { return false }
        if bestSubstringEditDistance(target: t, heard: h) <= errorBudget(forLength: t.count) {
            return true
        }

        let pt = Array(phoneticHiragana(target))
        let ph = Array(phoneticHiragana(heard))
        guard !pt.isEmpty, !ph.isEmpty else { return false }
        return bestSubstringEditDistance(target: pt, heard: ph) <= errorBudget(forLength: pt.count)
    }

    /// Short lines must be exact; longer ones forgive roughly one slip per
    /// seven kana for ASR noise.
    static func errorBudget(forLength count: Int) -> Int {
        switch count {
        case ...3: return 0
        case ...8: return 1
        default: return Int(Double(count) * 0.15)
        }
    }

    /// Edit distance from `target` to its closest substring of `heard`
    /// (semi-global alignment: skipping heard text at either end is free).
    private static func bestSubstringEditDistance(target: [Character], heard: [Character]) -> Int {
        guard !target.isEmpty else { return 0 }
        guard !heard.isEmpty else { return target.count }
        var previous = [Int](repeating: 0, count: heard.count + 1)
        var current = previous
        for i in 1...target.count {
            current[0] = i
            for j in 1...heard.count {
                let substitution = previous[j - 1] + (target[i - 1] == heard[j - 1] ? 0 : 1)
                current[j] = min(substitution, previous[j] + 1, current[j - 1] + 1)
            }
            swap(&previous, &current)
        }
        return previous.min() ?? target.count
    }

    private static func bestOrderedMatch(target: [Character], heard: [Character]) -> Int {
        max(
            longestContainedPrefixLength(target: target, heard: heard),
            greedySequentialMatch(target: target, heard: heard),
            lenientSequentialMatch(target: target, heard: heard)
        )
    }

    /// Longest prefix of `target` that appears as a contiguous substring of `heard`.
    /// Covers “said it again from the start” inside a longer ASR hypothesis.
    private static func longestContainedPrefixLength(target: [Character], heard: [Character]) -> Int {
        guard !target.isEmpty, !heard.isEmpty else { return 0 }
        let heardString = String(heard)
        for len in stride(from: target.count, through: 1, by: -1) {
            if heardString.contains(String(target.prefix(len))) {
                return len
            }
        }
        return 0
    }

    /// Advances through `target` whenever the next character shows up in `heard`.
    /// Extra ASR filler is skipped; target characters are not.
    private static func greedySequentialMatch(target: [Character], heard: [Character]) -> Int {
        var index = 0
        for character in heard where index < target.count {
            if character == target[index] {
                index += 1
            }
        }
        return index
    }

    /// Like sequential match, but will skip 1–2 target characters when ASR drops
    /// a particle or mora so the rest of the line can still count.
    private static func lenientSequentialMatch(target: [Character], heard: [Character]) -> Int {
        var ti = 0
        var hi = 0
        while ti < target.count, hi < heard.count {
            if target[ti] == heard[hi] {
                ti += 1
                hi += 1
                continue
            }

            var skippedTarget = false
            for skip in 1...2 where ti + skip < target.count {
                if target[ti + skip] == heard[hi] {
                    ti += skip
                    skippedTarget = true
                    break
                }
            }
            if skippedTarget {
                continue
            }
            hi += 1
        }
        return ti
    }
}

/// Per-turn uploaded-audio cap and idle timeout for Role Play Whisper listening.
enum RolePlayWhisperListenBudget {
    static let idleTimeout: TimeInterval = 10
    static let minTurnSeconds: TimeInterval = 6
    static let maxTurnSeconds: TimeInterval = 25

    private static let ttsMultiplier = 3.5
    private static let moraMultiplier = 2.5
    private static let padSeconds: TimeInterval = 4
    private static let learnerMoraePerSecond = 4.0

    static func turnCapSeconds(ttsDuration: TimeInterval?, japanese: String) -> TimeInterval {
        var estimates: [TimeInterval] = []
        if let ttsDuration, ttsDuration > 0 {
            estimates.append(ttsDuration * ttsMultiplier + padSeconds)
        }
        let moraCount = RolePlaySpeechMatching.phoneticHiragana(japanese).count
        if moraCount > 0 {
            let expectedSpeak = Double(moraCount) / learnerMoraePerSecond
            estimates.append(expectedSpeak * moraMultiplier + padSeconds)
        }
        let raw = estimates.max() ?? minTurnSeconds
        return min(maxTurnSeconds, max(minTurnSeconds, raw))
    }
}
