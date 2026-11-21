/**
 * Learner clip feedback: a thumbs rating on a clip, or a flagged issue
 * ("report an issue") on the clip or one of its lines.
 * Body of POST /api/client/clips/[id]/feedback. Pure: no DB, so it's testable.
 */
import { z } from "zod";

export const CLIP_FEEDBACK_REASONS = [
  "translation", // English is wrong
  "tokenization", // words split wrong
  "reading", // wrong furigana / reading
  "timing", // subtitles or karaoke out of sync
  "video", // video won't play, wrong part, inappropriate
  "other",
] as const;
export type ClipFeedbackReason = (typeof CLIP_FEEDBACK_REASONS)[number];

export const CLIP_FEEDBACK_STATUSES = ["open", "resolved", "wontfix", "duplicate"] as const;
export type ClipFeedbackStatus = (typeof CLIP_FEEDBACK_STATUSES)[number];

/** The line as the learner saw it. Clips get re-aligned, so this keeps a report readable. */
const lineSnapshotSchema = z.object({
  index: z.number().int().min(0).max(10_000),
  startSec: z.number().finite().min(0),
  endSec: z.number().finite().min(0),
  textJP: z.string().max(1_000),
  textEN: z.string().max(2_000).nullish(),
  tokens: z
    .array(
      z.object({
        position: z.number().int().min(0),
        surface: z.string().max(100),
        reading: z.string().max(200).nullish(),
      }),
    )
    .max(300)
    .optional(),
});
export type ClipLineSnapshot = z.infer<typeof lineSnapshotSchema>;

export const clipFeedbackRequestSchema = z
  .object({
    kind: z.enum(["rating", "flag"]),
    rating: z.enum(["up", "down"]).optional(),
    reason: z.enum(CLIP_FEEDBACK_REASONS).optional(),
    note: z.string().trim().max(1_000).optional(),
    /** Set when the learner reported from a line (the line breakdown screen). */
    line: lineSnapshotSchema.optional(),
    /** A specific word in `line`. */
    tokenPosition: z.number().int().min(0).optional(),
    app: z
      .object({
        version: z.string().max(40).optional(),
        build: z.string().max(40).optional(),
      })
      .optional(),
  })
  .superRefine((body, ctx) => {
    if (body.kind === "rating" && !body.rating) {
      ctx.addIssue({ code: "custom", path: ["rating"], message: "a rating needs up or down" });
    }
    if (body.kind === "flag" && !body.reason) {
      ctx.addIssue({ code: "custom", path: ["reason"], message: "a flag needs a reason" });
    }
    if (body.kind === "flag" && body.rating) {
      ctx.addIssue({ code: "custom", path: ["rating"], message: "a flag has no rating" });
    }
    if (body.tokenPosition !== undefined && !body.line) {
      ctx.addIssue({ code: "custom", path: ["tokenPosition"], message: "tokenPosition needs line" });
    }
  });
export type ClipFeedbackRequest = z.infer<typeof clipFeedbackRequestSchema>;

/**
 * Triage status for a new row. Flags and thumbs-down-with-a-reason are open
 * issues; a plain rating isn't something to triage (null).
 */
export function initialStatus(body: ClipFeedbackRequest): ClipFeedbackStatus | null {
  if (body.kind === "flag") return "open";
  if (body.rating === "down" && body.reason) return "open";
  return null;
}

/** Plain-text reason for a 400. */
export function feedbackValidationReason(error: z.ZodError): string {
  const issue = error.issues[0];
  if (!issue) return "invalid body";
  if (issue.path.length === 0) return "body must be a JSON object";
  return `invalid ${issue.path.join(".")}: ${issue.message}`;
}

/** Writes per learner per rolling 24h (ratings and flags together). */
export const DAILY_FEEDBACK_LIMIT = 60;

export const CLIP_FEEDBACK_DDL = `
CREATE TABLE IF NOT EXISTS clip_feedback (
  id text PRIMARY KEY,
  clip_id text NOT NULL,
  user_id text NOT NULL,
  kind text NOT NULL,
  rating text,
  reason text,
  note text,
  sentence_index integer,
  token_position integer,
  snapshot jsonb,
  app_version text,
  app_build text,
  status text,
  resolved_at timestamp with time zone,
  resolved_note text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS clip_feedback_status_cursor_idx ON clip_feedback (status, created_at, id);
CREATE INDEX IF NOT EXISTS clip_feedback_issue_cursor_idx ON clip_feedback (created_at, id) WHERE status IS NOT NULL;
CREATE INDEX IF NOT EXISTS clip_feedback_status_idx ON clip_feedback (status, created_at);
CREATE INDEX IF NOT EXISTS clip_feedback_clip_idx ON clip_feedback (clip_id);
CREATE INDEX IF NOT EXISTS clip_feedback_user_idx ON clip_feedback (user_id, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS clip_feedback_rating_uniq ON clip_feedback (clip_id, user_id) WHERE kind = 'rating';
`;

/** Same wording as the app's report screen (ClipFeedback.swift). */
export const clipFeedbackReasonLabels: Record<ClipFeedbackReason, string> = {
  translation: "Bad translation",
  tokenization: "Words split wrong",
  reading: "Wrong reading",
  timing: "Subtitles out of sync",
  video: "Video problem",
  other: "Something else",
};

export const clipFeedbackStatusLabels: Record<ClipFeedbackStatus, string> = {
  open: "Open",
  resolved: "Resolved",
  wontfix: "Won’t fix",
  duplicate: "Duplicate",
};
