/**
 * Upload signer for CSFeedbackKit's `"storage": { "type": "presigned" }`.
 * The app sends `{ id, filename, content_type, size }`; we answer with a short-lived
 * R2 PUT URL and a longer-lived GET URL. R2 credentials never leave the server.
 */
import { z } from "zod";

/** Download links stay valid this long. SigV4 presigning caps at 7 days. */
export const DOWNLOAD_URL_TTL_SECONDS = 3 * 24 * 60 * 60;
/** The phone uploads right after signing. */
export const UPLOAD_URL_TTL_SECONDS = 15 * 60;
/** Screenshots are ~0.2–1 MB; logs are capped well below this. */
export const MAX_UPLOAD_BYTES = 8 * 1024 * 1024;

export const ALLOWED_CONTENT_TYPES = ["image/jpeg", "image/png", "text/plain; charset=utf-8", "text/plain"] as const;

export const uploadSignRequestSchema = z.object({
  /** The note id (`fb_…`). Keys are per note, so a retried upload overwrites itself. */
  id: z.string().regex(/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/),
  filename: z.string().regex(/^[A-Za-z0-9._-]{1,100}$/),
  content_type: z.enum(ALLOWED_CONTENT_TYPES),
  size: z.number().int().positive().max(MAX_UPLOAD_BYTES),
});

export type UploadSignRequest = z.infer<typeof uploadSignRequestSchema>;

/** Private R2 key for one attachment. */
export function feedbackUploadKey(request: UploadSignRequest): string {
  return `csfeedback/${request.id}/${request.filename}`;
}

/** Plain-text reason for a 400. */
export function signRequestValidationReason(error: z.ZodError): string {
  const issue = error.issues[0];
  if (!issue) return "invalid body";
  if (issue.path.length === 0) return "body must be a JSON object";
  return `invalid ${issue.path.join(".")}`;
}
