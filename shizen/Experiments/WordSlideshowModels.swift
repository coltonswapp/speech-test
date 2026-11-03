//
//  WordSlideshowModels.swift
//  shizen
//
//  Deck model for prompt-generated word slideshows: "days of the week",
//  "opposites", and so on. The model only picks words and short meanings;
//  WordSlideshowValidator checks them against JMdict before they render.
//

import Foundation

/// How generated words are laid out across slides.
enum WordSlideshowLayout: String, CaseIterable {
    /// One word per slide.
    case single
    /// Two words stacked per slide, in list order.
    case double
    /// Two related words stacked per slide (opposites, synonyms, look-alikes).
    case pairs

    var title: String {
        switch self {
        case .single: return "1 per slide"
        case .double: return "2 per slide"
        case .pairs: return "Pairs"
        }
    }

    var subtitle: String {
        switch self {
        case .single: return "Each word gets its own slide."
        case .double: return "Two words stacked per slide, in order."
        case .pairs: return "Two related words per slide, e.g. opposites."
        }
    }

    var wordsPerSlide: Int {
        self == .single ? 1 : 2
    }
}

struct WordSlideshowWord: Equatable {
    var expression: String
    var meaning: String
    /// Kana reading from JMdict; empty when the word isn't in the dictionary.
    var reading: String = ""
    /// JMdict glosses for this word, most common sense first; empty when not found.
    var dictionaryMeanings: [String] = []
    /// False when `meaning` isn't one of `dictionaryMeanings`.
    var meaningMatchesDictionary = true
    /// Optional example sentence that uses the word; empty when examples are off.
    var exampleJapanese: String = ""
    var exampleEnglish: String = ""
    /// Problems the review screen shows, e.g. "Not in the dictionary".
    var warnings: [String] = []

    var isVerified: Bool { warnings.isEmpty }

    var hasExample: Bool {
        !exampleJapanese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Where the word appears in its example: the exact form, else the stem of a
    /// conjugated verb or adjective (食べる → 食べ in 食べました). Nil when absent.
    var exampleWordRange: NSRange? {
        let sentence = exampleJapanese as NSString
        let exact = sentence.range(of: expression)
        if exact.location != NSNotFound { return exact }
        guard expression.count >= 2 else { return nil }
        let stem = String(expression.dropLast())
        let stemRange = sentence.range(of: stem)
        return stemRange.location == NSNotFound ? nil : stemRange
    }

    /// True when the example is little more than the word itself (戦う。, 広いです。),
    /// so it doesn't show what the word means.
    var exampleIsTooBare: Bool {
        guard hasExample else { return false }
        let filler: Set<Character> = ["。", "、", "！", "？", "!", "?", ".", " ", "　"]
        let sentence = exampleJapanese as NSString
        let rest = exampleWordRange.map { sentence.replacingCharacters(in: $0, with: "") } ?? exampleJapanese
        var context = rest.filter { !filler.contains($0) }
        for ending in ["でした", "です", "だ", "ます", "ました"] where context.hasSuffix(ending) {
            context.removeLast(ending.count)
            break
        }
        return context.count < 3
    }
}

/// The words on one slide: one, or two stacked.
struct WordSlideshowGroup: Equatable {
    var words: [WordSlideshowWord]
    /// Group-level problems, e.g. a pair whose words are different word types.
    var warnings: [String] = []

    var hasWarnings: Bool {
        !warnings.isEmpty || words.contains { !$0.isVerified }
    }
}

/// Mutable so review-screen edits stick for live cards and export rebuilds.
final class WordSlideshowDeck {
    var title: String
    /// Middle line of the hook slide, between "Do you know" and "in Japanese?".
    var hookPhrase: String
    let layout: WordSlideshowLayout
    var groups: [WordSlideshowGroup]
    /// Each word carries an example sentence (Japanese + English).
    var includesExamples: Bool

    init(
        title: String,
        hookPhrase: String = "",
        layout: WordSlideshowLayout,
        groups: [WordSlideshowGroup],
        includesExamples: Bool = false
    ) {
        self.title = title
        self.hookPhrase = hookPhrase
        self.layout = layout
        self.groups = groups
        self.includesExamples = includesExamples
    }

    /// Splits an ordered list into slides for `.single` / `.double`.
    convenience init(
        title: String,
        hookPhrase: String = "",
        layout: WordSlideshowLayout,
        words: [WordSlideshowWord]
    ) {
        let size = layout.wordsPerSlide
        let groups = stride(from: 0, to: words.count, by: size).map { start in
            WordSlideshowGroup(words: Array(words[start..<min(start + size, words.count)]))
        }
        self.init(title: title, hookPhrase: hookPhrase, layout: layout, groups: groups)
    }

    /// The model sometimes echoes the slide's fixed lines or the slashes from an
    /// example ("Do you know / these body parts / in Japanese?"). Keep only the middle.
    static func cleanedHookPhrase(_ text: String) -> String {
        var phrase = text.replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let prefixes = ["do you know", "do you"]
        let suffixes = ["in japanese?", "in japanese"]
        phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in prefixes where phrase.lowercased().hasPrefix(prefix) {
            phrase.removeFirst(prefix.count)
            break
        }
        phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in suffixes where phrase.lowercased().hasSuffix(suffix) {
            phrase.removeLast(suffix.count)
            break
        }
        phrase = phrase.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "?\"“”")))
        return phrase.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    /// The hook's middle line, falling back to "these [title]".
    var resolvedHookPhrase: String {
        let phrase = Self.cleanedHookPhrase(hookPhrase)
        if !phrase.isEmpty { return phrase }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "these words" : "these \(name.lowercased())"
    }

    var allWords: [WordSlideshowWord] { groups.flatMap(\.words) }
}

// MARK: - Glow colors

/// Underglow colors for a deck's cards. The shuffle happens once and then stays
/// fixed, so the live preview and the exported images (rebuilt from scratch) match.
struct WordSlideshowGlowPalette {
    /// Saturated hues that read as a glow; gray and red are left out.
    static let colors: [DialogueBubbleUnderglowColor] = [
        .yellow, .blue, .pink, .orange, .green, .teal, .purple, .mint, .indigo,
    ]

    private(set) var order: [DialogueBubbleUnderglowColor]
    var mode: WordSlideshowGlowMode

    init(mode: WordSlideshowGlowMode = ExperimentSettings.wordSlideshowGlowMode) {
        order = Self.colors.shuffled()
        self.mode = mode
    }

    mutating func reshuffle() {
        let previous = order
        repeat { order = Self.colors.shuffled() } while order == previous
    }

    /// Color for the deck's nth card. Shuffled cycles, so no two neighbors match.
    func color(forCardAt index: Int) -> DialogueBubbleUnderglowColor {
        switch mode {
        case .shuffled: return order[index % order.count]
        case .single(let color): return color
        }
    }
}

/// Card underglow: a fresh shuffle per slideshow, or one color on every card.
enum WordSlideshowGlowMode: Equatable {
    case shuffled
    case single(DialogueBubbleUnderglowColor)

    var storageKey: String {
        switch self {
        case .shuffled: return "shuffled"
        case .single(let color): return color.storageKey
        }
    }

    init(storageKey: String) {
        self = DialogueBubbleUnderglowColor(storageKey: storageKey).map(Self.single) ?? .shuffled
    }
}

/// Text color of the meaning badge under each card.
enum WordSlideshowMeaningColor: Equatable {
    /// The gold used on kanji decomposition badges.
    case standard
    /// Primary label color (black / white).
    case primary
    /// The card's own underglow hue.
    case matchGlow
    case color(DialogueBubbleUnderglowColor)

    static let fixedOptions: [WordSlideshowMeaningColor] = [.standard, .primary, .matchGlow]

    var title: String {
        switch self {
        case .standard: return "Default gold"
        case .primary: return "Primary text"
        case .matchGlow: return "Match card glow"
        case .color(let color): return color.title
        }
    }

    var storageKey: String {
        switch self {
        case .standard: return "standard"
        case .primary: return "primary"
        case .matchGlow: return "matchGlow"
        case .color(let color): return color.storageKey
        }
    }

    init(storageKey: String) {
        switch storageKey {
        case "primary": self = .primary
        case "matchGlow": self = .matchGlow
        default: self = DialogueBubbleUnderglowColor(storageKey: storageKey).map(Self.color) ?? .standard
        }
    }
}

// MARK: - Prompt

enum WordSlideshowPromptStore {
    private static let instructionsDefaultsKey = "WordSlideshow.instructions"
    private static let lastRequestKey = "WordSlideshow.lastRequest"
    private static let lastLayoutKey = "WordSlideshow.lastLayout"
    private static let includeExamplesKey = "WordSlideshow.includeExamples"

    static let defaultRequest = "The days of the week"

    static let defaultInstructions = """
    You pick Japanese words for short social-media slideshows that teach beginners.
    The app builds the slides. You only supply the words, their English meanings, and a title.

    title: 2-5 English words naming the set, like "Days of the week" or "Japanese opposites".

    hook: 2-6 lowercase English words naming the set, like "these common body parts" or \
    "the days of the week". The app shows it between the fixed lines "Do you know" and \
    "in Japanese?", so never include those words yourself.

    Each word:
    - word: the Japanese word as a native speaker normally writes it, in dictionary form. \
    Use kanji where Japanese normally does (月曜日, 広い, 食べる), kana where it doesn't (ありがとう). \
    Japanese script only: no reading in brackets, no romaji, no English.
    - meaning: plain English, 1-3 words. Gloss a verb as "to X". For pairs, choose the sense \
    that makes the contrast clear (広い → wide, 狭い → narrow).

    Rules:
    - Real, common words a learner would meet. Never invent a word.
    - When the request is a fixed set (days, months, colors, numbers), give the whole set, in order.
    - Otherwise give the number of items the request asks for, or 5 when it doesn't say.
    - No repeated words.
    - For pairs, both words are the same word type, and the second is the true counterpart \
    of the first (広い ↔ 狭い, not 広い ↔ 細い).
    """

    static var instructions: String {
        get {
            let stored = UserDefaults.standard.string(forKey: instructionsDefaultsKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let stored, !stored.isEmpty { return stored }
            return defaultInstructions
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == defaultInstructions {
                UserDefaults.standard.removeObject(forKey: instructionsDefaultsKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: instructionsDefaultsKey)
            }
        }
    }

    static var lastRequest: String {
        get { UserDefaults.standard.string(forKey: lastRequestKey) ?? defaultRequest }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed.isEmpty ? defaultRequest : trimmed, forKey: lastRequestKey)
        }
    }

    static var lastLayout: WordSlideshowLayout {
        get {
            UserDefaults.standard.string(forKey: lastLayoutKey).flatMap(WordSlideshowLayout.init(rawValue:)) ?? .single
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: lastLayoutKey) }
    }

    static var includeExamples: Bool {
        get { UserDefaults.standard.bool(forKey: includeExamplesKey) }
        set { UserDefaults.standard.set(newValue, forKey: includeExamplesKey) }
    }

    /// Instructions for the per-word example call. Fixed: the word list prompt
    /// above stays the one place to steer content.
    static let exampleInstructions = """
    You write one example sentence for a Japanese word on a beginner's vocabulary slideshow. \
    The sentence is there to show what the word means, so the words around it must make the \
    meaning obvious.

    Rules for japanese:
    - A complete sentence of 8 to 25 characters, ending in 。 or ？.
    - Never the word on its own, and never the word plus only です or だ.
    - Give the word real context: a subject, an object, a time, a place, or a reason. \
      Use 私, a friend, a cat, school, work, the weekend: things a learner can picture.
    - Use the word exactly once, in the sense given, either as written or naturally \
      conjugated (食べる → 食べました, 広い → 広くて).
    - Polite です/ます style unless the word itself is casual.
    - Beginner vocabulary for everything except the word.
    - Japanese script only: no romaji, no readings in brackets, no spaces.

    Rules for english: a natural translation of that sentence, one short line.

    Good:
    戦う (to fight) → 兄と毎日ゲームで戦います。 / I battle my brother in games every day.
    広い (wide, spacious) → この公園はとても広いです。 / This park is really big.
    水曜日 (Wednesday) → 水曜日に友だちと映画を見ます。 / I'm seeing a movie with a friend on Wednesday.
    手 (hand) → ご飯の前に手を洗います。 / I wash my hands before meals.

    Bad:
    戦う。 (just the word)
    広いです。 (no context, says nothing about the meaning)
    水曜日は水曜日です。 (circular)
    """

    static func resetInstructionsToDefault() {
        UserDefaults.standard.removeObject(forKey: instructionsDefaultsKey)
    }
}

// MARK: - Samples

/// Offline decks for the showcase and "Open sample". Run through the validator
/// like generated decks, so readings and warnings are filled in.
enum WordSlideshowSamples {
    static func daysOfTheWeek(layout: WordSlideshowLayout = .single, withExamples: Bool = false) -> WordSlideshowDeck {
        let words = [
            ("月曜日", "Monday", "月曜日は仕事です。", "I work on Monday."),
            ("火曜日", "Tuesday", "火曜日に会いましょう。", "Let's meet on Tuesday."),
            ("水曜日", "Wednesday", "水曜日は休みです。", "I'm off on Wednesday."),
            ("木曜日", "Thursday", "木曜日にテストがある。", "I have a test on Thursday."),
            ("金曜日", "Friday", "金曜日の夜、飲みに行こう！", "Let's go for drinks Friday night!"),
            ("土曜日", "Saturday", "土曜日は朝寝坊する。", "I sleep in on Saturdays."),
            ("日曜日", "Sunday", "日曜日に家族と会う。", "I see my family on Sunday."),
        ].map { sample in
            WordSlideshowWord(
                expression: sample.0,
                meaning: sample.1,
                exampleJapanese: withExamples ? sample.2 : "",
                exampleEnglish: withExamples ? sample.3 : ""
            )
        }
        let deck = WordSlideshowDeck(title: "Days of the week", hookPhrase: "the days of the week", layout: layout, words: words)
        deck.includesExamples = withExamples
        return WordSlideshowValidator.validated(deck)
    }

    static func opposites(withExamples: Bool = false) -> WordSlideshowDeck {
        let pairs = [
            (("広い", "wide", "この部屋は広いね。", "This room is so spacious."),
             ("狭い", "narrow", "この道は狭い。", "This road is narrow.")),
            (("高い", "expensive", "このかばんは高い。", "This bag is expensive."),
             ("安い", "cheap", "このお店は安い！", "This shop is cheap!")),
            (("新しい", "new", "新しい車を買った。", "I bought a new car."),
             ("古い", "old", "古い家に住んでいる。", "I live in an old house.")),
            (("暑い", "hot", "今日は暑いですね。", "It's hot today, isn't it?"),
             ("寒い", "cold", "外は寒いよ。", "It's cold outside.")),
        ]
        func word(_ sample: (String, String, String, String)) -> WordSlideshowWord {
            WordSlideshowWord(
                expression: sample.0,
                meaning: sample.1,
                exampleJapanese: withExamples ? sample.2 : "",
                exampleEnglish: withExamples ? sample.3 : ""
            )
        }
        let groups = pairs.map { WordSlideshowGroup(words: [word($0.0), word($0.1)]) }
        let deck = WordSlideshowDeck(
            title: "Japanese opposites",
            hookPhrase: "these everyday opposites",
            layout: .pairs,
            groups: groups,
            includesExamples: withExamples
        )
        return WordSlideshowValidator.validated(deck)
    }
}
