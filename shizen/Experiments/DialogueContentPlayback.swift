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
            if line.isSpokenLine, speakerSides[line.speaker] == nil {
                speakerSides[line.speaker] = nextSide
                nextSide = nextSide == .leading ? .trailing : .leading
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
    static let stageLineHold: TimeInterval = 1.15
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
    private var index = 0
    private var lastPresentedIndex: Int?
    private var generation = 0
    private var isStopped = false

    init(lines: [DialogueContentSpokenLine]) {
        self.lines = lines
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
        wait(DialogueContentPlaybackTiming.stageLineHold) { [weak self] in
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

enum DialogueContentLineWrap {
    private static let wordJoiner = "\u{2060}"
    private static let wordJoinerCharacter: Character = "\u{2060}"
    private static let gluePrefixCount = 4
    /// Japanese and ASCII stops/commas, including fullwidth and halfwidth forms.
    private static let hangingPunctuation: Set<Unicode.Scalar> = [
        "\u{3002}", // ideographic full stop 。
        "\u{FF0E}", // fullwidth full stop ．
        "\u{002E}", // ascii full stop .
        "\u{FF61}", // halfwidth ideographic full stop ｡
        "\u{3001}", // ideographic comma 、
        "\u{FF0C}", // fullwidth comma ，
        "\u{002C}", // ascii comma ,
        "\u{FF64}", // halfwidth ideographic comma ､
        "\u{FF1F}", // fullwidth question ？
        "\u{003F}", // ascii question ?
        "\u{FF01}", // fullwidth bang ！
        "\u{0021}", // ascii bang !
        "\u{2026}", // ellipsis …
        "\u{22EF}", // midline ellipsis ⋯
        "\u{2025}", // two-dot leader ‥
    ]

    static func applyOrphanGlue(to label: FuriganaTranscriptLabel) {
        guard let attributed = label.attributedText, attributed.length > 0 else { return }
        label.attributedText = preparingForLayout(attributed)
        label.lineBreakMode = .byWordWrapping
        if #available(iOS 14.0, *) {
            label.lineBreakStrategy = .pushOut
        }
    }

    /// Word-joiners plus word-wrapping, matching what the label draws.
    static func preparingForLayout(_ attributed: NSAttributedString) -> NSAttributedString {
        let glued = gluingOrphanPunctuation(in: attributed)
        let mutable = NSMutableAttributedString(attributedString: glued)
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttribute(.paragraphStyle, in: fullRange, options: []) { value, range, _ in
            let style = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle)
                ?? NSMutableParagraphStyle()
            // Char-wrapping ignores Unicode close-punctuation rules and will
            // park `。` / `、` / `.` on their own line. Word-wrapping plus
            // joiners keeps the last few characters with the mark.
            style.lineBreakMode = .byWordWrapping
            style.hyphenationFactor = 0
            mutable.addAttribute(.paragraphStyle, value: style, range: range)
        }
        return mutable
    }

    /// Inserts word joiners so the last few characters plus a hanging mark stay on one line.
    static func gluingOrphanPunctuation(in attributed: NSAttributedString) -> NSAttributedString {
        let chars = Array(attributed.string)
        guard chars.count > 1 else { return attributed }

        var glueAfter = Set<Int>()
        var index = 0
        while index < chars.count {
            guard isHangingPunctuation(chars[index]) else {
                index += 1
                continue
            }
            var runEnd = index + 1
            while runEnd < chars.count, isHangingPunctuation(chars[runEnd]) {
                runEnd += 1
            }
            let start = max(0, index - gluePrefixCount)
            if start < runEnd {
                for glueIndex in start..<(runEnd - 1) {
                    // Already glued from a previous pass.
                    if chars[glueIndex] == wordJoinerCharacter { continue }
                    if chars[glueIndex + 1] == wordJoinerCharacter { continue }
                    glueAfter.insert(glueIndex)
                }
            }
            index = runEnd
        }
        guard !glueAfter.isEmpty else { return attributed }

        var utf16AfterChar: [Int] = Array(repeating: 0, count: chars.count)
        var utf16 = 0
        for (charIndex, char) in chars.enumerated() {
            utf16 += String(char).utf16.count
            utf16AfterChar[charIndex] = utf16
        }

        let rubyKey = NSAttributedString.Key(kCTRubyAnnotationAttributeName as String)
        let mutable = NSMutableAttributedString(attributedString: attributed)
        for location in glueAfter.map({ utf16AfterChar[$0] }).sorted(by: >) {
            guard location > 0, location <= mutable.length else { continue }
            let previousHasRuby =
                mutable.attribute(rubyKey, at: location - 1, effectiveRange: nil) != nil
            let nextHasRuby = location < mutable.length
                && mutable.attribute(rubyKey, at: location, effectiveRange: nil) != nil
            if previousHasRuby || nextHasRuby { continue }

            var attrs = mutable.attributes(at: location - 1, effectiveRange: nil)
            attrs.removeValue(forKey: rubyKey)
            mutable.insert(NSAttributedString(string: wordJoiner, attributes: attrs), at: location)
        }
        return mutable
    }

    private static func isHangingPunctuation(_ character: Character) -> Bool {
        character.unicodeScalars.contains(where: { hangingPunctuation.contains($0) })
    }
}
