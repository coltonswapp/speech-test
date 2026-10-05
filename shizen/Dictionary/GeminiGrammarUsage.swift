//
//  GeminiGrammarUsage.swift
//  shizen
//
//  How a grammar pattern from a dialogue is used: what it does in the scene,
//  how to build it, and a few new examples. Served by the LLM gateway
//  (feature `grammar_usage`); the prompt lives server-side.
//

import Foundation

enum GeminiGrammarUsage {

    struct Line: Equatable {
        let speaker: String
        let japanese: String
        let english: String?
        /// True for lines that use the pattern.
        let focus: Bool
    }

    struct Request: Equatable {
        let pattern: String
        let grammarPointID: String?
        let lines: [Line]
    }

    struct Result: Equatable {
        let inThisScene: String
        let form: String
        let examples: [String]
        let note: String
    }

    struct Explanation {
        let result: Result
        let feedback: LLMFeedbackReceipt?
    }

    static let maxLines = 12

    private actor Cache {
        static let shared = Cache()
        private var storage: [String: Explanation] = [:]

        func result(for key: String) -> Explanation? { storage[key] }

        func store(_ result: Explanation, for key: String) { storage[key] = result }
    }

    static var isConfigured: Bool { LLMGatewayClient.isAvailable }

    static var unavailabilityMessage: String {
        LLMGatewayClient.unavailabilityMessage(signInPrompt: "Sign in to see how this grammar is used.")
    }

    /// Scene lines for a pattern, with the lines that use it marked. Tagged lines win;
    /// otherwise lines containing the label's fixed text. When nothing matches, no line
    /// is marked and the gateway finds it.
    static func request(
        for pattern: DialogueGrammarPatternRef,
        in scenarioLines: [GrammarScenarioLine]
    ) -> Request? {
        let spoken = scenarioLines.filter {
            $0.isSpokenLine && !$0.japanese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !spoken.isEmpty else { return nil }

        let fixedText = patternFixedText(pattern.label)
        let evidence: Set<Int> = {
            guard let indices = pattern.sourceSpokenIndices else { return [] }
            return Set(indices.filter { spoken.indices.contains($0) })
        }()
        let tagged: Set<Int> = pattern.grammarPointID.map { id in
            Set(spoken.indices.filter { spoken[$0].grammarPointIDs.contains(id) })
        } ?? []
        let matched: Set<Int> = {
            if !evidence.isEmpty { return evidence }
            if !tagged.isEmpty { return tagged }
            if !fixedText.isEmpty {
                return Set(spoken.indices.filter { spoken[$0].japanese.contains(fixedText) })
            }
            return []
        }()

        let window = linesWindow(count: spoken.count, around: matched)
        let lines = window.map { index in
            let line = spoken[index]
            return Line(
                speaker: line.speaker,
                japanese: line.japanese,
                english: line.english,
                focus: matched.contains(index)
            )
        }
        return Request(pattern: pattern.label, grammarPointID: pattern.grammarPointID, lines: lines)
    }

    static func cachedResult(for request: Request) async -> Explanation? {
        await Cache.shared.result(for: cacheKey(for: request))
    }

    static func explain(_ request: Request) async throws -> Explanation {
        let pattern = request.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty, !request.lines.isEmpty else {
            throw GeminiTokenLookupError.invalidInput
        }

        let cacheKey = Self.cacheKey(for: request)
        if let cached = await Cache.shared.result(for: cacheKey) {
            return cached
        }
        guard isConfigured else {
            throw GeminiTokenLookupError.unavailable(unavailabilityMessage)
        }

        print("[GeminiGrammarUsage] explaining \"\(pattern)\" via gateway")
        let response = try await LLMGatewayClient.postGenerate(
            "v1/generate",
            body: GatewayRequest(
                pattern: pattern,
                grammarPointID: request.grammarPointID,
                lines: request.lines.prefix(maxLines).map(GatewayLine.init)
            ),
            as: Payload.self
        )
        if let usage = response.usage {
            GeminiUsageTracker.shared.record(feature: .grammarUsage, model: response.model, usage: usage)
        }

        let result = sanitized(response.result)
        guard !result.inThisScene.isEmpty else {
            throw GeminiTokenLookupError.emptyResponse
        }
        let explanation = Explanation(result: result, feedback: response.feedback)
        await Cache.shared.store(explanation, for: cacheKey)
        return explanation
    }

    // MARK: - Gateway

    private struct GatewayLine: Encodable {
        let speaker: String?
        let japanese: String
        let english: String?
        let focus: Bool

        init(_ line: Line) {
            let speaker = line.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
            let english = line.english?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.speaker = speaker.isEmpty ? nil : speaker
            japanese = line.japanese.trimmingCharacters(in: .whitespacesAndNewlines)
            self.english = english?.isEmpty == false ? english : nil
            focus = line.focus
        }
    }

    private struct GatewayRequest: Encodable {
        let feature = "grammar_usage"
        let pattern: String
        let grammarPointID: String?
        let lines: [GatewayLine]
    }

    private struct Payload: Decodable {
        let inThisScene: String
        let form: String
        let examples: [String]
        let note: String

        enum CodingKeys: String, CodingKey {
            case inThisScene, form, examples, note
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            inThisScene = try container.decode(String.self, forKey: .inThisScene)
            form = try container.decodeIfPresent(String.self, forKey: .form) ?? ""
            examples = try container.decodeIfPresent([String].self, forKey: .examples) ?? []
            note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        }
    }

    private static func sanitized(_ payload: Payload) -> Result {
        let here = glossWithoutVerbLabel(payload.inThisScene.trimmingCharacters(in: .whitespacesAndNewlines))
        var seen = Set<String>()
        var examples: [String] = []
        for raw in payload.examples {
            let example = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !example.isEmpty, example.count <= 160, seen.insert(example).inserted else { continue }
            examples.append(example)
            if examples.count == 3 { break }
        }
        let note = payload.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return Result(
            inThisScene: here,
            form: payload.form.trimmingCharacters(in: .whitespacesAndNewlines),
            examples: examples,
            note: note == here ? "" : note
        )
    }

    /// "___ ちゃいけない" → "ちゃいけない"; "〜ていい？" → "ていい".
    private static func patternFixedText(_ label: String) -> String {
        let dropped = CharacterSet(charactersIn: "_＿〜~～?？!！。、.・… ")
            .union(.whitespacesAndNewlines)
        let pieces = label.components(separatedBy: dropped).filter { !$0.isEmpty }
        return pieces.max { $0.count < $1.count } ?? ""
    }

    /// Whole scene when it fits; otherwise lines around the first and last match.
    private static func linesWindow(count: Int, around matched: Set<Int>) -> [Int] {
        guard count > maxLines else { return Array(0..<count) }
        guard let first = matched.min(), let last = matched.max() else {
            return Array(0..<maxLines)
        }
        let span = last - first + 1
        let pad = max(0, (maxLines - span) / 2)
        let start = min(max(0, first - pad), count - maxLines)
        return Array(start..<(start + maxLines))
    }

    private static func cacheKey(for request: Request) -> String {
        let lines = request.lines.map { line in
            [line.speaker, line.japanese, line.english ?? "", line.focus ? "1" : "0"]
                .joined(separator: "\u{1E}")
        }
        return [
            "gemini-grammar-usage-v1-gateway",
            request.pattern,
            request.grammarPointID ?? "",
            lines.joined(separator: "\u{1D}"),
        ].joined(separator: "\u{1F}")
    }
}
