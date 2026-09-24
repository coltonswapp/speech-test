import "server-only";

import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import {
  dialogueScenario,
  dialogueScenarioContentQa,
} from "@/lib/db/schema";
import {
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
 */
export async function upsertContentQa(
  scenarioId: string,
  body: UpsertContentQaRequest,
): Promise<{ record: ContentQaRecord; created: boolean }> {
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
  const now = new Date();

  let dialogueReviewedAt = existing?.dialogueReviewedAt ?? null;
  let quizReviewedAt = existing?.quizReviewedAt ?? null;
  let reviewNote = existing?.reviewNote ?? null;
  let reviewedBy = existing?.reviewedBy ?? null;

  if (body.dialogueReviewed === true && !dialogueReviewedAt) {
    dialogueReviewedAt = now;
  } else if (body.dialogueReviewed === false) {
    dialogueReviewedAt = null;
  }

  if (body.quizReviewed === true && !quizReviewedAt) {
    quizReviewedAt = now;
  } else if (body.quizReviewed === false) {
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
    return { record: toContentQaRecord(inserted), created: true };
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

  return { record: toContentQaRecord(updated), created: false };
}

export class ContentQaNotFoundError extends Error {
  constructor(scenarioId: string) {
    super(`Scenario "${scenarioId}" not found.`);
    this.name = "ContentQaNotFoundError";
  }
}
