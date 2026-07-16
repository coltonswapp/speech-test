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
    let choices: [String]
    let correctChoice: String
    let wrongAnswerExplanation: String
    let layout: Layout
}
