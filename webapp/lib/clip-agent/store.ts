import "server-only";
import { randomBytes } from "node:crypto";
import { and, desc, eq, inArray } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { clipAgentAttempt } from "@/lib/db/schema";
import { listClipFeedback, setClipFeedbackStatus, type ClipFeedbackRow } from "@/lib/clip-feedback/admin";
import { readClipDraft } from "@/lib/experiments/clips/store";
import { runCost } from "@/lib/experiments/clips/usage-cost";
import type { ClipDraft } from "@/lib/experiments/clips/types";
import { diffSnapshots, type ClipSnapshotDiff } from "@/lib/clip-agent/diff";
import { snapshotClip, type ClipSnapshot } from "@/lib/clip-agent/snapshot";
import { clipFeedbackPlaybook } from "@/lib/clip-agent/playbook";
import {
  agentLabel,
  outcomeResolvesReport,
  resolvedNoteFor,
  type ClipAgentAttemptStatus,
  type ClipAgentOutcome,
  type ClipAgentTarget,
} from "@/lib/clip-agent/schema";
import { deliverAttemptWebhook, type AttemptDelivery } from "@/lib/clip-agent/dispatch";
import { studioPublicBaseUrl } from "@/lib/dialogue/auto-stamp-review-webhook";

/** A pipeline run on the clip while an attempt was open (from the clip's usage log). */
export type AttemptRun = {
  step: string;
  model: string;
  at: string;
  durationMs: number;
  /** Estimate; null for align (our own aligner) or an unknown model. */
  costUsd: number | null;
};

/** One attempt as Studio and the MCP see it. */
export type ClipAgentAttemptView = {
  id: string;
  feedbackId: string;
  clipId: string;
  agent: string;
  agentLabel: string;
  dispatchedBy: string;
  instructions: string | null;
  status: ClipAgentAttemptStatus;
  delivery: AttemptDelivery | null;
  runUrl: string | null;
  outcome: ClipAgentOutcome | null;
  summary: string | null;
  createdAt: string;
  startedAt: string | null;
  finishedAt: string | null;
  /** before → after when finished; before → the clip now while working; null before a claim. */
  diff: ClipSnapshotDiff | null;
  /** True when `diff` and `runs` are against the live clip (attempt still open). */
  live: boolean;
  runs: AttemptRun[];
  costUsd: number;
};

type AttemptRow = typeof clipAgentAttempt.$inferSelect;

export class AttemptError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
    this.name = "AttemptError";
  }
}

/** Usage runs logged on the clip at or after `since`. */
function runsSince(draft: ClipDraft | null, since: Date | null): AttemptRun[] {
  if (!draft || !since) return [];
  return (draft.usage ?? [])
    .filter((run) => new Date(run.at).getTime() >= since.getTime())
    .map((run) => ({
      step: run.step,
      model: run.model,
      at: run.at,
      durationMs: run.durationMs,
      costUsd: runCost(run)?.usd ?? null,
    }));
}

function toView(row: AttemptRow, live: { draft: ClipDraft | null } | null): ClipAgentAttemptView {
  const before = row.before as ClipSnapshot | null;
  let after = row.after as ClipSnapshot | null;
  let runs = (row.runs as AttemptRun[] | null) ?? [];
  if (live) {
    after = live.draft ? snapshotClip(live.draft) : null;
    runs = runsSince(live.draft, row.startedAt);
  }
  return {
    id: row.id,
    feedbackId: row.feedbackId,
    clipId: row.clipId,
    agent: row.agent,
    agentLabel: agentLabel(row.agent),
    dispatchedBy: row.dispatchedBy,
    instructions: row.instructions,
    status: row.status as ClipAgentAttemptStatus,
    delivery: (row.delivery as AttemptDelivery | null) ?? null,
    runUrl: row.runUrl,
    outcome: (row.outcome as ClipAgentOutcome | null) ?? null,
    summary: row.summary,
    createdAt: row.createdAt.toISOString(),
    startedAt: row.startedAt?.toISOString() ?? null,
    finishedAt: row.finishedAt?.toISOString() ?? null,
    diff: before && after ? diffSnapshots(before, after) : null,
    live: Boolean(live),
    runs,
    costUsd: runs.reduce((sum, run) => sum + (run.costUsd ?? 0), 0),
  };
}

/** Attempts for these reports, newest first; open attempts are diffed against the clip now. */
export async function attemptsForFeedback(
  feedbackIds: string[],
): Promise<Map<string, ClipAgentAttemptView[]>> {
  const out = new Map<string, ClipAgentAttemptView[]>();
  if (feedbackIds.length === 0) return out;
  const rows = await db
    .select()
    .from(clipAgentAttempt)
    .where(inArray(clipAgentAttempt.feedbackId, feedbackIds))
    .orderBy(desc(clipAgentAttempt.createdAt));
  const liveClipIds = [...new Set(rows.filter((r) => r.status === "working").map((r) => r.clipId))];
  const drafts = new Map(
    await Promise.all(
      liveClipIds.map(async (id) => [id, await readClipDraft(id).catch(() => null)] as const),
    ),
  );
  for (const row of rows) {
    const view = toView(row, row.status === "working" ? { draft: drafts.get(row.clipId) ?? null } : null);
    out.set(row.feedbackId, [...(out.get(row.feedbackId) ?? []), view]);
  }
  return out;
}

export type ClipFeedbackWithAttempts = ClipFeedbackRow & { attempts: ClipAgentAttemptView[] };

export async function withAttempts(rows: ClipFeedbackRow[]): Promise<ClipFeedbackWithAttempts[]> {
  const attempts = await attemptsForFeedback(rows.filter((r) => r.status !== null).map((r) => r.id));
  return rows.map((row) => ({ ...row, attempts: attempts.get(row.id) ?? [] }));
}

async function openReport(feedbackId: string): Promise<ClipFeedbackRow> {
  const [row] = await listClipFeedback({ id: feedbackId });
  if (!row || row.status === null) throw new AttemptError("No such report.", 404);
  if (row.status !== "open") throw new AttemptError(`The report is ${row.status}, not open.`, 409);
  return row;
}

async function openAttempts(feedbackId: string): Promise<AttemptRow[]> {
  return db
    .select()
    .from(clipAgentAttempt)
    .where(
      and(
        eq(clipAgentAttempt.feedbackId, feedbackId),
        inArray(clipAgentAttempt.status, ["dispatched", "working"]),
      ),
    )
    .orderBy(desc(clipAgentAttempt.createdAt));
}

const newAttemptId = () => `att_${randomBytes(9).toString("base64url")}`;

export function studioClipUrl(clipId: string): string {
  return `${studioPublicBaseUrl()}/experiments/clips/${clipId}`;
}

function clipBrief(draft: ClipDraft) {
  return {
    id: draft.id,
    title: draft.video?.titleEn?.text ?? draft.video?.title ?? null,
    channel: draft.video?.channelName ?? null,
    youtube: `https://www.youtube.com/watch?v=${draft.videoId}&t=${Math.floor(draft.startSec)}s`,
    studioUrl: studioClipUrl(draft.id),
    lines: draft.sentences.length,
    deprecated: Boolean(draft.deprecated),
  };
}

/** The report as an agent needs it (no learner id). */
function reportBrief(row: ClipFeedbackRow) {
  return {
    id: row.id,
    clipId: row.clipId,
    kind: row.kind,
    reason: row.reason,
    note: row.note,
    line: row.line,
    tokenPosition: row.tokenPosition,
    appVersion: row.appVersion,
    createdAt: row.createdAt,
  };
}

/**
 * Studio "Send to agent": records the attempt, then posts the webhook.
 * A failed delivery marks the attempt failed (Studio shows why; send again).
 */
export async function dispatchAttempt(input: {
  feedbackId: string;
  agent: ClipAgentTarget;
  instructions: string | null;
  dispatchedBy: string;
}): Promise<ClipAgentAttemptView> {
  const report = await openReport(input.feedbackId);
  const open = await openAttempts(input.feedbackId);
  if (open.length > 0) {
    const a = open[0];
    throw new AttemptError(`${agentLabel(a.agent)} already has this report (${a.id}, ${a.status}).`, 409);
  }
  const draft = await readClipDraft(report.clipId);
  if (!draft) throw new AttemptError("The clip is gone.", 404);

  const id = newAttemptId();
  const now = new Date();
  await db.insert(clipAgentAttempt).values({
    id,
    feedbackId: report.id,
    clipId: report.clipId,
    agent: input.agent,
    dispatchedBy: input.dispatchedBy,
    instructions: input.instructions,
    status: "dispatched",
    createdAt: now,
    updatedAt: now,
  });

  const delivery = await deliverAttemptWebhook(input.agent, {
    attemptId: id,
    feedbackId: report.id,
    agent: input.agent,
    report: reportBrief(report),
    clip: clipBrief(draft),
    instructions: input.instructions,
    playbook: clipFeedbackPlaybook(report.reason),
    next: [
      `Use the shizen-studio MCP against ${studioPublicBaseUrl()} (STUDIO_BASE_URL, STUDIO_AGENT_TOKEN).`,
      `1. claim_clip_feedback { feedbackId: "${report.id}", runUrl: <this run's link> }.`,
      "2. Follow the playbook.",
      `3. finish_clip_feedback { attemptId: "${id}", outcome, summary }. Always finish, also when you couldn't fix it.`,
    ].join("\n"),
  });

  const [row] = await db
    .update(clipAgentAttempt)
    .set({
      delivery,
      status: delivery.ok ? "dispatched" : "failed",
      ...(delivery.ok ? {} : { finishedAt: new Date(), summary: `Webhook failed: ${delivery.error ?? `HTTP ${delivery.status}`}` }),
      updatedAt: new Date(),
    })
    .where(eq(clipAgentAttempt.id, id))
    .returning();
  return toView(row, null);
}

/**
 * An agent takes a report: picks up its dispatched attempt (webhook path) or
 * opens a new one (asked in chat), and snapshots the clip as `before`.
 * `takeOver` closes a working attempt someone else left behind.
 */
export async function claimAttempt(input: {
  feedbackId: string;
  agent: string | null;
  runUrl: string | null;
  claimedBy: string;
  takeOver: boolean;
}) {
  const report = await openReport(input.feedbackId);
  const open = await openAttempts(input.feedbackId);
  const working = open.filter((a) => a.status === "working");
  if (working.length > 0 && !input.takeOver) {
    const a = working[0];
    throw new AttemptError(
      `${agentLabel(a.agent)} is already working on this report (${a.id}, since ${a.startedAt?.toISOString() ?? "?"}). Pass takeOver: true if that run is dead.`,
      409,
    );
  }
  const draft = await readClipDraft(report.clipId);
  if (!draft) throw new AttemptError("The clip is gone.", 404);

  const now = new Date();
  for (const a of working) {
    await db
      .update(clipAgentAttempt)
      .set({
        status: "done",
        outcome: "could_not_fix",
        summary: `Abandoned: taken over by ${input.agent ?? input.claimedBy}.`,
        after: snapshotClip(draft, now),
        runs: runsSince(draft, a.startedAt),
        finishedAt: now,
        updatedAt: now,
      })
      .where(eq(clipAgentAttempt.id, a.id));
  }

  const before = snapshotClip(draft, now);
  const dispatched = open.find((a) => a.status === "dispatched");
  let row: AttemptRow;
  if (dispatched) {
    [row] = await db
      .update(clipAgentAttempt)
      .set({
        status: "working",
        before,
        runUrl: input.runUrl ?? dispatched.runUrl,
        startedAt: now,
        updatedAt: now,
      })
      .where(eq(clipAgentAttempt.id, dispatched.id))
      .returning();
  } else {
    [row] = await db
      .insert(clipAgentAttempt)
      .values({
        id: newAttemptId(),
        feedbackId: report.id,
        clipId: report.clipId,
        agent: input.agent ?? "agent",
        dispatchedBy: input.claimedBy,
        status: "working",
        before,
        runUrl: input.runUrl,
        createdAt: now,
        startedAt: now,
        updatedAt: now,
      })
      .returning();
  }

  return {
    attemptId: row.id,
    agent: agentLabel(row.agent),
    instructions: row.instructions,
    report: reportBrief(report),
    clip: clipBrief(draft),
    playbook: clipFeedbackPlaybook(report.reason),
    finish: `When done: finish_clip_feedback { attemptId: "${row.id}", outcome: fixed | no_change_needed | needs_review | could_not_fix, summary }.`,
  };
}

/** Closes a working attempt: `after` snapshot, the runs since the claim, and the report's status. */
export async function finishAttempt(input: {
  attemptId: string;
  outcome: ClipAgentOutcome;
  summary: string;
}): Promise<{ attempt: ClipAgentAttemptView; reportResolved: boolean }> {
  const [row] = await db.select().from(clipAgentAttempt).where(eq(clipAgentAttempt.id, input.attemptId)).limit(1);
  if (!row) throw new AttemptError("No such attempt.", 404);
  if (row.status !== "working") {
    throw new AttemptError(`Attempt ${row.id} is ${row.status}, not working (claim it first, or it was taken over).`, 409);
  }
  const draft = await readClipDraft(row.clipId);
  const now = new Date();
  const [done] = await db
    .update(clipAgentAttempt)
    .set({
      status: "done",
      outcome: input.outcome,
      summary: input.summary,
      after: draft ? snapshotClip(draft, now) : null,
      runs: runsSince(draft, row.startedAt),
      finishedAt: now,
      updatedAt: now,
    })
    .where(and(eq(clipAgentAttempt.id, row.id), eq(clipAgentAttempt.status, "working")))
    .returning();
  if (!done) throw new AttemptError(`Attempt ${row.id} changed while finishing; read it again.`, 409);

  let reportResolved = false;
  if (outcomeResolvesReport(input.outcome)) {
    const [report] = await listClipFeedback({ id: row.feedbackId });
    if (report?.status === "open") {
      reportResolved = await setClipFeedbackStatus(
        row.feedbackId,
        "resolved",
        resolvedNoteFor(row.agent, row.id, input.summary),
      );
    }
  }
  return { attempt: toView(done, null), reportResolved };
}
