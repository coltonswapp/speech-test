//
//  GrammarPointGenerator.swift
//  GrammarContentKit
//

import Foundation

public struct GrammarGenerationRequest: Sendable {
    public let pointID: String
    public let title: String
    public let headlineEnglish: String?
    public let orderIndex: Int

    public init(pointID: String, title: String, headlineEnglish: String? = nil, orderIndex: Int) {
        self.pointID = pointID
        self.title = title
        self.headlineEnglish = headlineEnglish
        self.orderIndex = orderIndex
    }
}

public struct GrammarGenerationResult: Sendable {
    public let point: GrammarPointRecord
    public let validationIssues: [ContentValidationIssue]
    public let attemptCount: Int
}

public enum GrammarPointGenerator {

    private static let schemaDescription = """
    Return a JSON object with a single key "grammarPoint" whose value matches this schema:

    {
      "id": "string (slug like n5-cha-ikenai)",
      "orderIndex": number,
      "title": "Japanese pattern name",
      "pattern": "display pattern (defaults to title)",
      "reading": "romaji reading of the pattern",
      "shortDefinition": "one-line English gloss",
      "headlineEnglish": "same as shortDefinition for compatibility",
      "blurb": "contextual paragraph: register, nuance, who says it",
      "structure": "how the pattern is built — formation rule as plain text",
      "register": "casual|polite|formal",
      "forms": ["surface forms"],
      "formation": [{"title": "optional", "body": "legacy teaching blocks — mirror structure"}],
      "relatedPointIDs": ["other point ids"],
      "examples": [{
        "japanese": "...",
        "romaji": "...",
        "english": "...",
        "targetSubstring": "highlighted morpheme",
        "sourceScenarioId": "optional dialogue scenario id",
        "scenario": {
          "setting": "one-line English scene setter",
          "lines": [{"speaker": "...", "japanese": "...", "romaji": "...", "english": "..."}]
        }
      }],
      "contrastDrills": [{
        "contrastLabel": "のむ → のんで → ?",
        "choices": ["のんちゃ", "のんじゃ"],
        "correctChoice": "のんじゃ",
        "ruleTargeted": "optional note on the rule tested"
      }]
    }

    Rules:
    - 3-4 curated examples per point; at least one with a 2-4 line scenario dialogue.
    - Include 1-3 contrastDrills only. Do NOT include meaningChoice, formChoice, sentenceBuilder, or precursorChoice drills.
    - Write in Shizen voice: clear, learner-focused, not textbook-dry.
    - Romaji should be lowercase with spaces between words.
    - targetSubstring must appear verbatim in the example japanese.
    - Do not include status, reviewNotes, or _provenance fields.
    """

    public static func buildPrompt(
        request: GrammarGenerationRequest,
        goldExamples: [GrammarPointRecord]
    ) -> String {
        let encoder = ContentStore.encoder()
        let goldJSON: String = {
            guard !goldExamples.isEmpty else { return "[]" }
            let shipping = goldExamples.map { $0.shippingRecord() }
            guard let data = try? encoder.encode(["points": shipping]),
                  let text = String(data: data, encoding: .utf8)
            else { return "[]" }
            return text
        }()

        let headline = request.headlineEnglish.map { " (\($0))" } ?? ""
        return """
        You are authoring JLPT N5 grammar reference content for the Shizen Japanese learning app.

        \(schemaDescription)

        Gold-standard approved examples (match this depth and voice):
        \(goldJSON)

        Generate a complete grammar point for:
        - id: \(request.pointID)
        - orderIndex: \(request.orderIndex)
        - title: \(request.title)\(headline)

        Return only valid JSON with the grammarPoint wrapper object.
        """
    }

    private struct GenerationPayload: Decodable {
        let grammarPoint: GrammarPointRecord
    }

    public static func generate(
        request: GrammarGenerationRequest,
        apiKey: String,
        goldExamples: [GrammarPointRecord],
        model: GeminiClient.Model = .flash,
        maxAttempts: Int = 3
    ) async throws -> GrammarGenerationResult {
        var lastIssues: [ContentValidationIssue] = []
        var attempt = 0

        while attempt < maxAttempts {
            attempt += 1
            var prompt = buildPrompt(request: request, goldExamples: goldExamples)
            if attempt > 1, !lastIssues.isEmpty {
                let feedback = lastIssues.map(\.message).joined(separator: "; ")
                prompt += "\n\nPrevious attempt failed validation: \(feedback). Fix all issues."
            }

            let jsonData = try await GeminiClient.generateJSON(
                apiKey: apiKey,
                prompt: prompt,
                model: model,
                temperature: attempt == 1 ? 0.4 : 0.2
            )

            let point: GrammarPointRecord
            do {
                let payload = try JSONDecoder().decode(GenerationPayload.self, from: jsonData)
                point = payload.grammarPoint
            } catch {
                if let direct = try? JSONDecoder().decode(GrammarPointRecord.self, from: jsonData) {
                    point = direct
                } else {
                    lastIssues = [ContentValidationIssue("Could not decode grammarPoint: \(error.localizedDescription)")]
                    continue
                }
            }

            let normalized = GrammarPointRecord(
                id: request.pointID,
                orderIndex: request.orderIndex,
                title: point.title,
                headlineEnglish: point.headlineEnglish,
                blurb: point.blurb,
                forms: point.forms,
                formation: point.formation,
                formationExamples: point.formationExamples,
                usage: point.usage,
                usageLadders: point.usageLadders,
                relatedPointIDs: point.relatedPointIDs,
                examples: point.examples,
                drills: point.drills,
                status: .draft,
                reviewNotes: nil,
                provenance: point.provenance
            )

            let issues = ContentValidator.validatePoint(normalized)
            if issues.isEmpty {
                return GrammarGenerationResult(point: normalized, validationIssues: [], attemptCount: attempt)
            }
            lastIssues = issues
        }

        throw GeminiClient.ClientError.api(
            "Generation failed after \(maxAttempts) attempts: \(lastIssues.map(\.message).joined(separator: "; "))"
        )
    }

    public static func generateBatch(
        requests: [GrammarGenerationRequest],
        apiKey: String,
        goldExamples: [GrammarPointRecord],
        model: GeminiClient.Model = .flash,
        onProgress: (@Sendable (GrammarGenerationRequest, Result<GrammarGenerationResult, Error>) -> Void)? = nil
    ) async -> [(GrammarGenerationRequest, Result<GrammarGenerationResult, Error>)] {
        var results: [(GrammarGenerationRequest, Result<GrammarGenerationResult, Error>)] = []
        for request in requests {
            do {
                let result = try await generate(
                    request: request,
                    apiKey: apiKey,
                    goldExamples: goldExamples,
                    model: model
                )
                results.append((request, .success(result)))
                onProgress?(request, .success(result))
            } catch {
                results.append((request, .failure(error)))
                onProgress?(request, .failure(error))
            }
        }
        return results
    }
}

public enum N5GrammarPointCatalog {

    public struct Seed: Identifiable, Sendable, Hashable {
        public let id: String
        public let title: String
        public let headlineEnglish: String
        public let orderIndex: Int

        public init(id: String, title: String, headlineEnglish: String, orderIndex: Int) {
            self.id = id
            self.title = title
            self.headlineEnglish = headlineEnglish
            self.orderIndex = orderIndex
        }
    }

    public static let seeds: [Seed] = [
        Seed(id: "n5-wa", title: "は", headlineEnglish: "topic marker", orderIndex: 0),
        Seed(id: "n5-ga-1", title: "が (subject)", headlineEnglish: "subject marker", orderIndex: 1),
        Seed(id: "n5-ga-2", title: "が (but)", headlineEnglish: "but; however", orderIndex: 2),
        Seed(id: "n5-ka-1", title: "か (question)", headlineEnglish: "question particle", orderIndex: 3),
        Seed(id: "n5-ka-2", title: "か (or)", headlineEnglish: "or", orderIndex: 4),
        Seed(id: "n5-ni", title: "に", headlineEnglish: "to; at; in", orderIndex: 5),
        Seed(id: "n5-ni-e", title: "に行く", headlineEnglish: "go to", orderIndex: 6),
        Seed(id: "n5-de-1", title: "で (location)", headlineEnglish: "at; by means of", orderIndex: 7),
        Seed(id: "n5-de-2", title: "で (reason)", headlineEnglish: "because of", orderIndex: 8),
        Seed(id: "n5-mo", title: "も", headlineEnglish: "also; too", orderIndex: 9),
        Seed(id: "n5-cha-ikenai", title: "ちゃいけない・じゃいけない", headlineEnglish: "must not; may not (casual)", orderIndex: 10),
        Seed(id: "n5-te-wa-ikenai", title: "てはいけない", headlineEnglish: "must not (standard)", orderIndex: 11),
        Seed(id: "n5-nakucha", title: "なくちゃ", headlineEnglish: "have to (casual)", orderIndex: 12),
        Seed(id: "n5-na-prohibitive", title: "な (prohibitive)", headlineEnglish: "don't (casual command)", orderIndex: 13),
        Seed(id: "n5-naide-kudasai", title: "ないでください", headlineEnglish: "please don't", orderIndex: 14),
        Seed(id: "n5-te-mo-ii", title: "てもいい", headlineEnglish: "may; it's okay to", orderIndex: 15),
        Seed(id: "n5-te-kudasai", title: "てください", headlineEnglish: "please do", orderIndex: 16),
        Seed(id: "n5-hou-ga-ii-1", title: "ほうがいい (advice)", headlineEnglish: "had better", orderIndex: 17),
        Seed(id: "n5-hou-ga-ii-2", title: "ほうがいい (comparison)", headlineEnglish: "better to", orderIndex: 18),
        Seed(id: "n5-suru", title: "する", headlineEnglish: "do", orderIndex: 19),
        Seed(id: "n5-da-desu", title: "だ・です", headlineEnglish: "to be", orderIndex: 20),
        Seed(id: "n5-te-iru", title: "ている", headlineEnglish: "ongoing action / state", orderIndex: 21),
        Seed(id: "n5-te-kara", title: "てから", headlineEnglish: "after doing", orderIndex: 22),
        Seed(id: "n5-tai", title: "たい", headlineEnglish: "want to", orderIndex: 23),
        Seed(id: "n5-naru", title: "なる", headlineEnglish: "become", orderIndex: 24),
        Seed(id: "n5-tsumori", title: "つもり", headlineEnglish: "intend to", orderIndex: 25),
        Seed(id: "n5-ni-iku", title: "に行く", headlineEnglish: "go to do", orderIndex: 26),
        Seed(id: "n5-ni-suru", title: "にする", headlineEnglish: "decide on", orderIndex: 27),
        Seed(id: "n5-ga-aru", title: "がある", headlineEnglish: "there is (inanimate)", orderIndex: 28),
        Seed(id: "n5-ga-iru", title: "がいる", headlineEnglish: "there is (animate)", orderIndex: 29),
        Seed(id: "n5-ichiban", title: "いちばん", headlineEnglish: "the most", orderIndex: 30),
        Seed(id: "n5-kurai", title: "くらい・ぐらい", headlineEnglish: "about; to the extent", orderIndex: 31),
        Seed(id: "n5-dake", title: "だけ", headlineEnglish: "only", orderIndex: 32),
        Seed(id: "n5-yori-hou-ga", title: "より〜ほうが", headlineEnglish: "more than", orderIndex: 33),
        Seed(id: "n5-ta-koto-ga-aru", title: "たことがある", headlineEnglish: "have done before", orderIndex: 34),
        Seed(id: "n5-no-1", title: "の (possessive)", headlineEnglish: "possessive", orderIndex: 35),
        Seed(id: "n5-no-2", title: "の (nominalizer)", headlineEnglish: "the one who / thing that", orderIndex: 36),
        Seed(id: "n5-no-ga-heta", title: "のが下手", headlineEnglish: "bad at", orderIndex: 37),
        Seed(id: "n5-no-ga-jouzu", title: "のが上手", headlineEnglish: "good at", orderIndex: 38),
        Seed(id: "n5-kara", title: "から", headlineEnglish: "because; from", orderIndex: 39),
        Seed(id: "n5-node", title: "ので", headlineEnglish: "because (softer)", orderIndex: 40),
        Seed(id: "n5-kedo", title: "けど", headlineEnglish: "but", orderIndex: 41),
        Seed(id: "n5-nagara", title: "ながら", headlineEnglish: "while", orderIndex: 42),
        Seed(id: "n5-to", title: "と", headlineEnglish: "and; with; when", orderIndex: 43),
        Seed(id: "n5-tara", title: "たら", headlineEnglish: "if; when", orderIndex: 44),
        Seed(id: "n5-nara", title: "なら", headlineEnglish: "if (given)", orderIndex: 45),
        Seed(id: "n5-ba", title: "ば", headlineEnglish: "if (conditional)", orderIndex: 46),
        Seed(id: "n5-to-omou", title: "と思う", headlineEnglish: "think that", orderIndex: 47),
        Seed(id: "n5-you-da", title: "ようだ", headlineEnglish: "seems like", orderIndex: 48),
        Seed(id: "n5-rashii", title: "らしい", headlineEnglish: "seems; I hear", orderIndex: 49),
        Seed(id: "n5-sou-da", title: "そうだ", headlineEnglish: "looks like", orderIndex: 50),
        Seed(id: "n5-te-shimau", title: "てしまう", headlineEnglish: "end up doing", orderIndex: 51),
        Seed(id: "n5-te-aru", title: "てある", headlineEnglish: "has been done (state)", orderIndex: 52),
        Seed(id: "n5-te-oku", title: "ておく", headlineEnglish: "do in advance", orderIndex: 53),
        Seed(id: "n5-te-miru", title: "てみる", headlineEnglish: "try doing", orderIndex: 54),
    ]
}
