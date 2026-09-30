//
//  ContextualGlossProviding.swift
//  shizen
//
//  Backend-agnostic contract for contextual gloss providers,
//  so WordDictionaryDetailView can swap between on-device-only and cloud-backed fallback behavior.
//

import Foundation

/// "the verb to work", "the verb, to move", and `the verb "to work"` become "to work".
/// A note that is only a part of speech ("the verb") becomes empty.
func glossWithoutVerbLabel(_ text: String) -> String {
    var result = text
    let quoted = #"(?i)\b(?:the|a)\s+verb\s*(?:[,:;]|meaning|that\s+means)?\s*["“‘']\s*(to\b[^"”’'\n)]*)["”’']"#
    let plain = #"(?i)\b(?:the|a)\s+verb\s*(?:[,:;]|meaning|that\s+means)?\s*(?=to\b)"#
    if let regex = try? NSRegularExpression(pattern: quoted) {
        let range = NSRange(result.startIndex..., in: result)
        result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1")
    }
    if let regex = try? NSRegularExpression(pattern: plain) {
        let range = NSRange(result.startIndex..., in: result)
        result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
    }
    let bare = #"(?i)^\s*(?:the|a)\s+(?:verb|noun|adjective|adverb)\s*[.…]?\s*$"#
    if let regex = try? NSRegularExpression(pattern: bare),
       regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)) != nil {
        return ""
    }
    return result
        .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// How the learner arrived at the word. Drives the card title and the prompt framing.
enum ContextualGlossFraming: String, Equatable {
    /// Reading the token inside a sentence they can see (sentence scrub, lyrics, grammar example).
    case inSentence
    /// Opened the word on its own (vocabulary list, search, saved word). A sentence, if any, is only a usage example.
    case word
}

/// Another Japanese word worth opening from the gloss, such as 引っ越す for 引っ越し.
struct ContextualRelatedWord: Equatable {
    let word: String
    let note: String

    static func sanitized(
        from candidates: [(String, String)],
        surface: String,
        dictionaryForm: String?
    ) -> [ContextualRelatedWord] {
        let excluded = Set(
            [surface, dictionaryForm ?? ""]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        var seen = Set<String>()
        var words: [ContextualRelatedWord] = []
        for candidate in candidates {
            let word = candidate.0.trimmingCharacters(in: .whitespacesAndNewlines)
            guard word.count <= 12, isLookupWord(word), !excluded.contains(word), seen.insert(word).inserted else {
                continue
            }
            if particleBlocklist.contains(word) { continue }
            var note = glossWithoutVerbLabel(candidate.1)
            if note == word || note.count > 40 { note = "" }
            words.append(ContextualRelatedWord(word: word, note: note))
            if words.count == 2 { break }
        }
        return words
    }

    private static let particleBlocklist: Set<String> = [
        "は", "が", "を", "に", "で", "と", "も", "か", "よ", "ね", "の", "へ", "や", "わ",
        "から", "まで", "より", "って",
    ]

    private static func isLookupWord(_ word: String) -> Bool {
        let scalars = word.unicodeScalars
        guard scalars.contains(where: isJapanese) else { return false }
        return scalars.allSatisfy { scalar in
            isJapanese(scalar) || scalar == "々" || scalar == "ー"
        }
    }

    private static func isJapanese(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x309F, // hiragana
             0x30A0...0x30FF, // katakana
             0x4E00...0x9FFF, // CJK
             0x3400...0x4DBF:
            return true
        default:
            return false
        }
    }
}

struct ContextualGlossRequest: Equatable {
    let sentence: String
    let surface: String
    let dictionaryForm: String?
    let dictionaryGloss: String?
    let framing: ContextualGlossFraming
    /// When true, the provider also names a dictionary headword for this use of `surface`.
    let requestsHeadword: Bool

    init(
        sentence: String,
        surface: String,
        dictionaryForm: String?,
        dictionaryGloss: String?,
        framing: ContextualGlossFraming,
        requestsHeadword: Bool = false
    ) {
        self.sentence = sentence
        self.surface = surface
        self.dictionaryForm = dictionaryForm
        self.dictionaryGloss = dictionaryGloss
        self.framing = framing
        self.requestsHeadword = requestsHeadword
    }
}

struct ContextualGlossResult: Equatable {
    let meaning: String
    let grammarNote: String
    let relatedWords: [ContextualRelatedWord]
    /// Standard dictionary form for this use, or empty when none was requested or none exists.
    let headword: String

    init(
        meaning: String,
        grammarNote: String,
        relatedWords: [ContextualRelatedWord],
        headword: String = ""
    ) {
        self.meaning = meaning
        self.grammarNote = grammarNote
        self.relatedWords = relatedWords
        self.headword = headword
    }
}

enum ContextualHeadword {
    /// Japanese-script headword, or empty when the model returned something we cannot look up.
    static func sanitized(_ raw: String) -> String {
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, word.count <= 12 else { return "" }
        let scalars = word.unicodeScalars
        guard scalars.allSatisfy(isJapaneseScript) else { return "" }
        return word
    }

    private static func isJapaneseScript(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x309F, // hiragana
             0x30A0...0x30FF, // katakana
             0x4E00...0x9FFF, // CJK
             0x3400...0x4DBF, // CJK extension A
             0x3005: // 々
            return true
        default:
            return false
        }
    }
}

protocol ContextualGlossProviding {
    var isAvailable: Bool { get }
    func cachedResult(for request: ContextualGlossRequest) async -> ContextualGlossResult?
    func explain(_ request: ContextualGlossRequest) async throws -> ContextualGlossResult
}

/// Today's default behavior: on-device only, hides the contextual card when Apple Intelligence
/// is unavailable rather than falling back to a cloud call.
struct OnDeviceOnlyContextualGlossProvider: ContextualGlossProviding {
    var isAvailable: Bool {
        FoundationModelContextualGloss.isAvailable
    }

    func cachedResult(for request: ContextualGlossRequest) async -> ContextualGlossResult? {
        guard let cached = await FoundationModelContextualGloss.cachedResult(for: request.asFoundationModelRequest) else {
            return nil
        }
        return cached.asContextualGlossResult
    }

    func explain(_ request: ContextualGlossRequest) async throws -> ContextualGlossResult {
        try await FoundationModelContextualGloss.explain(request.asFoundationModelRequest).asContextualGlossResult
    }
}

/// Cloud-only: always asks Gemini, never touches the on-device model.
struct GeminiOnlyContextualGlossProvider: ContextualGlossProviding {
    var isAvailable: Bool {
        GeminiContextualGloss.isConfigured
    }

    func cachedResult(for request: ContextualGlossRequest) async -> ContextualGlossResult? {
        await GeminiContextualGloss.cachedResult(for: request.asGeminiRequest)?.asContextualGlossResult
    }

    func explain(_ request: ContextualGlossRequest) async throws -> ContextualGlossResult {
        try await GeminiContextualGloss.explain(request.asGeminiRequest).asContextualGlossResult
    }
}

/// Tries the on-device model first (private, no network) and falls back to Gemini when
/// Apple Intelligence is unavailable or the on-device call fails — used by the sentence-scrub
/// experiment, which wants contextual insights to work even on devices without Apple Intelligence.
struct HybridContextualGlossProvider: ContextualGlossProviding {
    var isAvailable: Bool {
        FoundationModelContextualGloss.isAvailable || GeminiContextualGloss.isConfigured
    }

    func cachedResult(for request: ContextualGlossRequest) async -> ContextualGlossResult? {
        if FoundationModelContextualGloss.isAvailable,
           let cached = await FoundationModelContextualGloss.cachedResult(for: request.asFoundationModelRequest) {
            return cached.asContextualGlossResult
        }
        if let cached = await GeminiContextualGloss.cachedResult(for: request.asGeminiRequest) {
            return cached.asContextualGlossResult
        }
        return nil
    }

    func explain(_ request: ContextualGlossRequest) async throws -> ContextualGlossResult {
        if FoundationModelContextualGloss.isAvailable {
            do {
                return try await FoundationModelContextualGloss.explain(request.asFoundationModelRequest).asContextualGlossResult
            } catch {
                print("[HybridContextualGlossProvider] on-device gloss failed (\(error)); falling back to Gemini")
            }
        }
        return try await GeminiContextualGloss.explain(request.asGeminiRequest).asContextualGlossResult
    }
}

// MARK: - Backend preference

enum ContextualGlossBackend: String, CaseIterable {
    case onDevice
    case gemini
    case hybrid

    private static let defaultsKey = "ContextualGlossBackend"

    /// Persisted app-wide contextual gloss backend. Defaults to **hybrid** (on-device first, Gemini fallback).
    static var preferred: ContextualGlossBackend {
        get {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
                  let backend = ContextualGlossBackend(rawValue: raw) else { return .hybrid }
            return backend
        }
        set {
            guard preferred != newValue else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            NotificationCenter.default.post(name: .contextualGlossBackendDidChange, object: nil)
        }
    }

    var displayName: String {
        switch self {
        case .onDevice: return "On-device only"
        case .gemini: return "Gemini only"
        case .hybrid: return "Hybrid (on-device, Gemini fallback)"
        }
    }

    var provider: ContextualGlossProviding {
        switch self {
        case .onDevice: return OnDeviceOnlyContextualGlossProvider()
        case .gemini: return GeminiOnlyContextualGlossProvider()
        case .hybrid: return HybridContextualGlossProvider()
        }
    }
}

extension Notification.Name {
    static let contextualGlossBackendDidChange = Notification.Name("ContextualGlossBackendDidChange")
}

private extension ContextualGlossRequest {
    var asFoundationModelRequest: FoundationModelContextualGloss.Request {
        .init(
            sentence: sentence,
            surface: surface,
            dictionaryForm: dictionaryForm,
            dictionaryGloss: dictionaryGloss,
            framing: framing,
            requestsHeadword: requestsHeadword
        )
    }

    var asGeminiRequest: GeminiContextualGloss.Request {
        .init(
            sentence: sentence,
            surface: surface,
            dictionaryForm: dictionaryForm,
            dictionaryGloss: dictionaryGloss,
            framing: framing,
            requestsHeadword: requestsHeadword
        )
    }
}

private extension FoundationModelContextualGloss.Result {
    var asContextualGlossResult: ContextualGlossResult {
        .init(meaning: meaning, grammarNote: grammarNote, relatedWords: relatedWords, headword: headword)
    }
}

private extension GeminiContextualGloss.Result {
    var asContextualGlossResult: ContextualGlossResult {
        .init(meaning: meaning, grammarNote: grammarNote, relatedWords: relatedWords, headword: headword)
    }
}
