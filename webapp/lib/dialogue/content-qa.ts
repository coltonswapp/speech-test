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
    dialogueReviewed: z.boolean().optional(),
    quizReviewed: z.boolean().optional(),
    /** Pass null to clear. Omit to leave unchanged. */
    reviewNote: z.string().max(4000).nullable().optional(),
    reviewedBy: z.string().max(200).nullable().optional(),
  })
  .refine(
    (body) =>
      body.dialogueReviewed !== undefined ||
      body.quizReviewed !== undefined ||
      body.reviewNote !== undefined ||
      body.reviewedBy !== undefined,
    { message: "Provide at least one field to update." },
  );

export type UpsertContentQaRequest = z.infer<
  typeof upsertContentQaRequestSchema
>;

export type ContentQaRecord = {
  scenarioId: string;
  collectionId: string;
  dialogueReviewedAt: string | null;
  quizReviewedAt: string | null;
  reviewNote: string | null;
  reviewedBy: string | null;
  status: ContentQaStatus;
  createdAt: string;
  updatedAt: string;
};

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
  return {
    scenarioId: row.scenarioId,
    collectionId,
    dialogueReviewedAt: row.dialogueReviewedAt?.toISOString() ?? null,
    quizReviewedAt: row.quizReviewedAt?.toISOString() ?? null,
    reviewNote: row.reviewNote,
    reviewedBy: row.reviewedBy,
    status: contentQaStatusFromFlags(row),
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
  };
}
