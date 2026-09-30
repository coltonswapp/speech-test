//
//  ContentQAClientToken.swift
//  Reads CONTENT_QA_CLIENT_TOKEN from the Xcode scheme environment or shizen/Secrets.plist (gitignored).
//

import Foundation

enum ContentQAClientToken {
    static var resolved: String {
        if let env = ProcessInfo.processInfo.environment["CONTENT_QA_CLIENT_TOKEN"], !env.isEmpty {
            return env
        }
        return SecretsPlist.value(for: "CONTENT_QA_CLIENT_TOKEN") ?? ""
    }
}
