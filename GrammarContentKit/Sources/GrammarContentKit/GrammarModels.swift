//
//  GrammarModels.swift
//  GrammarContentKit
//

import Foundation

// MARK: - Content workflow

public enum ContentStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case needsRevision
    case approved
}

public struct ContentProvenance: Codable, Hashable, Sendable {
    public let source: String?
    public let url: String?
    public let importedAt: String?

    public init(source: String? = nil, url: String? = nil, importedAt: String? = nil) {
        self.source = source
        self.url = url
        self.importedAt = importedAt
    }
}

// MARK: - Bundle schema

public enum GrammarRegister: String, Codable, CaseIterable, Sendable {
    case casual
    case polite
    case formal
}

public struct GrammarContrastDrillRecord: Codable, Hashable, Sendable {
    public let contrastLabel: String
    public let choices: [String]
    public let correctChoice: String
    public let ruleTargeted: String?

    public init(
        contrastLabel: String,
        choices: [String],
        correctChoice: String,
        ruleTargeted: String? = nil
    ) {
        self.contrastLabel = contrastLabel
        self.choices = choices
        self.correctChoice = correctChoice
        self.ruleTargeted = ruleTargeted
    }

    public init?(drill: GrammarDrillRecord) {
        guard drill.kind == .contrastChoice else { return nil }
        contrastLabel = drill.contrastLabel ?? ""
        choices = drill.choices
        correctChoice = drill.correctChoice
        ruleTargeted = drill.instruction
    }
}

public struct GrammarCurriculumFile: Codable, Sendable {
    public static let currentFormatVersion = 2

    public var formatVersion: Int
    public var jlptLevel: Int
    public var checkpoints: [GrammarCheckpointRecord]?
    public var points: [GrammarPointRecord]

    public init(
        formatVersion: Int = Self.currentFormatVersion,
        jlptLevel: Int,
        checkpoints: [GrammarCheckpointRecord]? = nil,
        points: [GrammarPointRecord]
    ) {
        self.formatVersion = formatVersion
        self.jlptLevel = jlptLevel
        self.checkpoints = checkpoints
        self.points = points
    }
}

public struct GrammarCheckpointsFile: Codable, Sendable {
    public var jlptLevel: Int
    public var checkpoints: [GrammarCheckpointRecord]

    public init(jlptLevel: Int, checkpoints: [GrammarCheckpointRecord]) {
        self.jlptLevel = jlptLevel
        self.checkpoints = checkpoints
    }
}

public struct GrammarCheckpointRecord: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let orderIndex: Int
    public let title: String
    public let subtitle: String?
    public let pointIDs: [String]

    public init(
        id: String,
        orderIndex: Int,
        title: String,
        subtitle: String? = nil,
        pointIDs: [String]
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.title = title
        self.subtitle = subtitle
        self.pointIDs = pointIDs
    }
}

public struct GrammarPointRecord: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let orderIndex: Int
    public let title: String
    public let headlineEnglish: String
    public let blurb: String?
    public let forms: [String]
    public let formation: [GrammarTeachingBlock]
    public let formationExamples: [String]?
    public let usage: [GrammarTeachingBlock]?
    public let usageLadders: [GrammarUsageLadderRecord]?
    public let relatedPointIDs: [String]
    public let examples: [GrammarExampleRecord]
    public let drills: [GrammarDrillRecord]
    public let pattern: String?
    public let reading: String?
    public let shortDefinition: String?
    public let structure: String?
    public let register: GrammarRegister?
    public let contrastDrills: [GrammarContrastDrillRecord]?
    public var status: ContentStatus
    public var reviewNotes: String?
    public var provenance: ContentProvenance?

    public var resolvedPattern: String { pattern ?? title }
    public var resolvedShortDefinition: String { shortDefinition ?? headlineEnglish }
    public var resolvedReading: String { reading ?? forms.first ?? title }

    public var resolvedStructure: String {
        if let structure, !structure.isEmpty { return structure }
        return formation.map(\.body).joined(separator: "\n\n")
    }

    public var resolvedContrastDrills: [GrammarContrastDrillRecord] {
        if let contrastDrills, !contrastDrills.isEmpty { return contrastDrills }
        return drills.compactMap(GrammarContrastDrillRecord.init(drill:))
    }

    public init(
        id: String,
        orderIndex: Int,
        title: String,
        headlineEnglish: String,
        blurb: String? = nil,
        forms: [String],
        formation: [GrammarTeachingBlock],
        formationExamples: [String]? = nil,
        usage: [GrammarTeachingBlock]? = nil,
        usageLadders: [GrammarUsageLadderRecord]? = nil,
        relatedPointIDs: [String] = [],
        examples: [GrammarExampleRecord],
        drills: [GrammarDrillRecord] = [],
        pattern: String? = nil,
        reading: String? = nil,
        shortDefinition: String? = nil,
        structure: String? = nil,
        register: GrammarRegister? = nil,
        contrastDrills: [GrammarContrastDrillRecord]? = nil,
        status: ContentStatus = .draft,
        reviewNotes: String? = nil,
        provenance: ContentProvenance? = nil
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.title = title
        self.headlineEnglish = headlineEnglish
        self.blurb = blurb
        self.forms = forms
        self.formation = formation
        self.formationExamples = formationExamples
        self.usage = usage
        self.usageLadders = usageLadders
        self.relatedPointIDs = relatedPointIDs
        self.examples = examples
        self.drills = drills
        self.pattern = pattern
        self.reading = reading
        self.shortDefinition = shortDefinition
        self.structure = structure
        self.register = register
        self.contrastDrills = contrastDrills
        self.status = status
        self.reviewNotes = reviewNotes
        self.provenance = provenance
    }

    private enum CodingKeys: String, CodingKey {
        case id, orderIndex, title, headlineEnglish, blurb, forms, formation, formationExamples, usage
        case usageLadders, relatedPointIDs, examples, drills, status, reviewNotes
        case pattern, reading, shortDefinition, structure, register, contrastDrills
        case provenance = "_provenance"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        orderIndex = try container.decode(Int.self, forKey: .orderIndex)
        title = try container.decode(String.self, forKey: .title)
        headlineEnglish = try container.decode(String.self, forKey: .headlineEnglish)
        blurb = try container.decodeIfPresent(String.self, forKey: .blurb)
        forms = try container.decodeIfPresent([String].self, forKey: .forms) ?? []
        formation = try container.decodeIfPresent([GrammarTeachingBlock].self, forKey: .formation) ?? []
        formationExamples = try container.decodeIfPresent([String].self, forKey: .formationExamples)
        usage = try container.decodeIfPresent([GrammarTeachingBlock].self, forKey: .usage)
        usageLadders = try container.decodeIfPresent([GrammarUsageLadderRecord].self, forKey: .usageLadders)
        relatedPointIDs = try container.decodeIfPresent([String].self, forKey: .relatedPointIDs) ?? []
        examples = try container.decode([GrammarExampleRecord].self, forKey: .examples)
        drills = try container.decodeIfPresent([GrammarDrillRecord].self, forKey: .drills) ?? []
        pattern = try container.decodeIfPresent(String.self, forKey: .pattern)
        reading = try container.decodeIfPresent(String.self, forKey: .reading)
        shortDefinition = try container.decodeIfPresent(String.self, forKey: .shortDefinition)
        structure = try container.decodeIfPresent(String.self, forKey: .structure)
        register = try container.decodeIfPresent(GrammarRegister.self, forKey: .register)
        contrastDrills = try container.decodeIfPresent([GrammarContrastDrillRecord].self, forKey: .contrastDrills)
        status = try container.decodeIfPresent(ContentStatus.self, forKey: .status) ?? .draft
        reviewNotes = try container.decodeIfPresent(String.self, forKey: .reviewNotes)
        provenance = try container.decodeIfPresent(ContentProvenance.self, forKey: .provenance)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(orderIndex, forKey: .orderIndex)
        try container.encode(title, forKey: .title)
        try container.encode(headlineEnglish, forKey: .headlineEnglish)
        try container.encodeIfPresent(blurb, forKey: .blurb)
        try container.encode(forms, forKey: .forms)
        try container.encode(formation, forKey: .formation)
        try container.encodeIfPresent(formationExamples, forKey: .formationExamples)
        try container.encodeIfPresent(usage, forKey: .usage)
        try container.encodeIfPresent(usageLadders, forKey: .usageLadders)
        try container.encode(relatedPointIDs, forKey: .relatedPointIDs)
        try container.encode(examples, forKey: .examples)
        try container.encode(drills, forKey: .drills)
        try container.encodeIfPresent(pattern, forKey: .pattern)
        try container.encodeIfPresent(reading, forKey: .reading)
        try container.encodeIfPresent(shortDefinition, forKey: .shortDefinition)
        try container.encodeIfPresent(structure, forKey: .structure)
        try container.encodeIfPresent(register, forKey: .register)
        try container.encodeIfPresent(contrastDrills, forKey: .contrastDrills)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(reviewNotes, forKey: .reviewNotes)
        try container.encodeIfPresent(provenance, forKey: .provenance)
    }

    /// Strips workflow fields for the shipped app bundle.
    public func shippingRecord() -> GrammarPointRecord {
        var copy = self
        copy.status = .approved
        copy.reviewNotes = nil
        copy.provenance = nil
        return copy
    }

    /// Encodable shape for `n5.grammar.json` (no workflow metadata).
    public var bundleRecord: GrammarPointBundleRecord {
        GrammarPointBundleRecord(record: self)
    }
}

public struct GrammarPointBundleRecord: Codable, Sendable {
    public let id: String
    public let orderIndex: Int
    public let pattern: String
    public let reading: String?
    public let shortDefinition: String
    public let blurb: String?
    public let structure: String?
    public let register: GrammarRegister?
    public let forms: [String]
    public let relatedPointIDs: [String]
    public let examples: [GrammarExampleRecord]
    public let contrastDrills: [GrammarContrastDrillRecord]

    private enum CodingKeys: String, CodingKey {
        case id, orderIndex, pattern, reading, shortDefinition, blurb, structure, register
        case forms, relatedPointIDs, examples, contrastDrills
        case title, headlineEnglish, formation, drills
    }

    public init(record: GrammarPointRecord) {
        id = record.id
        orderIndex = record.orderIndex
        pattern = record.resolvedPattern
        reading = record.resolvedReading
        shortDefinition = record.resolvedShortDefinition
        blurb = record.blurb
        structure = record.resolvedStructure.isEmpty ? nil : record.resolvedStructure
        register = record.register ?? Self.inferRegister(from: record)
        forms = record.forms
        relatedPointIDs = record.relatedPointIDs
        examples = record.examples
        contrastDrills = record.resolvedContrastDrills
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        orderIndex = try container.decode(Int.self, forKey: .orderIndex)
        pattern = try container.decodeIfPresent(String.self, forKey: .pattern)
            ?? container.decodeIfPresent(String.self, forKey: .title)
            ?? ""
        reading = try container.decodeIfPresent(String.self, forKey: .reading)
        shortDefinition = try container.decodeIfPresent(String.self, forKey: .shortDefinition)
            ?? container.decodeIfPresent(String.self, forKey: .headlineEnglish)
            ?? ""
        blurb = try container.decodeIfPresent(String.self, forKey: .blurb)
        if let structure = try container.decodeIfPresent(String.self, forKey: .structure) {
            self.structure = structure
        } else if let formation = try container.decodeIfPresent([GrammarTeachingBlock].self, forKey: .formation) {
            let joined = formation.map(\.body).joined(separator: "\n\n")
            structure = joined.isEmpty ? nil : joined
        } else {
            structure = nil
        }
        register = try container.decodeIfPresent(GrammarRegister.self, forKey: .register)
        forms = try container.decodeIfPresent([String].self, forKey: .forms) ?? []
        relatedPointIDs = try container.decodeIfPresent([String].self, forKey: .relatedPointIDs) ?? []
        examples = try container.decode([GrammarExampleRecord].self, forKey: .examples)
        if let contrastDrills = try container.decodeIfPresent([GrammarContrastDrillRecord].self, forKey: .contrastDrills) {
            self.contrastDrills = contrastDrills
        } else if let drills = try container.decodeIfPresent([GrammarDrillRecord].self, forKey: .drills) {
            contrastDrills = drills.compactMap(GrammarContrastDrillRecord.init(drill:))
        } else {
            contrastDrills = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(orderIndex, forKey: .orderIndex)
        try container.encode(pattern, forKey: .pattern)
        try container.encodeIfPresent(reading, forKey: .reading)
        try container.encode(shortDefinition, forKey: .shortDefinition)
        try container.encodeIfPresent(blurb, forKey: .blurb)
        try container.encodeIfPresent(structure, forKey: .structure)
        try container.encodeIfPresent(register, forKey: .register)
        try container.encode(forms, forKey: .forms)
        try container.encode(relatedPointIDs, forKey: .relatedPointIDs)
        try container.encode(examples, forKey: .examples)
        try container.encode(contrastDrills, forKey: .contrastDrills)
    }

    private static func inferRegister(from record: GrammarPointRecord) -> GrammarRegister? {
        let ladderRegister = record.usageLadders?
            .flatMap(\.levels)
            .map(\.register)
            .first?
            .lowercased() ?? ""
        if ladderRegister.contains("casual") { return .casual }
        if ladderRegister.contains("formal") || ladderRegister.contains("keigo") { return .formal }
        if ladderRegister.contains("polite") { return .polite }
        return nil
    }
}

public struct GrammarCurriculumBundleFile: Codable, Sendable {
    public var formatVersion: Int
    public var jlptLevel: Int
    public var checkpoints: [GrammarCheckpointRecord]?
    public var points: [GrammarPointBundleRecord]

    public init(
        formatVersion: Int = GrammarCurriculumFile.currentFormatVersion,
        jlptLevel: Int,
        checkpoints: [GrammarCheckpointRecord]?,
        points: [GrammarPointBundleRecord]
    ) {
        self.formatVersion = formatVersion
        self.jlptLevel = jlptLevel
        self.checkpoints = checkpoints
        self.points = points
    }
}

public struct GrammarTeachingBlock: Codable, Hashable, Sendable {
    public let title: String?
    public let body: String

    public init(title: String? = nil, body: String) {
        self.title = title
        self.body = body
    }
}

public struct GrammarUsageLevelRecord: Codable, Hashable, Sendable {
    public let japanese: String
    public let register: String

    public init(japanese: String, register: String) {
        self.japanese = japanese
        self.register = register
    }
}

public struct GrammarUsageLadderRecord: Codable, Hashable, Sendable {
    public let label: String?
    public let levels: [GrammarUsageLevelRecord]

    public init(label: String? = nil, levels: [GrammarUsageLevelRecord]) {
        self.label = label
        self.levels = levels
    }
}

public struct GrammarScenarioLineRecord: Codable, Hashable, Sendable {
    public let speaker: String
    public let japanese: String
    public let romaji: String?
    public let english: String?

    public init(speaker: String, japanese: String, romaji: String? = nil, english: String? = nil) {
        self.speaker = speaker
        self.japanese = japanese
        self.romaji = romaji
        self.english = english
    }
}

public struct GrammarScenarioRecord: Codable, Hashable, Sendable {
    public let setting: String?
    public let lines: [GrammarScenarioLineRecord]

    public init(
        setting: String? = nil,
        lines: [GrammarScenarioLineRecord]
    ) {
        self.setting = setting
        self.lines = lines
    }

    // Keep decoding older content that still has payoffSpeaker.
    private enum CodingKeys: String, CodingKey {
        case setting, lines, payoffSpeaker
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        setting = try container.decodeIfPresent(String.self, forKey: .setting)
        lines = try container.decode([GrammarScenarioLineRecord].self, forKey: .lines)
        _ = try container.decodeIfPresent(String.self, forKey: .payoffSpeaker)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(setting, forKey: .setting)
        try container.encode(lines, forKey: .lines)
    }
}

public struct GrammarExampleRecord: Codable, Hashable, Sendable {
    public let japanese: String
    public let romaji: String
    public let english: String
    public let targetSubstring: String?
    public let audioKey: String?
    public let scenario: GrammarScenarioRecord?
    public let sourceScenarioId: String?

    public var resolvedReading: String { romaji }

    public init(
        japanese: String,
        romaji: String,
        english: String,
        targetSubstring: String? = nil,
        audioKey: String? = nil,
        scenario: GrammarScenarioRecord? = nil,
        sourceScenarioId: String? = nil
    ) {
        self.japanese = japanese
        self.romaji = romaji
        self.english = english
        self.targetSubstring = targetSubstring
        self.audioKey = audioKey
        self.scenario = scenario
        self.sourceScenarioId = sourceScenarioId
    }
}

public struct GrammarDrillRecord: Codable, Hashable, Sendable {
    public let kind: GrammarDrillKind
    public let instruction: String?
    public let prompt: String?
    public let choices: [String]
    public let correctChoice: String
    public let exampleJapanese: String?
    public let targetSubstring: String?
    public let contrastLabel: String?
    public let english: String?
    public let buildComponents: [String]?

    public init(
        kind: GrammarDrillKind,
        instruction: String? = nil,
        prompt: String? = nil,
        choices: [String],
        correctChoice: String,
        exampleJapanese: String? = nil,
        targetSubstring: String? = nil,
        contrastLabel: String? = nil,
        english: String? = nil,
        buildComponents: [String]? = nil
    ) {
        self.kind = kind
        self.instruction = instruction
        self.prompt = prompt
        self.choices = choices
        self.correctChoice = correctChoice
        self.exampleJapanese = exampleJapanese
        self.targetSubstring = targetSubstring
        self.contrastLabel = contrastLabel
        self.english = english
        self.buildComponents = buildComponents
    }
}

public enum GrammarDrillKind: String, Codable, CaseIterable, Sendable {
    case formChoice
    case meaningChoice
    case sentenceBuilder
    case sentenceChoice
    case contrastChoice
    case precursorChoice
}
