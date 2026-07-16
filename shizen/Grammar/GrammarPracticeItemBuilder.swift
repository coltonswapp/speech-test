//
//  GrammarPracticeItemBuilder.swift
//  shizen
//

import Foundation

enum GrammarPracticeItemBuilder {

    struct SessionConfig {
        let targetGrammarId: String
        let itemCount: Int
        let meaningChoiceRatio: Double

        static let `default` = SessionConfig(
            targetGrammarId: "",
            itemCount: 6,
            meaningChoiceRatio: 0.6
        )
    }

    static func buildSession(
        for point: GrammarPoint,
        completedScenarioIDs: Set<String>,
        config: SessionConfig
    ) -> [GrammarPracticeItem] {
        var meaningItems = buildMeaningChoiceItems(
            for: point,
            completedScenarioIDs: completedScenarioIDs
        )
        let contrastItems = buildContrastChoiceItems(for: point)

        if meaningItems.isEmpty {
            meaningItems = buildFallbackMeaningItems(from: point.examples)
        }

        let targetMeaning = max(0, Int(round(Double(config.itemCount) * config.meaningChoiceRatio)))
        let targetContrast = max(0, config.itemCount - targetMeaning)

        var selectedMeaning = Array(meaningItems.shuffled().prefix(min(targetMeaning, meaningItems.count)))
        var selectedContrast = Array(contrastItems.shuffled().prefix(min(targetContrast, contrastItems.count)))

        var items = interleave(
            meaning: selectedMeaning,
            contrast: selectedContrast,
            total: config.itemCount
        )

        if items.count < config.itemCount {
            let remainingMeaning = meaningItems.filter { candidate in
                !items.contains(where: { $0.correctChoice == candidate.correctChoice && $0.japanese == candidate.japanese })
            }
            for item in remainingMeaning where items.count < config.itemCount {
                items.append(item)
            }
        }

        if items.count < config.itemCount {
            let remainingContrast = contrastItems.filter { candidate in
                !items.contains(where: { $0.contrastLabel == candidate.contrastLabel })
            }
            for item in remainingContrast where items.count < config.itemCount {
                items.append(item)
            }
        }

        return items.shuffled()
    }

    private static func buildMeaningChoiceItems(
        for point: GrammarPoint,
        completedScenarioIDs: Set<String>
    ) -> [GrammarPracticeItem] {
        let sources = DialogueScenarioCollectionCatalog.meaningChoiceLines(
            forGrammarPointID: point.id,
            completedScenarioIDs: completedScenarioIDs
        )
        return sources.map { source in
            let distractors = buildDistractors(
                correct: source.english,
                scenarioID: source.sourceScenarioId,
                point: point
            )
            let choices = ([source.english] + distractors).shuffled()
            return GrammarPracticeItem(
                kind: .meaningChoice,
                japanese: source.japanese,
                reading: source.reading,
                choices: choices,
                correctChoice: source.english,
                contrastLabel: nil,
                ruleTargeted: nil,
                sourceLineId: source.sourceLineId,
                sourceScenarioId: source.sourceScenarioId
            )
        }
    }

    private static func buildFallbackMeaningItems(from examples: [GrammarExample]) -> [GrammarPracticeItem] {
        examples.compactMap { example in
            let english = example.english.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !english.isEmpty else { return nil }
            let distractors = examples
                .map(\.english)
                .filter { $0 != english }
                .shuffled()
                .prefix(3)
            let choices = ([english] + distractors).shuffled()
            return GrammarPracticeItem(
                kind: .meaningChoice,
                japanese: example.japanese,
                reading: example.reading,
                choices: Array(choices),
                correctChoice: english,
                contrastLabel: nil,
                ruleTargeted: nil,
                sourceLineId: nil,
                sourceScenarioId: example.sourceScenarioId
            )
        }
    }

    private static func buildContrastChoiceItems(for point: GrammarPoint) -> [GrammarPracticeItem] {
        point.contrastDrills.map { drill in
            GrammarPracticeItem(
                kind: .contrastChoice,
                japanese: nil,
                reading: nil,
                choices: drill.choices.shuffled(),
                correctChoice: drill.correctChoice,
                contrastLabel: drill.contrastLabel,
                ruleTargeted: drill.ruleTargeted,
                sourceLineId: nil,
                sourceScenarioId: nil
            )
        }
    }

    private static func buildDistractors(
        correct: String,
        scenarioID: String,
        point: GrammarPoint
    ) -> [String] {
        var pool: [String] = []
        for collection in DialogueScenarioCollectionCatalog.allCollections {
            for scenario in collection.scenarios where scenario.id == scenarioID {
                pool.append(contentsOf: scenario.lines.compactMap(\.english))
            }
        }
        pool.append(contentsOf: point.examples.map(\.english))
        let unique = Array(Set(pool.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty && $0 != correct }
        return Array(unique.shuffled().prefix(3))
    }

    private static func interleave(
        meaning: [GrammarPracticeItem],
        contrast: [GrammarPracticeItem],
        total: Int
    ) -> [GrammarPracticeItem] {
        var result: [GrammarPracticeItem] = []
        var meaningIndex = 0
        var contrastIndex = 0
        while result.count < total, meaningIndex < meaning.count || contrastIndex < contrast.count {
            if meaningIndex < meaning.count {
                result.append(meaning[meaningIndex])
                meaningIndex += 1
                if result.count >= total { break }
            }
            if contrastIndex < contrast.count {
                result.append(contrast[contrastIndex])
                contrastIndex += 1
            }
        }
        return result
    }
}
