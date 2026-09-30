//
//  GeminiUsageTracker.swift
//  shizen
//
//  Persists per-request Gemini token usage so we can estimate real-world cost/usage.
//

import Foundation

/// Mirrors the `usageMetadata` object Gemini includes on every `generateContent` response.
struct GeminiUsageMetadata: Decodable {
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
    let totalTokenCount: Int?
}

enum GeminiUsageFeature: String, Codable, CaseIterable, Hashable {
    case tokenizer
    case contextualGloss
    case commonUses
    case spanGloss
    case spanBreakdown
    case senseFit
    case registerLadder
    case dialogueNuance
    case verbCombo

    var displayName: String {
        switch self {
        case .tokenizer: return "Tokenizer"
        case .contextualGloss: return "Contextual gloss"
        case .commonUses: return "Common uses"
        case .spanGloss: return "Span gloss"
        case .spanBreakdown: return "Break down"
        case .senseFit: return "Sense fit"
        case .registerLadder: return "Register ladder"
        case .dialogueNuance: return "Deeper meaning"
        case .verbCombo: return "Verb combinations"
        }
    }
}

struct GeminiUsageRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let feature: GeminiUsageFeature
    let model: String
    let promptTokens: Int
    let candidatesTokens: Int
    let totalTokens: Int

    /// Tokens Google bills as output. Thinking tokens sit outside `candidatesTokenCount`,
    /// so when `total` is larger than prompt + candidates, the remainder is included here.
    var outputTokens: Int {
        guard totalTokens > 0 else { return candidatesTokens }
        return max(candidatesTokens, totalTokens - promptTokens)
    }

    /// Estimated USD cost of this single request, or nil when we don't have pricing for `model`.
    var costUSD: Double? {
        GeminiPricing.cost(
            model: model,
            promptTokens: promptTokens,
            outputTokens: outputTokens,
            on: timestamp
        )?.totalUSD
    }
}

/// Standard-tier text pricing from Google's Gemini API rate card.
/// Only models this app calls are priced; unknown models report no cost rather than a guess.
enum GeminiPricing {
    struct PublishedRate: Equatable {
        let inputPerMillion: Double
        let outputPerMillion: Double

        /// "$0.10 in · $0.40 out per 1M"
        var label: String {
            "$\(Self.amount(inputPerMillion)) in · $\(Self.amount(outputPerMillion)) out per 1M"
        }

        private static func amount(_ value: Double) -> String {
            String(format: "%.2f", value)
        }
    }

    struct TokenCost: Equatable {
        let inputUSD: Double
        let outputUSD: Double
        var totalUSD: Double { inputUSD + outputUSD }
    }

    /// Google lists `gemini-3.6-flash` at $0.75 / $3.75 through this instant, then $1.50 / $7.50.
    private static let flash36RateChange: Date = {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2027
        components.month = 1
        components.day = 1
        return components.date ?? Date(timeIntervalSince1970: 1_798_761_600)
    }()

    static func rate(for model: String, on date: Date = Date()) -> PublishedRate? {
        switch model {
        case "gemini-2.5-flash":
            return PublishedRate(inputPerMillion: 0.30, outputPerMillion: 2.50)
        case "gemini-2.5-flash-lite":
            return PublishedRate(inputPerMillion: 0.10, outputPerMillion: 0.40)
        case "gemini-3.1-flash-lite":
            return PublishedRate(inputPerMillion: 0.25, outputPerMillion: 1.50)
        case "gemini-3.6-flash":
            if date < flash36RateChange {
                return PublishedRate(inputPerMillion: 0.75, outputPerMillion: 3.75)
            }
            return PublishedRate(inputPerMillion: 1.50, outputPerMillion: 7.50)
        default:
            return nil
        }
    }

    static func cost(
        model: String,
        promptTokens: Int,
        outputTokens: Int,
        on date: Date = Date()
    ) -> TokenCost? {
        guard let rate = rate(for: model, on: date) else { return nil }
        return TokenCost(
            inputUSD: Double(promptTokens) / 1_000_000 * rate.inputPerMillion,
            outputUSD: Double(outputTokens) / 1_000_000 * rate.outputPerMillion
        )
    }

    static func costUSD(model: String, promptTokens: Int, outputTokens: Int) -> Double? {
        cost(model: model, promptTokens: promptTokens, outputTokens: outputTokens)?.totalUSD
    }
}

enum GeminiCostFormatter {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 6
        return f
    }()

    static func string(from costUSD: Double) -> String {
        formatter.string(from: NSNumber(value: costUSD)) ?? String(format: "$%.4f", costUSD)
    }
}

final class GeminiUsageTracker {
    static let shared = GeminiUsageTracker()

    struct Summary {
        let requestCount: Int
        let promptTokens: Int
        let outputTokens: Int
        let totalTokens: Int
        let byFeature: [GeminiUsageFeature: Int]
        /// Sum of input-token cost across records with a published rate. Nil when none were priced.
        let inputCostUSD: Double?
        /// Sum of output-token cost across records with a published rate. Nil when none were priced.
        let outputCostUSD: Double?
        /// Sum of `costUSD` across records that have known pricing; nil if none did.
        let totalCostUSD: Double?
        /// True when at least one record's model has no pricing data, so the dollar figures are partial.
        let hasUnpricedRecords: Bool
    }

    /// Estimated average USD cost per calendar day, based on the full retained history
    /// (bounded by 14-day retention, so this is "recent average," not lifetime-exact).
    struct CostEstimate {
        let averagePerDayUSD: Double?
        let averagePerSessionUSD: Double?
        let sessionCount: Int
        let dayCount: Int
        let hasUnpricedRecords: Bool
    }

    /// Boundary between requests that counts as a new "session" — approximates app-launch/foreground
    /// gaps without needing app-lifecycle plumbing, per how usage is actually clustered in the log.
    private static let sessionGapInterval: TimeInterval = 30 * 60

    private let fileURL: URL
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "GeminiUsageTracker", qos: .utility)

    private static let maxRecords = 2000
    private static let retentionDays = 14

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        fileURL = appSupport.appendingPathComponent("GeminiUsageLog.json")
    }

    /// Fire-and-forget from a Gemini call site; never throws, never blocks the caller.
    func record(feature: GeminiUsageFeature, model: String, usage: GeminiUsageMetadata) {
        let record = GeminiUsageRecord(
            id: UUID(),
            timestamp: Date(),
            feature: feature,
            model: model,
            promptTokens: usage.promptTokenCount ?? 0,
            candidatesTokens: usage.candidatesTokenCount ?? 0,
            totalTokens: usage.totalTokenCount ?? 0
        )
        print("[GeminiUsageTracker] recording \(feature.rawValue)/\(model): \(record.promptTokens) prompt + \(record.candidatesTokens) candidates = \(record.totalTokens) total tokens")
        queue.async { [weak self] in
            self?.appendAndRotate(record)
        }
    }

    /// Reads the log, dropping records older than 14 days. Safe to call from any thread.
    func allRecords() -> [GeminiUsageRecord] {
        queue.sync {
            let records = (try? load()) ?? []
            let pruned = recordsWithinRetention(records)
            if pruned.count != records.count {
                try? save(pruned)
            }
            return pruned
        }
    }

    func summary(since: Date? = nil, feature: GeminiUsageFeature? = nil) -> Summary {
        let records = allRecords().filter { record in
            if let feature, record.feature != feature { return false }
            guard let since else { return true }
            return record.timestamp >= since
        }
        return Self.summarize(records)
    }

    /// Estimated average cost per day and per session, derived from the retained history.
    /// "Session" is approximated by grouping requests separated by less than `sessionGapInterval`.
    /// Pass `feature` to estimate from one call type.
    func costEstimate(feature: GeminiUsageFeature? = nil) -> CostEstimate {
        let records = allRecords()
            .filter { feature == nil || $0.feature == feature }
            .sorted { $0.timestamp < $1.timestamp }
        guard !records.isEmpty else {
            return CostEstimate(
                averagePerDayUSD: nil,
                averagePerSessionUSD: nil,
                sessionCount: 0,
                dayCount: 0,
                hasUnpricedRecords: false
            )
        }

        let costs = records.map(\.costUSD)
        let hasUnpricedRecords = costs.contains(nil)
        let totalCost = costs.compactMap { $0 }.reduce(0, +)
        let knownCostCount = costs.compactMap { $0 }.count

        let calendar = Calendar.current
        let dayCount = Set(records.map { calendar.startOfDay(for: $0.timestamp) }).count

        var sessionCount = 0
        var previousTimestamp: Date?
        for record in records {
            if let previous = previousTimestamp, record.timestamp.timeIntervalSince(previous) < Self.sessionGapInterval {
                // Same session as the previous request.
            } else {
                sessionCount += 1
            }
            previousTimestamp = record.timestamp
        }

        let averagePerDayUSD = knownCostCount > 0 ? totalCost / Double(dayCount) : nil
        let averagePerSessionUSD = knownCostCount > 0 ? totalCost / Double(sessionCount) : nil

        return CostEstimate(
            averagePerDayUSD: averagePerDayUSD,
            averagePerSessionUSD: averagePerSessionUSD,
            sessionCount: sessionCount,
            dayCount: dayCount,
            hasUnpricedRecords: hasUnpricedRecords
        )
    }

    private static func summarize(_ records: [GeminiUsageRecord]) -> Summary {
        var byFeature: [GeminiUsageFeature: Int] = [:]
        var promptTokens = 0
        var outputTokens = 0
        var totalTokens = 0
        var inputCost = 0.0
        var outputCost = 0.0
        var pricedCount = 0
        var hasUnpricedRecords = false
        for record in records {
            byFeature[record.feature, default: 0] += record.totalTokens
            promptTokens += record.promptTokens
            outputTokens += record.outputTokens
            totalTokens += record.totalTokens
            if let cost = GeminiPricing.cost(
                model: record.model,
                promptTokens: record.promptTokens,
                outputTokens: record.outputTokens,
                on: record.timestamp
            ) {
                inputCost += cost.inputUSD
                outputCost += cost.outputUSD
                pricedCount += 1
            } else {
                hasUnpricedRecords = true
            }
        }
        return Summary(
            requestCount: records.count,
            promptTokens: promptTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            byFeature: byFeature,
            inputCostUSD: pricedCount > 0 ? inputCost : nil,
            outputCostUSD: pricedCount > 0 ? outputCost : nil,
            totalCostUSD: pricedCount > 0 ? inputCost + outputCost : nil,
            hasUnpricedRecords: hasUnpricedRecords
        )
    }

    func clearAll() {
        queue.async { [weak self] in
            guard let self else { return }
            try? self.fileManager.removeItem(at: self.fileURL)
        }
    }

    private func appendAndRotate(_ record: GeminiUsageRecord) {
        var records = (try? load()) ?? []
        records.append(record)
        records = recordsWithinRetention(records)
        if records.count > Self.maxRecords {
            records.removeFirst(records.count - Self.maxRecords)
        }
        try? save(records)
    }

    private func recordsWithinRetention(_ records: [GeminiUsageRecord], now: Date = Date()) -> [GeminiUsageRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: now)
            ?? now.addingTimeInterval(-TimeInterval(Self.retentionDays * 24 * 60 * 60))
        return records.filter { $0.timestamp >= cutoff }
    }

    private func load() throws -> [GeminiUsageRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([GeminiUsageRecord].self, from: Data(contentsOf: fileURL))
    }

    private func save(_ records: [GeminiUsageRecord]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
    }
}
