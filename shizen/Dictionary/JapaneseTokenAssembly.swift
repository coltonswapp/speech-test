//
//  JapaneseTokenAssembly.swift
//  shizen
//
//  Splices pre-tokenized segments into one display string without re-running tokenization.
//

import Foundation

enum JapaneseTokenAssembly {

    /// Keeps tokens fully inside `bounds`; ranges are rebased to the clipped substring.
    static func clipTokens(
        _ tokens: [JapaneseToken],
        within bounds: Range<String.Index>,
        in text: String
    ) -> [JapaneseToken] {
        let substring = String(text[bounds])
        var result: [JapaneseToken] = []
        result.reserveCapacity(tokens.count)

        for token in tokens {
            guard token.range.lowerBound >= bounds.lowerBound,
                  token.range.upperBound <= bounds.upperBound else { continue }
            let lowerOffset = text.distance(from: bounds.lowerBound, to: token.range.lowerBound)
            let upperOffset = text.distance(from: bounds.lowerBound, to: token.range.upperBound)
            let start = substring.index(substring.startIndex, offsetBy: lowerOffset)
            let end = substring.index(substring.startIndex, offsetBy: upperOffset)
            result.append(JapaneseToken(text: token.text, range: start..<end))
        }
        return result
    }

    /// Maps segment-local token ranges into one assembled `display` string.
    static func assemble(
        display: String,
        parts: [(text: String, tokens: [JapaneseToken])]
    ) -> [JapaneseToken] {
        var result: [JapaneseToken] = []
        var cursor = display.startIndex

        for (partText, partTokens) in parts {
            let partStart = cursor
            guard let partEnd = display.index(cursor, offsetBy: partText.count, limitedBy: display.endIndex) else {
                break
            }
            cursor = partEnd

            for token in partTokens {
                let lower = display.index(
                    partStart,
                    offsetBy: partText.distance(from: partText.startIndex, to: token.range.lowerBound)
                )
                let upper = display.index(
                    partStart,
                    offsetBy: partText.distance(from: partText.startIndex, to: token.range.upperBound)
                )
                result.append(JapaneseToken(text: token.text, range: lower..<upper))
            }
        }
        return result
    }

    static func singleToken(text: String, at start: String.Index, in display: String) -> [JapaneseToken] {
        guard let end = display.index(start, offsetBy: text.count, limitedBy: display.endIndex) else {
            return []
        }
        return [JapaneseToken(text: text, range: start..<end)]
    }
}
