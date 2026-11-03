//
//  LessonUnitSections.swift
//  shizen
//
//  Groups a CMS dialogue lesson index into per-curriculum-unit sections for
//  the Dialogue home path and the CMS lessons waterfall grid.
//

import Foundation

/// CMS Lessons filter bucket. N5–N3 follow a unit's `jlptLevel`.
/// Lessons with no unit, and units outside N5–N3, are unassigned (`NA`).
nonisolated enum CMSLessonTrack: CaseIterable, Hashable, Sendable {
    case n5
    case n4
    case n3
    case unassigned

    var title: String {
        switch self {
        case .n5: return "N5"
        case .n4: return "N4"
        case .n3: return "N3"
        case .unassigned: return "NA"
        }
    }

    init(jlptLevel: Int) {
        switch jlptLevel {
        case 5: self = .n5
        case 4: self = .n4
        case 3: self = .n3
        default: self = .unassigned
        }
    }
}

/// Dialogue lesson track on the home path. 5 = N5 … 3 = N3.
enum DialogueLessonTrack: Int, CaseIterable {
    case n5 = 5
    case n4 = 4
    case n3 = 3

    var title: String { "N\(rawValue)" }

    private static let storageKey = "dialogue.lessonTrack"

    static let didChangeNotification = Notification.Name("shizen.dialogueLessonTrackDidChange")

    static var current: DialogueLessonTrack {
        get {
            let raw = UserDefaults.standard.integer(forKey: storageKey)
            return DialogueLessonTrack(rawValue: raw) ?? .n5
        }
        set {
            guard newValue != current else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }
}

struct LessonUnitSection {
    let title: String?
    let subtitle: String?
    let lessons: [WaterfallLesson]
    let track: CMSLessonTrack

    init(
        title: String?,
        subtitle: String?,
        lessons: [WaterfallLesson],
        track: CMSLessonTrack = .unassigned
    ) {
        self.title = title
        self.subtitle = subtitle
        self.lessons = lessons
        self.track = track
    }
}

struct LessonTrackProgress {
    let completedScenes: Int
    let totalScenes: Int
    let stars: Int
}

enum LessonUnitSectionBuilder {

    /// One section per curriculum unit (in unit order), then an unfiled section
    /// for lessons with no unit. With no units at all, a single headerless
    /// section preserves the old flat grid.
    static func sections(from index: CMSDialogueLessonIndex) -> [LessonUnitSection] {
        guard !index.units.isEmpty else {
            return index.lessons.isEmpty
                ? []
                : [LessonUnitSection(
                    title: nil,
                    subtitle: nil,
                    lessons: index.lessons.map(waterfallLesson),
                    track: .unassigned
                )]
        }

        var sections: [LessonUnitSection] = []
        for unit in index.units {
            let lessons = index.lessons.filter { $0.unitId == unit.id }
            guard !lessons.isEmpty else { continue }
            sections.append(
                LessonUnitSection(
                    title: unit.title,
                    subtitle: unit.subtitle ?? "Level N\(unit.jlptLevel)",
                    lessons: lessons.map(waterfallLesson),
                    track: CMSLessonTrack(jlptLevel: unit.jlptLevel)
                )
            )
        }

        let knownUnitIDs = Set(index.units.map(\.id))
        let unfiled = index.lessons.filter { lesson in
            guard let unitId = lesson.unitId else { return true }
            return !knownUnitIDs.contains(unitId)
        }
        if !unfiled.isEmpty {
            sections.append(
                LessonUnitSection(
                    title: "More lessons",
                    subtitle: nil,
                    lessons: unfiled.map(waterfallLesson),
                    track: .unassigned
                )
            )
        }
        return sections
    }

    static func waterfallLesson(from summary: CMSDialogueLessonSummary) -> WaterfallLesson {
        WaterfallLesson(
            id: summary.id,
            title: summary.title,
            conversationCount: summary.scenarioCount,
            thumbnailName: summary.sceneImage ?? summary.id,
            thumbnailURL: (summary.thumbnailSmallUrl ?? summary.thumbnailUrl).flatMap(URL.init(string:)),
            scenarioIDs: summary.scenarioIDs,
            isLocked: false
        )
    }

    static func pathUnits(from index: CMSDialogueLessonIndex) -> [PathUnit] {
        pathUnits(from: index, completedScenarioIDs: [])
    }

    static func pathUnits(
        from index: CMSDialogueLessonIndex,
        progress: LessonProgressProviding
    ) -> [PathUnit] {
        pathUnits(from: index, completedScenarioIDs: progress.completedScenarioIDs)
    }

    static func pathUnits(
        from index: CMSDialogueLessonIndex,
        progress: LessonProgressProviding,
        track: DialogueLessonTrack
    ) -> [PathUnit] {
        pathUnits(from: scopedIndex(index, track: track), progress: progress)
    }

    /// Units and lessons for one JLPT track. Lessons with no curriculum unit
    /// stay on N5 so they remain reachable from the beginner path.
    static func scopedIndex(
        _ index: CMSDialogueLessonIndex,
        track: DialogueLessonTrack
    ) -> CMSDialogueLessonIndex {
        if index.units.isEmpty {
            return track == .n5 ? index : CMSDialogueLessonIndex(units: [], lessons: [])
        }
        let knownUnitIDs = Set(index.units.map(\.id))
        let units = index.units.filter { $0.jlptLevel == track.rawValue }
        let unitIDs = Set(units.map(\.id))
        let lessons = index.lessons.filter { lesson in
            guard let unitId = lesson.unitId else { return track == .n5 }
            if unitIDs.contains(unitId) { return true }
            return !knownUnitIDs.contains(unitId) && track == .n5
        }
        return CMSDialogueLessonIndex(units: units, lessons: lessons)
    }

    /// Scenes completed and best stars for one track, scoped and counted like the home path.
    static func trackProgress(
        from index: CMSDialogueLessonIndex,
        track: DialogueLessonTrack,
        progress: DialogueProgressStore
    ) -> LessonTrackProgress {
        let completedIDs = progress.completedScenarioIDs
        var completed = 0
        var total = 0
        var stars = 0
        for summary in scopedIndex(index, track: track).lessons where summary.scenarioCount > 0 {
            let lesson = waterfallLesson(from: summary)
            let partCount = sceneCount(for: lesson)
            total += partCount
            completed += sceneProgress(
                for: lesson,
                partCount: partCount,
                completedScenarioIDs: completedIDs
            ).completedParts
            let sceneIDs = lesson.scenarioIDs.isEmpty
                ? completedIDs.filter { $0.hasPrefix("\(summary.id)/") }
                : Set(lesson.scenarioIDs)
            stars += sceneIDs.reduce(0) { $0 + progress.displayedStarCount(scenarioID: $1) }
        }
        return LessonTrackProgress(completedScenes: completed, totalScenes: total, stars: stars)
    }

    static func pathUnits(
        from index: CMSDialogueLessonIndex,
        completedScenarioIDs: Set<String>
    ) -> [PathUnit] {
        let playable = CMSDialogueLessonIndex(
            units: index.units,
            lessons: index.lessons.filter { $0.scenarioCount > 0 }
        )
        var assignedCurrent = false
        return sections(from: playable).enumerated().map { index, section in
            PathUnit(
                eyebrow: pathEyebrow(for: section, index: index),
                title: pathHeaderTitle(for: section, sectionIndex: index),
                glowColor: index % 2 == 0 ? .yellow : .blue,
                lessons: section.lessons.map { lesson in
                    pathLesson(from: lesson, completedScenarioIDs: completedScenarioIDs, assignedCurrent: &assignedCurrent)
                },
                showsUnitNumberInLessonLabels: !isMoreLessonsSection(section)
            )
        }
    }

    static func pathUnits(from sections: [LessonUnitSection]) -> [PathUnit] {
        sections.enumerated().map { index, section in
            PathUnit(
                eyebrow: pathEyebrow(for: section, index: index),
                title: pathHeaderTitle(for: section, sectionIndex: index),
                glowColor: index % 2 == 0 ? .yellow : .blue,
                lessons: section.lessons.map(pathLesson),
                showsUnitNumberInLessonLabels: !isMoreLessonsSection(section)
            )
        }
    }

    private static func pathLesson(from lesson: WaterfallLesson) -> PathLesson {
        PathLesson(
            id: lesson.id,
            title: lesson.title,
            symbolName: pathSymbolName(for: lesson),
            thumbnailName: lesson.thumbnailName,
            thumbnailURL: lesson.thumbnailURL,
            state: lesson.isLocked ? .locked : .current,
            partCount: sceneCount(for: lesson)
        )
    }

    private static func pathLesson(
        from lesson: WaterfallLesson,
        completedScenarioIDs: Set<String>,
        assignedCurrent: inout Bool
    ) -> PathLesson {
        let partCount = sceneCount(for: lesson)
        let progress = sceneProgress(
            for: lesson,
            partCount: partCount,
            completedScenarioIDs: completedScenarioIDs
        )
        let state: PathLesson.State
        if progress.completedParts >= partCount {
            state = .completed
        } else if !assignedCurrent {
            state = .current
            assignedCurrent = true
        } else {
            state = .locked
        }
        return PathLesson(
            id: lesson.id,
            title: lesson.title,
            symbolName: pathSymbolName(for: lesson),
            thumbnailName: lesson.thumbnailName,
            thumbnailURL: lesson.thumbnailURL,
            state: state,
            completedParts: progress.completedParts,
            completedPartIndices: progress.completedPartIndices,
            partCount: partCount
        )
    }

    private static func sceneCount(for lesson: WaterfallLesson) -> Int {
        lesson.scenarioIDs.isEmpty ? lesson.conversationCount : lesson.scenarioIDs.count
    }

    /// Each index is one scene, in lesson order. When the index lists scene ids,
    /// only those exact ids light up. Older indexes fall back to a prefix count
    /// and fill the first N segments.
    private static func sceneProgress(
        for lesson: WaterfallLesson,
        partCount: Int,
        completedScenarioIDs: Set<String>
    ) -> (completedParts: Int, completedPartIndices: Set<Int>) {
        if !lesson.scenarioIDs.isEmpty {
            let indices = Set(
                lesson.scenarioIDs.enumerated().compactMap { index, id in
                    completedScenarioIDs.contains(id) ? index : nil
                }
            )
            return (indices.count, indices)
        }
        guard let lessonID = lesson.id, !lessonID.isEmpty else {
            return (0, [])
        }
        let prefix = "\(lessonID)/"
        let completedParts = min(
            partCount,
            completedScenarioIDs.lazy.filter { $0.hasPrefix(prefix) }.count
        )
        return (completedParts, Set(0 ..< completedParts))
    }

    private static let moreLessonsSectionTitle = "More lessons"

    private static func isMoreLessonsSection(_ section: LessonUnitSection) -> Bool {
        section.title == moreLessonsSectionTitle
    }

    private static func pathHeaderTitle(for section: LessonUnitSection, sectionIndex: Int) -> String {
        if isMoreLessonsSection(section) {
            return moreLessonsSectionTitle
        }
        if let title = section.title {
            return "Unit \(sectionIndex + 1) · \(title)"
        }
        return "Lessons"
    }

    private static func pathEyebrow(for section: LessonUnitSection, index: Int) -> String {
        if isMoreLessonsSection(section) {
            return moreLessonsSectionTitle.uppercased()
        }
        if let subtitle = section.subtitle, !subtitle.isEmpty {
            return subtitle.uppercased()
        }
        if section.title != nil {
            return "UNIT \(index + 1)"
        }
        return "LESSONS"
    }

    private static func pathSymbolName(for lesson: WaterfallLesson) -> String {
        switch lesson.thumbnailName {
        case "train-station": return "tram.fill"
        case "at-the-library": return "book.fill"
        case "at-the-convenient-store": return "basket.fill"
        case "asking-directions": return "map.fill"
        default: return "text.bubble.fill"
        }
    }
}
