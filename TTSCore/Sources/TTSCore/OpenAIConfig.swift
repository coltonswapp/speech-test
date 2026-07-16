//
//  OpenAIConfig.swift
//  shizen
//
//  WARNING: Shipping an API key inside the app binary is inherently
//  insecure — anyone can extract it from the .ipa. For anything beyond
//  a personal POC, proxy TTS requests through a server you control so
//  your key never leaves your infrastructure.
//

import Foundation

public enum OpenAIConfig {
    /// Reads `OPENAI_API_KEY` only. Host apps (iOS POC, Studio) may supply fallbacks separately.
    public static let apiKey: String = {
        if let fromEnv = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
           !fromEnv.isEmpty {
            return fromEnv
        }
        return ""
    }()
}
