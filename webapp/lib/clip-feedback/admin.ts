import "server-only";
import { and, desc, eq, inArray, isNotNull, sql, type SQL } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { clipAgentAttempt, clipFeedback, clipIndex } from "@/lib/db/schema";
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
  cursorTimestamp: string;
};

export type ClipFeedbackQuery = {
  /** One report by id (any status). */
  id?: string | null;
  clipId?: string | null;
  /** "issues": anything with a status (flags, reasoned thumbs-downs). "all": ratings too. */
  status?: ClipFeedbackStatus | "issues" | "all";
  reason?: ClipFeedbackReason | null;
  before?: { timestamp: string; id?: string; inclusive?: boolean };
  limit?: number;
  /**
   * Open reports whose latest done/working attempt finished `needs_review`.
   * The report status stays `open`; this is derived from clip_agent_attempt.
   */
  latestNeedsReview?: boolean;
};

function mapClipFeedbackRow(
  f: typeof clipFeedback.$inferSelect,
  summary: ClipSummary | null,
  cursorTimestamp: string,
): ClipFeedbackRow {
  return {
    id: f.id,
    cursorTimestamp,
    clipId: f.clipId,
    videoId: summary?.videoId ?? null,
    videoStartSec: summary?.startSec ?? 0,
    clipTitle: summary ? (summary.videoTitleEn ?? summary.videoTitle) : null,
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
}

export async function listClipFeedback(q: ClipFeedbackQuery): Promise<ClipFeedbackRow[]> {
  const where: SQL[] = [];
  if (q.id) where.push(eq(clipFeedback.id, q.id));
  if (q.clipId) where.push(eq(clipFeedback.clipId, q.clipId));
  const status = q.status ?? (q.id ? "all" : "issues");
  if (q.latestNeedsReview) where.push(eq(clipFeedback.status, "open"));
  else if (status === "issues") where.push(isNotNull(clipFeedback.status));
  else if (status !== "all") where.push(eq(clipFeedback.status, status));
  if (q.reason) where.push(eq(clipFeedback.reason, q.reason));

  if (q.before) {
    const { timestamp, id, inclusive } = q.before;
    const comparison = inclusive ? sql`<=` : sql`<`;
    where.push(id === undefined
      ? sql`${clipFeedback.createdAt} ${comparison} ${timestamp}::timestamptz`
      : sql`(${clipFeedback.createdAt}, ${clipFeedback.id}) < (${timestamp}::timestamptz, ${id})`);
  }

  const columns = {
    feedback: clipFeedback,
    summary: clipIndex.summary,
    cursorTimestamp: sql<string>`to_char(${clipFeedback.createdAt} AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"000Z"')`,
  };
  const limit = Math.min(q.limit ?? 200, 500);
  const filter = where.length ? and(...where) : undefined;

  if (q.latestNeedsReview) {
    const latestAttempt = db
      .selectDistinctOn([clipAgentAttempt.feedbackId], {
        feedbackId: clipAgentAttempt.feedbackId,
        status: clipAgentAttempt.status,
        outcome: clipAgentAttempt.outcome,
      })
      .from(clipAgentAttempt)
      .where(inArray(clipAgentAttempt.status, ["done", "working"]))
      .orderBy(clipAgentAttempt.feedbackId, desc(clipAgentAttempt.createdAt))
      .as("latest_clip_attempt");
    const rows = await db
      .select(columns)
      .from(clipFeedback)
      .innerJoin(
        latestAttempt,
        and(
          eq(clipFeedback.id, latestAttempt.feedbackId),
          eq(latestAttempt.status, "done"),
          eq(latestAttempt.outcome, "needs_review"),
        ),
      )
      .leftJoin(clipIndex, eq(clipIndex.id, clipFeedback.clipId))
      .where(filter)
      .orderBy(desc(clipFeedback.createdAt), desc(clipFeedback.id))
      .limit(limit);
    return rows.map(({ feedback: f, summary, cursorTimestamp }) =>
      mapClipFeedbackRow(f, summary as ClipSummary | null, cursorTimestamp),
    );
  }

  const rows = await db
    .select(columns)
    .from(clipFeedback)
    .leftJoin(clipIndex, eq(clipIndex.id, clipFeedback.clipId))
    .where(filter)
    .orderBy(desc(clipFeedback.createdAt), desc(clipFeedback.id))
    .limit(limit);

  return rows.map(({ feedback: f, summary, cursorTimestamp }) =>
    mapClipFeedbackRow(f, summary as ClipSummary | null, cursorTimestamp),
  );
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

