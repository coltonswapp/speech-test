//
//  KanaLessonCoordinator.swift
//  shizen
//
//  Builds and presents row lesson, review, and SRS review sessions.
//

import UIKit

enum KanaSessionKind: Equatable {
    case lesson
    case rowReview
    case srsReview
    case customReview(selectedKana: Set<String>, script: KanaScript)
}

protocol KanaLessonSessionDelegate: AnyObject {
    func kanaLessonSessionDidFinish(kind: KanaSessionKind, row: KanaRow?, metrics: KanaLessonSessionMetrics)
    func kanaLessonSessionDidFail(kind: KanaSessionKind, row: KanaRow?, metrics: KanaLessonSessionMetrics)
    func kanaLessonSessionDidCancel(kind: KanaSessionKind, row: KanaRow?)
}

final class KanaLessonCoordinator: NSObject {

    weak var delegate: KanaLessonSessionDelegate?

    private let kind: KanaSessionKind
    private let row: KanaRow?
    private let progressStore: KanaProgressStore
    private let sessionTracker = KanaLessonSessionTracker()
    private var progressiveCoordinator: ProgressiveContainerCoordinator?
    private var didPresentSummary = false
    private var sessionRecentCorrectGlyphs: [String] = []

    init(
        kind: KanaSessionKind,
        row: KanaRow?,
        progressStore: KanaProgressStore = .shared
    ) {
        self.kind = kind
        self.row = row
        self.progressStore = progressStore
        super.init()
    }

    func makeCoordinator() -> ProgressiveContainerCoordinator {
        let steps = buildSteps()
        let coordinator = ProgressiveContainerCoordinator(steps: steps)
        coordinator.delegate = self
        wireCallbacks(into: steps)
        progressiveCoordinator = coordinator
        return coordinator
    }

    func present(from viewController: UIViewController) {
        let coordinator = makeCoordinator()
        let container = coordinator.start()
        coordinator.setLivesVisible(true)
        coordinator.updateLives(sessionTracker.metrics.livesRemaining)
        container.modalPresentationStyle = .fullScreen
        viewController.present(container, animated: true)
    }

    // MARK: - Step building

    private func buildSteps() -> [UIViewController] {
        switch kind {
        case .lesson:
            guard let row else { return [] }
            return buildLessonSteps(for: row)
        case .rowReview:
            guard let row else { return [] }
            return buildReviewSteps(for: row)
        case .srsReview:
            return buildSRSReviewSteps()
        case .customReview(let selectedKana, let script):
            return buildCustomReviewSteps(selectedKana: selectedKana, script: script)
        }
    }

    private func buildCustomReviewSteps(selectedKana: Set<String>, script: KanaScript) -> [UIViewController] {
        let content = KanaLessonContentBuilder.customReviewContent(
            selectedKana: selectedKana,
            script: script,
            unlockedGlyphs: progressStore.unlockedGlyphs
        )
        let steps = makeMixedBatchSteps(from: content.mixItems, script: script)
        return reindex(steps)
    }

    private func buildLessonSteps(for row: KanaRow) -> [UIViewController] {
        var steps: [UIViewController] = []
        var lessonUnlocked = progressStore.unlockedGlyphs
        var usedSpellingWords: Set<String> = []

        let batches = KanaLessonContentBuilder.glyphBatches(for: row)
        let kanaPairMatchRound = KanaLessonContentBuilder.kanaPairMatchRound(for: row)
        for (batchIndex, batch) in batches.enumerated() {
            let shuffledBatch = batch.shuffled()
            let batchGlyphs = Set(batch.map(\.kana))
            var deferredDrills: [KanaLessonDrillItem] = []

            for glyph in shuffledBatch {
                let isNew = !progressStore.hasBeenIntroduced(to: glyph.kana)
                if isNew {
                    let discovery = KanaLessonContentBuilder.discoveryRound(for: glyph, in: row)
                    steps.append(
                        KanaDiscoveryStepViewController(
                            round: discovery,
                            presentationMode: .introduction,
                            script: row.script
                        )
                    )
                    steps.append(
                        KanaVocabAssociationStepViewController(
                            glyph: glyph,
                            script: row.script
                        )
                    )
                }

                let split = KanaLessonContentBuilder.splitBatchDrills(
                    for: glyph,
                    distractorPool: row.glyphs,
                    includeImmediate: isNew
                )
                if let immediate = split.immediate {
                    steps.append(contentsOf: makeDrillSteps(from: [immediate]))
                }
                deferredDrills.append(contentsOf: split.deferred)
            }

            lessonUnlocked.formUnion(batchGlyphs)
            let batchSpelling = KanaLessonContentBuilder.spellingItems(
                for: row,
                unlockedGlyphs: lessonUnlocked,
                excludingWords: usedSpellingWords,
                romajiCount: 2,
                listenSpellCount: 1,
                requiredOverlapGlyphs: batchGlyphs,
                minimumOverlapCount: 1,
                preferredSyllableRanges: KanaLessonContentBuilder.batchSpellingSyllableRanges(
                    batchIndex: batchIndex,
                    batchCount: batches.count
                ),
                bias: .currentBatch
            )
            usedSpellingWords.formUnion(batchSpelling.map { $0.word.hiragana })

            let mixedBatch = KanaLessonContentBuilder.shuffledBatchMix(
                drills: deferredDrills,
                spelling: batchSpelling,
                pairMatches: pairMatchItems(
                    batchIndex: batchIndex,
                    batchCount: batches.count,
                    kanaRound: kanaPairMatchRound,
                    wordRound: KanaLessonContentBuilder.wordPairMatchRound(
                        for: row,
                        unlockedGlyphs: lessonUnlocked
                    ),
                    usedSpellingWords: &usedSpellingWords
                )
            )
            steps.append(contentsOf: makeMixedBatchSteps(from: mixedBatch, script: row.script))
        }

        if KanaLessonContentBuilder.shouldIncludeRecallSpelling(for: row, unlockedGlyphs: lessonUnlocked) {
            let recallSpelling = KanaLessonContentBuilder.spellingItems(
                for: row,
                unlockedGlyphs: lessonUnlocked,
                excludingWords: usedSpellingWords,
                romajiCount: 2,
                listenSpellCount: 1,
                requiredOverlapGlyphs: row.kanaSet,
                minimumOverlapCount: 1,
                preferredSyllableRanges: KanaLessonContentBuilder.recallSpellingSyllableRanges(),
                bias: .priorLearning
            )
            steps.append(contentsOf: makeSpellingSteps(from: recallSpelling, script: row.script))
        }

        return reindex(steps)
    }

    private func buildReviewSteps(for row: KanaRow) -> [UIViewController] {
        var steps: [UIViewController] = []
        var usedSpellingWords: Set<String> = []
        let reviewGlyphs = progressStore.unlockedGlyphs.union(row.kanaSet)

        let batches = KanaLessonContentBuilder.glyphBatches(for: row)
        let kanaPairMatchRound = KanaLessonContentBuilder.kanaPairMatchRound(for: row)
        for (batchIndex, batch) in batches.enumerated() {
            let shuffledBatch = batch.shuffled()
            let batchGlyphs = Set(batch.map(\.kana))
            var deferredDrills: [KanaLessonDrillItem] = []

            for glyph in shuffledBatch {
                let split = KanaLessonContentBuilder.splitReviewDrills(
                    for: glyph,
                    in: row,
                    includeImmediate: true
                )
                if let immediate = split.immediate {
                    steps.append(contentsOf: makeDrillSteps(from: [immediate]))
                }
                deferredDrills.append(contentsOf: split.deferred)
            }

            let batchSpelling = KanaLessonContentBuilder.spellingItems(
                for: row,
                unlockedGlyphs: reviewGlyphs,
                excludingWords: usedSpellingWords,
                romajiCount: 4,
                listenSpellCount: 3,
                requiredOverlapGlyphs: batchGlyphs,
                minimumOverlapCount: 1,
                preferredSyllableRanges: KanaLessonContentBuilder.reviewBatchSpellingSyllableRanges(
                    batchIndex: batchIndex,
                    batchCount: batches.count
                ),
                bias: .currentBatch
            )
            usedSpellingWords.formUnion(batchSpelling.map { $0.word.hiragana })

            let mixedBatch = KanaLessonContentBuilder.shuffledBatchMix(
                drills: deferredDrills,
                spelling: batchSpelling,
                pairMatches: pairMatchItems(
                    batchIndex: batchIndex,
                    batchCount: batches.count,
                    kanaRound: kanaPairMatchRound,
                    wordRound: KanaLessonContentBuilder.wordPairMatchRound(
                        for: row,
                        unlockedGlyphs: reviewGlyphs
                    ),
                    usedSpellingWords: &usedSpellingWords
                )
            )
            steps.append(contentsOf: makeMixedBatchSteps(from: mixedBatch, script: row.script))
        }

        if KanaLessonContentBuilder.shouldIncludeRecallSpelling(for: row, unlockedGlyphs: reviewGlyphs) {
            let recallSpelling = KanaLessonContentBuilder.spellingItems(
                for: row,
                unlockedGlyphs: reviewGlyphs,
                excludingWords: usedSpellingWords,
                romajiCount: 4,
                listenSpellCount: 3,
                requiredOverlapGlyphs: row.kanaSet,
                minimumOverlapCount: 1,
                preferredSyllableRanges: KanaLessonContentBuilder.recallSpellingSyllableRanges(),
                bias: .priorLearning
            )
            steps.append(contentsOf: makeSpellingSteps(from: recallSpelling, script: row.script))
        }

        return reindex(steps)
    }

    private func buildSRSReviewSteps() -> [UIViewController] {
        let due = progressStore.dueGlyphs()
        let rounds = KanaLessonContentBuilder.srsReviewRounds(for: due)
        return reindex(makeSoundMatchSteps(from: rounds))
    }

    private func pairMatchItems(
        batchIndex: Int,
        batchCount: Int,
        kanaRound: KanaPairMatchRound,
        wordRound: KanaPairMatchRound,
        usedSpellingWords: inout Set<String>
    ) -> [(round: KanaPairMatchRound, kind: KanaPairMatchStepKind)] {
        var items: [(round: KanaPairMatchRound, kind: KanaPairMatchStepKind)] = []
        if batchIndex == 0 {
            items.append((kanaRound, .kanaGlyphs))
        }
        if batchIndex == batchCount - 1 {
            usedSpellingWords.formUnion(wordRound.pairs.compactMap(\.spellingWordKey))
            items.append((wordRound, .words))
        }
        return items
    }

    private func makeSoundMatchSteps(from rounds: [KanaSoundMatchRound]) -> [UIViewController] {
        let total = rounds.count
        return rounds.enumerated().map { index, round in
            KanaSoundMatchExperimentViewController(round: round, stepIndex: index, totalSteps: total)
        }
    }

    private func makeListenIdentifySteps(from rounds: [KanaListenIdentifyRound]) -> [UIViewController] {
        let total = rounds.count
        return rounds.enumerated().map { index, round in
            KanaListenIdentifyStepViewController(round: round, stepIndex: index, totalSteps: total)
        }
    }

    private func makeDrillSteps(from items: [KanaLessonDrillItem]) -> [UIViewController] {
        items.map { item in
            switch item {
            case .recognitionMC(let round):
                KanaDiscoveryStepViewController(
                    round: round,
                    presentationMode: .review,
                    script: round.glyph.script
                )
            case .soundMatch(let round):
                KanaSoundMatchExperimentViewController(round: round, stepIndex: 0, totalSteps: 1)
            case .listenIdentify(let round):
                KanaListenIdentifyStepViewController(round: round, stepIndex: 0, totalSteps: 1)
            }
        }
    }

    private func makeMixedBatchSteps(
        from items: [KanaLessonBatchMixItem],
        script: KanaScript
    ) -> [UIViewController] {
        items.flatMap { item -> [UIViewController] in
            switch item {
            case .drill(let drill):
                makeDrillSteps(from: [drill])
            case .spelling(let spelling):
                makeSpellingSteps(from: [spelling], script: script)
            case .pairMatch(let round, let kind):
                [KanaPairMatchStepViewController(round: round, kind: kind)]
            }
        }
    }

    private func makeSpellingSteps(from items: [KanaLessonSpellingItem], script: KanaScript) -> [UIViewController] {
        let total = items.count
        return items.enumerated().map { index, item in
            switch item.promptStyle {
            case .romaji:
                KanaSpellingViewController(
                    word: item.word,
                    wordIndex: index,
                    totalSteps: total,
                    script: script
                )
            case .audio:
                KanaListenSpellingViewController(
                    word: item.word,
                    wordIndex: index,
                    totalSteps: total,
                    script: script
                )
            }
        }
    }

    private func reindex(_ steps: [UIViewController]) -> [UIViewController] {
        let total = steps.count
        for (index, step) in steps.enumerated() {
            if let discovery = step as? KanaDiscoveryStepViewController {
                discovery.applyStepIndex(index, totalSteps: total)
            } else if let listen = step as? KanaListenIdentifyStepViewController {
                listen.applyStepIndex(index, totalSteps: total)
            } else if let match = step as? KanaSoundMatchExperimentViewController {
                match.applyStepIndex(index, totalSteps: total)
            } else if let spelling = step as? KanaSpellingViewController {
                spelling.applyStepIndex(index, totalSteps: total)
            } else if let vocab = step as? KanaVocabAssociationStepViewController {
                vocab.applyStepIndex(index, totalSteps: total)
            } else if let pairMatch = step as? KanaPairMatchStepViewController {
                pairMatch.applyStepIndex(index, totalSteps: total)
            }
        }
        return steps
    }

    private func wireCallbacks(into steps: [UIViewController]) {
        for step in steps {
            if let discovery = step as? KanaDiscoveryStepViewController {
                if discovery.recordsExposureOnAppear {
                    discovery.onDidExpose = { [weak self] kana in
                        self?.progressStore.recordExposure(for: kana)
                    }
                }
                discovery.onStepResult = { [weak self] kana, correct in
                    self?.handleStepResult(kana: kana, correct: correct)
                }
            } else if let listen = step as? KanaListenIdentifyStepViewController {
                listen.onStepResult = { [weak self] kana, correct in
                    self?.handleStepResult(kana: kana, correct: correct)
                }
            } else if let match = step as? KanaSoundMatchExperimentViewController {
                match.onStepResult = { [weak self] kana, correct in
                    self?.handleStepResult(kana: kana, correct: correct)
                }
            } else if let spelling = step as? KanaSpellingViewController {
                spelling.onStepResult = { [weak self] syllables, correct in
                    guard let self else { return }
                    guard !self.didPresentSummary else { return }
                    let failedOut = self.handleSessionAnswer(correct: correct)
                    if failedOut || self.sessionTracker.isActive {
                        for kana in Set(syllables) {
                            self.recordStepResult(kana: kana, correct: correct)
                            if correct {
                                self.recordSessionCorrectGlyph(kana)
                            }
                        }
                    }
                    if failedOut {
                        self.presentSummary(outcome: .failed)
                    }
                }
            } else if let pairMatch = step as? KanaPairMatchStepViewController {
                pairMatch.onStepComplete = { [weak self] progressKana in
                    guard let self else { return }
                    guard !self.didPresentSummary else { return }
                    let failedOut = self.handleSessionAnswer(correct: true)
                    if failedOut || self.sessionTracker.isActive {
                        for kana in Set(progressKana) {
                            self.recordStepResult(kana: kana, correct: true)
                            self.recordSessionCorrectGlyph(kana)
                        }
                    }
                    if failedOut {
                        self.presentSummary(outcome: .failed)
                    }
                }
            }
        }
    }

    private func handleStepResult(kana: String, correct: Bool) {
        guard !didPresentSummary else { return }
        let failedOut = handleSessionAnswer(correct: correct)
        if failedOut || sessionTracker.isActive {
            recordStepResult(kana: kana, correct: correct)
            if correct {
                recordSessionCorrectGlyph(kana)
            }
        }
        if failedOut {
            presentSummary(outcome: .failed)
        }
    }

    private func recordSessionCorrectGlyph(_ kana: String) {
        sessionRecentCorrectGlyphs.removeAll { $0 == kana }
        sessionRecentCorrectGlyphs.append(kana)
    }

    private func encouragementGlyphs() -> [(kana: String, romaji: String)] {
        let script = lessonScript
        var pairs: [(kana: String, romaji: String)] = sessionRecentCorrectGlyphs.suffix(2).map { kana in
            let romaji = KanaCurriculum.glyph(kana: kana, script: script)?.romaji
                ?? HiraganaRomaji.romanize(kana)
            return (kana, romaji)
        }
        if pairs.isEmpty, let first = row?.glyphs.first {
            pairs = [(first.kana, first.romaji)]
        }
        if pairs.count == 1 {
            pairs.append(pairs[0])
        }
        return pairs
    }

    private var lessonScript: KanaScript {
        if case .customReview(_, let script) = kind { return script }
        return row?.script ?? .hiragana
    }

    @discardableResult
    private func handleSessionAnswer(correct: Bool) -> Bool {
        let failedOut = sessionTracker.recordAnswer(
            correct: correct,
            encouragementEnabled: kind == .lesson
        )
        progressiveCoordinator?.updateLives(sessionTracker.metrics.livesRemaining)
        if sessionTracker.shouldPlayEncouragement {
            presentEncouragementNotchDrop()
        } else if !correct {
            presentLifeLostNotchDrop()
        }
        return failedOut
    }

    private func presentEncouragementNotchDrop() {
        guard kind == .lesson else { return }
        let names = MeteredAudioPlayer.encouragementClipNames
        guard !names.isEmpty else { return }
        guard let comboStreak = sessionTracker.consumePendingEncouragementStreak() else { return }
        let clipIndex = Int.random(in: 0 ..< names.count)
        let payload = PendingEncouragement(
            clipIndex: clipIndex,
            comboStreak: comboStreak,
            glyphs: encouragementGlyphs(),
            praisePhrase: KanaLessonEncouragementPhraseBank.randomPhrase()
        )
        progressiveCoordinator?.queueEncouragement(payload)
    }

    private func presentLifeLostNotchDrop() {
        guard kind == .lesson, sessionTracker.isActive else { return }
        progressiveCoordinator?.presentNotchDrop(.lifeLost(
            remaining: sessionTracker.metrics.livesRemaining
        ))
    }

    private func recordStepResult(kana: String, correct: Bool) {
        switch kind {
        case .srsReview:
            if correct {
                progressStore.recordSuccess(for: kana)
            } else {
                progressStore.recordFailure(for: kana)
            }
        case .lesson, .rowReview, .customReview:
            if correct {
                progressStore.recordPracticeSuccess(for: kana)
            } else {
                progressStore.recordPracticeFailure(for: kana)
            }
        }
    }

    private func handleFinish() {
        switch kind {
        case .lesson:
            if let row {
                progressStore.markLessonCompleted(for: row)
            }
        case .rowReview:
            if let row {
                progressStore.markReviewCompleted(for: row)
            }
        case .srsReview, .customReview:
            break
        }
    }

    private func presentSummary(outcome: KanaLessonSummaryOutcome) {
        guard !didPresentSummary, let progressiveCoordinator else { return }
        didPresentSummary = true
        sessionTracker.endSession()

        let summary = KanaLessonSummaryStepViewController(
            kind: kind,
            outcome: outcome,
            metrics: sessionTracker.metrics.snapshot()
        )
        summary.onContinue = { [weak self] in
            self?.completeSummary(outcome: outcome)
        }
        progressiveCoordinator.pushPostSessionStep(summary)
    }

    private func completeSummary(outcome: KanaLessonSummaryOutcome) {
        let metrics = sessionTracker.metrics.snapshot()
        progressiveCoordinator?.delegate = nil
        progressiveCoordinator = nil

        switch outcome {
        case .completed:
            handleFinish()
            delegate?.kanaLessonSessionDidFinish(kind: kind, row: row, metrics: metrics)
        case .failed:
            delegate?.kanaLessonSessionDidFail(kind: kind, row: row, metrics: metrics)
        }
    }
}

extension KanaLessonCoordinator: ProgressiveContainerCoordinatorDelegate {
    func progressiveContainerCoordinatorDidFinish(_ coordinator: ProgressiveContainerCoordinator) {
        presentSummary(outcome: .completed)
    }

    func progressiveContainerCoordinatorDidCancel(_ coordinator: ProgressiveContainerCoordinator) {
        coordinator.delegate = nil
        progressiveCoordinator = nil
        sessionTracker.endSession()
        delegate?.kanaLessonSessionDidCancel(kind: kind, row: row)
    }
}
