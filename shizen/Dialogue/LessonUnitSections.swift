//
//  LessonUnitSections.swift
//  shizen
//
//  Groups a CMS dialogue lesson index into per-curriculum-unit sections for
//  waterfall grid rendering. Shared by the Dialogue home tab and the CMS
//  lessons screen.
//

import Foundation

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
            thumbnailURL: summary.thumbnailUrl.flatMap(URL.init(string:)),
            isLocked: false
        )
    }
}
