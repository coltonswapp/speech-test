//
//  DialogueLearningHighlights.swift
//  shizen
//
//  Curated vocabulary, grammar patterns, and context notes keyed to dialogue clips.
//

import Foundation

/// Pattern library card shipped with CMS collection JSON (`patterns[]`).
struct DialogueTeachingPattern: Hashable {
    let id: String
    let label: String
    let shortMeaning: String?
    let formNote: String?
}

struct DialogueGrammarPatternRef: Hashable {
    let label: String
    let patternId: String?
    let grammarPointID: String?
    /// Inclusive spoken-only line index (same space as quiz evidence).
    let sourceSpokenStart: Int?
    /// Inclusive spoken-only end; nil means same as start.
    let sourceSpokenEnd: Int?

    init(
        label: String,
        patternId: String? = nil,
        grammarPointID: String? = nil,
        sourceSpokenStart: Int? = nil,
        sourceSpokenEnd: Int? = nil
    ) {
        self.label = label
        self.patternId = patternId
        self.grammarPointID = grammarPointID
        self.sourceSpokenStart = sourceSpokenStart
        self.sourceSpokenEnd = sourceSpokenEnd
    }

    /// Spoken-only indices for Hear / example lines.
    var sourceSpokenIndices: [Int]? {
        guard let start = sourceSpokenStart, start >= 0 else { return nil }
        let end = max(start, sourceSpokenEnd ?? start)
        return Array(start...end)
    }
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
