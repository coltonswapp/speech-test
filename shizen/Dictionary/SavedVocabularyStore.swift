//
//  SavedVocabularyStore.swift
//  shizen
//
//  Saved vocabulary folders for the signed-in user: `users/{uid}/folders/{folderId}`.
//

import FirebaseFirestore
import Foundation
import os

enum SavedVocabularyKind: String, Codable, Equatable {
    case word
    /// A multi-token span saved as one card, glossed in its sentence.
    case phrase
}

struct SavedVocabularyItem: Codable, Equatable, Identifiable {
    var id: String
    var surface: String
    var dictionaryForm: String?
    var reading: String?
    /// Primary sense text. Kept so older readers still see one gloss.
    var gloss: String?
    /// Up to a few JMdict senses. Empty legacy rows migrate from `gloss` on load.
    var senses: [VocabSense]
    /// Index into `senses` the learner chose. Nil uses the first sense.
    var primarySenseIndex: Int?
    var sentence: String?
    /// Missing on rows saved before phrase cards; those read as `.word`.
    var kind: SavedVocabularyKind
    /// Scrub tokens for a phrase, so furigana and readings stay per word.
    var tokens: [String]?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    var isPhrase: Bool { kind == .phrase }

    var resolvedPrimaryIndex: Int {
        if let primarySenseIndex, senses.indices.contains(primarySenseIndex) {
            return primarySenseIndex
        }
        return 0
    }

    var primarySenseText: String? {
        if senses.indices.contains(resolvedPrimaryIndex) {
            return senses[resolvedPrimaryIndex].text
        }
        let trimmed = gloss?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var flashcard: VocabFlashcard {
        VocabFlashcard(
            japanese: surface,
            reading: reading ?? "",
            english: primarySenseText ?? sentence ?? "",
            sentence: sentence,
            tokens: isPhrase ? tokens : nil,
            dictionaryForm: dictionaryForm
        )
    }

    init(
        id: String,
        surface: String,
        dictionaryForm: String? = nil,
        reading: String? = nil,
        gloss: String? = nil,
        senses: [VocabSense] = [],
        primarySenseIndex: Int? = nil,
        sentence: String? = nil,
        kind: SavedVocabularyKind = .word,
        tokens: [String]? = nil,
        createdAt: Date,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.surface = surface
        self.dictionaryForm = dictionaryForm
        self.reading = reading
        self.sentence = sentence
        self.kind = kind
        let cleanedTokens = tokens?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.tokens = (cleanedTokens?.isEmpty ?? true) ? nil : cleanedTokens
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt

        var resolved = senses
        if resolved.isEmpty,
           let gloss = gloss?.trimmingCharacters(in: .whitespacesAndNewlines),
           !gloss.isEmpty {
            resolved = [VocabSense(text: gloss, sourceKey: nil)]
        }
        self.senses = resolved
        if let primarySenseIndex, resolved.indices.contains(primarySenseIndex) {
            self.primarySenseIndex = primarySenseIndex
        } else {
            self.primarySenseIndex = nil
        }
        if let gloss = gloss?.trimmingCharacters(in: .whitespacesAndNewlines), !gloss.isEmpty {
            self.gloss = gloss
        } else {
            self.gloss = resolved.first?.text
        }
    }

    /// One English line for the flashcard. Replaces any stacked sense list.
    mutating func setFlashcardDefinition(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        gloss = trimmed
        senses = [VocabSense(text: trimmed, sourceKey: nil)]
        primarySenseIndex = nil
    }

    var isDeleted: Bool { deletedAt != nil }

    private enum CodingKeys: String, CodingKey {
        case id, surface, dictionaryForm, reading, gloss, senses, primarySenseIndex, sentence, kind, tokens, createdAt, updatedAt, deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            surface: try container.decode(String.self, forKey: .surface),
            dictionaryForm: try container.decodeIfPresent(String.self, forKey: .dictionaryForm),
            reading: try container.decodeIfPresent(String.self, forKey: .reading),
            gloss: try container.decodeIfPresent(String.self, forKey: .gloss),
            senses: try container.decodeIfPresent([VocabSense].self, forKey: .senses) ?? [],
            primarySenseIndex: try container.decodeIfPresent(Int.self, forKey: .primarySenseIndex),
            sentence: try container.decodeIfPresent(String.self, forKey: .sentence),
            kind: (try? container.decodeIfPresent(SavedVocabularyKind.self, forKey: .kind)) ?? .word,
            tokens: try container.decodeIfPresent([String].self, forKey: .tokens),
            createdAt: createdAt,
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(surface, forKey: .surface)
        try container.encodeIfPresent(dictionaryForm, forKey: .dictionaryForm)
        try container.encodeIfPresent(reading, forKey: .reading)
        try container.encodeIfPresent(gloss, forKey: .gloss)
        try container.encode(senses, forKey: .senses)
        try container.encodeIfPresent(primarySenseIndex, forKey: .primarySenseIndex)
        try container.encodeIfPresent(sentence, forKey: .sentence)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(tokens, forKey: .tokens)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
}

struct SavedVocabularyFolder: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var items: [SavedVocabularyItem]
    var createdAt: Date
    var updatedAt: Date

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
    func setPrimarySenseIndex(_ index: Int, forItemID itemID: String, inFolderID folderID: String)
    @discardableResult func createFolder(name: String) -> SavedVocabularyFolder
    func remove(id: String, fromFolderID folderID: String)
    func move(id: String, fromFolderID: String, toFolderID: String)
}

final class SavedVocabularyStore: SavedVocabularyStoring {

    static let shared = SavedVocabularyStore()
    static let inboxID = "inbox"
    static let inboxName = "Inbox"
    static let didChangeNotification = Notification.Name("SavedVocabularyStoreDidChange")

    private static let surfaceLimit = 200
    private static let glossLimit = 600
    private static let senseTextLimit = 200
    private static let sourceKeyLimit = 80
    private static let sentenceLimit = 1200
    private static let nameLimit = 80
    private static let tokenLimit = 24

    private struct StoredFolder: Equatable {
        var id: String
        var name: String
        var createdAt: Date
        var updatedAt: Date
        var items: [String: SavedVocabularyItem]
    }

    private var storedFolders: [String: StoredFolder] = [:]
    private var pendingItems: [String: SavedVocabularyItem] = [:]
    private var readyFolderIDs: Set<String> = []
    private var queuedWrites: [(folderID: String, fields: [AnyHashable: Any])] = []
    private var literalRepairKeys: Set<String> = []
    private var listener: ListenerRegistration?
    private var authObserver: NSObjectProtocol?
    private var generation = 0
    private var didRequestInbox = false
    private let logger = Logger(subsystem: "com.swappfunc.shizen", category: "SavedVocabulary")

    init() {
        bind(uid: AuthService.shared.userId)
        authObserver = NotificationCenter.default.addObserver(
            forName: AuthService.userDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.bind(uid: AuthService.shared.userId)
            }
        }
    }

    func folders() -> [SavedVocabularyFolder] {
        let visible = storedFolders.values.map(publicFolder)
        let inbox = visible.filter { $0.id == Self.inboxID }
        let rest = visible
            .filter { $0.id != Self.inboxID }
            .sorted { $0.createdAt < $1.createdAt }
        return inbox + rest
    }

    func folder(id: String) -> SavedVocabularyFolder? {
        storedFolders[id].map(publicFolder)
    }

    func items(inFolderID folderID: String) -> [SavedVocabularyItem] {
        guard let folder = storedFolders[folderID] else { return [] }
        return folder.items.values
            .filter { !$0.isDeleted }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func item(matchingSurface surface: String) -> SavedVocabularyItem? {
        let key = Self.normalized(surface)
        guard !key.isEmpty else { return nil }
        for folder in storedFolders.values {
            if let match = folder.items.values.first(where: {
                !$0.isDeleted && Self.normalized($0.surface) == key
            }) {
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
        return storedFolders[folderID]?.items.values.contains {
            !$0.isDeleted && Self.normalized($0.surface) == key
        } == true
    }

    @discardableResult
    func save(_ item: SavedVocabularyItem, toFolderID folderID: String) -> SavedVocabularyItem {
        ensureInbox()
        let surface = Self.clipped(Self.normalized(item.surface), limit: Self.surfaceLimit)
        guard !surface.isEmpty, storedFolders[folderID] != nil else { return item }
        if let existing = storedFolders[folderID]?.items.values.first(where: {
            !$0.isDeleted && Self.normalized($0.surface) == surface
        }) {
            return existing
        }

        if var deleted = storedFolders[folderID]?.items.values.first(where: {
            $0.isDeleted && Self.normalized($0.surface) == surface
        }) {
            deleted = Self.applying(item, surface: surface, onto: deleted)
            deleted.updatedAt = Date()
            deleted.deletedAt = nil
            writeItem(deleted, toFolderID: folderID)
            return deleted
        }

        var stored = Self.applying(item, surface: surface, onto: item)
        stored.id = stored.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if stored.id.isEmpty || stored.id.contains("/") || stored.id.contains(".") {
            stored.id = UUID().uuidString
        }
        stored.createdAt = item.createdAt
        stored.updatedAt = Date()
        stored.deletedAt = nil
        writeItem(stored, toFolderID: folderID)
        return stored
    }

    func setPrimarySenseIndex(_ index: Int, forItemID itemID: String, inFolderID folderID: String) {
        guard var item = storedFolders[folderID]?.items[itemID], !item.isDeleted else { return }
        guard item.senses.indices.contains(index), item.primarySenseIndex != index else { return }
        item.primarySenseIndex = index
        item.gloss = Self.optionalClipped(item.senses[index].text, limit: Self.glossLimit)
        item.updatedAt = Date()
        writeItem(item, toFolderID: folderID)
    }

    @discardableResult
    func createFolder(name: String) -> SavedVocabularyFolder {
        ensureInbox()
        let trimmed = Self.clipped(Self.normalized(name), limit: Self.nameLimit)
        let now = Date()
        let folder = StoredFolder(
            id: UUID().uuidString,
            name: trimmed.isEmpty ? "New folder" : trimmed,
            createdAt: now,
            updatedAt: now,
            items: [:]
        )
        storedFolders[folder.id] = folder
        if AuthService.shared.userId != nil {
            LearnerFirestore.commit(folderPayload(name: folder.name), to: folderReference(folder.id), merge: false)
        }
        notify()
        return publicFolder(folder)
    }

    func remove(id: String, fromFolderID folderID: String) {
        guard var item = storedFolders[folderID]?.items[id], !item.isDeleted else { return }
        let now = Date()
        item.deletedAt = now
        item.updatedAt = now
        writeItem(item, toFolderID: folderID)
    }

    /// Moves an item onto one folder. Online, the two folder writes commit in one transaction.
    func move(id: String, fromFolderID: String, toFolderID: String) {
        guard fromFolderID != toFolderID else { return }
        guard var item = storedFolders[fromFolderID]?.items[id], !item.isDeleted else { return }
        guard storedFolders[toFolderID] != nil else { return }

        let now = Date()
        var tombstone = item
        tombstone.deletedAt = now
        tombstone.updatedAt = now
        item.deletedAt = nil
        item.updatedAt = now.addingTimeInterval(0.001)
        storeLocally(tombstone, inFolderID: fromFolderID)
        storeLocally(item, inFolderID: toFolderID)
        notify()

        guard AuthService.shared.userId != nil else { return }
        let sourceFields = itemUpdateFields(tombstone)
        let destinationFields = itemUpdateFields(item)
        Task {
            await commitMove(
                id: id,
                fromFolderID: fromFolderID,
                toFolderID: toFolderID,
                sourceFields: sourceFields,
                destinationFields: destinationFields
            )
        }
    }

    private func ensureInbox() {
        if storedFolders[Self.inboxID] == nil {
            let now = Date()
            storedFolders[Self.inboxID] = StoredFolder(
                id: Self.inboxID,
                name: Self.inboxName,
                createdAt: now,
                updatedAt: now,
                items: [:]
            )
        }
        guard AuthService.shared.userId != nil else { return }
        guard !readyFolderIDs.contains(Self.inboxID), !didRequestInbox else { return }
        didRequestInbox = true
        // Merge, and do not send `items`. A replace would wipe words already on the folder.
        LearnerFirestore.commit(inboxEnsurePayload(), to: folderReference(Self.inboxID), merge: true)
    }

    private func writeItem(_ item: SavedVocabularyItem, toFolderID folderID: String) {
        storeLocally(item, inFolderID: folderID)
        notify()
        guard AuthService.shared.userId != nil else { return }
        queuedWrites.append((folderID, itemUpdateFields(item)))
        flushQueuedWrites()
    }

    private func storeLocally(_ item: SavedVocabularyItem, inFolderID folderID: String) {
        guard var folder = storedFolders[folderID] else { return }
        folder.items[item.id] = item
        folder.updatedAt = item.updatedAt
        storedFolders[folderID] = folder
        pendingItems[pendingKey(folderID: folderID, itemID: item.id)] = item
    }

    private func itemBody(_ item: SavedVocabularyItem) -> [String: Any] {
        [
            "surface": item.surface,
            "dictionaryForm": item.dictionaryForm ?? NSNull(),
            "reading": item.reading ?? NSNull(),
            "gloss": item.gloss ?? NSNull(),
            "senses": item.senses.map { sense -> [String: Any] in
                var body: [String: Any] = ["text": sense.text]
                if let sourceKey = sense.sourceKey {
                    body["sourceKey"] = sourceKey
                }
                return body
            },
            "primarySenseIndex": item.primarySenseIndex ?? NSNull(),
            "sentence": item.sentence ?? NSNull(),
            "kind": item.kind.rawValue,
            "tokens": item.tokens ?? NSNull(),
            "createdAt": Timestamp(date: item.createdAt),
            "updatedAt": Timestamp(date: item.updatedAt),
            "deletedAt": item.deletedAt.map { Timestamp(date: $0) } ?? NSNull(),
        ]
    }

    /// Nested `items.{id}` via `FieldPath`. A dotted string in `setData` is stored as one literal field name, which reads never see.
    private func itemUpdateFields(_ item: SavedVocabularyItem) -> [AnyHashable: Any] {
        [
            "updatedAt": FieldValue.serverTimestamp(),
            "lastItemId": item.id,
            FieldPath(["items", item.id]): itemBody(item),
            FieldPath(["items.\(item.id)"]): FieldValue.delete(),
        ]
    }

    private func folderPayload(name: String) -> [String: Any] {
        [
            "name": name,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "items": [:],
            "lastItemId": NSNull(),
        ]
    }

    private func inboxEnsurePayload() -> [String: Any] {
        [
            "name": Self.inboxName,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
    }

    private func commitMove(
        id: String,
        fromFolderID: String,
        toFolderID: String,
        sourceFields: [AnyHashable: Any],
        destinationFields: [AnyHashable: Any]
    ) async {
        guard AuthService.shared.userId != nil else { return }
        let sourceRef = folderReference(fromFolderID)
        let destinationRef = folderReference(toFolderID)
        do {
            let outcome = try await Firestore.firestore().runTransaction { transaction, errorPointer -> Any? in
                let sourceSnapshot: DocumentSnapshot
                let destinationSnapshot: DocumentSnapshot
                do {
                    sourceSnapshot = try transaction.getDocument(sourceRef)
                    destinationSnapshot = try transaction.getDocument(destinationRef)
                } catch let error as NSError {
                    errorPointer?.pointee = error
                    return nil
                }
                guard sourceSnapshot.exists, destinationSnapshot.exists else { return "missing" }
                guard let sourceItem = Self.storedItemMap(id: id, in: sourceSnapshot.data()) else { return "missing" }
                let destinationItem = Self.storedItemMap(id: id, in: destinationSnapshot.data())
                let sourceUpdated = LearnerSnapshotValue.date(sourceItem["updatedAt"]) ?? .distantPast
                let destinationUpdated = LearnerSnapshotValue.date(destinationItem?["updatedAt"]) ?? .distantPast
                let destinationDeleted = destinationItem?["deletedAt"] != nil && !(destinationItem?["deletedAt"] is NSNull)
                let now = Date()
                var tombstone = sourceItem
                tombstone["updatedAt"] = Timestamp(date: now)
                tombstone["deletedAt"] = Timestamp(date: now)
                var living = sourceItem
                living["createdAt"] = (destinationItem?["createdAt"] as? Timestamp) ?? sourceItem["createdAt"] ?? Timestamp(date: now)
                living["updatedAt"] = Timestamp(date: now.addingTimeInterval(0.001))
                living["deletedAt"] = NSNull()
                if destinationItem != nil, !destinationDeleted, destinationUpdated > sourceUpdated {
                    transaction.updateData(Self.itemWrite(id: id, body: tombstone), forDocument: sourceRef)
                    return "moved"
                }
                transaction.updateData(Self.itemWrite(id: id, body: living), forDocument: destinationRef)
                transaction.updateData(Self.itemWrite(id: id, body: tombstone), forDocument: sourceRef)
                return "moved"
            }
            if (outcome as? String) == "missing" {
                LearnerFirestore.update(sourceFields, on: sourceRef)
                LearnerFirestore.update(destinationFields, on: destinationRef)
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == FirestoreErrorDomain && nsError.code == FirestoreErrorCode.unavailable.rawValue {
                LearnerFirestore.update(sourceFields, on: sourceRef)
                LearnerFirestore.update(destinationFields, on: destinationRef)
            } else {
                logger.error("Folder move failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func bind(uid: String?) {
        generation += 1
        let generation = generation
        listener?.remove()
        listener = nil
        readyFolderIDs = []
        didRequestInbox = false
        queuedWrites = []
        pendingItems = [:]
        literalRepairKeys = []
        let hadFolders = !storedFolders.isEmpty
        storedFolders = [:]
        if hadFolders {
            notify()
        }
        guard let uid else { return }
        listener = LearnerFirestore.folders(uid: uid).addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                if let error {
                    self.logger.error("Folder listen failed: \(error.localizedDescription, privacy: .public)")
                    return
                }
                self.handle(snapshot)
            }
        }
    }

    private func handle(_ snapshot: QuerySnapshot?) {
        let documents = snapshot?.documents ?? []
        readyFolderIDs = Set(documents.map(\.documentID))
        if !readyFolderIDs.contains(Self.inboxID) {
            ensureInbox()
        }
        apply(documents)
        flushQueuedWrites()
        reconcileDuplicateItems()
    }

    private func apply(_ documents: [QueryDocumentSnapshot]) {
        var next: [String: StoredFolder] = [:]
        var literalRepairs: [String: [String: [String: Any]?]] = [:]
        for document in documents {
            let decoded = decodeFolder(id: document.documentID, data: document.data())
            next[document.documentID] = decoded.folder
            if !decoded.literalItems.isEmpty {
                literalRepairs[document.documentID] = decoded.literalItems
            }
        }
        for (id, folder) in storedFolders where next[id] == nil {
            next[id] = folder
        }
        for (key, pending) in pendingItems {
            let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let folderID = parts[0]
            let itemID = parts[1]
            var folder = next[folderID] ?? storedFolders[folderID]
            guard var folder else { continue }
            if let remote = folder.items[itemID], echoed(remote, pending) {
                pendingItems[key] = nil
            } else {
                folder.items[itemID] = pending
                next[folderID] = folder
            }
        }
        if next != storedFolders {
            storedFolders = next
            notify()
        }
        for (folderID, items) in literalRepairs {
            repairLiteralItems(folderID: folderID, items: items)
        }
    }

    private func reconcileDuplicateItems() {
        var winner: [String: (folderID: String, updatedAt: Date)] = [:]
        for folder in folders() {
            for item in folder.items where !item.isDeleted {
                if let current = winner[item.id] {
                    if item.updatedAt > current.updatedAt {
                        tombstoneIfLive(id: item.id, folderID: current.folderID)
                        winner[item.id] = (folder.id, item.updatedAt)
                    } else if item.updatedAt < current.updatedAt {
                        tombstoneIfLive(id: item.id, folderID: folder.id)
                    }
                } else {
                    winner[item.id] = (folder.id, item.updatedAt)
                }
            }
        }
    }

    private func tombstoneIfLive(id: String, folderID: String) {
        guard let item = storedFolders[folderID]?.items[id], !item.isDeleted else { return }
        remove(id: id, fromFolderID: folderID)
    }

    private func flushQueuedWrites() {
        var waiting: [(folderID: String, fields: [AnyHashable: Any])] = []
        for write in queuedWrites {
            if readyFolderIDs.contains(write.folderID) {
                LearnerFirestore.update(write.fields, on: folderReference(write.folderID))
            } else {
                waiting.append(write)
            }
        }
        queuedWrites = waiting
    }

    private struct DecodedFolder {
        var folder: StoredFolder
        /// Literal `items.{id}` fields to move under the `items` map. A nil body means the nested copy is newer, so only delete the literal field.
        var literalItems: [String: [String: Any]?]
    }

    private func decodeFolder(id: String, data: [String: Any]) -> DecodedFolder {
        var items: [String: SavedVocabularyItem] = [:]
        for (itemID, value) in LearnerSnapshotValue.map(data["items"]) {
            guard let item = decodeItem(id: itemID, value: value) else { continue }
            items[itemID] = item
        }
        var literalItems: [String: [String: Any]?] = [:]
        for (key, value) in data {
            guard let itemID = Self.literalItemID(fieldName: key) else { continue }
            guard let item = decodeItem(id: itemID, value: value) else { continue }
            if let existing = items[itemID], existing.updatedAt > item.updatedAt {
                literalItems[itemID] = nil
                continue
            }
            literalItems[itemID] = LearnerSnapshotValue.map(value)
            items[itemID] = item
        }
        let createdAt = LearnerSnapshotValue.date(data["createdAt"]) ?? Date()
        return DecodedFolder(
            folder: StoredFolder(
                id: id,
                name: LearnerSnapshotValue.string(data["name"]) ?? "Folder",
                createdAt: createdAt,
                updatedAt: LearnerSnapshotValue.date(data["updatedAt"]) ?? createdAt,
                items: items
            ),
            literalItems: literalItems
        )
    }

    private func repairLiteralItems(folderID: String, items: [String: [String: Any]?]) {
        guard AuthService.shared.userId != nil else { return }
        var fields: [AnyHashable: Any] = [:]
        for (itemID, payload) in items {
            let token = "\(folderID)/\(itemID)"
            guard literalRepairKeys.insert(token).inserted else { continue }
            if let payload {
                fields[FieldPath(["items", itemID])] = payload
            }
            fields[FieldPath(["items.\(itemID)"])] = FieldValue.delete()
        }
        guard !fields.isEmpty else { return }
        fields["updatedAt"] = FieldValue.serverTimestamp()
        LearnerFirestore.update(fields, on: folderReference(folderID))
    }

    private static func literalItemID(fieldName: String) -> String? {
        let prefix = "items."
        guard fieldName.hasPrefix(prefix) else { return nil }
        let itemID = String(fieldName.dropFirst(prefix.count))
        guard !itemID.isEmpty, !itemID.contains(".") else { return nil }
        return itemID
    }

    private static func storedItemMap(id: String, in data: [String: Any]?) -> [String: Any]? {
        let nested = LearnerSnapshotValue.map(data?["items"])
        if let item = nested[id] as? [String: Any] { return item }
        if let item = data?["items.\(id)"] as? [String: Any] { return item }
        return nil
    }

    private static func itemWrite(id: String, body: [String: Any]) -> [AnyHashable: Any] {
        [
            "updatedAt": FieldValue.serverTimestamp(),
            "lastItemId": id,
            FieldPath(["items", id]): body,
            FieldPath(["items.\(id)"]): FieldValue.delete(),
        ]
    }

    private func decodeItem(id: String, value: Any) -> SavedVocabularyItem? {
        let map = LearnerSnapshotValue.map(value)
        guard let surface = LearnerSnapshotValue.string(map["surface"]),
              let createdAt = LearnerSnapshotValue.date(map["createdAt"])
        else { return nil }
        return SavedVocabularyItem(
            id: id,
            surface: surface,
            dictionaryForm: LearnerSnapshotValue.string(map["dictionaryForm"]),
            reading: LearnerSnapshotValue.string(map["reading"]),
            gloss: LearnerSnapshotValue.string(map["gloss"]),
            senses: Self.decodeSenses(map["senses"]),
            primarySenseIndex: LearnerSnapshotValue.int(map["primarySenseIndex"]),
            sentence: LearnerSnapshotValue.string(map["sentence"]),
            kind: LearnerSnapshotValue.string(map["kind"]).flatMap(SavedVocabularyKind.init(rawValue:)) ?? .word,
            tokens: LearnerSnapshotValue.stringList(map["tokens"]),
            createdAt: createdAt,
            updatedAt: LearnerSnapshotValue.date(map["updatedAt"]) ?? createdAt,
            deletedAt: LearnerSnapshotValue.date(map["deletedAt"])
        )
    }

    private static func decodeSenses(_ value: Any?) -> [VocabSense] {
        guard let rows = value as? [Any] else { return [] }
        return rows.compactMap { row in
            let map = LearnerSnapshotValue.map(row)
            guard let text = LearnerSnapshotValue.string(map["text"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { return nil }
            return VocabSense(
                text: text,
                sourceKey: LearnerSnapshotValue.string(map["sourceKey"])
            )
        }
    }

    private func echoed(_ remote: SavedVocabularyItem, _ local: SavedVocabularyItem) -> Bool {
        let deletedMatches = remote.isDeleted == local.isDeleted
        return deletedMatches
            && remote.surface == local.surface
            && remote.gloss == local.gloss
            && remote.senses == local.senses
            && remote.primarySenseIndex == local.primarySenseIndex
            && remote.updatedAt >= local.updatedAt.addingTimeInterval(-1)
    }

    private func publicFolder(_ folder: StoredFolder) -> SavedVocabularyFolder {
        SavedVocabularyFolder(
            id: folder.id,
            name: folder.name,
            items: folder.items.values.filter { !$0.isDeleted }.sorted { $0.createdAt < $1.createdAt },
            createdAt: folder.createdAt,
            updatedAt: folder.updatedAt
        )
    }

    private func folderReference(_ folderID: String) -> DocumentReference {
        let uid = AuthService.shared.userId ?? ""
        return LearnerFirestore.folders(uid: uid).document(folderID)
    }

    private func pendingKey(folderID: String, itemID: String) -> String {
        "\(folderID)/\(itemID)"
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clipped(_ value: String, limit: Int) -> String {
        String(value.prefix(limit))
    }

    private static func optionalClipped(_ value: String?, limit: Int) -> String? {
        guard let trimmed = value.map(normalized), !trimmed.isEmpty else { return nil }
        return clipped(trimmed, limit: limit)
    }

    /// Copies dictionary fields onto `base`, clipping senses and keeping `gloss` as the primary text.
    private static func applying(
        _ item: SavedVocabularyItem,
        surface: String,
        onto base: SavedVocabularyItem
    ) -> SavedVocabularyItem {
        var stored = base
        stored.surface = surface
        stored.dictionaryForm = optionalClipped(item.dictionaryForm, limit: surfaceLimit)
        stored.reading = optionalClipped(item.reading, limit: surfaceLimit)
        stored.sentence = optionalClipped(item.sentence, limit: sentenceLimit)
        stored.kind = item.kind
        stored.tokens = item.kind == .phrase ? clippedTokens(item.tokens) : nil
        let senses = clippedSenses(item.senses)
        stored.senses = senses
        if let index = item.primarySenseIndex, senses.indices.contains(index) {
            stored.primarySenseIndex = index
        } else {
            stored.primarySenseIndex = nil
        }
        let primaryText = senses.indices.contains(stored.resolvedPrimaryIndex)
            ? senses[stored.resolvedPrimaryIndex].text
            : item.gloss
        stored.gloss = optionalClipped(primaryText, limit: glossLimit)
        if stored.senses.isEmpty, let gloss = stored.gloss {
            stored.senses = [VocabSense(text: gloss, sourceKey: nil)]
        }
        return stored
    }

    private static func clippedTokens(_ tokens: [String]?) -> [String]? {
        let clipped = (tokens ?? [])
            .compactMap { optionalClipped($0, limit: surfaceLimit) }
            .prefix(tokenLimit)
        return clipped.isEmpty ? nil : Array(clipped)
    }

    private static func clippedSenses(_ senses: [VocabSense]) -> [VocabSense] {
        var seen = Set<String>()
        var result: [VocabSense] = []
        for sense in senses {
            guard let text = optionalClipped(sense.text, limit: senseTextLimit) else { continue }
            guard seen.insert(text.lowercased()).inserted else { continue }
            result.append(VocabSense(
                text: text,
                sourceKey: optionalClipped(sense.sourceKey, limit: sourceKeyLimit)
            ))
            if result.count == VocabSenseList.maximumCount { break }
        }
        return result
    }
}
