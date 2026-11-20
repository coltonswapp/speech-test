//
//  LyricsTokenizationTextView.swift
//  InteractionKit
//
//  Inline tappable word regions for a single sentence. Selection + underlines
//  are custom-drawn; parent shows a definition tip.
//

import CoreText
import UIKit

private extension NSAttributedString.Key {
  static let scrubTokenIndex = NSAttributedString.Key("scrubTokenIndex")
}

// MARK: - Selection drawing

public enum LyricsTokenSelectionAppearance {
  /// Rounded blue fill behind the token; white text. Used with definition tips in lyrics.
  case definitionTip
  /// Thick blue underline on the active token; thin grey on others (scrub / explore experiments).
  case scrubUnderline
}

/// Top color and text for a multi-word selection. The pill eases from `fillColor`
/// to a lighter blue at the bottom. Single-token tips stay system blue.
@MainActor
public struct LyricsSpanHighlightStyle {
  public var fillColor: UIColor
  public var bandColor: UIColor
  public var textColor: UIColor
  /// Fraction of the pill height covered by `bandColor`, measured from the bottom.
  public var bandHeightFraction: CGFloat

  public init(
    fillColor: UIColor,
    bandColor: UIColor,
    textColor: UIColor,
    bandHeightFraction: CGFloat
  ) {
    self.fillColor = fillColor
    self.bandColor = bandColor
    self.textColor = textColor
    self.bandHeightFraction = bandHeightFraction
  }

  public static let standard = LyricsSpanHighlightStyle(
    fillColor: .systemBlue,
    bandColor: .systemYellow,
    textColor: .white,
    bandHeightFraction: 0.15
  )

  public static var current = standard {
    didSet {
      NotificationCenter.default.post(name: .lyricsSpanHighlightStyleDidChange, object: nil)
    }
  }
}

public extension Notification.Name {
  static let lyricsSpanHighlightStyleDidChange = Notification.Name("LyricsSpanHighlightStyleDidChange")
}

// MARK: - Inset underlines + rounded blue selection (drawn before glyphs)

public final class LyricsInsetUnderlineTextView: UITextView {
  /// `CGRect` is in the text view’s coordinate space; convert in the parent when anchoring a tip.
  /// The parent should call `setDefinitionSelectionHighlight` only after a definition tip is shown; blue fill follows that.
  public var onWordTapped: ((String, CGRect, Int) -> Void)?

  public var underlineHorizontalPadding: CGFloat = 2.5

  /// Space between the glyph bounds bottom and the underline (positive = line sits lower).
  /// Furigana lines ignore this and sit just under the baseline — the font descent
  /// would otherwise drop the stroke into the gap the next line's readings use.
  public var underlineVerticalGap: CGFloat = 2

  /// Layout points; slightly thick so underlines read clearly on iPhone.
  public var tokenUnderlineWidth: CGFloat = 3
  public var tokenUnderlineColor: UIColor = UIColor.systemGray3

  /// Stroke under the active token when `tokenSelectionAppearance == .scrubUnderline`.
  public var scrubActiveUnderlineWidth: CGFloat = 4
  public var scrubActiveUnderlineColor: UIColor = UIColor.systemBlue

  public var tokenSelectionAppearance: LyricsTokenSelectionAppearance = .definitionTip

  /// Extra points after each token that directly abuts the next one, for easier
  /// tapping. Applied as tracking on the token's last character; highlight, underline
  /// and selection rects are trimmed so they do not extend into the gap. Set before
  /// `configure`.
  public var tokenSpacing: CGFloat = 0

  /// Extra points between wrapped lines when furigana is off (furigana reserves
  /// its own room above each line). Highlight and underline rects stay one line
  /// tall. Set before `configure`.
  public var plainLineSpacing: CGFloat = 0

  public private(set) var selectedTokenIndex: Int?

  /// Exact token indices for a scrubbed span. When nil, the highlight follows
  /// `selectedTokenIndex` and any neighbors that share a lookup surface.
  private var explicitSelectionIndices: Set<Int>?

  private var activeSelectionIndices: Set<Int> {
    if let explicitSelectionIndices {
      return explicitSelectionIndices
    }
    if let selectedTokenIndex {
      return contiguousIndicesWithSameLookup(as: selectedTokenIndex)
    }
    return []
  }

  /// Horizontal: keep small so the rounded fill doesn’t extend far past glyph bounds into neighbors.
  private let selectionHPad: CGFloat = 0.5
  private let selectionVPad: CGFloat = 1
  private let selectionCornerRadius: CGFloat = 6
  private let selectionColor = UIColor.systemBlue
  /// Multi-word spans keep the blue pill and fade it to a lighter blue toward the bottom.
  private var selectionUsesSpanAccent = false

  /// Lowers the selection fill while audio plays so karaoke can read on top of it.
  public var dimsSelectionHighlight = false {
    didSet {
      guard dimsSelectionHighlight != oldValue else { return }
      if showsFurigana {
        setNeedsDisplay()
      } else {
        let indices = activeSelectionIndices
        applySelectionAttributed(selectedIndices: indices.isEmpty ? nil : indices)
      }
    }
  }

  private static let playbackSelectionAlpha: CGFloat = 0.32

  /// Playback karaoke wash. Independent of `selectedTokenIndex` / definition fill.
  private var karaokeRange: NSRange?
  private var karaokeFullHeight = false
  private var karaokeHighlightColor = UIColor.systemYellow.withAlphaComponent(0.45)
  /// Compact marker as a fraction of point size; sits on the baseline
  /// and overlaps the lower part of the glyphs (matches dialogue karaoke).
  private static let karaokeHighlightHeightFactor: CGFloat = 0.34
  private static let karaokeHighlightBelowBaselineFactor: CGFloat = 0.08
  private static let karaokeHighlightCornerRadius: CGFloat = 2

  private var tokens: [ScrubToken] = []
  /// Parallel to `tokens`: merged adjacent surfaces when the pair is an exact dictionary match.
  private var tokenLookupSurfaces: [String] = []
  private var applyRuby: ((NSMutableAttributedString, String, UIFont) -> Void)?
  private var fullText: String = ""
  private var showsFurigana = false
  private var accentSubstring: String?
  private var accentColor: UIColor = .systemBlue
  private var visibleAttributedText: NSAttributedString?

  private struct FuriganaTextLayout {
    let lines: [CTLine]
    /// Core Text coordinates (y up from the bottom of `textSize`), like `CTFrameGetLineOrigins`.
    let lineOrigins: [CGPoint]
    let textOrigin: CGPoint
    let textSize: CGSize
  }

  private var furiganaLayout: FuriganaTextLayout?

  /// Last line wrap, keyed by the visible text and width. Sizing (`sizeThatFits`,
  /// `intrinsicContentSize`) and layout each asked for the same wrap, so one layout
  /// pass ran Core Text up to three times per line; resizes and drags paid it per frame.
  private var wrapCache: (
    text: NSAttributedString,
    width: CGFloat,
    result: (lines: [CTLine], baselines: [CGFloat], height: CGFloat)
  )?

  private func wrappedFuriganaLinesCached(
    for visible: NSAttributedString,
    width: CGFloat
  ) -> (lines: [CTLine], baselines: [CGFloat], height: CGFloat) {
    if let wrapCache, wrapCache.text === visible, wrapCache.width == width {
      return wrapCache.result
    }
    let result = Self.wrappedFuriganaLines(for: visible, width: width)
    wrapCache = (visible, width, result)
    return result
  }

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
    // `draw(_:)` paints the text itself, so the default `.scaleToFill` stretched the
    // old bitmap to the new width on rotation (wider in landscape, squeezed in
    // portrait). Pin it unscaled at the top left and redraw on every bounds change.
    contentMode = .topLeft
    layer.needsDisplayOnBoundsChange = true
    textContainer.lineFragmentPadding = 0
    textContainer.widthTracksTextView = true
    textContainer.heightTracksTextView = false
    tap.addTarget(self, action: #selector(handleTap))
    addGestureRecognizer(tap)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(spanHighlightStyleDidChange),
      name: .lyricsSpanHighlightStyleDidChange,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  public var tokenCount: Int { tokens.count }

  @objc private func spanHighlightStyleDidChange() {
    if selectionUsesSpanAccent {
      applySelectionAttributed(selectedIndices: activeSelectionIndices)
    }
    setNeedsDisplay()
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
    return wrappedFuriganaLinesCached(for: visible, width: width).height
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

    let wrapped = wrappedFuriganaLinesCached(for: visible, width: textWidth)
    let flush = Self.flushFactor(for: visible)
    let origins = zip(wrapped.lines, wrapped.baselines).map { line, baseline in
      CGPoint(
        x: CGFloat(CTLineGetPenOffsetForFlush(line, flush, Double(textWidth))),
        y: wrapped.height - baseline
      )
    }
    let layout = FuriganaTextLayout(
      lines: wrapped.lines,
      lineOrigins: origins,
      textOrigin: CGPoint(x: textContainerInset.left, y: textContainerInset.top),
      textSize: CGSize(width: textWidth, height: wrapped.height)
    )
    furiganaLayout = layout
    return layout
  }

  /// Lays out base text (ruby stripped, so Core Text does not stretch 少々 to
  /// しょうしょう or slide ま off 待; readings are painted as an overlay).
  /// Lines only break between tokens, so 人口減少 and its reading move to the
  /// next line together. A token wider than the line falls back to Core Text's break.
  private static func wrappedFuriganaLines(
    for visible: NSAttributedString,
    width: CGFloat
  ) -> (lines: [CTLine], baselines: [CGFloat], height: CGFloat) {
    let measured = attributedStringByRemovingRuby(visible)
    let ranges = furiganaLineRanges(
      in: measured,
      width: width,
      keepsTogether: { keepsTogether(visible, at: $0) }
    )
    let framesetter = CTFramesetterCreateWithAttributedString(measured)
    var lines: [CTLine] = []
    var baselines: [CGFloat] = []
    var top: CGFloat = 0
    var bottom: CGFloat = 0
    let lineSpacing = (measured.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?
      .lineSpacing ?? 0
    for range in ranges {
      guard let line = singleLine(in: framesetter, range: range) else { continue }
      var ascent: CGFloat = 0
      var descent: CGFloat = 0
      var leading: CGFloat = 0
      CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
      let baseline = top + ascent
      lines.append(line)
      baselines.append(baseline)
      bottom = baseline + descent
      top = bottom + max(0, leading) + lineSpacing
    }
    return (lines, baselines, max(ceil(bottom), 1))
  }

  /// One line for `range`, laid out by a frame so paragraph metrics
  /// (minimum line height) match what `CTFrame` stacking produced.
  private static func singleLine(in framesetter: CTFramesetter, range: CFRange) -> CTLine? {
    let path = CGPath(rect: CGRect(x: 0, y: 0, width: 100_000, height: 100_000), transform: nil)
    let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
    let lines = CTFrameGetLines(frame)
    guard CFArrayGetCount(lines) > 0 else { return nil }
    return unsafeBitCast(CFArrayGetValueAtIndex(lines, 0), to: CTLine.self)
  }

  /// Core Text's own breaks (kinsoku included), pulled back to the start of
  /// a token Core Text would split.
  private static func furiganaLineRanges(
    in measured: NSAttributedString,
    width: CGFloat,
    keepsTogether: (Int) -> Bool
  ) -> [CFRange] {
    let typesetter = CTTypesetterCreateWithAttributedString(measured)
    var ranges: [CFRange] = []
    var start = 0
    while start < measured.length {
      var count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
      if count <= 0 {
        count = max(1, CTTypesetterSuggestClusterBreak(typesetter, start, Double(width)))
      }
      var end = start + count
      if end < measured.length, keepsTogether(end) {
        var candidate = end - 1
        while candidate > start {
          // Only take a token boundary Core Text also accepts, so 、 never starts a line.
          // Measure the whole piece, not the caret offset at `candidate`: the offset
          // leaves out part of the token-final `tokenSpacing` kern that Core Text
          // counts when breaking, so every multi-character piece came up short and
          // only a one-character line (私 / も) passed.
          if !keepsTogether(candidate) {
            let piece = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: candidate - start))
            let width = CTLineGetTypographicBounds(piece, nil, nil, nil)
            if CTTypesetterSuggestLineBreak(typesetter, start, width + 0.5) >= candidate - start { break }
          }
          candidate -= 1
        }
        if candidate > start { end = candidate }
      }
      ranges.append(CFRange(location: start, length: end - start))
      start = end
    }
    return ranges
  }

  /// True when `location` sits inside one token or one ruby group.
  private static func keepsTogether(_ visible: NSAttributedString, at location: Int) -> Bool {
    guard location > 0, location < visible.length else { return false }
    if let previous = visible.attribute(.scrubTokenIndex, at: location - 1, effectiveRange: nil) as? Int,
       let next = visible.attribute(.scrubTokenIndex, at: location, effectiveRange: nil) as? Int,
       previous == next {
      return true
    }
    let rubyKey = NSAttributedString.Key(kCTRubyAnnotationAttributeName as String)
    guard let previous = visible.attribute(rubyKey, at: location - 1, effectiveRange: nil),
          let next = visible.attribute(rubyKey, at: location, effectiveRange: nil)
    else { return false }
    return (previous as AnyObject) === (next as AnyObject)
  }

  private static func flushFactor(for attributed: NSAttributedString) -> CGFloat {
    let style = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    switch style?.alignment {
    case .center: return 0.5
    case .right: return 1
    default: return 0
    }
  }

  /// Visible string karaoke ranges should be mapped onto (ruby is attributes only).
  public var displayedString: String {
    visibleAttributedText?.string ?? attributedText?.string ?? fullText
  }

  /// Yellow (or host-tinted) playback marker behind a character range.
  /// Does not change `selectedTokenIndex`, callouts, or tap/pan selection.
  public func setKaraokeHighlight(
    range: NSRange?,
    fullHeight: Bool,
    highlightColor: UIColor
  ) {
    let length = (visibleAttributedText ?? attributedText)?.length ?? (fullText as NSString).length
    var clamped: NSRange?
    if let range,
       range.location >= 0,
       range.length > 0,
       NSMaxRange(range) <= length {
      clamped = range
    }
    let rangeChanged = !NSEqualRanges(
      karaokeRange ?? NSRange(location: NSNotFound, length: 0),
      clamped ?? NSRange(location: NSNotFound, length: 0)
    )
    let styleChanged = karaokeFullHeight != fullHeight
    let fillChanged = karaokeHighlightColor != highlightColor
    karaokeRange = clamped
    karaokeFullHeight = fullHeight
    karaokeHighlightColor = highlightColor
    if rangeChanged || styleChanged || fillChanged {
      setNeedsDisplay()
    }
  }

  /// Line fragments (text view coordinates, top to bottom) under the karaoke marker;
  /// empty when none is set. Hosts use it to keep a wrapped line in view.
  public func karaokeLineFragmentRectsInTextView() -> [CGRect] {
    guard let range = karaokeRange, range.length > 0 else { return [] }
    return lineFragmentViewRectsForCharacterRange(range)
  }

  /// Rounded blue fill + light text; only used while a definition tip is active (parent drives this).
  public func setDefinitionSelectionHighlight(tokenIndex: Int?) {
    selectionUsesSpanAccent = false
    explicitSelectionIndices = nil
    selectedTokenIndex = tokenIndex
    let selectedIndices = tokenIndex.map { contiguousIndicesWithSameLookup(as: $0) }
    applySelectionAttributed(selectedIndices: selectedIndices)
  }

  /// Highlights a contiguous token span exactly, without expanding to merged lookup groups.
  /// The pill stays the existing blue on top and eases to a lighter blue at the bottom.
  public func setDefinitionSelectionHighlight(tokenRange: ClosedRange<Int>?) {
    let filtered = tokenRange.map { range in
      Set(range.filter { tokens.indices.contains($0) })
    } ?? []
    selectionUsesSpanAccent = !filtered.isEmpty
    if filtered.isEmpty {
      explicitSelectionIndices = nil
      selectedTokenIndex = nil
      applySelectionAttributed(selectedIndices: nil)
    } else {
      explicitSelectionIndices = filtered
      selectedTokenIndex = filtered.min()
      applySelectionAttributed(selectedIndices: filtered)
    }
  }

  private func applySelectionAttributed(selectedIndices: Set<Int>?) {
    let font: UIFont
    if let a = attributedText, a.length > 0 {
      font = Self.fontForAttributes(from: a)
    } else {
      font = UIFont.preferredFont(forTextStyle: .title1)
    }
    let built = Self.buildAttributed(
      text: fullText,
      tokens: tokens,
      font: font,
      selectedIndices: selectedIndices,
      selectionAppearance: tokenSelectionAppearance,
      selectedTextColor: dimsSelectionHighlight
        ? .label
        : (selectionUsesSpanAccent
          ? LyricsSpanHighlightStyle.current.textColor
          : .white),
      showsFurigana: showsFurigana,
      tokenSpacing: tokenSpacing,
      lookupSurfaces: tokenLookupSurfaces,
      plainLineSpacing: plainLineSpacing,
      applyRuby: applyRuby
    )
    let styled = NSMutableAttributedString(attributedString: built)
    applyAccentHighlight(to: styled, in: fullText)
    applyVisibleAttributedText(styled)
    setNeedsDisplay()
  }

  /// - Parameter showsFurigana: When true, applies ruby via `applyRuby` and extra line height.
  /// - Parameter accentSubstring: Optional substring drawn in `accentColor` (e.g. a learner's fill-in choice).
  /// - Parameter preservesTokenBoundaries: When true, keep `tokens` 1:1 (skip full-sentence expand).
  public func configure(
    sentence: String,
    lyricFont: UIFont,
    tokens precomputedTokens: [ScrubToken],
    lookupSurfaces: [String]? = nil,
    showsFurigana: Bool = false,
    accentSubstring: String? = nil,
    accentColor: UIColor = .systemBlue,
    applyRuby: ((NSMutableAttributedString, String, UIFont) -> Void)? = nil,
    preservesTokenBoundaries: Bool = false
  ) {
    self.applyRuby = applyRuby
    applyTokenConfiguration(
      sentence: sentence,
      lyricFont: lyricFont,
      tokens: precomputedTokens,
      lookupSurfaces: lookupSurfaces,
      showsFurigana: showsFurigana,
      accentSubstring: accentSubstring,
      accentColor: accentColor,
      preservesTokenBoundaries: preservesTokenBoundaries
    )
  }

  private func applyTokenConfiguration(
    sentence: String,
    lyricFont: UIFont,
    tokens rawTokens: [ScrubToken],
    lookupSurfaces: [String]?,
    showsFurigana: Bool,
    accentSubstring: String?,
    accentColor: UIColor,
    preservesTokenBoundaries: Bool = false
  ) {
    fullText = sentence
    self.showsFurigana = showsFurigana
    tokens = preservesTokenBoundaries
      ? rawTokens
      : Self.expandIfSingleFullSentenceToken(
        base: sentence,
        tokens: rawTokens
      )
    if preservesTokenBoundaries {
      tokenLookupSurfaces = tokens.map(\.text)
    } else if let lookupSurfaces, lookupSurfaces.count == tokens.count {
      tokenLookupSurfaces = lookupSurfaces
    } else {
      tokenLookupSurfaces = tokens.map(\.text)
    }
    selectedTokenIndex = nil
    explicitSelectionIndices = nil
    selectionUsesSpanAccent = false
    karaokeRange = nil
    let edge = textContainerEdgeOutset
    let rubyTop = showsFurigana ? Self.rubyOverlayTopInset(for: lyricFont) : 0
    let rubySide = showsFurigana ? Self.rubyOverlaySideInset(for: lyricFont) : 0
    textContainerInset = UIEdgeInsets(
      top: edge + rubyTop,
      left: edge + rubySide,
      bottom: bottomTextContainerOutset,
      right: edge + rubySide
    )
    self.accentSubstring = accentSubstring
    self.accentColor = accentColor
    let built = Self.buildAttributed(
      text: sentence,
      tokens: tokens,
      font: lyricFont,
      selectedIndices: nil,
      selectionAppearance: tokenSelectionAppearance,
      showsFurigana: showsFurigana,
      tokenSpacing: tokenSpacing,
      lookupSurfaces: tokenLookupSurfaces,
      plainLineSpacing: plainLineSpacing,
      applyRuby: applyRuby
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
    wrapCache = nil
    attributedText = showsFurigana ? Self.layoutOnlyAttributedText(from: visible) : visible
  }

  private static func layoutOnlyAttributedText(from visible: NSAttributedString) -> NSAttributedString {
    let m = NSMutableAttributedString(attributedString: attributedStringByRemovingRuby(visible))
    guard m.length > 0 else { return m }
    m.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: 0, length: m.length))
    return m
  }

  /// How far past a line's first or last glyph a tap still counts as on that line.
  private static let tapHorizontalSlop: CGFloat = 8

  /// Maps a point in this view’s bounds to a token index (same logic as tap).
  /// By default a point beside a line snaps to its nearest token, which a drag wants.
  /// With `requiringHit`, a point left or right of a line's text returns nil, so a
  /// tap in the empty space past a short line is not read as its last word.
  public func tokenIndex(at pointInView: CGPoint, requiringHit: Bool = false) -> Int? {
    if showsFurigana, let layout = furiganaLayout ?? rebuildFuriganaLayoutIfNeeded(),
      let visible = visibleAttributedText {
      return tokenIndexFromCoreText(at: pointInView, layout: layout, in: visible, requiringHit: requiringHit)
    }
    guard let pos = closestPosition(to: pointInView) else { return nil }
    let idx = offset(from: beginningOfDocument, to: pos)
    guard let a = attributedText, a.length > 0, idx >= 0, idx < a.length else { return nil }
    if requiringHit, !textKitLineContainsHorizontally(pointInView, nearCharacter: idx) { return nil }
    return tokenIndexResolving(near: idx, in: a)
  }

  /// Whether `point` falls within the used width (plus slop) of the line holding `character`.
  private func textKitLineContainsHorizontally(_ point: CGPoint, nearCharacter character: Int) -> Bool {
    let lm = layoutManager
    let glyphCount = lm.numberOfGlyphs
    guard glyphCount > 0 else { return false }
    let glyph = min(lm.glyphIndexForCharacter(at: character), glyphCount - 1)
    var lineRange = NSRange()
    _ = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &lineRange)
    var used = lm.boundingRect(forGlyphRange: lineRange, in: textContainer)
    guard !used.isNull, !used.isEmpty else { return false }
    used.origin.x += textContainerInset.left - contentOffset.x
    let slop = Self.tapHorizontalSlop
    return point.x >= used.minX - slop && point.x <= used.maxX + slop
  }

  public func tokenSurface(at index: Int) -> String? {
    guard tokens.indices.contains(index), tokenLookupSurfaces.indices.contains(index) else { return nil }
    return tokenLookupSurfaces[index]
  }

  /// Sentence text covered by a contiguous token range, including characters between those tokens.
  public func surface(covering tokenRange: ClosedRange<Int>) -> String? {
    let indices = tokenRange.filter { tokens.indices.contains($0) }
    guard let firstIndex = indices.min(), let lastIndex = indices.max() else { return nil }
    let start = tokens[firstIndex].range.lowerBound
    let end = tokens[lastIndex].range.upperBound
    guard start < end, end <= fullText.endIndex else { return nil }
    let trimmed = Self.strippingClauseSeparators(
      String(fullText[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    )
    return trimmed.isEmpty ? nil : trimmed
  }

  /// Display text of each token in the range, in order.
  public func tokenTexts(in tokenRange: ClosedRange<Int>) -> [String] {
    tokenRange.compactMap { index in
      guard tokens.indices.contains(index) else { return nil }
      let text = tokens[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
      return text.isEmpty ? nil : text
    }
  }

  /// Token span that shares this index's lookup surface (お店 from お or 店).
  public func lookupTokenRange(for index: Int) -> ClosedRange<Int>? {
    guard tokens.indices.contains(index) else { return nil }
    let group = contiguousIndicesWithSameLookup(as: index)
    guard let lo = group.min(), let hi = group.max() else { return nil }
    return lo...hi
  }

  /// Extends a span so a merged lookup at either end stays whole (お + 店 → お店).
  public func tokenRangeExpandingLookupGroups(_ tokenRange: ClosedRange<Int>) -> ClosedRange<Int> {
    guard !tokens.isEmpty else { return tokenRange }
    let last = tokens.index(before: tokens.endIndex)
    let lower = min(max(tokenRange.lowerBound, tokens.startIndex), last)
    let upper = min(max(tokenRange.upperBound, tokens.startIndex), last)
    let lo = contiguousIndicesWithSameLookup(as: lower).min() ?? lower
    let hi = contiguousIndicesWithSameLookup(as: upper).max() ?? upper
    return min(lo, hi)...max(lo, hi)
  }

  /// Keeps a drag inside the sentence part that contains `anchor`. Periods, quotes,
  /// and other separators are walls; the returned index never crosses one.
  /// Commas are not walls — phrases like それなのに、もう often only read as a pair.
  public func tokenIndexLimitedToClause(anchor: Int, proposed: Int) -> Int {
    guard tokens.indices.contains(anchor) else { return proposed }
    guard tokens.indices.contains(proposed) else { return anchor }
    let anchorKind = clauseKind(of: tokens[anchor].text)
    if anchorKind == .wall { return anchor }
    if proposed == anchor { return anchor }

    let step = proposed > anchor ? 1 : -1
    if step > 0, anchorKind == .trailingBreak { return anchor }
    if step < 0, anchorKind == .leadingBreak { return anchor }

    var cursor = anchor
    while cursor != proposed {
      let next = cursor + step
      if gapContainsClauseSeparator(from: cursor, to: next) { return cursor }
      switch clauseKind(of: tokens[next].text) {
      case .wall:
        return cursor
      case .trailingBreak:
        return step > 0 ? next : cursor
      case .leadingBreak:
        return step < 0 ? next : cursor
      case .content:
        cursor = next
      }
    }
    return cursor
  }

  private enum ClauseTokenKind {
    case content
    case wall
    case trailingBreak
    case leadingBreak
  }

  /// Clause breaks. Middle dots stay selectable so names like ジョン・スミス can be one span.
  private static let clauseSeparators = CharacterSet(charactersIn: "。．.!?;:！？；：…‥\n\r「」『』【】〈〉《》（）()[]{}")

  /// Trimmed from span ends; commas can sit inside a span but never start or end one.
  private static let spanEdgeSeparators = clauseSeparators.union(CharacterSet(charactersIn: "、，,､"))

  private func clauseKind(of text: String) -> ClauseTokenKind {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .content }
    let characters = Array(trimmed)
    func isSeparator(_ character: Character) -> Bool {
      character.unicodeScalars.allSatisfy { Self.clauseSeparators.contains($0) }
    }
    if characters.allSatisfy(isSeparator) { return .wall }
    let leading = isSeparator(characters[0])
    let trailing = isSeparator(characters[characters.count - 1])
    let middle = characters.dropFirst().dropLast().contains(where: isSeparator)
    if middle || (leading && trailing) { return .wall }
    if trailing { return .trailingBreak }
    if leading { return .leadingBreak }
    return .content
  }

  private func gapContainsClauseSeparator(from: Int, to: Int) -> Bool {
    let left = min(from, to)
    let right = max(from, to)
    let start = tokens[left].range.upperBound
    let end = tokens[right].range.lowerBound
    guard start < end, end <= fullText.endIndex else { return false }
    return fullText[start..<end].unicodeScalars.contains { Self.clauseSeparators.contains($0) }
  }

  private static func strippingClauseSeparators(_ text: String) -> String {
    var scalars = Array(text.unicodeScalars)
    while let first = scalars.first,
      spanEdgeSeparators.contains(first) || CharacterSet.whitespacesAndNewlines.contains(first)
    {
      scalars.removeFirst()
    }
    while let last = scalars.last,
      spanEdgeSeparators.contains(last) || CharacterSet.whitespacesAndNewlines.contains(last)
    {
      scalars.removeLast()
    }
    return String(String.UnicodeScalarView(scalars))
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
  /// `tokenSpacing` tracking on the character before `end` (exclusive), or 0.
  private func trailingTokenKern(endingAt end: Int) -> CGFloat {
    guard tokenSpacing > 0, end > 0 else { return 0 }
    let source = visibleAttributedText ?? attributedText
    guard let source, end <= source.length else { return 0 }
    let value = source.attribute(.tracking, at: end - 1, effectiveRange: nil)
    return (value as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
  }

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
      let lastChar = lm.characterIndexForGlyph(at: NSMaxRange(sub) - 1)
      br.size.width = max(1, br.width - self.trailingTokenKern(endingAt: lastChar + 1))
      // Line fragments include `plainLineSpacing` below the glyphs; keep marks one line tall.
      if self.plainLineSpacing > 0, let text = self.attributedText, text.length > 0 {
        br.size.height = min(br.height, Self.fontForAttributes(from: text).lineHeight)
      }
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
    let selectionIndices = activeSelectionIndices
    // Character runs under a full-strength selection pill; the karaoke wash skips them.
    var pillRuns: [NSRange] = []
    if tokenSelectionAppearance == .definitionTip, !selectionIndices.isEmpty {
      let highlight = selectionIndices
      let source = visibleAttributedText ?? full
      // One pill per run of touching selected tokens: 中華 + 料理屋 share a lookup, and
      // drawing each token on its own left a `tokenSpacing` hole in the middle.
      var selectedRuns: [NSRange] = []
      source.enumerateAttribute(
        .scrubTokenIndex, in: NSRange(location: 0, length: source.length), options: []
      ) { value, charRange, _ in
        guard let value else { return }
        let n: Int = (value as? NSNumber)?.intValue ?? (value as? Int) ?? -1
        guard highlight.contains(n), charRange.length > 0 else { return }
        if let last = selectedRuns.last, NSMaxRange(last) == charRange.location {
          selectedRuns[selectedRuns.count - 1] = NSUnionRange(last, charRange)
        } else {
          selectedRuns.append(charRange)
        }
      }
      if !dimsSelectionHighlight { pillRuns = selectedRuns }
      for charRange in selectedRuns {
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
          // Single-token and multi-word selections share one corner radius.
          let r = min(selectionCornerRadius, b.height * 0.45)
          let p = UIBezierPath(roundedRect: b, cornerRadius: r)
          if selectionUsesSpanAccent {
            drawSpanVerticalGradient(
              in: p, bounds: b, topColor: LyricsSpanHighlightStyle.current.fillColor)
          } else {
            selectionFillColor(selectionColor).setFill()
            p.fill()
          }
        }
      }
    }
    // After the selection fill so a dimmed pill does not cover the playback marker,
    // and before glyphs so the wash stays behind the characters. A full-strength
    // pill wins: the wash would clash with the blue, so it's left out there.
    drawKaraokeHighlight(in: rect, excluding: pillRuns)
    if showsFurigana {
      _ = rebuildFuriganaLayoutIfNeeded()
      drawFuriganaCoreText()
      if tokenSelectionAppearance == .definitionTip, !selectionIndices.isEmpty, !dimsSelectionHighlight {
        drawFuriganaSelectionBaseTextOverlay(highlight: selectionIndices)
      }
    } else {
      super.draw(rect)
    }
    let pad = underlineHorizontalPadding
    let underlineHighlight = selectionIndices
    let underlineSegments = mergedUnderlineSegments()
    if showsFurigana {
      drawInsetUnderlinesUsingViewRects(
        segments: underlineSegments,
        pad: pad,
        rect: rect,
        underlineHighlight: underlineHighlight
      )
    } else {
      drawPlainInsetUnderlines(
        segments: underlineSegments,
        pad: pad,
        rect: rect,
        selectedTokenIndices: underlineHighlight
      )
    }
  }

  /// Existing blue across the top of a multi-word pill, easing to a lighter blue at the bottom.
  private func drawSpanVerticalGradient(
    in pill: UIBezierPath,
    bounds: CGRect,
    topColor: UIColor
  ) {
    guard let ctx = UIGraphicsGetCurrentContext() else { return }
    let top = deviceRGBColor(selectionFillColor(topColor))
    let bottom = deviceRGBColor(selectionFillColor(lighterBlue(from: topColor)))
    let locations: [CGFloat] = [0, 0.42, 1]
    guard let gradient = CGGradient(
      colorsSpace: CGColorSpaceCreateDeviceRGB(),
      colors: [top, top, bottom] as CFArray,
      locations: locations
    ) else { return }
    ctx.saveGState()
    pill.addClip()
    ctx.drawLinearGradient(
      gradient,
      start: CGPoint(x: bounds.midX, y: bounds.minY),
      end: CGPoint(x: bounds.midX, y: bounds.maxY),
      options: []
    )
    ctx.restoreGState()
  }

  /// `UIColor.cgColor` is often Display P3. The gradient is device RGB, so convert first.
  private func deviceRGBColor(_ color: UIColor) -> CGColor {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    let resolved = color.resolvedColor(with: traitCollection)
    guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
      return resolved.cgColor
    }
    return CGColor(
      colorSpace: CGColorSpaceCreateDeviceRGB(),
      components: [red, green, blue, alpha]
    ) ?? resolved.cgColor
  }

  private func selectionFillColor(_ color: UIColor) -> UIColor {
    let resolved = color.resolvedColor(with: traitCollection)
    guard dimsSelectionHighlight else { return resolved }
    return resolved.withAlphaComponent(Self.playbackSelectionAlpha)
  }

  /// Same hue as the selection blue, mixed toward white so the bottom of the pill reads lighter.
  private func lighterBlue(from color: UIColor) -> UIColor {
    let resolved = color.resolvedColor(with: traitCollection)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return resolved }
    let mix: CGFloat = 0.46
    return UIColor(
      red: red + (1 - red) * mix,
      green: green + (1 - green) * mix,
      blue: blue + (1 - blue) * mix,
      alpha: alpha
    )
  }

  public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
      setNeedsDisplay()
    }
  }

  /// `range` minus every run in `excluded`, as the ranges left over, in order.
  private static func subtracting(_ excluded: [NSRange], from range: NSRange) -> [NSRange] {
    var pieces = [range]
    for cut in excluded {
      pieces = pieces.flatMap { piece -> [NSRange] in
        guard let overlap = piece.intersection(cut), overlap.length > 0 else { return [piece] }
        var rest: [NSRange] = []
        if overlap.location > piece.location {
          rest.append(NSRange(location: piece.location, length: overlap.location - piece.location))
        }
        if NSMaxRange(overlap) < NSMaxRange(piece) {
          rest.append(NSRange(location: NSMaxRange(overlap), length: NSMaxRange(piece) - NSMaxRange(overlap)))
        }
        return rest
      }
    }
    return pieces
  }

  private func drawKaraokeHighlight(in rect: CGRect, excluding excluded: [NSRange]) {
    guard let range = karaokeRange, range.length > 0 else { return }
    let visible = Self.subtracting(excluded, from: range)
    // Furigana path: ink-centered like the underlines, so the wash sits on the glyph.
    let fragments = visible.flatMap { piece in
      showsFurigana
        ? inkCenteredFuriganaFragments(for: piece, baseTextOnly: true).map(\.rect)
        : lineFragmentViewRectsForCharacterRange(piece)
    }
    guard !fragments.isEmpty else { return }

    let source: NSAttributedString? = visibleAttributedText ?? attributedText
    let font: UIFont
    if let source, range.location < source.length,
      let tokenFont = source.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
    {
      font = tokenFont
    } else if let source {
      font = Self.fontForAttributes(from: source)
    } else {
      font = UIFont.preferredFont(forTextStyle: .title1)
    }

    karaokeHighlightColor.setFill()
    for fragment in fragments {
      guard fragment.width > 0.5, fragment.height > 0.5, fragment.intersects(rect) else { continue }
      let highlight: CGRect
      if karaokeFullHeight {
        highlight = fragment
      } else {
        let baselineY = fragment.minY + font.ascender
        let height = max(5, font.pointSize * Self.karaokeHighlightHeightFactor)
        let belowBaseline = font.pointSize * Self.karaokeHighlightBelowBaselineFactor
        highlight = CGRect(
          x: fragment.minX,
          y: baselineY - height + belowBaseline,
          width: fragment.width,
          height: height
        )
      }
      let radius = min(
        Self.karaokeHighlightCornerRadius,
        min(highlight.width, highlight.height) / 2
      )
      UIBezierPath(roundedRect: highlight, cornerRadius: radius).fill()
    }
  }

  private func drawFuriganaCoreText() {
    guard let layout = furiganaLayout, let ctx = UIGraphicsGetCurrentContext() else { return }
    ctx.saveGState()
    ctx.translateBy(x: layout.textOrigin.x, y: layout.textOrigin.y + layout.textSize.height)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textMatrix = .identity
    for (line, origin) in zip(layout.lines, layout.lineOrigins) {
      ctx.textPosition = origin
      CTLineDraw(line, ctx)
    }
    ctx.restoreGState()
    drawFuriganaReadings(layout: layout)
  }

  /// One reading to paint: its base glyph span and its own size.
  private struct PlacedReading {
    let reading: String
    let attributes: [NSAttributedString.Key: Any]
    let baseMinX: CGFloat
    let baseMaxX: CGFloat
    let size: CGSize
    let y: CGFloat
    var x: CGFloat
  }

  /// Minimum space between two readings that would otherwise touch.
  private static let rubyCollisionGap: CGFloat = 1

  /// Centers each reading on its base glyphs. Core Text ruby is not used for
  /// drawing — it widens kanji and leaves holes between tokens. Readings wider
  /// than their kanji (しゅうかん over 週間, next to まえ over 前) would overlap,
  /// so colliding neighbors on a line are set side by side and the group is
  /// centered over their combined kanji.
  private func drawFuriganaReadings(layout: FuriganaTextLayout) {
    var byLine: [Int: [PlacedReading]] = [:]
    collectFuriganaReadings(layout: layout) { lineIndex, placed in
      byLine[lineIndex, default: []].append(placed)
    }
    for (_, readings) in byLine {
      for placed in Self.resolvingRubyCollisions(readings) {
        (placed.reading as NSString).draw(
          with: CGRect(origin: CGPoint(x: placed.x, y: placed.y), size: placed.size),
          options: .usesLineFragmentOrigin,
          attributes: placed.attributes,
          context: nil
        )
      }
    }
  }

  /// Groups readings that would overlap and lays each group out edge to edge,
  /// centered on the span from its first kanji to its last.
  private static func resolvingRubyCollisions(_ readings: [PlacedReading]) -> [PlacedReading] {
    let sorted = readings.sorted { $0.baseMinX < $1.baseMinX }
    var groups: [[PlacedReading]] = []
    var groupMaxX = -CGFloat.greatestFiniteMagnitude
    for item in sorted {
      if !groups.isEmpty, item.x < groupMaxX + rubyCollisionGap {
        groups[groups.count - 1].append(item)
        groupMaxX = layOut(&groups[groups.count - 1])
        // Re-centering can push the group's left edge into the one before it.
        while groups.count > 1,
              let start = groups[groups.count - 1].first?.x,
              let previous = groups[groups.count - 2].last,
              start < previous.x + previous.size.width + rubyCollisionGap {
          let merged = groups.removeLast()
          groups[groups.count - 1].append(contentsOf: merged)
          groupMaxX = layOut(&groups[groups.count - 1])
        }
      } else {
        groups.append([item])
        groupMaxX = item.x + item.size.width
      }
    }
    return groups.flatMap { $0 }
  }

  /// Places `group` side by side, centered on its kanji. Returns its right edge.
  @discardableResult
  private static func layOut(_ group: inout [PlacedReading]) -> CGFloat {
    guard let first = group.first, let last = group.last else { return 0 }
    guard group.count > 1 else { return first.x + first.size.width }
    let total = group.reduce(0) { $0 + $1.size.width }
      + rubyCollisionGap * CGFloat(group.count - 1)
    var x = (first.baseMinX + last.baseMaxX) / 2 - total / 2
    for index in group.indices {
      group[index].x = x
      x += group[index].size.width + rubyCollisionGap
    }
    return x - rubyCollisionGap
  }

  private func collectFuriganaReadings(
    layout: FuriganaTextLayout,
    _ add: (Int, PlacedReading) -> Void
  ) {
    guard let visible = visibleAttributedText, visible.length > 0 else { return }
    let rubyKey = NSAttributedString.Key(kCTRubyAnnotationAttributeName as String)
    let lines = layout.lines
    guard !lines.isEmpty else { return }
    let lineOrigins = layout.lineOrigins

    visible.enumerateAttribute(rubyKey, in: NSRange(location: 0, length: visible.length)) { value, range, _ in
      guard let value,
            let reading = Self.reading(fromRubyAnnotation: value),
            !reading.isEmpty,
            range.length > 0
      else { return }

      for (index, line) in lines.enumerated() {
        let lineRange = CTLineGetStringRange(line)
        let lineNSRange = NSRange(location: lineRange.location, length: lineRange.length)
        let sub = NSIntersectionRange(range, lineNSRange)
        guard sub.length > 0 else { continue }

        // Glyph edges, not carets: a caret sits mid-way through the `tokenSpacing`
        // gap, which pulled readings left of their kanji.
        guard let extent = self.glyphExtent(of: sub, in: line) else { continue }
        let startX = extent.minX
        let endX = extent.maxX
        let origin = lineOrigins[index]
        let baseFont = visible.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
          ?? Self.fontForAttributes(from: visible)
        let factor = Self.sizeFactor(fromRubyAnnotation: value)
        let rubyFont = UIFont.systemFont(
          ofSize: baseFont.pointSize * (factor > 0 ? factor : Self.rubySizeFactor),
          weight: .regular
        )
        let rubyAttrs: [NSAttributedString.Key: Any] = [
          .font: rubyFont,
          .foregroundColor: Self.rubyTextColor,
        ]
        let rubySize = (reading as NSString).size(withAttributes: rubyAttrs)
        let baseMinX = layout.textOrigin.x + origin.x + startX
        let baseMaxX = layout.textOrigin.x + origin.x + endX
        let glyphTop = layout.textOrigin.y + (layout.textSize.height - origin.y - baseFont.ascender)
        add(index, PlacedReading(
          reading: reading,
          attributes: rubyAttrs,
          baseMinX: baseMinX,
          baseMaxX: baseMaxX,
          size: rubySize,
          y: glyphTop - rubySize.height + 1,
          x: (baseMinX + baseMaxX) / 2 - rubySize.width / 2
        ))
        break
      }
    }
  }

  /// White base glyphs on the blue selection pill; furigana stays from the first pass only.
  private func drawFuriganaSelectionBaseTextOverlay(highlight: Set<Int>) {
    guard
      !highlight.isEmpty,
      let visible = visibleAttributedText,
      let layout = furiganaLayout,
      let ctx = UIGraphicsGetCurrentContext()
    else { return }

    let overlay = Self.selectionOverlayAttributedString(
      from: visible,
      highlight: highlight,
      textColor: selectionUsesSpanAccent ? LyricsSpanHighlightStyle.current.textColor : .white
    )
    // Same line ranges as the base layout so the overlay stays on the same glyphs.
    let framesetter = CTFramesetterCreateWithAttributedString(overlay)

    ctx.saveGState()
    ctx.translateBy(x: layout.textOrigin.x, y: layout.textOrigin.y + layout.textSize.height)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textMatrix = .identity

    for (line, origin) in zip(layout.lines, layout.lineOrigins) {
      let lineRange = CTLineGetStringRange(line)
      guard lineRange.length > 0 else { continue }
      let nsRange = NSRange(location: lineRange.location, length: lineRange.length)
      guard Self.lineIntersectsHighlight(in: visible, range: nsRange, highlight: highlight),
            let overlayLine = Self.singleLine(in: framesetter, range: lineRange)
      else { continue }
      ctx.textPosition = origin
      CTLineDraw(overlayLine, ctx)
    }

    ctx.restoreGState()
  }

  /// White base glyphs on the selection pill. Layout matches the ruby-stripped
  /// Core Text frame so the overlay stays on the same glyphs.
  private static func selectionOverlayAttributedString(
    from visible: NSAttributedString,
    highlight: Set<Int>,
    textColor: UIColor
  ) -> NSAttributedString {
    let overlay = NSMutableAttributedString(attributedString: attributedStringByRemovingRuby(visible))
    let fullRange = NSRange(location: 0, length: overlay.length)
    overlay.addAttribute(.foregroundColor, value: UIColor.clear, range: fullRange)
    overlay.enumerateAttribute(.scrubTokenIndex, in: fullRange, options: []) { value, charRange, _ in
      guard let value, charRange.length > 0 else { return }
      let n: Int = (value as? NSNumber)?.intValue ?? (value as? Int) ?? -1
      guard highlight.contains(n) else { return }
      overlay.addAttribute(.foregroundColor, value: textColor, range: charRange)
    }
    return overlay
  }

  private static func lineIntersectsHighlight(
    in visible: NSAttributedString,
    range: NSRange,
    highlight: Set<Int>
  ) -> Bool {
    var intersects = false
    visible.enumerateAttribute(.scrubTokenIndex, in: range, options: []) { value, _, stop in
      guard let value else { return }
      let n: Int = (value as? NSNumber)?.intValue ?? (value as? Int) ?? -1
      guard highlight.contains(n) else { return }
      intersects = true
      stop.pointee = true
    }
    return intersects
  }

  private static let rubySizeFactor: CGFloat = 0.45
  private static let rubyTextColor = UIColor.secondaryLabel

  private static func rubyOverlayTopInset(for font: UIFont) -> CGFloat {
    ceil(font.pointSize * rubySizeFactor) + 2
  }

  private static func rubyOverlaySideInset(for font: UIFont) -> CGFloat {
    ceil(font.pointSize * rubySizeFactor * 0.85)
  }

  private static func attributedStringByRemovingRuby(_ attributed: NSAttributedString) -> NSAttributedString {
    let mutable = NSMutableAttributedString(attributedString: attributed)
    let rubyKey = NSAttributedString.Key(kCTRubyAnnotationAttributeName as String)
    mutable.removeAttribute(rubyKey, range: NSRange(location: 0, length: mutable.length))
    return mutable
  }

  private static func reading(fromRubyAnnotation value: Any) -> String? {
    let annotation = (value as AnyObject) as! CTRubyAnnotation
    return CTRubyAnnotationGetTextForPosition(annotation, .before) as String?
  }

  private static func sizeFactor(fromRubyAnnotation value: Any) -> CGFloat {
    let annotation = (value as AnyObject) as! CTRubyAnnotation
    return CTRubyAnnotationGetSizeFactor(annotation)
  }

  /// Left edge of the first glyph and right edge of the last glyph of `range` on `line`,
  /// in line coordinates, without the token-final `tokenSpacing` kern. Read from glyph
  /// positions, not caret offsets: Core Text puts the caret halfway through a kerned gap,
  /// so caret-based marks started kern/2 before a token's first kanji and, after trimming
  /// the full kern, stopped kern/2 short of its last one.
  private func glyphExtent(of range: NSRange, in line: CTLine) -> (minX: CGFloat, maxX: CGFloat)? {
    var minX = CGFloat.greatestFiniteMagnitude
    var maxX = -CGFloat.greatestFiniteMagnitude
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
      let count = CTRunGetGlyphCount(run)
      guard count > 0 else { continue }
      var indices = [CFIndex](repeating: 0, count: count)
      var positions = [CGPoint](repeating: .zero, count: count)
      var advances = [CGSize](repeating: .zero, count: count)
      CTRunGetStringIndices(run, CFRange(), &indices)
      CTRunGetPositions(run, CFRange(), &positions)
      CTRunGetAdvances(run, CFRange(), &advances)
      for i in 0..<count where NSLocationInRange(indices[i], range) {
        minX = min(minX, positions[i].x)
        maxX = max(maxX, positions[i].x + advances[i].width - trailingTokenKern(endingAt: indices[i] + 1))
      }
    }
    guard minX.isFinite, maxX > minX else { return nil }
    return (minX, maxX)
  }

  private func coreTextLineFragmentViewRects(
    forCharacterRange range: NSRange,
    layout: FuriganaTextLayout,
    baseTextOnly: Bool = false
  ) -> [CGRect] {
    coreTextLineFragments(
      forCharacterRange: range,
      layout: layout,
      baseTextOnly: baseTextOnly
    ).map(\.rect)
  }

  /// Glyph box plus the view-space baseline. The box bottom includes font descent,
  /// which is mostly empty under kana; underlines should key off `baselineY`.
  private func coreTextLineFragments(
    forCharacterRange range: NSRange,
    layout: FuriganaTextLayout,
    baseTextOnly: Bool = false
  ) -> [(rect: CGRect, baselineY: CGFloat)] {
    let lines = layout.lines
    guard !lines.isEmpty else { return [] }
    let lineOrigins = layout.lineOrigins
    let baseFont = baseTextOnly ? Self.fontForAttributes(from: visibleAttributedText ?? NSAttributedString()) : nil
    var out: [(rect: CGRect, baselineY: CGFloat)] = []
    for (index, line) in lines.enumerated() {
      let lineRange = CTLineGetStringRange(line)
      let lineNSRange = NSRange(location: lineRange.location, length: lineRange.length)
      let sub = NSIntersectionRange(range, lineNSRange)
      guard sub.length > 0 else { continue }
      guard let extent = glyphExtent(of: sub, in: line) else { continue }
      let (minX, maxX) = (extent.minX, extent.maxX)
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
      let width = max(1, maxX - minX)
      let baselineY = layout.textOrigin.y + (layout.textSize.height - origin.y)
      let y = baselineY - glyphAscent
      out.append((
        CGRect(
          x: layout.textOrigin.x + origin.x + minX,
          y: y,
          width: width,
          height: glyphAscent + glyphDescent
        ),
        baselineY
      ))
    }
    return out
  }

  private func tokenIndexFromCoreText(
    at point: CGPoint,
    layout: FuriganaTextLayout,
    in attributed: NSAttributedString,
    requiringHit: Bool = false
  ) -> Int? {
    let localX = point.x - layout.textOrigin.x
    let localY = point.y - layout.textOrigin.y
    let slop = requiringHit ? Self.tapHorizontalSlop : 0
    guard localX >= -slop, localY >= 0 else { return nil }

    let lines = layout.lines
    guard !lines.isEmpty else { return nil }
    let lineOrigins = layout.lineOrigins

    for (index, line) in lines.enumerated() {
      let origin = lineOrigins[index]
      var ascent: CGFloat = 0
      var descent: CGFloat = 0
      var leading: CGFloat = 0
      CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
      let lineTop = layout.textOrigin.y + (layout.textSize.height - origin.y - ascent)
      let lineBottom = lineTop + ascent + descent + leading
      guard point.y >= lineTop - 4, point.y <= lineBottom + underlineVerticalGap + 8 else { continue }
      let lineX = localX - origin.x
      if requiringHit {
        let inkWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
          - CGFloat(CTLineGetTrailingWhitespaceWidth(line))
        guard lineX >= -slop, lineX <= inkWidth + slop else { continue }
      }
      var idx = CTLineGetStringIndexForPosition(line, CGPoint(x: lineX, y: 0))
      guard idx != kCFNotFound else { continue }
      // That call returns the nearest caret boundary, so a tap on the right
      // half of a character lands on the next one (the next token for は, を…).
      // Step back to the character actually under the finger.
      let lineRange = CTLineGetStringRange(line)
      if idx > lineRange.location, CTLineGetOffsetForStringIndex(line, idx, nil) > lineX {
        idx -= 1
      }
      let lineEnd = lineRange.location + lineRange.length
      if lineRange.length > 0, idx >= lineEnd {
        idx = lineEnd - 1
      }
      let clamped = max(0, min(idx, attributed.length - 1))
      return tokenIndexResolving(near: clamped, in: attributed)
    }
    return nil
  }

  /// Stroke center just under the glyph baseline. The fragment bottom includes
  /// font descent, which is mostly empty under kana and crowds the next line's
  /// readings. Line spacing stays put.
  private func furiganaUnderlineCenterY(baselineY: CGFloat) -> CGFloat {
    let source = visibleAttributedText ?? attributedText
    let font = source.map { Self.fontForAttributes(from: $0) }
      ?? UIFont.preferredFont(forTextStyle: .title1)
    let belowBaseline = max(2, font.pointSize * 0.09) + 2
    return baselineY + belowBaseline
  }

  /// Per-line advance boxes (kern trimmed), slid horizontally so they center on the
  /// glyph ink. Kana and some kanji sit unevenly inside their em box (に leans left),
  /// so box-centered marks look shifted. The shift is capped so a token ending in
  /// punctuation (ink hugging one side) cannot drag its mark off the word.
  /// Underlines and the karaoke wash both use this so they stay aligned.
  private func inkCenteredFuriganaFragments(
    for range: NSRange,
    baseTextOnly: Bool = false
  ) -> [(rect: CGRect, baselineY: CGFloat)] {
    guard let layout = furiganaLayout ?? rebuildFuriganaLayoutIfNeeded() else { return [] }
    var out: [(rect: CGRect, baselineY: CGFloat)] = []
    for (index, line) in layout.lines.enumerated() {
      let lineRange = CTLineGetStringRange(line)
      let sub = NSIntersectionRange(range, NSRange(location: lineRange.location, length: lineRange.length))
      guard sub.length > 0,
            let fragment = coreTextLineFragments(
              forCharacterRange: sub,
              layout: layout,
              baseTextOnly: baseTextOnly
            ).first
      else { continue }
      var box = fragment.rect
      if let ink = Self.inkSpan(of: line, range: sub) {
        let inkMidX = layout.textOrigin.x + layout.lineOrigins[index].x + (ink.lowerBound + ink.upperBound) / 2
        let maxShift = box.width * 0.15
        box.origin.x += min(max(inkMidX - box.midX, -maxShift), maxShift)
      }
      out.append((box, fragment.baselineY))
    }
    return out
  }

  /// Underline span per line: the ink-centered box minus `pad` on each side.
  private func furiganaUnderlineFragments(
    for range: NSRange,
    pad: CGFloat
  ) -> [(minX: CGFloat, maxX: CGFloat, rect: CGRect, baselineY: CGFloat)] {
    inkCenteredFuriganaFragments(for: range).compactMap { fragment in
      let box = fragment.rect
      guard box.width > pad * 2 else { return nil }
      return (box.minX + pad, box.maxX - pad, box, fragment.baselineY)
    }
  }

  /// Horizontal ink extent (line coordinates) of the glyphs that map to `range`.
  /// Glyphs with no outline (spaces) are skipped.
  private static func inkSpan(of line: CTLine, range: NSRange) -> ClosedRange<CGFloat>? {
    var minX = CGFloat.greatestFiniteMagnitude
    var maxX = -CGFloat.greatestFiniteMagnitude
    let runs = CTLineGetGlyphRuns(line) as! [CTRun]
    for run in runs {
      let count = CTRunGetGlyphCount(run)
      guard count > 0,
            let fontValue = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName]
      else { continue }
      let font = fontValue as! CTFont
      var glyphs = [CGGlyph](repeating: 0, count: count)
      var positions = [CGPoint](repeating: .zero, count: count)
      var indices = [CFIndex](repeating: 0, count: count)
      var boxes = [CGRect](repeating: .zero, count: count)
      let all = CFRange(location: 0, length: 0)
      CTRunGetGlyphs(run, all, &glyphs)
      CTRunGetPositions(run, all, &positions)
      CTRunGetStringIndices(run, all, &indices)
      CTFontGetBoundingRectsForGlyphs(font, .horizontal, glyphs, &boxes, count)
      for i in 0..<count where NSLocationInRange(indices[i], range) {
        let box = boxes[i]
        guard box.width > 0 else { continue }
        minX = min(minX, positions[i].x + box.minX)
        maxX = max(maxX, positions[i].x + box.maxX)
      }
    }
    guard minX.isFinite, maxX > minX else { return nil }
    return minX...maxX
  }

  private func drawInsetUnderlinesUsingViewRects(
    segments: [(range: NSRange, tokenIndices: Set<Int>)],
    pad: CGFloat,
    rect: CGRect,
    underlineHighlight: Set<Int>
  ) {
    let isScrub = tokenSelectionAppearance == .scrubUnderline

    func stroke(_ charRange: NSRange, lineWidth: CGFloat, color: UIColor) {
      for fragment in furiganaUnderlineFragments(for: charRange, pad: pad) {
        guard fragment.rect.intersects(rect) else { continue }
        let y = furiganaUnderlineCenterY(baselineY: fragment.baselineY)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: fragment.minX, y: y))
        path.addLine(to: CGPoint(x: fragment.maxX, y: y))
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
      }
    }

    for (charRange, tokenIndices) in segments where charRange.length > 0 {
      guard tokenIndices.isDisjoint(with: underlineHighlight) else { continue }
      stroke(charRange, lineWidth: max(1.5, tokenUnderlineWidth), color: tokenUnderlineColor)
    }

    if isScrub, !underlineHighlight.isEmpty {
      for (charRange, tokenIndices) in segments where charRange.length > 0 {
        guard !tokenIndices.isDisjoint(with: underlineHighlight) else { continue }
        stroke(charRange, lineWidth: max(1.5, scrubActiveUnderlineWidth), color: scrubActiveUnderlineColor)
      }
    }
  }

  /// Grey underlines for non-selected segments; scrub mode adds a blue stroke on the active merged segment.
  /// TextKit (no furigana) underlines. Rects come from
  /// `lineFragmentViewRectsForCharacterRange`, which trims `tokenSpacing` kern
  /// and caps height at one line when `plainLineSpacing` is set, so wrapped
  /// lines keep their underline directly under the glyphs.
  private func drawPlainInsetUnderlines(
    segments: [(range: NSRange, tokenIndices: Set<Int>)],
    pad: CGFloat,
    rect: CGRect,
    selectedTokenIndices: Set<Int>
  ) {
    let isScrub = tokenSelectionAppearance == .scrubUnderline
    let inactiveLineWidth = max(1.5, tokenUnderlineWidth)
    let activeLineWidth = max(1.5, scrubActiveUnderlineWidth)

    func stroke(_ charRange: NSRange, lineWidth: CGFloat, color: UIColor) {
      for fragment in lineFragmentViewRectsForCharacterRange(charRange) {
        guard fragment.width > pad * 2 else { continue }
        let br = fragment.insetBy(dx: pad, dy: 0)
        guard br.intersects(rect) else { continue }
        let y = br.maxY + underlineVerticalGap - lineWidth * 0.5
        let p = UIBezierPath()
        p.move(to: CGPoint(x: br.minX, y: y))
        p.addLine(to: CGPoint(x: br.maxX, y: y))
        p.lineWidth = lineWidth
        p.lineCapStyle = .round
        color.setStroke()
        p.stroke()
      }
    }

    for (charRange, tokenIndices) in segments where charRange.length > 0 {
      guard tokenIndices.isDisjoint(with: selectedTokenIndices) else { continue }
      stroke(charRange, lineWidth: inactiveLineWidth, color: tokenUnderlineColor)
    }

    if isScrub, !selectedTokenIndices.isEmpty {
      for (charRange, tokenIndices) in segments where charRange.length > 0 {
        guard !tokenIndices.isDisjoint(with: selectedTokenIndices) else { continue }
        stroke(charRange, lineWidth: activeLineWidth, color: scrubActiveUnderlineColor)
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
    // Same hit test as scrub. With furigana on, glyphs come from the Core Text
    // layout; UITextView's own TextKit layout (closestPosition) wraps and
    // spaces lines differently, so it can resolve to a neighboring token.
    guard let tIdx = tokenIndex(at: p, requiringHit: true) else { return }
    let surface = tokenLookupSurfaces.indices.contains(tIdx) ? tokenLookupSurfaces[tIdx] : tokens[tIdx].text
    let rect = mergedWordBoundsInTextView(forTokenIndex: tIdx) ?? .zero
    onWordTapped?(surface, rect, tIdx)
  }

  private func tokenIndexResolving(near location: Int, in a: NSAttributedString) -> Int? {
    for p in [location, location - 1, location + 1, location - 2, location + 2] {
      if p < 0 || p >= a.length { continue }
      if let n = a.attribute(.scrubTokenIndex, at: p, effectiveRange: nil) as? NSNumber,
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
    tokens: [ScrubToken],
    font: UIFont,
    selectedIndices: Set<Int>?,
    selectionAppearance: LyricsTokenSelectionAppearance,
    selectedTextColor: UIColor = .white,
    showsFurigana: Bool = false,
    tokenSpacing: CGFloat = 0,
    lookupSurfaces: [String] = [],
    plainLineSpacing: CGFloat = 0,
    applyRuby: ((NSMutableAttributedString, String, UIFont) -> Void)? = nil
  ) -> NSAttributedString {
    // Tokens merged into one lookup (県 + 大会 → 県大会) read, tap and highlight as one
    // word, so no gap goes between them.
    let sharesLookup: (Int) -> Bool = { i in
      lookupSurfaces.count == tokens.count && lookupSurfaces[i] == lookupSurfaces[i + 1]
    }
    let base: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: UIColor.label,
    ]
    let m = NSMutableAttributedString(string: text, attributes: base)
    let highlight = selectedIndices ?? []
    for (i, t) in tokens.enumerated() {
      let r = NSRange(t.range, in: text)
      guard r.location != NSNotFound, r.length > 0, NSMaxRange(r) <= m.length else { continue }
      m.addAttribute(.scrubTokenIndex, value: i, range: r)
      if selectionAppearance == .definitionTip, highlight.contains(i), !showsFurigana {
        m.addAttribute(.foregroundColor, value: selectedTextColor, range: r)
      }
      // Gap only between touching tokens, so punctuation keeps its normal spacing.
      if tokenSpacing > 0, i + 1 < tokens.count,
        NSRange(tokens[i + 1].range, in: text).location == NSMaxRange(r),
        !sharesLookup(i)
      {
        let last = (text as NSString).rangeOfComposedCharacterSequence(at: NSMaxRange(r) - 1)
        // Tracking, not kern: a kern on the character right after 、 or 。 makes Core Text
        // halve that punctuation and add the removed width after the kerned character
        // (、県 + 大会 left a ~14pt hole after 県). Tracking adds the gap and nothing else.
        m.addAttribute(.tracking, value: tokenSpacing, range: last)
      }
    }
    if showsFurigana {
      applyRuby?(m, text, font)
    } else if plainLineSpacing > 0, m.length > 0 {
      let paragraph = NSMutableParagraphStyle()
      paragraph.lineSpacing = plainLineSpacing
      m.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: m.length))
    }
    return m
  }

  private static func expandIfSingleFullSentenceToken(
    base: String,
    tokens: [ScrubToken]
  ) -> [ScrubToken] {
    guard
      tokens.count == 1,
      let t = tokens.first,
      t.text == base,
      t.text.count > 1
    else { return tokens }

    var out: [ScrubToken] = []
    var i = base.startIndex
    while i < base.endIndex {
      let c = String(base[i])
      let j = base.index(after: i)
      let punc = c.unicodeScalars.allSatisfy { s in
        CharacterSet.punctuationCharacters.contains(s) || CharacterSet.whitespacesAndNewlines.contains(s)
      }
      if punc { i = j; continue }
      if !c.isEmpty { out.append(ScrubToken(text: c, range: i..<j)) }
      i = j
    }
    return out.isEmpty ? tokens : out
  }
}
