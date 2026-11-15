//
//  TutorOnboardingFlow.swift
//  shizen
//
//  Session and small shared types for the Hana steps.
//

import UIKit

/// Subclassed by NaturalOnboardingSession, which reuses the name, level, and pacing answers.
class TutorOnboardingSession {
    var name = ""
    var level: TutorLevel = .brandNew
    var minutesPerDay = 10

    /// Whether chats use the flower mascot instead of the 🌸 avatar. On for listen-first v2.
    var showsMascot: Bool { false }

    /// A Hana that floats above every screen and glides between them. Listen-first v2 only.
    var hanaStage: OnboardingHanaStage? { nil }

    /// The hand-written breakdown a right swipe opens for a Japanese line. None by default.
    func breakdown(for japanese: String) -> SentenceScrubScript? { nil }

    /// When true, every Japanese line shown must have a breakdown; a missing one asserts.
    var dissectsEveryLine: Bool { false }

    var displayName: String {
        name.isEmpty ? "friend" : name
    }

    func personalize(_ text: String) -> String {
        text.replacingOccurrences(of: "{name}", with: displayName)
    }
}

/// Cancellable timers for scripted beats, so popping a step never fires stale animations.
/// `fastForward()` runs every waiting beat immediately (tap-to-advance); beats those schedule wait as usual.
final class TutorTimeline {

    private struct Beat {
        let task: Task<Void, Never>
        let work: @MainActor () -> Void
    }

    private var tasks: [Task<Void, Never>] = []
    private var beats: [Int: Beat] = [:]
    private var nextBeatID = 0
    /// Bumps on every fast-forward; long-running work (typing, counters) jumps to its end state when it changes.
    private(set) var skipGeneration = 0

    var hasWaitingBeats: Bool { !beats.isEmpty }

    func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        let id = nextBeatID
        nextBeatID += 1
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.fire(id)
        }
        beats[id] = Beat(task: task, work: work)
    }

    func run(_ operation: @escaping @MainActor () async -> Void) {
        tasks.append(Task { @MainActor in await operation() })
    }

    /// Fires every waiting beat now, in the order they were scheduled.
    func fastForward() {
        skipGeneration += 1
        for id in beats.keys.sorted() {
            guard let beat = beats.removeValue(forKey: id) else { continue }
            beat.task.cancel()
            beat.work()
        }
    }

    func cancelAll() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        beats.values.forEach { $0.task.cancel() }
        beats.removeAll()
    }

    private func fire(_ id: Int) {
        beats.removeValue(forKey: id)?.work()
    }
}

// MARK: - Content

struct TutorLine {
    let japanese: String
    let english: String

    init(_ japanese: String, _ english: String) {
        self.japanese = japanese
        self.english = english
    }
}

enum TutorLevel: Int, CaseIterable {
    case brandNew
    case kana
    case someKanji
    case conversational

    var title: String {
        switch self {
        case .brandNew: return "Brand new"
        case .kana: return "I know kana"
        case .someKanji: return "Some kanji"
        case .conversational: return "I can hold a chat"
        }
    }

}
