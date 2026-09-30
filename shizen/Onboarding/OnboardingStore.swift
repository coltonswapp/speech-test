import Foundation

enum OnboardingStore {
    private static let completedKey = "hasCompletedOnboarding"
    private static let completedUserIdKey = "hasCompletedOnboardingUserId"
    private static let answersKey = "onboardingAnswers"

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: completedKey) }
        set { UserDefaults.standard.set(newValue, forKey: completedKey) }
    }

    /// True only when this signed-in uid finished onboarding on this device.
    static var isCompletedForCurrentUser: Bool {
        guard hasCompletedOnboarding, let uid = AuthService.shared.userId else { return false }
        return UserDefaults.standard.string(forKey: completedUserIdKey) == uid
    }

    static func markCompletedForCurrentUser() {
        hasCompletedOnboarding = true
        if let uid = AuthService.shared.userId {
            UserDefaults.standard.set(uid, forKey: completedUserIdKey)
        }
    }

    static func save(_ info: UserOnboardingInfo) {
        let payload = PersistedOnboardingAnswers(
            surveyResponses: info.surveyResponses,
            sliderLevel: info.sliderLevel,
            dailyGoal: info.dailyGoal,
            listeningQuizAnswer: info.listeningQuizAnswer,
            pendingProvider: info.pendingProvider?.rawValue
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: answersKey)
    }

    static func loadAnswers() -> PersistedOnboardingAnswers? {
        guard let data = UserDefaults.standard.data(forKey: answersKey) else { return nil }
        return try? JSONDecoder().decode(PersistedOnboardingAnswers.self, from: data)
    }

    /// Removes the answer buffer. Leaves `hasCompletedOnboarding` in place.
    static func clearAnswers() {
        UserDefaults.standard.removeObject(forKey: answersKey)
    }
}

struct PersistedOnboardingAnswers: Codable {
    var surveyResponses: [String: [String]]
    var sliderLevel: String?
    var dailyGoal: String?
    var listeningQuizAnswer: [String]
    var pendingProvider: String?
}
