import { z } from "zod";

/**
 * Learner-client content QA — not Studio take review.
 *
 * - dialogueReviewed: reviewer looked over the spoken dialogue / lines.
 * - quizReviewed: reviewer looked over the quiz questions.
 * - reviewNote: freeform note persisted for Studio chips / tooltips.
 */

export const contentQaStatusSchema = z.enum([
  "pending",
  "dialogue",
  "quiz",
  "done",
]);
export type ContentQaStatus = z.infer<typeof contentQaStatusSchema>;

/** Scenario id is "<collectionId>/<slug>" (same as dialogue_scenario.id). */
export const contentQaScenarioIdSchema = z
  .string()
  .min(3)
  .regex(/^[^/]+\/[^/]+$/, 'Expected scenario id "collectionId/slug"');

export const upsertContentQaRequestSchema = z
  .object({
    /**
     * Scene-level check-off shorthand. `true` sets both dialogueReviewed and
     * quizReviewed. `false` clears both. Prefer POST …/check-off for the
     * client “mark scene reviewed” action.
     */
    checkedOff: z.boolean().optional(),
    dialogueReviewed: z.boolean().optional(),
    quizReviewed: z.boolean().optional(),
    /** Pass null to clear. Omit to leave unchanged. */
    reviewNote: z.string().max(4000).nullable().optional(),
    reviewedBy: z.string().max(200).nullable().optional(),
  })
  .refine(
    (body) =>
      body.checkedOff !== undefined ||
      body.dialogueReviewed !== undefined ||
      body.quizReviewed !== undefined ||
      body.reviewNote !== undefined ||
      body.reviewedBy !== undefined,
    { message: "Provide at least one field to update." },
  );

export type UpsertContentQaRequest = z.infer<
  typeof upsertContentQaRequestSchema
>;

/** Body for POST …/check-off — marks the whole scene reviewed. */
export const checkOffContentQaRequestSchema = z.object({
  reviewNote: z.string().max(4000).nullable().optional(),
  reviewedBy: z.string().max(200).nullable().optional(),
});

export type CheckOffContentQaRequest = z.infer<
  typeof checkOffContentQaRequestSchema
>;

export type ContentQaRecord = {
  scenarioId: string;
  collectionId: string;
  dialogueReviewedAt: string | null;
  quizReviewedAt: string | null;
  reviewNote: string | null;
  reviewedBy: string | null;
  status: ContentQaStatus;
  /** True when both dialogue + quiz are reviewed (`status === "done"`). */
  checkedOff: boolean;
  createdAt: string;
  updatedAt: string;
};

/** Chip-facing slice returned alongside write responses. */
export type ContentQaReadinessSlice = {
  contentQa: ContentQaStatus;
  contentQaHasNote: boolean;
  checkedOff: boolean;
};

export function contentQaReadinessSlice(
  record: Pick<ContentQaRecord, "status" | "reviewNote" | "checkedOff">,
): ContentQaReadinessSlice {
  return {
    contentQa: record.status,
    contentQaHasNote: !!record.reviewNote?.trim(),
    checkedOff: record.checkedOff,
  };
}

export function contentQaStatusFromFlags(params: {
  dialogueReviewedAt: Date | string | null | undefined;
  quizReviewedAt: Date | string | null | undefined;
}): ContentQaStatus {
  const dialogue = !!params.dialogueReviewedAt;
  const quiz = !!params.quizReviewedAt;
  if (dialogue && quiz) return "done";
  if (dialogue) return "dialogue";
  if (quiz) return "quiz";
  return "pending";
}

/**
 * True when the scenario’s selected take id actually changed.
 * Same id re-saved (including both null) is a no-op for Content QA.
 */
export function shouldClearContentQaOnSelectedTakeChange(
  previousSelectedTakeId: string | null | undefined,
  nextSelectedTakeId: string | null | undefined,
): boolean {
  const previous = previousSelectedTakeId ?? null;
  const next = nextSelectedTakeId ?? null;
  return previous !== next;
}

export function toContentQaRecord(row: {
  scenarioId: string;
  dialogueReviewedAt: Date | null;
  quizReviewedAt: Date | null;
  reviewNote: string | null;
  reviewedBy: string | null;
  createdAt: Date;
  updatedAt: Date;
}): ContentQaRecord {
  const slash = row.scenarioId.indexOf("/");
  const collectionId =
    slash > 0 ? row.scenarioId.slice(0, slash) : row.scenarioId;
  const status = contentQaStatusFromFlags(row);
  return {
    scenarioId: row.scenarioId,
    collectionId,
    dialogueReviewedAt: row.dialogueReviewedAt?.toISOString() ?? null,
    quizReviewedAt: row.quizReviewedAt?.toISOString() ?? null,
    reviewNote: row.reviewNote,
    reviewedBy: row.reviewedBy,
    status,
    checkedOff: status === "done",
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
  };
}
