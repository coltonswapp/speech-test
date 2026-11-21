import "server-only";
import { and, desc, eq, isNotNull, sql, type SQL } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { clipFeedback, clipIndex } from "@/lib/db/schema";
import type { ClipSummary } from "@/lib/experiments/clips/types";
import type { ClipFeedbackReason, ClipFeedbackStatus, ClipLineSnapshot } from "@/lib/clip-feedback/schema";

/** One learner write as Studio shows it (rows from POST /api/client/clips/[id]/feedback). */
export type ClipFeedbackRow = {
  id: string;
  clipId: string;
  /** From the clip index; null when the clip is gone from it. */
  clipTitle: string | null;
  videoId: string | null;
  videoStartSec: number;
  userId: string;
  kind: "rating" | "flag";
  rating: "up" | "down" | null;
  reason: ClipFeedbackReason | null;
  note: string | null;
  sentenceIndex: number | null;
  tokenPosition: number | null;
  line: ClipLineSnapshot | null;
  appVersion: string | null;
  appBuild: string | null;
  status: ClipFeedbackStatus | null;
  resolvedAt: string | null;
  resolvedNote: string | null;
  createdAt: string;
  updatedAt: string;
};

export type ClipFeedbackQuery = {
  /** One report by id (any status). */
  id?: string | null;
  clipId?: string | null;
  /** "issues": anything with a status (flags, reasoned thumbs-downs). "all": ratings too. */
  status?: ClipFeedbackStatus | "issues" | "all";
  reason?: ClipFeedbackReason | null;
  offset?: number;
  limit?: number;
};

export async function listClipFeedback(q: ClipFeedbackQuery): Promise<ClipFeedbackRow[]> {
  const where: SQL[] = [];
  if (q.id) where.push(eq(clipFeedback.id, q.id));
  if (q.clipId) where.push(eq(clipFeedback.clipId, q.clipId));
  const status = q.status ?? (q.id ? "all" : "issues");
  if (status === "issues") where.push(isNotNull(clipFeedback.status));
  else if (status !== "all") where.push(eq(clipFeedback.status, status));
  if (q.reason) where.push(eq(clipFeedback.reason, q.reason));

  const rows = await db
    .select({ feedback: clipFeedback, summary: clipIndex.summary })
    .from(clipFeedback)
    .leftJoin(clipIndex, eq(clipIndex.id, clipFeedback.clipId))
    .where(where.length ? and(...where) : undefined)
    .orderBy(desc(clipFeedback.createdAt), desc(clipFeedback.id))
    .offset(q.offset ?? 0)
    .limit(Math.min(q.limit ?? 200, 500));

  return rows.map(({ feedback: f, summary }) => {
    const s = summary as ClipSummary | null;
    return {
      id: f.id,
      clipId: f.clipId,
      videoId: s?.videoId ?? null,
      videoStartSec: s?.startSec ?? 0,
      clipTitle: s ? (s.videoTitleEn ?? s.videoTitle) : null,
      userId: f.userId,
      kind: f.kind as ClipFeedbackRow["kind"],
      rating: f.rating as ClipFeedbackRow["rating"],
      reason: f.reason as ClipFeedbackRow["reason"],
      note: f.note,
      sentenceIndex: f.sentenceIndex,
      tokenPosition: f.tokenPosition,
      line: (f.snapshot as ClipLineSnapshot | null) ?? null,
      appVersion: f.appVersion,
      appBuild: f.appBuild,
      status: f.status as ClipFeedbackRow["status"],
      resolvedAt: f.resolvedAt?.toISOString() ?? null,
      resolvedNote: f.resolvedNote,
      createdAt: f.createdAt.toISOString(),
      updatedAt: f.updatedAt.toISOString(),
    };
  });
}

export type ClipRatingCounts = { up: number; down: number; openIssues: number };

/** Thumbs totals and open issues for one clip. */
export async function clipFeedbackCounts(clipId: string): Promise<ClipRatingCounts> {
  const [row] = await db
    .select({
      up: sql<number>`count(*) filter (where ${clipFeedback.kind} = 'rating' and ${clipFeedback.rating} = 'up')::int`,
      down: sql<number>`count(*) filter (where ${clipFeedback.kind} = 'rating' and ${clipFeedback.rating} = 'down')::int`,
      openIssues: sql<number>`count(*) filter (where ${clipFeedback.status} = 'open')::int`,
    })
    .from(clipFeedback)
    .where(eq(clipFeedback.clipId, clipId));
  return row ?? { up: 0, down: 0, openIssues: 0 };
}

/** Open issues across all clips (for the inbox link). */
export async function openClipIssueCount(): Promise<number> {
  const [row] = await db
    .select({ n: sql<number>`count(*)::int` })
    .from(clipFeedback)
    .where(eq(clipFeedback.status, "open"));
  return row?.n ?? 0;
}

/**
 * Triage: resolve, won't fix, duplicate, or reopen. Plain ratings (no status)
 * aren't issues, so they're left alone. Returns false when no issue matched.
 */
export async function setClipFeedbackStatus(
  id: string,
  status: ClipFeedbackStatus,
  note: string | null,
): Promise<boolean> {
  const now = new Date();
  const closed = status !== "open";
  const updated = await db
    .update(clipFeedback)
    .set({
      status,
      resolvedAt: closed ? now : null,
      resolvedNote: closed ? note : null,
      updatedAt: now,
    })
    .where(and(eq(clipFeedback.id, id), isNotNull(clipFeedback.status)))
    .returning({ id: clipFeedback.id });
  return updated.length > 0;
}

