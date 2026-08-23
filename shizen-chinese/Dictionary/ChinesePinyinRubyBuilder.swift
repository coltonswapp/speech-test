//
//  ChinesePinyinRubyBuilder.swift
//  shizen-chinese
//
//  Stacks marked pinyin above each hanzi via Core Text ruby, matching Japanese furigana.
//

import CoreText
import UIKit

/// Insets the drawing rect so ruby on the first line is not clipped at the label's top edge.
final class PinyinRubyLabel: UILabel {
    var textInsets = UIEdgeInsets.zero {
        didSet {
            guard textInsets != oldValue else { return }
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    override var alignmentRectInsets: UIEdgeInsets {
        UIEdgeInsets(
            top: textInsets.top,
            left: textInsets.left,
            bottom: textInsets.bottom,
            right: textInsets.right
        )
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }

    override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let insetBounds = bounds.inset(by: textInsets)
        var rect = super.textRect(forBounds: insetBounds, limitedToNumberOfLines: numberOfLines)
        rect.origin.x -= textInsets.left
        rect.origin.y -= textInsets.top
        rect.size.width += textInsets.left + textInsets.right
        rect.size.height += textInsets.top + textInsets.bottom
        return rect
    }
}

enum ChinesePinyinRubyBuilder {
    private static let rubySizeFactor: CGFloat = 0.45
    private static let rubyTextColor = UIColor.secondaryLabel

    static func wordDetailRubyTopInset(for font: UIFont) -> CGFloat {
        let rubyReserve = font.pointSize * rubySizeFactor
        return ceil(rubyReserve + 4)
    }

    static func applyDisplay(
        to label: PinyinRubyLabel,
        hanzi: String,
        pinyinMarked: String,
        font: UIFont,
        textColor: UIColor
    ) -> Bool {
        let result = attributedString(hanzi: hanzi, pinyinMarked: pinyinMarked, font: font, textColor: textColor)
        let insets = result.appliedRuby
            ? UIEdgeInsets(top: wordDetailRubyTopInset(for: font), left: 0, bottom: 2, right: 0)
            : .zero
        label.textInsets = insets
        label.attributedText = result.attributed
        return result.appliedRuby
    }

    static func attributedString(
        hanzi: String,
        pinyinMarked: String,
        font: UIFont,
        textColor: UIColor
    ) -> (attributed: NSAttributedString, appliedRuby: Bool) {
        let trimmedHanzi = hanzi.trimmingCharacters(in: .whitespacesAndNewlines)
        let syllables = pinyinMarked
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }

        let base = NSMutableAttributedString(
            string: trimmedHanzi,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
            ]
        )

        guard !trimmedHanzi.isEmpty, !syllables.isEmpty else {
            return (base, false)
        }

        let paragraphStyle = NSMutableParagraphStyle()
        let rubyReserve = font.pointSize * rubySizeFactor
        paragraphStyle.minimumLineHeight = font.lineHeight + rubyReserve * 0.35
        paragraphStyle.lineSpacing = 0
        base.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: base.length))

        let pairs: [(NSRange, String)]
        if syllables.count == trimmedHanzi.count {
            var built: [(NSRange, String)] = []
            built.reserveCapacity(syllables.count)
            var index = trimmedHanzi.startIndex
            for syllable in syllables {
                let next = trimmedHanzi.index(after: index)
                built.append((NSRange(index..<next, in: trimmedHanzi), syllable))
                index = next
            }
            pairs = built
        } else if trimmedHanzi.count == 1 {
            pairs = [(NSRange(location: 0, length: base.length), syllables.joined(separator: " "))]
        } else {
            return (base, false)
        }

        for (range, syllable) in pairs {
            guard range.location != NSNotFound, NSMaxRange(range) <= base.length else { continue }
            let attrs: [CFString: Any] = [
                kCTRubyAnnotationSizeFactorAttributeName: rubySizeFactor,
                kCTForegroundColorAttributeName: rubyTextColor.cgColor,
            ]
            let annotation = CTRubyAnnotationCreateWithAttributes(
                .center,
                .auto,
                .before,
                syllable as CFString,
                attrs as CFDictionary
            )
            base.addAttribute(
                NSAttributedString.Key(kCTRubyAnnotationAttributeName as String),
                value: annotation,
                range: range
            )
        }
        return (base, true)
    }
}
