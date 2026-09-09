import Foundation

enum AuthProvider: String {
    case apple
    case google
    case guest
}

enum AuthStubError: Error {
    case notConfigured
}

/// Placeholder session. Apple / Google / Firebase drop in here later.
enum AuthSession {
    static var isSignedIn: Bool {
        false
    }

    static func signIn(with provider: AuthProvider) async throws {
        switch provider {
        case .guest:
            return
        case .apple, .google:
            throw AuthStubError.notConfigured
        }
    }
}
