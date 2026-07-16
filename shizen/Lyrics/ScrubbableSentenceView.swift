//
//  ScrubbableSentenceView.swift
//  shizen
//
//  Reusable sentence scrubber: pan/tap across tokens, optional compact gloss callout above selection.
//

import UIKit

/// Embeds a tokenized sentence with scrub interaction and an optional compact definition callout.
final class ScrubbableSentenceView: UIView, UIGestureRecognizerDelegate {

    var showCalloutOnScrub = true {
        didSet { updateCalloutVisibility() }
    }

    var onSelectionChanged: ((_ tokenIndex: Int?, _ surface: String?) -> Void)?

    /// Called when the user taps the chevron on the compact callout.
    var onRequestDictionaryDetail: ((_ surface: String, _ sentence: String) -> Void)?

    /// Inner text view for layout anchors (e.g. align controls to the sentence line).
    var sentenceLineView: LyricsInsetUnderlineTextView { sentenceTextView }

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
    private var backendObserver: NSObjectProtocol?

    private var lastSentence = ""
    private var lastFont = UIFont.preferredFont(forTextStyle: .title1)
    private var lastAccentSubstring: String?
    private var lastAccentColor: UIColor = .systemBlue
    private var hasConfigured = false
    private var usesProvidedTokens = false

    private static let calloutGap: CGFloat = 4
    private static let tokenizingIndicatorGap: CGFloat = 6

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
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

        backendObserver = NotificationCenter.default.addObserver(
            forName: .japaneseTokenizerBackendDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reapplyTokenizationIfConfigured()
        }
    }

    deinit {
        tokenizeTask?.cancel()
        if let backendObserver {
            NotificationCenter.default.removeObserver(backendObserver)
        }
        scrollObservation?.invalidate()
        if calloutIsVisible {
            DefinitionCalloutPresenter.shared.dismiss(animated: false)
        }
    }

    /// Dismisses the callout when the enclosing scroll view moves.
    func bindDismissOnScroll(_ scrollView: UIScrollView) {
        scrollObservation?.invalidate()
        scrollObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
            guard scrollView.isDragging || scrollView.isDecelerating else { return }
            self?.dismissCallout(animated: true)
        }
    }

    /// Dismisses the callout when the user taps anywhere in `view` (e.g. the parent scroll view).
    func bindDismissOnTap(_ view: UIView) {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleDismissTap(_:)))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    /// Dismisses the callout without clearing the current token selection.
    func dismissCalloutOnly(animated: Bool = true) {
        dismissCallout(animated: animated)
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
    func configureWithTokens(
        sentence: String,
        font: UIFont,
        tokens: [JapaneseToken],
        showsFurigana: Bool = true,
        accentSubstring: String? = nil,
        accentColor: UIColor = .systemBlue,
        clearInteraction: Bool = false
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
            accentColor: accentColor
        )
    }

    /// One-shot tokenization for exercise drills; matches the active backend (including async LLM backends).
    static func tokenize(sentence: String) async -> [JapaneseToken] {
        switch JapaneseTokenizerBackend.preferred {
        case .naturalLanguage, .mecab:
            return JapaneseTokenizer(backend: JapaneseTokenizerBackend.preferred).tokenize(sentence)
        case .foundationModel, .geminiFlash, .geminiFlashLite, .geminiFlash31Lite:
            let fallback = JapaneseTokenizer(backend: .mecab).tokenize(sentence)
            switch JapaneseTokenizerBackend.preferred {
            case .foundationModel:
                guard FoundationModelJapaneseTokenizer.isAvailable else { return fallback }
                do {
                    let result = try await FoundationModelJapaneseTokenizer.tokenize(sentence)
                    return result.tokens.isEmpty ? fallback : result.tokens
                } catch {
                    return fallback
                }
            case .geminiFlash, .geminiFlashLite, .geminiFlash31Lite:
                guard let model = JapaneseTokenizerBackend.preferred.geminiModel else { return fallback }
                guard GeminiJapaneseTokenizer.isConfigured else { return fallback }
                do {
                    let result = try await GeminiJapaneseTokenizer.tokenize(sentence, model: model)
                    return result.tokens.isEmpty ? fallback : result.tokens
                } catch {
                    return fallback
                }
            default:
                return fallback
            }
        }
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

        switch JapaneseTokenizerBackend.preferred {
        case .naturalLanguage, .mecab:
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
        case .foundationModel, .geminiFlash, .geminiFlashLite, .geminiFlash31Lite:
            sentenceTextView.configure(
                sentence: lastSentence,
                lyricFont: lastFont,
                tokens: [],
                showsFurigana: showsFurigana,
                accentSubstring: lastAccentSubstring,
                accentColor: lastAccentColor
            )
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
                self.setTokenizing(false, animatedSuccess: true)
            }
        }
    }

    override func layoutSubviews() {
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

    private func loadAsyncTokens(for backend: JapaneseTokenizerBackend) async -> [JapaneseToken] {
        let fallback = JapaneseTokenizer(backend: .mecab).tokenize(lastSentence)
        switch backend {
        case .foundationModel:
            guard FoundationModelJapaneseTokenizer.isAvailable else { return fallback }
            do {
                let result = try await FoundationModelJapaneseTokenizer.tokenize(lastSentence)
                return result.tokens.isEmpty ? fallback : result.tokens
            } catch {
                return fallback
            }
        case .geminiFlash, .geminiFlashLite:
            guard let model = backend.geminiModel else { return fallback }
            guard GeminiJapaneseTokenizer.isConfigured else { return fallback }
            do {
                let result = try await GeminiJapaneseTokenizer.tokenize(lastSentence, model: model)
                return result.tokens.isEmpty ? fallback : result.tokens
            } catch {
                return fallback
            }
        default:
            return fallback
        }
    }

    func clearSelection() {
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

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
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

        let gloss = Self.primaryGloss(for: surface)
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

    // MARK: - Gloss lookup

    private static func primaryGloss(for surface: String) -> String {
        let entries = JMDictStore.shared.entries(forSurface: surface)
        guard let primary = entries.max(by: { ($0.score ?? 0) < ($1.score ?? 0) }) ?? entries.first else {
            return ""
        }
        let gloss = primary.glossary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gloss.isEmpty else { return "" }
        return gloss
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? gloss
    }
}
