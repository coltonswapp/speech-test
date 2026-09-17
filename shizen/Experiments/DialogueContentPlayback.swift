//
//  DialogueContentPlayback.swift
//  shizen
//
//  Models and playback directors for Dialogue Replay (TikTok/Reels stage).
//  Formats share spoken-line records; directors sequence hook → bubbles → audio.
//

import CoreText
import UIKit

enum DialogueContentFormat: Int, CaseIterable, Hashable {
    case fullConversation
    case twoPassReplay
    case responseQuiz

    var title: String {
        switch self {
        case .fullConversation: return "Full conversation"
        case .twoPassReplay: return "Two-pass replay"
        case .responseQuiz: return "Response quiz"
        }
    }

    var subtitle: String {
        switch self {
        case .fullConversation: return "Selected lines, one by one, with audio"
        case .twoPassReplay: return "Japanese only, then faster with English"
        case .responseQuiz: return "Prompt + three replies, then the correct audio"
        }
    }

    var symbolName: String {
        switch self {
        case .fullConversation: return "text.bubble"
        case .twoPassReplay: return "arrow.2.squarepath"
        case .responseQuiz: return "checklist"
        }
    }

    var defaultHookText: String {
        switch self {
        case .fullConversation, .twoPassReplay:
            return "Can you understand this Japanese Dialogue?"
        case .responseQuiz:
            return "What's an appropriate response to this question?"
        }
    }

    /// Checklist of scenario lines, rather than prompt / correct / distractor roles.
    var selectsSpokenLines: Bool {
        switch self {
        case .fullConversation, .twoPassReplay: return true
        case .responseQuiz: return false
        }
    }
}

nonisolated struct DialogueContentSpokenLine: Hashable, Sendable {
    let id: String
    let scenarioID: String
    let scenarioTitle: String
    let spokenIndex: Int
    let speaker: String
    let speakerSide: DialogueSpeakerSide
    let japanese: String
    let english: String?
    let isStageLine: Bool

    var speakerPrefix: String {
        let trimmed = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "\(trimmed):"
    }
}

struct DialogueContentSession {
    let collection: DialogueScenarioCollection
    let scenario: DialogueScenarioCollection.Scenario
    var format: DialogueContentFormat
    /// Opening hook on the replay stage. Empty falls back to `format.defaultHookText`.
    var hookText: String
    /// Version 1: checked lines, already in original scenario order.
    var selectedLines: [DialogueContentSpokenLine]
    var prompt: DialogueContentSpokenLine?
    var correct: DialogueContentSpokenLine?
    var distractors: [DialogueContentSpokenLine]

    var example: GrammarExample { scenario.example }

    var spokenTextsForClip: [String] {
        GrammarExampleDialogueLines.lines(for: example)
    }

    var displayHookText: String {
        let trimmed = hookText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? format.defaultHookText : trimmed
    }

    func canPlayAudio(for line: DialogueContentSpokenLine) -> Bool {
        !line.isStageLine && line.scenarioID == scenario.id
    }

    var isReadyToRecord: Bool {
        switch format {
        case .fullConversation, .twoPassReplay:
            return selectedLines.contains { !$0.isStageLine }
        case .responseQuiz:
            return prompt != nil && correct != nil && distractors.count == 2
        }
    }

    /// Spoken lines the user checked, plus catalog stage directions when enabled.
    func playbackLines(includingStageLines: Bool) -> [DialogueContentSpokenLine] {
        let catalog = DialogueContentLineCatalog.spokenLines(in: scenario)
        let selectedIDs = Set(selectedLines.map(\.id))
        return catalog.filter { line in
            if line.isStageLine { return includingStageLines }
            return selectedIDs.contains(line.id)
        }
    }

    /// Shuffled 1–2–3 options with the correct reply mixed in.
    func shuffledResponseOptions() -> [DialogueContentSpokenLine] {
        guard let correct else { return distractors }
        return ([correct] + distractors).shuffled()
    }
}

enum DialogueContentLineCatalog {
    static func spokenLines(in scenario: DialogueScenarioCollection.Scenario) -> [DialogueContentSpokenLine] {
        let source = scenario.example.scenario?.lines
            ?? scenario.lines.map { tagged in
                GrammarScenarioLine(
                    speaker: tagged.speaker,
                    japanese: tagged.japanese,
                    romaji: tagged.romaji,
                    english: tagged.english,
                    grammarPointIDs: tagged.grammarPointIDs,
                    lineID: tagged.lineID
                )
            }

        var speakerSides: [String: DialogueSpeakerSide] = [:]
        var nextSide: DialogueSpeakerSide = .leading
        var spokenIndex = 0
        return source.enumerated().compactMap { offset, line -> DialogueContentSpokenLine? in
            if line.isInlineQuestion { return nil }
            if line.isSpokenLine {
                DialogueBubbleLayout.assignSpeakerSide(
                    for: line.speaker,
                    sides: &speakerSides,
                    nextSide: &nextSide
                )
            }
            let indexForAudio: Int
            if !line.isSpokenLine {
                indexForAudio = -1
            } else {
                indexForAudio = spokenIndex
                spokenIndex += 1
            }
            return DialogueContentSpokenLine(
                id: line.lineID ?? "\(scenario.id)#\(offset)",
                scenarioID: scenario.id,
                scenarioTitle: scenario.menuTitle,
                spokenIndex: indexForAudio,
                speaker: line.speaker,
                speakerSide: speakerSides[line.speaker] ?? .leading,
                japanese: line.japanese,
                english: line.english,
                isStageLine: line.isStageLine
            )
        }
    }

    static func spokenLinesElsewhere(
        in collection: DialogueScenarioCollection,
        excluding scenarioID: String
    ) -> [DialogueContentSpokenLine] {
        collection.scenarios
            .filter { $0.id != scenarioID }
            .flatMap { spokenLines(in: $0) }
            .filter { !$0.isStageLine }
    }
}

enum DialogueContentPlaybackTiming {
    static let recordStartDelay: TimeInterval = 2
    static let hookPreEnterPause: TimeInterval = 0.7
    static let hookEnterDuration: TimeInterval = 0.45
    static let hookHold: TimeInterval = 1.5
    static let hookFadeToGray: TimeInterval = 0.45
    static let hookExitDuration: TimeInterval = 0.42
    static let lineAnimationDuration: TimeInterval = 0.35
    static let interLinePause: TimeInterval = 0.28
    /// Pause after a stage direction so the scene can land before the next line.
    static let stageLineHold: TimeInterval = 1.25
    static let lastLineHold: TimeInterval = 0.8
    static let outroFadeToGray: TimeInterval = 0.5
    static let optionsGuessHold: TimeInterval = 1.8
    static let optionsRevealDuration: TimeInterval = 0.28
    static let twoPassBeatText = "Time to see what you understood!"
    static let twoPassFadeOut: TimeInterval = 0.4
    static let twoPassBeatPreEnterPause: TimeInterval = 0.2
    static let twoPassBeatHold: TimeInterval = 1.15
}

protocol DialogueContentDirectorDelegate: AnyObject {
    func directorDismissHook()
    /// Play one contiguous spoken run. Stage directions are held before the
    /// next run, matching live Dialogue's pause / focus / resume.
    func directorPlaySpokenRun(_ lines: [DialogueContentSpokenLine])
    func directorPresentLine(_ line: DialogueContentSpokenLine, parkingPrevious: Bool)
    func directorPlayLine(_ line: DialogueContentSpokenLine)
    func directorPresentOptions(_ options: [DialogueContentSpokenLine], correctID: String)
    func directorRevealCorrectOption()
    func directorPresentCorrectBubble(_ line: DialogueContentSpokenLine)
    func directorDidFinish()
}

/// Drives hook → karaoke lines → hold. Spoken runs play as one clip span;
/// stage directions pause between runs, matching live Dialogue.
final class DialogueContentFullConversationDirector {
    weak var delegate: DialogueContentDirectorDelegate?

    private let lines: [DialogueContentSpokenLine]
    private let stageLineHold: TimeInterval
    private var index = 0
    private var lastPresentedIndex: Int?
    private var generation = 0
    private var isStopped = false

    init(
        lines: [DialogueContentSpokenLine],
        stageLineHold: TimeInterval = DialogueContentPlaybackTiming.stageLineHold
    ) {
        self.lines = lines
        self.stageLineHold = stageLineHold
    }

    func start() {
        generation += 1
        isStopped = false
        index = 0
        lastPresentedIndex = nil
        continueFrom(0)
    }

    func stop() {
        isStopped = true
        generation += 1
    }

    func noteConversationLine(_ index: Int) {
        guard !isStopped, lines.indices.contains(index) else { return }
        let start = (lastPresentedIndex ?? -1) + 1
        guard start <= index else { return }
        for lineIndex in start...index {
            // Stage lines are presented on their own hold, before a spoken run.
            guard !lines[lineIndex].isStageLine else { continue }
            let parkingPrevious = lastPresentedIndex != nil
            lastPresentedIndex = lineIndex
            self.index = lineIndex
            delegate?.directorPresentLine(lines[lineIndex], parkingPrevious: parkingPrevious)
        }
    }

    func noteConversationAudioFinished() {
        guard !isStopped else { return }
        continueFrom((lastPresentedIndex ?? -1) + 1)
    }

    func noteHookDismissed() {
        guard !isStopped, !lines.isEmpty else {
            delegate?.directorDidFinish()
            return
        }
        continueFrom(0)
    }

    func noteLinePresented() {}

    func noteAudioFinished() {
        noteConversationAudioFinished()
    }

    /// Present any stage directions at `start`, hold on each, then play the
    /// next contiguous spoken run.
    private func continueFrom(_ start: Int) {
        guard !isStopped else { return }
        guard lines.indices.contains(start) else {
            finishAfterLastLineHold()
            return
        }
        if lines[start].isStageLine {
            presentStageLine(at: start) { [weak self] in
                guard let self, !self.isStopped else { return }
                self.playSpokenRun(startingAt: (self.lastPresentedIndex ?? start) + 1)
            }
            return
        }
        playSpokenRun(startingAt: start)
    }

    private func playSpokenRun(startingAt start: Int) {
        guard !isStopped else { return }
        guard lines.indices.contains(start) else {
            finishAfterLastLineHold()
            return
        }
        if lines[start].isStageLine {
            continueFrom(start)
            return
        }
        var end = start + 1
        while end < lines.count, !lines[end].isStageLine {
            end += 1
        }
        delegate?.directorPlaySpokenRun(Array(lines[start..<end]))
    }

    private func presentStageLine(at lineIndex: Int, then continueWork: @escaping () -> Void) {
        guard lines.indices.contains(lineIndex), lines[lineIndex].isStageLine else {
            continueWork()
            return
        }
        let parkingPrevious = lastPresentedIndex != nil
        lastPresentedIndex = lineIndex
        index = lineIndex
        delegate?.directorPresentLine(lines[lineIndex], parkingPrevious: parkingPrevious)
        wait(stageLineHold) { [weak self] in
            guard let self else { return }
            let next = lineIndex + 1
            if self.lines.indices.contains(next), self.lines[next].isStageLine {
                self.presentStageLine(at: next, then: continueWork)
            } else {
                continueWork()
            }
        }
    }

    private func finishAfterLastLineHold() {
        wait(DialogueContentPlaybackTiming.lastLineHold) { [weak self] in
            self?.delegate?.directorDidFinish()
        }
    }

    private func wait(_ duration: TimeInterval, then work: @escaping () -> Void) {
        let currentGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, !self.isStopped, self.generation == currentGeneration else { return }
            work()
        }
    }
}

/// Drives hook → prompt → options → reveal → correct audio.
final class DialogueContentResponseQuizDirector {
    weak var delegate: DialogueContentDirectorDelegate?

    private let prompt: DialogueContentSpokenLine
    private let correct: DialogueContentSpokenLine
    private let options: [DialogueContentSpokenLine]
    private var generation = 0
    private var isStopped = false
    private var skipHolds = false

    init(
        prompt: DialogueContentSpokenLine,
        correct: DialogueContentSpokenLine,
        options: [DialogueContentSpokenLine]
    ) {
        self.prompt = prompt
        self.correct = correct
        self.options = options
    }

    func start(skipHolds: Bool) {
        generation += 1
        isStopped = false
        optionsVisible = false
        self.skipHolds = skipHolds
        delegate?.directorPresentLine(prompt, parkingPrevious: false)
    }

    func stop() {
        isStopped = true
        generation += 1
    }

    func noteHookDismissed() {
        guard !isStopped else { return }
        delegate?.directorPresentLine(prompt, parkingPrevious: false)
    }

    func noteLinePresented() {
        guard !isStopped else { return }
        delegate?.directorPlayLine(prompt)
    }

    func noteAudioFinished() {
        guard !isStopped else { return }
        // First audio finish is the prompt; second is the correct reply.
        if optionsVisible {
            wait(DialogueContentPlaybackTiming.lastLineHold) { [weak self] in
                self?.delegate?.directorDidFinish()
            }
        } else {
            wait(DialogueContentPlaybackTiming.interLinePause) { [weak self] in
                guard let self else { return }
                self.optionsVisible = true
                self.delegate?.directorPresentOptions(self.options, correctID: self.correct.id)
            }
        }
    }

    func noteOptionsPresented() {
        guard !isStopped else { return }
        let hold = skipHolds ? 0.35 : DialogueContentPlaybackTiming.optionsGuessHold
        wait(hold) { [weak self] in
            self?.delegate?.directorRevealCorrectOption()
        }
    }

    func noteCorrectRevealed() {
        guard !isStopped else { return }
        wait(DialogueContentPlaybackTiming.optionsRevealDuration) { [weak self] in
            guard let self else { return }
            self.delegate?.directorPresentCorrectBubble(self.correct)
        }
    }

    func noteCorrectBubblePresented() {
        guard !isStopped else { return }
        delegate?.directorPlayLine(correct)
    }

    private var optionsVisible = false

    private func wait(_ duration: TimeInterval, then work: @escaping () -> Void) {
        let currentGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, !self.isStopped, self.generation == currentGeneration else { return }
            work()
        }
    }
}
