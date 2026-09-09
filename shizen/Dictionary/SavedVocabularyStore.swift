//
//  SavedVocabularyStore.swift
//  shizen
//
//  Local folders of saved vocabulary. Codable documents are shaped for a later
//  Firestore `users/{uid}/folders/{id}` collection.
//

import Foundation

struct SavedVocabularyItem: Codable, Equatable, Identifiable {
    var id: String
    var surface: String
    var dictionaryForm: String?
    var reading: String?
    var gloss: String?
    var sentence: String?
    var createdAt: Date

    var flashcard: VocabFlashcard {
        VocabFlashcard(
            japanese: surface,
            reading: reading ?? "",
            english: gloss ?? sentence ?? ""
        )
    }
}

struct SavedVocabularyFolder: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var items: [SavedVocabularyItem]
    var createdAt: Date

    var subtitle: String {
        if items.isEmpty {
            return "Empty · save words from the dictionary"
        }
        return items.count == 1 ? "1 word" : "\(items.count) words"
    }

    var sampleJapanese: String {
        items.sorted { $0.createdAt > $1.createdAt }.first?.surface ?? "語"
    }
}

protocol SavedVocabularyStoring: AnyObject {
    func folders() -> [SavedVocabularyFolder]
    func folder(id: String) -> SavedVocabularyFolder?
    func items(inFolderID folderID: String) -> [SavedVocabularyItem]
    func item(matchingSurface surface: String) -> SavedVocabularyItem?
    func contains(surface: String) -> Bool
    func contains(surface: String, inFolderID folderID: String) -> Bool
    @discardableResult func save(_ item: SavedVocabularyItem, toFolderID folderID: String) -> SavedVocabularyItem
    @discardableResult func createFolder(name: String) -> SavedVocabularyFolder
    func remove(id: String, fromFolderID folderID: String)
}

final class SavedVocabularyStore: SavedVocabularyStoring {

    static let shared = SavedVocabularyStore()
    static let inboxID = "inbox"
    static let inboxName = "Inbox"
    static let didChangeNotification = Notification.Name("SavedVocabularyStoreDidChange")

    private let fileURL: URL
    private var storedFolders: [SavedVocabularyFolder]

    init(
        fileManager: FileManager = .default,
        fileName: String = "saved-vocabulary.json"
    ) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("shizen", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent(fileName)
        let loaded = Self.loadFolders(from: fileURL)
        storedFolders = loaded.folders
        if loaded.migratedFromLegacy {
            persist()
        }
        ensureInbox()
    }

    func folders() -> [SavedVocabularyFolder] {
        let inbox = storedFolders.filter { $0.id == Self.inboxID }
        let rest = storedFolders
            .filter { $0.id != Self.inboxID }
            .sorted { $0.createdAt < $1.createdAt }
        return inbox + rest
    }

    func folder(id: String) -> SavedVocabularyFolder? {
        storedFolders.first { $0.id == id }
    }

    func items(inFolderID folderID: String) -> [SavedVocabularyItem] {
        folder(id: folderID)?.items.sorted { $0.createdAt > $1.createdAt } ?? []
    }

    func item(matchingSurface surface: String) -> SavedVocabularyItem? {
        let key = Self.normalized(surface)
        guard !key.isEmpty else { return nil }
        for folder in storedFolders {
            if let match = folder.items.first(where: { Self.normalized($0.surface) == key }) {
                return match
            }
        }
        return nil
    }

    func contains(surface: String) -> Bool {
        item(matchingSurface: surface) != nil
    }

    func contains(surface: String, inFolderID folderID: String) -> Bool {
        let key = Self.normalized(surface)
        guard !key.isEmpty else { return false }
        return folder(id: folderID)?.items.contains { Self.normalized($0.surface) == key } == true
    }

    @discardableResult
    func save(_ item: SavedVocabularyItem, toFolderID folderID: String) -> SavedVocabularyItem {
        ensureInbox()
        let surface = Self.normalized(item.surface)
        guard !surface.isEmpty, let index = storedFolders.firstIndex(where: { $0.id == folderID }) else {
            return item
        }
        if let existing = storedFolders[index].items.first(where: { Self.normalized($0.surface) == surface }) {
            return existing
        }

        var stored = item
        stored.id = stored.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if stored.id.isEmpty {
            stored.id = UUID().uuidString
        }
        stored.surface = surface
        stored.dictionaryForm = Self.optionalNormalized(item.dictionaryForm)
        stored.reading = Self.optionalNormalized(item.reading)
        stored.gloss = Self.optionalNormalized(item.gloss)
        stored.sentence = Self.optionalNormalized(item.sentence)
        storedFolders[index].items.append(stored)
        persist()
        return stored
    }

    @discardableResult
    func createFolder(name: String) -> SavedVocabularyFolder {
        ensureInbox()
        let trimmed = Self.normalized(name)
        let folder = SavedVocabularyFolder(
            id: UUID().uuidString,
            name: trimmed.isEmpty ? "New folder" : trimmed,
            items: [],
            createdAt: Date()
        )
        storedFolders.append(folder)
        persist()
        return folder
    }

    func remove(id: String, fromFolderID folderID: String) {
        guard let index = storedFolders.firstIndex(where: { $0.id == folderID }) else { return }
        let before = storedFolders[index].items.count
        storedFolders[index].items.removeAll { $0.id == id }
        guard storedFolders[index].items.count != before else { return }
        persist()
    }

    private func ensureInbox() {
        guard !storedFolders.contains(where: { $0.id == Self.inboxID }) else { return }
        storedFolders.insert(
            SavedVocabularyFolder(
                id: Self.inboxID,
                name: Self.inboxName,
                items: [],
                createdAt: Date(timeIntervalSince1970: 0)
            ),
            at: 0
        )
        persist()
    }

    private func persist() {
        guard let data = try? Self.makeEncoder().encode(Snapshot(folders: storedFolders)) else { return }
        try? data.write(to: fileURL, options: [.atomic])
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private static func loadFolders(from fileURL: URL) -> (folders: [SavedVocabularyFolder], migratedFromLegacy: Bool) {
        guard let data = try? Data(contentsOf: fileURL) else {
            return ([], false)
        }
        let decoder = makeDecoder()
        if let snapshot = try? decoder.decode(Snapshot.self, from: data) {
            return (snapshot.folders, false)
        }
        if let legacy = try? decoder.decode(LegacySnapshot.self, from: data) {
            return (
                [
                    SavedVocabularyFolder(
                        id: inboxID,
                        name: inboxName,
                        items: legacy.items,
                        createdAt: Date(timeIntervalSince1970: 0)
                    )
                ],
                true
            )
        }
        return ([], false)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func optionalNormalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private struct Snapshot: Codable {
        var folders: [SavedVocabularyFolder]
    }

    private struct LegacySnapshot: Codable {
        var items: [SavedVocabularyItem]
    }
}
