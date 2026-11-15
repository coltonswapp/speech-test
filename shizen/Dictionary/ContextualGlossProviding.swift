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
        let focus = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        var words: [ContextualRelatedWord] = []
        for candidate in candidates {
            let word = candidate.0.trimmingCharacters(in: .whitespacesAndNewlines)
            guard word.count <= 12, isLookupWord(word), !excluded.contains(word), seen.insert(word).inserted else {
                continue
            }
            if particleBlocklist.contains(word) { continue }
            if word.count == 1, focus.contains(word) { continue }
            var note = glossWithoutVerbLabel(candidate.1)
            if note == word || note.count > 40 { note = "" }
            words.append(ContextualRelatedWord(word: word, note: note))
        }
        return Array(prioritized(words, surface: focus).prefix(2))
    }

    /// Same rule as the gateway `selectRelatedWords`: a complete split of the surface
    /// leads, and other character chunks of that split are dropped. Nothing is invented.
    private static func prioritized(
        _ words: [ContextualRelatedWord],
        surface: String
    ) -> [ContextualRelatedWord] {
        guard let cover = componentCover(surface: surface, words: words.map(\.word)) else {
            return words
        }
        let byWord = Dictionary(words.map { ($0.word, $0) }, uniquingKeysWith: { first, _ in first })
        var ordered: [ContextualRelatedWord] = []
        var used = Set<String>()
        for word in cover {
            guard let item = byWord[word], used.insert(word).inserted else { continue }
            ordered.append(item)
        }
        for item in words where used.insert(item.word).inserted {
            if surface.contains(item.word) { continue }
            ordered.append(item)
        }
        return ordered
    }

    /// Component words that tile `surface`, preferring fewer and longer pieces.
    private static func componentCover(surface: String, words: [String]) -> [String]? {
        let chars = Array(surface)
        let count = chars.count
        var seen = Set<String>()
        let pieces = words.filter { piece in
            let length = piece.count
            guard length >= 2, length < count, seen.insert(piece).inserted else { return false }
            return surface.contains(piece)
        }
        guard pieces.count >= 2 else { return nil }

        var at = Array(repeating: [String](), count: count)
        for piece in pieces {
            let pieceChars = Array(piece)
            let length = pieceChars.count
            guard length > 0 else { continue }
            var index = 0
            while index + length <= count {
                if Array(chars[index..<(index + length)]) == pieceChars {
                    at[index].append(piece)
                }
                index += 1
            }
        }
        for index in at.indices {
            at[index].sort { $0.count > $1.count }
        }

        struct Choice {
            var count: Int
            var path: [String]
        }
        var best = Array(repeating: Choice(count: Int.max, path: []), count: count + 1)
        best[count] = Choice(count: 0, path: [])
        if count > 0 {
            for index in stride(from: count - 1, through: 0, by: -1) {
                for piece in at[index] {
                    let length = piece.count
                    let next = best[index + length]
                    guard next.count < Int.max else { continue }
                    let partCount = next.count + 1
                    let path = [piece] + next.path
                    let current = best[index]
                    if partCount < current.count || (partCount == current.count && longerEarlier(path, than: current.path)) {
                        best[index] = Choice(count: partCount, path: path)
                    }
                }
            }
        }
        let chosen = best[0]
        guard chosen.count >= 2, chosen.count < Int.max, chosen.path.joined() == surface else { return nil }
        return chosen.path
    }

    private static func longerEarlier(_ path: [String], than other: [String]) -> Bool {
        let left = path.map(\.count)
        let right = other.map(\.count)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
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
