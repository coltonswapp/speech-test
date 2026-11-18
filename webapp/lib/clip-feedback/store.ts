import "server-only";
import { randomBytes } from "node:crypto";
import { and, count, eq, gte, sql } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { clipFeedback, clipIndex } from "@/lib/db/schema";
import {
  DAILY_FEEDBACK_LIMIT,
  initialStatus,
  type ClipFeedbackRequest,
  type ClipFeedbackStatus,
} from "@/lib/clip-feedback/schema";

export type SaveFeedbackResult =
  | { ok: true; id: string; status: ClipFeedbackStatus | null }
  | { ok: false; error: "unknown_clip" | "rate_limited" };

/**
 * Saves one learner write. A rating replaces that learner's earlier rating
 * on the clip (they can flip thumbs); a flag is always a new row.
 */
export async function saveClipFeedback(
  uid: string,
  clipId: string,
  body: ClipFeedbackRequest,
): Promise<SaveFeedbackResult> {
  const [clip] = await db
    .select({ id: clipIndex.id })
    .from(clipIndex)
    .where(and(eq(clipIndex.id, clipId), eq(clipIndex.listed, true)))
    .limit(1);
  if (!clip) return { ok: false, error: "unknown_clip" };

  const since = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const [{ n }] = await db
    .select({ n: count() })
    .from(clipFeedback)
    .where(and(eq(clipFeedback.userId, uid), gte(clipFeedback.updatedAt, since)));
  if (n >= DAILY_FEEDBACK_LIMIT) return { ok: false, error: "rate_limited" };

  const status = initialStatus(body);
  const now = new Date();
  const fields = {
    rating: body.rating ?? null,
    reason: body.reason ?? null,
    note: body.note || null,
    sentenceIndex: body.line?.index ?? null,
    tokenPosition: body.tokenPosition ?? null,
    snapshot: body.line ?? null,
    appVersion: body.app?.version ?? null,
    appBuild: body.app?.build ?? null,
    status,
    updatedAt: now,
  };
  const id = `cfb_${randomBytes(9).toString("base64url")}`;

  if (body.kind === "rating") {
    const [row] = await db
      .insert(clipFeedback)
      .values({ id, clipId, userId: uid, kind: "rating", ...fields })
      .onConflictDoUpdate({
        target: [clipFeedback.clipId, clipFeedback.userId],
        targetWhere: sql`kind = 'rating'`,
        // A flipped vote reopens triage only if it's a new thumbs-down with a reason.
        set: { ...fields, resolvedAt: null, resolvedNote: null },
      })
      .returning({ id: clipFeedback.id });
    return { ok: true, id: row.id, status };
  }

  await db.insert(clipFeedback).values({ id, clipId, userId: uid, kind: "flag", ...fields });
  return { ok: true, id, status };
}
