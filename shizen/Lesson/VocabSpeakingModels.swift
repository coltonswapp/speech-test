//
//  VocabSpeakingModels.swift
//  shizen
//

import Foundation

struct VocabSpeakingPrompt: Equatable {
    let hiragana: String
    let romaji: String
    private let altRecognitions: [String]

    init(hiragana: String, romaji: String, altRecognitions: [String] = []) {
        self.hiragana = hiragana
        self.romaji = romaji
        self.altRecognitions = altRecognitions
    }

    var contextualHints: [String] {
        Array(Set([hiragana, romaji] + altRecognitions)).sorted()
    }

    func matches(transcription: String) -> Bool {
        let normalized = Self.normalizeForMatch(transcription)
        guard !normalized.isEmpty else { return false }

        let accepted = [hiragana, romaji] + altRecognitions
        return accepted.contains { form in
            let key = Self.normalizeForMatch(form)
            guard !key.isEmpty else { return false }
            return normalized.contains(key)
        }
    }

    private static func normalizeForMatch(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{3000}", with: "")
    }
}

enum VocabSpeakingBank {
    static let prompts: [VocabSpeakingPrompt] = [
        VocabSpeakingPrompt(
            hiragana: "ありがとう",
            romaji: "arigatou",
            altRecognitions: ["ありがと", "arigato", "a rigato"]
        ),
        VocabSpeakingPrompt(
            hiragana: "こんにちは",
            romaji: "konnichiwa",
            altRecognitions: ["こんにちわ", "konichiwa", "konnichiha"]
        ),
        VocabSpeakingPrompt(
            hiragana: "おはよう",
            romaji: "ohayou",
            altRecognitions: ["おはよ", "ohayo", "ohiyo"]
        ),
    ]
}
