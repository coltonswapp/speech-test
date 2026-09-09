import Foundation

enum OnboardingStore {
    private static let completedKey = "hasCompletedOnboarding"
    private static let answersKey = "onboardingAnswers"

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: completedKey) }
        set { UserDefaults.standard.set(newValue, forKey: completedKey) }
    }

    static func save(_ info: UserOnboardingInfo) {
        let payload = PersistedOnboardingAnswers(
            surveyResponses: info.surveyResponses,
            sliderLevel: info.sliderLevel,
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
}

struct PersistedOnboardingAnswers: Codable {
    var surveyResponses: [String: [String]]
    var sliderLevel: String?
    var listeningQuizAnswer: [String]
    var pendingProvider: String?
}
