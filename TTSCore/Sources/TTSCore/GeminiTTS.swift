//
//  GeminiTTS.swift
//  TTSCore
//
//  Multi-speaker conversation synthesis via Gemini 3.1 Flash TTS Preview.
//

import Foundation

public enum GeminiTTSVoice: String, CaseIterable, Codable, Sendable {
    case zephyr = "Zephyr"
    case puck = "Puck"
    case charon = "Charon"
    case kore = "Kore"
    case fenrir = "Fenrir"
    case leda = "Leda"
    case orus = "Orus"
    case aoede = "Aoede"
    case callirrhoe = "Callirrhoe"
    case autonoe = "Autonoe"
    case enceladus = "Enceladus"
    case iapetus = "Iapetus"
    case umbriel = "Umbriel"
    case algieba = "Algieba"
    case despina = "Despina"
    case erinome = "Erinome"
    case algenib = "Algenib"
    case rasalgethi = "Rasalgethi"
    case laomedeia = "Laomedeia"
    case achernar = "Achernar"
    case alnilam = "Alnilam"
    case schedar = "Schedar"
    case gacrux = "Gacrux"
    case pulcherrima = "Pulcherrima"
    case achird = "Achird"
    case zubenelgenubi = "Zubenelgenubi"
    case vindemiatrix = "Vindemiatrix"
    case sadachbia = "Sadachbia"
    case sadaltager = "Sadaltager"
    case sulafat = "Sulafat"
}

public enum ConversationSpeaker: String, CaseIterable, Codable, Sendable, Identifiable {
    case speaker1 = "Speaker 1"
    case speaker2 = "Speaker 2"

    public var id: String { rawValue }
}

public struct ConversationDialogueLine: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var speaker: ConversationSpeaker
    public var text: String

    public init(id: UUID = UUID(), speaker: ConversationSpeaker, text: String) {
        self.id = id
        self.speaker = speaker
        self.text = text
    }
}

public enum GeminiTTSError: Error, LocalizedError {
    case missingAPIKey
    case noDialogueLines
    case invalidResponse(status: Int, body: String?)
    case noAudioInResponse
    case couldNotDecodeAudio

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing Gemini API key."
        case .noDialogueLines:
            return "Add at least one dialogue line."
        case let .invalidResponse(status, body):
            if let body, !body.isEmpty {
                return "Gemini request failed (HTTP \(status)): \(body)"
            }
            return "Gemini request failed (HTTP \(status))."
        case .noAudioInResponse:
            return "Gemini returned no audio data."
        case .couldNotDecodeAudio:
            return "Could not decode Gemini audio response."
        }
    }
}

public enum GeminiConversationTTSClient {
    public static let defaultModel = "gemini-3.1-flash-tts-preview"

    public static func buildTranscript(from lines: [ConversationDialogueLine]) -> String {
        let body = lines
            .map { "\($0.speaker.rawValue): \($0.text.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n")
        return "## Transcript:\n\(body)"
    }

    public static func generatePCM(
        apiKey: String,
        lines: [ConversationDialogueLine],
        speaker1Voice: GeminiTTSVoice,
        speaker2Voice: GeminiTTSVoice,
        model: String = defaultModel,
        temperature: Double = 1
    ) async throws -> Data {
        guard !apiKey.isEmpty else { throw GeminiTTSError.missingAPIKey }

        let trimmedLines = lines.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !trimmedLines.isEmpty else { throw GeminiTTSError.noDialogueLines }

        let transcript = buildTranscript(from: trimmedLines)
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let payload: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": transcript]],
                ],
            ],
            "generationConfig": [
                "temperature": temperature,
                "responseModalities": ["AUDIO"],
                "speechConfig": [
                    "multiSpeakerVoiceConfig": [
                        "speakerVoiceConfigs": [
                            [
                                "speaker": ConversationSpeaker.speaker1.rawValue,
                                "voiceConfig": [
                                    "prebuiltVoiceConfig": ["voiceName": speaker1Voice.rawValue],
                                ],
                            ],
                            [
                                "speaker": ConversationSpeaker.speaker2.rawValue,
                                "voiceConfig": [
                                    "prebuiltVoiceConfig": ["voiceName": speaker2Voice.rawValue],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeminiTTSError.invalidResponse(status: -1, body: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw GeminiTTSError.invalidResponse(status: http.statusCode, body: body)
        }

        return try extractPCM(from: data)
    }

    private static func extractPCM(from responseData: Data) throws -> Data {
        guard
            let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let first = candidates.first,
            let content = first["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else {
            throw GeminiTTSError.noAudioInResponse
        }

        for part in parts {
            guard
                let inlineData = part["inlineData"] as? [String: Any],
                let base64 = inlineData["data"] as? String,
                let audioData = Data(base64Encoded: base64)
            else { continue }

            let mimeType = inlineData["mimeType"] as? String ?? "audio/L16;rate=24000"
            if mimeType.lowercased().contains("wav") || audioData.starts(with: [0x52, 0x49, 0x46, 0x46]) {
                return stripWAVHeader(from: audioData) ?? audioData
            }
            return audioData
        }

        throw GeminiTTSError.noAudioInResponse
    }

    private static func stripWAVHeader(from data: Data) -> Data? {
        guard data.count > 44 else { return nil }
        return data.subdata(in: 44..<data.count)
    }
}
