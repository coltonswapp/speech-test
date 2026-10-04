/**
 * Shapes and parsers for `lessonFeedbackStats` / `lessonFeedback`, written by
 * `services/llm-gateway/src/lesson-feedback.ts`. Stats use literal dotted
 * field names (`audio.sum`), not nested maps. See FIRESTORE_USAGE_CONTRACT.md.
 */

export const LESSON_FEEDBACK_DIMENSIONS = [
  "audio",
  "content",
  "highlighting",
  "quiz",
] as const;

export type LessonFeedbackDimension =
  (typeof LESSON_FEEDBACK_DIMENSIONS)[number];

export const lessonFeedbackDimensionLabels: Record<
  LessonFeedbackDimension,
  string
> = {
  audio: "Audio quality",
  content: "Content",
  highlighting: "Word highlighting",
  quiz: "Quiz",
};

export const PRODUCT_LESSON_FEEDBACK_SCOPE = "_product";

export type DimensionStats = {
  n: number;
  sum: number;
  average: number | null;
  /** Counts for ratings 1 through 5, index 0 is rating 1. */
  histogram: [number, number, number, number, number];
};

export type LessonFeedbackStats = {
  sceneKey: string;
  collectionId: string | null;
  scenarioId: string | null;
  count: number;
  dimensions: Record<LessonFeedbackDimension, DimensionStats>;
  /** Weakest dimension with at least one rating, used for ranking. */
  lowest: { dimension: LessonFeedbackDimension; average: number } | null;
  updatedAt: string | null;
};

export type LessonFeedbackEntry = {
  id: string;
  createdAt: string | null;
  ratings: Partial<Record<LessonFeedbackDimension, number>>;
  score: { correct: number; total: number; stars: number } | null;
  publishedVariantId: string | null;
  appVersion: string | null;
};

export type ScenarioFeedback = {
  stats: LessonFeedbackStats;
  recent: LessonFeedbackEntry[];
  /** Set when the recent list could not load (for example, a missing index). */
  recentError: string | null;
};

export type LessonFeedbackOverview = {
  product: LessonFeedbackStats;
  scenes: LessonFeedbackStats[];
};

export function lessonSceneKey(collectionId: string, scenarioId: string) {
  return `${collectionId}__${scenarioId}`;
}

function num(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function str(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value : null;
}

export function timestampIso(value: unknown): string | null {
  if (value && typeof value === "object" && "toDate" in value) {
    const toDate = (value as { toDate: unknown }).toDate;
    if (typeof toDate === "function") {
      const date = toDate.call(value) as Date;
      return Number.isNaN(date.getTime()) ? null : date.toISOString();
    }
  }
  return null;
}

export function parseLessonFeedbackStats(
  sceneKey: string,
  data: Record<string, unknown> | null,
): LessonFeedbackStats {
  const source = data ?? {};
  const dimensions = {} as Record<LessonFeedbackDimension, DimensionStats>;
  let lowest: LessonFeedbackStats["lowest"] = null;

  for (const dimension of LESSON_FEEDBACK_DIMENSIONS) {
    const n = num(source[`${dimension}.n`]);
    const sum = num(source[`${dimension}.sum`]);
    const average = n > 0 ? sum / n : null;
    const histogram = [1, 2, 3, 4, 5].map((rating) =>
      num(source[`${dimension}.h${rating}`]),
    ) as DimensionStats["histogram"];
    dimensions[dimension] = { n, sum, average, histogram };
    if (average != null && (lowest == null || average < lowest.average)) {
      lowest = { dimension, average };
    }
  }

  return {
    sceneKey,
    collectionId: str(source.collectionId),
    scenarioId: str(source.scenarioId),
    count: num(source.count),
    dimensions,
    lowest,
    updatedAt: timestampIso(source.updatedAt),
  };
}

export function parseLessonFeedbackEntry(
  id: string,
  data: Record<string, unknown>,
): LessonFeedbackEntry {
  const ratings: LessonFeedbackEntry["ratings"] = {};
  const rawRatings =
    data.ratings && typeof data.ratings === "object"
      ? (data.ratings as Record<string, unknown>)
      : {};
  for (const dimension of LESSON_FEEDBACK_DIMENSIONS) {
    const value = rawRatings[dimension];
    if (typeof value === "number" && value >= 1 && value <= 5) {
      ratings[dimension] = value;
    }
  }
  const rawScore =
    data.score && typeof data.score === "object"
      ? (data.score as Record<string, unknown>)
      : null;

  return {
    id,
    createdAt: timestampIso(data.createdAt),
    ratings,
    score: rawScore
      ? {
          correct: num(rawScore.correct),
          total: num(rawScore.total),
          stars: num(rawScore.stars),
        }
      : null,
    publishedVariantId: str(data.publishedVariantId),
    appVersion: str(data.appVersion),
  };
}
