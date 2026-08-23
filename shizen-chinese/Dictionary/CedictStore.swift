//
//  CedictStore.swift
//  shizen-chinese
//
//  Read-only access to bundled cedict.sqlite (CC-CEDICT, simplified only).
//

import Foundation
import GRDB

struct CedictEntry: Decodable, FetchableRecord, Equatable {
    let id: Int64
    let simplified: String
    let pinyinNumbered: String
    let pinyinMarked: String
    let pinyinPlain: String
    let glossary: String
    let score: Int

    enum CodingKeys: String, CodingKey {
        case id, simplified, glossary, score
        case pinyinNumbered = "pinyin_numbered"
        case pinyinMarked = "pinyin_marked"
        case pinyinPlain = "pinyin_plain"
    }

    var glossaryLines: [String] {
        glossary
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var primaryGloss: String {
        glossaryLines.first ?? glossary
    }

    var briefChipMeaning: String {
        let first = primaryGloss
            .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? primaryGloss
        if first.count <= 24 { return first }
        return String(first.prefix(23)) + "…"
    }
}

final class CedictStore {
    static let shared = CedictStore()

    private var dbQueue: DatabaseQueue?

    private init() {
        openDatabaseIfNeeded()
    }

    private func openDatabaseIfNeeded() {
        guard dbQueue == nil else { return }
        guard let url = Bundle.main.url(forResource: "cedict", withExtension: "sqlite") else {
            print("CedictStore: cedict.sqlite not found in bundle — run scripts/build_cedict.py")
            return
        }
        var config = Configuration()
        config.readonly = true
        do {
            dbQueue = try DatabaseQueue(path: url.path, configuration: config)
        } catch {
            print("CedictStore: failed to open DB: \(error)")
        }
    }

    func entries(forSimplified simplified: String) -> [CedictEntry] {
        let trimmed = simplified.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        openDatabaseIfNeeded()
        guard let dbQueue else { return [] }
        do {
            return try dbQueue.read { db in
                try CedictEntry.fetchAll(
                    db,
                    sql: """
                        SELECT * FROM entries
                        WHERE simplified = ?
                        ORDER BY score DESC, id ASC
                        """,
                    arguments: [trimmed]
                )
            }
        } catch {
            print("CedictStore: query error: \(error)")
            return []
        }
    }

    func search(query rawQuery: String, limit: Int = 40) -> [CedictEntry] {
        let q = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        openDatabaseIfNeeded()
        guard let dbQueue else { return [] }

        do {
            return try dbQueue.read { db in
                let ftsQuery = Self.buildFTSQuery(q)
                return try CedictEntry.fetchAll(
                    db,
                    sql: """
                        SELECT e.*
                        FROM entries e
                        JOIN entries_fts f ON f.rowid = e.id
                        WHERE entries_fts MATCH ?
                        ORDER BY e.score DESC, rank, e.id ASC
                        LIMIT ?
                        """,
                    arguments: [ftsQuery, limit]
                )
            }
        } catch {
            return searchFallback(query: q, limit: limit)
        }
    }

    private func searchFallback(query: String, limit: Int) -> [CedictEntry] {
        guard let dbQueue else { return [] }
        let pattern = query + "%"
        do {
            return try dbQueue.read { db in
                try CedictEntry.fetchAll(
                    db,
                    sql: """
                        SELECT * FROM entries
                        WHERE simplified LIKE ?
                           OR pinyin_numbered LIKE ?
                           OR pinyin_plain LIKE ?
                           OR pinyin_marked LIKE ?
                           OR glossary LIKE ?
                        ORDER BY score DESC, id ASC
                        LIMIT ?
                        """,
                    arguments: [pattern, pattern, pattern, pattern, "%\(query)%", limit]
                )
            }
        } catch {
            return []
        }
    }

    private static func buildFTSQuery(_ input: String) -> String {
        var tokens = input.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return "\"\"" }
        let last = tokens.removeLast()
        let quoted = tokens.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        let lastQ = "\"\(last.replacingOccurrences(of: "\"", with: "\"\""))\""
        return (quoted + [lastQ + "*"]).joined(separator: " ")
    }

    /// Brief CEDICT gloss for each Han character in `surface` (used by character chips).
    func briefInfo(forCharactersIn surface: String) -> [(character: String, briefMeaning: String)] {
        var seen = Set<Character>()
        var items: [(character: String, briefMeaning: String)] = []
        for character in surface where seen.insert(character).inserted && Self.isHanCharacter(character) {
            let glyph = String(character)
            let meaning = entries(forSimplified: glyph).first?.briefChipMeaning ?? ""
            items.append((glyph, meaning))
        }
        return items
    }

    /// Common multi-character words that contain this single character.
    func compounds(forSurface surface: String, limit: Int = 30) -> [CedictEntry] {
        let trimmed = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isSingleHanCharacter(trimmed) else { return [] }
        openDatabaseIfNeeded()
        guard let dbQueue else { return [] }

        let pattern = "%\(Self.escapeLike(trimmed))%"
        do {
            let rows = try dbQueue.read { db in
                try CedictEntry.fetchAll(
                    db,
                    sql: """
                        SELECT * FROM entries
                        WHERE simplified LIKE ? ESCAPE '\\'
                            AND simplified <> ?
                            AND length(simplified) > 1
                        ORDER BY score DESC, id ASC
                        LIMIT ?
                        """,
                    arguments: [pattern, trimmed, limit * 4]
                )
            }
            var seen = Set<String>()
            var out: [CedictEntry] = []
            for row in rows where seen.insert(row.simplified).inserted {
                out.append(row)
                if out.count >= limit { break }
            }
            return out
        } catch {
            print("CedictStore: compounds query error: \(error)")
            return []
        }
    }

    static func isSingleHanCharacter(_ surface: String) -> Bool {
        let trimmed = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1, let character = trimmed.first else { return false }
        return isHanCharacter(character)
    }

    static func isHanCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            let v = scalar.value
            return (0x3400...0x4DBF).contains(v)
                || (0x4E00...0x9FFF).contains(v)
                || (0x20000...0x2A6DF).contains(v)
        }
    }

    private static func escapeLike(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
