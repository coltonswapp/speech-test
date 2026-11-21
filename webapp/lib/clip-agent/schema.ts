/**
 * Agent attempts at learner clip reports (docs/clip-agent-tickets-plan.md).
 * One row per try: who took it, the clip before and after, and the outcome.
 * Pure: no DB, so it's testable.
 */
import { z } from "zod";

export const CLIP_AGENT_TARGETS = ["grokbot", "openbot"] as const;
export type ClipAgentTarget = (typeof CLIP_AGENT_TARGETS)[number];

export const CLIP_AGENT_TARGET_LABELS: Record<ClipAgentTarget, string> = {
  grokbot: "Grok Bot",
  openbot: "OpenBot",
};

export const CLIP_AGENT_ATTEMPT_STATUSES = ["dispatched", "working", "done", "failed"] as const;
export type ClipAgentAttemptStatus = (typeof CLIP_AGENT_ATTEMPT_STATUSES)[number];

export const CLIP_AGENT_OUTCOMES = [
  "fixed", // changed the clip; report resolved
  "no_change_needed", // the clip was already right; report resolved
  "needs_review", // unsure: a person compares and accepts; report stays open
  "could_not_fix", // report stays open
] as const;
export type ClipAgentOutcome = (typeof CLIP_AGENT_OUTCOMES)[number];

/** Outcomes that resolve the report on finish. */
export function outcomeResolvesReport(outcome: ClipAgentOutcome): boolean {
  return outcome === "fixed" || outcome === "no_change_needed";
}

/** Display name for an attempt's agent (a target, or whatever a claiming agent called itself). */
export function agentLabel(agent: string): string {
  return (CLIP_AGENT_TARGET_LABELS as Record<string, string>)[agent] ?? agent;
}

/** Resolved-note text: "Grok Bot · att_… · first line of the summary". */
export function resolvedNoteFor(agent: string, attemptId: string, summary: string): string {
  const first = summary.trim().split("\n")[0]?.trim() ?? "";
  const note = `${agentLabel(agent)} · ${attemptId}${first ? ` · ${first}` : ""}`;
  return note.length > 900 ? `${note.slice(0, 899)}…` : note;
}

const agentName = z
  .string()
  .trim()
  .min(1)
  .max(40)
  .regex(/^[A-Za-z0-9 ._-]+$/, "letters, digits, space, . _ -");
const runUrl = z.string().trim().url().max(1_000);

export const dispatchBodySchema = z.object({
  agent: z.enum(CLIP_AGENT_TARGETS),
  instructions: z.string().trim().max(2_000).optional(),
});

export const claimBodySchema = z.object({
  agent: agentName.optional(),
  runUrl: runUrl.optional(),
});

export const finishBodySchema = z.object({
  outcome: z.enum(CLIP_AGENT_OUTCOMES),
  summary: z.string().trim().min(1).max(4_000),
});

export const CLIP_AGENT_ATTEMPT_DDL = `
CREATE TABLE IF NOT EXISTS clip_agent_attempt (
  id text PRIMARY KEY,
  feedback_id text NOT NULL,
  clip_id text NOT NULL,
  agent text NOT NULL,
  dispatched_by text NOT NULL,
  instructions text,
  status text NOT NULL,
  delivery jsonb,
  run_url text,
  before jsonb,
  after jsonb,
  outcome text,
  summary text,
  runs jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  started_at timestamp with time zone,
  finished_at timestamp with time zone,
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS clip_agent_attempt_feedback_idx ON clip_agent_attempt (feedback_id, created_at);
CREATE INDEX IF NOT EXISTS clip_agent_attempt_clip_idx ON clip_agent_attempt (clip_id);
CREATE INDEX IF NOT EXISTS clip_agent_attempt_status_idx ON clip_agent_attempt (status);
`;
