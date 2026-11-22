//
//  SavedClipStore.swift
//  shizen
//
//  Clips the signed-in learner saved: `users/{uid}/savedClips/{clipId}`, so they
//  follow the account across devices. Each doc keeps the clip's list summary, so
//  the saved list shows and plays without fetching every clip again.
//

import FirebaseFirestore
import Foundation
import os

@MainActor
final class SavedClipStore {
    static let shared = SavedClipStore()
    static let didChangeNotification = Notification.Name("SavedClipStoreDidChange")

    private struct Entry {
        var summary: ClipSummary
        /// Nil while the save is still pending on the server: newest, so it sorts first.
        var savedAt: Date?
    }

    private var entries: [String: Entry] = [:]
    private var uid: String?
    private var listener: ListenerRegistration?
    private var authObserver: NSObjectProtocol?
    private var generation = 0
    private let logger = Logger(subsystem: "com.swappfunc.shizen", category: "SavedClips")

    private init() {
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

    /// Saving needs an account to save to.
    var isAvailable: Bool { uid != nil }

    /// Most recently saved first.
    var clips: [ClipSummary] {
        entries.values
            .sorted { ($0.savedAt ?? .distantFuture) > ($1.savedAt ?? .distantFuture) }
            .map(\.summary)
    }

    var count: Int { entries.count }

    func isSaved(_ clipID: String) -> Bool {
        entries[clipID] != nil
    }

    func save(_ summary: ClipSummary) {
        guard let uid, entries[summary.clipID] == nil else { return }
        guard let summaryData = Self.encode(summary) else {
            logger.error("Couldn't encode clip \(summary.clipID, privacy: .public) to save it")
            return
        }
        entries[summary.clipID] = Entry(summary: summary, savedAt: nil)
        notify()
        LearnerFirestore.commit([
            "clipId": summary.clipID,
            "savedAt": FieldValue.serverTimestamp(),
            "schemaVersion": 1,
            "summary": summaryData,
        ], to: LearnerFirestore.savedClips(uid: uid).document(summary.clipID), merge: false)
    }

    func unsave(clipID: String) {
        guard let uid, entries.removeValue(forKey: clipID) != nil else { return }
        notify()
        LearnerFirestore.savedClips(uid: uid).document(clipID).delete { [logger] error in
            guard let error else { return }
            let message = error.localizedDescription
            Task { @MainActor in
                logger.error("Unsave failed: \(message, privacy: .public)")
            }
        }
    }

    /// Where a save or unsave came from, for `clip_saved` / `clip_unsaved`.
    enum Origin: String {
        case menu
        case details
        /// Long-press in Profile → Saved Clips.
        case list
    }

    /// Saves or unsaves, as the learner asked from `origin`; returns whether the clip is now saved.
    @discardableResult
    func toggle(_ summary: ClipSummary, from origin: Origin) -> Bool {
        let wasSaved = isSaved(summary.clipID)
        if wasSaved {
            unsave(clipID: summary.clipID)
        } else {
            save(summary)
        }
        let nowSaved = isSaved(summary.clipID)
        if nowSaved != wasSaved {
            Analytics.track(nowSaved ? .clipSaved : .clipUnsaved, [
                "clip_id": summary.clipID,
                "from": origin.rawValue,
            ])
        }
        return nowSaved
    }

    // MARK: - Sync

    private func bind(uid: String?) {
        guard uid != self.uid || listener == nil else { return }
        generation += 1
        let generation = generation
        listener?.remove()
        listener = nil
        self.uid = uid
        if !entries.isEmpty {
            entries = [:]
            notify()
        }
        guard let uid else { return }
        // Pending writes are in the snapshot too (offline cache), so a save shows at once.
        listener = LearnerFirestore.savedClips(uid: uid).addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                if let error {
                    self.logger.error("Saved clips listen failed: \(error.localizedDescription, privacy: .public)")
                    return
                }
                self.apply(snapshot?.documents ?? [])
            }
        }
    }

    private func apply(_ documents: [QueryDocumentSnapshot]) {
        var next: [String: Entry] = [:]
        for document in documents {
            let data = document.data(with: .estimate)
            guard let summary = Self.decode(data["summary"]), summary.clipID == document.documentID else {
                continue
            }
            next[summary.clipID] = Entry(
                summary: summary,
                savedAt: LearnerSnapshotValue.date(data["savedAt"])
            )
        }
        let changed = Set(next.keys) != Set(entries.keys)
            || next.contains { id, entry in entries[id]?.savedAt != entry.savedAt }
        entries = next
        if changed { notify() }
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    // MARK: - Summary coding

    /// The summary as a Firestore map, with the same keys the clip API uses.
    private static func encode(_ summary: ClipSummary) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(summary) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func decode(_ value: Any?) -> ClipSummary? {
        guard let map = value as? [String: Any],
              JSONSerialization.isValidJSONObject(map),
              let data = try? JSONSerialization.data(withJSONObject: map) else { return nil }
        return try? JSONDecoder().decode(ClipSummary.self, from: data)
    }
}
