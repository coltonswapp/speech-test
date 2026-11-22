// Keep in sync with webapp/lib/content-issues/subjects.ts (parseIssueRef).
// MCP can't import Studio's path alias, so this copy stays dependency-free.

const SUBJECTS = ["clip", "scene"] as const;
type Subject = (typeof SUBJECTS)[number];

export type ParsedIssueRef = { subject: Subject; key: string };

const ISSUE_KEY = /^[a-zA-Z0-9_-]{1,128}$/;
const CLIP_FEEDBACK_ID = /^cfb_[a-zA-Z0-9_-]{1,120}$/;

function parseIssueId(value: string): ParsedIssueRef | null {
  const separator = value.indexOf("-");
  if (separator < 0) return null;
  const subject = SUBJECTS.find((candidate) => candidate === value.slice(0, separator));
  const key = value.slice(separator + 1);
  return subject && ISSUE_KEY.test(key) ? { subject, key } : null;
}

/** Studio issue id, clip feedback id (`cfb_…`), path, or full issue URL. */
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

export function issueIdOf(ref: ParsedIssueRef): string {
  return `${ref.subject}-${ref.key}`;
}
