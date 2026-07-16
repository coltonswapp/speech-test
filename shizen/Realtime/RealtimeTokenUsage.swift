//
//  RealtimeTokenUsage.swift
//  shizen
//
//  Cumulative token usage for an OpenAI Realtime session (parsed from response.done).
//

import Foundation

struct RealtimeTokenUsage: Equatable {
    var totalInputTokens: Int = 0
    var inputTextTokens: Int = 0
    var inputAudioTokens: Int = 0
    var cachedTokens: Int = 0
    var totalOutputTokens: Int = 0
    var outputTextTokens: Int = 0
    var outputAudioTokens: Int = 0

    var totalTokens: Int { totalInputTokens + totalOutputTokens }

    mutating func accumulate(from responseUsage: [String: Any]) {
        if let input = responseUsage["input_tokens"] as? Int {
            totalInputTokens += input
        }
        if let output = responseUsage["output_tokens"] as? Int {
            totalOutputTokens += output
        }
        if let total = responseUsage["total_tokens"] as? Int, totalInputTokens == 0, totalOutputTokens == 0 {
            // Some payloads only expose total_tokens at the top level.
            _ = total
        }

        if let inputDetails = responseUsage["input_token_details"] as? [String: Any] {
            if let text = inputDetails["text_tokens"] as? Int {
                inputTextTokens += text
            }
            if let audio = inputDetails["audio_tokens"] as? Int {
                inputAudioTokens += audio
            }
            if let cached = inputDetails["cached_tokens"] as? Int {
                cachedTokens += cached
            }
        }

        if let outputDetails = responseUsage["output_token_details"] as? [String: Any] {
            if let text = outputDetails["text_tokens"] as? Int {
                outputTextTokens += text
            }
            if let audio = outputDetails["audio_tokens"] as? Int {
                outputAudioTokens += audio
            }
        }
    }

    var summaryLine: String {
        String(
            format: "In: %d (text %d, audio %d, cached %d) · Out: %d (text %d, audio %d) · Total: %d",
            totalInputTokens,
            inputTextTokens,
            inputAudioTokens,
            cachedTokens,
            totalOutputTokens,
            outputTextTokens,
            outputAudioTokens,
            totalTokens
        )
    }
}
