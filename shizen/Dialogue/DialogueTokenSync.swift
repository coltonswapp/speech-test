//
//  DialogueTokenSync.swift
//  shizen
//
//  Optional authored token timing: learner tokens + start times, shipped in
//  scenario JSON. Invalid or mismatched payloads are dropped so playback
//  falls back to line-level emphasis.
//

import Foundation

struct DialogueTokenSync: Hashable {
    let version: Int
    let variantId: String
    let contentHash: String
    let lines: [Line]

    struct Line: Hashable {
        let text: String
        let tokens: [Token]
    }

    struct Token: Hashable {
        let text: String
        let startSeconds: TimeInterval
    }

    static let formatVersion = 1

    static func validated(
        _ sync: DialogueTokenSync?,
        spokenTexts: [String],
        publishedContentHash: String?
    ) -> DialogueTokenSync? {
        guard let sync, sync.version == formatVersion else { return nil }
        if let publishedContentHash, sync.contentHash != publishedContentHash {
            return nil
        }
        let trimmedSpoken = spokenTexts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard sync.lines.count == trimmedSpoken.count, !sync.lines.isEmpty else { return nil }

        var previous: TimeInterval = -.infinity
        var lines: [Line] = []
        for (index, line) in sync.lines.enumerated() {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text == trimmedSpoken[index], !line.tokens.isEmpty else { return nil }
            var searchStart = text.startIndex
            var tokens: [Token] = []
            for token in line.tokens {
                let surface = token.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !surface.isEmpty, token.startSeconds.isFinite, token.startSeconds >= 0 else {
                    return nil
                }
                guard token.startSeconds > previous else { return nil }
                guard let range = text.range(of: surface, range: searchStart..<text.endIndex) else {
                    return nil
                }
                previous = token.startSeconds
                searchStart = range.upperBound
                tokens.append(Token(text: surface, startSeconds: token.startSeconds))
            }
            lines.append(Line(text: text, tokens: tokens))
        }
        return DialogueTokenSync(
            version: sync.version,
            variantId: sync.variantId,
            contentHash: sync.contentHash,
            lines: lines
        )
    }

    /// Current token for playback. Before the first stamp, returns `0` so the
    /// focused line can highlight immediately instead of waiting on the first
    /// word onset.
    func tokenIndex(lineIndex: Int, at time: TimeInterval) -> Int? {
        guard lines.indices.contains(lineIndex) else { return nil }
        let tokens = lines[lineIndex].tokens
        guard !tokens.isEmpty else { return nil }
        var active = 0
        for (index, token) in tokens.enumerated() where time >= token.startSeconds {
            active = index
        }
        return active
    }

    func utf16Range(lineIndex: Int, tokenIndex: Int) -> NSRange? {
        guard lines.indices.contains(lineIndex) else { return nil }
        let line = lines[lineIndex]
        guard line.tokens.indices.contains(tokenIndex) else { return nil }
        var searchStart = line.text.startIndex
        for (index, token) in line.tokens.enumerated() {
            guard let range = line.text.range(of: token.text, range: searchStart..<line.text.endIndex) else {
                return nil
            }
            if index == tokenIndex {
                return NSRange(range, in: line.text)
            }
            searchStart = range.upperBound
        }
        return nil
    }

    /// Learner-token surfaces mapped onto `sentence` for sentence scrub.
    /// Returns `nil` when the line is missing or a surface no longer appears in order.
    func japaneseTokens(lineIndex: Int, in sentence: String) -> [JapaneseToken]? {
        guard lines.indices.contains(lineIndex) else { return nil }
        var searchStart = sentence.startIndex
        var result: [JapaneseToken] = []
        for token in lines[lineIndex].tokens {
            let surface = token.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !surface.isEmpty,
                  let range = sentence.range(of: surface, range: searchStart..<sentence.endIndex) else {
                return nil
            }
            result.append(JapaneseToken(text: surface, range: range))
            searchStart = range.upperBound
        }
        return result.isEmpty ? nil : result
    }

    /// Maps a token range onto the bubble string, which may contain word-joiners
    /// inserted to keep hanging punctuation from wrapping alone.
    func utf16Range(lineIndex: Int, tokenIndex: Int, inDisplay display: String) -> NSRange? {
        guard let original = utf16Range(lineIndex: lineIndex, tokenIndex: tokenIndex) else { return nil }
        return Self.mapOriginalUTF16Range(original, onto: display)
    }

    private static let wordJoiner: unichar = 0x2060

    private static func mapOriginalUTF16Range(_ range: NSRange, onto display: String) -> NSRange? {
        guard range.location >= 0, range.length > 0 else { return nil }
        let ns = display as NSString
        var originalUTF16 = 0
        var displayUTF16 = 0
        var mappedLocation: Int?
        let targetEnd = range.location + range.length
        while displayUTF16 < ns.length {
            let unit = ns.character(at: displayUTF16)
            if unit == wordJoiner {
                displayUTF16 += 1
                continue
            }
            let unitLength = (unit >= 0xD800 && unit <= 0xDBFF && displayUTF16 + 1 < ns.length) ? 2 : 1
            if mappedLocation == nil, originalUTF16 == range.location {
                mappedLocation = displayUTF16
            }
            originalUTF16 += unitLength
            displayUTF16 += unitLength
            if let mappedLocation, originalUTF16 >= targetEnd {
                return NSRange(location: mappedLocation, length: displayUTF16 - mappedLocation)
            }
        }
        return nil
    }
}
