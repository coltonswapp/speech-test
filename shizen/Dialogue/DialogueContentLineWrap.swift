//
//  DialogueContentLineWrap.swift
//  shizen
//
//  Keeps hanging Japanese/ASCII punctuation from wrapping onto its own line.
//

import CoreText
import UIKit

enum DialogueContentLineWrap {
    private static let wordJoiner = "\u{2060}"
    private static let wordJoinerCharacter: Character = "\u{2060}"
    private static let gluePrefixCount = 4
    /// Japanese and ASCII stops/commas, including fullwidth and halfwidth forms.
    private static let hangingPunctuation: Set<Unicode.Scalar> = [
        "\u{3002}", // ideographic full stop 。
        "\u{FF0E}", // fullwidth full stop ．
        "\u{002E}", // ascii full stop .
        "\u{FF61}", // halfwidth ideographic full stop ｡
        "\u{3001}", // ideographic comma 、
        "\u{FF0C}", // fullwidth comma ，
        "\u{002C}", // ascii comma ,
        "\u{FF64}", // halfwidth ideographic comma ､
        "\u{FF1F}", // fullwidth question ？
        "\u{003F}", // ascii question ?
        "\u{FF01}", // fullwidth bang ！
        "\u{0021}", // ascii bang !
        "\u{2026}", // ellipsis …
        "\u{22EF}", // midline ellipsis ⋯
        "\u{2025}", // two-dot leader ‥
    ]

    static func applyOrphanGlue(to label: FuriganaTranscriptLabel) {
        guard let attributed = label.attributedText, attributed.length > 0 else { return }
        label.attributedText = preparingForLayout(attributed)
        label.lineBreakMode = .byWordWrapping
        if #available(iOS 14.0, *) {
            label.lineBreakStrategy = .pushOut
        }
    }

    /// Word-joiners plus word-wrapping, matching what the label draws.
    static func preparingForLayout(_ attributed: NSAttributedString) -> NSAttributedString {
        let glued = gluingOrphanPunctuation(in: attributed)
        let mutable = NSMutableAttributedString(attributedString: glued)
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttribute(.paragraphStyle, in: fullRange, options: []) { value, range, _ in
            let style = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle)
                ?? NSMutableParagraphStyle()
            // Char-wrapping ignores Unicode close-punctuation rules and will
            // park `。` / `、` / `.` on their own line. Word-wrapping plus
            // joiners keeps the last few characters with the mark.
            style.lineBreakMode = .byWordWrapping
            style.hyphenationFactor = 0
            mutable.addAttribute(.paragraphStyle, value: style, range: range)
        }
        return mutable
    }

    /// Inserts word joiners so the last few characters plus a hanging mark stay on one line.
    static func gluingOrphanPunctuation(in attributed: NSAttributedString) -> NSAttributedString {
        let chars = Array(attributed.string)
        guard chars.count > 1 else { return attributed }

        var glueAfter = Set<Int>()
        var index = 0
        while index < chars.count {
            guard isHangingPunctuation(chars[index]) else {
                index += 1
                continue
            }
            var runEnd = index + 1
            while runEnd < chars.count, isHangingPunctuation(chars[runEnd]) {
                runEnd += 1
            }
            let start = max(0, index - gluePrefixCount)
            if start < runEnd {
                for glueIndex in start..<(runEnd - 1) {
                    // Already glued from a previous pass.
                    if chars[glueIndex] == wordJoinerCharacter { continue }
                    if chars[glueIndex + 1] == wordJoinerCharacter { continue }
                    glueAfter.insert(glueIndex)
                }
            }
            index = runEnd
        }
        guard !glueAfter.isEmpty else { return attributed }

        var utf16AfterChar: [Int] = Array(repeating: 0, count: chars.count)
        var utf16 = 0
        for (charIndex, char) in chars.enumerated() {
            utf16 += String(char).utf16.count
            utf16AfterChar[charIndex] = utf16
        }

        let rubyKey = NSAttributedString.Key(kCTRubyAnnotationAttributeName as String)
        let mutable = NSMutableAttributedString(attributedString: attributed)
        for location in glueAfter.map({ utf16AfterChar[$0] }).sorted(by: >) {
            guard location > 0, location <= mutable.length else { continue }
            let previousHasRuby =
                mutable.attribute(rubyKey, at: location - 1, effectiveRange: nil) != nil
            let nextHasRuby = location < mutable.length
                && mutable.attribute(rubyKey, at: location, effectiveRange: nil) != nil
            if previousHasRuby || nextHasRuby { continue }

            var attrs = mutable.attributes(at: location - 1, effectiveRange: nil)
            attrs.removeValue(forKey: rubyKey)
            mutable.insert(NSAttributedString(string: wordJoiner, attributes: attrs), at: location)
        }
        return mutable
    }

    private static func isHangingPunctuation(_ character: Character) -> Bool {
        character.unicodeScalars.contains(where: { hangingPunctuation.contains($0) })
    }
}
