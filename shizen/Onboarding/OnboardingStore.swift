import Foundation

enum OnboardingStore {
    private static let completedKey = "hasCompletedOnboarding"
    private static let completedUserIdKey = "hasCompletedOnboardingUserId"
    private static let lessonStepsFinishedKey = "onboardingLessonStepsFinishedUserIds"
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
            // Only one completed uid is kept, so the one it replaces still skips the lesson steps.
            if let previous = UserDefaults.standard.string(forKey: completedUserIdKey) {
                addLessonStepsFinished(previous)
            }
            addLessonStepsFinished(uid)
            UserDefaults.standard.set(uid, forKey: completedUserIdKey)
        }
    }

    /// True once this uid reached the paywall or finished onboarding on this device. Doesn't
    /// mean completed: completion still means they entered the app with access.
    static var hasFinishedLessonStepsForCurrentUser: Bool {
        guard let uid = AuthService.shared.userId else { return false }
        return isCompletedForCurrentUser || lessonStepsFinishedUserIds.contains(uid)
    }

    static func markLessonStepsFinishedForCurrentUser() {
        guard let uid = AuthService.shared.userId else { return }
        addLessonStepsFinished(uid)
    }

    private static var lessonStepsFinishedUserIds: [String] {
        UserDefaults.standard.stringArray(forKey: lessonStepsFinishedKey) ?? []
    }

    private static func addLessonStepsFinished(_ uid: String) {
        let finished = lessonStepsFinishedUserIds
        guard !finished.contains(uid) else { return }
        UserDefaults.standard.set(finished + [uid], forKey: lessonStepsFinishedKey)
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
