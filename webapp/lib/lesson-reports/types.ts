/**
 * Shapes and parsers for `lessonReportStats` / `lessonReports`, written by
 * `services/llm-gateway/src/lesson-report.ts`. Stats use literal dotted field
 * names (`categories.audio`), not nested maps. See FIRESTORE_USAGE_CONTRACT.md.
 */

import { timestampIso } from "@/lib/lesson-feedback/types";

export const LESSON_REPORT_CATEGORIES = [
  "audio",
  "timing",
  "translation",
  "content",
  "quiz",
  "bug",
  "other",
] as const;

export type LessonReportCategory = (typeof LESSON_REPORT_CATEGORIES)[number];

export const lessonReportCategoryLabels: Record<LessonReportCategory, string> = {
  audio: "Wrong audio",
  timing: "Timing",
  translation: "Translation",
  content: "Japanese text",
  quiz: "Quiz",
  bug: "Broken",
  other: "Other",
};

export const LESSON_REPORT_STATUSES = ["open", "resolved", "wontfix"] as const;

export type LessonReportStatus = (typeof LESSON_REPORT_STATUSES)[number];

export const lessonReportStatusLabels: Record<LessonReportStatus, string> = {
  open: "Open",
  resolved: "Resolved",
  wontfix: "Won't fix",
};

export type LessonReportStats = {
  sceneKey: string;
  count: number;
  open: number;
  categories: Record<LessonReportCategory, number>;
  lastReportedAt: string | null;
};

export type LessonReportEntry = {
  id: string;
  createdAt: string | null;
  status: LessonReportStatus;
  categories: LessonReportCategory[];
  note: string | null;
  page: string | null;
  focusTitle: string | null;
  focusDetails: string[];
  sessionMode: string | null;
  quizQuestionNumber: number | null;
  publishedVariantId: string | null;
  appVersion: string | null;
  osVersion: string | null;
};

export type ScenarioReports = {
  stats: LessonReportStats;
  recent: LessonReportEntry[];
  /** Set when the recent list could not load (for example, a missing index). */
  recentError: string | null;
};

function num(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function str(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value : null;
}

export function isLessonReportStatus(value: unknown): value is LessonReportStatus {
  return (
    typeof value === "string" &&
    (LESSON_REPORT_STATUSES as readonly string[]).includes(value)
  );
}

function isCategory(value: unknown): value is LessonReportCategory {
  return (
    typeof value === "string" &&
    (LESSON_REPORT_CATEGORIES as readonly string[]).includes(value)
  );
}

export function parseLessonReportStats(
  sceneKey: string,
  data: Record<string, unknown> | null,
): LessonReportStats {
  const source = data ?? {};
  const categories = {} as Record<LessonReportCategory, number>;
  for (const category of LESSON_REPORT_CATEGORIES) {
    categories[category] = num(source[`categories.${category}`]);
  }
  return {
    sceneKey,
    count: num(source.count),
    open: Math.max(0, num(source.open)),
    categories,
    lastReportedAt: timestampIso(source.lastReportedAt),
  };
}

export function parseLessonReportEntry(
  id: string,
  data: Record<string, unknown>,
): LessonReportEntry {
  const categories = Array.isArray(data.categories)
    ? data.categories.filter(isCategory)
    : [];
  const focusDetails = Array.isArray(data.focusDetails)
    ? data.focusDetails.filter((line): line is string => typeof line === "string")
    : [];
  return {
    id,
    createdAt: timestampIso(data.createdAt),
    status: isLessonReportStatus(data.status) ? data.status : "open",
    categories,
    note: str(data.note),
    page: str(data.page),
    focusTitle: str(data.focusTitle),
    focusDetails,
    sessionMode: str(data.sessionMode),
    quizQuestionNumber:
      typeof data.quizQuestionNumber === "number" ? data.quizQuestionNumber : null,
    publishedVariantId: str(data.publishedVariantId),
    appVersion: str(data.appVersion),
    osVersion: str(data.osVersion),
  };
}
