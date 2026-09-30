//
//  VerbComboModels.swift
//  shizen
//
//  One pattern (みる, いく, …) as five exportable stills: a hook verb,
//  a plain-language rule, then three example verbs with a sentence each.
//

import Foundation

struct VerbComboExample: Equatable {
    var compound: String
    var exampleJapanese: String
    var exampleEnglish: String

    var exampleLine: String {
        let trimmed = exampleJapanese.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("「"), trimmed.hasSuffix("」") { return trimmed }
        return "「\(trimmed)」"
    }
}

struct VerbComboDeck: Equatable {
    /// Shown alone on still 1, e.g. やってみる.
    var hookVerb: String
    /// The verb being added, in hiragana, e.g. みる.
    var partner: String
    /// Still 2, e.g. "When a verb is combined with みる it means to try something."
    var rule: String
    var examples: [VerbComboExample]
}

enum VerbComboCopy {
    static let question = "Do you know this verb?"
}

enum VerbComboSamples {
    static let miru = VerbComboDeck(
        hookVerb: "やってみる",
        partner: "みる",
        rule: "When a verb is combined with みる it means to try something.",
        examples: [
            VerbComboExample(
                compound: "食べてみる",
                exampleJapanese: "新しいラーメン、食べてみる？",
                exampleEnglish: "Wanna try the new ramen?"
            ),
            VerbComboExample(
                compound: "飲んでみる",
                exampleJapanese: "このお茶、飲んでみる？",
                exampleEnglish: "Wanna try this tea?"
            ),
            VerbComboExample(
                compound: "読んでみる",
                exampleJapanese: "この漫画、読んでみる。",
                exampleEnglish: "I'll try this manga."
            ),
        ]
    )

    static let all: [VerbComboDeck] = [miru]
}

enum VerbComboPromptStore {
    static let themePlaceholder = "[theme]"

    private static let promptDefaultsKey = "VerbCombo.usagePrompt.v2"
    private static let lastThemeKey = "VerbCombo.lastTheme"

    static let defaultTheme = "daily life — trying things, errands, getting around"

    static let defaultPrompt = """
    You are authoring exportable slideshow stills for the Shizen Japanese learning app.

    Each result is one 5-still slideshow about a single added verb (みる, いく, くる, おく, しまう, and similar). The stills are separate exports. The app builds the cards. You only supply the words.

    Theme: \(themePlaceholder)

    The app lays each slideshow out like this:
    1. "Do you know this verb?" and hookVerb alone. No sentence.
    2. rule, one plain sentence, centered.
    3. examples[0].compound, then that example sentence.
    4. examples[1].compound, then that example sentence.
    5. examples[2].compound, then that example sentence.

    Write 3 slideshows. Each one:
    - partner: the added verb in hiragana (みる).
    - hookVerb: one familiar fused verb that uses partner, in everyday writing (やってみる). Not repeated in examples.
    - rule: one beginner sentence of the form "When a verb is combined with PARTNER it means …." Use the partner's hiragana inside the sentence. Say what it means in everyday English (to try something). No grammar words.
    - examples: exactly 3 different fused verbs that use the same partner. Each has compound, exampleJapanese, and exampleEnglish.

    Writing:
    - compound and hookVerb: kanji on the main verb. Write the partner in hiragana (食べてみる, 歩いていく, 持ってくる).
    - exampleJapanese: one short spoken line that uses that compound. A conjugated ending is fine when the combination is still obvious.
    - exampleEnglish: that line in plain English, one short line.
    - Beginner words. Things people say. Daily life on the theme.

    Rules:
    - 3 slideshows. Each stands alone. Do not mention another slideshow.
    - Exactly 3 examples inside each slideshow. hookVerb is a fourth verb, only for still 1.
    - No romaji.
    - No grammar labels: te-form, auxiliary, compound verb, godan, stem, conjugation.
    - Do not repeat a compound.

    Shape to match (write 3 new slideshows on the theme, not a copy of this one):
    partner みる
    hookVerb やってみる
    rule When a verb is combined with みる it means to try something.
    examples:
    食べてみる / 新しいラーメン、食べてみる？ / Wanna try the new ramen?
    飲んでみる / このお茶、飲んでみる？ / Wanna try this tea?
    読んでみる / この漫画、読んでみる。 / I'll try this manga.
    """

    static var usagePrompt: String {
        get {
            let stored = UserDefaults.standard.string(forKey: promptDefaultsKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let stored, !stored.isEmpty { return stored }
            return defaultPrompt
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == defaultPrompt {
                UserDefaults.standard.removeObject(forKey: promptDefaultsKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: promptDefaultsKey)
            }
        }
    }

    static var lastTheme: String {
        get {
            UserDefaults.standard.string(forKey: lastThemeKey) ?? defaultTheme
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed.isEmpty ? defaultTheme : trimmed, forKey: lastThemeKey)
        }
    }

    static func resetPromptToDefault() {
        UserDefaults.standard.removeObject(forKey: promptDefaultsKey)
    }

    static func resolvedPrompt(theme: String, template: String? = nil) -> String {
        let prompt = template ?? usagePrompt
        let resolvedTheme = theme.trimmingCharacters(in: .whitespacesAndNewlines)
        let themeText = resolvedTheme.isEmpty ? defaultTheme : resolvedTheme
        return prompt.replacingOccurrences(of: themePlaceholder, with: themeText)
    }
}
