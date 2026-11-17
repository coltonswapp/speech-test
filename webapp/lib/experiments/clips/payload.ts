import { exportHighlights } from "@/lib/dialogue/export";
import type { DialogueHighlights, ExportedTeachingPattern } from "@/lib/dialogue/types";
import { clipIsAligned, clipListedAt, type ClipDraft, type ClipOrientation } from "@/lib/experiments/clips/types";
import { clipFeedStatus } from "@/lib/experiments/clips/feed";
import { splitSentencePhrases } from "@/lib/experiments/clips/phrases";
import {
  clipEffectiveTags,
  clipPaceLabel,
  clipSpeechPace,
  type ClipPace,
} from "@/lib/experiments/clips/tags";

// App-facing clip payload (snake_case, like the public dialogue API). Every
// time is in seconds on the YouTube video's timeline, onset shift applied, so
// the app compares them straight to the player's current time.

/**
 * Catalog tags (values in lib/experiments/clips/tags.ts; new values can appear
 * as the vocabulary grows, so treat unknown ones as plain labels).
 */
export type ClipPayloadTags = {
  /** anime, drama, comedy-skit, variety, vlog, streamer, explainer, how-to, interview, learner, other */
  format: string;
  /** 0–3, most important first: food, travel, school, work, romance… */
  topics: string[];
  /** casual, polite, keigo */
  register: string;
  /** monologue, dialogue, group, narration */
  speakers: string;
  /** standard, kansai, other */
  dialect: string;
  /** The show or franchise, when known. */
  series?: string;
};

/** How fast it's spoken: characters per second of speech, and its bucket. */
export type ClipPayloadPace = { label: ClipPace; chars_per_sec: number };

function payloadTagFields(draft: ClipDraft): { tags?: ClipPayloadTags; pace?: ClipPayloadPace } {
  const tags = clipEffectiveTags(draft.tags);
  const cps = clipSpeechPace(draft.sentences);
  return {
    ...(tags ? { tags } : {}),
    ...(cps !== null ? { pace: { label: clipPaceLabel(cps), chars_per_sec: Math.round(cps * 10) / 10 } } : {}),
  };
}

export type ClipPayload = {
  clip_id: string;
  media: {
    source: "youtube";
    video_id: string;
    start_sec: number;
    end_sec: number;
    /** "portrait" for 9:16 Shorts; the app sizes the player from it. */
    orientation: ClipOrientation;
    /** The video's YouTube title; absent until fetched. */
    title?: string;
    /** The title in English, hashtags left out; absent when there is none. */
    title_en?: string;
    channel_name?: string;
    channel_url?: string;
    thumbnail_url?: string;
  };
  sentences: Array<{
    index: number;
    start_sec: number;
    end_sec: number;
    text_jp: string;
    text_en?: string;
    /**
     * Long sentences only: where to wrap it into readable lines (see
     * phrases.ts). Covers the sentence in order; `text_jp` pieces concatenate
     * to the sentence's text_jp, and `token_start`/`token_end` are positions
     * in `tokens` ([start, end)). Display only: translation, highlights and
     * saving stay per sentence. Absent when the sentence is one line.
     */
    phrases?: Array<{
      text_jp: string;
      token_start: number;
      token_end: number;
      start_sec: number;
      end_sec: number;
    }>;
  }>;
  /** In order; surfaces map onto their sentence's text_jp left to right. */
  tokens: Array<{
    position: number;
    sentence_index: number;
    surface: string;
    reading?: string;
    start_sec: number;
    end_sec: number;
  }>;
  /**
   * Same shape (camelCase) as a lesson scene's `highlights`, so the app reuses
   * its decoder rules. Pattern source indices are sentence indices.
   */
  highlights?: DialogueHighlights;
  /** Pattern library cards for `highlights.grammarPatterns[].patternId`. */
  patterns?: ExportedTeachingPattern[];
  /** 5 = N5 … 1 = N1; absent until the clip is rated. */
  jlpt_level?: number;
  /** Absent until the clip is tagged. */
  tags?: ClipPayloadTags;
  pace?: ClipPayloadPace;
  /**
   * Present on a retired clip. It is no longer in the clip list and its video
   * may be gone, so the app should not try to play it; the transcript above is
   * kept so items saved from the clip still resolve.
   */
  deprecated?: { at: string; reason?: string };
  updated_at: string;
};

export type ClipPayloadSummary = {
  clip_id: string;
  video_id: string;
  start_sec: number;
  end_sec: number;
  orientation: ClipOrientation;
  /** The video's YouTube title and channel; absent until fetched. */
  title?: string;
  /** The title in English, hashtags left out; absent when there is none. */
  title_en?: string;
  channel_name?: string;
  sentence_count: number;
  preview_jp: string;
  /** 5 = N5 … 1 = N1; absent until the clip is rated. */
  jlpt_level?: number;
  /** Absent until the clip is tagged. */
  tags?: ClipPayloadTags;
  pace?: ClipPayloadPace;
  /** Whether the clip is in the feed (`?feed=1` lists only these). */
  in_feed: boolean;
  /** When the clip first appeared in the app; the list is newest first by this. */
  listed_at: string;
  updated_at: string;
};

const round3 = (n: number) => Math.round(n * 1000) / 1000;

/** Pattern ids the clip's grammar highlights point at (for `patterns`). */
export function clipReferencedPatternIds(draft: ClipDraft): string[] {
  const ids = (draft.highlights?.grammarPatterns ?? [])
    .map((pattern) => pattern.patternId?.trim())
    .filter((id): id is string => Boolean(id));
  return [...new Set(ids)];
}

/** null until every token has a timestamp. */
export function buildClipPayload(
  draft: ClipDraft,
  patterns: ExportedTeachingPattern[] = []
): ClipPayload | null {
  if (!clipIsAligned(draft)) return null;
  const toVideo = (clipSeconds: number) =>
    round3(Math.max(0, draft.startSec + clipSeconds + draft.shiftSec));

  const sentences: ClipPayload["sentences"] = [];
  const tokens: ClipPayload["tokens"] = [];
  draft.sentences.forEach((sentence, index) => {
    const timed = sentence.tokens ?? [];
    const firstPosition = tokens.length;
    for (const token of timed) {
      tokens.push({
        position: tokens.length,
        sentence_index: index,
        surface: token.text,
        ...(token.reading ? { reading: token.reading } : {}),
        start_sec: toVideo(token.startSec ?? 0),
        end_sec: toVideo(token.endSec ?? 0),
      });
    }
    const en = sentence.en?.trim();
    const phrases = splitSentencePhrases(sentence.text, timed);
    sentences.push({
      index,
      start_sec: toVideo(timed[0]?.startSec ?? 0),
      end_sec: toVideo(timed[timed.length - 1]?.endSec ?? 0),
      text_jp: sentence.text,
      ...(en ? { text_en: en } : {}),
      ...(phrases.length > 1
        ? {
            phrases: phrases.map((p) => ({
              text_jp: sentence.text.slice(p.charStart, p.charEnd),
              token_start: firstPosition + p.tokenStart,
              token_end: firstPosition + p.tokenEnd,
              start_sec: toVideo(timed[p.tokenStart]?.startSec ?? 0),
              end_sec: toVideo(timed[p.tokenEnd - 1]?.endSec ?? 0),
            })),
          }
        : {}),
    });
  });

  const highlights = exportHighlights(draft.highlights ?? null);
  return {
    clip_id: draft.id,
    media: {
      source: "youtube",
      video_id: draft.videoId,
      start_sec: draft.startSec,
      end_sec: draft.endSec,
      orientation: draft.orientation ?? "landscape",
      ...(draft.video
        ? {
            title: draft.video.title,
            ...(draft.video.titleEn ? { title_en: draft.video.titleEn.text } : {}),
            channel_name: draft.video.channelName,
            ...(draft.video.channelUrl ? { channel_url: draft.video.channelUrl } : {}),
            ...(draft.video.thumbnailUrl ? { thumbnail_url: draft.video.thumbnailUrl } : {}),
          }
        : {}),
    },
    sentences,
    tokens,
    ...(highlights ? { highlights } : {}),
    ...(highlights && patterns.length > 0 ? { patterns } : {}),
    ...(draft.difficulty ? { jlpt_level: draft.difficulty.jlptLevel } : {}),
    ...payloadTagFields(draft),
    ...(draft.deprecated ? { deprecated: draft.deprecated } : {}),
    updated_at: draft.updatedAt,
  };
}

/** List entry; null for clips that aren't aligned yet or are deprecated. */
export function clipPayloadSummary(draft: ClipDraft): ClipPayloadSummary | null {
  if (!clipIsAligned(draft) || draft.deprecated) return null;
  return {
    clip_id: draft.id,
    video_id: draft.videoId,
    start_sec: draft.startSec,
    end_sec: draft.endSec,
    orientation: draft.orientation ?? "landscape",
    ...(draft.video
      ? {
          title: draft.video.title,
          ...(draft.video.titleEn ? { title_en: draft.video.titleEn.text } : {}),
          channel_name: draft.video.channelName,
        }
      : {}),
    sentence_count: draft.sentences.length,
    preview_jp: draft.sentences[0]?.text ?? "",
    ...(draft.difficulty ? { jlpt_level: draft.difficulty.jlptLevel } : {}),
    ...payloadTagFields(draft),
    in_feed: clipFeedStatus(draft).eligible,
    listed_at: clipListedAt(draft) ?? draft.updatedAt,
    updated_at: draft.updatedAt,
  };
}
