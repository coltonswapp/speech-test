//
//  DialogueQuiz.swift
//  shizen
//
//  Optional comprehension quiz attached to a dialogue scenario.
//

import Foundation

struct DialogueQuizQuestion: Hashable {
    enum Layout: String, Hashable, Decodable {
        case grid
        case list
    }

    let prompt: String
    /// Featured Japanese word or phrase; shown with furigana when present.
    let target: String?
    let choices: [String]
    let correctChoice: String
    let wrongAnswerExplanation: String
    let layout: Layout
}

/// Mid-listen checkpoint authored as `type: "inline-question"` in `lines[]`.
struct DialogueInlineQuestion: Hashable {
    let prompt: String
    let target: String?
    let choices: [String]
    let correctChoice: String
    let wrongAnswerExplanation: String
    let layout: DialogueQuizQuestion.Layout

    var asQuizQuestion: DialogueQuizQuestion {
        DialogueQuizQuestion(
            prompt: prompt,
            target: target,
            choices: choices,
            correctChoice: correctChoice,
            wrongAnswerExplanation: wrongAnswerExplanation,
            layout: layout
        )
    }
}
