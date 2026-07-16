//
//  GrammarModels.swift
//  shizen
//

import Foundation
import GrammarContentKit

// MARK: - Runtime models

struct GrammarPoint: Identifiable, Hashable {
    let id: String
    let orderIndex: Int
    let jlptLevel: Int
    let pattern: String
    let reading: String
    let shortDefinition: String
    let blurb: String?
    let structure: String?
    let register: GrammarRegister?
    let forms: [String]
    let relatedPointIDs: [String]
    let examples: [GrammarExample]
    let contrastDrills: [GrammarContrastDrill]

    var title: String { pattern }
    var headlineEnglish: String { shortDefinition }
}

struct GrammarContrastDrill: Hashable {
    let contrastLabel: String
    let choices: [String]
    let correctChoice: String
    let ruleTargeted: String?
}

/// Legacy lesson drill shape — retained for experiment/lesson step view controllers.
struct GrammarDrill: Hashable {
    let kind: GrammarDrillKind
    let instruction: String
    let prompt: String?
    let choices: [String]
    let correctChoice: String
    let exampleJapanese: String?
    let targetSubstring: String?
    let contrastLabel: String?
    let english: String?
    let buildComponents: [String]

    init(record: GrammarDrillRecord) {
        kind = record.kind
        instruction = record.instruction ?? Self.defaultInstruction(for: record.kind)
        prompt = record.prompt
        choices = record.choices
        correctChoice = record.correctChoice
        exampleJapanese = record.exampleJapanese
        targetSubstring = record.targetSubstring
        contrastLabel = record.contrastLabel
        english = record.english
        buildComponents = record.buildComponents ?? []
    }

    init(contrastDrill: GrammarContrastDrill) {
        kind = .contrastChoice
        instruction = "Pick the correct option."
        prompt = nil
        choices = contrastDrill.choices
        correctChoice = contrastDrill.correctChoice
        exampleJapanese = nil
        targetSubstring = nil
        contrastLabel = contrastDrill.contrastLabel
        english = nil
        buildComponents = []
    }

    private static func defaultInstruction(for kind: GrammarDrillKind) -> String {
        switch kind {
        case .formChoice: return "Pick the correct form."
        case .meaningChoice: return "What does this sentence mean?"
        case .sentenceBuilder: return "Tap the pieces in order to build the sentence."
        case .sentenceChoice: return "Pick the sentence that matches."
        case .contrastChoice: return "Pick the correct option."
        case .precursorChoice:
            return "Select the missing component to make this sentence whole."
        }
    }
}

struct GrammarUsageLevel: Hashable {
    let japanese: String
    let register: String
}

struct GrammarUsageLadder: Hashable {
    let label: String?
    let levels: [GrammarUsageLevel]
}

struct GrammarScenarioLine: Hashable {
    let speaker: String
    let japanese: String
    let romaji: String?
    let english: String?
    let grammarPointIDs: [String]
    let lineID: String?

    init(
        speaker: String,
        japanese: String,
        romaji: String? = nil,
        english: String? = nil,
        grammarPointIDs: [String] = [],
        lineID: String? = nil
    ) {
        self.speaker = speaker
        self.japanese = japanese
        self.romaji = romaji
        self.english = english
        self.grammarPointIDs = grammarPointIDs
        self.lineID = lineID
    }
}

struct GrammarScenario: Hashable {
    let setting: String?
    let lines: [GrammarScenarioLine]
}

struct GrammarExample: Hashable {
    let japanese: String
    let romaji: String
    let english: String
    let targetSubstring: String?
    let audioKey: String?
    let publishedAudioUrl: String?
    let scenario: GrammarScenario?
    let sourceScenarioId: String?

    var reading: String { romaji }

    var targetRange: Range<String.Index>? {
        guard let targetSubstring, !targetSubstring.isEmpty else { return nil }
        return japanese.range(of: targetSubstring)
    }

    var isAlternativeFormExample: Bool {
        guard let targetSubstring, !targetSubstring.isEmpty else { return false }
        return targetSubstring.contains("ダメ") && !targetSubstring.contains("いけない")
    }
}

enum GrammarMasteryState: String, Codable, CaseIterable, Equatable {
    case new
    case seen
    case known
}

struct GrammarMasteryRecord: Codable, Equatable {
    var grammarId: String
    var masteryState: GrammarMasteryState
    var timesEncountered: Int
    var firstSeenScenarioId: String?
    var lastPracticedAt: Date?
    var correctStreak: Int

    static func fresh(grammarId: String) -> GrammarMasteryRecord {
        GrammarMasteryRecord(
            grammarId: grammarId,
            masteryState: .new,
            timesEncountered: 0,
            firstSeenScenarioId: nil,
            lastPracticedAt: nil,
            correctStreak: 0
        )
    }
}

extension GrammarPoint {
    init(bundle: GrammarPointBundleRecord, jlptLevel: Int) {
        id = bundle.id
        orderIndex = bundle.orderIndex
        self.jlptLevel = jlptLevel
        pattern = bundle.pattern
        reading = bundle.reading ?? bundle.forms.first ?? bundle.pattern
        shortDefinition = bundle.shortDefinition
        blurb = bundle.blurb
        structure = bundle.structure
        register = bundle.register
        forms = bundle.forms
        relatedPointIDs = bundle.relatedPointIDs
        examples = bundle.examples.map(GrammarExample.init(record:))
        contrastDrills = bundle.contrastDrills.map(GrammarContrastDrill.init(record:))
    }

    init(record: GrammarPointRecord, jlptLevel: Int) {
        self.init(bundle: record.bundleRecord, jlptLevel: jlptLevel)
    }
}

extension GrammarContrastDrill {
    init(record: GrammarContrastDrillRecord) {
        contrastLabel = record.contrastLabel
        choices = record.choices
        correctChoice = record.correctChoice
        ruleTargeted = record.ruleTargeted
    }
}

extension GrammarScenarioLine {
    init(record: GrammarScenarioLineRecord) {
        speaker = record.speaker
        japanese = record.japanese
        romaji = record.romaji
        english = record.english
        grammarPointIDs = []
        lineID = nil
    }
}

extension GrammarScenario {
    init(record: GrammarScenarioRecord) {
        setting = record.setting
        lines = record.lines.map(GrammarScenarioLine.init(record:))
    }
}

extension GrammarExample {
    init(record: GrammarExampleRecord) {
        japanese = record.japanese
        romaji = record.romaji
        english = record.english
        targetSubstring = record.targetSubstring
        audioKey = record.audioKey
        publishedAudioUrl = nil
        scenario = record.scenario.map(GrammarScenario.init(record:))
        sourceScenarioId = record.sourceScenarioId
    }
}

extension GrammarPoint {
    var primaryPatternForms: [String] {
        let primary = forms.filter { $0.contains("いけない") }
        if !primary.isEmpty { return primary }
        return Array(forms.prefix(2))
    }

    var primaryExamples: [GrammarExample] {
        examples.filter { !$0.isAlternativeFormExample }
    }

    var alternativeExamples: [GrammarExample] {
        examples.filter(\.isAlternativeFormExample)
    }

    var formation: [GrammarTeachingBlock] {
        guard let structure, !structure.isEmpty else { return [] }
        return [GrammarTeachingBlock(title: nil, body: structure)]
    }

    var usage: [GrammarTeachingBlock] { [] }
    var usageLadders: [GrammarUsageLadder] { [] }
    var drills: [GrammarDrill] {
        contrastDrills.map(GrammarDrill.init(contrastDrill:))
    }
}

extension GrammarUsageLadder {
    init(record: GrammarUsageLadderRecord) {
        label = record.label
        levels = record.levels.map(GrammarUsageLevel.init(record:))
    }
}

extension GrammarUsageLevel {
    init(record: GrammarUsageLevelRecord) {
        japanese = record.japanese
        register = record.register
    }
}

struct GrammarCheckpoint: Identifiable, Hashable {
    let id: String
    let orderIndex: Int
    let jlptLevel: Int
    let title: String
    let subtitle: String?
    let pointIDs: [String]

    func points(from allPoints: [GrammarPoint]) -> [GrammarPoint] {
        let byID = Dictionary(uniqueKeysWithValues: allPoints.map { ($0.id, $0) })
        return pointIDs.compactMap { byID[$0] }
    }
}

extension GrammarCheckpoint {
    init(record: GrammarCheckpointRecord, jlptLevel: Int) {
        id = record.id
        orderIndex = record.orderIndex
        self.jlptLevel = jlptLevel
        title = record.title
        subtitle = record.subtitle
        pointIDs = record.pointIDs
    }
}

// MARK: - Practice items

enum GrammarPracticeItemKind: Hashable {
    case meaningChoice
    case contrastChoice
}

struct GrammarPracticeItem: Hashable {
    let kind: GrammarPracticeItemKind
    let japanese: String?
    let reading: String?
    let choices: [String]
    let correctChoice: String
    let contrastLabel: String?
    let ruleTargeted: String?
    let sourceLineId: String?
    let sourceScenarioId: String?
}
