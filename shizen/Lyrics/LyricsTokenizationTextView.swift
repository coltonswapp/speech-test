//
//  LyricsTokenizationTextView.swift
//  shizen
//
//  Inline tappable word regions for a single sentence. Used in LyricsViewController
//  focus mode. Selection + underlines are custom-drawn; parent shows a definition tip.
//

import CoreText
import UIKit

private extension NSAttributedString.Key {
  static let jmdictTokenIndex = NSAttributedString.Key("jmdictTokenIndex")
}

// MARK: - Selection drawing

public enum LyricsTokenSelectionAppearance {
  /// Rounded blue fill behind the token; white text. Used with definition tips in lyrics.
  case definitionTip
  /// Thick blue underline on the active token; thin grey on others (scrub / explore experiments).
  case scrubUnderline
}

// MARK: - Inset underlines + rounded blue selection (drawn before glyphs)

public final class LyricsInsetUnderlineTextView: UITextView {
  /// `CGRect` is in the text view’s coordinate space; convert in the parent when anchoring a tip.
  /// The parent should call `setDefinitionSelectionHighlight` only after a definition tip is shown; blue fill follows that.
  public var onWordTapped: ((String, CGRect, Int) -> Void)?

  public var underlineHorizontalPadding: CGFloat = 2.5

  /// Space between the glyph bounds bottom and the underline (positive = line sits lower).
  public var underlineVerticalGap: CGFloat = 2

  /// Layout points; slightly thick so underlines read clearly on iPhone.
  public var tokenUnderlineWidth: CGFloat = 3
  public var tokenUnderlineColor: UIColor = UIColor.systemGray3

  /// Stroke under the active token when `tokenSelectionAppearance == .scrubUnderline`.
  public var scrubActiveUnderlineWidth: CGFloat = 4
  public var scrubActiveUnderlineColor: UIColor = UIColor.systemBlue

  public var tokenSelectionAppearance: LyricsTokenSelectionAppearance = .definitionTip

  public private(set) var selectedTokenIndex: Int?

  /// Horizontal: keep small so the rounded fill doesn’t extend far past glyph bounds into neighbors.
  private let selectionHPad: CGFloat = 0.5
  private let selectionVPad: CGFloat = 1
  private let selectionCornerRadius: CGFloat = 6
  private let selectionColor = UIColor.systemBlue

  private var tokens: [JapaneseToken] = []
  /// Parallel to `tokens`: merged adjacent surfaces when the pair is an exact JMdict match (e.g. お + 釣り → お釣り).
  private var tokenLookupSurfaces: [String] = []
  private let japaneseTokenizer = JapaneseTokenizer()
  private var fullText: String = ""
  private var showsFurigana = false
  private var accentSubstring: String?
  private var accentColor: UIColor = .systemBlue
  private var visibleAttributedText: NSAttributedString?

  private struct FuriganaTextLayout {
    let frame: CTFrame
    let textOrigin: CGPoint
    let textSize: CGSize
  }

  private var furiganaLayout: FuriganaTextLayout?

  private let tap = UITapGestureRecognizer()

  public override var attributedText: NSAttributedString! {
    didSet { setNeedsDisplay() }
  }

  public override init(frame: CGRect, textContainer: NSTextContainer?) {
    super.init(frame: frame, textContainer: textContainer)
    commonInit()
  }

  public convenience init() {
    self.init(frame: .zero, textContainer: nil)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    commonInit()
  }

  private func commonInit() {
    isEditable = false
    isScrollEnabled = false
    isSelectable = false
    backgroundColor = .clear
    // Custom `draw` is clipped to bounds; we add `textContainerInset` + intrinsic sizing
    // so underlines and selection are not cut off. Lyrics rows keep `clipsToBounds` false.
    textContainerInset = .zero
    clipsToBounds = false
    textContainer.lineFragmentPadding = 0
    textContainer.widthTracksTextView = true
    textContainer.heightTracksTextView = false
    tap.addTarget(self, action: #selector(handleTap))
    addGestureRecognizer(tap)
  }

  /// Room below the last line for the stroke, gap, and selection padding (`draw` is clipped to bounds).
  private var bottomTextContainerOutset: CGFloat {
    let lineW = max(1.5, tokenUnderlineWidth)
    return underlineVerticalGap + lineW * 0.5 + selectionVPad + 4
  }

  /// Insets the text away from the view edges so `draw(_:)` (clipped to bounds) can show
  /// definition-tip rounded fills and scrub/underline round caps that extend past glyph bounds.
  private var textContainerEdgeOutset: CGFloat {
    max(selectionHPad, selectionVPad) + selectionCornerRadius * 0.5 + 2
  }

  public override var intrinsicContentSize: CGSize {
    if bounds.width <= 0 { return super.intrinsicContentSize }
    return sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
  }

  public override func sizeThatFits(_ size: CGSize) -> CGSize {
    let fit: CGSize
    if size.width > 0 {
      fit = super.sizeThatFits(CGSize(width: size.width, height: .greatestFiniteMagnitude))
    } else {
      fit = super.sizeThatFits(size)
    }
    guard showsFurigana, size.width > 0 else {
      return fit
    }

    let textHeight = furiganaTextContentHeight(forViewWidth: size.width)
    let totalHeight = textHeight + textContainerInset.top + textContainerInset.bottom
    return CGSize(width: fit.width, height: max(fit.height, totalHeight))
  }

  private func furiganaTextWidth(forViewWidth viewWidth: CGFloat) -> CGFloat {
    viewWidth - textContainerInset.left - textContainerInset.right
  }

  private func furiganaTextContentHeight(forViewWidth viewWidth: CGFloat) -> CGFloat {
    guard let visible = visibleAttributedText, visible.length > 0 else { return 0 }
    let width = furiganaTextWidth(forViewWidth: viewWidth)
    guard width > 0 else { return 0 }
    let framesetter = CTFramesetterCreateWithAttributedString(visible)
    var fitRange = CFRange()
    let size = CTFramesetterSuggestFrameSizeWithConstraints(
      framesetter,
      CFRange(location: 0, length: visible.length),
      nil,
      CGSize(width: width, height: .greatestFiniteMagnitude),
      &fitRange
    )
    return max(size.height, 1)
  }

  @discardableResult
  private func rebuildFuriganaLayoutIfNeeded(forViewWidth viewWidth: CGFloat? = nil) -> FuriganaTextLayout? {
    guard showsFurigana, let visible = visibleAttributedText, visible.length > 0 else {
      furiganaLayout = nil
      return nil
    }
    let width = viewWidth ?? bounds.width
    let textWidth = furiganaTextWidth(forViewWidth: width)
    guard textWidth > 0 else { return furiganaLayout }

    let framesetter = CTFramesetterCreateWithAttributedString(visible)
    var fitRange = CFRange()
    let textSize = CTFramesetterSuggestFrameSizeWithConstraints(
      framesetter,
      CFRange(location: 0, length: visible.length),
      nil,
      CGSize(width: textWidth, height: .greatestFiniteMagnitude),
      &fitRange
    )
    let frameHeight = max(textSize.height, 1)
    let path = CGPath(
      rect: CGRect(x: 0, y: 0, width: textWidth, height: frameHeight),
      transform: nil
    )
    let frame = CTFramesetterCreateFrame(
      framesetter,
      CFRange(location: 0, length: visible.length),
      path,
      nil
    )
    let layout = FuriganaTextLayout(
      frame: frame,
      textOrigin: CGPoint(x: textContainerInset.left, y: textContainerInset.top),
      textSize: CGSize(width: textWidth, height: frameHeight)
    )
    furiganaLayout = layout
    return layout
  }

  /// Rounded blue fill + light text; only used while a definition tip is active (parent drives this).
  public func setDefinitionSelectionHighlight(tokenIndex: Int?) {
    let font: UIFont
    if let a = attributedText, a.length > 0 {
      font = Self.fontForAttributes(from: a)
    } else {
      font = UIFont.preferredFont(forTextStyle: .title1)
    }
    selectedTokenIndex = tokenIndex
    let selectedIndices = tokenIndex.map { contiguousIndicesWithSameLookup(as: $0) }
    let built = Self.buildAttributed(
      text: fullText,
      tokens: tokens,
      font: font,
      selectedIndices: selectedIndices,
      selectionAppearance: tokenSelectionAppearance,
      showsFurigana: showsFurigana
    )
    let styled = NSMutableAttributedString(attributedString: built)
    applyAccentHighlight(to: styled, in: fullText)
    applyVisibleAttributedText(styled)
    setNeedsDisplay()
  }

  /// - Parameter showsFurigana: When true, adds MeCab ruby readings and extra line height (sentence scrub).
  /// - Parameter accentSubstring: Optional substring drawn in `accentColor` (e.g. a learner's fill-in choice).
  func configure(
    sentence: String,
    lyricFont: UIFont,
    tokenizer tokenizerOverride: JapaneseTokenizer? = nil,
    showsFurigana: Bool = false,
    accentSubstring: String? = nil,
    accentColor: UIColor = .systemBlue
  ) {
    let tokenizer = tokenizerOverride ?? japaneseTokenizer
    applyTokenConfiguration(
      sentence: sentence,
      lyricFont: lyricFont,
      tokens: tokenizer.tokenize(sentence),
      showsFurigana: showsFurigana,
      accentSubstring: accentSubstring,
      accentColor: accentColor
    )
  }

  func configure(
    sentence: String,
    lyricFont: UIFont,
    tokens precomputedTokens: [JapaneseToken],
    showsFurigana: Bool = false,
    accentSubstring: String? = nil,
    accentColor: UIColor = .systemBlue
  ) {
    applyTokenConfiguration(
      sentence: sentence,
      lyricFont: lyricFont,
      tokens: precomputedTokens,
      showsFurigana: showsFurigana,
      accentSubstring: accentSubstring,
      accentColor: accentColor
    )
  }

  private func applyTokenConfiguration(
    sentence: String,
    lyricFont: UIFont,
    tokens rawTokens: [JapaneseToken],
    showsFurigana: Bool,
    accentSubstring: String?,
    accentColor: UIColor
  ) {
    fullText = sentence
    self.showsFurigana = showsFurigana
    tokens = Self.expandIfSingleFullSentenceToken(
      base: sentence,
      tokens: rawTokens
    )
    tokenLookupSurfaces = JMDictStore.shared.effectiveLookupSurfaces(for: tokens)
    selectedTokenIndex = nil
    let edge = textContainerEdgeOutset
    textContainerInset = UIEdgeInsets(
      top: edge,
      left: edge,
      bottom: bottomTextContainerOutset,
      right: edge
    )
    self.accentSubstring = accentSubstring
    self.accentColor = accentColor
    let built = Self.buildAttributed(
      text: sentence,
      tokens: tokens,
      font: lyricFont,
      selectedIndices: nil,
      selectionAppearance: tokenSelectionAppearance,
      showsFurigana: showsFurigana
    )
    let styled = NSMutableAttributedString(attributedString: built)
    applyAccentHighlight(to: styled, in: sentence)
    applyVisibleAttributedText(styled)
    invalidateIntrinsicContentSize()
    setNeedsDisplay()
  }

  private func applyAccentHighlight(to styled: NSMutableAttributedString, in text: String) {
    guard let accentSubstring, !accentSubstring.isEmpty, let range = text.range(of: accentSubstring) else {
      return
    }
    let nsRange = NSRange(range, in: text)
    guard nsRange.location != NSNotFound, NSMaxRange(nsRange) <= styled.length else { return }
    styled.addAttribute(.foregroundColor, value: accentColor, range: nsRange)
  }

  /// Visible string for furigana scrub; underlines/selection use the same Core Text layout.
  private func applyVisibleAttributedText(_ visible: NSAttributedString) {
    visibleAttributedText = visible
    furiganaLayout = nil
    attributedText = showsFurigana ? Self.layoutOnlyAttributedText(from: visible) : visible
  }

  private static func layoutOnlyAttributedText(from visible: NSAttributedString) -> NSAttributedString {
    let m = NSMutableAttributedString(attributedString: visible)
    guard m.length > 0 else { return m }
    m.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: 0, length: m.length))
    return m
  }

  /// Maps a point in this view’s bounds to a token index (same logic as tap).
  public func tokenIndex(at pointInView: CGPoint) -> Int? {
    if showsFurigana, let layout = furiganaLayout ?? rebuildFuriganaLayoutIfNeeded(),
      let visible = visibleAttributedText {
      return tokenIndexFromCoreText(at: pointInView, layout: layout, in: visible)
    }
    guard let pos = closestPosition(to: pointInView) else { return nil }
    let idx = offset(from: beginningOfDocument, to: pos)
    guard let a = attributedText, a.length > 0, idx >= 0, idx < a.length else { return nil }
    return tokenIndexResolving(near: idx, in: a)
  }

  public func tokenSurface(at index: Int) -> String? {
    guard tokens.indices.contains(index), tokenLookupSurfaces.indices.contains(index) else { return nil }
    return tokenLookupSurfaces[index]
  }

  // MARK: - Drawing (same as prior Sentence inline implementation)

  /// Trailing edge of the last laid-out line, in this text view’s coordinate space.
  /// When furigana is shown, uses base Japanese glyph metrics only (not furigana above).
  public func lastLineTrailingRectInTextView() -> CGRect? {
    guard let text = attributedText, text.length > 0 else { return nil }
    let fragments = lineFragmentViewRectsForCharacterRange(
      NSRange(location: 0, length: text.length),
      baseTextOnly: showsFurigana
    )
    return fragments.last
  }

  public func wordBoundsInTextView(forTokenIndex tIdx: Int) -> CGRect? {
    guard tokens.indices.contains(tIdx) else { return nil }
    let r = NSRange(tokens[tIdx].range, in: fullText)
    return lineBoundsInView(forCharacterRange: r)
  }

  /// Union of bounds for this token and any neighbors merged into the same dictionary lookup (e.g. お + 釣り).
  public func mergedWordBoundsInTextView(forTokenIndex tIdx: Int) -> CGRect? {
    let fragments = mergedWordLineFragmentRectsInTextView(forTokenIndex: tIdx)
    guard let first = fragments.first else { return nil }
    return fragments.dropFirst().reduce(first) { $0.union($1) }
  }

  /// Per-line tight rects for a merged lookup group (top-to-bottom). Use the first line to place
  /// a callout above and the last line to place one below when the highlight spans multiple lines.
  public func mergedWordLineFragmentRectsInTextView(forTokenIndex tIdx: Int) -> [CGRect] {
    let group = contiguousIndicesWithSameLookup(as: tIdx).sorted()
    guard !group.isEmpty else { return [] }
    var unionRange: NSRange?
    for i in group {
      guard tokens.indices.contains(i) else { continue }
      let r = NSRange(tokens[i].range, in: fullText)
      guard r.location != NSNotFound, r.length > 0 else { continue }
      unionRange = unionRange.map { NSUnionRange($0, r) } ?? r
    }
    guard let unionRange else { return [] }
    return lineFragmentViewRectsForCharacterRange(unionRange)
  }

  private func contiguousIndicesWithSameLookup(as index: Int) -> Set<Int> {
    guard tokens.indices.contains(index) else { return [index] }
    guard tokenLookupSurfaces.indices.contains(index) else { return [index] }
    let surface = tokenLookupSurfaces[index]
    var lo = index
    while lo > 0, tokenLookupSurfaces[lo - 1] == surface { lo -= 1 }
    var hi = index
    while hi + 1 < tokens.count, tokenLookupSurfaces[hi + 1] == surface { hi += 1 }
    return Set(lo...hi)
  }

  /// Character ranges for underlines: one segment per contiguous run of tokens with the same lookup surface (matches merged highlight).
  private func mergedUnderlineSegments() -> [(range: NSRange, tokenIndices: Set<Int>)] {
    guard !tokens.isEmpty else { return [] }
    if tokenLookupSurfaces.count != tokens.count {
      return tokens.enumerated().compactMap { i, t -> (NSRange, Set<Int>)? in
        let r = NSRange(t.range, in: fullText)
        guard r.location != NSNotFound, r.length > 0 else { return nil }
        return (r, Set([i]))
      }
    }
    var out: [(NSRange, Set<Int>)] = []
    var i = 0
    while i < tokens.count {
      let surface = tokenLookupSurfaces[i]
      var hi = i
      while hi + 1 < tokens.count, tokenLookupSurfaces[hi + 1] == surface {
        hi += 1
      }
      var unionRange: NSRange?
      var idx = Set<Int>()
      for j in i...hi {
        idx.insert(j)
        let r = NSRange(tokens[j].range, in: fullText)
        guard r.location != NSNotFound, r.length > 0 else { continue }
        unionRange = unionRange.map { NSUnionRange($0, r) } ?? r
      }
      if let u = unionRange, u.length > 0 {
        out.append((u, idx))
      }
      i = hi + 1
    }
    return out
  }

  private func lineBoundsInView(forCharacterRange r: NSRange) -> CGRect? {
    let rects = lineFragmentViewRectsForCharacterRange(r)
    guard let first = rects.first else { return nil }
    return rects.dropFirst().reduce(first) { $0.union($1) }
  }

  /// Tight per–line-fragment rects in view coordinates. Using the full `boundingRect(forGlyphRange:)`
  /// for a range that spans line fragments can expand to the text view width on each line; drawing
  /// per line fragment matches glyphs only.
  private func lineFragmentViewRectsForCharacterRange(
    _ r: NSRange,
    baseTextOnly: Bool = false
  ) -> [CGRect] {
    if showsFurigana, let layout = furiganaLayout ?? rebuildFuriganaLayoutIfNeeded() {
      return coreTextLineFragmentViewRects(
        forCharacterRange: r,
        layout: layout,
        baseTextOnly: baseTextOnly
      )
    }
    let lm = layoutManager
    let c = textContainer
    let gr = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
    guard gr.length > 0 else { return [] }
    var out: [CGRect] = []
    lm.enumerateLineFragments(forGlyphRange: gr) { _, _, _, lineGlyphRange, _ in
      let sub = NSIntersectionRange(gr, lineGlyphRange)
      guard sub.length > 0 else { return }
      var br = lm.boundingRect(forGlyphRange: sub, in: c)
      guard !br.isNull, !br.isEmpty else { return }
      br.origin.x += self.textContainerInset.left
      br.origin.y += self.textContainerInset.top
      br.origin.x -= self.contentOffset.x
      br.origin.y -= self.contentOffset.y
      out.append(br)
    }
    return out
  }

  public override func draw(_ rect: CGRect) {
    guard let full = attributedText, full.length > 0 else {
      super.draw(rect)
      return
    }
    if tokenSelectionAppearance == .definitionTip, let sel = selectedTokenIndex {
      let highlight = contiguousIndicesWithSameLookup(as: sel)
      let source = visibleAttributedText ?? full
      source.enumerateAttribute(
        .jmdictTokenIndex, in: NSRange(location: 0, length: source.length), options: []
      ) { value, charRange, _ in
        guard let value else { return }
        let n: Int = (value as? NSNumber)?.intValue ?? (value as? Int) ?? -1
        guard highlight.contains(n), charRange.length > 0 else { return }
        for fragment in self.lineFragmentViewRectsForCharacterRange(charRange, baseTextOnly: showsFurigana) {
          var b = fragment
          if self.showsFurigana {
            b = CGRect(
              x: b.minX - selectionHPad,
              y: b.minY,
              width: b.width + selectionHPad * 2,
              height: b.height + selectionVPad
            )
          } else {
            b = b.insetBy(dx: -selectionHPad, dy: -selectionVPad)
          }
          guard b.width > 1, b.height > 0.5, b.intersects(rect) else { continue }
          let r = min(selectionCornerRadius, b.height * 0.45)
          let p = UIBezierPath(roundedRect: b, cornerRadius: r)
          selectionColor.setFill()
          p.fill()
        }
      }
    }
    if showsFurigana {
      _ = rebuildFuriganaLayoutIfNeeded()
      drawFuriganaCoreText()
      if tokenSelectionAppearance == .definitionTip, let sel = selectedTokenIndex {
        drawFuriganaSelectionBaseTextOverlay(
          highlight: contiguousIndicesWithSameLookup(as: sel)
        )
      }
    } else {
      super.draw(rect)
    }
    let pad = underlineHorizontalPadding
    let underlineHighlight =
      selectedTokenIndex.map { contiguousIndicesWithSameLookup(as: $0) } ?? []
    let underlineSegments = mergedUnderlineSegments()
    if showsFurigana {
      drawInsetUnderlinesUsingViewRects(
        segments: underlineSegments,
        pad: pad,
        rect: rect,
        underlineHighlight: underlineHighlight
      )
    } else {
      let lm = layoutManager
      let c = textContainer
      Self.drawInsetUnderlines(
        segments: underlineSegments,
        layoutManager: lm,
        textContainer: c,
        textContainerInset: textContainerInset,
        contentOffset: contentOffset,
        pad: pad,
        rect: rect,
        underlineVerticalGap: underlineVerticalGap,
        tokenSelectionAppearance: tokenSelectionAppearance,
        selectedTokenIndices: underlineHighlight,
        inactiveLineWidth: max(1.5, tokenUnderlineWidth),
        inactiveColor: tokenUnderlineColor,
        activeLineWidth: max(1.5, scrubActiveUnderlineWidth),
        activeColor: scrubActiveUnderlineColor
      )
    }
  }

  private func drawFuriganaCoreText() {
    guard let layout = furiganaLayout, let ctx = UIGraphicsGetCurrentContext() else { return }
    ctx.saveGState()
    ctx.translateBy(x: layout.textOrigin.x, y: layout.textOrigin.y + layout.textSize.height)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textMatrix = .identity
    CTFrameDraw(layout.frame, ctx)
    ctx.restoreGState()
  }

  /// White base glyphs on the blue selection pill; furigana stays from the first pass only.
  private func drawFuriganaSelectionBaseTextOverlay(highlight: Set<Int>) {
    guard
      !highlight.isEmpty,
      let visible = visibleAttributedText,
      let layout = furiganaLayout,
      let ctx = UIGraphicsGetCurrentContext()
    else { return }

    let overlay = Self.selectionOverlayAttributedString(from: visible, highlight: highlight)
    let originalLines = coreTextLines(in: layout.frame)
    let lineOrigins = coreTextLineOrigins(in: layout.frame, lineCount: originalLines.count)

    let framesetter = CTFramesetterCreateWithAttributedString(overlay)
    let path = CGPath(
      rect: CGRect(origin: .zero, size: layout.textSize),
      transform: nil
    )
    let overlayFrame = CTFramesetterCreateFrame(
      framesetter,
      CFRange(location: 0, length: overlay.length),
      path,
      nil
    )
    let overlayLines = coreTextLines(in: overlayFrame)

    ctx.saveGState()
    ctx.translateBy(x: layout.textOrigin.x, y: layout.textOrigin.y + layout.textSize.height)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textMatrix = .identity

    for index in 0..<min(originalLines.count, overlayLines.count) {
      let lineRange = CTLineGetStringRange(originalLines[index])
      guard lineRange.length > 0 else { continue }
      let nsRange = NSRange(location: lineRange.location, length: lineRange.length)
      guard Self.lineIntersectsHighlight(in: visible, range: nsRange, highlight: highlight) else { continue }
      ctx.textPosition = lineOrigins[index]
      CTLineDraw(overlayLines[index], ctx)
    }

    ctx.restoreGState()
  }

  /// Overlay keeps ruby layout metrics but draws ruby invisibly so the white base glyphs
  /// align with the first pass (stripping ruby shifts lines by paragraph line spacing).
  private static func selectionOverlayAttributedString(
    from visible: NSAttributedString,
    highlight: Set<Int>
  ) -> NSAttributedString {
    let overlay = NSMutableAttributedString(attributedString: visible)
    let fullRange = NSRange(location: 0, length: overlay.length)
    let rubyKey = NSAttributedString.Key(kCTRubyAnnotationAttributeName as String)

    overlay.enumerateAttribute(rubyKey, in: fullRange) { value, range, _ in
      guard let value else { return }
      let clearAnnotation = clearRubyAnnotation(from: value)
      overlay.addAttribute(rubyKey, value: clearAnnotation, range: range)
    }
    overlay.addAttribute(.foregroundColor, value: UIColor.clear, range: fullRange)
    overlay.enumerateAttribute(.jmdictTokenIndex, in: fullRange, options: []) { value, charRange, _ in
      guard let value, charRange.length > 0 else { return }
      let n: Int = (value as? NSNumber)?.intValue ?? (value as? Int) ?? -1
      guard highlight.contains(n) else { return }
      overlay.addAttribute(.foregroundColor, value: UIColor.white, range: charRange)
    }
    return overlay
  }

  private static func lineIntersectsHighlight(
    in visible: NSAttributedString,
    range: NSRange,
    highlight: Set<Int>
  ) -> Bool {
    var intersects = false
    visible.enumerateAttribute(.jmdictTokenIndex, in: range, options: []) { value, _, stop in
      guard let value else { return }
      let n: Int = (value as? NSNumber)?.intValue ?? (value as? Int) ?? -1
      guard highlight.contains(n) else { return }
      intersects = true
      stop.pointee = true
    }
    return intersects
  }

  private static func clearRubyAnnotation(from source: Any) -> CTRubyAnnotation {
    let annotation = (source as AnyObject) as! CTRubyAnnotation
    let sizeFactor = CTRubyAnnotationGetSizeFactor(annotation)
    let alignment = CTRubyAnnotationGetAlignment(annotation)
    let overhang = CTRubyAnnotationGetOverhang(annotation)
    let reading = (CTRubyAnnotationGetTextForPosition(annotation, .before) as String?) ?? ""
    let attrs: [CFString: Any] = [
      kCTRubyAnnotationSizeFactorAttributeName: sizeFactor,
      kCTForegroundColorAttributeName: UIColor.clear.cgColor,
    ]
    return CTRubyAnnotationCreateWithAttributes(
      alignment,
      overhang,
      .before,
      reading as CFString,
      attrs as CFDictionary
    )
  }

  private func coreTextLines(in frame: CTFrame) -> [CTLine] {
    let linesArray = CTFrameGetLines(frame)
    let lineCount = CFArrayGetCount(linesArray)
    guard lineCount > 0 else { return [] }
    return (0..<lineCount).map { index in
      let rawLine = CFArrayGetValueAtIndex(linesArray, index)
      return unsafeBitCast(rawLine, to: CTLine.self)
    }
  }

  private func coreTextLineOrigins(in frame: CTFrame, lineCount: Int) -> [CGPoint] {
    var origins = [CGPoint](repeating: .zero, count: lineCount)
    guard lineCount > 0 else { return origins }
    CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
    return origins
  }

  private func coreTextLineFragmentViewRects(
    forCharacterRange range: NSRange,
    layout: FuriganaTextLayout,
    baseTextOnly: Bool = false
  ) -> [CGRect] {
    let lines = coreTextLines(in: layout.frame)
    guard !lines.isEmpty else { return [] }
    let lineOrigins = coreTextLineOrigins(in: layout.frame, lineCount: lines.count)
    let baseFont = baseTextOnly ? Self.fontForAttributes(from: visibleAttributedText ?? NSAttributedString()) : nil
    var out: [CGRect] = []
    for (index, line) in lines.enumerated() {
      let lineRange = CTLineGetStringRange(line)
      let lineNSRange = NSRange(location: lineRange.location, length: lineRange.length)
      let sub = NSIntersectionRange(range, lineNSRange)
      guard sub.length > 0 else { continue }
      let startX = CTLineGetOffsetForStringIndex(line, sub.location, nil)
      let endX = CTLineGetOffsetForStringIndex(line, sub.location + sub.length, nil)
      var ascent: CGFloat = 0
      var descent: CGFloat = 0
      var leading: CGFloat = 0
      CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
      let glyphAscent: CGFloat
      let glyphDescent: CGFloat
      if baseTextOnly, let baseFont {
        glyphAscent = baseFont.ascender
        glyphDescent = -baseFont.descender
      } else {
        glyphAscent = ascent
        glyphDescent = descent
      }
      let origin = lineOrigins[index]
      let minX = min(startX, endX)
      let width = abs(endX - startX)
      let y = layout.textOrigin.y + (layout.textSize.height - origin.y - glyphAscent)
      out.append(
        CGRect(
          x: layout.textOrigin.x + origin.x + minX,
          y: y,
          width: width,
          height: glyphAscent + glyphDescent
        )
      )
    }
    return out
  }

  private func tokenIndexFromCoreText(
    at point: CGPoint,
    layout: FuriganaTextLayout,
    in attributed: NSAttributedString
  ) -> Int? {
    let localX = point.x - layout.textOrigin.x
    let localY = point.y - layout.textOrigin.y
    guard localX >= 0, localY >= 0 else { return nil }

    let lines = coreTextLines(in: layout.frame)
    guard !lines.isEmpty else { return nil }
    let lineOrigins = coreTextLineOrigins(in: layout.frame, lineCount: lines.count)

    for (index, line) in lines.enumerated() {
      let origin = lineOrigins[index]
      var ascent: CGFloat = 0
      var descent: CGFloat = 0
      var leading: CGFloat = 0
      CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
      let lineTop = layout.textOrigin.y + (layout.textSize.height - origin.y - ascent)
      let lineBottom = lineTop + ascent + descent + leading
      guard point.y >= lineTop - 4, point.y <= lineBottom + underlineVerticalGap + 8 else { continue }
      let idx = CTLineGetStringIndexForPosition(line, CGPoint(x: localX - origin.x, y: 0))
      guard idx != kCFNotFound else { continue }
      let clamped = max(0, min(idx, attributed.length - 1))
      return tokenIndexResolving(near: clamped, in: attributed)
    }
    return nil
  }

  private func drawInsetUnderlinesUsingViewRects(
    segments: [(range: NSRange, tokenIndices: Set<Int>)],
    pad: CGFloat,
    rect: CGRect,
    underlineHighlight: Set<Int>
  ) {
    let isScrub = tokenSelectionAppearance == .scrubUnderline

    for (charRange, tokenIndices) in segments {
      let isActive = !tokenIndices.isDisjoint(with: underlineHighlight)
      guard !isActive else { continue }
      guard charRange.length > 0 else { continue }
      for fragment in lineFragmentViewRectsForCharacterRange(charRange) {
        var br = fragment
        guard br.width > pad * 2 else { continue }
        br = br.insetBy(dx: pad, dy: 0)
        guard br.intersects(rect) else { continue }
        let y = br.maxY + underlineVerticalGap - tokenUnderlineWidth * 0.5
        let path = UIBezierPath()
        path.move(to: CGPoint(x: br.minX, y: y))
        path.addLine(to: CGPoint(x: br.maxX, y: y))
        path.lineWidth = max(1.5, tokenUnderlineWidth)
        path.lineCapStyle = .round
        tokenUnderlineColor.setStroke()
        path.stroke()
      }
    }

    if isScrub, !underlineHighlight.isEmpty {
      for (charRange, tokenIndices) in segments {
        let isActive = !tokenIndices.isDisjoint(with: underlineHighlight)
        guard isActive, charRange.length > 0 else { continue }
        for fragment in lineFragmentViewRectsForCharacterRange(charRange) {
          var br = fragment
          guard br.width > pad * 2 else { continue }
          br = br.insetBy(dx: pad, dy: 0)
          guard br.intersects(rect) else { continue }
          let y = br.maxY + underlineVerticalGap - scrubActiveUnderlineWidth * 0.5
          let path = UIBezierPath()
          path.move(to: CGPoint(x: br.minX, y: y))
          path.addLine(to: CGPoint(x: br.maxX, y: y))
          path.lineWidth = max(1.5, scrubActiveUnderlineWidth)
          path.lineCapStyle = .round
          scrubActiveUnderlineColor.setStroke()
          path.stroke()
        }
      }
    }
  }

  /// Grey underlines for non-selected segments; scrub mode adds a blue stroke on the active merged segment.
  private static func drawInsetUnderlines(
    segments: [(range: NSRange, tokenIndices: Set<Int>)],
    layoutManager lm: NSLayoutManager,
    textContainer c: NSTextContainer,
    textContainerInset: UIEdgeInsets,
    contentOffset: CGPoint,
    pad: CGFloat,
    rect: CGRect,
    underlineVerticalGap: CGFloat,
    tokenSelectionAppearance: LyricsTokenSelectionAppearance,
    selectedTokenIndices: Set<Int>,
    inactiveLineWidth: CGFloat,
    inactiveColor: UIColor,
    activeLineWidth: CGFloat,
    activeColor: UIColor
  ) {
    let isScrub = tokenSelectionAppearance == .scrubUnderline

    for (charRange, tokenIndices) in segments {
      let isActive = !tokenIndices.isDisjoint(with: selectedTokenIndices)
      guard !isActive else { continue }
      guard charRange.length > 0 else { continue }
      let gr = lm.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
      guard gr.length > 0 else { continue }
      lm.enumerateLineFragments(forGlyphRange: gr) { _, _, _, lineGlyphRange, _ in
        let sub = NSIntersectionRange(gr, lineGlyphRange)
        guard sub.length > 0 else { return }
        var br = lm.boundingRect(forGlyphRange: sub, in: c)
        guard !br.isNull, !br.isEmpty else { return }
        br.origin.x += textContainerInset.left
        br.origin.y += textContainerInset.top
        br.origin.x -= contentOffset.x
        br.origin.y -= contentOffset.y
        if br.width <= pad * 2 { return }
        br = br.insetBy(dx: pad, dy: 0)
        if !br.intersects(rect) { return }
        let y = br.maxY + underlineVerticalGap - inactiveLineWidth * 0.5
        let p = UIBezierPath()
        p.move(to: CGPoint(x: br.minX, y: y))
        p.addLine(to: CGPoint(x: br.maxX, y: y))
        p.lineWidth = inactiveLineWidth
        p.lineCapStyle = .round
        inactiveColor.setStroke()
        p.stroke()
      }
    }

    if isScrub, !selectedTokenIndices.isEmpty {
      for (charRange, tokenIndices) in segments {
        let isActive = !tokenIndices.isDisjoint(with: selectedTokenIndices)
        guard isActive, charRange.length > 0 else { continue }
        let gr = lm.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard gr.length > 0 else { continue }
        lm.enumerateLineFragments(forGlyphRange: gr) { _, _, _, lineGlyphRange, _ in
          let sub = NSIntersectionRange(gr, lineGlyphRange)
          guard sub.length > 0 else { return }
          var br = lm.boundingRect(forGlyphRange: sub, in: c)
          guard !br.isNull, !br.isEmpty else { return }
          br.origin.x += textContainerInset.left
          br.origin.y += textContainerInset.top
          br.origin.x -= contentOffset.x
          br.origin.y -= contentOffset.y
          if br.width <= pad * 2 { return }
          br = br.insetBy(dx: pad, dy: 0)
          if !br.intersects(rect) { return }
          let y = br.maxY + underlineVerticalGap - activeLineWidth * 0.5
          let p = UIBezierPath()
          p.move(to: CGPoint(x: br.minX, y: y))
          p.addLine(to: CGPoint(x: br.maxX, y: y))
          p.lineWidth = activeLineWidth
          p.lineCapStyle = .round
          activeColor.setStroke()
          p.stroke()
        }
      }
    }
  }

  private var lastLaidOutWidth: CGFloat = 0

  public override func layoutSubviews() {
    super.layoutSubviews()
    if showsFurigana {
      _ = rebuildFuriganaLayoutIfNeeded()
    }
    if abs(bounds.width - lastLaidOutWidth) > 0.5 {
      lastLaidOutWidth = bounds.width
      invalidateIntrinsicContentSize()
    }
    setNeedsDisplay()
  }

  @objc private func handleTap(_ g: UITapGestureRecognizer) {
    guard g.state == .ended else { return }
    let p = g.location(in: self)
    guard let pos = closestPosition(to: p) else { return }
    let idx = offset(from: beginningOfDocument, to: pos)
    guard let a = attributedText, a.length > 0, idx >= 0, idx < a.length else { return }
    guard let tIdx = tokenIndexResolving(near: idx, in: a) else { return }
    let surface = tokenLookupSurfaces.indices.contains(tIdx) ? tokenLookupSurfaces[tIdx] : tokens[tIdx].text
    let rect = mergedWordBoundsInTextView(forTokenIndex: tIdx) ?? .zero
    onWordTapped?(surface, rect, tIdx)
  }

  private func tokenIndexResolving(near location: Int, in a: NSAttributedString) -> Int? {
    for p in [location, location - 1, location + 1, location - 2, location + 2] {
      if p < 0 || p >= a.length { continue }
      if let n = a.attribute(.jmdictTokenIndex, at: p, effectiveRange: nil) as? NSNumber,
        tokens.indices.contains(n.intValue)
      {
        return n.intValue
      }
    }
    return nil
  }

  private static func fontForAttributes(from a: NSAttributedString) -> UIFont {
    a.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
      ?? UIFont.preferredFont(forTextStyle: .title1)
  }

  // MARK: - Build + single-token expand

  private static func buildAttributed(
    text: String,
    tokens: [JapaneseToken],
    font: UIFont,
    selectedIndices: Set<Int>?,
    selectionAppearance: LyricsTokenSelectionAppearance,
    showsFurigana: Bool = false
  ) -> NSAttributedString {
    let base: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: UIColor.label,
    ]
    let m = NSMutableAttributedString(string: text, attributes: base)
    let highlight = selectedIndices ?? []
    for (i, t) in tokens.enumerated() {
      let r = NSRange(t.range, in: text)
      guard r.location != NSNotFound, r.length > 0, NSMaxRange(r) <= m.length else { continue }
      m.addAttribute(.jmdictTokenIndex, value: i, range: r)
      if selectionAppearance == .definitionTip, highlight.contains(i), !showsFurigana {
        m.addAttribute(.foregroundColor, value: UIColor.white, range: r)
      }
    }
    if showsFurigana {
      JapaneseFuriganaBuilder.applyFurigana(to: m, text: text, font: font)
    }
    return m
  }

  private static func expandIfSingleFullSentenceToken(
    base: String,
    tokens: [JapaneseToken]
  ) -> [JapaneseToken] {
    guard
      tokens.count == 1,
      let t = tokens.first,
      t.text == base,
      t.text.count > 1
    else { return tokens }

    var out: [JapaneseToken] = []
    var i = base.startIndex
    while i < base.endIndex {
      let c = String(base[i])
      let j = base.index(after: i)
      let punc = c.unicodeScalars.allSatisfy { s in
        CharacterSet.punctuationCharacters.contains(s) || CharacterSet.whitespacesAndNewlines.contains(s)
      }
      if punc { i = j; continue }
      if !c.isEmpty { out.append(JapaneseToken(text: c, range: i..<j)) }
      i = j
    }
    return out.isEmpty ? tokens : out
  }
}
