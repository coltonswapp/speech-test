//
//  TTSProvider.swift
//  TTSCore
//

import Foundation

public enum TTSProvider: String, CaseIterable, Codable, Sendable {
    case openAI
    case elevenLabs
    case gemini

    public var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .elevenLabs: return "ElevenLabs"
        case .gemini: return "Gemini"
        }
    }
}

public struct TTSCredentials: Sendable {
    public let openAIKey: String
    public let elevenLabsKey: String
    public let geminiKey: String

    public init(openAIKey: String = "", elevenLabsKey: String = "", geminiKey: String = "") {
        self.openAIKey = openAIKey
        self.elevenLabsKey = elevenLabsKey
        self.geminiKey = geminiKey
    }

    public func key(for provider: TTSProvider) -> String {
        switch provider {
        case .openAI: return openAIKey
        case .elevenLabs: return elevenLabsKey
        case .gemini: return geminiKey
        }
    }
}

public struct ElevenLabsVoice: Identifiable, Hashable, Sendable {
    public let voiceID: String
    public let name: String

    public var id: String { voiceID }

    public init(voiceID: String, name: String) {
        self.voiceID = voiceID
        self.name = name
    }
}

public enum ElevenLabsVoiceCatalog {
    public static let defaultVoiceID = "21m00Tcm4TlvDq8ikWAM"

    public static let fallbackVoices: [ElevenLabsVoice] = [
        ElevenLabsVoice(voiceID: "21m00Tcm4TlvDq8ikWAM", name: "Rachel"),
        ElevenLabsVoice(voiceID: "pNInz6obpgDQGcFmaJgB", name: "Adam"),
        ElevenLabsVoice(voiceID: "EXAVITQu4vr4xnSDxMaL", name: "Bella"),
        ElevenLabsVoice(voiceID: "ErXwobaYiN019PkySvjV", name: "Antoni"),
        ElevenLabsVoice(voiceID: "MF3mGyEYCl7XYWbV9V6O", name: "Elli"),
    ]

    public static func fetchVoices(apiKey: String) async throws -> [ElevenLabsVoice] {
        guard !apiKey.isEmpty else { return fallbackVoices }

        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/voices")!)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ElevenLabsVoiceCatalogError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw ElevenLabsVoiceCatalogError.httpError(status: http.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(VoicesResponse.self, from: data)
        let voices = decoded.voices
            .map { ElevenLabsVoice(voiceID: $0.voice_id, name: $0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return voices.isEmpty ? fallbackVoices : voices
    }

    private struct VoicesResponse: Decodable {
        let voices: [VoiceRow]
    }

    private struct VoiceRow: Decodable {
        let voice_id: String
        let name: String
    }
}

public enum ElevenLabsVoiceCatalogError: Error, LocalizedError {
    case invalidResponse
    case httpError(status: Int, body: String?)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Could not load ElevenLabs voices."
        case let .httpError(status, body):
            if let body, !body.isEmpty {
                return "ElevenLabs voices request failed (HTTP \(status)): \(body)"
            }
            return "ElevenLabs voices request failed (HTTP \(status))."
        }
    }
}
