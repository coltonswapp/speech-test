//
//  SlideJapaneseText.swift
//  shizen
//
//  Centered Japanese (with furigana over kanji) for slideshow hero cards.
//  Used by the Verb combo and word slideshow cards.
//

import UIKit

enum SlideJapaneseText {
    static func hasKanji(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    static func centeredAttributed(_ text: String, font: UIFont) -> NSAttributedString {
        let base = JapaneseFuriganaBuilder.attributedString(for: text, font: font, textColor: .label)
        let centered = NSMutableAttributedString(attributedString: base)
        guard centered.length > 0 else { return centered }
        let range = NSRange(location: 0, length: centered.length)
        let existing = (centered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            ?? NSParagraphStyle.default
        let paragraph = (existing.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        paragraph.alignment = .center
        centered.addAttribute(.paragraphStyle, value: paragraph, range: range)
        return centered
    }

    /// Furigana when the text has kanji, plain centered text otherwise.
    static func apply(_ text: String, to label: FuriganaTranscriptLabel, font: UIFont) {
        label.numberOfLines = 0
        label.textAlignment = .center
        label.lineBreakMode = .byWordWrapping
        // Ruby height stays inside the label. Leaving this on reports the ruby
        // inset twice, so Auto Layout centers the glyphs below the card.
        label.verticalTextInsetsAffectAlignmentRect = false
        if hasKanji(text) {
            JapaneseFuriganaBuilder.applyScrubDisplay(
                to: label,
                attributed: centeredAttributed(text, font: font),
                contentInsets: UIEdgeInsets(
                    top: JapaneseFuriganaBuilder.wordDetailRubyTopInset(for: font),
                    left: 0,
                    bottom: 2,
                    right: 0
                )
            )
        } else {
            label.textInsets = .zero
            label.attributedText = nil
            label.font = font
            label.text = text
            label.textColor = .label
        }
        label.textAlignment = .center
    }
}
