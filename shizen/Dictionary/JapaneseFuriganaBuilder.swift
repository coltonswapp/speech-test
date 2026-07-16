//
//  JapaneseFuriganaBuilder.swift
//  shizen
//

import CoreText
import StringTools
import UIKit

enum JapaneseFuriganaSettings {
    private static let tutorDefaultsKey = "JapaneseFuriganaShowInTutor"
    private static let flashcardsDefaultsKey = "JapaneseFuriganaShowOnFlashcards"

    /// Prototype default: furigana on in tutor transcripts.
    static var showInTutorTranscripts: Bool {
        get {
            if UserDefaults.standard.object(forKey: tutorDefaultsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: tutorDefaultsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: tutorDefaultsKey) }
    }

    /// Prototype default: furigana on flashcard keywords.
    static var showOnFlashcards: Bool {
        get {
            if UserDefaults.standard.object(forKey: flashcardsDefaultsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: flashcardsDefaultsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: flashcardsDefaultsKey) }
    }
}

/// Insets the text drawing rect so ruby on the first line is not clipped at the label's top edge.
final class FuriganaTranscriptLabel: UILabel {
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

enum JapaneseFuriganaBuilder {
    private static let cache = NSCache<NSString, NSAttributedString>()
    private static let rubySizeFactor: CGFloat = 0.45
    private static let rubyTextColor = UIColor.secondaryLabel

    /// Vertical gap between transcript lines in the same speaker turn.
    static let transcriptLineSpacing: CGFloat = 18

    /// Extra gap when the speaker changes (user ↔ assistant).
    static let transcriptSpeakerTurnSpacing: CGFloat = 24

    /// Internal top inset inside the label — ruby draws above the first line of glyphs.
    static func transcriptRubyTopInset(for font: UIFont) -> CGFloat {
        guard JapaneseFuriganaSettings.showInTutorTranscripts else { return 0 }
        return rubyTopInset(for: font)
    }

    /// Top inset for UITextView `textContainerInset` (sentence scrub, etc.).
    static func rubyTopInset(for font: UIFont) -> CGFloat {
        let rubyReserve = font.pointSize * rubySizeFactor
        return ceil(rubyReserve * 2.75 + 10)
    }

    private static func paragraphStyleForFurigana(font: UIFont) -> NSParagraphStyle {
        let rubyReserve = font.pointSize * rubySizeFactor
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = font.lineHeight + rubyReserve * 0.8
        paragraphStyle.lineSpacing = max(8, rubyReserve * 0.52)
        return paragraphStyle
    }

    private static func compactParagraphStyleForFurigana(font: UIFont) -> NSParagraphStyle {
        let rubyReserve = font.pointSize * rubySizeFactor
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = font.lineHeight + rubyReserve * 0.35
        paragraphStyle.lineSpacing = 0
        return paragraphStyle
    }

    private static func usageLadderParagraphStyleForFurigana(font: UIFont) -> NSParagraphStyle {
        let rubyReserve = font.pointSize * rubySizeFactor
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = font.lineHeight + rubyReserve * 0.55
        paragraphStyle.lineSpacing = 3
        paragraphStyle.lineBreakMode = .byWordWrapping
        return paragraphStyle
    }

    private static func dialogueBubbleParagraphStyleForFurigana(font: UIFont) -> NSParagraphStyle {
        let rubyReserve = font.pointSize * rubySizeFactor
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = font.lineHeight + rubyReserve * 0.58
        paragraphStyle.lineSpacing = 5
        paragraphStyle.lineBreakMode = .byWordWrapping
        return paragraphStyle
    }

    private static func dialogueScrollParagraphStyleForFurigana(font: UIFont) -> NSParagraphStyle {
        let rubyReserve = font.pointSize * rubySizeFactor
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = font.lineHeight + rubyReserve * 0.85
        paragraphStyle.lineSpacing = 6
        return paragraphStyle
    }

    static func applyFurigana(to attributed: NSMutableAttributedString, text: String, font: UIFont) {
        applyFurigana(to: attributed, text: text, font: font, paragraphStyle: paragraphStyleForFurigana(font: font))
    }

    private static func applyFurigana(
        to attributed: NSMutableAttributedString,
        text: String,
        font: UIFont,
        paragraphStyle: NSParagraphStyle
    ) {
        guard !text.isEmpty, attributed.length > 0 else { return }

        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

        let rubyFont = rubyFont(for: font)
        let rubyAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: rubyTextColor,
            .font: rubyFont,
        ]

        for furi in JapaneseTokenizer.furiganaAnnotations(for: text) {
            let range = NSRange(furi.range, in: text)
            guard range.location != NSNotFound, NSMaxRange(range) <= attributed.length else { continue }
            attributed.addAttribute(
                NSAttributedString.Key(kCTRubyAnnotationAttributeName as String),
                value: furi.rubyAnnotation(sizeFActor: rubySizeFactor, attributes: rubyAttributes),
                range: range
            )
        }
    }

    private static func rubyFont(for baseFont: UIFont) -> UIFont {
        UIFont.systemFont(ofSize: baseFont.pointSize * rubySizeFactor, weight: .regular)
    }

    static func makeTranscriptLabel(font: UIFont) -> FuriganaTranscriptLabel {
        let label = FuriganaTranscriptLabel()
        label.clipsToBounds = false
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.font = font
        return label
    }

    static func attributedString(for text: String, font: UIFont, textColor: UIColor) -> NSAttributedString {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: textColor])
        }

        let cacheKey =
            "\(trimmed)|\(font.fontName)|\(font.pointSize)|\(textColor.cgColor.hashValue)|\(transcriptRubyTopInset(for: font))|\(transcriptLineSpacing)|ruby-internal-inset-v3" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let base = NSMutableAttributedString(
            string: trimmed,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
            ]
        )
        applyFurigana(to: base, text: trimmed, font: font)

        let result = NSAttributedString(attributedString: base)
        cache.setObject(result, forKey: cacheKey)
        return result
    }

    static func usageLadderAttributedString(for text: String, font: UIFont, textColor: UIColor) -> NSAttributedString {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: textColor])
        }

        let cacheKey =
            "usage-ladder|\(trimmed)|\(font.fontName)|\(font.pointSize)|\(textColor.cgColor.hashValue)|v1" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let base = NSMutableAttributedString(
            string: trimmed,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
            ]
        )
        applyFurigana(
            to: base,
            text: trimmed,
            font: font,
            paragraphStyle: usageLadderParagraphStyleForFurigana(font: font)
        )

        let result = NSAttributedString(attributedString: base)
        cache.setObject(result, forKey: cacheKey)
        return result
    }

    static func dialogueScrollAttributedString(for text: String, font: UIFont, textColor: UIColor) -> NSAttributedString {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: textColor])
        }

        let cacheKey =
            "dialogue-scroll|\(trimmed)|\(font.fontName)|\(font.pointSize)|\(textColor.cgColor.hashValue)|v2" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let base = NSMutableAttributedString(
            string: trimmed,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
            ]
        )
        applyFurigana(
            to: base,
            text: trimmed,
            font: font,
            paragraphStyle: dialogueScrollParagraphStyleForFurigana(font: font)
        )

        let result = NSAttributedString(attributedString: base)
        cache.setObject(result, forKey: cacheKey)
        return result
    }

    static func dialogueBubbleAttributedString(for text: String, font: UIFont, textColor: UIColor) -> NSAttributedString {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: textColor])
        }

        let cacheKey =
            "dialogue-bubble|\(trimmed)|\(font.fontName)|\(font.pointSize)|\(textColor.cgColor.hashValue)|v3" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let base = NSMutableAttributedString(
            string: trimmed,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
            ]
        )
        applyFurigana(
            to: base,
            text: trimmed,
            font: font,
            paragraphStyle: dialogueBubbleParagraphStyleForFurigana(font: font)
        )

        let result = NSAttributedString(attributedString: base)
        cache.setObject(result, forKey: cacheKey)
        return result
    }

    static func scenarioAttributedString(for text: String, font: UIFont, textColor: UIColor) -> NSAttributedString {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: textColor])
        }

        let cacheKey =
            "scenario|\(trimmed)|\(font.fontName)|\(font.pointSize)|\(textColor.cgColor.hashValue)|compact-v1" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let base = NSMutableAttributedString(
            string: trimmed,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
            ]
        )
        applyFurigana(
            to: base,
            text: trimmed,
            font: font,
            paragraphStyle: compactParagraphStyleForFurigana(font: font)
        )

        let result = NSAttributedString(attributedString: base)
        cache.setObject(result, forKey: cacheKey)
        return result
    }

    static func apply(to label: UILabel, text: String, font: UIFont, textColor: UIColor) {
        let topInset = JapaneseFuriganaSettings.showInTutorTranscripts ? transcriptRubyTopInset(for: font) : 0
        if let furiganaLabel = label as? FuriganaTranscriptLabel {
            furiganaLabel.textInsets = UIEdgeInsets(top: topInset, left: 0, bottom: 4, right: 0)
        }

        if JapaneseFuriganaSettings.showInTutorTranscripts {
            label.attributedText = attributedString(for: text, font: font, textColor: textColor)
        } else {
            label.attributedText = nil
            label.font = font
            label.text = text
            label.textColor = textColor
        }
    }

    static func flashcardTextInsets(for font: UIFont, showFurigana: Bool) -> UIEdgeInsets {
        let topInset = showFurigana ? wordDetailRubyTopInset(for: font) : 0
        return UIEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)
    }

    static func applyFlashcardDisplay(to label: FuriganaTranscriptLabel, text: String, font: UIFont, textColor: UIColor) {
        label.textInsets = flashcardTextInsets(
            for: font,
            showFurigana: JapaneseFuriganaSettings.showOnFlashcards
        )
        applyFlashcardContent(
            to: label,
            text: text,
            font: font,
            textColor: textColor,
            showFurigana: JapaneseFuriganaSettings.showOnFlashcards
        )
    }

    static func applyFlashcardContent(
        to label: FuriganaTranscriptLabel,
        text: String,
        font: UIFont,
        textColor: UIColor,
        showFurigana: Bool
    ) {
        if showFurigana {
            label.attributedText = flashcardAttributedString(for: text, font: font, textColor: textColor)
        } else {
            label.attributedText = nil
            label.font = font
            label.text = text
            label.textColor = textColor
        }
    }

    private static func flashcardAttributedString(for text: String, font: UIFont, textColor: UIColor) -> NSAttributedString {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: textColor])
        }

        let cacheKey =
            "flashcard|\(trimmed)|\(font.fontName)|\(font.pointSize)|\(textColor.cgColor.hashValue)|v1" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let base = NSMutableAttributedString(
            string: trimmed,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
            ]
        )
        applyFurigana(to: base, text: trimmed, font: font)

        let result = NSAttributedString(attributedString: base)
        cache.setObject(result, forKey: cacheKey)
        return result
    }

    /// Top inset for the word-detail row: enough for ruby without the full transcript padding.
    static func wordDetailRubyTopInset(for font: UIFont) -> CGFloat {
        let rubyReserve = font.pointSize * rubySizeFactor
        return ceil(rubyReserve + 4)
    }

    /// Insets for speech-bubble dialogue lines (title-sized Japanese with ruby).
    static func dialogueBubbleDisplayInsets(for font: UIFont) -> UIEdgeInsets {
        let top = max(2, wordDetailRubyTopInset(for: font) - 2)
        return UIEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
    }

    /// Insets for compact furigana rows (example lists, scenario dialogue).
    static func compactDisplayInsets(for font: UIFont) -> UIEdgeInsets {
        let top = max(2, wordDetailRubyTopInset(for: font) - 6)
        return UIEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
    }

    private static let dialoguePillPlainVocabUpwardNudge: CGFloat = 7
    private static let dialoguePillPlainGrammarUpwardNudge: CGFloat = 8
    private static let dialoguePillGrammarBottomInset: CGFloat = 4

    /// Insets for dialogue learning pills — compact ruby room plus grammar bottom balance.
    static func dialoguePillDisplayInsets(
        for font: UIFont,
        text: String,
        style: DialogueGlassPillStyle
    ) -> UIEdgeInsets {
        if textHasFurigana(text) {
            var insets = compactDisplayInsets(for: font)
            insets.top = max(2, insets.top - 2)
            insets.bottom = 0
            return insets
        }
        if style == .grammar {
            return UIEdgeInsets(top: 0, left: 0, bottom: dialoguePillGrammarBottomInset, right: 0)
        }
        return .zero
    }

    /// Positions the label within the pill's fixed-height band.
    static func dialoguePillLabelBandTopOffset(
        for font: UIFont,
        text: String,
        style: DialogueGlassPillStyle
    ) -> CGFloat {
        let bandHeight = dialoguePillFixedBandHeight(for: font)
        if textHasFurigana(text) {
            return 2
        }

        let textInsets = dialoguePillDisplayInsets(for: font, text: text, style: style)
        let plainHeight = dialoguePillMeasuredLabelHeight(
            for: text,
            font: font,
            textInsets: textInsets
        )

        let centered = (bandHeight - plainHeight) / 2
        switch style {
        case .vocab:
            return max(0, centered - dialoguePillPlainVocabUpwardNudge)
        case .grammar:
            return max(0, centered - dialoguePillPlainGrammarUpwardNudge)
        }
    }

    /// Label band height for the tallest furigana pill — keeps every capsule the same height.
    static func dialoguePillFixedBandHeight(for font: UIFont) -> CGFloat {
        let label = FuriganaTranscriptLabel()
        label.numberOfLines = 1
        let sample = "図"
        applyScrubDisplay(
            to: label,
            attributed: scenarioAttributedString(for: sample, font: font, textColor: .label),
            contentInsets: dialoguePillDisplayInsets(for: font, text: sample, style: .vocab)
        )
        return ceil(
            label.sizeThatFits(CGSize(width: 1_000, height: CGFloat.greatestFiniteMagnitude)).height
        )
    }

    static func dialoguePillMeasuredLabelHeight(
        for text: String,
        font: UIFont,
        textInsets: UIEdgeInsets
    ) -> CGFloat {
        let label = FuriganaTranscriptLabel()
        label.numberOfLines = 1
        applyScrubDisplay(
            to: label,
            attributed: scenarioAttributedString(for: text, font: font, textColor: .label),
            contentInsets: textInsets
        )
        return ceil(
            label.sizeThatFits(CGSize(width: 1_000, height: CGFloat.greatestFiniteMagnitude)).height
        )
    }

    private static func textHasFurigana(_ text: String) -> Bool {
        !JapaneseTokenizer.furiganaAnnotations(for: text).isEmpty
    }

    /// Insets for the grammar dialogue scroll card (large title-sized Japanese).
    static func dialogueScrollDisplayInsets(for font: UIFont) -> UIEdgeInsets {
        UIEdgeInsets(top: wordDetailRubyTopInset(for: font), left: 0, bottom: 4, right: 0)
    }

    /// Sentence scrub always shows furigana (independent of the tutor transcript toggle).
    static func applyScrubDisplay(
        to label: FuriganaTranscriptLabel,
        attributed: NSAttributedString,
        contentInsets: UIEdgeInsets
    ) {
        label.textInsets = contentInsets
        label.attributedText = attributed
    }

}
