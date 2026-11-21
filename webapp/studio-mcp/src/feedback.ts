// Learner clip feedback for agents: find flagged clips, take a report, fix
// the clip with the clip tools, and close it with an outcome. Every take is
// an attempt in Studio with server-side before/after snapshots of the clip
// (docs/clip-agent-tickets-plan.md), so a person can see what changed.
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { studioBaseUrl, studioFetch } from "./client.ts";

const REASONS = ["translation", "tokenization", "reading", "timing", "video", "other"] as const;
const STATUSES = ["open", "resolved", "wontfix", "duplicate", "issues"] as const;
const OUTCOMES = ["fixed", "no_change_needed", "needs_review", "could_not_fix"] as const;

type Attempt = {
  id: string;
  agentLabel: string;
  status: string;
  outcome: string | null;
  summary: string | null;
  runUrl: string | null;
  startedAt: string | null;
  finishedAt: string | null;
  diff: { empty: boolean; lines: unknown[]; fields: unknown[] } | null;
};

type FeedbackRow = {
  id: string;
  clipId: string;
  clipTitle: string | null;
  kind: string;
  rating: string | null;
  reason: string | null;
  note: string | null;
  tokenPosition: number | null;
  line: {
    index: number;
    textJP: string;
    textEN?: string | null;
    tokens?: Array<{ position: number; surface: string; reading?: string | null }>;
  } | null;
  status: string | null;
  resolvedNote: string | null;
  createdAt: string;
  attempts: Attempt[];
};

function jsonResult(data: unknown) {
  return { content: [{ type: "text" as const, text: JSON.stringify(data, null, 2) }] };
}

function errorResult(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  return { isError: true, content: [{ type: "text" as const, text: message }] };
}

function brief(row: FeedbackRow) {
  const word =
    row.tokenPosition != null ? row.line?.tokens?.find((t) => t.position === row.tokenPosition) : undefined;
  return {
    id: row.id,
    clipId: row.clipId,
    clipTitle: row.clipTitle,
    reason: row.reason ?? (row.rating === "down" ? "thumbs down" : null),
    note: row.note,
    line: row.line
      ? { index: row.line.index, ja: row.line.textJP, en: row.line.textEN ?? null }
      : "whole clip",
    ...(word ? { word: word.reading ? `${word.surface} (${word.reading})` : word.surface } : {}),
    status: row.status,
    ...(row.resolvedNote ? { resolvedNote: row.resolvedNote } : {}),
    reportedAt: row.createdAt,
    attempts: row.attempts.map((a) => ({
      id: a.id,
      agent: a.agentLabel,
      status: a.status,
      ...(a.outcome ? { outcome: a.outcome } : {}),
      ...(a.summary ? { summary: a.summary.split("\n")[0] } : {}),
      ...(a.diff ? { changedLines: a.diff.lines.length, changedFields: a.diff.fields.length } : {}),
    })),
    studio: `${studioBaseUrl()}/experiments/clips/${row.clipId}`,
  };
}

export function registerFeedbackTools(server: McpServer) {
  server.registerTool(
    "list_clip_feedback",
    {
      title: "List flagged clips",
      description: [
        "Learner reports on clips from the app (\"Report an issue\", thumbs-down with a reason), newest first, each with its agent attempts.",
        "status: open (default) | resolved | wontfix | duplicate | issues (any). reason: translation | tokenization | reading | timing | video | other. clipId narrows to one clip.",
        "To work a report: claim_clip_feedback, fix it with the clip tools following the playbook it returns, then finish_clip_feedback. Skip reports whose latest attempt is working.",
      ].join("\n"),
      inputSchema: {
        status: z.enum(STATUSES).default("open"),
        reason: z.enum(REASONS).optional(),
        clipId: z.string().optional(),
      },
    },
    async ({ status, reason, clipId }) => {
      try {
        const query = new URLSearchParams({ status });
        if (reason) query.set("reason", reason);
        if (clipId) query.set("clip_id", clipId);
        const { rows, openIssues } = await studioFetch<{ rows: FeedbackRow[]; openIssues: number }>(
          `/api/experiments/clip-feedback?${query}`,
        );
        const reports = rows.filter((r) => r.status !== null).map(brief);
        return jsonResult({ openIssues, shown: reports.length, reports });
      } catch (error) {
        return errorResult(error);
      }
    },
  );

  server.registerTool(
    "claim_clip_feedback",
    {
      title: "Take a clip report",
      description: [
        "Start work on one open report: Studio opens an attempt (or picks up the one dispatched to you), snapshots the clip, and returns the report, the clip and the playbook for its reason. Returns attemptId for finish_clip_feedback.",
        "agent: your name as Studio should show it (e.g. claude, grokbot, openbot). runUrl: a link to this run/session, if you have one.",
        "Fails while another attempt is working on the report; takeOver: true only when that run is clearly dead.",
        "Work one report at a time: finish before claiming the next.",
      ].join("\n"),
      inputSchema: {
        feedbackId: z.string().min(1),
        agent: z.string().max(40).optional(),
        runUrl: z.string().url().optional(),
        takeOver: z.boolean().optional(),
      },
    },
    async ({ feedbackId, ...body }) => {
      try {
        return jsonResult(
          await studioFetch(`/api/experiments/clip-feedback/${encodeURIComponent(feedbackId)}/claim`, {
            method: "POST",
            body: JSON.stringify(body),
          }),
        );
      } catch (error) {
        return errorResult(error);
      }
    },
  );

  server.registerTool(
    "finish_clip_feedback",
    {
      title: "Close a clip report attempt",
      description: [
        "Close your attempt. Studio snapshots the clip again and shows the before/after diff and the pipeline runs you made.",
        "outcome: fixed (report resolved) | no_change_needed (clip was right; resolved) | needs_review (unsure: a person compares; report stays open) | could_not_fix (report stays open).",
        "summary: first line = cause and fix in one sentence (it becomes the resolved note); then details, including anything a reviewer should compare.",
        "Always call this, also when you give up.",
      ].join("\n"),
      inputSchema: {
        attemptId: z.string().min(1),
        outcome: z.enum(OUTCOMES),
        summary: z.string().min(1).max(4000),
      },
    },
    async ({ attemptId, outcome, summary }) => {
      try {
        const { attempt, reportResolved } = await studioFetch<{ attempt: Attempt; reportResolved: boolean }>(
          `/api/experiments/clip-agent-attempts/${encodeURIComponent(attemptId)}/finish`,
          { method: "POST", body: JSON.stringify({ outcome, summary }) },
        );
        return jsonResult({
          attemptId: attempt.id,
          outcome: attempt.outcome,
          reportResolved,
          diff: attempt.diff,
        });
      } catch (error) {
        return errorResult(error);
      }
    },
  );
}
