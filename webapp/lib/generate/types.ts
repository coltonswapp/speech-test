import { z } from "zod";
import { variantTokenSyncSchema } from "@/lib/dialogue/types";

export const GENERATE_MAX_LINES = 20;
export const GENERATE_MAX_TEXT_CHARS = 4000;
export const GENERATE_MAX_PAUSE_SECONDS = 5;
export const GENERATE_MAX_TITLE_CHARS = 200;
export const GENERATE_MAX_DELIVERY_CHARS = 200;
export const GENERATE_DUPLICATE_WINDOW_MS = 15_000;

/** Unsaved clips expire after this TTL and become eligible for deletion. Physical delete is the next daily cleanup (or a listing sweep), so objects can remain up to about 48 hours after creation. Saved clips stay. */
export const GENERATE_TEMPORARY_TTL_MS = 24 * 60 * 60 * 1000;
export const GENERATE_TEMPORARY_TTL_HOURS = 24;
export const GENERATE_CLEANUP_MAX_RETENTION_HOURS = 48;
/** Stale pending reservations can be reclaimed after the TTS maxDuration window. */
export const GENERATE_PENDING_STALE_MS = 8 * 60 * 1000;

export const GENERATE_TEMPORARY_LIFETIME = `Unsaved clips expire after ${GENERATE_TEMPORARY_TTL_HOURS} hours. Studio deletes expired clips on the next daily cleanup, so they can remain for up to about ${GENERATE_CLEANUP_MAX_RETENTION_HOURS} hours after creation. Save to library keeps them. They are not published and are kept apart from TTS Studio takes and learner content.`;

export const GENERATE_ALIGNMENT_NOTE =
  "Timestamps are taken from the combined WAV (pauses included) that is then encoded to MP3. A small MP3 encoder delay versus playback is possible and has not been live-measured.";

export type GenerationStatus = "pending" | "ready" | "failed" | "purging";

export const generateLineInputSchema = z.object({
  id: z.string().min(1).max(80),
  text: z
    .string()
    .trim()
    .min(1, "Each line needs text.")
    .max(GENERATE_MAX_TEXT_CHARS, "Keep each line under 4,000 characters."),
  voice: z.string().min(1).max(120),
  delivery: z.string().max(GENERATE_MAX_DELIVERY_CHARS).optional(),
  pauseAfterSeconds: z
    .number()
    .min(0, "Pause cannot be negative.")
    .max(GENERATE_MAX_PAUSE_SECONDS, "Pause can be at most 5 seconds.")
    .optional(),
});
export type GenerateLineInput = z.infer<typeof generateLineInputSchema>;

export const generateRequestSchema = z.object({
  title: z.string().max(GENERATE_MAX_TITLE_CHARS).optional(),
  lines: z
    .array(generateLineInputSchema)
    .min(1, "Add at least one line.")
    .max(GENERATE_MAX_LINES, "Keep it to 20 lines."),
  requestId: z.string().uuid(),
});
export type GenerateRequest = z.infer<typeof generateRequestSchema>;

export const generatePatchSchema = z
  .object({
    title: z.string().trim().min(1).max(GENERATE_MAX_TITLE_CHARS).optional(),
    saved: z.boolean().optional(),
  })
  .refine((value) => value.title !== undefined || value.saved !== undefined, {
    message: "Nothing to update.",
  });
export type GeneratePatch = z.infer<typeof generatePatchSchema>;

export const generateAlignRequestSchema = z.object({
  transcript: z
    .string()
    .trim()
    .max(20_000)
    .optional(),
});
export type GenerateAlignRequest = z.infer<typeof generateAlignRequestSchema>;

export const generateLineTimingSchema = z.object({
  index: z.number().int().nonnegative(),
  text: z.string(),
  voice: z.string().optional(),
  startSeconds: z.number(),
  endSeconds: z.number(),
  pauseAfterSeconds: z.number(),
});
export type GenerateLineTiming = z.infer<typeof generateLineTimingSchema>;

export type GenerateKind = "tts" | "upload";

export type GenerationRecord = {
  id: string;
  createdAt: string;
  updatedAt: string;
  savedAt: string | null;
  expiresAt: string | null;
  status: GenerationStatus;
  revision: number;
  error: string | null;
  title: string;
  kind: GenerateKind;
  model: string | null;
  requestId: string | null;
  contentHash: string | null;
  lines: GenerateLineInput[];
  lineTimings: GenerateLineTiming[] | null;
  tokenSync: z.infer<typeof variantTokenSyncSchema> | null;
  transcript: string | null;
  wavObjectKey: string | null;
  mp3ObjectKey: string | null;
  /** Object keys that still exist after a later attempt took over current keys. */
  obsoleteObjectKeys: string[];
  sampleRate: number | null;
  durationSeconds: number;
  byteCount: number | null;
};

export const GENERATE_UPLOAD_MAX_BYTES = 20 * 1024 * 1024;
export const GENERATE_UPLOAD_MAX_SECONDS = 180;
export const GENERATE_UPLOAD_MIN_SECONDS = 0.2;

export const GENERATE_UPLOAD_TYPES = new Map<string, string>([
  ["audio/wav", "wav"],
  ["audio/wave", "wav"],
  ["audio/x-wav", "wav"],
  ["audio/mpeg", "mp3"],
  ["audio/mp3", "mp3"],
  ["audio/mp4", "m4a"],
  ["audio/m4a", "m4a"],
  ["audio/x-m4a", "m4a"],
  ["audio/aac", "m4a"],
  ["audio/ogg", "ogg"],
  ["audio/flac", "flac"],
]);

export const GENERATE_UPLOAD_EXT: Record<string, string> = {
  wav: "wav",
  wave: "wav",
  mp3: "mp3",
  m4a: "m4a",
  aac: "m4a",
  mp4: "m4a",
  ogg: "ogg",
  flac: "flac",
};
