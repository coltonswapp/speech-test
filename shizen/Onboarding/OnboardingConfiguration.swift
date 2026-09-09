import Foundation

struct OnboardingConfiguration: Codable {
    let version: String
    let flow: OnboardingFlow

    static func loadLocal(named filename: String = "onboarding_config") -> OnboardingConfiguration? {
        let bundle = Bundle.main
        let url = bundle.url(forResource: filename, withExtension: "json")
            ?? bundle.url(forResource: filename, withExtension: "json", subdirectory: "Onboarding")
            ?? bundle.urls(forResourcesWithExtension: "json", subdirectory: nil)?
                .first { $0.deletingPathExtension().lastPathComponent == filename }
        guard let url, let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(OnboardingConfiguration.self, from: data)
    }
}

struct OnboardingFlow: Codable {
    let name: String
    let steps: [OnboardingStep]
}

struct OnboardingStep: Codable {
    let id: String
    let type: StepType
    let config: StepConfiguration

    enum StepType: String, Codable {
        case survey
        case slider
        case listeningQuiz = "listening_quiz"
        case demo
        case finish
    }
}

enum StepConfiguration: Codable {
    case survey(SurveyStepConfig)
    case slider(SliderStepConfig)
    case listeningQuiz(ListeningQuizStepConfig)
    case demo(DemoStepConfig)
    case finish(BasicStepConfig)

    enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "survey":
            self = .survey(try SurveyStepConfig(from: decoder))
        case "slider":
            self = .slider(try SliderStepConfig(from: decoder))
        case "listening_quiz":
            self = .listeningQuiz(try ListeningQuizStepConfig(from: decoder))
        case "demo":
            self = .demo(try DemoStepConfig(from: decoder))
        default:
            self = .finish(try BasicStepConfig(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .survey(let config):
            try container.encode("survey", forKey: .type)
            try config.encode(to: encoder)
        case .slider(let config):
            try container.encode("slider", forKey: .type)
            try config.encode(to: encoder)
        case .listeningQuiz(let config):
            try container.encode("listening_quiz", forKey: .type)
            try config.encode(to: encoder)
        case .demo(let config):
            try container.encode("demo", forKey: .type)
            try config.encode(to: encoder)
        case .finish(let config):
            try container.encode("finish", forKey: .type)
            try config.encode(to: encoder)
        }
    }
}

struct SurveyOptionConfig: Codable {
    let title: String
    let subtitle: String?
    let value: String?
}

struct SurveyStepConfig: Codable {
    let questionId: String?
    let title: String
    let subtitle: String?
    let options: [SurveyOptionConfig]
    let isMultiSelect: Bool
    let layout: SurveyQuestion.Layout?
    let ctaText: String?

    enum CodingKeys: String, CodingKey {
        case questionId = "question_id"
        case title
        case subtitle
        case options
        case isMultiSelect = "multi_select"
        case layout
        case ctaText = "cta_text"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        questionId = try container.decodeIfPresent(String.self, forKey: .questionId)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        options = try container.decodeIfPresent([SurveyOptionConfig].self, forKey: .options) ?? []
        isMultiSelect = try container.decodeIfPresent(Bool.self, forKey: .isMultiSelect) ?? false
        layout = try container.decodeIfPresent(SurveyQuestion.Layout.self, forKey: .layout)
        ctaText = try container.decodeIfPresent(String.self, forKey: .ctaText)
    }
}

struct SliderLevelConfig: Codable {
    let title: String
    let description: String
    let value: String?
}

struct SliderStepConfig: Codable {
    let title: String
    let subtitle: String?
    let levels: [SliderLevelConfig]
    let ctaText: String?

    enum CodingKeys: String, CodingKey {
        case title
        case subtitle
        case levels
        case ctaText = "cta_text"
    }
}

struct ListeningQuizStepConfig: Codable {
    let title: String
    let subtitle: String?
    let options: [SurveyOptionConfig]
    let ctaText: String?

    enum CodingKeys: String, CodingKey {
        case title
        case subtitle
        case options
        case ctaText = "cta_text"
    }
}

enum DemoVariant: String, Codable {
    case bars
    case inspect
}

struct DemoStepConfig: Codable {
    let title: String
    let subtitle: String?
    let variant: DemoVariant
    let ctaText: String?

    enum CodingKeys: String, CodingKey {
        case title
        case subtitle
        case variant
        case ctaText = "cta_text"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        variant = try container.decodeIfPresent(DemoVariant.self, forKey: .variant) ?? .bars
        ctaText = try container.decodeIfPresent(String.self, forKey: .ctaText)
    }
}

struct BasicStepConfig: Codable {
    let title: String?
    let subtitle: String?
    let ctaText: String?

    enum CodingKeys: String, CodingKey {
        case title
        case subtitle
        case ctaText = "cta_text"
    }
}
