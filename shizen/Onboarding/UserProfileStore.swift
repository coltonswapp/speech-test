import FirebaseFirestore
import Foundation
import os

struct UserProfile: Codable {
    var schemaVersion: Int
    var createdAt: Date?
    var updatedAt: Date?
    var timezone: String
    var onboardingCompleted: Bool
    var level: String?
    var dailyGoal: String?
    var survey: [String: [String]]
    var listeningQuizAnswers: [String]
}

/// Creates `users/{uid}` once from the onboarding answer buffer.
/// Call only after `FirebaseApp.configure()`.
@MainActor
final class UserProfileStore {
    static let shared = UserProfileStore()

    private(set) var profile: UserProfile?

    private var isFlushing = false
    private var needsRerun = false
    private let logger = Logger(subsystem: "com.swappfunc.shizen", category: "UserProfile")

    private init() {}

    /// Creates the profile when a signed-in user has finished onboarding and the buffer is still on device.
    /// A missing document is created. An existing document is read and the buffer is dropped.
    /// Landing sign-in does not call this with a saved completion flag, so it does not create an empty profile.
    func flushSavedBufferIfNeeded() async {
        if isFlushing {
            needsRerun = true
            return
        }
        isFlushing = true
        await performFlush()
        isFlushing = false
        if needsRerun {
            needsRerun = false
            await flushSavedBufferIfNeeded()
        }
    }

    private func performFlush() async {
        guard let uid = AuthService.shared.userId else {
            profile = nil
            return
        }

        let ref = Firestore.firestore().collection("users").document(uid)
        // The buffer is saved before the completion flag. Wait for the flag so the
        // one-time create records onboardingCompleted as true.
        guard OnboardingStore.isCompletedForCurrentUser, let answers = OnboardingStore.loadAnswers() else {
            await readIfPresent(ref)
            return
        }

        let payload = profilePayload(from: answers)
        do {
            let created = try await createIfMissing(ref: ref, payload: payload)
            if created {
                OnboardingStore.clearAnswers()
                await readIfPresent(ref)
                return
            }
        } catch {
            if !isAlreadyExists(error) {
                logger.error("Profile create failed; keeping the local buffer: \(error.localizedDescription, privacy: .public)")
                return
            }
        }

        do {
            try await adoptExisting(ref)
        } catch {
            logger.error("Profile exists but could not be read; keeping the local buffer: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Returns true when this call created the document.
    /// Returns false when it already existed. Does not write over an existing document.
    private func createIfMissing(ref: DocumentReference, payload: [String: Any]) async throws -> Bool {
        let outcome = try await Firestore.firestore().runTransaction { transaction, errorPointer -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ref)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
            if snapshot.exists {
                return "exists"
            }
            transaction.setData(payload, forDocument: ref)
            return "created"
        }
        guard let outcome = outcome as? String else {
            throw UserProfileStoreError.missingTransactionResult
        }
        return outcome == "created"
    }

    private func adoptExisting(_ ref: DocumentReference) async throws {
        let snapshot = try await ref.getDocument()
        guard snapshot.exists else {
            throw UserProfileStoreError.missingProfile
        }
        profile = try snapshot.data(as: UserProfile.self)
        OnboardingStore.clearAnswers()
    }

    /// Whether `users/{uid}` already exists. `.unavailable` means the read did not settle.
    func accountPresence() async -> AccountPresence {
        guard let uid = AuthService.shared.userId else { return .missing }
        let ref = Firestore.firestore().collection("users").document(uid)
        do {
            let snapshot = try await ref.getDocument()
            guard snapshot.exists else { return .missing }
            if let decoded = try? snapshot.data(as: UserProfile.self) {
                profile = decoded
            }
            OnboardingStore.clearAnswers()
            return .exists
        } catch {
            logger.error("Account lookup failed: \(error.localizedDescription, privacy: .public)")
            return .unavailable
        }
    }

    private func readIfPresent(_ ref: DocumentReference) async {
        do {
            let snapshot = try await ref.getDocument()
            guard snapshot.exists else { return }
            profile = try snapshot.data(as: UserProfile.self)
        } catch {
            logger.error("Profile read failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func profilePayload(from answers: PersistedOnboardingAnswers) -> [String: Any] {
        [
            "schemaVersion": 1,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "timezone": TimeZone.current.identifier,
            "onboardingCompleted": OnboardingStore.hasCompletedOnboarding,
            "level": answers.sliderLevel ?? NSNull(),
            "dailyGoal": answers.dailyGoal ?? NSNull(),
            "survey": answers.surveyResponses,
            "listeningQuizAnswers": answers.listeningQuizAnswer,
        ]
    }

    private func isAlreadyExists(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == FirestoreErrorDomain
            && nsError.code == FirestoreErrorCode.alreadyExists.rawValue
    }
}

enum AccountPresence {
    case exists
    case missing
    case unavailable
}

private enum UserProfileStoreError: Error {
    case missingTransactionResult
    case missingProfile
}
