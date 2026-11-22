export const issueSubjects = ["clip", "scene"] as const;
export type IssueSubject = (typeof issueSubjects)[number];

export type ParsedIssueRef = { subject: IssueSubject; key: string };

const ISSUE_KEY = /^[a-zA-Z0-9_-]{1,128}$/;
const CLIP_FEEDBACK_ID = /^cfb_[a-zA-Z0-9_-]{1,120}$/;

export function parseIssueId(value: string): ParsedIssueRef | null {
  const separator = value.indexOf("-");
  if (separator < 0) return null;
  const subject = issueSubjects.find(candidate => candidate === value.slice(0, separator));
  const key = value.slice(separator + 1);
  return subject && ISSUE_KEY.test(key) ? { subject, key } : null;
}

/** `/content/issues/clip-cfb_…` (and the scene equivalent). */
export function issuePath(ref: ParsedIssueRef | string): string {
  const id = typeof ref === "string" ? ref : issueIdOf(ref);
  return `/content/issues/${id}`;
}

export function issueIdOf(ref: ParsedIssueRef): string {
  return `${ref.subject}-${ref.key}`;
}

export function clipIssueId(feedbackId: string): string {
  return `clip-${feedbackId}`;
}

/**
 * Studio issue id, clip feedback id, path, or full URL.
 * `https://…/content/issues/clip-cfb_x`, `/content/issues/clip-cfb_x`,
 * `clip-cfb_x`, or `cfb_x`.
 */
export function parseIssueRef(value: string): ParsedIssueRef | null {
  const trimmed = value.trim();
  if (!trimmed) return null;

  let candidate = trimmed;
  try {
    candidate = new URL(trimmed).pathname;
  } catch {
    // Not an absolute URL; may still be a path or bare id.
  }

  const fromPath = candidate.match(/\/content\/issues\/([^/?#]+)/i);
  if (fromPath) {
    try {
      candidate = decodeURIComponent(fromPath[1] ?? "");
    } catch {
      candidate = fromPath[1] ?? "";
    }
  } else {
    candidate = candidate.replace(/^\/+/, "");
  }

  const parsed = parseIssueId(candidate);
  if (parsed) return parsed;
  if (CLIP_FEEDBACK_ID.test(candidate) || CLIP_FEEDBACK_ID.test(trimmed)) {
    return { subject: "clip", key: CLIP_FEEDBACK_ID.test(candidate) ? candidate : trimmed };
  }
  return null;
}
