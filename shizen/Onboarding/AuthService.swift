import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import Foundation
import GoogleSignIn
import UIKit

enum AuthProvider: String {
    case apple
    case google
}

struct AuthAccount {
    var title: String
    var subtitle: String
    var isSignedIn: Bool
}

enum AuthServiceError: LocalizedError {
    case canceled
    case missingPresentingViewController
    case missingGoogleClientID
    case missingIDToken
    case invalidAppleResponse
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .canceled:
            return nil
        case .missingPresentingViewController:
            return "Sign-in needs a screen to present from."
        case .missingGoogleClientID:
            return "Google Sign-In needs CLIENT_ID and REVERSED_CLIENT_ID in GoogleService-Info.plist. Enable Google in the Firebase console for this iOS app and re-download the plist."
        case .missingIDToken:
            return "Sign-in did not return an ID token."
        case .invalidAppleResponse:
            return "Apple Sign-In returned an incomplete credential."
        case .notSignedIn:
            return "A signed-in account is required."
        }
    }
}

/// Owns the Firebase Auth session. Callers read the uid from here.
/// Start after `FirebaseApp.configure()`. Do not create learner documents without a uid.
@MainActor
final class AuthService: NSObject {
    static let shared = AuthService()

    /// Non-anonymous Firebase Auth uid. Apple and Google credentials resolve to this.
    private(set) var userId: String?

    var hasSignedInUserId: Bool { userId != nil }

    var account: AuthAccount {
        guard let user = Auth.auth().currentUser, !user.isAnonymous else {
            return AuthAccount(title: "Account", subtitle: "Not signed in", isSignedIn: false)
        }
        let provider = Self.providerLabel(for: user)
        let name = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = user.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty {
            let detail = email.flatMap { $0.isEmpty ? nil : $0 } ?? provider
            return AuthAccount(title: name, subtitle: detail, isSignedIn: true)
        }
        if let email, !email.isEmpty {
            return AuthAccount(title: email, subtitle: provider, isSignedIn: true)
        }
        return AuthAccount(title: "Account", subtitle: provider, isSignedIn: true)
    }

    /// Later profile and learner-data plans must check this before writing `users/{uid}`.
    var canCreateLearnerDocuments: Bool { hasSignedInUserId }

    static let userDidChangeNotification = Notification.Name("AuthService.userDidChange")

    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?
    private var appleSignInContinuation: CheckedContinuation<Bool, Error>?
    private var appleAuthorizationController: ASAuthorizationController?
    private weak var presentingWindow: UIWindow?

    private override init() {
        super.init()
    }

    /// Call once after `FirebaseApp.configure()`.
    func start() {
        applyGoogleConfigurationIfAvailable()
        syncUser(Auth.auth().currentUser)
        guard authStateHandle == nil else { return }
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.syncUser(user)
            }
        }
    }

    static func signedInUserId() -> String? {
        shared.userId
    }

    /// Use from later plans before creating `users/{uid}`, progress, or folders.
    static func requireSignedInUserId() throws -> String {
        guard let uid = shared.userId else {
            throw AuthServiceError.notSignedIn
        }
        return uid
    }

    /// Returns true when Firebase created the user during this sign-in.
    @discardableResult
    func signIn(with provider: AuthProvider, presenting viewController: UIViewController) async throws -> Bool {
        switch provider {
        case .apple:
            return try await signInWithApple(presenting: viewController)
        case .google:
            return try await signInWithGoogle(presenting: viewController)
        }
    }

    func signInWithApple(presenting viewController: UIViewController) async throws -> Bool {
        try await ensureReadyToSignIn()
        guard let window = viewController.view.window ?? Self.keyWindow() else {
            throw AuthServiceError.missingPresentingViewController
        }
        presentingWindow = window

        let nonce = Self.randomNonceString()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        appleAuthorizationController = controller

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            appleSignInContinuation = continuation
            controller.performRequests()
        }
    }

    func signInWithGoogle(presenting viewController: UIViewController) async throws -> Bool {
        try await ensureReadyToSignIn()
        applyGoogleConfigurationIfAvailable()
        guard googleClientID() != nil, GIDSignIn.sharedInstance.configuration != nil else {
            throw AuthServiceError.missingGoogleClientID
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthServiceError.missingIDToken
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            return try await signInToFirebase(with: credential)
        } catch let error as AuthServiceError {
            throw error
        } catch {
            throw Self.mappedGoogleError(error)
        }
    }

    func signOut() throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
        OnboardingStore.clearAnswers()
        syncUser(nil)
    }

    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    private func ensureReadyToSignIn() async throws {
        start()
    }

    private func signInToFirebase(with credential: AuthCredential) async throws -> Bool {
        let result = try await Auth.auth().signIn(with: credential)
        if result.user.isAnonymous {
            try Auth.auth().signOut()
            syncUser(nil)
            throw AuthServiceError.notSignedIn
        }
        syncUser(result.user)
        return result.additionalUserInfo?.isNewUser ?? false
    }

    private static func providerLabel(for user: User) -> String {
        let providers = Set(user.providerData.map(\.providerID))
        if providers.contains("apple.com") { return "Signed in with Apple" }
        if providers.contains("google.com") { return "Signed in with Google" }
        return "Signed in"
    }

    private func syncUser(_ user: User?) {
        if let user, user.isAnonymous {
            try? Auth.auth().signOut()
            assignUserId(nil)
            return
        }
        assignUserId(user?.uid)
    }

    private func assignUserId(_ next: String?) {
        let changed = userId != next
        userId = next
        if changed {
            NotificationCenter.default.post(name: Self.userDidChangeNotification, object: self)
        }
        Task { await UserProfileStore.shared.flushSavedBufferIfNeeded() }
    }

    private func applyGoogleConfigurationIfAvailable() {
        guard let clientID = googleClientID() else { return }
        if GIDSignIn.sharedInstance.configuration?.clientID != clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
    }

    private func googleClientID() -> String? {
        if let id = FirebaseApp.app()?.options.clientID, !id.isEmpty {
            return id
        }
        return Self.googleServiceInfoValue("CLIENT_ID")
    }

    private static func googleServiceInfoValue(_ key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url),
              let value = dict[key] as? String,
              !value.isEmpty
        else {
            return nil
        }
        return value
    }

    private func finishAppleSignIn(_ result: Result<Bool, Error>) {
        guard let continuation = appleSignInContinuation else { return }
        appleSignInContinuation = nil
        appleAuthorizationController = nil
        currentNonce = nil
        continuation.resume(with: result)
    }

    private static func mappedGoogleError(_ error: Error) -> Error {
        let nsError = error as NSError
        if nsError.domain == kGIDSignInErrorDomain,
           nsError.code == GIDSignInError.canceled.rawValue {
            return AuthServiceError.canceled
        }
        return error
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        precondition(status == errSecSuccess, "Unable to generate nonce")
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

extension AuthService: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let nonce = currentNonce,
              let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8)
        else {
            finishAppleSignIn(.failure(AuthServiceError.invalidAppleResponse))
            return
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )
        Task { @MainActor in
            do {
                let isNewUser = try await signInToFirebase(with: credential)
                finishAppleSignIn(.success(isNewUser))
            } catch {
                finishAppleSignIn(.failure(error))
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            finishAppleSignIn(.failure(AuthServiceError.canceled))
            return
        }
        finishAppleSignIn(.failure(error))
    }
}

extension AuthService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        presentingWindow ?? Self.keyWindow() ?? ASPresentationAnchor()
    }
}
