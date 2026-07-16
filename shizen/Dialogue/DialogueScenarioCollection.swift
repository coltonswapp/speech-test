//
//  DialogueScenarioCollection.swift
//  shizen
//
//  Standalone, curriculum-ordered dialogue collections (e.g. "At the Train
//  Station"). Each collection bundles its own scene image and a set of
//  progressively harder scenarios with curated learning highlights. Loaded from
//  JSON in the app bundle, decoupled from the grammar-point catalog.
//

import Foundation

// MARK: - Runtime model

struct DialogueScenarioCollection: Hashable {
    let id: String
    let title: String
    let subtitle: String?
    /// Asset-catalog image shown at the top of every scenario in this collection.
    let sceneImageName: String?
    /// Public CDN thumbnail for lesson cards when served from the CMS.
    let thumbnailURL: URL?
    let scenarios: [Scenario]

    struct Scenario: Hashable {
        let id: String
        let menuTitle: String
        let menuSubtitle: String?
        let example: GrammarExample
        let highlights: DialogueLearningHighlights
        let quiz: [DialogueQuizQuestion]
        let grammarPointIDs: [String]
        let lines: [TaggedLine]

        struct TaggedLine: Hashable {
            let lineID: String
            let speaker: String
            let japanese: String
            let romaji: String?
            let english: String?
            let grammarPointIDs: [String]
        }
    }
}

// MARK: - JSON decoding shapes

private struct DialogueScenarioCollectionFile: Decodable {
    let id: String
    let title: String
    let subtitle: String?
    let sceneImage: String?
    let thumbnailUrl: String?
    let scenarios: [ScenarioRecord]

    struct ScenarioRecord: Decodable {
        let id: String
        let menuTitle: String
        let menuSubtitle: String?
        let japanese: String
        let romaji: String
        let english: String
        let targetSubstring: String?
        let audioKey: String?
        let publishedAudioUrl: String?
        let grammarPointIDs: [String]?
        let scenario: ScenarioBody
        let highlights: HighlightsRecord?
        let quiz: [QuizRecord]?
    }

    struct QuizRecord: Decodable {
        let prompt: String
        let layout: DialogueQuizQuestion.Layout
        let choices: [String]
        let correctChoice: String
        let wrongAnswerExplanation: String
    }

    struct ScenarioBody: Decodable {
        let setting: String?
        let lines: [LineRecord]
    }

    struct LineRecord: Decodable {
        let id: String?
        let speaker: String
        let japanese: String
        let romaji: String?
        let english: String?
        let grammarPointIDs: [String]?
    }

    struct HighlightsRecord: Decodable {
        let vocabulary: [String]?
        let grammarPatterns: [GrammarPatternRecord]?
        let contextNotes: [String]?
    }

    struct GrammarPatternRecord: Decodable {
        let label: String
        let grammarPointID: String?

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer(),
               let string = try? single.decode(String.self) {
                label = string
                grammarPointID = nil
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            label = try container.decode(String.self, forKey: .label)
            grammarPointID = try container.decodeIfPresent(String.self, forKey: .grammarPointID)
        }

        private enum CodingKeys: String, CodingKey {
            case label, grammarPointID
        }
    }
}

private extension DialogueScenarioCollection {
    init(file: DialogueScenarioCollectionFile) {
        id = file.id
        title = file.title
        subtitle = file.subtitle
        sceneImageName = file.sceneImage
        thumbnailURL = file.thumbnailUrl.flatMap(URL.init(string:))
        scenarios = file.scenarios.map { record in
            let taggedLines = record.scenario.lines.enumerated().map { index, line in
                Scenario.TaggedLine(
                    lineID: line.id ?? "\(record.id)/line-\(index)",
                    speaker: line.speaker,
                    japanese: line.japanese,
                    romaji: line.romaji,
                    english: line.english,
                    grammarPointIDs: line.grammarPointIDs ?? []
                )
            }
            let lines = taggedLines.map { tagged in
                GrammarScenarioLine(
                    speaker: tagged.speaker,
                    japanese: tagged.japanese,
                    romaji: tagged.romaji,
                    english: tagged.english,
                    grammarPointIDs: tagged.grammarPointIDs,
                    lineID: tagged.lineID
                )
            }
            let example = GrammarExample(
                japanese: record.japanese,
                romaji: record.romaji,
                english: record.english,
                targetSubstring: record.targetSubstring,
                audioKey: record.audioKey,
                publishedAudioUrl: record.publishedAudioUrl,
                scenario: GrammarScenario(
                    setting: record.scenario.setting,
                    lines: lines
                ),
                sourceScenarioId: record.id
            )
            let grammarPatterns = (record.highlights?.grammarPatterns ?? []).map {
                DialogueGrammarPatternRef(label: $0.label, grammarPointID: $0.grammarPointID)
            }
            let highlights = DialogueLearningHighlights(
                vocabulary: record.highlights?.vocabulary ?? [],
                grammarPatterns: grammarPatterns,
                contextNotes: record.highlights?.contextNotes ?? []
            )
            let scenarioGrammarIDs = record.grammarPointIDs
                ?? Array(Set(grammarPatterns.compactMap(\.grammarPointID) + taggedLines.flatMap(\.grammarPointIDs)))
            let quiz = (record.quiz ?? []).map {
                DialogueQuizQuestion(
                    prompt: $0.prompt,
                    choices: $0.choices,
                    correctChoice: $0.correctChoice,
                    wrongAnswerExplanation: $0.wrongAnswerExplanation,
                    layout: $0.layout
                )
            }
            return Scenario(
                id: record.id,
                menuTitle: record.menuTitle,
                menuSubtitle: record.menuSubtitle,
                example: example,
                highlights: highlights,
                quiz: quiz,
                grammarPointIDs: scenarioGrammarIDs,
                lines: taggedLines
            )
        }
    }
}

// MARK: - Catalog / loader

enum DialogueScenarioCollectionCatalog {

    static let trainStationID = "train-station"

    private static let cacheLock = NSLock()
    private static var remoteCollections: [String: DialogueScenarioCollection] = [:]
    /// Completions waiting on an in-flight CMS fetch for a given collection id.
    private static var inFlightCompletions: [String: [(DialogueScenarioCollection?) -> Void]] = [:]

    static func collection(id: String) -> DialogueScenarioCollection? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let remote = remoteCollections[id] {
            return remote
        }
        return bundledCollections[id]
    }

    /// Collection that can be presented immediately — remote cache hit, or bundled
    /// when the CMS is not configured. Returns `nil` when a network fetch is needed.
    static func readyCollection(id: String) -> DialogueScenarioCollection? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let remote = remoteCollections[id] {
            return remote
        }
        guard !ContentCMSClient.isConfigured else { return nil }
        return bundledCollections[id]
    }

    static var trainStation: DialogueScenarioCollection? {
        collection(id: trainStationID)
    }

    static var allCollections: [DialogueScenarioCollection] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        var merged = bundledCollections
        for (id, remote) in remoteCollections {
            merged[id] = remote
        }
        return Array(merged.values).sorted { $0.title < $1.title }
    }

    /// Fetches a collection from the CMS when configured; falls back to bundled JSON.
    /// Subsequent calls for the same id reuse the remote cache (or join an in-flight fetch).
    static func fetchCollection(
        id: String,
        completion: @escaping (DialogueScenarioCollection?) -> Void
    ) {
        cacheLock.lock()
        if let cached = remoteCollections[id] {
            cacheLock.unlock()
            DispatchQueue.main.async { completion(cached) }
            return
        }
        if inFlightCompletions[id] != nil {
            inFlightCompletions[id, default: []].append(completion)
            cacheLock.unlock()
            return
        }
        inFlightCompletions[id] = [completion]
        cacheLock.unlock()

        guard ContentCMSClient.isConfigured else {
            finishFetch(id: id, result: collection(id: id))
            return
        }

        ContentCMSClient.fetchDialogueCollection(id: id) { result in
            switch result {
            case .success(let data):
                guard let file = try? JSONDecoder().decode(
                    DialogueScenarioCollectionFile.self,
                    from: data
                ) else {
                    finishFetch(id: id, result: collection(id: id))
                    return
                }
                let decoded = DialogueScenarioCollection(file: file)
                cacheLock.lock()
                remoteCollections[id] = decoded
                cacheLock.unlock()
                finishFetch(id: id, result: decoded)
            case .failure:
                finishFetch(id: id, result: collection(id: id))
            }
        }
    }

    private static func finishFetch(id: String, result: DialogueScenarioCollection?) {
        cacheLock.lock()
        let completions = inFlightCompletions.removeValue(forKey: id) ?? []
        cacheLock.unlock()
        DispatchQueue.main.async {
            for completion in completions {
                completion(result)
            }
        }
    }

    static func prefetchConfiguredCollections() {
        guard ContentCMSClient.isConfigured else { return }
        fetchCollection(id: trainStationID) { _ in }
    }

    static func scenarios(containingGrammarPointID grammarID: String) -> [ScenarioReference] {
        allCollections.flatMap { collection in
            collection.scenarios.compactMap { scenario in
                guard scenario.grammarPointIDs.contains(grammarID) else { return nil }
                return ScenarioReference(collection: collection, scenario: scenario)
            }
        }
    }

    static func meaningChoiceLines(
        forGrammarPointID grammarID: String,
        completedScenarioIDs: Set<String>
    ) -> [MeaningChoiceLineSource] {
        var results: [MeaningChoiceLineSource] = []
        for collection in allCollections {
            for scenario in collection.scenarios where completedScenarioIDs.contains(scenario.id) {
                for line in scenario.lines {
                    guard line.grammarPointIDs.contains(grammarID),
                          let english = line.english?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !english.isEmpty
                    else { continue }
                    results.append(
                        MeaningChoiceLineSource(
                            japanese: line.japanese,
                            reading: line.romaji ?? line.japanese,
                            english: english,
                            sourceLineId: line.lineID,
                            sourceScenarioId: scenario.id,
                            collectionID: collection.id
                        )
                    )
                }
                if results.isEmpty, scenario.grammarPointIDs.contains(grammarID) {
                    let english = scenario.example.english.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !english.isEmpty {
                        results.append(
                            MeaningChoiceLineSource(
                                japanese: scenario.example.japanese,
                                reading: scenario.example.romaji,
                                english: english,
                                sourceLineId: scenario.lines.first?.lineID ?? "\(scenario.id)/line-0",
                                sourceScenarioId: scenario.id,
                                collectionID: collection.id
                            )
                        )
                    }
                }
            }
        }
        return results
    }

    struct ScenarioReference: Hashable {
        let collection: DialogueScenarioCollection
        let scenario: DialogueScenarioCollection.Scenario

        var scenarioID: String { scenario.id }
        var menuTitle: String { scenario.menuTitle }
        var collectionTitle: String { collection.title }
    }

    struct MeaningChoiceLineSource: Hashable {
        let japanese: String
        let reading: String
        let english: String
        let sourceLineId: String
        let sourceScenarioId: String
        let collectionID: String
    }

    private static let bundledCollections: [String: DialogueScenarioCollection] = {
        var byID: [String: DialogueScenarioCollection] = [:]
        for resourceName in bundledResourceNames {
            guard let collection = decodeCollection(resourceName: resourceName) else { continue }
            byID[collection.id] = collection
        }
        return byID
    }()

    /// Collection JSON files bundled with the app. Add new collection ids here.
    private static let bundledResourceNames = ["train-station"]

    private static func decodeCollection(resourceName: String) -> DialogueScenarioCollection? {
        guard let url = bundleJSONURL(resourceName: resourceName),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(DialogueScenarioCollectionFile.self, from: data)
        else { return nil }
        return DialogueScenarioCollection(file: file)
    }

    /// Xcode folder-sync layouts vary; try known paths, then scan the bundle.
    private static func bundleJSONURL(resourceName: String) -> URL? {
        let subdirectories = [
            "Dialogue",
            "Resources/Dialogue",
            "shizen/Dialogue",
            "shizen/Resources/Dialogue",
            "collections",
        ]
        for subdirectory in subdirectories {
            if let url = Bundle.main.url(
                forResource: resourceName,
                withExtension: "json",
                subdirectory: subdirectory
            ) {
                return url
            }
        }
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "json") {
            return url
        }
        return findResourceInBundle(named: "\(resourceName).json")
    }

    private static func findResourceInBundle(named filename: String) -> URL? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        let root = URL(fileURLWithPath: resourcePath)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return nil }
        for case let fileURL as URL in enumerator where fileURL.lastPathComponent == filename {
            return fileURL
        }
        return nil
    }
}
