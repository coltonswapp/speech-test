//
//  RegisterLadderModels.swift
//  shizen
//
//  Mutable slide deck for the register-ladder social slideshow experiment.
//

import Foundation

struct RegisterLadderLevel: Equatable {
    var japanese: String
    var gloss: String
    var audience: String
}

/// Mutable so tap-to-edit Japanese updates stick for live cards and export rebuilds.
final class RegisterLadderDeck {
    var english: String
    var casual: RegisterLadderLevel
    var polite: RegisterLadderLevel
    var formal: RegisterLadderLevel
    var why: String

    init(
        english: String,
        casual: RegisterLadderLevel,
        polite: RegisterLadderLevel,
        formal: RegisterLadderLevel,
        why: String
    ) {
        self.english = english
        self.casual = casual
        self.polite = polite
        self.formal = formal
        self.why = why
    }

    enum Register: CaseIterable {
        case casual
        case polite
        case formal

        var title: String {
            switch self {
            case .casual: return "Casual"
            case .polite: return "Polite"
            case .formal: return "Formal / Keigo"
            }
        }

        var defaultAudience: String {
            switch self {
            case .casual: return "to a friend"
            case .polite: return "to a coworker / stranger"
            case .formal: return "to your boss / a customer"
            }
        }
    }

    func level(for register: Register) -> RegisterLadderLevel {
        switch register {
        case .casual: return casual
        case .polite: return polite
        case .formal: return formal
        }
    }

    func setJapanese(_ japanese: String, for register: Register) {
        switch register {
        case .casual:
            casual.japanese = japanese
        case .polite:
            polite.japanese = japanese
        case .formal:
            formal.japanese = japanese
        }
    }
}

enum RegisterLadderPromptStore {
    static let targetSentencePlaceholder = "[target sentence]"

    private static let promptDefaultsKey = "RegisterLadder.usagePrompt"
    private static let lastTargetKey = "RegisterLadder.lastTargetSentence"

    static let defaultPrompt = """
    You are authoring social slideshow content for the Shizen Japanese learning app.

    Hook: "This is one sentence, said 3 ways" — Japanese politeness feels hard because one idea has multiple registers.

    Task: Given this English target sentence:
    \(targetSentencePlaceholder)

    Produce one English framing of that idea plus three SPOKEN Japanese versions of the SAME communicative intent at different registers:
    1. Casual — natural friend-to-friend speech
    2. Polite — coworker / stranger (です・ます)
    3. Formal / Keigo — boss / customer (respectful or humble forms as appropriate)

    Rules:
    - These are things people SAY out loud — spoken Japanese, not written/textbook style.
    - Prefer common spoken wording and contractions natives actually use (e.g. 〜てる, なんか, ちょっと, 〜かな, 〜っす). Avoid stiff or literary phrasing.
    - Keep the same meaning across all three; prefer changing verb endings / politeness morphology over swapping vocabulary.
    - Write natural Japanese orthography with kanji where a native speaker would (not all-hiragana, not romaji). The app adds furigana over the kanji.
    - Do NOT include romaji anywhere.
    - casualGloss: a short plain-English gloss of the casual Japanese (not a full retranslation of the English).
    - Audience labels should be short (e.g. "to a friend", "to a coworker / stranger", "to your boss / a customer").
    - why: one line explaining what actually changes (verb ending / form), not new vocab.
    - english: the English sentence shown on slide 1 (usually the target, lightly cleaned).

    Return a JSON object with these string fields:
    english, casualJapanese, casualGloss, casualAudience, politeJapanese, politeAudience, formalJapanese, formalAudience, why
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

    static var lastTargetSentence: String {
        get {
            UserDefaults.standard.string(forKey: lastTargetKey) ?? "Can I get the check?"
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed.isEmpty ? "Can I get the check?" : trimmed, forKey: lastTargetKey)
        }
    }

    static func resetPromptToDefault() {
        UserDefaults.standard.removeObject(forKey: promptDefaultsKey)
    }

    static func resolvedPrompt(targetSentence: String, template: String? = nil) -> String {
        let prompt = template ?? usagePrompt
        let sentence = targetSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        return prompt.replacingOccurrences(of: targetSentencePlaceholder, with: sentence)
    }
}
