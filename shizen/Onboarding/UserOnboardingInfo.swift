import Foundation

struct UserOnboardingInfo {
    var surveyResponses: [String: [String]] = [:]
    var sliderLevel: String?
    var listeningQuizAnswer: [String] = []
    var pendingProvider: AuthProvider?
}
