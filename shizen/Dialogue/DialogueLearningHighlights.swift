//
//  DialogueLearningHighlights.swift
//  shizen
//
//  Curated vocabulary, grammar patterns, and context notes keyed to dialogue clips.
//

import Foundation

struct DialogueGrammarPatternRef: Hashable {
    let label: String
    let grammarPointID: String?
}

struct DialogueLearningHighlights: Hashable {
    let vocabulary: [String]
    let grammarPatterns: [DialogueGrammarPatternRef]
    let contextNotes: [String]

    static let empty = DialogueLearningHighlights(vocabulary: [], grammarPatterns: [], contextNotes: [])

    var isEmpty: Bool {
        vocabulary.isEmpty && grammarPatterns.isEmpty && contextNotes.isEmpty
    }

    var grammarPatternLabels: [String] {
        grammarPatterns.map(\.label)
    }
}

enum DialogueLearningHighlightsCatalog {

    static func highlights(forEntryID id: String) -> DialogueLearningHighlights {
        curated[id] ?? .empty
    }

    /// Hand-authored highlights for bundled dialogue clips. Grows with curated content.
    private static let curated: [String: DialogueLearningHighlights] = [
        "n5-cha-ikenai/dialogue-8-lines": DialogueLearningHighlights(
            vocabulary: ["宿題", "数学", "図書館", "飲み物", "コップ", "ダメ", "静か"],
            grammarPatterns: [
                DialogueGrammarPatternRef(label: "___ ていい？", grammarPointID: "n5-te-mo-ii"),
                DialogueGrammarPatternRef(label: "___ だし", grammarPointID: nil),
                DialogueGrammarPatternRef(label: "___ ちゃいけない", grammarPointID: "n5-cha-ikenai"),
                DialogueGrammarPatternRef(label: "___ じゃダメ", grammarPointID: "n5-cha-ikenai"),
            ],
            contextNotes: [
                "Japanese libraries often ban food and drinks in study areas.",
            ]
        ),
    ]
}

extension DialogueExperimentCatalog.Entry {
    var learningHighlights: DialogueLearningHighlights {
        DialogueLearningHighlightsCatalog.highlights(forEntryID: id)
    }
}
