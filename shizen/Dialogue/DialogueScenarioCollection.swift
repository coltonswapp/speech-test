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
        let publishedVariantId: String?
        let publishedContentHash: String?
        let publishedAt: String?
        let grammarPointIDs: [String]?
        let scenario: ScenarioBody
        let highlights: HighlightsRecord?
        let quiz: [QuizRecord]?
        let tokenSync: TokenSyncRecord?

        enum CodingKeys: String, CodingKey {
            case id, menuTitle, menuSubtitle, japanese, romaji, english
            case targetSubstring, audioKey, publishedAudioUrl, publishedVariantId
            case publishedContentHash, publishedAt, grammarPointIDs
            case scenario, highlights, quiz, tokenSync
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            menuTitle = try container.decode(String.self, forKey: .menuTitle)
            menuSubtitle = try container.decodeIfPresent(String.self, forKey: .menuSubtitle)
            japanese = try container.decode(String.self, forKey: .japanese)
            romaji = try container.decode(String.self, forKey: .romaji)
            english = try container.decode(String.self, forKey: .english)
            targetSubstring = try container.decodeIfPresent(String.self, forKey: .targetSubstring)
            audioKey = try container.decodeIfPresent(String.self, forKey: .audioKey)
            publishedAudioUrl = try container.decodeIfPresent(String.self, forKey: .publishedAudioUrl)
            publishedVariantId = try container.decodeIfPresent(String.self, forKey: .publishedVariantId)
            publishedContentHash = try container.decodeIfPresent(String.self, forKey: .publishedContentHash)
            publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt)
            grammarPointIDs = try container.decodeIfPresent([String].self, forKey: .grammarPointIDs)
            scenario = try container.decode(ScenarioBody.self, forKey: .scenario)
            highlights = try container.decodeIfPresent(HighlightsRecord.self, forKey: .highlights)
            quiz = try container.decodeIfPresent([QuizRecord].self, forKey: .quiz)
            // Karaoke is optional — a bad stamp payload must not drop the lesson.
            tokenSync = try? container.decode(TokenSyncRecord.self, forKey: .tokenSync)
        }
    }

    struct TokenSyncRecord: Decodable {
        let version: Int
        let variantId: String
        let contentHash: String
        let lines: [Line]

        struct Line: Decodable {
            let text: String
            let tokens: [Token]
        }

        struct Token: Decodable {
            let text: String
            let startSeconds: Double

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                text = try container.decode(String.self, forKey: .text)
                if let seconds = try? container.decode(Double.self, forKey: .startSeconds) {
                    startSeconds = seconds
                } else {
                    startSeconds = Double(try container.decode(Int.self, forKey: .startSeconds))
                }
            }

            private enum CodingKeys: String, CodingKey {
                case text, startSeconds
            }
        }

        func model() -> DialogueTokenSync {
            DialogueTokenSync(
                version: version,
                variantId: variantId,
                contentHash: contentHash,
                lines: lines.map { line in
                    DialogueTokenSync.Line(
                        text: line.text,
                        tokens: line.tokens.map {
                            DialogueTokenSync.Token(text: $0.text, startSeconds: $0.startSeconds)
                        }
                    )
                }
            )
        }
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
        let type: String?
        let speaker: String?
        let japanese: String?
        let romaji: String?
        let english: String?
        let grammarPointIDs: [String]?
        let text: String?
        let visibility: String?
        let prompt: String?
        let target: String?
        let layout: DialogueQuizQuestion.Layout?
        let choices: [String]?
        let correctChoice: String?
        let wrongAnswerExplanation: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id)
            type = try container.decodeIfPresent(String.self, forKey: .type)
            speaker = try container.decodeIfPresent(String.self, forKey: .speaker)
            japanese = try container.decodeIfPresent(String.self, forKey: .japanese)
            romaji = try container.decodeIfPresent(String.self, forKey: .romaji)
            english = try container.decodeIfPresent(String.self, forKey: .english)
            grammarPointIDs = try container.decodeIfPresent([String].self, forKey: .grammarPointIDs)
            text = try container.decodeIfPresent(String.self, forKey: .text)
            visibility = try container.decodeIfPresent(String.self, forKey: .visibility)
            prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
            target = try container.decodeIfPresent(String.self, forKey: .target)
            if let raw = try container.decodeIfPresent(String.self, forKey: .layout) {
                layout = DialogueQuizQuestion.Layout(rawValue: raw) ?? .grid
            } else {
                layout = nil
            }
            choices = try container.decodeIfPresent([String].self, forKey: .choices)
            correctChoice = try container.decodeIfPresent(String.self, forKey: .correctChoice)
            wrongAnswerExplanation = try container.decodeIfPresent(
                String.self,
                forKey: .wrongAnswerExplanation
            )
        }

        private enum CodingKeys: String, CodingKey {
            case id, type, speaker, japanese, romaji, english, grammarPointIDs
            case text, visibility, prompt, target, layout, choices
            case correctChoice, wrongAnswerExplanation
        }

        func grammarScenarioLine(scenarioID: String, fallbackIndex: Int) -> GrammarScenarioLine? {
            if type == "inline-question" {
                let promptText = prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let optionChoices = (choices ?? []).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
                let correct = correctChoice?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !promptText.isEmpty else {
                    print("[inline-question] DROPPED \(scenarioID)#\(fallbackIndex): empty prompt choices=\(optionChoices.count) correct=\(correct.isEmpty ? "empty" : "ok")")
                    return nil
                }
                print("[inline-question] decoded \(scenarioID)#\(fallbackIndex) prompt=\(promptText) choices=\(optionChoices.count)")
                return GrammarScenarioLine(
                    speaker: "",
                    japanese: promptText,
                    romaji: nil,
                    english: nil,
                    grammarPointIDs: [],
                    lineID: id ?? "\(scenarioID)/inline-question-\(fallbackIndex)",
                    inlineQuestion: DialogueInlineQuestion(
                        prompt: promptText,
                        target: target?.trimmingCharacters(in: .whitespacesAndNewlines),
                        choices: optionChoices,
                        correctChoice: correct,
                        wrongAnswerExplanation: wrongAnswerExplanation ?? "",
                        layout: layout ?? .grid
                    )
                )
            }
            if type == "stage" {
                let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !trimmed.isEmpty else { return nil }
                let stageVisibility = DialogueStageLineVisibility(rawValue: visibility ?? "cold") ?? .cold
                return GrammarScenarioLine(
                    speaker: "",
                    japanese: trimmed,
                    romaji: nil,
                    english: nil,
                    grammarPointIDs: [],
                    lineID: id ?? "\(scenarioID)/stage-\(fallbackIndex)",
                    stageVisibility: stageVisibility
                )
            }
            let speakerName = speaker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let japaneseText = japanese?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !speakerName.isEmpty, !japaneseText.isEmpty else { return nil }
            return GrammarScenarioLine(
                speaker: speakerName,
                japanese: japaneseText,
                romaji: romaji,
                english: english,
                grammarPointIDs: grammarPointIDs ?? [],
                lineID: id ?? "\(scenarioID)/line-\(fallbackIndex)"
            )
        }

        func taggedLine(scenarioID: String, fallbackIndex: Int) -> DialogueScenarioCollection.Scenario.TaggedLine? {
            guard type != "stage", type != "inline-question" else { return nil }
            let speakerName = speaker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let japaneseText = japanese?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !speakerName.isEmpty, !japaneseText.isEmpty else { return nil }
            return DialogueScenarioCollection.Scenario.TaggedLine(
                lineID: id ?? "\(scenarioID)/line-\(fallbackIndex)",
                speaker: speakerName,
                japanese: japaneseText,
                romaji: romaji,
                english: english,
                grammarPointIDs: grammarPointIDs ?? []
            )
        }
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
            let taggedLines = record.scenario.lines.enumerated().compactMap { index, line in
                line.taggedLine(scenarioID: record.id, fallbackIndex: index)
            }
            let lines = record.scenario.lines.enumerated().compactMap { index, line in
                line.grammarScenarioLine(scenarioID: record.id, fallbackIndex: index)
            }
            let example = GrammarExample(
                japanese: record.japanese,
                romaji: record.romaji,
                english: record.english,
                targetSubstring: record.targetSubstring,
                audioKey: record.audioKey,
                publishedAudioUrl: record.publishedAudioUrl,
                publishedVariantId: record.publishedVariantId,
                publishedContentHash: record.publishedContentHash,
                publishedAt: record.publishedAt,
                scenario: GrammarScenario(
                    setting: record.scenario.setting,
                    lines: lines
                ),
                sourceScenarioId: record.id,
                tokenSync: DialogueTokenSync.validated(
                    record.tokenSync?.model(),
                    spokenTexts: lines.filter(\.isSpokenLine).map(\.japanese),
                    publishedContentHash: record.publishedContentHash
                )
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
                    target: nil,
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
    /// Always revalidates against the network so a republish is visible without
    /// force-quitting. In-flight fetches for the same id are joined.
    static func fetchCollection(
        id: String,
        completion: @escaping (DialogueScenarioCollection?) -> Void
    ) {
        cacheLock.lock()
        if inFlightCompletions[id] != nil {
            inFlightCompletions[id, default: []].append(completion)
            cacheLock.unlock()
            return
        }
        inFlightCompletions[id] = [completion]
        cacheLock.unlock()

        print("[inline-question] fetch \(id) cms=\(ContentCMSClient.isConfigured) base=\(ContentCMSClient.baseURL?.absoluteString ?? "nil")")
        guard ContentCMSClient.isConfigured else {
            print("[inline-question] fetch \(id) using bundled/cache — CMS not configured")
            finishFetch(id: id, result: collection(id: id))
            return
        }
        ContentCMSClient.fetchDialogueCollection(id: id) { result in
            switch result {
            case .success(let data):
                Self.logRawInlineQuestions(in: data, collectionID: id)
                do {
                    let file = try JSONDecoder().decode(
                        DialogueScenarioCollectionFile.self,
                        from: data
                    )
                    let decoded = DialogueScenarioCollection(file: file)
                    Self.logDecodedInlineQuestions(in: decoded)
                    cacheLock.lock()
                    remoteCollections[id] = decoded
                    cacheLock.unlock()
                    finishFetch(id: id, result: decoded)
                } catch {
                    print("[inline-question] DECODE FAILED \(id): \(error)")
                    print("DialogueScenarioCollection: decode failed for \(id): \(error)")
                    finishFetch(id: id, result: collection(id: id))
                }
            case .failure(let error):
                print("[inline-question] FETCH FAILED \(id): \(error) — falling back to cache/bundle")
                print("DialogueScenarioCollection: fetch failed for \(id): \(error)")
                finishFetch(id: id, result: collection(id: id))
            }
        }
    }

    private static func logRawInlineQuestions(in data: Data, collectionID: String) {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let scenarios = root["scenarios"] as? [[String: Any]]
        else {
            print("[inline-question] raw \(collectionID): could not parse JSON object")
            return
        }
        for scenario in scenarios {
            let scenarioID = scenario["id"] as? String ?? "?"
            let lines = (scenario["scenario"] as? [String: Any])?["lines"] as? [[String: Any]] ?? []
            let types = lines.map { $0["type"] as? String ?? "spoken" }
            let inlineCount = types.filter { $0 == "inline-question" }.count
            print("[inline-question] raw \(scenarioID): \(inlineCount)/\(lines.count) inline-question types=\(types)")
        }
    }

    private static func logDecodedInlineQuestions(in collection: DialogueScenarioCollection) {
        for scenario in collection.scenarios {
            let lines = scenario.example.scenario?.lines ?? []
            let inline = lines.enumerated().compactMap { index, line -> String? in
                guard line.isInlineQuestion else { return nil }
                return "#\(index) \(line.inlineQuestion?.prompt ?? "?")"
            }
            print("[inline-question] decoded \(scenario.id): \(inline.count)/\(lines.count) kept \(inline)")
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
