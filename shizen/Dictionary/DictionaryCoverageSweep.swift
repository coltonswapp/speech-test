//
//  DictionaryCoverageSweep.swift
//  shizen
//
//  Runs every lesson line through the same tokens + JMdict lookup a token tap uses and
//  collects the words whose callout would be empty or a guess. Feeds the bundled-dictionary
//  supplement (`scripts/jmdict_supplement.tsv`).
//

import Foundation

struct DictionaryCoverageReport {
    enum Status: String, CaseIterable {
        /// No JMdict row at all. The callout never appears.
        case missing
        /// A kana-only hit that `isContextSensitiveKanaLookup` rejects. The callout never appears.
        case untrustedKana = "untrusted_kana"
        /// Tail-trim or prefix fallback. The callout appears but may name another word.
        case weak

        var label: String {
            switch self {
            case .missing: return "No entry"
            case .untrustedKana: return "Kana hit rejected"
            case .weak: return "Weak match"
            }
        }
    }

    struct Occurrence: Hashable {
        let lessonTitle: String
        let sentence: String
        let english: String?
    }

    struct Item: Identifiable {
        var id: String { surface }
        let surface: String
        let status: Status
        let matchKind: JMDictLookupResult.MatchKind
        /// Headword the lookup landed on (weak / untrusted only).
        let matchedHeadword: String?
        let reading: String
        var occurrences: [Occurrence]
        var lessonTitles: [String]

        var hitCount: Int { occurrences.count }
    }

    var lessonCount = 0
    var lineCount = 0
    var uniqueSurfaceCount = 0
    var studioTokenLineCount = 0
    var items: [Item] = []

    func items(with statuses: Set<Status>) -> [Item] {
        items.filter { statuses.contains($0.status) }
    }

    // MARK: - Export

    /// Review sheet: one row per flagged surface, most frequent first.
    func reviewCSV() -> String {
        var rows = [[
            "status", "surface", "reading", "match_kind", "matched_headword",
            "hits", "lessons", "example_sentence", "example_english",
        ]]
        for item in items {
            let example = item.occurrences.first
            rows.append([
                item.status.rawValue,
                item.surface,
                item.reading,
                item.matchKind.rawValue,
                item.matchedHeadword ?? "",
                String(item.hitCount),
                item.lessonTitles.joined(separator: " | "),
                example?.sentence ?? "",
                example?.english ?? "",
            ])
        }
        return rows.map { $0.map(Self.csvField).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    /// Paste-ready rows for `scripts/jmdict_supplement.tsv`. `glossary` is left blank;
    /// the build skips blank-glossary rows until someone fills them in.
    func supplementTSV(statuses: Set<Status>) -> String {
        var lines: [String] = []
        for item in items where statuses.contains(item.status) {
            let example = item.occurrences.first?.sentence ?? ""
            let note = "# \(item.status.rawValue), \(item.hitCount)× — \(example)"
            lines.append(Self.tsvField(note))
            lines.append([item.surface, item.reading, "", "", "", ""].map(Self.tsvField).joined(separator: "\t"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func tsvField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

enum DictionaryCoverageSweep {

    struct Line {
        let lessonTitle: String
        let japanese: String
        let english: String?
        /// Authored Studio tokens when the scenario ships a valid `tokenSync`; otherwise nil.
        let studioTokens: [JapaneseToken]?
    }

    // MARK: - Collect lesson lines

    /// Every published lesson from the CMS, or bundled lessons when the CMS is not configured.
    static func loadCollections(progress: (String) -> Void) async -> [DialogueScenarioCollection] {
        guard ContentCMSClient.isConfigured else {
            return DialogueScenarioCollectionCatalog.allCollections
        }
        progress("Fetching lesson index…")
        let index: CMSDialogueLessonIndex? = await withCheckedContinuation { continuation in
            ContentCMSClient.fetchDialogueLessonIndex { result in
                continuation.resume(returning: try? result.get())
            }
        }
        guard let index, !index.lessons.isEmpty else {
            return DialogueScenarioCollectionCatalog.allCollections
        }
        var collections: [DialogueScenarioCollection] = []
        for (position, lesson) in index.lessons.enumerated() {
            progress("Fetching lessons \(position + 1)/\(index.lessons.count)…")
            let collection: DialogueScenarioCollection? = await withCheckedContinuation { continuation in
                DialogueScenarioCollectionCatalog.fetchCollection(id: lesson.id) { collection in
                    continuation.resume(returning: collection)
                }
            }
            if let collection {
                collections.append(collection)
            }
        }
        return collections
    }

    static func lines(in collections: [DialogueScenarioCollection]) -> [Line] {
        var result: [Line] = []
        var seen = Set<String>()
        for collection in collections {
            for scenario in collection.scenarios {
                let sync = scenario.example.tokenSync
                var syncLineIndexByText: [String: Int] = [:]
                for (index, line) in (sync?.lines ?? []).enumerated() where syncLineIndexByText[line.text] == nil {
                    syncLineIndexByText[line.text] = index
                }
                for line in scenario.lines {
                    let japanese = line.japanese.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !japanese.isEmpty, seen.insert(japanese).inserted else { continue }
                    let studioTokens = syncLineIndexByText[japanese].flatMap {
                        sync?.japaneseTokens(lineIndex: $0, in: japanese)
                    }
                    result.append(Line(
                        lessonTitle: collection.title,
                        japanese: japanese,
                        english: line.english,
                        studioTokens: studioTokens
                    ))
                }
            }
        }
        return result
    }

    // MARK: - Sweep

    /// Mirrors `ScrubbableSentenceView` → `JapaneseScrubSentenceEngine.gloss(for:)`: tokens,
    /// merged lookup surfaces, then the same trust rules that decide whether a callout shows.
    static func run(
        collections: [DialogueScenarioCollection],
        progress: (String) -> Void
    ) async -> DictionaryCoverageReport {
        let sweepLines = Self.lines(in: collections)
        let store = JMDictStore.shared
        // Gemini / Foundation Model backends would spend a request per line; MeCab is the
        // fallback those backends use anyway.
        let tokenizer: JapaneseTokenizer
        switch JapaneseTokenizerBackend.preferred {
        case .naturalLanguage, .mecab:
            tokenizer = JapaneseTokenizer(backend: JapaneseTokenizerBackend.preferred)
        default:
            tokenizer = JapaneseTokenizer(backend: .mecab)
        }

        var report = DictionaryCoverageReport()
        report.lessonCount = collections.count
        report.lineCount = sweepLines.count

        var verdicts: [String: DictionaryCoverageReport.Item?] = [:]
        var flagged: [String: DictionaryCoverageReport.Item] = [:]
        var flaggedOrder: [String] = []

        for (position, line) in sweepLines.enumerated() {
            if position % 10 == 0 {
                progress("Checking line \(position + 1)/\(sweepLines.count)…")
                await Task.yield()
                if Task.isCancelled { break }
            }
            let tokens: [JapaneseToken]
            if let studio = line.studioTokens {
                tokens = studio
                report.studioTokenLineCount += 1
            } else {
                tokens = tokenizer.tokenize(line.japanese)
            }
            let surfaces = store.effectiveLookupSurfaces(for: tokens)

            // Merged runs repeat the same surface once per token; count each run once.
            var previous: String?
            for surface in surfaces {
                defer { previous = surface }
                guard surface != previous else { continue }
                let trimmed = surface.trimmingCharacters(in: .whitespacesAndNewlines)
                guard Self.containsJapanese(trimmed) else { continue }

                let verdict: DictionaryCoverageReport.Item?
                if let cached = verdicts[trimmed] {
                    verdict = cached
                } else {
                    verdict = classify(trimmed, store: store)
                    verdicts[trimmed] = verdict
                }
                guard let verdict else { continue }

                let occurrence = DictionaryCoverageReport.Occurrence(
                    lessonTitle: line.lessonTitle,
                    sentence: line.japanese,
                    english: line.english
                )
                if var existing = flagged[trimmed] {
                    existing.occurrences.append(occurrence)
                    if !existing.lessonTitles.contains(line.lessonTitle) {
                        existing.lessonTitles.append(line.lessonTitle)
                    }
                    flagged[trimmed] = existing
                } else {
                    var item = verdict
                    item.occurrences = [occurrence]
                    item.lessonTitles = [line.lessonTitle]
                    flagged[trimmed] = item
                    flaggedOrder.append(trimmed)
                }
            }
        }

        report.uniqueSurfaceCount = verdicts.count
        let statusRank: [DictionaryCoverageReport.Status: Int] = [.missing: 0, .untrustedKana: 1, .weak: 2]
        report.items = flaggedOrder.compactMap { flagged[$0] }.sorted { a, b in
            if a.status != b.status { return statusRank[a.status, default: 9] < statusRank[b.status, default: 9] }
            if a.hitCount != b.hitCount { return a.hitCount > b.hitCount }
            return a.surface < b.surface
        }
        return report
    }

    /// `nil` when a tap on `surface` shows a trustworthy gloss.
    private static func classify(_ surface: String, store: JMDictStore) -> DictionaryCoverageReport.Item? {
        let lookup = store.lookup(forSurface: surface)
        let status: DictionaryCoverageReport.Status
        if lookup.entries.isEmpty {
            status = .missing
        } else if store.isContextSensitiveKanaLookup(lookup) {
            status = .untrustedKana
        } else if lookup.matchKind == .tailTrim || lookup.matchKind == .prefix {
            status = .weak
        } else {
            return nil
        }
        return DictionaryCoverageReport.Item(
            surface: surface,
            status: status,
            matchKind: lookup.matchKind,
            matchedHeadword: status == .missing ? nil : lookup.resolvedLemma,
            reading: JapaneseTokenizer.hiraganaReading(for: surface)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            occurrences: [],
            lessonTitles: []
        )
    }

    /// Skips punctuation, digits, and Latin tokens — only kana / kanji can be dictionary words.
    private static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3041...0x309F, // hiragana
                 0x30A1...0x30FA, // katakana (not ・ or ー alone)
                 0x3400...0x4DBF, // CJK ext A
                 0x4E00...0x9FFF, // CJK unified
                 0xF900...0xFAFF, // CJK compatibility
                 0xFF66...0xFF9F: // half-width katakana
                return true
            default:
                return false
            }
        }
    }
}
