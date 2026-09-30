import Foundation

enum LLMUsagePeriod: String, CaseIterable {
    case day
    case week
    case month
}

struct LLMUsageFeatureTotals: Decodable, Hashable {
    let feature: String?
    let calls: Int
    let promptTokens: Int
    let outputTokens: Int
    let estimatedCostUSD: Double

    var displayName: String {
        Self.displayName(for: feature ?? "")
    }

    static func displayName(for feature: String) -> String {
        GeminiUsageFeature(rawValue: camelCaseFeature(feature))?.displayName
            ?? feature.replacingOccurrences(of: "_", with: " ")
    }

    /// `contextual_gloss` → `contextualGloss` to match `GeminiUsageFeature`.
    private static func camelCaseFeature(_ feature: String) -> String {
        let parts = feature.split(separator: "_").map(String.init)
        guard let first = parts.first else { return feature }
        return first + parts.dropFirst().map { $0.capitalized }.joined()
    }
}

struct LLMUsageReport: Decodable {
    let period: String
    let periodKey: String
    let calls: Int
    let promptTokens: Int
    let outputTokens: Int
    let estimatedCostUSD: Double
    let hasUnpriced: Bool
    let byFeature: [String: LLMUsageFeatureTotals]

    enum CodingKeys: String, CodingKey {
        case period, periodKey, calls, promptTokens, outputTokens, estimatedCostUSD, hasUnpriced, byFeature
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        period = try container.decode(String.self, forKey: .period)
        periodKey = try container.decode(String.self, forKey: .periodKey)
        calls = try container.decodeIfPresent(Int.self, forKey: .calls) ?? 0
        promptTokens = try container.decodeIfPresent(Int.self, forKey: .promptTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        estimatedCostUSD = try container.decodeIfPresent(Double.self, forKey: .estimatedCostUSD) ?? 0
        hasUnpriced = try container.decodeIfPresent(Bool.self, forKey: .hasUnpriced) ?? false
        byFeature = try container.decodeIfPresent([String: LLMUsageFeatureTotals].self, forKey: .byFeature) ?? [:]
    }

    var rankedFeatures: [(name: String, totals: LLMUsageFeatureTotals)] {
        byFeature
            .map { ($0.key, $0.value) }
            .sorted { lhs, rhs in
                if lhs.1.calls != rhs.1.calls { return lhs.1.calls > rhs.1.calls }
                return lhs.1.estimatedCostUSD > rhs.1.estimatedCostUSD
            }
    }
}

struct LLMProductUsageReport: Decodable {
    struct FeatureRow: Decodable, Hashable {
        let feature: String
        let calls: Int
        let promptTokens: Int
        let outputTokens: Int
        let estimatedCostUSD: Double

        var displayName: String { LLMUsageFeatureTotals.displayName(for: feature) }
    }

    let period: String
    let periodKey: String
    let calls: Int
    let promptTokens: Int
    let outputTokens: Int
    let estimatedCostUSD: Double
    let hasUnpriced: Bool
    let features: [FeatureRow]
}

enum LLMUsageClient {
    static func mine(period: LLMUsagePeriod = .week) async throws -> LLMUsageReport {
        try await LLMGatewayClient.get("v1/usage", query: ["period": period.rawValue], as: LLMUsageReport.self)
    }

    static func product(period: LLMUsagePeriod = .week) async throws -> LLMProductUsageReport {
        try await LLMGatewayClient.get("v1/usage/features", query: ["period": period.rawValue], as: LLMProductUsageReport.self)
    }
}
