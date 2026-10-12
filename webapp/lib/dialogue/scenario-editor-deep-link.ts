/**
 * Scene-editor `?tab=` deep links (Curriculum chips, review queue, new-scene).
 *
 * A normal visit (no section tab) keeps remembered expand/collapse defaults.
 * A section tab expands only that section — callers apply this in memory and
 * must not persist it to localStorage.
 */

export const SCENARIO_EDITOR_SECTION_IDS = [
  "overview",
  "lines",
  "audio",
  "highlights",
  "quiz",
] as const;

export type ScenarioEditorSectionId =
  (typeof SCENARIO_EDITOR_SECTION_IDS)[number];

const SECTION_ID_SET = new Set<string>(SCENARIO_EDITOR_SECTION_IDS);

export function isScenarioEditorSectionId(
  value: string | null,
): value is ScenarioEditorSectionId {
  return value != null && SECTION_ID_SET.has(value);
}

/** Curriculum readiness chip → scene-editor `?tab=` section. */
export const READINESS_CHIP_TAB = {
  audio: "audio",
  align: "audio",
  review: "audio",
  published: "audio",
  quiz: "quiz",
  thumbnail: "overview",
  contentQa: "overview",
} as const satisfies Record<string, ScenarioEditorSectionId>;

export type ReadinessChipKey = keyof typeof READINESS_CHIP_TAB;
export type ReadinessChipTab =
  (typeof READINESS_CHIP_TAB)[ReadinessChipKey];

export function readinessChipHref(
  hrefBase: string,
  chip: ReadinessChipKey,
): string {
  return `${hrefBase}?tab=${READINESS_CHIP_TAB[chip]}`;
}

export type ScenarioEditorDeepLink = {
  keepOpen: ScenarioEditorSectionId;
  /** Every section except `keepOpen`. */
  collapsed: ScenarioEditorSectionId[];
};

/**
 * Exclusive expand for a section `?tab=` (or review-queue with no/invalid tab).
 * `null` = leave the editor's default / remembered collapsed set alone.
 * `tab=raw` / `tab=source` switch the top-level view, not a collapsible section.
 */
export function scenarioEditorDeepLink(params: {
  tab: string | null;
  fromReview?: boolean;
}): ScenarioEditorDeepLink | null {
  const { tab, fromReview } = params;
  if (tab === "raw" || tab === "source") return null;

  const keepOpen: ScenarioEditorSectionId | null = isScenarioEditorSectionId(
    tab,
  )
    ? tab
    : fromReview
      ? "audio"
      : null;
  if (!keepOpen) return null;

  return {
    keepOpen,
    collapsed: SCENARIO_EDITOR_SECTION_IDS.filter((id) => id !== keepOpen),
  };
}
