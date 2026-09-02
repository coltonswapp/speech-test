//
//  ScrubbableSentenceView.swift
//  InteractionKit
//
//  Reusable sentence scrubber: pan/tap across tokens, optional compact gloss callout above selection.
//

import UIKit

/// Embeds a tokenized sentence with scrub interaction and an optional compact definition callout.
public final class ScrubbableSentenceView: UIView, UIGestureRecognizerDelegate {

    public var engine: (any ScrubSentenceEngine)? {
        didSet { bindEngineNotifications() }
    }

    public var showCalloutOnScrub = true {
        didSet { updateCalloutVisibility() }
    }

    public var onSelectionChanged: ((_ tokenIndex: Int?, _ surface: String?) -> Void)?

    /// Called when the user taps the chevron on the compact callout.
    public var onRequestDictionaryDetail: ((_ surface: String, _ sentence: String) -> Void)?

    /// Inner text view for layout anchors (e.g. align controls to the sentence line).
    public var sentenceLineView: LyricsInsetUnderlineTextView { sentenceTextView }

    private let sentenceTextView = LyricsInsetUnderlineTextView()
    private let tokenizingIndicator: NNLoadingSpinner = {
        let spinner = NNLoadingSpinner(frame: CGRect(x: 0, y: 0, width: 18, height: 18))
        spinner.configure(with: .secondaryLabel)
        spinner.isHidden = true
        return spinner
    }()
    private var isTokenizing = false
    private var tokenizingAnimationID = 0
    private var calloutIsVisible = false
    private var calloutSurface: String?
    private var scrollObservation: NSKeyValueObservation?

    private let selectionFeedback = UISelectionFeedbackGenerator()
    private var lastScrubTokenIndex: Int?
    private var showsFurigana = true
    private var tokenizeTask: Task<Void, Never>?
    private var observedTokenizerNotification: Notification.Name?

    private var lastSentence = ""
    private var lastFont = UIFont.preferredFont(forTextStyle: .title1)
    private var lastAccentSubstring: String?
    private var lastAccentColor: UIColor = .systemBlue
    private var hasConfigured = false
    private var usesProvidedTokens = false

    private static let calloutGap: CGFloat = 4
    private static let tokenizingIndicatorGap: CGFloat = 6

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        clipsToBounds = false
        translatesAutoresizingMaskIntoConstraints = false

        sentenceTextView.translatesAutoresizingMaskIntoConstraints = false
        sentenceTextView.tokenSelectionAppearance = .definitionTip
        sentenceTextView.clipsToBounds = false
        addSubview(sentenceTextView)
        addSubview(tokenizingIndicator)

        NSLayoutConstraint.activate([
            sentenceTextView.topAnchor.constraint(equalTo: topAnchor),
            sentenceTextView.leadingAnchor.constraint(equalTo: leadingAnchor),
            sentenceTextView.trailingAnchor.constraint(equalTo: trailingAnchor),
            sentenceTextView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        sentenceTextView.addGestureRecognizer(pan)

        sentenceTextView.onWordTapped = { [weak self] _, _, tokenIndex in
            guard let self else { return }
            if self.lastScrubTokenIndex == tokenIndex {
                self.applyTokenIndex(nil, fromUser: true, showCallout: false)
            } else {
                self.applyTokenIndex(tokenIndex, fromUser: true, showCallout: true)
            }
        }

        selectionFeedback.prepare()
        bindEngineNotifications()
    }

    private func bindEngineNotifications() {
        if let observedTokenizerNotification {
            NotificationCenter.default.removeObserver(self, name: observedTokenizerNotification, object: nil)
            self.observedTokenizerNotification = nil
        }
        guard let name = engine?.tokenizerDidChangeNotification else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTokenizerBackendDidChange),
            name: name,
            object: nil
        )
        observedTokenizerNotification = name
    }

    @objc private func handleTokenizerBackendDidChange() {
        reapplyTokenizationIfConfigured()
    }

    public override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        guard newWindow == nil else { return }
        tokenizeTask?.cancel()
        if calloutIsVisible {
            DefinitionCalloutPresenter.shared.dismiss(animated: false)
        }
    }

    /// Dismisses the callout when the enclosing scroll view moves.
    public func bindDismissOnScroll(_ scrollView: UIScrollView) {
        scrollObservation?.invalidate()
        scrollObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
            guard scrollView.isDragging || scrollView.isDecelerating else { return }
            self?.dismissCallout(animated: true)
        }
    }

    /// Dismisses the callout when the user taps anywhere in `view` (e.g. the parent scroll view).
    public func bindDismissOnTap(_ view: UIView) {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleDismissTap(_:)))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    /// Dismisses the callout without clearing the current token selection.
    public func dismissCalloutOnly(animated: Bool = true) {
        dismissCallout(animated: animated)
    }

    /// Text-container padding is only for ruby / selection overflow. Hug the
    /// glyphs so this view's leading matches siblings in the same stack.
    override var alignmentRectInsets: UIEdgeInsets {
        UIEdgeInsets(
            top: 0,
            left: sentenceTextView.textContainerInset.left,
            bottom: 0,
            right: 0
        )
    }

    func configure(
        sentence: String,
        font: UIFont,
        showsFurigana: Bool = true,
        accentSubstring: String? = nil,
        accentColor: UIColor = .systemBlue
    ) {
        usesProvidedTokens = false
        lastSentence = sentence
        lastFont = font
        self.showsFurigana = showsFurigana
        lastAccentSubstring = accentSubstring
        lastAccentColor = accentColor
        hasConfigured = true
        applyTokenization(clearInteraction: true)
    }

    /// Renders with precomputed tokens only — no tokenizer or network call.
    /// When `preservesTokenBoundaries` is true, underlines stay 1:1 with
    /// `tokens` instead of merging adjacent JMDict compounds.
    func configureWithTokens(
        sentence: String,
        font: UIFont,
        tokens: [ScrubToken],
        lookupSurfaces: [String]? = nil,
        showsFurigana: Bool = true,
        accentSubstring: String? = nil,
        accentColor: UIColor = .systemBlue,
        clearInteraction: Bool = false,
        preservesTokenBoundaries: Bool = false
    ) {
        tokenizeTask?.cancel()
        usesProvidedTokens = true
        lastSentence = sentence
        lastFont = font
        self.showsFurigana = showsFurigana
        lastAccentSubstring = accentSubstring
        lastAccentColor = accentColor
        hasConfigured = true

        if clearInteraction {
            dismissCallout(animated: false)
            lastScrubTokenIndex = nil
            sentenceTextView.setDefinitionSelectionHighlight(tokenIndex: nil)
            onSelectionChanged?(nil, nil)
        }

        setTokenizing(false)
        sentenceTextView.configure(
            sentence: sentence,
            lyricFont: font,
            tokens: tokens,
            showsFurigana: showsFurigana,
            accentSubstring: accentSubstring,
            accentColor: accentColor,
            preservesTokenBoundaries: preservesTokenBoundaries
        )
        noteTextLayoutChanged()
    }

    private func noteTextLayoutChanged() {
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func applyTokensToTextView(_ tokens: [ScrubToken], lookupSurfaces: [String]? = nil) {
        let surfaces = lookupSurfaces ?? engine?.lookupSurfaces(for: tokens)
        sentenceTextView.configure(
            sentence: lastSentence,
            lyricFont: lastFont,
            tokens: tokens,
            lookupSurfaces: surfaces,
            showsFurigana: showsFurigana,
            accentSubstring: lastAccentSubstring,
            accentColor: lastAccentColor,
            applyRuby: showsFurigana ? { [weak self] attributed, text, font in
                self?.engine?.applyRuby(to: attributed, text: text, font: font)
            } : nil
        )
    }

    private func reapplyTokenizationIfConfigured() {
        guard hasConfigured, !usesProvidedTokens else { return }
        applyTokenization(clearInteraction: true)
    }

    private func applyTokenization(clearInteraction: Bool) {
        tokenizeTask?.cancel()

        if clearInteraction {
            dismissCallout(animated: false)
            lastScrubTokenIndex = nil
            sentenceTextView.setDefinitionSelectionHighlight(tokenIndex: nil)
            onSelectionChanged?(nil, nil)
        }

        guard let engine else {
            applyTokensToTextView([])
            return
        }

        if let tokens = engine.tokenizeSync(lastSentence) {
            setTokenizing(false)
            let tokenizer = JapaneseTokenizer(backend: JapaneseTokenizerBackend.preferred)
            sentenceTextView.configure(
                sentence: lastSentence,
                lyricFont: lastFont,
                tokenizer: tokenizer,
                showsFurigana: showsFurigana,
                accentSubstring: lastAccentSubstring,
                accentColor: lastAccentColor
            )
            noteTextLayoutChanged()
        case .foundationModel, .geminiFlash, .geminiFlashLite, .geminiFlash31Lite:
            sentenceTextView.configure(
                sentence: lastSentence,
                lyricFont: lastFont,
                tokens: [],
                showsFurigana: showsFurigana,
                accentSubstring: lastAccentSubstring,
                accentColor: lastAccentColor
            )
            noteTextLayoutChanged()
            setTokenizing(true)
            tokenizeTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let tokens = await self.loadAsyncTokens(for: JapaneseTokenizerBackend.preferred)
                guard !Task.isCancelled else { return }
                self.sentenceTextView.configure(
                    sentence: self.lastSentence,
                    lyricFont: self.lastFont,
                    tokens: tokens,
                    showsFurigana: self.showsFurigana,
                    accentSubstring: self.lastAccentSubstring,
                    accentColor: self.lastAccentColor
                )
                self.noteTextLayoutChanged()
                self.setTokenizing(false, animatedSuccess: true)
            }
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateTokenizingIndicatorPosition()
    }

    private func setTokenizing(_ tokenizing: Bool, animatedSuccess: Bool = false) {
        if tokenizing {
            guard !isTokenizing else { return }
            tokenizingAnimationID += 1
            isTokenizing = true
            tokenizingIndicator.isHidden = false
            tokenizingIndicator.alpha = 1
            tokenizingIndicator.reset()
            setNeedsLayout()
            return
        }

        guard isTokenizing || !tokenizingIndicator.isHidden else { return }
        isTokenizing = false
        let animationID = tokenizingAnimationID
        if animatedSuccess {
            tokenizingIndicator.fadeOut { [weak self] in
                guard let self, self.tokenizingAnimationID == animationID else { return }
                self.tokenizingIndicator.isHidden = true
                self.tokenizingIndicator.alpha = 1
                self.tokenizingIndicator.reset()
            }
        } else {
            tokenizingAnimationID += 1
            tokenizingIndicator.isHidden = true
        }
        setNeedsLayout()
    }

    private func updateTokenizingIndicatorPosition() {
        guard isTokenizing else { return }
        sentenceTextView.layoutIfNeeded()
        let anchor: CGPoint
        if let trailing = sentenceTextView.lastLineTrailingRectInTextView() {
            anchor = sentenceTextView.convert(
                CGPoint(x: trailing.maxX, y: trailing.midY),
                to: self
            )
        } else {
            anchor = sentenceTextView.convert(
                CGPoint(x: sentenceTextView.bounds.minX, y: sentenceTextView.bounds.midY),
                to: self
            )
        }
        let size = tokenizingIndicator.bounds.size
        tokenizingIndicator.center = CGPoint(
            x: anchor.x + Self.tokenizingIndicatorGap + size.width * 0.5,
            y: anchor.y
        )
    }

    public func clearSelection() {
        applyTokenIndex(nil, fromUser: false)
    }

    // MARK: - Interaction

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began, .changed, .ended:
            break
        default:
            return
        }
        let p = g.location(in: sentenceTextView)
        guard let idx = sentenceTextView.tokenIndex(at: p) else { return }
        applyTokenIndex(idx, fromUser: true, showCallout: true)
    }

    @objc private func handleDismissTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended else { return }
        let root = g.view ?? self
        let point = g.location(in: root)
        if isPointInsideCallout(point, in: root) { return }
        if isPointOnInteractiveControl(point, in: root) { return }

        let pointInTextView = g.location(in: sentenceTextView)
        if sentenceTextView.bounds.contains(pointInTextView),
           sentenceTextView.tokenIndex(at: pointInTextView) != nil {
            return
        }
        dismissCalloutOnly(animated: true)
    }

    private func isPointOnInteractiveControl(_ point: CGPoint, in root: UIView) -> Bool {
        var view: UIView? = root.hitTest(point, with: nil)
        while let current = view {
            if current is UIControl, current !== sentenceTextView {
                return true
            }
            if current === self || current === root {
                break
            }
            view = current.superview
        }
        return false
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    private func isPointInsideCallout(_ point: CGPoint, in coordinateView: UIView) -> Bool {
        guard calloutIsVisible else { return false }
        return DefinitionCalloutPresenter.shared.isShowingCallout(at: point, in: coordinateView)
    }

    private func presentDictionaryDetailFromCallout() {
        guard let surface = calloutSurface else { return }
        dismissCallout(animated: true)
        onRequestDictionaryDetail?(surface, lastSentence)
    }

    private func applyTokenIndex(_ index: Int?, fromUser: Bool, showCallout: Bool = true) {
        if let index {
            if lastScrubTokenIndex != index {
                lastScrubTokenIndex = index
                if fromUser {
                    selectionFeedback.selectionChanged()
                    selectionFeedback.prepare()
                }
            }
        } else {
            lastScrubTokenIndex = nil
        }

        sentenceTextView.setDefinitionSelectionHighlight(tokenIndex: index)

        let surface = index.flatMap { sentenceTextView.tokenSurface(at: $0) }
        if showCallout, showCalloutOnScrub, index != nil {
            updateCallout(for: index, surface: surface)
        } else if index == nil {
            dismissCallout(animated: calloutIsVisible)
        }
        onSelectionChanged?(index, surface)
    }

    // MARK: - Callout

    private func updateCalloutVisibility() {
        if showCalloutOnScrub {
            if let idx = lastScrubTokenIndex {
                let surface = sentenceTextView.tokenSurface(at: idx)
                updateCallout(for: idx, surface: surface)
            }
        } else {
            dismissCallout(animated: true)
        }
    }

    private func updateCallout(for index: Int?, surface: String?) {
        guard showCalloutOnScrub, let index, let surface, !surface.isEmpty else {
            dismissCallout(animated: calloutIsVisible)
            return
        }

        let gloss = engine?.gloss(for: surface) ?? ""
        guard !gloss.isEmpty else {
            dismissCallout(animated: calloutIsVisible)
            return
        }

        let lineFragments = sentenceTextView.mergedWordLineFragmentRectsInTextView(forTokenIndex: index)
        guard !lineFragments.isEmpty else {
            dismissCallout(animated: calloutIsVisible)
            return
        }

        let fragmentsInSelf = lineFragments.map { sentenceTextView.convert($0, to: self) }
        presentOrMoveCallout(text: gloss, surface: surface, lineFragments: fragmentsInSelf)
    }

    private func presentOrMoveCallout(text: String, surface: String, lineFragments: [CGRect]) {
        calloutSurface = surface
        calloutIsVisible = true

        DefinitionCalloutPresenter.shared.presentOrUpdate(
            text: text,
            surface: surface,
            lineFragments: lineFragments,
            in: self,
            gap: Self.calloutGap
        ) { [weak self] _ in
            self?.presentDictionaryDetailFromCallout()
        }
    }

    private func dismissCallout(animated: Bool) {
        calloutIsVisible = false
        calloutSurface = nil
        DefinitionCalloutPresenter.shared.dismiss(animated: animated)
    }
}
