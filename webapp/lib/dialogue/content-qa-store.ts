import "server-only";

import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import {
  dialogueScenario,
  dialogueScenarioContentQa,
} from "@/lib/db/schema";
import {
  shouldClearContentQaOnSelectedTakeChange,
  toContentQaRecord,
  type ContentQaRecord,
  type UpsertContentQaRequest,
} from "@/lib/dialogue/content-qa";

export async function getContentQaByScenarioId(
  scenarioId: string,
): Promise<ContentQaRecord | null> {
  const row = await db.query.dialogueScenarioContentQa.findFirst({
    where: eq(dialogueScenarioContentQa.scenarioId, scenarioId),
  });
  return row ? toContentQaRecord(row) : null;
}

export async function listContentQa(params?: {
  collectionId?: string;
}): Promise<ContentQaRecord[]> {
  const rows = await db.query.dialogueScenarioContentQa.findMany();
  const records = rows.map(toContentQaRecord);
  if (!params?.collectionId) return records;
  return records.filter((row) => row.collectionId === params.collectionId);
}

/**
 * Upsert content QA for a scenario. Idempotent for flags already true:
 * first-reviewed timestamps are kept unless the flag is explicitly cleared.
 *
 * `checkedOff: true` sets both dialogue + quiz reviewed (scene check-off).
 * `checkedOff: false` clears both.
 */
export async function upsertContentQa(
  scenarioId: string,
  body: UpsertContentQaRequest,
): Promise<{
  record: ContentQaRecord;
  created: boolean;
  alreadyCheckedOff: boolean;
}> {
  const scenario = await db.query.dialogueScenario.findFirst({
    where: eq(dialogueScenario.id, scenarioId),
    columns: { id: true },
  });
  if (!scenario) {
    throw new ContentQaNotFoundError(scenarioId);
  }

  const existing = await db.query.dialogueScenarioContentQa.findFirst({
    where: eq(dialogueScenarioContentQa.scenarioId, scenarioId),
  });
  const alreadyCheckedOff = !!(
    existing?.dialogueReviewedAt && existing?.quizReviewedAt
  );
  const now = new Date();

  let dialogueReviewedAt = existing?.dialogueReviewedAt ?? null;
  let quizReviewedAt = existing?.quizReviewedAt ?? null;
  let reviewNote = existing?.reviewNote ?? null;
  let reviewedBy = existing?.reviewedBy ?? null;

  const dialogueReviewed =
    body.checkedOff === true
      ? true
      : body.checkedOff === false
        ? false
        : body.dialogueReviewed;
  const quizReviewed =
    body.checkedOff === true
      ? true
      : body.checkedOff === false
        ? false
        : body.quizReviewed;

  if (dialogueReviewed === true && !dialogueReviewedAt) {
    dialogueReviewedAt = now;
  } else if (dialogueReviewed === false) {
    dialogueReviewedAt = null;
  }

  if (quizReviewed === true && !quizReviewedAt) {
    quizReviewedAt = now;
  } else if (quizReviewed === false) {
    quizReviewedAt = null;
  }

  if (body.reviewNote !== undefined) {
    reviewNote = body.reviewNote;
  }
  if (body.reviewedBy !== undefined) {
    reviewedBy = body.reviewedBy;
  }

  if (!existing) {
    const [inserted] = await db
      .insert(dialogueScenarioContentQa)
      .values({
        scenarioId,
        dialogueReviewedAt,
        quizReviewedAt,
        reviewNote,
        reviewedBy,
        createdAt: now,
        updatedAt: now,
      })
      .returning();
    return {
      record: toContentQaRecord(inserted),
      created: true,
      alreadyCheckedOff: false,
    };
  }

  const [updated] = await db
    .update(dialogueScenarioContentQa)
    .set({
      dialogueReviewedAt,
      quizReviewedAt,
      reviewNote,
      reviewedBy,
      updatedAt: now,
    })
    .where(eq(dialogueScenarioContentQa.scenarioId, scenarioId))
    .returning();

  return {
    record: toContentQaRecord(updated),
    created: false,
    alreadyCheckedOff,
  };
}

/**
 * Scene check-off: mark dialogue + quiz reviewed. Idempotent when already done.
 */
export async function checkOffContentQa(
  scenarioId: string,
  body: { reviewNote?: string | null; reviewedBy?: string | null } = {},
): Promise<{
  record: ContentQaRecord;
  created: boolean;
  alreadyCheckedOff: boolean;
}> {
  return upsertContentQa(scenarioId, {
    checkedOff: true,
    reviewNote: body.reviewNote,
    reviewedBy: body.reviewedBy,
  });
}

/**
 * Invalidate Content QA when a scenario’s selected take changes.
 *
 * Matches `checkedOff: false`: clears `dialogue_reviewed_at` + `quiz_reviewed_at`
 * only. Leaves `review_note` / `reviewed_by` unchanged.
 *
 * No-ops when:
 * - `scenarioId` is missing (ad-hoc TTS project, not scenario-backed)
 * - previous and next take ids are the same (including both null)
 * - no Content QA row exists yet (nothing to clear)
 */
export async function clearContentQaIfSelectedTakeChanged(params: {
  scenarioId: string | null | undefined;
  previousSelectedTakeId: string | null | undefined;
  nextSelectedTakeId: string | null | undefined;
}): Promise<{ cleared: boolean }> {
  if (!params.scenarioId) return { cleared: false };
  if (
    !shouldClearContentQaOnSelectedTakeChange(
      params.previousSelectedTakeId,
      params.nextSelectedTakeId,
    )
  ) {
    return { cleared: false };
  }

  const existing = await getContentQaByScenarioId(params.scenarioId);
  if (!existing) return { cleared: false };
  if (!existing.dialogueReviewedAt && !existing.quizReviewedAt) {
    return { cleared: false };
  }

  await upsertContentQa(params.scenarioId, { checkedOff: false });
  return { cleared: true };
}

export class ContentQaNotFoundError extends Error {
  constructor(scenarioId: string) {
    super(`Scenario "${scenarioId}" not found.`);
    this.name = "ContentQaNotFoundError";
  }
}
