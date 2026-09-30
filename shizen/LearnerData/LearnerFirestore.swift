import FirebaseFirestore
import Foundation
import os

enum LearnerFirestore {
    static let progressDialogue = "dialogue"
    static let progressKanaHiragana = "kanaHiragana"
    static let progressKanaKatakana = "kanaKatakana"
    static let progressGrammar = "grammar"

    private static let logger = Logger(subsystem: "com.swappfunc.shizen", category: "LearnerFirestore")
    private static var didConfigure = false

    /// Call once, immediately after `FirebaseApp.configure()`, before any other Firestore use.
    static func configure() {
        guard !didConfigure else { return }
        didConfigure = true
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = settings
        deleteRetiredLocalProgress()
    }

    static func progressDocument(uid: String, id: String) -> DocumentReference {
        Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("progress")
            .document(id)
    }

    static func folders(uid: String) -> CollectionReference {
        Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("folders")
    }

    static func commit(_ data: [String: Any], to document: DocumentReference, merge: Bool = true) {
        document.setData(data, merge: merge) { error in
            guard let error else { return }
            let message = error.localizedDescription
            Task { @MainActor in
                logger.error("Learner write failed: \(message, privacy: .public)")
            }
        }
    }

    /// Field updates. Dotted string keys and `FieldPath` segments nest; `setData` does not.
    static func update(_ data: [AnyHashable: Any], on document: DocumentReference) {
        document.updateData(data) { error in
            guard let error else { return }
            let message = error.localizedDescription
            Task { @MainActor in
                logger.error("Learner update failed: \(message, privacy: .public)")
            }
        }
    }

    private static func deleteRetiredLocalProgress() {
        let fileManager = FileManager.default
        var urls: [URL] = []
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let shizen = appSupport.appendingPathComponent("shizen", isDirectory: true)
            for name in [
                "dialogue-progress.json",
                "grammar-mastery.json",
                "grammar-progress.json",
                "saved-vocabulary.json",
            ] {
                urls.append(shizen.appendingPathComponent(name))
            }
            let kana = appSupport.appendingPathComponent("KanaProgress", isDirectory: true)
            urls.append(kana.appendingPathComponent("progress.json"))
            urls.append(kana.appendingPathComponent("progress-katakana.json"))
        }
        if let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.Swappfunc.shizen") {
            let kana = group.appendingPathComponent("KanaProgress", isDirectory: true)
            urls.append(kana.appendingPathComponent("progress.json"))
            urls.append(kana.appendingPathComponent("progress-katakana.json"))
        }
        for url in urls where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }
}

nonisolated enum LearnerSnapshotValue {
    static func stringList(_ value: Any?) -> [String] {
        if let list = value as? [String] { return list }
        if let list = value as? [Any] { return list.compactMap { $0 as? String } }
        return []
    }

    static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    static func date(_ value: Any?) -> Date? {
        if let value = value as? Timestamp { return value.dateValue() }
        return nil
    }

    static func string(_ value: Any?) -> String? {
        value as? String
    }

    static func map(_ value: Any?) -> [String: Any] {
        value as? [String: Any] ?? [:]
    }
}

/// Holds listeners assigned after a store finishes initializing.
final class LearnerProgressCallbacks {
    var onSnapshot: ((DocumentSnapshot?) -> Void)?
    var onSignedOut: (() -> Void)?
}

/// Binds one progress document to the signed-in uid and sends field merges.
/// The empty shell is written once; later writes never replace the whole document.
@MainActor
final class LearnerProgressConnection {
    private enum State {
        case signedOut
        case unknown
        case absent
        case ready
    }

    private let documentID: String
    private let shell: [String: Any]
    private let onSnapshot: (DocumentSnapshot?) -> Void
    private let onSignedOut: () -> Void
    private let logger = Logger(subsystem: "com.swappfunc.shizen", category: "LearnerProgress")

    private var state: State = .signedOut
    private var listener: ListenerRegistration?
    private var authObserver: NSObjectProtocol?
    private var generation = 0
    private var didSendShell = false
    private var pending: [[String: Any]] = []
    private var document: DocumentReference?

    init(
        documentID: String,
        shell: [String: Any],
        onSnapshot: @escaping (DocumentSnapshot?) -> Void,
        onSignedOut: @escaping () -> Void
    ) {
        self.documentID = documentID
        self.shell = shell
        self.onSnapshot = onSnapshot
        self.onSignedOut = onSignedOut
    }

    func start() {
        bind(uid: AuthService.shared.userId)
        guard authObserver == nil else { return }
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

    func enqueue(_ fields: [String: Any]) {
        guard state != .signedOut else { return }
        guard !fields.isEmpty else { return }
        pending.append(fields)
        flush()
    }

    private func bind(uid: String?) {
        generation += 1
        let generation = generation
        listener?.remove()
        listener = nil
        document = nil
        didSendShell = false
        pending.removeAll()
        onSignedOut()

        guard let uid else {
            state = .signedOut
            return
        }

        state = .unknown
        let document = LearnerFirestore.progressDocument(uid: uid, id: documentID)
        self.document = document
        listener = document.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                if let error {
                    self.logger.error("Progress listen failed: \(error.localizedDescription, privacy: .public)")
                    return
                }
                self.handle(snapshot)
            }
        }
    }

    private func handle(_ snapshot: DocumentSnapshot?) {
        if let snapshot, snapshot.exists {
            state = .ready
            didSendShell = true
            onSnapshot(snapshot)
            flush()
            return
        }
        onSnapshot(nil)
        if !didSendShell {
            state = .absent
            flush()
        }
    }

    private func flush() {
        guard let document else { return }
        if state == .absent, !didSendShell {
            didSendShell = true
            LearnerFirestore.commit(shell, to: document)
            state = .ready
        }
        guard state == .ready else { return }
        let queued = pending
        pending.removeAll()
        for fields in queued {
            var payload = fields
            payload["schemaVersion"] = 1
            payload["updatedAt"] = FieldValue.serverTimestamp()
            LearnerFirestore.commit(payload, to: document)
        }
    }
}
