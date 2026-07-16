//
//  GrammarLessonContentBuilder.swift
//  shizen
//

import UIKit
import GrammarContentKit

enum GrammarLessonContentBuilder {

    static func lessonSteps(for point: GrammarPoint) -> [UIViewController] {
        var steps: [UIViewController] = []

        steps.append(GrammarPrincipleStepViewController(point: point))
        steps.append(GrammarFormationStepViewController(point: point))

        for example in point.examples {
            steps.append(GrammarExampleStepViewController(example: example, pointTitle: point.title))
        }

        for drill in point.drills where drill.kind == .precursorChoice {
            steps.append(makeDrillStep(for: drill))
        }

        let practiceDrills = point.drills.filter {
            $0.kind != .precursorChoice && $0.kind != .sentenceBuilder
        }
        for drill in practiceDrills.prefix(3) {
            steps.append(makeDrillStep(for: drill))
        }

        for drill in point.drills where drill.kind == .sentenceBuilder {
            steps.append(GrammarSentenceBuilderStepViewController(drill: drill))
        }

        return steps
    }

    static func makeDrillStep(for drill: GrammarDrill) -> UIViewController {
        switch drill.kind {
        case .formChoice:
            return GrammarMultipleChoiceStepViewController(
                drill: drill,
                choiceLabelStyle: .grammarFormChoice,
                choiceLayout: .list
            )
        case .contrastChoice:
            return GrammarMultipleChoiceStepViewController(
                drill: drill,
                choiceLabelStyle: .grammarForm,
                choiceLayout: .grid
            )
        case .meaningChoice:
            return GrammarMultipleChoiceStepViewController(
                drill: drill,
                choiceLabelStyle: .compact,
                choiceLayout: .list
            )
        case .sentenceChoice:
            return GrammarMultipleChoiceStepViewController(
                drill: drill,
                choiceLabelStyle: .grammarSentenceList,
                choiceLayout: .list
            )
        case .sentenceBuilder:
            return GrammarSentenceBuilderStepViewController(drill: drill)
        case .precursorChoice:
            return GrammarPrecursorChoiceStepViewController(drill: drill)
        }
    }
}
