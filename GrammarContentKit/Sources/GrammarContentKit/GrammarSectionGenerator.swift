//
//  GrammarSectionGenerator.swift
//  GrammarContentKit
//

import Foundation

public enum GrammarSectionGenerationTask: Sendable, Equatable {
    case overview
    case formation
    case usage
    case usageLadders
    case example
    case drills
    case drill(GrammarDrillKind)

    public var label: String {
        switch self {
        case .overview: return "overview"
        case .formation: return "formation"
        case .usage: return "usage"
        case .usageLadders: return "usage ladders"
        case .example: return "example"
        case .drills: return "drills"
        case .drill(let kind): return "drill (\(kind.rawValue))"
        }
    }
}

public struct GrammarSectionGenerationResult: Sendable {
    public var blurb: String?
    public var headlineEnglish: String?
    public var forms: [String]?
    public var formation: [GrammarTeachingBlock]?
    public var usage: [GrammarTeachingBlock]?
    public var usageLadders: [GrammarUsageLadderRecord]?
    public var example: GrammarExampleRecord?
    public var drill: GrammarDrillRecord?
    public var drills: [GrammarDrillRecord]?
    public let attemptCount: Int

    public init(attemptCount: Int) {
        self.attemptCount = attemptCount
    }
}

public enum GrammarSectionGenerator {

    private static func contextJSON(for point: GrammarPointRecord) -> String {
        let encoder = ContentStore.encoder()
        let shipping = point.shippingRecord()
        guard let data = try? encoder.encode(shipping),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    private static func goldJSON(_ gold: [GrammarPointRecord]) -> String {
        let encoder = ContentStore.encoder()
        guard !gold.isEmpty,
              let data = try? encoder.encode(["points": gold.map { $0.shippingRecord() }]),
              let text = String(data: data, encoding: .utf8)
        else { return "[]" }
        return text
    }

    public static func taskSummary(for task: GrammarSectionGenerationTask) -> String {
        switch task {
        case .overview:
            return "Write blurb and forms (optionally refine headline English)."
        case .formation:
            return "Write 1–3 formation teaching blocks."
        case .usage:
            return "Write 1–3 usage teaching blocks."
        case .usageLadders:
            return "Write Everyday/Casual/Formal usage ladders for 2–3 verbs."
        case .example:
            return "Write one new example with scenario dialogue when natural."
        case .drills:
            return "Write a full drills set for this point."
        case .drill(let kind):
            return "Write one \(kind.rawValue) drill."
        }
    }

    private static func taskText(for task: GrammarSectionGenerationTask) -> String {
        switch task {
        case .overview:
            return """
            Generate overview content: blurb (1-2 paragraphs, Shizen voice) and forms array. \
            Optionally refine headlineEnglish. Align with the point title and any existing examples.
            """
        case .formation:
            return """
            Generate 1-3 formation teaching blocks explaining how to build this pattern. \
            Must synergize with blurb, forms, and existing examples. Append-quality content.
            """
        case .usage:
            return """
            Generate 1-3 usage teaching blocks: when/how to use, nuance, pitfalls. \
            Must synergize with formation, blurb, and examples.
            """
        case .usageLadders:
            return """
            Generate usageLadders with Everyday/Casual/Formal register levels for 2-3 verbs relevant to this pattern.
            """
        case .example:
            return """
            Generate ONE new example (japanese, romaji, english, targetSubstring). \
            Use a fresh situation not covered by existing examples. Include scenario dialogue when natural. \
            targetSubstring must appear verbatim in japanese.
            """
        case .drills:
            return """
            Generate a complete drills array for this point from its examples and teaching. \
            Include meaningChoice, sentenceBuilder, sentenceChoice. Use real example sentences for precursorChoice. \
            For sentenceBuilder: set buildComponents to the correct tiles and correctChoice to their concatenation.
            """
        case .drill(let kind):
            return """
            Generate ONE \(kind.rawValue) drill synergistic with this point's examples and teaching. \
            For sentenceBuilder: set buildComponents to the correct tiles and correctChoice to their concatenation. \
            For other kinds: correctChoice must be in choices.
            """
        }
    }

    private static func schema(for task: GrammarSectionGenerationTask) -> String {
        switch task {
        case .overview:
            return #"{"blurb":"string","forms":["string"],"headlineEnglish":"optional string"}"#
        case .formation:
            return #"{"formation":[{"title":"optional string","body":"string"}]}"#
        case .usage:
            return #"{"usage":[{"title":"optional string","body":"string"}]}"#
        case .usageLadders:
            return #"{"usageLadders":[{"label":"verb","levels":[{"japanese":"...","register":"Everyday|Casual|Formal"}]}]}"#
        case .example:
            return #"{"example":{"japanese":"...","romaji":"...","english":"...","targetSubstring":"...","scenario":{"setting":"...","lines":[{"speaker":"...","japanese":"...","romaji":"...","english":"..."}]}}}"#
        case .drills:
            return #"{"drills":[{"kind":"meaningChoice|sentenceBuilder|sentenceChoice|formChoice|contrastChoice|precursorChoice","instruction":"...","choices":["..."],"correctChoice":"...","english":"optional","buildComponents":["optional"],"exampleJapanese":"optional","targetSubstring":"optional"}]}"#
        case .drill(let kind):
            return #"{"drill":{"kind":"\(kind.rawValue)","instruction":"...","choices":["..."],"correctChoice":"...","english":"optional","buildComponents":["optional"],"exampleJapanese":"optional","targetSubstring":"optional"}}"#
        }
    }

    public static func buildPrompt(
        task: GrammarSectionGenerationTask,
        context: GrammarPointRecord,
        goldExamples: [GrammarPointRecord],
        customInstructions: String? = nil
    ) -> String {
        let taskText = taskText(for: task)
        let schema = schema(for: task)
        let authorInstructions = trimmedOrNil(customInstructions)

        return """
        You are authoring JLPT N5 grammar lesson content for the Shizen Japanese learning app.

        Current grammar point (use as context — stay consistent):
        \(contextJSON(for: context))

        Gold-standard approved points (match depth and voice):
        \(goldJSON(goldExamples))

        Task: \(taskText)
        \(authorInstructions.map { "\nAuthor instructions (follow carefully):\n\($0)\n" } ?? "")

        Return JSON matching this schema:
        \(schema)

        Rules:
        - Shizen voice: clear, learner-focused.
        - Romaji lowercase with spaces.
        - Synergize with existing content; do not contradict examples or formation.
        - No status, reviewNotes, or _provenance fields.
        """
    }

    private struct OverviewPayload: Decodable { let blurb: String?; let forms: [String]?; let headlineEnglish: String? }
    private struct FormationPayload: Decodable { let formation: [GrammarTeachingBlock] }
    private struct UsagePayload: Decodable { let usage: [GrammarTeachingBlock] }
    private struct UsageLaddersPayload: Decodable { let usageLadders: [GrammarUsageLadderRecord] }
    private struct ExamplePayload: Decodable { let example: GrammarExampleRecord }
    private struct DrillPayload: Decodable { let drill: GrammarDrillRecord }
    private struct DrillsPayload: Decodable { let drills: [GrammarDrillRecord] }

    public static func generate(
        task: GrammarSectionGenerationTask,
        context: GrammarPointRecord,
        apiKey: String,
        goldExamples: [GrammarPointRecord],
        customInstructions: String? = nil,
        model: GeminiClient.Model = .flash,
        maxAttempts: Int = 3
    ) async throws -> GrammarSectionGenerationResult {
        var lastError = "Unknown error"
        var attempt = 0

        while attempt < maxAttempts {
            attempt += 1
            var prompt = buildPrompt(
                task: task,
                context: context,
                goldExamples: goldExamples,
                customInstructions: customInstructions
            )
            if attempt > 1 {
                prompt += "\n\nPrevious attempt failed: \(lastError). Fix and return valid JSON."
            }

            let jsonData = try await GeminiClient.generateJSON(
                apiKey: apiKey,
                prompt: prompt,
                model: model,
                temperature: attempt == 1 ? 0.4 : 0.2,
                useSchema: false
            )

            do {
                let result = try decodeResult(jsonData: jsonData, task: task, attemptCount: attempt)
                let merged = apply(result, to: context)
                let issues = ContentValidator.validatePoint(merged)
                if issues.isEmpty {
                    return result
                }
                lastError = issues.map(\.message).joined(separator: "; ")
            } catch {
                lastError = error.localizedDescription
            }
        }

        throw GeminiClient.ClientError.api(
            "Section generation failed after \(maxAttempts) attempts: \(lastError)"
        )
    }

    private static func normalizedSectionJSON(_ jsonData: Data) throws -> Data {
        var text = String(data: jsonData, encoding: .utf8) ?? ""
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let data = text.data(using: .utf8) ?? jsonData

        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else { return data }

        // Full-point generation wraps sections in grammarPoint; unwrap only that case.
        if let wrapped = dict["grammarPoint"] {
            return try JSONSerialization.data(withJSONObject: wrapped)
        }

        return data
    }

    private static func decodeErrorMessage(_ error: Error, task: GrammarSectionGenerationTask) -> String {
        if let decoding = error as? DecodingError {
            switch decoding {
            case .keyNotFound(let key, let context):
                return "Missing JSON key '\(key.stringValue)' in \(task.label) response (\(context.codingPath.map(\.stringValue).joined(separator: ".")))"
            case .typeMismatch(let type, let context):
                return "Unexpected type for \(type) in \(task.label) response (\(context.codingPath.map(\.stringValue).joined(separator: ".")))"
            case .valueNotFound(let type, let context):
                return "Missing value for \(type) in \(task.label) response (\(context.codingPath.map(\.stringValue).joined(separator: ".")))"
            case .dataCorrupted(let context):
                return "Invalid JSON for \(task.label): \(context.debugDescription)"
            @unknown default:
                break
            }
        }
        return error.localizedDescription
    }

    private struct GeneratedScenario: Decodable {
        let setting: String?
        let lines: [GrammarScenarioLineRecord]?

        var record: GrammarScenarioRecord? {
            guard let lines, !lines.isEmpty else { return nil }
            return GrammarScenarioRecord(
                setting: trimmedOrNil(setting),
                lines: lines
            )
        }
    }

    private struct GeneratedExample: Decodable {
        let japanese: String?
        let romaji: String?
        let english: String?
        let targetSubstring: String?
        let audioKey: String?
        let scenario: GeneratedScenario?

        func toRecord() throws -> GrammarExampleRecord {
            guard let japanese = trimmedOrNil(japanese) else {
                throw GeminiClient.ClientError.invalidResponse
            }
            guard let english = trimmedOrNil(english) else {
                throw GeminiClient.ClientError.invalidResponse
            }
            return GrammarExampleRecord(
                japanese: japanese,
                romaji: trimmedOrNil(romaji) ?? "",
                english: english,
                targetSubstring: trimmedOrNil(targetSubstring),
                audioKey: trimmedOrNil(audioKey),
                scenario: scenario?.record
            )
        }
    }

    private struct GeneratedExampleWrapper: Decodable { let example: GeneratedExample }
    private struct ExamplesArrayPayload: Decodable { let examples: [GeneratedExample] }

    private static func decodeExample(from payload: Data, decoder: JSONDecoder) throws -> GrammarExampleRecord {
        if let wrapped = try? decoder.decode(GeneratedExampleWrapper.self, from: payload) {
            return try wrapped.example.toRecord()
        }
        if let wrapped = try? decoder.decode(GeneratedExample.self, from: payload) {
            return try wrapped.toRecord()
        }
        if let wrapped = try? decoder.decode(ExamplesArrayPayload.self, from: payload),
           let first = wrapped.examples.first {
            return try first.toRecord()
        }
        if let wrapped = try? decoder.decode(ExamplePayload.self, from: payload) {
            return wrapped.example
        }
        throw GeminiClient.ClientError.invalidResponse
    }

    private static func decodeFormation(from payload: Data, decoder: JSONDecoder) throws -> [GrammarTeachingBlock] {
        if let wrapped = try? decoder.decode(FormationPayload.self, from: payload), !wrapped.formation.isEmpty {
            return wrapped.formation
        }
        if let direct = try? decoder.decode([GrammarTeachingBlock].self, from: payload), !direct.isEmpty {
            return direct
        }
        throw GeminiClient.ClientError.invalidResponse
    }

    private static func decodeUsage(from payload: Data, decoder: JSONDecoder) throws -> [GrammarTeachingBlock] {
        if let wrapped = try? decoder.decode(UsagePayload.self, from: payload), !wrapped.usage.isEmpty {
            return wrapped.usage
        }
        if let direct = try? decoder.decode([GrammarTeachingBlock].self, from: payload), !direct.isEmpty {
            return direct
        }
        throw GeminiClient.ClientError.invalidResponse
    }

    private static func decodeUsageLadders(from payload: Data, decoder: JSONDecoder) throws -> [GrammarUsageLadderRecord] {
        if let wrapped = try? decoder.decode(UsageLaddersPayload.self, from: payload), !wrapped.usageLadders.isEmpty {
            return wrapped.usageLadders
        }
        if let direct = try? decoder.decode([GrammarUsageLadderRecord].self, from: payload), !direct.isEmpty {
            return direct
        }
        throw GeminiClient.ClientError.invalidResponse
    }

    private static func decodeDrills(from payload: Data, decoder: JSONDecoder) throws -> [GrammarDrillRecord] {
        if let wrapped = try? decoder.decode(DrillsPayload.self, from: payload), !wrapped.drills.isEmpty {
            return wrapped.drills
        }
        if let direct = try? decoder.decode([GrammarDrillRecord].self, from: payload), !direct.isEmpty {
            return direct
        }
        throw GeminiClient.ClientError.invalidResponse
    }

    private static func decodeDrill(from payload: Data, decoder: JSONDecoder) throws -> GrammarDrillRecord {
        if let wrapped = try? decoder.decode(DrillPayload.self, from: payload) {
            return wrapped.drill
        }
        if let direct = try? decoder.decode(GrammarDrillRecord.self, from: payload) {
            return direct
        }
        throw GeminiClient.ClientError.invalidResponse
    }

    private static func decodeResult(
        jsonData: Data,
        task: GrammarSectionGenerationTask,
        attemptCount: Int
    ) throws -> GrammarSectionGenerationResult {
        let decoder = JSONDecoder()
        let payload = try normalizedSectionJSON(jsonData)
        var result = GrammarSectionGenerationResult(attemptCount: attemptCount)

        do {
            switch task {
            case .overview:
                let p = try decoder.decode(OverviewPayload.self, from: payload)
                result.blurb = p.blurb
                result.forms = p.forms
                result.headlineEnglish = p.headlineEnglish
            case .formation:
                result.formation = try decodeFormation(from: payload, decoder: decoder)
            case .usage:
                result.usage = try decodeUsage(from: payload, decoder: decoder)
            case .usageLadders:
                result.usageLadders = try decodeUsageLadders(from: payload, decoder: decoder)
            case .example:
                result.example = try decodeExample(from: payload, decoder: decoder)
            case .drills:
                result.drills = try decodeDrills(from: payload, decoder: decoder)
            case .drill:
                result.drill = try decodeDrill(from: payload, decoder: decoder)
            }
        } catch {
            throw GeminiClient.ClientError.api(decodeErrorMessage(error, task: task))
        }

        return result
    }

    private static func apply(
        _ result: GrammarSectionGenerationResult,
        to point: GrammarPointRecord
    ) -> GrammarPointRecord {
        var p = point
        if let blurb = result.blurb { p = copy(p, blurb: blurb) }
        if let headline = result.headlineEnglish { p = copy(p, headlineEnglish: headline) }
        if let forms = result.forms { p = copy(p, forms: forms) }
        if let formation = result.formation {
            p = copy(p, formation: p.formation + formation)
        }
        if let usage = result.usage {
            p = copy(p, usage: (p.usage ?? []) + usage)
        }
        if let ladders = result.usageLadders {
            p = copy(p, usageLadders: (p.usageLadders ?? []) + ladders)
        }
        if let example = result.example {
            p = copy(p, examples: p.examples + [example])
        }
        if let drill = result.drill {
            p = copy(p, drills: p.drills + [drill])
        }
        if let drills = result.drills {
            p = copy(p, drills: drills)
        }
        return p
    }

    private static func trimmedOrNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func copy(
        _ point: GrammarPointRecord,
        blurb: String? = nil,
        headlineEnglish: String? = nil,
        forms: [String]? = nil,
        formation: [GrammarTeachingBlock]? = nil,
        usage: [GrammarTeachingBlock]? = nil,
        usageLadders: [GrammarUsageLadderRecord]? = nil,
        examples: [GrammarExampleRecord]? = nil,
        drills: [GrammarDrillRecord]? = nil
    ) -> GrammarPointRecord {
        GrammarPointRecord(
            id: point.id,
            orderIndex: point.orderIndex,
            title: point.title,
            headlineEnglish: headlineEnglish ?? point.headlineEnglish,
            blurb: blurb ?? point.blurb,
            forms: forms ?? point.forms,
            formation: formation ?? point.formation,
            formationExamples: point.formationExamples,
            usage: usage ?? point.usage,
            usageLadders: usageLadders ?? point.usageLadders,
            relatedPointIDs: point.relatedPointIDs,
            examples: examples ?? point.examples,
            drills: drills ?? point.drills,
            status: point.status,
            reviewNotes: point.reviewNotes,
            provenance: point.provenance
        )
    }
}
