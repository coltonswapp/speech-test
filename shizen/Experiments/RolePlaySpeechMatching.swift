//
//  RolePlaySpeechMatching.swift
//  shizen
//
//  Soft Japanese line matching for Role Play ASR partials.
//  Paint is generous (particles/mora drops, phonetic fold). Completion is
//  strict so a mid-line pause or a padded ASR final cannot skip the rest.
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

        let strictSurface = strictOrderedMatch(target: tChars, heard: hChars)
        var strictResume = clampedAlready
        if clampedAlready < tChars.count {
            let rest = Array(tChars.dropFirst(clampedAlready))
            strictResume = clampedAlready + strictOrderedMatch(target: rest, heard: hChars)
        }
        let strictMatched = min(tChars.count, max(strictSurface, strictResume, clampedAlready))
        let remaining = tChars.count - strictMatched
        let ratio = Double(strictMatched) / Double(tChars.count)

        let phoneticT = phoneticHiragana(target)
        let phoneticH = phoneticHiragana(heard)
        let phoneticRatio: Double
        let phoneticRemaining: Int
        if phoneticT.isEmpty {
            phoneticRatio = 1
            phoneticRemaining = 0
        } else if phoneticH.isEmpty {
            phoneticRatio = 0
            phoneticRemaining = phoneticT.count
        } else {
            let pChars = Array(phoneticT)
            let phoneticMatched = strictOrderedMatch(target: pChars, heard: Array(phoneticH))
            phoneticRatio = Double(phoneticMatched) / Double(pChars.count)
            phoneticRemaining = pChars.count - phoneticMatched
        }

        let remainingLimit = tChars.count <= 8 ? 1 : 2
        let leftoverIsPunctuationOnly = leftoverIsOnlyPunctuation(
            in: target,
            matchedNormalizedCount: matched
        )
        let isSoftComplete: Bool
        if leftoverIsPunctuationOnly {
            isSoftComplete = true
        } else if tChars.count <= 2 {
            isSoftComplete = remaining == 0
        } else {
            isSoftComplete =
                ratio >= 0.80
                || phoneticRatio >= 0.80
                || remaining <= remainingLimit
                || phoneticRemaining <= remainingLimit
        }
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

    private static func leftoverIsOnlyPunctuation(in original: String, matchedNormalizedCount: Int) -> Bool {
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        var remaining = matchedNormalizedCount
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let next = trimmed.index(after: index)
            let piece = normalizeForMatch(String(trimmed[index]))
            if !piece.isEmpty {
                if remaining <= 0 { break }
                remaining -= piece.count
            }
            index = next
        }
        return trimmed[index...].allSatisfy { isIgnorablePunctuation($0) }
    }

    static func normalizeForMatch(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let scalars = trimmed.unicodeScalars.filter { scalar in
            !ignorablePunctuation.contains(scalar)
                && scalar != "\u{3000}"
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Fold katakana to hiragana and kanji to a hiragana reading so ASR kana can
    /// match written kanji.
    static func phoneticHiragana(_ text: String) -> String {
        var s = normalizeForMatch(text)
        if let folded = s.applyingTransform(.fullwidthToHalfwidth, reverse: false) {
            s = folded
        }
        if let hira = s.applyingTransform(.hiraganaToKatakana, reverse: true) {
            s = hira
        }
        if let latin = s.applyingTransform(.toLatin, reverse: false) {
            let foldedLatin = latin
                .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .replacingOccurrences(of: " ", with: "")
            if let hira = foldedLatin.applyingTransform(.latinToHiragana, reverse: false) {
                s = hira
            }
        }
        return normalizeForMatch(s)
    }

    private static func bestOrderedMatch(target: [Character], heard: [Character]) -> Int {
        max(
            longestContainedPrefixLength(target: target, heard: heard),
            greedySequentialMatch(target: target, heard: heard),
            lenientSequentialMatch(target: target, heard: heard)
        )
    }

    /// Prefix / in-order coverage only — used to decide the line is done.
    private static func strictOrderedMatch(target: [Character], heard: [Character]) -> Int {
        max(
            longestContainedPrefixLength(target: target, heard: heard),
            greedySequentialMatch(target: target, heard: heard)
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
