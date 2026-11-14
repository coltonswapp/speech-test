import { z } from "zod";
import { highlightsSchema } from "@/lib/dialogue/types";

// Clip POC (YouTube clip + word-synced transcript). Client-safe: no server
// imports. A draft lives in R2 at `experiments/clips/<id>/draft.json` next to
// the clip audio (`clip.wav`, mono 16 kHz, cut in the browser before upload).
//
// Token times are clip-relative seconds (0 = `startSec` in the video), as the
// aligner returns them. Video time = startSec + seconds + shiftSec.

export const CLIP_ID_PATTERN = /^[a-z0-9-]+$/;
export const YOUTUBE_ID_PATTERN = /^[A-Za-z0-9_-]{11}$/;

/** Keeps the 16 kHz WAV under the ~4 MB request body we can POST to Vercel. */
export const CLIP_MAX_SECONDS = 120;
export const CLIP_SAMPLE_RATE = 16_000;

/** Video shape: "portrait" for 9:16 YouTube Shorts; the app gives it a taller player. */
export const clipOrientationSchema = z.enum(["landscape", "portrait"]);
export type ClipOrientation = z.infer<typeof clipOrientationSchema>;

/**
 * Longest clip a whole-video split makes. Under CLIP_MAX_SECONDS so rounding
 * a cut to the millisecond can never push a piece over the upload limit.
 */
export const CLIP_SPLIT_MAX_SECONDS = 110;
export const CLIP_SPLIT_DEFAULT_TARGET_SECONDS = 40;
export const CLIP_SPLIT_MIN_TARGET_SECONDS = 10;

/** 5 = N5 (easiest) … 1 = N1, as on lessons and curriculum units. */
export const clipJlptLevelSchema = z.number().int().min(1).max(5);
export const CLIP_JLPT_LEVELS = [5, 4, 3, 2, 1] as const;

/** Same onset shift as auto-stamp (token-sync-auto.ts); tune per clip. */
export const CLIP_DEFAULT_SHIFT_SECONDS = -0.065;

export const clipTokenSchema = z.object({
  text: z.string().min(1),
  reading: z.string().optional(),
  startSec: z.number().optional(),
  endSec: z.number().optional(),
  score: z.number().optional(),
  readingFallback: z.boolean().optional(),
});
export type ClipToken = z.infer<typeof clipTokenSchema>;

export const clipSentenceSchema = z.object({
  text: z.string(),
  /** null until tokenized; cleared when the sentence text changes. */
  tokens: z.array(clipTokenSchema).nullable(),
  /** Aligner line score; present once aligned. */
  score: z.number().optional(),
  /** English translation (Translate step, hand-editable). Kept when only timings change. */
  en: z.string().optional(),
  /**
   * Reviewed: hide this line's orange warnings (low scores, reading
   * fallbacks). Reset when the line is re-aligned or its tokens change.
   */
  flagsCleared: z.boolean().optional(),
});
export type ClipSentence = z.infer<typeof clipSentenceSchema>;

export const CLIP_USAGE_STEPS = ["transcribe", "translate", "tokenize", "align", "level"] as const;
export type ClipUsageStep = (typeof CLIP_USAGE_STEPS)[number];

/** Gemini token counts for one model call (or a step's calls summed). */
export type GeminiTokenCounts = {
  /** Prompt tokens, all modalities. */
  inputTokens: number;
  /** Of inputTokens, how many were audio (billed at a higher rate). */
  audioInputTokens: number;
  /** Response tokens, excluding thinking. */
  outputTokens: number;
  /** Thinking tokens (billed as output). */
  thinkingTokens: number;
};

/** One run of a step (one button press). Align has no Gemini tokens. */
export const clipUsageRunSchema = z.object({
  step: z.enum(CLIP_USAGE_STEPS),
  at: z.string(),
  /** Gemini model, or the aligner version for align. */
  model: z.string(),
  durationMs: z.number(),
  /** Gemini requests made (retries included). 0 for align and fully cached tokenize. */
  calls: z.number(),
  inputTokens: z.number(),
  audioInputTokens: z.number(),
  outputTokens: z.number(),
  thinkingTokens: z.number(),
  /** Tokenize only: lines served from the shared line cache (no tokens spent). */
  cachedLines: z.number().optional(),
  /** Lines processed in this run. */
  lines: z.number().optional(),
});
export type ClipUsageRun = z.infer<typeof clipUsageRunSchema>;

/** Newest last; capped so the draft stays small. */
export const CLIP_USAGE_HISTORY_LIMIT = 50;

/** The clip's source video, as YouTube describes it (oEmbed). */
export const clipVideoInfoSchema = z.object({
  title: z.string(),
  channelName: z.string(),
  /** The channel's page, e.g. https://www.youtube.com/@handle. */
  channelUrl: z.string().optional(),
  thumbnailUrl: z.string().optional(),
  fetchedAt: z.string(),
});
export type ClipVideoInfo = z.infer<typeof clipVideoInfoSchema>;

export const clipDraftSchema = z.object({
  id: z.string().regex(CLIP_ID_PATTERN),
  videoId: z.string().regex(YOUTUBE_ID_PATTERN),
  startSec: z.number().min(0),
  endSec: z.number().positive(),
  /**
   * Title and channel, fetched from YouTube when the clip is created (and on
   * "Refresh" in the editor). Missing on older drafts or if the fetch failed.
   */
  video: clipVideoInfoSchema.optional(),
  /** Missing on older drafts = landscape. */
  orientation: clipOrientationSchema.optional(),
  /** Duration of clip.wav in seconds. */
  durationSec: z.number().positive(),
  shiftSec: z.number(),
  sentences: z.array(clipSentenceSchema),
  asr: z.object({ model: z.string(), at: z.string() }).optional(),
  translation: z.object({ model: z.string(), at: z.string() }).optional(),
  /**
   * Same shape as lesson scene highlights (vocabulary, grammarPatterns,
   * contextNotes). Pattern source indices are sentence indices.
   */
  highlights: highlightsSchema.optional(),
  alignment: z
    .object({ alignerVersion: z.string(), at: z.string() })
    .optional(),
  /**
   * How hard the clip is, so the app can keep it away from learners below
   * that level. "auto" = the Level step's estimate (with its reason); "manual"
   * = set by hand in Studio, which the Level step never overwrites silently.
   */
  difficulty: z
    .object({
      jlptLevel: clipJlptLevelSchema,
      source: z.enum(["auto", "manual"]),
      reason: z.string().optional(),
      model: z.string().optional(),
      at: z.string(),
    })
    .optional(),
  /**
   * Retired (video deleted, delisted, bad clip…). Hidden from the app's clip
   * list, but the payload is still served by id with this flag, so anything a
   * learner saved from the clip keeps its sentence, tokens and translation.
   * Prefer this to Delete once a clip has been live.
   */
  deprecated: z.object({ at: z.string(), reason: z.string().optional() }).optional(),
  /** Per-run cost log (Transcribe, Translate, Tokenize, Align, Level). */
  usage: z.array(clipUsageRunSchema).optional(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ClipDraft = z.infer<typeof clipDraftSchema>;

/** What GET /api/experiments/clips/[id] returns. */
export type ClipDraftResponse = {
  draft: ClipDraft;
  /** Short-lived signed URL for the clip WAV. */
  audioUrl: string;
};

export type ClipSummary = {
  id: string;
  videoId: string;
  /** null until fetched from YouTube. */
  videoTitle: string | null;
  channelName: string | null;
  startSec: number;
  endSec: number;
  orientation: ClipOrientation;
  sentenceCount: number;
  tokenized: boolean;
  translated: boolean;
  highlighted: boolean;
  aligned: boolean;
  /** 5 = N5 … 1 = N1; null until rated. */
  jlptLevel: number | null;
  deprecated: boolean;
  updatedAt: string;
};

/**
 * Whether a clip rated `clipLevel` suits a learner at `learnerLevel` (both
 * 5 = N5 … 1 = N1): at their level or easier. Unrated clips never match, so
 * an unreviewed clip can't land in front of a beginner.
 */
export function clipSuitsLevel(clipLevel: number | null | undefined, learnerLevel: number): boolean {
  return typeof clipLevel === "number" && clipLevel >= learnerLevel;
}

export function clipIsTokenized(draft: ClipDraft): boolean {
  return (
    draft.sentences.length > 0 &&
    draft.sentences.every((s) => s.tokens !== null && s.tokens.length > 0)
  );
}

export function clipIsTranslated(draft: ClipDraft): boolean {
  return draft.sentences.length > 0 && draft.sentences.every((s) => Boolean(s.en?.trim()));
}

export function clipHasHighlights(draft: ClipDraft): boolean {
  const h = draft.highlights;
  return Boolean(
    h && ((h.vocabulary?.length ?? 0) > 0 || (h.grammarPatterns?.length ?? 0) > 0 || (h.contextNotes?.length ?? 0) > 0)
  );
}

/** Every token in the line has a start and end time. */
export function sentenceIsTimed(sentence: ClipSentence): boolean {
  return (sentence.tokens ?? []).every((t) => t.startSec !== undefined && t.endSec !== undefined);
}

export function clipIsAligned(draft: ClipDraft): boolean {
  return clipIsTokenized(draft) && draft.sentences.every(sentenceIsTimed);
}

/**
 * Tokenized, with some lines timed and some not: usually after a token edit.
 * "Align edited lines" can fill the gaps without touching the timed lines.
 */
export function clipHasUntimedLines(draft: ClipDraft): boolean {
  return (
    clipIsTokenized(draft) &&
    draft.sentences.some(sentenceIsTimed) &&
    !draft.sentences.every(sentenceIsTimed)
  );
}

/**
 * Apply edited sentence texts: keep tokens for lines whose text is unchanged,
 * drop all timings (the aligner times the whole script at once, so any edit
 * can shift its neighbours).
 */
export function applySentenceEdits(draft: ClipDraft, texts: string[]): ClipSentence[] {
  const cleaned = texts.map((t) => t.trim()).filter((t) => t.length > 0);
  const textChanged =
    cleaned.length !== draft.sentences.length ||
    cleaned.some((t, i) => draft.sentences[i]?.text !== t);
  if (!textChanged) return draft.sentences;
  return cleaned.map((text, i) => {
    const prev = draft.sentences[i];
    const unchanged = prev !== undefined && prev.text === text;
    const tokens = unchanged ? prev.tokens : null;
    return {
      text,
      ...(unchanged && prev.en ? { en: prev.en } : {}),
      tokens: tokens
        ? tokens.map(({ text: surface, reading }) => ({
            text: surface,
            ...(reading ? { reading } : {}),
          }))
        : null,
    };
  });
}
