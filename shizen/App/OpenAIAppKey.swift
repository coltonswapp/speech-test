//
//  OpenAIAppKey.swift
//  Reads OPENAI_API_KEY from the Xcode scheme environment or shizen/Secrets.plist (gitignored).
//

import Foundation

enum OpenAIAppKey {
    static var resolved: String {
        if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !env.isEmpty {
            return env
        }
        return SecretsPlist.value(for: "OPENAI_API_KEY") ?? ""
    }
}
