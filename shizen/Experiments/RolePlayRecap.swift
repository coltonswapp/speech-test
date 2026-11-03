//
//  RolePlayRecap.swift
//  shizen
//
//  Role Play completion recap: a few of the learner's lines, preferring the
//  ones that lean on the scene's grammar patterns.
//

import UIKit

/// Scene content the recap teaches from. The lesson pager supplies it; a
/// standalone Role Play without it still recaps lines, just without patterns.
struct RolePlayRecapSource {
    let highlights: DialogueLearningHighlights
    let teachingPattern: (DialogueGrammarPatternRef) -> DialogueTeachingPattern?
    /// Opens the shared grammar detail from the presenting view controller.
    let presentPattern: (DialogueGrammarPatternRef, UIViewController) -> Void
}

struct RolePlayRecap {
    struct Pattern {
        let ref: DialogueGrammarPatternRef
        let label: String
        let meaning: String?
    }

    struct Line {
        let displayIndex: Int
        let japanese: String
        let english: String?
        let patterns: [Pattern]
        /// UTF-16 range of the pattern's surface in `japanese`, when findable.
        let highlightRange: NSRange?
    }

    let learnerSpeaker: String
    /// The single other speaker in a two-person scene — the "Play as" target.
    let nextSpeaker: String?
    /// Every line the learner spoke this run.
    let spokenLineCount: Int
    /// Up to ``maxLines``, in scene order: grammar-bearing lines first pick.
    let lines: [Line]

    static let maxLines = 3

    var hasGrammar: Bool {
        lines.contains { !$0.patterns.isEmpty }
    }

    /// Keeps scene order but fills the slots with grammar lines before plain ones.
    static func featuredLines(from all: [Line]) -> [Line] {
        let withGrammar = all.filter { !$0.patterns.isEmpty }
        let picked = withGrammar.isEmpty
            ? Array(all.prefix(maxLines))
            : Array(withGrammar.prefix(maxLines))
        return picked.sorted { $0.displayIndex < $1.displayIndex }
    }

    /// Best-effort surface of a pattern label inside a line: drops the
    /// `___` / `〜` slot and trailing punctuation, then trims leading kana
    /// until a piece (two characters minimum) appears — `___ ていい？`
    /// still finds `いい` inside `飲んでもいい？`.
    static func highlightRange(ofPatternLabel label: String, in japanese: String) -> NSRange? {
        let slotMarkers = CharacterSet(charactersIn: "_＿〜～…・")
            .union(.whitespacesAndNewlines)
        let trailingPunctuation = CharacterSet(charactersIn: "？?！!。、")
        let fragments = label
            .components(separatedBy: slotMarkers)
            .map { $0.trimmingCharacters(in: trailingPunctuation) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        let text = japanese as NSString
        for fragment in fragments {
            var piece = Substring(fragment)
            while piece.count >= 2 || (piece.count == fragment.count && !piece.isEmpty) {
                let range = text.range(of: String(piece))
                if range.location != NSNotFound { return range }
                piece = piece.dropFirst()
            }
        }
        return nil
    }
}
