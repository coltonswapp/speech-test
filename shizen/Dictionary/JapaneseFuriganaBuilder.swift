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

    /// When true (default), vertical `textInsets` sit outside Auto Layout so ruby
    /// can paint into surrounding padding. Dialogue bubbles set this false so
    /// ruby reserves real height inside the bubble.
    var verticalTextInsetsAffectAlignmentRect = true {
        didSet {
            guard verticalTextInsetsAffectAlignmentRect != oldValue else { return }
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    /// When true, color-only attributed updates skip intrinsic-size invalidation
    /// so dialogue emphasis can recolor without re-wrapping the line.
    private var ignoreIntrinsicInvalidation = false
    /// Spoken-token marker. Compact and full both paint in `drawText`.
    private var tokenHighlightRange: NSRange?
    private var tokenHighlightIsFullHeight = false
    private var tokenHighlightFillColor = tokenSyncHighlightColor

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Ruby like わたし on 私 paints a few points past the first glyph.
        clipsToBounds = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        clipsToBounds = false
    }

    override var attributedText: NSAttributedString? {
        get { super.attributedText }
        set {
            tokenHighlightRange = nil
            super.attributedText = newValue
            invalidateIntrinsicContentSize()
        }
    }

    override func invalidateIntrinsicContentSize() {
        guard !ignoreIntrinsicInvalidation else { return }
        super.invalidateIntrinsicContentSize()
    }

    /// Marker fill behind the spoken token. Text stays `foregroundColor`.
    /// Default matches the yellow bubble underglow; prefer the bubble's own glow when known.
    static let tokenSyncHighlightColor = DialogueBubbleUnderglowColor.yellow.tokenHighlightUIColor
    /// On Messages-style solid bubbles, yellow is unreadable — 25% black wash.
    static let tokenSyncHighlightColorOnBlueBubble = UIColor.black.withAlphaComponent(0.25)
    /// Underline-like bar as a fraction of point size; sits on the baseline
    /// and overlaps the lower part of the glyphs.
    private static let tokenHighlightHeightFactor: CGFloat = 0.34
    private static let tokenHighlightBelowBaselineFactor: CGFloat = 0.08
    /// Soften the marker just enough that it doesn't read as a hard box.
    private static let tokenHighlightCornerRadius: CGFloat = 2

    /// Recolors glyphs without changing font or layout. Ruby annotations keep
    /// their own color.
    func setForegroundColorPreservingLayout(_ color: UIColor) {
        setTokenHighlightPreservingLayout(
            foregroundColor: color,
            highlightedRange: nil,
            fullHeight: tokenHighlightIsFullHeight,
            highlightColor: tokenHighlightFillColor
        )
    }

    /// Recolors the full string and optionally paints a yellow highlight behind
    /// a token range, without relayout. Pass `nil` to clear the marker.
    ///
    /// Both styles paint a rounded wash in `drawText`, measured without ruby
    /// so wrapped lines stay on the glyph baseline.
    func setTokenHighlightPreservingLayout(
        foregroundColor: UIColor,
        highlightedRange: NSRange?,
        fullHeight: Bool,
        highlightColor: UIColor = tokenSyncHighlightColor
    ) {
        guard let current = attributedText, current.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: current.length)
        var clampedHighlight: NSRange?
        if let highlightedRange,
           highlightedRange.location >= 0,
           NSMaxRange(highlightedRange) <= current.length,
           highlightedRange.length > 0 {
            clampedHighlight = highlightedRange
        }

        let highlightChanged = !NSEqualRanges(
            tokenHighlightRange ?? NSRange(location: NSNotFound, length: 0),
            clampedHighlight ?? NSRange(location: NSNotFound, length: 0)
        )
        let styleChanged = tokenHighlightIsFullHeight != fullHeight
        let fillChanged = !tokenHighlightFillColor.isVisuallyEqual(to: highlightColor, in: traitCollection)
        tokenHighlightRange = clampedHighlight
        tokenHighlightIsFullHeight = fullHeight
        tokenHighlightFillColor = highlightColor

        var colorAlreadyApplied = true
        current.enumerateAttribute(.foregroundColor, in: fullRange) { value, _, stop in
            guard let value = value as? UIColor,
                  value.isVisuallyEqual(to: foregroundColor, in: traitCollection) else {
                colorAlreadyApplied = false
                stop.pointee = true
                return
            }
        }

        var hasBackground = false
        current.enumerateAttribute(.backgroundColor, in: fullRange) { value, _, stop in
            guard value is UIColor else { return }
            hasBackground = true
            stop.pointee = true
        }

        let needsAttributedUpdate = !colorAlreadyApplied
            || styleChanged
            || fillChanged
            || (fullHeight && highlightChanged)
            || (!fullHeight && hasBackground)

        if needsAttributedUpdate {
            let mutable = NSMutableAttributedString(attributedString: current)
            mutable.addAttribute(.foregroundColor, value: foregroundColor, range: fullRange)
            mutable.removeAttribute(.backgroundColor, range: fullRange)
            ignoreIntrinsicInvalidation = true
            super.attributedText = mutable
            ignoreIntrinsicInvalidation = false
        }

        if highlightChanged || styleChanged || fillChanged || needsAttributedUpdate {
            setNeedsDisplay()
        }
    }

    override var alignmentRectInsets: UIEdgeInsets {
        let overflow = horizontalRubyOverflow
        return UIEdgeInsets(
            top: verticalTextInsetsAffectAlignmentRect ? textInsets.top : 0,
            left: textInsets.left + overflow,
            bottom: verticalTextInsetsAffectAlignmentRect ? textInsets.bottom : 0,
            right: textInsets.right + overflow
        )
    }

    /// Ruby sits above glyphs, but UILabel counts it as extra advance. Hug the
    /// longest wrapped line — not `preferredMaxLayoutWidth` — so a hanging
    /// punctuation wrap does not leave a trailing gap in the bubble.
    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        guard size.width != UIView.noIntrinsicMetric else { return size }
        let limit: CGFloat
        if preferredMaxLayoutWidth > 0 {
            limit = max(1, preferredMaxLayoutWidth - textInsets.left - textInsets.right)
        } else {
            limit = CGFloat.greatestFiniteMagnitude
        }
        size.width = fittedBaseTextWidth(limitingWidth: limit)
        return size
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        var fitted = super.sizeThatFits(size)
        let limit: CGFloat
        if size.width > 0, size.width < CGFloat.greatestFiniteMagnitude / 2 {
            limit = max(1, size.width - textInsets.left - textInsets.right)
        } else {
            limit = CGFloat.greatestFiniteMagnitude
        }
        fitted.width = fittedBaseTextWidth(limitingWidth: limit)
        return fitted
    }

    private func fittedBaseTextWidth(limitingWidth: CGFloat) -> CGFloat {
        guard let attributedText, attributedText.length > 0 else { return 1 }
        let base = JapaneseFuriganaBuilder.usedBaseTextWidth(
            for: attributedText,
            limitingWidth: limitingWidth
        )
        return max(1, ceil(base) + textInsets.left + textInsets.right)
    }

    override func drawText(in rect: CGRect) {
        let overflow = horizontalRubyOverflow
        let drawRect = bounds.inset(by: UIEdgeInsets(
            top: textInsets.top,
            left: textInsets.left + overflow,
            bottom: textInsets.bottom,
            right: textInsets.right + overflow
        ))
        guard let attributedText, attributedText.length > 0 else {
            super.drawText(in: drawRect)
            return
        }
        drawTokenHighlight(in: drawRect)
        if attributedTextHasRuby {
            // Do not ask Core Text to paint ruby. `NSAttributedString.draw`
            // stretches each kanji to the reading width (少々 / しょうしょう)
            // and can shift later readings off their glyphs (ま sitting
            // before 待). Base line first, readings centered on top.
            drawBaseTextWithRubyOverlay(attributedText, in: drawRect)
        } else {
            attributedText.draw(
                with: drawRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        }
    }

    private func drawBaseTextWithRubyOverlay(_ attributed: NSAttributedString, in drawRect: CGRect) {
        guard drawRect.width > 0, drawRect.height > 0 else { return }

        let base = Self.attributedStringByRemovingRuby(attributed)
        let storage = NSTextStorage(attributedString: base)
        let manager = NSLayoutManager()
        manager.usesFontLeading = true
        let container = NSTextContainer(size: CGSize(
            width: drawRect.width,
            height: .greatestFiniteMagnitude
        ))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = numberOfLines
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)

        let glyphs = manager.glyphRange(for: container)
        manager.drawGlyphs(forGlyphRange: glyphs, at: drawRect.origin)

        let rubyKey = NSAttributedString.Key(kCTRubyAnnotationAttributeName as String)
        attributed.enumerateAttribute(rubyKey, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            guard let value,
                  let reading = Self.reading(fromRubyAnnotation: value),
                  !reading.isEmpty,
                  range.length > 0
            else { return }
            self.drawRubyReading(
                reading,
                sizeFactor: Self.sizeFactor(fromRubyAnnotation: value),
                over: range,
                in: drawRect,
                manager: manager,
                container: container,
                attributed: base
            )
        }
    }

    private func drawRubyReading(
        _ reading: String,
        sizeFactor: CGFloat,
        over range: NSRange,
        in drawRect: CGRect,
        manager: NSLayoutManager,
        container: NSTextContainer,
        attributed: NSAttributedString
    ) {
        let glyphRange = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return }

        let baseFont = attributed.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
            ?? font
            ?? .systemFont(ofSize: 17)
        let factor = sizeFactor > 0 ? sizeFactor : JapaneseFuriganaBuilder.rubySizeFactor
        let rubyFont = UIFont.systemFont(ofSize: baseFont.pointSize * factor, weight: .regular)
        let rubyAttrs: [NSAttributedString.Key: Any] = [
            .font: rubyFont,
            .foregroundColor: Self.rubyColor(
                over: range,
                in: attributed,
                traits: traitCollection
            ),
        ]
        let rubySize = (reading as NSString).size(withAttributes: rubyAttrs)

        var didDraw = false
        manager.enumerateLineFragments(forGlyphRange: glyphRange) { fragmentRect, _, _, lineGlyphRange, _ in
            guard !didDraw else { return }
            let intersection = NSIntersectionRange(lineGlyphRange, glyphRange)
            guard intersection.length > 0 else { return }

            var tokenRect = CGRect.null
            manager.enumerateEnclosingRects(
                forGlyphRange: intersection,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: container
            ) { rect, _ in
                tokenRect = tokenRect.union(rect)
            }
            guard !tokenRect.isNull, tokenRect.width > 0 else { return }

            let baseline = manager.location(forGlyphAt: intersection.location).y
            let baselineY = drawRect.minY + fragmentRect.minY + baseline
            let glyphTop = baselineY - baseFont.ascender
            let rubyRect = CGRect(
                x: drawRect.minX + tokenRect.midX - rubySize.width / 2,
                y: glyphTop - rubySize.height + 1,
                width: rubySize.width,
                height: rubySize.height
            )
            (reading as NSString).draw(
                with: rubyRect,
                options: .usesLineFragmentOrigin,
                attributes: rubyAttrs,
                context: nil
            )
            didDraw = true
        }
    }

    /// White-on-blue Messages bubbles: secondaryLabel is too dark on the fill.
    /// Keep a slight fade vs the body so ruby still reads as annotation.
    private static func rubyColor(
        over range: NSRange,
        in attributed: NSAttributedString,
        traits: UITraitCollection
    ) -> UIColor {
        let location = min(max(range.location, 0), max(0, attributed.length - 1))
        guard attributed.length > 0,
              let base = attributed.attribute(.foregroundColor, at: location, effectiveRange: nil) as? UIColor
        else {
            return JapaneseFuriganaBuilder.rubyTextColor
        }
        let resolved = base.resolvedColor(with: traits)
        if resolved.relativeLuminance > 0.82 {
            return UIColor.white.withAlphaComponent(0.78)
        }
        return JapaneseFuriganaBuilder.rubyTextColor
    }

    private static func reading(fromRubyAnnotation value: Any) -> String? {
        let annotation = (value as AnyObject) as! CTRubyAnnotation
        return CTRubyAnnotationGetTextForPosition(annotation, .before) as String?
    }

    private static func sizeFactor(fromRubyAnnotation value: Any) -> CGFloat {
        let annotation = (value as AnyObject) as! CTRubyAnnotation
        return CTRubyAnnotationGetSizeFactor(annotation)
    }

    /// Paints the token wash. Measurement strips ruby and keys off each
    /// fragment's glyph baseline so wrapped lines stay on their glyphs —
    /// laying out *with* ruby inflates the first fragment and drops the
    /// marker below the baseline.
    private func drawTokenHighlight(in drawRect: CGRect) {
        guard let range = tokenHighlightRange,
              let attributed = attributedText,
              range.location >= 0,
              range.length > 0,
              NSMaxRange(range) <= attributed.length,
              drawRect.width > 0,
              drawRect.height > 0 else { return }

        let stripped = Self.attributedStringByRemovingRuby(attributed)
        let storage = NSTextStorage(attributedString: stripped)
        let manager = NSLayoutManager()
        manager.usesFontLeading = true
        let container = NSTextContainer(size: CGSize(
            width: drawRect.width,
            height: .greatestFiniteMagnitude
        ))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)

        let glyphRange = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return }

        let font = attributed.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
            ?? self.font
            ?? .systemFont(ofSize: 17)

        tokenHighlightFillColor.setFill()
        manager.enumerateLineFragments(forGlyphRange: glyphRange) { fragmentRect, _, _, lineGlyphRange, _ in
            let intersection = NSIntersectionRange(lineGlyphRange, glyphRange)
            guard intersection.length > 0 else { return }

            var tokenRect = CGRect.null
            manager.enumerateEnclosingRects(
                forGlyphRange: intersection,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: container
            ) { rect, _ in
                tokenRect = tokenRect.union(rect)
            }
            guard !tokenRect.isNull, tokenRect.width > 0 else { return }

            let baseline = manager.location(forGlyphAt: intersection.location).y
            let baselineY = drawRect.minY + fragmentRect.minY + baseline
            let highlight = self.tokenHighlightRect(
                x: drawRect.minX + tokenRect.minX,
                width: tokenRect.width,
                baselineY: baselineY,
                font: font
            )
            let radius = min(
                Self.tokenHighlightCornerRadius,
                min(highlight.width, highlight.height) / 2
            )
            UIBezierPath(roundedRect: highlight, cornerRadius: radius).fill()
        }
    }

    private func tokenHighlightRect(
        x: CGFloat,
        width: CGFloat,
        baselineY: CGFloat,
        font: UIFont
    ) -> CGRect {
        if tokenHighlightIsFullHeight {
            let height = font.ascender + abs(font.descender)
            return CGRect(
                x: x,
                y: baselineY - font.ascender,
                width: width,
                height: height
            )
        }
        let height = max(5, font.pointSize * Self.tokenHighlightHeightFactor)
        let belowBaseline = font.pointSize * Self.tokenHighlightBelowBaselineFactor
        return CGRect(
            x: x,
            y: baselineY - height + belowBaseline,
            width: width,
            height: height
        )
    }

    fileprivate static func attributedStringByRemovingRuby(
        _ attributed: NSAttributedString
    ) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let rubyKey = NSAttributedString.Key(kCTRubyAnnotationAttributeName as String)
        mutable.removeAttribute(rubyKey, range: NSRange(location: 0, length: mutable.length))
        return mutable
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

    /// Extra drawing width so line-start/end ruby is not clipped.
    private var horizontalRubyOverflow: CGFloat {
        let font = self.font
            ?? attributedText?.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        guard let font, attributedTextHasRuby else { return 0 }
        return JapaneseFuriganaBuilder.rubyHorizontalOverhangInset(for: font)
    }

    private var attributedTextHasRuby: Bool {
        guard let attributedText, attributedText.length > 0 else { return false }
        let key = NSAttributedString.Key(kCTRubyAnnotationAttributeName as String)
        var found = false
        attributedText.enumerateAttribute(key, in: NSRange(location: 0, length: attributedText.length)) { value, _, stop in
            guard value != nil else { return }
            found = true
            stop.pointee = true
        }
        return found
    }
}

enum JapaneseFuriganaBuilder {
    private static let cache = NSCache<NSString, NSAttributedString>()
    fileprivate static let rubySizeFactor: CGFloat = 0.45
    fileprivate static let rubyTextColor = UIColor.secondaryLabel
    /// Bump when ruby alignment / drawing changes so cached strings don't keep the old layout.
    private static let rubyLayoutRevision = "ruby-split-mixed-kana-v12"

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

    /// Horizontal room so ruby can overhang a single kanji (わたし on 私)
    /// without clipping at the label / bubble edge. Used at draw time only —
    /// do not put this in paragraph indent, which corrupts UILabel wrapping.
    fileprivate static func rubyHorizontalOverhangInset(for font: UIFont) -> CGFloat {
        ceil(font.pointSize * rubySizeFactor * 0.85)
    }

    /// Width of the drawn base line, including optical glyph overflow.
    /// Ruby is painted as an overlay, so measurement strips it — otherwise
    /// Core Text counts furigana as extra advance and the bubble goes wide.
    static func usedBaseTextWidth(
        for attributed: NSAttributedString,
        limitingWidth: CGFloat = .greatestFiniteMagnitude
    ) -> CGFloat {
        guard attributed.length > 0 else { return 0 }
        let measured = FuriganaTranscriptLabel.attributedStringByRemovingRuby(attributed)

        let cap: CGFloat
        if limitingWidth > 0, limitingWidth.isFinite, limitingWidth < CGFloat.greatestFiniteMagnitude / 2 {
            cap = limitingWidth
        } else {
            cap = CGFloat.greatestFiniteMagnitude
        }

        let framesetter = CTFramesetterCreateWithAttributedString(measured)
        let path = CGPath(
            rect: CGRect(x: 0, y: 0, width: cap, height: 10_000),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: measured.length),
            path,
            nil
        )
        let lines = CTFrameGetLines(frame)
        let count = CFArrayGetCount(lines)
        guard count > 0 else { return 0 }

        var longest: CGFloat = 0
        for index in 0..<count {
            let line = unsafeBitCast(CFArrayGetValueAtIndex(lines, index), to: CTLine.self)
            let typographic = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let ink = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
            let inkWidth = ink.maxX - min(ink.minX, 0)
            longest = max(longest, typographic, inkWidth)
        }
        return longest
    }

    private static func dialogueBubbleParagraphStyle(font: UIFont, hasFurigana: Bool) -> NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byCharWrapping
        paragraphStyle.minimumLineHeight = font.lineHeight
        if hasFurigana {
            // Gap between wrapped lines only — ruby on line 2+ sits in this
            // space. Extra minimumLineHeight on a single line just lengthens
            // the box and drops the glyphs.
            let rubyReserve = font.pointSize * rubySizeFactor
            paragraphStyle.lineSpacing = ceil(rubyReserve) + 4
        } else {
            paragraphStyle.lineSpacing = 0
        }
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
            // `.center` widens each kanji to the ruby width (つか on 疲).
            // `.auto` + overhang lets furigana sit above without stretching
            // the base line.
            attributed.addAttribute(
                NSAttributedString.Key(kCTRubyAnnotationAttributeName as String),
                value: furi.rubyAnnotation(
                    alignment: .auto,
                    overhang: .auto,
                    sizeFActor: rubySizeFactor,
                    attributes: rubyAttributes
                ),
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
            "\(trimmed)|\(font.fontName)|\(font.pointSize)|\(textColor.cgColor.hashValue)|\(transcriptRubyTopInset(for: font))|\(transcriptLineSpacing)|\(rubyLayoutRevision)" as NSString
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
            "usage-ladder|\(trimmed)|\(font.fontName)|\(font.pointSize)|\(textColor.cgColor.hashValue)|\(rubyLayoutRevision)" as NSString
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
            "dialogue-scroll|\(trimmed)|\(font.fontName)|\(font.pointSize)|\(textColor.cgColor.hashValue)|\(rubyLayoutRevision)" as NSString
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
            "dialogue-bubble|\(trimmed)|\(font.fontName)|\(font.pointSize)|\(textColor.cgColor.hashValue)|\(rubyLayoutRevision)" as NSString
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
            paragraphStyle: dialogueBubbleParagraphStyle(
                font: font,
                hasFurigana: textHasFurigana(trimmed)
            )
        )

        let result = NSAttributedString(attributedString: base)
        cache.setObject(result, forKey: cacheKey)
        return result
    }

    /// Progressive Speak-as-B paint: blue matched prefix + gray remainder (furigana-safe).
    /// `prefixUTF16Length` is measured on the trimmed display string.
    static func dialogueBubbleAttributedString(
        for text: String,
        font: UIFont,
        prefixUTF16Length: Int,
        prefixColor: UIColor,
        remainderColor: UIColor
    ) -> NSAttributedString {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: remainderColor])
        }

        let nsLen = (trimmed as NSString).length
        let clamped = max(0, min(prefixUTF16Length, nsLen))
        let cacheKey =
            "dialogue-bubble-progressive|\(trimmed)|\(font.fontName)|\(font.pointSize)|\(clamped)|\(prefixColor.cgColor.hashValue)|\(remainderColor.cgColor.hashValue)|\(rubyLayoutRevision)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let base = NSMutableAttributedString(
            string: trimmed,
            attributes: [
                .font: font,
                .foregroundColor: remainderColor,
            ]
        )
        if clamped > 0 {
            base.addAttribute(
                .foregroundColor,
                value: prefixColor,
                range: NSRange(location: 0, length: clamped)
            )
        }
        applyFurigana(
            to: base,
            text: trimmed,
            font: font,
            paragraphStyle: dialogueBubbleParagraphStyle(
                font: font,
                hasFurigana: textHasFurigana(trimmed)
            )
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
            "scenario|\(trimmed)|\(font.fontName)|\(font.pointSize)|\(textColor.cgColor.hashValue)|\(rubyLayoutRevision)" as NSString
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
            "flashcard|\(trimmed)|\(font.fontName)|\(font.pointSize)|\(textColor.cgColor.hashValue)|\(rubyLayoutRevision)" as NSString
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
    static func dialogueBubbleDisplayInsets(for font: UIFont, text: String = "") -> UIEdgeInsets {
        if !text.isEmpty, !textHasFurigana(text) {
            // Bubble chrome is 6/10 (top/bottom) for the corner radius; extra
            // top inset drops the glyphs onto the same optical midline as ruby.
            return UIEdgeInsets(top: 5, left: 0, bottom: 1, right: 0)
        }
        // Only the ruby glyph height — extra slop here reads as a void above じっか
        // and drops the base line off optical center.
        let top = ceil(font.pointSize * rubySizeFactor)
        return UIEdgeInsets(top: top, left: 0, bottom: 3, right: 0)
    }

    static func applyDialogueBubbleDisplay(
        to label: FuriganaTranscriptLabel,
        text: String,
        font: UIFont,
        textColor: UIColor
    ) {
        applyDialogueBubbleDisplay(
            to: label,
            text: text,
            font: font,
            attributed: dialogueBubbleAttributedString(for: text, font: font, textColor: textColor)
        )
    }

    static func applyDialogueBubbleDisplay(
        to label: FuriganaTranscriptLabel,
        text: String,
        font: UIFont,
        prefixUTF16Length: Int,
        prefixColor: UIColor,
        remainderColor: UIColor
    ) {
        applyDialogueBubbleDisplay(
            to: label,
            text: text,
            font: font,
            attributed: dialogueBubbleAttributedString(
                for: text,
                font: font,
                prefixUTF16Length: prefixUTF16Length,
                prefixColor: prefixColor,
                remainderColor: remainderColor
            )
        )
    }

    static func applyDialogueBubbleDisplay(
        to label: FuriganaTranscriptLabel,
        text: String,
        font: UIFont,
        attributed: NSAttributedString
    ) {
        label.verticalTextInsetsAffectAlignmentRect = false
        applyScrubDisplay(
            to: label,
            attributed: attributed,
            contentInsets: dialogueBubbleDisplayInsets(for: font, text: text)
        )
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

private extension UIColor {
    var relativeLuminance: CGFloat {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if getRed(&r, green: &g, blue: &b, alpha: &a) {
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        var white: CGFloat = 0
        if getWhite(&white, alpha: &a) {
            return white
        }
        return 0
    }

    func isVisuallyEqual(to other: UIColor, in traits: UITraitCollection) -> Bool {
        let a = resolvedColor(with: traits)
        let b = other.resolvedColor(with: traits)
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0
        guard a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else {
            return a == b
        }
        return abs(r1 - r2) < 0.004
            && abs(g1 - g2) < 0.004
            && abs(b1 - b2) < 0.004
            && abs(a1 - a2) < 0.004
    }
}
