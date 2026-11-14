//
//  ContentQAClientToken.swift
//  Reads CONTENT_QA_CLIENT_TOKEN from the Xcode scheme environment or shizen/Secrets.plist (gitignored).
//  DEBUG builds only. Release builds use the Firebase staff claim instead (see StaffAccess).
//

import Foundation

enum ContentQAClientToken {
    static var resolved: String {
        #if DEBUG
        if let env = ProcessInfo.processInfo.environment["CONTENT_QA_CLIENT_TOKEN"], !env.isEmpty {
            return env
        }
        return SecretsPlist.value(for: "CONTENT_QA_CLIENT_TOKEN") ?? ""
        #else
        return ""
        #endif
    }
}
