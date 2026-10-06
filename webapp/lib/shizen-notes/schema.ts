import { z } from "zod";

export const NOTE_SOURCES = ["dialogue", "quiz"] as const;
export const NOTE_AGENTS = ["shohei", "vikram", "hana"] as const;

/** Base64 JPEG, no `data:` prefix. ~1.1MB binary. Matches the iOS snapshot cap. */
export const SCREENSHOT_JPEG_MAX_CHARS = 1_500_000;

export const shizenNoteSchema = z.object({
  source: z.enum(NOTE_SOURCES),
  source_id: z.string().trim().min(1),
  title: z.string().trim().min(1).optional(),
  note: z.string().trim().min(1),
  agent: z.enum(NOTE_AGENTS).default("shohei"),
  metadata: z.object({
    url: z.string().trim().min(1),
    created_at: z.iso.datetime({ offset: true }),
    screenshot_jpeg: z
      .string()
      .trim()
      .min(1)
      .max(SCREENSHOT_JPEG_MAX_CHARS)
      .regex(/^\/9j\/[A-Za-z0-9+/]*={0,2}$/)
      .optional(),
  }),
});

export type ShizenNote = z.infer<typeof shizenNoteSchema>;

/** Plain-text reason for a 400, e.g. `missing note` or `unknown source`. */
export function noteValidationReason(error: z.ZodError, body: unknown): string {
  const issue = error.issues[0];
  if (!issue) return "invalid body";
  if (issue.path.length === 0) return "body must be a JSON object";
  const field = issue.path.join(".");
  if (issue.code === "invalid_value") return `unknown ${field}`;
  if (issue.code === "invalid_format") return `bad ${field.replace("metadata.", "")}`;
  if (issue.code === "too_small" || valueAt(body, issue.path) === undefined) {
    return `missing ${field}`;
  }
  return `invalid ${field}`;
}

function valueAt(body: unknown, path: PropertyKey[]): unknown {
  let current = body;
  for (const key of path) {
    if (current === null || typeof current !== "object") return undefined;
    current = (current as Record<PropertyKey, unknown>)[key];
  }
  return current;
}
