//
//  VocabSenseRanker.swift
//  shizen
//
//  Picks which stored sense best fits a source sentence.
//  Failure and "model unavailable" both return nil — callers show no pulse.
//

import Foundation
import FoundationModels

/// Plug-in point for sense ranking. The dictionary uses this to choose one
/// sense for a saved flashcard. Assign `VocabSenseRanker.ranker` to swap in
/// an external ranker (JEV) later.
protocol VocabSenseRanking {
    func suggestedIndex(sentence: String, surface: String, senses: [VocabSense]) async -> Int?
}

enum VocabSenseRanker {
    static var ranker: any VocabSenseRanking = PreferredVocabSenseRanker()

    static func suggestedIndex(sentence: String, surface: String, senses: [VocabSense]) async -> Int? {
        await ranker.suggestedIndex(sentence: sentence, surface: surface, senses: senses)
    }
}

/// Follows the app's contextual-gloss backend: on-device, Gemini, or on-device then Gemini.
struct PreferredVocabSenseRanker: VocabSenseRanking {
    func suggestedIndex(sentence: String, surface: String, senses: [VocabSense]) async -> Int? {
        let sentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let surface = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard senses.count > 1, !sentence.isEmpty, !surface.isEmpty, sentence != surface else { return nil }

        switch ContextualGlossBackend.preferred {
        case .onDevice:
            guard FoundationModelContextualGloss.isAvailable else { return nil }
            return await FoundationModelVocabSenseRanker.suggestedIndex(
                sentence: sentence,
                surface: surface,
                senses: senses
            )
        case .gemini:
            guard GeminiContextualGloss.isConfigured else { return nil }
            return await GeminiVocabSenseRanker.suggestedIndex(
                sentence: sentence,
                surface: surface,
                senses: senses
            )
        case .hybrid:
            if FoundationModelContextualGloss.isAvailable,
               let index = await FoundationModelVocabSenseRanker.suggestedIndex(
                sentence: sentence,
                surface: surface,
                senses: senses
               ) {
                return index
            }
            guard GeminiContextualGloss.isConfigured else { return nil }
            return await GeminiVocabSenseRanker.suggestedIndex(
                sentence: sentence,
                surface: surface,
                senses: senses
            )
        }
    }
}

@Generable
struct VocabSenseFitChoice {
    @Guide(description: "Zero-based index of the listed English sense that best fits the Japanese word in the sentence. Must be one of the indexes in the list.")
    var index: Int
}

private enum FoundationModelVocabSenseRanker {
    private static let instructions = """
    You choose which dictionary sense of one Japanese word fits a sentence.
    The user message lists numbered English senses. Return the zero-based index of the best fit.
    Use only an index from that list. Do not invent a meaning.
    """

    private actor Cache {
        static let shared = Cache()
        private var storage: [String: Int] = [:]

        func index(for key: String) -> Int? { storage[key] }
        func store(_ index: Int, for key: String) { storage[key] = index }
    }

    static func suggestedIndex(sentence: String, surface: String, senses: [VocabSense]) async -> Int? {
        let key = cacheKey(sentence: sentence, surface: surface, senses: senses)
        if let cached = await Cache.shared.index(for: key) { return cached }
        guard SystemLanguageModel.default.availability == .available else { return nil }

        do {
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
            let response = try await session.respond(
                to: Prompt(prompt(sentence: sentence, surface: surface, senses: senses)),
                generating: VocabSenseFitChoice.self,
                includeSchemaInPrompt: false,
                options: GenerationOptions(sampling: .greedy)
            )
            guard senses.indices.contains(response.content.index) else { return nil }
            await Cache.shared.store(response.content.index, for: key)
            return response.content.index
        } catch {
            print("[VocabSenseRanker] on-device sense fit failed: \(error.localizedDescription)")
            return nil
        }
    }
}

/// Served by the LLM gateway (feature `sense_fit`); the prompt lives server-side.
private enum GeminiVocabSenseRanker {
    private actor Cache {
        static let shared = Cache()
        private var storage: [String: Int] = [:]

        func index(for key: String) -> Int? { storage[key] }
        func store(_ index: Int, for key: String) { storage[key] = index }
    }

    static func suggestedIndex(sentence: String, surface: String, senses: [VocabSense]) async -> Int? {
        guard GeminiContextualGloss.isConfigured else { return nil }
        let key = cacheKey(sentence: sentence, surface: surface, senses: senses)
        if let cached = await Cache.shared.index(for: key) { return cached }

        do {
            let index = try await fetchIndex(sentence: sentence, surface: surface, senses: senses)
            guard senses.indices.contains(index) else { return nil }
            await Cache.shared.store(index, for: key)
            return index
        } catch {
            print("[VocabSenseRanker] Gemini sense fit failed: \(error.localizedDescription)")
            return nil
        }
    }

    private struct GatewayRequest: Encodable {
        let feature = "sense_fit"
        let sentence: String
        let surface: String
        let senses: [String]
    }

    private struct GatewayResponse: Decodable {
        struct IndexResult: Decodable { let index: Int }

        let result: IndexResult
        let model: String
        let usage: GeminiUsageMetadata?
    }

    private static func fetchIndex(sentence: String, surface: String, senses: [VocabSense]) async throws -> Int {
        let response = try await LLMGatewayClient.post(
            "v1/generate",
            body: GatewayRequest(sentence: sentence, surface: surface, senses: senses.map(\.text)),
            as: GatewayResponse.self
        )
        if let usage = response.usage {
            GeminiUsageTracker.shared.record(feature: .senseFit, model: response.model, usage: usage)
        }
        return response.result.index
    }
}

private func cacheKey(sentence: String, surface: String, senses: [VocabSense]) -> String {
    ([sentence, surface] + senses.map(\.text)).joined(separator: "\u{1F}")
}

private func prompt(sentence: String, surface: String, senses: [VocabSense]) -> String {
    var lines = [
        "Sentence: \(sentence)",
        "Word: \(surface)",
        "Senses:",
    ]
    for (index, sense) in senses.enumerated() {
        lines.append("\(index). \(sense.text)")
    }
    return lines.joined(separator: "\n")
}
