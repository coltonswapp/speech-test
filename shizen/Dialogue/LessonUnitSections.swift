//
//  LessonUnitSections.swift
//  shizen
//
//  Groups a CMS dialogue lesson index into per-curriculum-unit sections for
//  the Dialogue home path and the CMS lessons waterfall grid.
//

import Foundation

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
}

enum LessonUnitSectionBuilder {

    /// One section per curriculum unit (in unit order), then an unfiled section
    /// for lessons with no unit. With no units at all, a single headerless
    /// section preserves the old flat grid.
    static func sections(from index: CMSDialogueLessonIndex) -> [LessonUnitSection] {
        guard !index.units.isEmpty else {
            return index.lessons.isEmpty
                ? []
                : [LessonUnitSection(title: nil, subtitle: nil, lessons: index.lessons.map(waterfallLesson))]
        }

        var sections: [LessonUnitSection] = []
        for unit in index.units {
            let lessons = index.lessons.filter { $0.unitId == unit.id }
            guard !lessons.isEmpty else { continue }
            sections.append(
                LessonUnitSection(
                    title: unit.title,
                    subtitle: unit.subtitle ?? "Level N\(unit.jlptLevel)",
                    lessons: lessons.map(waterfallLesson)
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
                    lessons: unfiled.map(waterfallLesson)
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
                title: section.title ?? "Lessons",
                glowColor: index % 2 == 0 ? .yellow : .blue,
                lessons: section.lessons.map { lesson in
                    pathLesson(from: lesson, completedScenarioIDs: completedScenarioIDs, assignedCurrent: &assignedCurrent)
                }
            )
        }
    }

    static func pathUnits(from sections: [LessonUnitSection]) -> [PathUnit] {
        sections.enumerated().map { index, section in
            PathUnit(
                eyebrow: pathEyebrow(for: section, index: index),
                title: section.title ?? "Lessons",
                glowColor: index % 2 == 0 ? .yellow : .blue,
                lessons: section.lessons.map(pathLesson)
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

    private static func pathEyebrow(for section: LessonUnitSection, index: Int) -> String {
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
