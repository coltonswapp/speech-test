//
//  KanjidicStore.swift
//  shizen
//
//  Read-only access to bundled kanjidic.sqlite (character → meanings).
//

import Foundation
import GRDB

struct KanjidicKanjiRow: Decodable, FetchableRecord {
    let character: String
    let meanings: String
}

/// Full record for the kanji detail screen.
struct KanjidicDetail: Decodable, FetchableRecord {
    let character: String
    let onReadings: String?
    let kunReadings: String?
    let meanings: String?
    let grade: Int?
    let jlpt: Int?
    let freq: Int?
    let strokeCount: Int?

    enum CodingKeys: String, CodingKey {
        case character
        case onReadings = "on_readings"
        case kunReadings = "kun_readings"
        case meanings
        case grade
        case jlpt
        case freq
        case strokeCount = "stroke_count"
    }

    private static func splitList(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var onReadingList: [String] { Self.splitList(onReadings) }
    var kunReadingList: [String] { Self.splitList(kunReadings) }
    var meaningList: [String] { Self.splitList(meanings) }
}

final class KanjidicStore {
    static let shared = KanjidicStore()

    private var dbQueue: DatabaseQueue?

    private init() {
        openDatabaseIfNeeded()
    }

    private func openDatabaseIfNeeded() {
        guard dbQueue == nil else { return }
        guard let url = Bundle.main.url(forResource: "kanjidic", withExtension: "sqlite") else {
            print("KanjidicStore: kanjidic.sqlite not found in bundle")
            return
        }
        var config = Configuration()
        config.readonly = true
        do {
            dbQueue = try DatabaseQueue(path: url.path, configuration: config)
        } catch {
            print("KanjidicStore: failed to open DB: \(error)")
        }
    }

    /// Ordered unique kanji in `surface` (CJK Extension A + Unified Ideographs), with a short English gloss from the first comma-separated meaning.
    func briefInfo(forKanjiIn surface: String) -> [(character: String, briefMeaning: String)] {
        openDatabaseIfNeeded()
        let order = Self.orderedUniqueKanjiScalars(in: surface)
        guard let dbQueue, !order.isEmpty else { return [] }

        var map: [String: String] = [:]
        do {
            try dbQueue.read { db in
                let placeholders = repeatElement("?", count: order.count).joined(separator: ",")
                let sql = "SELECT character, meanings FROM kanji WHERE character IN (\(placeholders))"
                let rows = try KanjidicKanjiRow.fetchAll(db, sql: sql, arguments: StatementArguments(order))
                for row in rows {
                    map[row.character] = row.meanings
                }
            }
        } catch {
            print("KanjidicStore: query error: \(error)")
            return []
        }

        var result: [(String, String)] = []
        result.reserveCapacity(order.count)
        for char in order {
            guard let raw = map[char], !raw.isEmpty else { continue }
            let brief = Self.briefMeaning(from: raw)
            if !brief.isEmpty {
                result.append((char, brief))
            }
        }
        return result
    }

    /// Full kanjidic record for a single kanji character, or nil if not present.
    func detail(forKanji character: String) -> KanjidicDetail? {
        openDatabaseIfNeeded()
        let trimmed = character.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dbQueue, !trimmed.isEmpty else { return nil }
        do {
            return try dbQueue.read { db in
                try KanjidicDetail.fetchOne(
                    db,
                    sql: """
                        SELECT character, on_readings, kun_readings, meanings, grade, jlpt, freq, stroke_count
                        FROM kanji WHERE character = ? LIMIT 1
                        """,
                    arguments: [trimmed]
                )
            }
        } catch {
            print("KanjidicStore: detail query error: \(error)")
            return nil
        }
    }

    private static func orderedUniqueKanjiScalars(in surface: String) -> [String] {
        var seen = Set<String>()
        var order: [String] = []
        for scalar in surface.unicodeScalars {
            guard isKanjiScalar(scalar) else { continue }
            let s = String(scalar)
            if seen.insert(s).inserted {
                order.append(s)
            }
        }
        return order
    }

    private static func isKanjiScalar(_ s: UnicodeScalar) -> Bool {
        let v = s.value
        return (0x3400...0x4DBF).contains(v) || (0x4E00...0x9FFF).contains(v)
    }

    private static func briefMeaning(from meanings: String, maxLen: Int = 40) -> String {
        let first =
            meanings
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        if first.count <= maxLen { return String(first) }
        return String(first.prefix(maxLen)) + "…"
    }
}
