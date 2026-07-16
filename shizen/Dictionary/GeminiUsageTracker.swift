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

    var displayName: String {
        switch self {
        case .tokenizer: return "Tokenizer"
        case .contextualGloss: return "Contextual gloss"
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

    /// Estimated USD cost of this single request, or nil when we don't have pricing for `model`.
    var costUSD: Double? {
        GeminiPricing.costUSD(model: model, promptTokens: promptTokens, candidatesTokens: candidatesTokens)
    }
}

/// Standard-tier, text/image/video pricing per Google's published rate card.
/// Only models we actually default to are priced; unknown models report no cost rather than a guess.
enum GeminiPricing {
    private struct Rate {
        let inputPerMillion: Double
        let outputPerMillion: Double
    }

    private static let rates: [String: Rate] = [
        "gemini-2.5-flash-lite": Rate(inputPerMillion: 0.10, outputPerMillion: 0.40),
    ]

    static func costUSD(model: String, promptTokens: Int, candidatesTokens: Int) -> Double? {
        guard let rate = rates[model] else { return nil }
        let inputCost = Double(promptTokens) / 1_000_000 * rate.inputPerMillion
        let outputCost = Double(candidatesTokens) / 1_000_000 * rate.outputPerMillion
        return inputCost + outputCost
    }
}

enum GeminiCostFormatter {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 4
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
        let totalTokens: Int
        let byFeature: [GeminiUsageFeature: Int]
        /// Sum of `costUSD` across records that have known pricing; nil if none did.
        let totalCostUSD: Double?
        /// True when at least one record's model has no pricing data, so `totalCostUSD` is a partial figure.
        let hasUnpricedRecords: Bool
    }

    /// Estimated average USD cost per calendar day, based on the full retained history
    /// (bounded by `maxRecords`/retention, so this is "recent average," not lifetime-exact).
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

    /// Reads the full log. Safe to call from any thread; performs local file I/O.
    func allRecords() -> [GeminiUsageRecord] {
        queue.sync { (try? load()) ?? [] }
    }

    func summary(since: Date? = nil) -> Summary {
        let records = allRecords().filter { record in
            guard let since else { return true }
            return record.timestamp >= since
        }
        return Self.summarize(records)
    }

    /// Estimated average cost per day and per session, derived from the retained history.
    /// "Session" is approximated by grouping requests separated by less than `sessionGapInterval`.
    func costEstimate() -> CostEstimate {
        let records = allRecords().sorted { $0.timestamp < $1.timestamp }
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
        for record in records {
            byFeature[record.feature, default: 0] += record.totalTokens
        }
        let costs = records.map(\.costUSD)
        let knownCosts = costs.compactMap { $0 }
        return Summary(
            requestCount: records.count,
            totalTokens: records.reduce(0) { $0 + $1.totalTokens },
            byFeature: byFeature,
            totalCostUSD: knownCosts.isEmpty ? nil : knownCosts.reduce(0, +),
            hasUnpricedRecords: costs.contains(nil)
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
        if records.count > Self.maxRecords {
            records.removeFirst(records.count - Self.maxRecords)
        }
        try? save(records)
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
