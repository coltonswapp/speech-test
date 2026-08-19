//
//  JapaneseTokenizer.swift
//  shizen
//

import Foundation
import IPADic
import Mecab_Swift
import NaturalLanguage
import StringTools

// MARK: - Token Model

struct JapaneseToken: Identifiable {
    let id = UUID()
    let text: String
    let range: Range<String.Index>
    var isSelected: Bool = false
}

// MARK: - Backend preference

enum JapaneseTokenizerBackend: String, CaseIterable {
    case naturalLanguage
    case mecab
    case foundationModel
    case geminiFlash
    case geminiFlashLite
    case geminiFlash31Lite

    private static let defaultsKey = "JapaneseTokenizerBackend"

    /// Persisted app-wide tokenizer. Defaults to **MeCab** (IPADic).
    static var preferred: JapaneseTokenizerBackend {
        get {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
                  let b = JapaneseTokenizerBackend(rawValue: raw) else { return .mecab }
            return b
        }
        set {
            guard preferred != newValue else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            NotificationCenter.default.post(name: .japaneseTokenizerBackendDidChange, object: nil)
        }
    }

    var displayName: String {
        switch self {
        case .naturalLanguage: return "NaturalLanguage"
        case .mecab: return "MeCab (IPADic)"
        case .foundationModel: return "Foundation model"
        case .geminiFlash: return "Gemini 2.5 Flash"
        case .geminiFlashLite: return "Gemini 2.5 Flash Lite"
        case .geminiFlash31Lite: return "Gemini 3.1 Flash Lite"
        }
    }

    var shortName: String {
        switch self {
        case .naturalLanguage: return "NL"
        case .mecab: return "MeCab"
        case .foundationModel: return "FM"
        case .geminiFlash: return "G-Flash"
        case .geminiFlashLite: return "G-Lite"
        case .geminiFlash31Lite: return "G-3.1-Lite"
        }
    }

    var geminiModel: GeminiJapaneseTokenizer.Model? {
        switch self {
        case .geminiFlash: return .flash
        case .geminiFlashLite: return .flashLite
        case .geminiFlash31Lite: return .flash31Lite
        default: return nil
        }
    }
}

extension Notification.Name {
    static let japaneseTokenizerBackendDidChange = Notification.Name("JapaneseTokenizerBackendDidChange")
}

// MARK: - LLM segmentation validation

enum JapaneseSegmentationMapping {

    /// Maps model surfaces to tokens only when every surface is an exact input substring in order.
    static func validatedTokens(from surfaces: [String], in text: String) -> [JapaneseToken]? {
        guard !surfaces.isEmpty else {
            print("[JapaneseSegmentationMapping] rejected: no surfaces returned")
            return nil
        }

        var tokens: [JapaneseToken] = []
        tokens.reserveCapacity(surfaces.count)
        var searchStart = text.startIndex

        for surface in surfaces {
            let word = surface.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else {
                print("[JapaneseSegmentationMapping] rejected: blank surface in \(surfaces)")
                return nil
            }
            guard isAcceptableSurface(word) else {
                print("[JapaneseSegmentationMapping] rejected: surface \"\(word)\" contains Latin letters")
                return nil
            }
            guard let range = text.range(of: word, range: searchStart..<text.endIndex) else {
                print("[JapaneseSegmentationMapping] rejected: surface \"\(word)\" not found in order in \"\(text)\" (searched from remaining: \"\(text[searchStart...])\")")
                return nil
            }

            if !isAllPunctuationOrWhitespace(word) {
                tokens.append(JapaneseToken(text: word, range: range))
            }
            searchStart = range.upperBound
        }

        guard coversInput(tokens, in: text) else {
            let significantInput = text.filter { !$0.isWhitespace && !isAllPunctuationOrWhitespace(String($0)) }
            let mapped = tokens.map(\.text).joined().filter { !$0.isWhitespace }
            print("[JapaneseSegmentationMapping] rejected: coverage \(mapped.count)/\(significantInput.count) chars below 90% threshold for \"\(text)\"")
            return nil
        }
        return tokens
    }

    private static func isAcceptableSurface(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        let latinLetters = word.unicodeScalars.filter { scalar in
            (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
        }
        return latinLetters.isEmpty
    }

    private static func isAllPunctuationOrWhitespace(_ word: String) -> Bool {
        word.unicodeScalars.allSatisfy { scalar in
            CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
    }

    private static func coversInput(_ tokens: [JapaneseToken], in text: String) -> Bool {
        let significantInput = text.filter { !$0.isWhitespace && !isAllPunctuationOrWhitespace(String($0)) }
        guard !significantInput.isEmpty else { return true }

        let mapped = tokens.map(\.text).joined().filter { !$0.isWhitespace }
        guard !mapped.isEmpty else { return false }
        return mapped.count >= Int(Double(significantInput.count) * 0.9)
    }

    /// Glues the colloquial explanatory ending ん+です/だ (and a following softener like けど/か/よ/から/が)
    /// into a single tappable token, since a learner looking up "ん" or "です" alone gets a useless hit.
    /// Backstops the Gemini prompt instructions for cases where the model doesn't comply.
    static func mergeColloquialExplanatorySuffixes(_ tokens: [JapaneseToken], in fullText: String) -> [JapaneseToken] {
        guard tokens.count >= 2 else { return tokens }
        var t = tokens
        var changed = true
        while changed {
            changed = false
            var out: [JapaneseToken] = []
            out.reserveCapacity(t.count)
            var i = 0
            while i < t.count {
                if i + 1 < t.count,
                   let merged = mergeExplanatorySuffixPairIfNeeded(t[i], t[i + 1], in: fullText) {
                    out.append(merged)
                    i += 2
                    changed = true
                } else {
                    out.append(t[i])
                    i += 1
                }
            }
            t = out
        }
        return t
    }

    private static let explanatoryCopulas: Set<String> = ["です", "だ"]
    private static let explanatorySofteners: Set<String> = ["けど", "か", "よ", "から", "が"]

    private static func mergeExplanatorySuffixPairIfNeeded(
        _ a: JapaneseToken,
        _ b: JapaneseToken,
        in fullText: String
    ) -> JapaneseToken? {
        guard a.range.upperBound == b.range.lowerBound else { return nil }

        let isNGlue = a.text == "ん" && explanatoryCopulas.contains(b.text)
        let isSoftenerGlue = (a.text.hasPrefix("ん") && (a.text.hasSuffix("です") || a.text.hasSuffix("だ")))
            && explanatorySofteners.contains(b.text)
        guard isNGlue || isSoftenerGlue else { return nil }

        let mergedRange = a.range.lowerBound..<b.range.upperBound
        let merged = String(fullText[mergedRange])
        guard !merged.isEmpty else { return nil }
        return JapaneseToken(text: merged, range: mergedRange)
    }
}

// MARK: - Tokenizer

final class JapaneseTokenizer {

    private let backend: JapaneseTokenizerBackend
    private let nlTokenizer: NLTokenizer

    /// Greetings and fixed phrases: final は is not the topic marker and must not be split from the rest.
    private static let doNotSplitTrailingHa: Set<String> = [
        "こんにちは", "こんばんは", "おはよう", "おはようございます", "ありがとう", "ありがとうございます",
    ]

    init(backend: JapaneseTokenizerBackend = .preferred) {
        self.backend = backend
        nlTokenizer = NLTokenizer(unit: .word)
        nlTokenizer.setLanguage(.japanese)
    }

    func tokenize(_ text: String) -> [JapaneseToken] {
        switch backend {
        case .mecab:
            return Self.tokenizeWithMecab(text, nlFallback: nlTokenizer)
        case .naturalLanguage:
            return Self.tokenizeWithNaturalLanguage(text, tokenizer: nlTokenizer)
        case .foundationModel, .geminiFlash, .geminiFlashLite, .geminiFlash31Lite:
            return Self.tokenizeWithMecab(text, nlFallback: nlTokenizer)
        }
    }

    // MARK: - Side-by-side comparison (always runs both engines)

    /// Surfaces only — useful for debugging and A/B display.
    static func comparisonTokenSurfaces(for text: String) -> (nl: [String], mecab: [String]) {
        let nlTok = NLTokenizer(unit: .word)
        nlTok.setLanguage(.japanese)
        let nl = Self.tokenizeWithNaturalLanguage(text, tokenizer: nlTok).map(\.text)
        let mc = Self.tokenizeWithMecab(text, nlFallback: nlTok).map(\.text)
        return (nl, mc)
    }

    // MARK: - MeCab (shared, locked — libmecab is not thread-safe)

    private static let mecabLock = NSLock()
    private static var mecabEngine: Tokenizer?
    private static var mecabInitFailed = false

    private static func tokenizeWithMecab(_ text: String, nlFallback nlTokenizer: NLTokenizer) -> [JapaneseToken] {
        if mecabInitFailed {
            return tokenizeWithNaturalLanguage(text, tokenizer: nlTokenizer)
        }
        mecabLock.lock()
        defer { mecabLock.unlock() }
        if mecabEngine == nil {
            do {
                mecabEngine = try Tokenizer(dictionary: IPADic())
            } catch {
                mecabInitFailed = true
                return tokenizeWithNaturalLanguage(text, tokenizer: nlTokenizer)
            }
        }
        guard let engine = mecabEngine else {
            return tokenizeWithNaturalLanguage(text, tokenizer: nlTokenizer)
        }

        let annotations = engine.tokenize(text: text, transliteration: .hiragana)
        var tokens: [JapaneseToken] = []
        tokens.reserveCapacity(annotations.count)
        for ann in annotations {
            let word = ann.base
            let isAllPuncOrSpace = word.unicodeScalars.allSatisfy { s in
                CharacterSet.punctuationCharacters.contains(s)
                    || CharacterSet.whitespacesAndNewlines.contains(s)
            }
            if !isAllPuncOrSpace, !word.isEmpty {
                tokens.append(JapaneseToken(text: word, range: ann.range))
            }
        }
        return postProcessTokens(tokens, in: text)
    }

    /// Shared cleanup for both NL and MeCab token streams (inflection glue, intentional splits).
    private static func postProcessTokens(_ tokens: [JapaneseToken], in text: String) -> [JapaneseToken] {
        var t = splitFinalHaParticle(from: tokens, in: text)
        t = splitAdjectiveNounForLookup(from: t, in: text)
        t = mergeSplitInflectionTokens(from: t, in: text)
        return t
    }

    // MARK: - Natural Language + heuristics (original pipeline)

    private static func tokenizeWithNaturalLanguage(_ text: String, tokenizer: NLTokenizer) -> [JapaneseToken] {
        tokenizer.string = text
        var tokens: [JapaneseToken] = []

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range])
            let isAllPuncOrSpace = word.unicodeScalars.allSatisfy { s in
                CharacterSet.punctuationCharacters.contains(s)
                    || CharacterSet.whitespacesAndNewlines.contains(s)
            }
            if !isAllPuncOrSpace, !word.isEmpty {
                tokens.append(JapaneseToken(text: word, range: range))
            }
            return true
        }
        return postProcessTokens(tokens, in: text)
    }

    /// `NLTokenizer` often splits te-forms, negatives, and polite endings (歩い+て, 行き+ましょう). Rejoin those
    /// into one tappable unit when spans are contiguous; also merge any run that forms an exact JMdict headword
    /// (e.g. お+釣+り), except pairs marked `JMDictStore.mustKeepSplit`.
    private static func mergeSplitInflectionTokens(from tokens: [JapaneseToken], in fullText: String) -> [JapaneseToken] {
        guard tokens.count >= 2 else { return tokens }
        var t = tokens
        var changed = true
        while changed {
            changed = false
            var out: [JapaneseToken] = []
            out.reserveCapacity(t.count)
            var i = 0
            while i < t.count {
                if i + 1 < t.count,
                   let merged = mergePairIfNeeded(t[i], t[i + 1], in: fullText) {
                    out.append(merged)
                    i += 2
                    changed = true
                } else {
                    out.append(t[i])
                    i += 1
                }
            }
            t = out
        }
        return t
    }

    private static func mergePairIfNeeded(_ a: JapaneseToken, _ b: JapaneseToken, in fullText: String) -> JapaneseToken? {
        guard a.range.upperBound == b.range.lowerBound else { return nil }
        let mergedRange = a.range.lowerBound..<b.range.upperBound
        let merged = String(fullText[mergedRange])
        guard !merged.isEmpty else { return nil }
        if JMDictStore.mustKeepSplit(mergedSurface: merged) { return nil }
        if b.text == "は" { return nil }
        let dictHit = JMDictStore.shared.hasExactLexicalMatch(for: merged)
        let glue = shouldGlueInflectionSuffix(firstText: a.text, secondText: b.text)
        guard glue || dictHit else { return nil }
        return JapaneseToken(text: merged, range: mergedRange)
    }

    private static func shouldGlueInflectionSuffix(firstText: String, secondText: String) -> Bool {
        switch secondText {
        case "て", "ちゃ", "ちゃう", "ちゃい", "ちゃった", "ちゃって":
            return true
        case "た":
            return true
        case "ない", "なかった", "なくて", "なければ", "なくちゃ", "なきゃ", "なくちゃいけない", "なきゃいけない":
            return true
        case "ましょう", "ます", "ました", "ません", "ませんでした":
            return true
        case "たい", "たく", "たかった":
            return true
        case "で":
            guard let last = firstText.last else { return false }
            return last == "ん" || last == "い" || last == "っ"
        default:
            return false
        }
    }

    private static let splitTwoPartLookupPhrases: [(whole: String, first: String, second: String)] = [
        ("いい天気", "いい", "天気"),
        ("良い天気", "良い", "天気"),
    ]

    private static func splitAdjectiveNounForLookup(
        from tokens: [JapaneseToken],
        in fullText: String
    ) -> [JapaneseToken] {
        var out: [JapaneseToken] = []
        out.reserveCapacity(tokens.count + 1)
        for t in tokens {
            if let spec = splitTwoPartLookupPhrases.first(where: { t.text == $0.whole }) {
                let r = t.range
                guard String(fullText[r]) == t.text,
                      let mid = fullText.index(
                          r.lowerBound,
                          offsetBy: spec.first.count,
                          limitedBy: r.upperBound
                      ),
                      mid < r.upperBound
                else {
                    out.append(t)
                    continue
                }
                out.append(JapaneseToken(text: spec.first, range: r.lowerBound..<mid))
                out.append(JapaneseToken(text: spec.second, range: mid..<r.upperBound))
            } else {
                out.append(t)
            }
        }
        return out
    }

    private static func splitFinalHaParticle(from tokens: [JapaneseToken], in fullText: String) -> [JapaneseToken] {
        var out: [JapaneseToken] = []
        out.reserveCapacity(tokens.count + 2)
        for t in tokens {
            let s = t.text
            if s == "は" || s.count < 2 {
                out.append(t)
                continue
            }
            if Self.doNotSplitTrailingHa.contains(s) {
                out.append(t)
                continue
            }
            if !s.hasSuffix("は") {
                out.append(t)
                continue
            }
            let base = String(s.dropLast())
            if base.isEmpty {
                out.append(t)
                continue
            }
            let r = t.range
            let haStart = fullText.index(before: r.upperBound)
            guard fullText[haStart..<r.upperBound] == "は" else {
                out.append(t)
                continue
            }
            let prefixR = r.lowerBound..<haStart
            out.append(JapaneseToken(text: base, range: prefixR))
            out.append(JapaneseToken(text: "は", range: haStart..<r.upperBound))
        }
        return out
    }
}

// MARK: - Furigana (shared MeCab engine)

extension JapaneseTokenizer {
    /// MeCab tokenization + JMDict reading lookups are expensive and depend only on `text` —
    /// never on font. Callers that rebuild furigana purely for a font/weight change (e.g. the
    /// emphasis animation in DialogueExperimentViewController, which reruns this on nearly every
    /// display-link tick) would otherwise redo this work every frame, which is what was causing
    /// the animation to drop frames. Cache by text so a font-only change is a cache hit.
    ///
    /// Ranges are cached as UTF-16 `NSRange`s, not `Range<String.Index>`: a `String.Index` is
    /// only valid for the exact string instance it was created from, and a cache hit hands the
    /// result to a different (equal-content) instance whose backing storage may differ.
    private final class FuriganaAnnotationsBox {
        let entries: [(reading: String, nsRange: NSRange)]
        init(_ entries: [(reading: String, nsRange: NSRange)]) { self.entries = entries }

        func annotations(in text: String) -> [FuriganaAnnotation] {
            entries.compactMap { entry in
                guard let range = Range(entry.nsRange, in: text) else { return nil }
                return FuriganaAnnotation(reading: entry.reading, range: range)
            }
        }
    }

    private static let furiganaAnnotationsCache = NSCache<NSString, FuriganaAnnotationsBox>()

    static func furiganaAnnotations(for text: String) -> [FuriganaAnnotation] {
        guard !text.isEmpty else { return [] }
        if mecabInitFailed { return [] }

        let cacheKey = text as NSString
        if let cached = furiganaAnnotationsCache.object(forKey: cacheKey) {
            return cached.annotations(in: text)
        }

        mecabLock.lock()
        defer { mecabLock.unlock() }

        if let cached = furiganaAnnotationsCache.object(forKey: cacheKey) {
            return cached.annotations(in: text)
        }

        if mecabEngine == nil {
            do {
                mecabEngine = try Tokenizer(dictionary: IPADic())
            } catch {
                mecabInitFailed = true
                return []
            }
        }
        guard let engine = mecabEngine else { return [] }

        let tokenAnnotations = engine.tokenize(text: text, transliteration: .hiragana)
        let annotations = engine.furiganaAnnotations(for: text, transliteration: .hiragana, options: [.kanjiOnly])
        let compounds = kanjiCompounds(in: tokenAnnotations)

        var result: [FuriganaAnnotation] = []
        result.reserveCapacity(annotations.count)
        var consumedCompounds = Set<Int>()
        for annotation in annotations {
            // MeCab split a dictionary compound across tokens (一+人): collapse the contained
            // annotations into one ruby spanning the whole compound, since jukujikun readings
            // (ひとり) cannot be split per kanji.
            if let ci = compounds.firstIndex(where: { compound in
                compound.range.lowerBound <= annotation.range.lowerBound
                    && compound.range.upperBound >= annotation.range.upperBound
            }) {
                if consumedCompounds.insert(ci).inserted {
                    result.append(FuriganaAnnotation(reading: compounds[ci].reading, range: compounds[ci].range))
                }
                continue
            }

            let rubySurface = String(text[annotation.range])
            let parent = tokenAnnotations.first { ann in
                ann.range.lowerBound <= annotation.range.lowerBound
                    && ann.range.upperBound >= annotation.range.upperBound
            }
            let wordSurface = parent.map(\.base) ?? rubySurface
            let wordReading = parent?.reading ?? annotation.reading
            let wordDictionaryForm = parent?.dictionaryForm
            let reading = JMDictStore.shared.preferredKanjiRubyReading(
                wordSurface: wordSurface,
                wordReading: wordReading,
                rubySurface: rubySurface,
                rubyReading: annotation.reading,
                in: text,
                at: annotation.range,
                wordDictionaryForm: wordDictionaryForm
            )
            if reading != annotation.reading {
                result.append(FuriganaAnnotation(reading: reading, range: annotation.range))
            } else {
                result.append(annotation)
            }
        }
        furiganaAnnotationsCache.setObject(
            FuriganaAnnotationsBox(result.map { (reading: $0.reading, nsRange: NSRange($0.range, in: text)) }),
            forKey: cacheKey
        )
        return result
    }

    // MARK: - Compound merge (dictionary-driven)

    /// A run of adjacent kanji-only MeCab tokens whose concatenation is a JMdict headword
    /// (一+人 → 一人, 案内+板 → 案内板), rendered as a single ruby annotation.
    private struct KanjiCompound {
        let range: Range<String.Index>
        let reading: String
    }

    private static let compoundMergeMaxRunLength = 4

    /// Numeral+counter readings are compositional (三人 → さんにん) and context-sensitive
    /// (十分 = じゅっぷん vs じゅうぶん), so MeCab reads them better than a score-ranked dictionary
    /// lookup; numeral-led runs merge only for the closed jukujikun class.
    private static let numeralJukujikunCompounds: Set<String> = ["一人", "二人", "二十歳"]

    private static func kanjiCompounds(in tokens: [Annotation]) -> [KanjiCompound] {
        var out: [KanjiCompound] = []
        var i = 0
        while i < tokens.count {
            guard isKanjiOnlySurface(tokens[i].base) else {
                i += 1
                continue
            }
            var merged: (endIndex: Int, compound: KanjiCompound)?
            let upper = min(i + compoundMergeMaxRunLength, tokens.count)
            for j in stride(from: upper - 1, through: i + 1, by: -1) {
                let run = Array(tokens[i...j])
                guard isContiguousKanjiRun(run) else { continue }
                let surface = run.map(\.base).joined()
                if startsWithNumeral(surface), !numeralJukujikunCompounds.contains(surface) { continue }
                guard let reading = JMDictStore.shared.compoundMergedReading(
                    forSurface: surface,
                    mecabReading: run.map(\.reading).joined()
                ) else { continue }
                let range = run[0].range.lowerBound..<run[run.count - 1].range.upperBound
                merged = (j, KanjiCompound(range: range, reading: reading))
                break
            }
            if let merged {
                out.append(merged.compound)
                i = merged.endIndex + 1
            } else {
                i += 1
            }
        }
        return out
    }

    private static func isContiguousKanjiRun(_ run: [Annotation]) -> Bool {
        guard run.allSatisfy({ isKanjiOnlySurface($0.base) }) else { return false }
        for k in 1..<run.count where run[k - 1].range.upperBound != run[k].range.lowerBound {
            return false
        }
        return true
    }

    private static func isKanjiOnlySurface(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        return s.unicodeScalars.allSatisfy { u in
            (0x3400...0x4DBF).contains(u.value) || (0x4E00...0x9FFF).contains(u.value) || u.value == 0x3005
        }
    }

    private static func startsWithNumeral(_ s: String) -> Bool {
        guard let first = s.first else { return false }
        return "〇零一二三四五六七八九十百千万億何幾".contains(first)
    }
}
