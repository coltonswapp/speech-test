//
//  TokenizerLabViewController.swift
//  shizen
//
//  Compare NaturalLanguage vs MeCab (IPADic) vs Foundation Model using the same underline rendering as lyrics / sentence breakdown.
//

import InteractionKit
import UIKit

final class TokenizerLabViewController: UIViewController {

    private static let exampleSentences: [String] = [
        "今日はいい天気ですね。",
        "歩いて学校へ行きましょう。",
        "蜂蜜は熊の大好物です。",
        "お釣りは三百円です。どうぞ。",
        "こんにちは。お元気ですか。",
        "日本語を勉強しています。",
        "食べられなかったそうです。",
        "新天地で働き始めました。",
        "りんごを三つ買いました。",
        "彼女は東京で生まれましたが、今は大阪に住んでいます。",
    ]

    private struct FMTarget {
        weak var textView: LyricsInsetUnderlineTextView?
        weak var statusLabel: UILabel?
        let sentence: String
    }

    private let nlEngine = JapaneseTokenizer(backend: .naturalLanguage)
    private let mecabEngine = JapaneseTokenizer(backend: .mecab)

    private struct GeminiTarget {
        weak var textView: LyricsInsetUnderlineTextView?
        weak var statusLabel: UILabel?
        let sentence: String
        let model: GeminiJapaneseTokenizer.Model
    }

    private var fmTargets: [FMTarget] = []
    private var geminiTargets: [GeminiTarget] = []
    private var fmRefreshTask: Task<Void, Never>?
    private var geminiRefreshTask: Task<Void, Never>?

    private let scrollView: UIScrollView = {
        let s = UIScrollView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.alwaysBounceVertical = true
        return s
    }()

    private let contentStack: UIStackView = {
        let s = UIStackView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.axis = .vertical
        s.spacing = 20
        return s
    }()

    private let backendControl: UISegmentedControl = {
        let c = UISegmentedControl(items: JapaneseTokenizerBackend.allCases.map(\.shortName))
        c.translatesAutoresizingMaskIntoConstraints = false
        return c
    }()

    private let hintLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.numberOfLines = 0
        l.font = .preferredFont(forTextStyle: .footnote)
        l.textColor = .secondaryLabel
        l.text = "Orange = NaturalLanguage. Teal = MeCab. Purple = on-device Foundation model. Indigo = Gemini 2.5 Flash. Cyan = Gemini 2.5 Flash Lite (re-fetched in lab; cached in app). LLM tokenizers reject romaji and fall back to MeCab when output is invalid. Segmented control sets the app-wide tokenizer."
        return l
    }()

    private let fmAvailabilityLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.numberOfLines = 0
        l.font = .preferredFont(forTextStyle: .caption1)
        l.textColor = .tertiaryLabel
        return l
    }()

    private let geminiAvailabilityLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.numberOfLines = 0
        l.font = .preferredFont(forTextStyle: .caption1)
        l.textColor = .tertiaryLabel
        return l
    }()

    private let customTitle: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .preferredFont(forTextStyle: .headline)
        l.text = "Custom sentence"
        return l
    }()

    private let customTextView: UITextView = {
        let v = UITextView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.font = .preferredFont(forTextStyle: .body)
        v.adjustsFontForContentSizeCategory = true
        v.layer.borderColor = UIColor.separator.cgColor
        v.layer.borderWidth = 1 / UIScreen.main.scale
        v.layer.cornerRadius = 8
        v.backgroundColor = .secondarySystemGroupedBackground
        return v
    }()

    private let customNL = LyricsInsetUnderlineTextView()
    private let customMeCab = LyricsInsetUnderlineTextView()
    private let customFM = LyricsInsetUnderlineTextView()
    private let customFMStatus = UILabel()
    private let customGemini = LyricsInsetUnderlineTextView()
    private let customGeminiStatus = UILabel()
    private let customGeminiLite = LyricsInsetUnderlineTextView()
    private let customGeminiLiteStatus = UILabel()

    private weak var definitionHighlightTextView: LyricsInsetUnderlineTextView?
    private var definitionAnchor: UIView?

    private lazy var bodyFont: UIFont = .preferredFont(forTextStyle: .body)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        title = "Tokenizer Lab"

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
        ])

        syncBackendControlSelection()
        backendControl.addTarget(self, action: #selector(backendChanged), for: .valueChanged)

        let topStack = UIStackView(arrangedSubviews: [hintLabel, fmAvailabilityLabel, geminiAvailabilityLabel, backendControl])
        topStack.axis = .vertical
        topStack.spacing = 10
        contentStack.addArrangedSubview(topStack)

        let samplesTitle = sectionTitle("Examples")
        contentStack.addArrangedSubview(samplesTitle)

        for (i, sentence) in Self.exampleSentences.enumerated() {
            contentStack.addArrangedSubview(
                makeExampleBlock(index: i + 1, sentence: sentence)
            )
        }

        contentStack.addArrangedSubview(customTitle)

        customTextView.text = "試しに自分の文を入力してください。"
        customTextView.delegate = self
        contentStack.addArrangedSubview(customTextView)
        let customH = customTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100)
        customH.priority = .required
        customH.isActive = true

        configureCustomHighlightViews()
        contentStack.addArrangedSubview(makeEngineQuadRow(
            nl: customNL,
            mecab: customMeCab,
            fm: customFM,
            fmStatus: customFMStatus,
            gemini: customGemini,
            geminiStatus: customGeminiStatus,
            geminiLite: customGeminiLite,
            geminiLiteStatus: customGeminiLiteStatus
        ))

        fmTargets.append(FMTarget(textView: customFM, statusLabel: customFMStatus, sentence: customTextView.text ?? ""))
        geminiTargets.append(GeminiTarget(
            textView: customGemini,
            statusLabel: customGeminiStatus,
            sentence: customTextView.text ?? "",
            model: .flash
        ))
        geminiTargets.append(GeminiTarget(
            textView: customGeminiLite,
            statusLabel: customGeminiLiteStatus,
            sentence: customTextView.text ?? "",
            model: .flashLite
        ))

        NSLayoutConstraint.activate([
            customNL.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
            customMeCab.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
            customFM.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
            customGemini.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
            customGeminiLite.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])

        updateFMAvailabilityLabel()
        updateGeminiAvailabilityLabel()
        updateDismissButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshCustomHighlights()
        refreshFoundationModelTokens(customOnly: false)
        refreshGeminiTokens(customOnly: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateDismissButton()
        updateFMAvailabilityLabel()
        updateGeminiAvailabilityLabel()
        syncBackendControlSelection()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        fmRefreshTask?.cancel()
        geminiRefreshTask?.cancel()
        clearDefinitionPresentation(animateTip: true)
    }

    private func updateDismissButton() {
        let isModalRoot =
            presentingViewController != nil
            && navigationController?.viewControllers.first === self
        navigationItem.rightBarButtonItem = isModalRoot
            ? UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))
            : nil
    }

    @objc private func doneTapped() {
        clearDefinitionPresentation(animateTip: false)
        if let nav = navigationController, nav.presentingViewController != nil, nav.viewControllers.first === self {
            nav.dismiss(animated: true)
        } else if presentingViewController != nil {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    @objc private func backendChanged() {
        let backends = JapaneseTokenizerBackend.allCases
        let index = backendControl.selectedSegmentIndex
        guard backends.indices.contains(index) else { return }
        JapaneseTokenizerBackend.preferred = backends[index]
    }

    private func syncBackendControlSelection() {
        let backends = JapaneseTokenizerBackend.allCases
        if let index = backends.firstIndex(of: JapaneseTokenizerBackend.preferred) {
            backendControl.selectedSegmentIndex = index
        }
    }

    private func updateFMAvailabilityLabel() {
        if FoundationModelJapaneseTokenizer.isAvailable {
            fmAvailabilityLabel.text = "Foundation model is available on this device."
            fmAvailabilityLabel.textColor = .secondaryLabel
        } else {
            fmAvailabilityLabel.text = FoundationModelJapaneseTokenizer.unavailabilityMessage
            fmAvailabilityLabel.textColor = .systemOrange
        }
    }

    private func updateGeminiAvailabilityLabel() {
        if GeminiJapaneseTokenizer.isConfigured {
            geminiAvailabilityLabel.text = GeminiJapaneseTokenizer.configurationMessage
            geminiAvailabilityLabel.textColor = .secondaryLabel
        } else {
            geminiAvailabilityLabel.text = "Gemini API key missing — cloud segmentation will fail in the lab."
            geminiAvailabilityLabel.textColor = .systemOrange
        }
    }

    private func sectionTitle(_ text: String) -> UILabel {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .title3)
        l.textColor = .label
        l.text = text
        return l
    }

    private func caption(_ text: String, color: UIColor) -> UILabel {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .subheadline)
        l.textColor = color
        l.text = text
        return l
    }

    private func fmStatusLabel() -> UILabel {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.numberOfLines = 0
        l.font = .preferredFont(forTextStyle: .caption2)
        l.textColor = .tertiaryLabel
        l.text = "Waiting for foundation model…"
        return l
    }

    private func makeExampleBlock(index: Int, sentence: String) -> UIView {
        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.backgroundColor = .secondarySystemGroupedBackground
        wrap.layer.cornerRadius = 12
        wrap.layer.cornerCurve = .continuous

        let badge = UILabel()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.font = .preferredFont(forTextStyle: .caption1)
        badge.textColor = .tertiaryLabel
        badge.text = "Example \(index)"

        let nlTV = makeHighlightTextView()
        let meTV = makeHighlightTextView()
        let fmTV = makeHighlightTextView()
        let fmStatus = fmStatusLabel()
        let geminiTV = makeHighlightTextView()
        let geminiStatus = fmStatusLabel()
        let geminiLiteTV = makeHighlightTextView()
        let geminiLiteStatus = fmStatusLabel()
        nlTV.tokenUnderlineColor = .systemOrange
        meTV.tokenUnderlineColor = .systemTeal
        fmTV.tokenUnderlineColor = .systemPurple
        geminiTV.tokenUnderlineColor = .systemIndigo
        geminiLiteTV.tokenUnderlineColor = .systemCyan

        nlTV.configure(sentence: sentence, lyricFont: bodyFont, tokenizer: nlEngine)
        meTV.configure(sentence: sentence, lyricFont: bodyFont, tokenizer: mecabEngine)
        fmTV.configure(sentence: sentence, lyricFont: bodyFont, japaneseTokens: [])
        geminiTV.configure(sentence: sentence, lyricFont: bodyFont, japaneseTokens: [])
        geminiLiteTV.configure(sentence: sentence, lyricFont: bodyFont, japaneseTokens: [])
        attachDefinitionTapHandler(to: nlTV)
        attachDefinitionTapHandler(to: meTV)
        attachDefinitionTapHandler(to: fmTV)
        attachDefinitionTapHandler(to: geminiTV)
        attachDefinitionTapHandler(to: geminiLiteTV)

        fmTargets.append(FMTarget(textView: fmTV, statusLabel: fmStatus, sentence: sentence))
        geminiTargets.append(GeminiTarget(textView: geminiTV, statusLabel: geminiStatus, sentence: sentence, model: .flash))
        geminiTargets.append(GeminiTarget(textView: geminiLiteTV, statusLabel: geminiLiteStatus, sentence: sentence, model: .flashLite))

        let inner = UIStackView(arrangedSubviews: [
            badge,
            caption("NaturalLanguage", color: .systemOrange),
            nlTV,
            caption("MeCab (IPADic)", color: .systemTeal),
            meTV,
            caption("Foundation Model", color: .systemPurple),
            fmStatus,
            fmTV,
            caption("Gemini 2.5 Flash", color: .systemIndigo),
            geminiStatus,
            geminiTV,
            caption("Gemini 2.5 Flash Lite", color: .systemCyan),
            geminiLiteStatus,
            geminiLiteTV,
        ])
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.axis = .vertical
        inner.spacing = 8

        wrap.addSubview(inner)

        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 12),
            inner.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -12),
            inner.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 10),
            inner.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -10),
        ])

        return wrap
    }

    private func makeHighlightTextView() -> LyricsInsetUnderlineTextView {
        let v = LyricsInsetUnderlineTextView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.tintColor = .clear
        v.tokenSelectionAppearance = .definitionTip
        v.isScrollEnabled = false
        return v
    }

    private func configureCustomHighlightViews() {
        for v in [customNL, customMeCab, customFM, customGemini, customGeminiLite] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.tintColor = .clear
            v.tokenSelectionAppearance = .definitionTip
            v.isScrollEnabled = false
        }
        customNL.tokenUnderlineColor = .systemOrange
        customMeCab.tokenUnderlineColor = .systemTeal
        customFM.tokenUnderlineColor = .systemPurple
        customGemini.tokenUnderlineColor = .systemIndigo
        customGeminiLite.tokenUnderlineColor = .systemCyan
        customFMStatus.font = .preferredFont(forTextStyle: .caption2)
        customFMStatus.textColor = .tertiaryLabel
        customFMStatus.numberOfLines = 0
        customFMStatus.text = "Waiting for foundation model…"
        customGeminiStatus.font = .preferredFont(forTextStyle: .caption2)
        customGeminiStatus.textColor = .tertiaryLabel
        customGeminiStatus.numberOfLines = 0
        customGeminiStatus.text = "Waiting for Gemini Flash…"
        customGeminiLiteStatus.font = .preferredFont(forTextStyle: .caption2)
        customGeminiLiteStatus.textColor = .tertiaryLabel
        customGeminiLiteStatus.numberOfLines = 0
        customGeminiLiteStatus.text = "Waiting for Gemini Flash Lite…"
        attachDefinitionTapHandler(to: customNL)
        attachDefinitionTapHandler(to: customMeCab)
        attachDefinitionTapHandler(to: customFM)
        attachDefinitionTapHandler(to: customGemini)
        attachDefinitionTapHandler(to: customGeminiLite)
    }

    private func makeEngineQuadRow(
        nl: LyricsInsetUnderlineTextView,
        mecab: LyricsInsetUnderlineTextView,
        fm: LyricsInsetUnderlineTextView,
        fmStatus: UILabel,
        gemini: LyricsInsetUnderlineTextView,
        geminiStatus: UILabel,
        geminiLite: LyricsInsetUnderlineTextView,
        geminiLiteStatus: UILabel
    ) -> UIView {
        let wrap = UIView()
        let stack = UIStackView(arrangedSubviews: [
            caption("NaturalLanguage", color: .systemOrange),
            nl,
            caption("MeCab (IPADic)", color: .systemTeal),
            mecab,
            caption("Foundation Model", color: .systemPurple),
            fmStatus,
            fm,
            caption("Gemini 2.5 Flash", color: .systemIndigo),
            geminiStatus,
            gemini,
            caption("Gemini 2.5 Flash Lite", color: .systemCyan),
            geminiLiteStatus,
            geminiLite,
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8
        wrap.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: wrap.topAnchor),
            stack.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
        ])
        return wrap
    }

    private func refreshCustomHighlights() {
        clearDefinitionPresentation(animateTip: false)
        let sentence = customTextView.text ?? ""
        customNL.configure(sentence: sentence, lyricFont: bodyFont, tokenizer: nlEngine)
        customMeCab.configure(sentence: sentence, lyricFont: bodyFont, tokenizer: mecabEngine)
        customFM.configure(sentence: sentence, lyricFont: bodyFont, japaneseTokens: [])
        customGemini.configure(sentence: sentence, lyricFont: bodyFont, japaneseTokens: [])
        customGeminiLite.configure(sentence: sentence, lyricFont: bodyFont, japaneseTokens: [])
        if let customIndex = fmTargets.firstIndex(where: { $0.textView === customFM }) {
            fmTargets[customIndex] = FMTarget(textView: customFM, statusLabel: customFMStatus, sentence: sentence)
        }
        if let customIndex = geminiTargets.firstIndex(where: { $0.textView === customGemini }) {
            geminiTargets[customIndex] = GeminiTarget(
                textView: customGemini,
                statusLabel: customGeminiStatus,
                sentence: sentence,
                model: .flash
            )
        }
        if let customIndex = geminiTargets.firstIndex(where: { $0.textView === customGeminiLite }) {
            geminiTargets[customIndex] = GeminiTarget(
                textView: customGeminiLite,
                statusLabel: customGeminiLiteStatus,
                sentence: sentence,
                model: .flashLite
            )
        }
    }

    private func refreshFoundationModelTokens(customOnly: Bool) {
        fmRefreshTask?.cancel()
        fmRefreshTask = Task { [weak self] in
            guard let self else { return }
            guard FoundationModelJapaneseTokenizer.isAvailable else {
                await MainActor.run {
                    self.setFMStatus("Foundation model unavailable.", forAll: !customOnly)
                    if customOnly {
                        self.customFMStatus.text = FoundationModelJapaneseTokenizer.unavailabilityMessage
                    }
                }
                return
            }

            let targets = await MainActor.run {
                customOnly
                    ? self.fmTargets.filter { $0.textView === self.customFM }
                    : self.fmTargets
            }
            for target in targets {
                if Task.isCancelled { return }
                await MainActor.run {
                    target.statusLabel?.text = "Segmenting with foundation model…"
                }
                do {
                    let result = try await FoundationModelJapaneseTokenizer.tokenize(target.sentence)
                    if Task.isCancelled { return }
                    await MainActor.run {
                        guard let textView = target.textView else { return }
                        textView.configure(
                            sentence: target.sentence,
                            lyricFont: self.bodyFont,
                            japaneseTokens: result.tokens
                        )
                        self.attachDefinitionTapHandler(to: textView)
                        target.statusLabel?.text = "\(result.tokens.count) segments"
                    }
                } catch {
                    if Task.isCancelled { return }
                    await MainActor.run {
                        target.statusLabel?.text = error.localizedDescription
                        target.textView?.configure(
                            sentence: target.sentence,
                            lyricFont: self.bodyFont,
                            japaneseTokens: []
                        )
                    }
                }
            }
        }
    }

    private func setFMStatus(_ message: String, forAll: Bool) {
        for target in fmTargets {
            target.statusLabel?.text = message
            if forAll, let textView = target.textView {
                textView.configure(sentence: target.sentence, lyricFont: bodyFont, japaneseTokens: [])
            }
        }
    }

    private func refreshGeminiTokens(customOnly: Bool) {
        geminiRefreshTask?.cancel()
        geminiRefreshTask = Task { [weak self] in
            guard let self else { return }
            guard GeminiJapaneseTokenizer.isConfigured else {
                await MainActor.run {
                    self.setGeminiStatus("Gemini API key is not configured.", forAll: !customOnly)
                }
                return
            }

            let targets = await MainActor.run {
                if customOnly {
                    self.geminiTargets.filter {
                        $0.textView === self.customGemini || $0.textView === self.customGeminiLite
                    }
                } else {
                    self.geminiTargets
                }
            }
            for target in targets {
                if Task.isCancelled { return }
                await MainActor.run {
                    target.statusLabel?.text = "Segmenting with \(target.model.rawValue)…"
                }
                do {
                    let result = try await GeminiJapaneseTokenizer.tokenize(
                        target.sentence,
                        model: target.model,
                        useCache: false
                    )
                    if Task.isCancelled { return }
                    await MainActor.run {
                        guard let textView = target.textView else { return }
                        textView.configure(
                            sentence: target.sentence,
                            lyricFont: self.bodyFont,
                            japaneseTokens: result.tokens
                        )
                        self.attachDefinitionTapHandler(to: textView)
                        target.statusLabel?.text = "\(result.tokens.count) segments"
                    }
                } catch {
                    if Task.isCancelled { return }
                    let fallback = JapaneseTokenizer(backend: .mecab).tokenize(target.sentence)
                    await MainActor.run {
                        guard let textView = target.textView else { return }
                        textView.configure(
                            sentence: target.sentence,
                            lyricFont: self.bodyFont,
                            japaneseTokens: fallback
                        )
                        self.attachDefinitionTapHandler(to: textView)
                        target.statusLabel?.text = "MeCab fallback · \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func setGeminiStatus(_ message: String, forAll: Bool) {
        for target in geminiTargets {
            target.statusLabel?.text = message
            if forAll, let textView = target.textView {
                let fallback = JapaneseTokenizer(backend: .mecab).tokenize(target.sentence)
                textView.configure(sentence: target.sentence, lyricFont: bodyFont, japaneseTokens: fallback)
            }
        }
    }

    private func attachDefinitionTapHandler(to textView: LyricsInsetUnderlineTextView) {
        textView.onWordTapped = { [weak self] surface, wordRect, tIdx in
            self?.presentDefinitionTip(surface: surface, from: textView, wordRect: wordRect, tokenIndex: tIdx)
        }
    }

    /// Same anchoring approach as `LyricsViewController.presentDefinitionTip`.
    private func presentDefinitionTip(
        surface: String,
        from textView: LyricsInsetUnderlineTextView,
        wordRect: CGRect,
        tokenIndex: Int
    ) {
        definitionAnchor?.removeFromSuperview()
        definitionHighlightTextView?.setDefinitionSelectionHighlight(tokenIndex: nil)

        let anchor = UIView()
        anchor.isUserInteractionEnabled = false
        anchor.backgroundColor = .clear
        anchor.translatesAutoresizingMaskIntoConstraints = true
        anchor.frame = textView.convert(wordRect, to: view)
        view.addSubview(anchor)
        definitionAnchor = anchor
        definitionHighlightTextView = textView

        DefinitionTipPresenter.show(surface: surface, sourceView: anchor, in: self) { [weak self, weak textView] in
            self?.definitionAnchor?.removeFromSuperview()
            self?.definitionAnchor = nil
            self?.definitionHighlightTextView = nil
            textView?.setDefinitionSelectionHighlight(tokenIndex: nil)
        }
        textView.setDefinitionSelectionHighlight(tokenIndex: tokenIndex)
    }

    private func clearDefinitionPresentation(animateTip: Bool) {
        DefinitionTipPresenter.dismiss(animateOut: animateTip)
        definitionAnchor?.removeFromSuperview()
        definitionAnchor = nil
        definitionHighlightTextView?.setDefinitionSelectionHighlight(tokenIndex: nil)
        definitionHighlightTextView = nil
    }

}

extension TokenizerLabViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        refreshCustomHighlights()
        refreshFoundationModelTokens(customOnly: true)
        refreshGeminiTokens(customOnly: true)
    }
}
