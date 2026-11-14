//
//  OpenAIAppKey.swift
//  Reads OPENAI_API_KEY from the Xcode scheme environment or shizen/Secrets.plist (gitignored).
//  DEBUG builds only: Release strips provider keys from the bundled plist (see the
//  "Strip provider keys" build phase) and this always returns "".
//

import Foundation

enum OpenAIAppKey {
    static var resolved: String {
        #if DEBUG
        if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !env.isEmpty {
            return env
        }
        return SecretsPlist.value(for: "OPENAI_API_KEY") ?? ""
        #else
        return ""
        #endif
    }
}
