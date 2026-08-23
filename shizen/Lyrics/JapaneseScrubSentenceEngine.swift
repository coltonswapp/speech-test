//
//  JapaneseScrubSentenceEngine.swift
//  shizen
//
//  JMdict / MeCab / furigana adapter for InteractionKit sentence scrub.
//

import InteractionKit
import UIKit

extension JapaneseToken {
    var asScrubToken: ScrubToken {
        ScrubToken(text: text, range: range)
    }
}

@MainActor
final class JapaneseScrubSentenceEngine: ScrubSentenceEngine {
    static let shared = JapaneseScrubSentenceEngine()

    var tokenizerDidChangeNotification: Notification.Name? { .japaneseTokenizerBackendDidChange }

    func tokenizeSync(_ sentence: String) -> [ScrubToken]? {
        switch JapaneseTokenizerBackend.preferred {
        case .naturalLanguage, .mecab:
            return JapaneseTokenizer(backend: JapaneseTokenizerBackend.preferred)
                .tokenize(sentence)
                .map(\.asScrubToken)
        case .foundationModel, .geminiFlash, .geminiFlashLite, .geminiFlash31Lite:
            return nil
        }
    }

    func tokenizeAsync(_ sentence: String) async -> [ScrubToken] {
        switch JapaneseTokenizerBackend.preferred {
        case .naturalLanguage, .mecab:
            return JapaneseTokenizer(backend: JapaneseTokenizerBackend.preferred)
                .tokenize(sentence)
                .map(\.asScrubToken)
        case .foundationModel, .geminiFlash, .geminiFlashLite, .geminiFlash31Lite:
            let fallback = JapaneseTokenizer(backend: .mecab).tokenize(sentence).map(\.asScrubToken)
            switch JapaneseTokenizerBackend.preferred {
            case .foundationModel:
                guard FoundationModelJapaneseTokenizer.isAvailable else { return fallback }
                do {
                    let result = try await FoundationModelJapaneseTokenizer.tokenize(sentence)
                    return result.tokens.isEmpty ? fallback : result.tokens.map(\.asScrubToken)
                } catch {
                    return fallback
                }
            case .geminiFlash, .geminiFlashLite, .geminiFlash31Lite:
                guard let model = JapaneseTokenizerBackend.preferred.geminiModel else { return fallback }
                guard GeminiJapaneseTokenizer.isConfigured else { return fallback }
                do {
                    let result = try await GeminiJapaneseTokenizer.tokenize(sentence, model: model)
                    return result.tokens.isEmpty ? fallback : result.tokens.map(\.asScrubToken)
                } catch {
                    return fallback
                }
            default:
                return fallback
            }
        }
    }

    func lookupSurfaces(for tokens: [ScrubToken]) -> [String] {
        let japaneseTokens = tokens.map { JapaneseToken(text: $0.text, range: $0.range) }
        return JMDictStore.shared.effectiveLookupSurfaces(for: japaneseTokens)
    }

    func gloss(for surface: String) -> String {
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

    func applyRuby(to attributed: NSMutableAttributedString, text: String, font: UIFont) {
        JapaneseFuriganaBuilder.applyFurigana(to: attributed, text: text, font: font)
    }
}

extension ScrubbableSentenceView {
    convenience init(engine: any ScrubSentenceEngine = JapaneseScrubSentenceEngine.shared) {
        self.init(frame: .zero)
        self.engine = engine
    }

    static func tokenize(sentence: String) async -> [JapaneseToken] {
        let tokens = await JapaneseScrubSentenceEngine.shared.tokenizeAsync(sentence)
        return tokens.map { JapaneseToken(text: $0.text, range: $0.range) }
    }

    func configureWithTokens(
        sentence: String,
        font: UIFont,
        tokens: [JapaneseToken],
        showsFurigana: Bool = true,
        accentSubstring: String? = nil,
        accentColor: UIColor = .systemBlue,
        clearInteraction: Bool = false
    ) {
        configureWithTokens(
            sentence: sentence,
            font: font,
            tokens: tokens.map(\.asScrubToken),
            lookupSurfaces: JMDictStore.shared.effectiveLookupSurfaces(for: tokens),
            showsFurigana: showsFurigana,
            accentSubstring: accentSubstring,
            accentColor: accentColor,
            clearInteraction: clearInteraction
        )
    }
}

extension LyricsInsetUnderlineTextView {
    func configure(
        sentence: String,
        lyricFont: UIFont,
        tokenizer tokenizerOverride: JapaneseTokenizer? = nil,
        showsFurigana: Bool = false,
        accentSubstring: String? = nil,
        accentColor: UIColor = .systemBlue
    ) {
        let tokenizer = tokenizerOverride ?? JapaneseTokenizer()
        let tokens = tokenizer.tokenize(sentence)
        configure(
            sentence: sentence,
            lyricFont: lyricFont,
            tokens: tokens.map(\.asScrubToken),
            lookupSurfaces: JMDictStore.shared.effectiveLookupSurfaces(for: tokens),
            showsFurigana: showsFurigana,
            accentSubstring: accentSubstring,
            accentColor: accentColor,
            applyRuby: showsFurigana
                ? { JapaneseFuriganaBuilder.applyFurigana(to: $0, text: $1, font: $2) }
                : nil
        )
    }

    func configure(
        sentence: String,
        lyricFont: UIFont,
        japaneseTokens precomputedTokens: [JapaneseToken],
        showsFurigana: Bool = false,
        accentSubstring: String? = nil,
        accentColor: UIColor = .systemBlue
    ) {
        configure(
            sentence: sentence,
            lyricFont: lyricFont,
            tokens: precomputedTokens.map(\.asScrubToken),
            lookupSurfaces: JMDictStore.shared.effectiveLookupSurfaces(for: precomputedTokens),
            showsFurigana: showsFurigana,
            accentSubstring: accentSubstring,
            accentColor: accentColor,
            applyRuby: showsFurigana
                ? { JapaneseFuriganaBuilder.applyFurigana(to: $0, text: $1, font: $2) }
                : nil
        )
    }
}
