//
//  KanaLessonContentBuilder.swift
//  shizen
//
//  Generates row-scoped lesson phases: discovery, recall, listen-identify, production, spelling, and listen-spell.
//

import Foundation

enum KanaLessonDrillItem {
    case recognitionMC(KanaDiscoveryRound)
    case soundMatch(KanaSoundMatchRound)
    case listenIdentify(KanaListenIdentifyRound)
}

enum KanaLessonBatchMixItem {
    case drill(KanaLessonDrillItem)
    case spelling(KanaLessonSpellingItem)
    case pairMatch(KanaPairMatchRound, KanaPairMatchStepKind)
}

extension KanaLessonDrillItem {
    var primaryKana: String {
        switch self {
        case .recognitionMC(let round):
            round.glyph.kana
        case .soundMatch(let round):
            round.primaryKana
        case .listenIdentify(let round):
            round.targetKana
        }
    }
}

enum KanaLessonContentBuilder {

    // MARK: - Batching

    static func glyphBatches(for row: KanaRow) -> [[KanaGlyph]] {
        let batchSize = row.glyphs.count >= 5 ? 3 : row.glyphs.count
        return row.glyphs.chunked(into: batchSize)
    }

    // MARK: - Discovery

    static func discoveryRound(for glyph: KanaGlyph, in row: KanaRow) -> KanaDiscoveryRound {
        let matchRound = makeRound(glyph: glyph, row: row, direction: .kanaToRomaji)
        return KanaDiscoveryRound(
            glyph: glyph,
            correctChoice: matchRound.correctChoice,
            choices: matchRound.choices
        )
    }

    // MARK: - Sound match phases

    static func recallRounds(
        for glyphs: [KanaGlyph],
        distractorPool: [KanaGlyph],
        shuffle: Bool = false
    ) -> [KanaSoundMatchRound] {
        var rounds = glyphs.map {
            makeRound(glyph: $0, distractorPool: distractorPool, direction: .kanaToRomaji)
        }
        if shuffle {
            rounds.shuffle()
        }
        return rounds
    }

    static func productionRounds(
        for glyphs: [KanaGlyph],
        distractorPool: [KanaGlyph],
        shuffle: Bool = true
    ) -> [KanaSoundMatchRound] {
        var rounds = glyphs.map {
            makeRound(glyph: $0, distractorPool: distractorPool, direction: .romajiToKana)
        }
        if shuffle {
            rounds.shuffle()
        }
        return rounds
    }

    static func listenIdentifyRounds(
        for glyphs: [KanaGlyph],
        distractorPool: [KanaGlyph],
        shuffle: Bool = false
    ) -> [KanaListenIdentifyRound] {
        var rounds = glyphs.map {
            makeListenIdentifyRound(glyph: $0, distractorPool: distractorPool)
        }
        if shuffle {
            rounds.shuffle()
        }
        return rounds
    }

    /// Recall, listen-identify, and production drills for a batch, shuffled together.
    /// Call only after every glyph in the batch has had its discovery step.
    static func shuffledBatchDrills(
        for glyphs: [KanaGlyph],
        distractorPool: [KanaGlyph]
    ) -> [KanaLessonDrillItem] {
        glyphs.flatMap { glyph in
            splitBatchDrills(for: glyph, distractorPool: distractorPool, includeImmediate: false).deferred
        }.shuffled()
    }

    /// One immediate drill plus the remaining two deferred drills for a glyph.
    static func splitBatchDrills(
        for glyph: KanaGlyph,
        distractorPool: [KanaGlyph],
        includeImmediate: Bool
    ) -> (immediate: KanaLessonDrillItem?, deferred: [KanaLessonDrillItem]) {
        let drills = [
            KanaLessonDrillItem.soundMatch(
                makeRound(glyph: glyph, distractorPool: distractorPool, direction: .kanaToRomaji)
            ),
            .listenIdentify(makeListenIdentifyRound(glyph: glyph, distractorPool: distractorPool)),
            .soundMatch(
                makeRound(glyph: glyph, distractorPool: distractorPool, direction: .romajiToKana)
            ),
        ].shuffled()

        guard includeImmediate else {
            return (nil, drills)
        }
        return (drills[0], Array(drills.dropFirst()))
    }

    /// Shuffles deferred drills (avoiding long same-glyph streaks) with spelling steps,
    /// then inserts pair-match boards at spaced positions (never adjacent).
    static func shuffledBatchMix(
        drills: [KanaLessonDrillItem],
        spelling: [KanaLessonSpellingItem],
        pairMatches: [(round: KanaPairMatchRound, kind: KanaPairMatchStepKind)] = []
    ) -> [KanaLessonBatchMixItem] {
        let orderedDrills = shuffleDrillsAvoidingClusters(drills)
        var pool: [KanaLessonBatchMixItem] =
            orderedDrills.map { .drill($0) } + spelling.map { .spelling($0) }
        pool.shuffle()
        return insertSpacedPairMatches(into: pool, pairMatches: pairMatches)
    }

    private static func insertSpacedPairMatches(
        into mix: [KanaLessonBatchMixItem],
        pairMatches: [(round: KanaPairMatchRound, kind: KanaPairMatchStepKind)],
        minimumGap: Int = 2
    ) -> [KanaLessonBatchMixItem] {
        guard !pairMatches.isEmpty else { return mix }

        var result = mix
        var lastIndex = -minimumGap
        for (i, match) in pairMatches.enumerated() {
            let remaining = pairMatches.count - i
            let slots = result.count + remaining
            var target = ((i + 1) * slots) / (pairMatches.count + 1)
            if i > 0 {
                target = max(target, lastIndex + minimumGap + 1)
            }
            target = min(target, result.count)
            result.insert(.pairMatch(match.round, match.kind), at: target)
            lastIndex = target
        }
        return result
    }

    static func batchSpellingSyllableRanges(batchIndex: Int, batchCount: Int) -> [ClosedRange<Int>] {
        if batchCount <= 1 {
            return [2...3, 2...4]
        }
        if batchIndex == 0 {
            return [2...2, 2...3]
        }
        return [2...3, 3...3, 2...4]
    }

    static func recallSpellingSyllableRanges() -> [ClosedRange<Int>] {
        [4...5, 3...5, 3...4, 2...5]
    }

    static func reviewBatchSpellingSyllableRanges(batchIndex: Int, batchCount: Int) -> [ClosedRange<Int>] {
        if batchCount <= 1 {
            return [2...3, 3...4, 2...4]
        }
        if batchIndex == 0 {
            return [2...3, 2...4]
        }
        return [3...4, 3...5, 2...4]
    }

    private static func shuffleDrillsAvoidingClusters(_ drills: [KanaLessonDrillItem]) -> [KanaLessonDrillItem] {
        guard drills.count > 1 else { return drills }

        var remaining = drills
        var result: [KanaLessonDrillItem] = []
        var previousKana: String?
        var streak = 0

        while !remaining.isEmpty {
            let eligible = remaining.enumerated().filter { _, item in
                let kana = item.primaryKana
                if kana == previousKana, streak >= 2 { return false }
                return true
            }

            let pickIndex: Int
            if let choice = eligible.randomElement() {
                pickIndex = choice.offset
            } else {
                pickIndex = 0
            }

            let item = remaining.remove(at: pickIndex)
            let kana = item.primaryKana
            if kana == previousKana {
                streak += 1
            } else {
                previousKana = kana
                streak = 1
            }
            result.append(item)
        }

        return result
    }

    /// Row-review drills split like lesson batches: one immediate drill, remainder deferred.
    static func splitReviewDrills(
        for glyph: KanaGlyph,
        in row: KanaRow,
        includeImmediate: Bool
    ) -> (immediate: KanaLessonDrillItem?, deferred: [KanaLessonDrillItem]) {
        let drills = [
            KanaLessonDrillItem.recognitionMC(discoveryRound(for: glyph, in: row)),
            .soundMatch(
                makeRound(glyph: glyph, distractorPool: row.glyphs, direction: .kanaToRomaji)
            ),
            .listenIdentify(
                makeListenIdentifyRound(glyph: glyph, distractorPool: row.glyphs)
            ),
            .soundMatch(
                makeRound(glyph: glyph, distractorPool: row.glyphs, direction: .romajiToKana)
            ),
        ].shuffled()

        guard includeImmediate else {
            return (nil, drills)
        }
        return (drills[0], Array(drills.dropFirst()))
    }

    /// Row-review drills: recognition MC plus recall, listen-identify, and production, shuffled together.
    static func shuffledReviewDrills(
        for row: KanaRow
    ) -> [KanaLessonDrillItem] {
        row.glyphs.flatMap { glyph in
            splitReviewDrills(for: glyph, in: row, includeImmediate: false).deferred
        }.shuffled()
    }

    static func soundMatchRounds(
        for row: KanaRow,
        directions: [KanaSoundMatchDirection],
        shuffle: Bool = true
    ) -> [KanaSoundMatchRound] {
        var rounds: [KanaSoundMatchRound] = []
        for glyph in row.glyphs {
            for direction in directions {
                rounds.append(makeRound(glyph: glyph, row: row, direction: direction))
            }
        }
        if shuffle {
            rounds.shuffle()
        }
        return rounds
    }

    static func soundMatchRounds(
        for glyphs: [KanaGlyph],
        distractorPool: [KanaGlyph],
        shuffle: Bool = true
    ) -> [KanaSoundMatchRound] {
        var rounds: [KanaSoundMatchRound] = []
        for glyph in glyphs {
            for direction in [KanaSoundMatchDirection.kanaToRomaji, .romajiToKana] {
                rounds.append(makeRound(glyph: glyph, distractorPool: distractorPool, direction: direction))
            }
        }
        if shuffle {
            rounds.shuffle()
        }
        return rounds
    }

    static func srsReviewRounds(for kanaGlyphs: [String]) -> [KanaSoundMatchRound] {
        let glyphs = kanaGlyphs.compactMap { KanaCurriculum.glyph(kana: $0) }
        guard let script = glyphs.first?.script else { return [] }
        let pool = KanaCurriculum.seionLessonRows(script: script).flatMap(\.glyphs)
        return soundMatchRounds(for: glyphs, distractorPool: pool, shuffle: true)
    }

    private static func makeRound(
        glyph: KanaGlyph,
        row: KanaRow,
        direction: KanaSoundMatchDirection
    ) -> KanaSoundMatchRound {
        makeRound(glyph: glyph, distractorPool: row.glyphs, direction: direction)
    }

    private static func makeRound(
        glyph: KanaGlyph,
        distractorPool: [KanaGlyph],
        direction: KanaSoundMatchDirection
    ) -> KanaSoundMatchRound {
        let distractors = pickDistractors(
            correct: glyph,
            pool: distractorPool,
            count: 3
        )

        switch direction {
        case .kanaToRomaji:
            let choices = ([glyph.romaji] + distractors.map(\.romaji)).shuffled()
            return KanaSoundMatchRound(
                direction: .kanaToRomaji,
                draggedText: glyph.kana,
                correctChoice: glyph.romaji,
                choices: choices
            )
        case .romajiToKana:
            let choices = ([glyph.kana] + distractors.map(\.kana)).shuffled()
            return KanaSoundMatchRound(
                direction: .romajiToKana,
                draggedText: glyph.romaji,
                correctChoice: glyph.kana,
                choices: choices
            )
        }
    }

    private static func makeListenIdentifyRound(
        glyph: KanaGlyph,
        distractorPool: [KanaGlyph]
    ) -> KanaListenIdentifyRound {
        let distractors = pickDistractors(
            correct: glyph,
            pool: distractorPool,
            count: 3
        )
        let choices = ([glyph.kana] + distractors.map(\.kana)).shuffled()
        return KanaListenIdentifyRound(
            targetKana: glyph.kana,
            correctChoice: glyph.kana,
            choices: choices
        )
    }

    private static func pickDistractors(
        correct: KanaGlyph,
        pool: [KanaGlyph],
        count: Int
    ) -> [KanaGlyph] {
        var candidates = pool.filter { $0.kana != correct.kana }
        if candidates.count < count {
            let sectionPool = KanaCurriculum.seionLessonRows(script: correct.script)
                .filter { $0.section == correct.section }
                .flatMap(\.glyphs)
                .filter { $0.kana != correct.kana }
            for glyph in sectionPool where !candidates.contains(where: { $0.kana == glyph.kana }) {
                candidates.append(glyph)
            }
        }
        return Array(candidates.shuffled().prefix(count))
    }

    // MARK: - Pair match

    /// Single-glyph kana ↔ romaji board for the row (up to four pairs).
    static func kanaPairMatchRound(for row: KanaRow) -> KanaPairMatchRound {
        let pairCount = min(KanaPairMatchRound.preferredPairCount, row.glyphs.count)
        let glyphs = Array(row.glyphs.shuffled().prefix(pairCount))
        let pairs = glyphs.map { glyph in
            let displayKana = row.script == .katakana
                ? KanaCurriculum.hiraganaToKatakana(glyph.kana)
                : glyph.kana
            return KanaPairMatchPair(
                kana: displayKana,
                romaji: glyph.romaji,
                speaksKana: glyph.kana
            )
        }
        let sideLayout: KanaPairMatchSideLayout = Bool.random() ? .kanaOnLeft : .romajiOnLeft
        return KanaPairMatchRound(sideLayout: sideLayout, pairs: pairs)
    }

    /// Short-word kana ↔ romaji board (always returned; falls back to row vocabulary).
    static func wordPairMatchRound(
        for row: KanaRow,
        unlockedGlyphs: Set<String>
    ) -> KanaPairMatchRound {
        let targetCount = KanaPairMatchRound.preferredPairCount

        if shouldIncludeSpelling(for: row, unlockedGlyphs: unlockedGlyphs) {
            let eligible = eligibleSpellingEntries(
                for: row,
                unlockedGlyphs: unlockedGlyphs,
                excludingWords: []
            )

            let rowTied = filterSpellingEntries(
                from: eligible,
                script: row.script,
                requiredOverlapGlyphs: row.kanaSet,
                minimumOverlapCount: 1,
                preferredSyllableRanges: [2...3, 2...4, 2...5]
            )
            var entries = pickSpellingEntries(
                from: rowTied,
                overlapGlyphs: row.kanaSet,
                priorGlyphs: unlockedGlyphs.subtracting(row.kanaSet),
                maxCount: targetCount,
                bias: .currentBatch
            )

            if entries.count < 2 {
                let multiSyllable = eligible.filter {
                    syllableCount(for: $0, script: row.script) >= 2
                }
                entries = pickSpellingEntries(
                    from: multiSyllable.isEmpty ? eligible : multiSyllable,
                    overlapGlyphs: row.kanaSet,
                    priorGlyphs: unlockedGlyphs.subtracting(row.kanaSet),
                    maxCount: targetCount,
                    bias: .currentBatch
                )
            }

            if entries.count >= 2 {
                return makeWordPairMatchRound(from: entries, row: row)
            }
        }

        let catalogPairs = catalogWordPairs(for: row, maxCount: targetCount)
        if catalogPairs.count >= 2 {
            return makePairMatchRound(pairs: catalogPairs)
        }

        let fallbackPairs = catalogWordPairs(for: row, maxCount: targetCount, minimumSyllables: 1)
        return makePairMatchRound(pairs: fallbackPairs)
    }

    private static func makeWordPairMatchRound(
        from entries: [CurriculumSpellingWord],
        row: KanaRow
    ) -> KanaPairMatchRound {
        makeWordPairMatchRound(from: entries, script: row.script)
    }

    private static func makeWordPairMatchRound(
        from entries: [CurriculumSpellingWord],
        script: KanaScript
    ) -> KanaPairMatchRound {
        let pairs = entries.map { entry in
            let word = entry.word
            let speaksKana = script == .katakana
                ? KanaCurriculum.katakanaToHiragana(word.hiragana)
                : word.hiragana
            return KanaPairMatchPair(
                kana: word.hiragana,
                romaji: word.romaji,
                speaksKana: speaksKana,
                spellingWordKey: word.hiragana
            )
        }
        return makePairMatchRound(pairs: pairs)
    }

    private static func makePairMatchRound(pairs: [KanaPairMatchPair]) -> KanaPairMatchRound {
        let sideLayout: KanaPairMatchSideLayout = Bool.random() ? .kanaOnLeft : .romajiOnLeft
        return KanaPairMatchRound(sideLayout: sideLayout, pairs: pairs)
    }

    private static func catalogWordPairs(
        for row: KanaRow,
        maxCount: Int,
        minimumSyllables: Int = 2
    ) -> [KanaPairMatchPair] {
        var pairs: [KanaPairMatchPair] = []
        var seen = Set<String>()

        for glyph in row.glyphs.shuffled() {
            let examples = KanaDetailCatalog.vocabularyExamples(
                for: glyph.kana,
                romaji: glyph.romaji,
                maxCount: 4
            )
            for example in examples {
                guard !seen.contains(example.japanese) else { continue }
                let syllableCount = HiraganaRomaji.syllables(in: example.japanese, script: row.script).count
                guard syllableCount >= minimumSyllables else { continue }
                seen.insert(example.japanese)

                let speaksKana = row.script == .katakana
                    ? KanaCurriculum.katakanaToHiragana(example.japanese)
                    : example.japanese
                pairs.append(
                    KanaPairMatchPair(
                        kana: example.japanese,
                        romaji: example.romaji,
                        speaksKana: speaksKana
                    )
                )
                if pairs.count >= maxCount { return pairs }
            }
        }

        return pairs
    }

    // MARK: - Spelling

    static func spellingItems(
        for row: KanaRow,
        unlockedGlyphs: Set<String>,
        excludingWords: Set<String> = [],
        romajiCount: Int = 1,
        listenSpellCount: Int = 0,
        requiredOverlapGlyphs: Set<String>,
        minimumOverlapCount: Int = 1,
        preferredSyllableRanges: [ClosedRange<Int>] = [],
        bias: KanaSpellingSelectionBias = .currentBatch
    ) -> [KanaLessonSpellingItem] {
        let totalCount = romajiCount + listenSpellCount
        guard totalCount > 0 else { return [] }
        guard shouldIncludeSpelling(for: row, unlockedGlyphs: unlockedGlyphs) else { return [] }

        let eligible = eligibleSpellingEntries(
            for: row,
            unlockedGlyphs: unlockedGlyphs,
            excludingWords: excludingWords
        )
        guard !eligible.isEmpty else { return [] }

        let filtered = filterSpellingEntries(
            from: eligible,
            script: row.script,
            requiredOverlapGlyphs: requiredOverlapGlyphs,
            minimumOverlapCount: minimumOverlapCount,
            preferredSyllableRanges: preferredSyllableRanges
        )
        guard !filtered.isEmpty else { return [] }

        let entries = pickSpellingEntries(
            from: filtered,
            overlapGlyphs: requiredOverlapGlyphs,
            priorGlyphs: unlockedGlyphs.subtracting(requiredOverlapGlyphs),
            maxCount: totalCount,
            bias: bias
        )
        return makeSpellingItems(from: entries, listenSpellCount: listenSpellCount)
    }

    /// End-of-lesson spelling with longer, row-tied words.
    static func shouldIncludeRecallSpelling(for row: KanaRow, unlockedGlyphs: Set<String>) -> Bool {
        let eligible = eligibleSpellingEntries(for: row, unlockedGlyphs: unlockedGlyphs, excludingWords: [])
        let filtered = filterSpellingEntries(
            from: eligible,
            script: row.script,
            requiredOverlapGlyphs: row.kanaSet,
            minimumOverlapCount: 1,
            preferredSyllableRanges: recallSpellingSyllableRanges()
        )
        return !filtered.isEmpty
    }

    private static func eligibleSpellingEntries(
        for row: KanaRow,
        unlockedGlyphs: Set<String>,
        excludingWords: Set<String>
    ) -> [CurriculumSpellingWord] {
        spellingWordBank(for: row.script).filter { entry in
            entry.requiredGlyphs.isSubset(of: unlockedGlyphs)
                && unlockedGlyphs.count >= entry.minimumUnlockedGlyphCount
                && !excludingWords.contains(entry.word.hiragana)
        }
    }

    private static func syllableCount(for entry: CurriculumSpellingWord, script: KanaScript) -> Int {
        HiraganaRomaji.syllables(in: entry.word.hiragana, script: script).count
    }

    private static func filterSpellingEntries(
        from candidates: [CurriculumSpellingWord],
        script: KanaScript,
        requiredOverlapGlyphs: Set<String>,
        minimumOverlapCount: Int,
        preferredSyllableRanges: [ClosedRange<Int>]
    ) -> [CurriculumSpellingWord] {
        func overlapMatches(_ entry: CurriculumSpellingWord) -> Bool {
            entry.requiredGlyphs.intersection(requiredOverlapGlyphs).count >= minimumOverlapCount
        }

        func matchesRange(_ entry: CurriculumSpellingWord, range: ClosedRange<Int>) -> Bool {
            overlapMatches(entry) && range.contains(syllableCount(for: entry, script: script))
        }

        for range in preferredSyllableRanges {
            let filtered = candidates.filter { matchesRange($0, range: range) }
            if !filtered.isEmpty { return filtered }
        }

        return candidates.filter(overlapMatches)
    }

    private static func pickSpellingEntries(
        from candidates: [CurriculumSpellingWord],
        overlapGlyphs: Set<String>,
        priorGlyphs: Set<String>,
        maxCount: Int,
        bias: KanaSpellingSelectionBias
    ) -> [CurriculumSpellingWord] {
        guard !candidates.isEmpty else { return [] }

        let ranked = candidates
            .map { entry -> (CurriculumSpellingWord, Int) in
                let score: Int
                switch bias {
                case .currentBatch:
                    let overlap = entry.requiredGlyphs.intersection(overlapGlyphs).count
                    score = overlap * 100 + entry.requiredGlyphs.count * 10 + entry.minimumUnlockedGlyphCount
                case .priorLearning:
                    let rowOverlap = entry.requiredGlyphs.intersection(overlapGlyphs).count
                    let priorOverlap = entry.requiredGlyphs.intersection(priorGlyphs).count
                    score = priorOverlap * 100 + rowOverlap * 10 + entry.requiredGlyphs.count
                }
                return (entry, score)
            }
            .sorted { $0.1 > $1.1 }

        var picked: [CurriculumSpellingWord] = []
        var seen: Set<String> = []
        for (entry, _) in ranked {
            guard !seen.contains(entry.word.hiragana) else { continue }
            picked.append(entry)
            seen.insert(entry.word.hiragana)
            if picked.count >= maxCount { break }
        }
        return picked
    }

    private static func makeSpellingItems(
        from entries: [CurriculumSpellingWord],
        listenSpellCount: Int
    ) -> [KanaLessonSpellingItem] {
        guard !entries.isEmpty else { return [] }

        let audioCount = min(listenSpellCount, entries.count)
        let audioIndices = Set(entries.indices.shuffled().prefix(audioCount))
        var items = entries.enumerated().map { index, entry in
            KanaLessonSpellingItem(
                word: entry.word,
                promptStyle: audioIndices.contains(index) ? .audio : .romaji
            )
        }
        items.shuffle()
        return items
    }

    static func shouldIncludeSpelling(for row: KanaRow, unlockedGlyphs: Set<String>) -> Bool {
        spellingWordBank(for: row.script).contains { entry in
            entry.requiredGlyphs.isSubset(of: unlockedGlyphs)
                && unlockedGlyphs.count >= entry.minimumUnlockedGlyphCount
        }
    }

    // MARK: - Custom chart review

    struct CustomReviewContent {
        let mixItems: [KanaLessonBatchMixItem]
    }

    static func customReviewContent(
        selectedKana: Set<String>,
        script: KanaScript,
        unlockedGlyphs: Set<String>
    ) -> CustomReviewContent {
        let glyphs = selectedKana.compactMap { kana -> KanaGlyph? in
            guard unlockedGlyphs.contains(kana) else { return nil }
            return KanaCurriculum.glyph(kana: kana, script: script)
        }
        guard !glyphs.isEmpty else {
            return CustomReviewContent(mixItems: [])
        }

        let selectedSet = Set(glyphs.map(\.kana))
        let distractorPool = Array(
            Set(glyphs + KanaCurriculum.seionLessonRows(script: script).flatMap(\.glyphs))
        )

        var drills: [KanaLessonDrillItem] = []
        for glyph in glyphs {
            if let row = KanaCurriculum.row(id: glyph.rowID, script: script, section: glyph.section) {
                drills.append(
                    contentsOf: splitReviewDrills(
                        for: glyph,
                        in: row,
                        includeImmediate: false
                    ).deferred
                )
            } else {
                drills.append(
                    contentsOf: splitBatchDrills(
                        for: glyph,
                        distractorPool: distractorPool,
                        includeImmediate: false
                    ).deferred
                )
            }
        }

        let romajiSpellCount = max(1, min(2, glyphs.count))
        let listenSpellCount = glyphs.count >= 2 ? 1 : 0
        var spelling = spellingItemsForSelectedGlyphs(
            selectedGlyphs: selectedSet,
            unlockedGlyphs: unlockedGlyphs,
            script: script,
            romajiCount: romajiSpellCount,
            listenSpellCount: listenSpellCount
        )
        if spelling.isEmpty {
            spelling = glyphSpellingFallback(
                glyphs: glyphs,
                romajiCount: romajiSpellCount,
                listenSpellCount: listenSpellCount
            )
        }

        var pairMatches: [(round: KanaPairMatchRound, kind: KanaPairMatchStepKind)] = []
        if let wordRound = customReviewWordPairMatchRound(
            glyphs: glyphs,
            selectedGlyphs: selectedSet,
            unlockedGlyphs: unlockedGlyphs,
            script: script
        ) {
            pairMatches.append((wordRound, .words))
        }
        let mixItems = shuffledBatchMix(
            drills: drills,
            spelling: spelling,
            pairMatches: pairMatches
        )
        return CustomReviewContent(mixItems: mixItems)
    }

    static func customReviewWordPairMatchRound(
        glyphs: [KanaGlyph],
        selectedGlyphs: Set<String>,
        unlockedGlyphs: Set<String>,
        script: KanaScript
    ) -> KanaPairMatchRound? {
        guard glyphs.count >= 2 else { return nil }

        let targetCount = min(KanaPairMatchRound.preferredPairCount, glyphs.count)
        let eligible = spellingWordBank(for: script).filter { entry in
            entry.requiredGlyphs.isSubset(of: unlockedGlyphs)
                && unlockedGlyphs.count >= entry.minimumUnlockedGlyphCount
                && !entry.requiredGlyphs.isDisjoint(with: selectedGlyphs)
        }

        var entries: [CurriculumSpellingWord] = []
        if !eligible.isEmpty {
            let filtered = filterSpellingEntries(
                from: eligible,
                script: script,
                requiredOverlapGlyphs: selectedGlyphs,
                minimumOverlapCount: 1,
                preferredSyllableRanges: [2...3, 2...4, 2...5, 3...5]
            )
            let candidates = filtered.isEmpty ? eligible : filtered
            let subsetCandidates = candidates.filter { $0.requiredGlyphs.isSubset(of: selectedGlyphs) }
            let pickFrom = subsetCandidates.isEmpty ? candidates : subsetCandidates
            entries = pickSpellingEntries(
                from: pickFrom,
                overlapGlyphs: selectedGlyphs,
                priorGlyphs: unlockedGlyphs.subtracting(selectedGlyphs),
                maxCount: targetCount,
                bias: .currentBatch
            )
        }

        if entries.count >= 2 {
            return makeWordPairMatchRound(from: entries, script: script)
        }

        let pairs = glyphs.prefix(targetCount).map { glyph in
            let displayKana = script == .katakana
                ? KanaCurriculum.hiraganaToKatakana(glyph.kana)
                : glyph.kana
            return KanaPairMatchPair(
                kana: displayKana,
                romaji: glyph.romaji,
                speaksKana: glyph.kana,
                spellingWordKey: glyph.kana
            )
        }
        guard pairs.count >= 2 else { return nil }
        return makePairMatchRound(pairs: pairs)
    }

    private static func spellingItemsForSelectedGlyphs(
        selectedGlyphs: Set<String>,
        unlockedGlyphs: Set<String>,
        script: KanaScript,
        romajiCount: Int,
        listenSpellCount: Int,
        excludingWords: Set<String> = []
    ) -> [KanaLessonSpellingItem] {
        let totalCount = romajiCount + listenSpellCount
        guard totalCount > 0 else { return [] }

        let eligible = spellingWordBank(for: script).filter { entry in
            entry.requiredGlyphs.isSubset(of: unlockedGlyphs)
                && unlockedGlyphs.count >= entry.minimumUnlockedGlyphCount
                && !excludingWords.contains(entry.word.hiragana)
        }
        guard !eligible.isEmpty else { return [] }

        let filtered = filterSpellingEntries(
            from: eligible,
            script: script,
            requiredOverlapGlyphs: selectedGlyphs,
            minimumOverlapCount: 1,
            preferredSyllableRanges: [2...3, 2...4, 3...4]
        )
        let candidates = filtered.isEmpty
            ? eligible.filter { !$0.requiredGlyphs.isDisjoint(with: selectedGlyphs) }
            : filtered
        let subsetCandidates = candidates.filter { $0.requiredGlyphs.isSubset(of: selectedGlyphs) }
        let pickFrom = subsetCandidates.isEmpty ? candidates : subsetCandidates
        guard !pickFrom.isEmpty else { return [] }

        let entries = pickSpellingEntries(
            from: pickFrom,
            overlapGlyphs: selectedGlyphs,
            priorGlyphs: unlockedGlyphs.subtracting(selectedGlyphs),
            maxCount: totalCount,
            bias: .currentBatch
        )
        return makeSpellingItems(from: entries, listenSpellCount: listenSpellCount)
    }

    private static func glyphSpellingFallback(
        glyphs: [KanaGlyph],
        romajiCount: Int,
        listenSpellCount: Int
    ) -> [KanaLessonSpellingItem] {
        let shuffled = glyphs.shuffled()
        let totalCount = min(romajiCount + listenSpellCount, shuffled.count)
        guard totalCount > 0 else { return [] }

        let listenCount = min(listenSpellCount, totalCount)
        let listenIndices = Set(shuffled.indices.prefix(listenCount))
        return shuffled.prefix(totalCount).enumerated().map { index, glyph in
            KanaLessonSpellingItem(
                word: KanaSpellingWord(
                    hiragana: glyph.kana,
                    romaji: glyph.romaji,
                    meaning: glyph.romaji
                ),
                promptStyle: listenIndices.contains(index) ? .audio : .romaji
            )
        }
    }

    private static func spellingWordBank(for script: KanaScript) -> [CurriculumSpellingWord] {
        switch script {
        case .hiragana: KanaSpellingWordBank.curriculumWords
        case .katakana: KanaSpellingWordBank.katakanaCurriculumWords
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

extension KanaSoundMatchRound {
    var primaryKana: String {
        switch direction {
        case .kanaToRomaji: draggedText
        case .romajiToKana: correctChoice
        }
    }

    /// Kana audio to play on drop: dragged glyph (kana→romaji) or destination glyph (romaji→kana).
    func droppedKanaToPlay(on destinationChoice: String) -> String {
        switch direction {
        case .kanaToRomaji: draggedText
        case .romajiToKana: destinationChoice
        }
    }
}
