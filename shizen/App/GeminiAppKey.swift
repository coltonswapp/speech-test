//
//  GeminiAppKey.swift
//  Reads GEMINI_API_KEY from the Xcode scheme environment or shizen/Secrets.plist (gitignored).
//

import Foundation

enum GeminiAppKey {
    static var resolved: String {
        if let env = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !env.isEmpty {
            return env
        }
        return SecretsPlist.value(for: "GEMINI_API_KEY") ?? ""
    }
}
