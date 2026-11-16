// What needs a look on a clip, from the same rules Studio's editor and the
// Feed step use. Shared by the clip report route (and through it the Studio
// MCP), so an agent's view of a clip matches what an editor sees.

import { clipFeedMetrics, clipFeedNotReady, clipFeedRules, clipFeedStatus } from "@/lib/experiments/clips/feed";
import { sumUsage, usageByStep } from "@/lib/experiments/clips/usage-cost";
import {
  clipHasHighlights,
  clipIsAligned,
  clipIsTokenized,
  clipIsTranslated,
  sentenceIsTimed,
  type ClipDraft,
} from "@/lib/experiments/clips/types";

/** Aligner scores below this are worth a listen (they don't predict error well). */
export const CLIP_LOW_SCORE = 0.3;

export const CLIP_PIPELINE_STEPS = [
  "video-info",
  "transcribe",
  "tokenize",
  "align",
  "translate",
  "level",
  "feed",
] as const;
export type ClipPipelineStep = (typeof CLIP_PIPELINE_STEPS)[number];

/** Steps that haven't produced their result yet, in pipeline order. */
export function clipMissingSteps(draft: ClipDraft): ClipPipelineStep[] {
  const s = draft.sentences;
  const done: Record<ClipPipelineStep, boolean> = {
    "video-info": Boolean(draft.video),
    transcribe: s.length > 0 || Boolean(draft.asr),
    tokenize: clipIsTokenized(draft),
    align: clipIsAligned(draft),
    translate: clipIsTranslated(draft),
    level: Boolean(draft.difficulty),
    feed: Boolean(draft.feed?.auto || draft.feed?.manual),
  };
  return CLIP_PIPELINE_STEPS.filter((step) => !done[step]);
}

export type ClipSentenceCheck = {
  sentence: number;
  text: string;
  /** Line-level aligner score, when aligned. */
  score: number | null;
  untimedTokens: number;
  lowScoreTokens: string[];
  readingFallbackTokens: string[];
  basicSplit: boolean;
  missingEnglish: boolean;
  /** An editor marked this line's warnings as reviewed. */
  flagsCleared: boolean;
};

export type ClipChecks = {
  id: string;
  videoId: string;
  channelName: string | null;
  title: string | null;
  durationSec: number;
  orientation: string;
  deprecated: boolean;
  jlptLevel: number | null;
  levelSource: "auto" | "manual" | null;
  feed: ReturnType<typeof clipFeedStatus>;
  feedRules: ReturnType<typeof clipFeedRules>;
  feedNotReady: string | null;
  metrics: ReturnType<typeof clipFeedMetrics>;
  missingSteps: ClipPipelineStep[];
  noSpeech: boolean;
  highlighted: boolean;
  /** Lines with something worth a look (reviewed lines included, marked). */
  sentences: ClipSentenceCheck[];
  counts: {
    lines: number;
    weakLines: number;
    lowScoreTokens: number;
    readingFallbackTokens: number;
    untimedLines: number;
    basicSplitLines: number;
    missingEnglish: number;
    /** Lines with warnings an editor hasn't marked reviewed. */
    unreviewedFlaggedLines: number;
  };
  cost: { usd: number; floor: boolean; unpriced: boolean; byStep: Record<string, number> };
  createdAt: string;
  updatedAt: string;
};

export function clipChecks(draft: ClipDraft): ClipChecks {
  const sentences: ClipSentenceCheck[] = [];
  const counts = {
    lines: draft.sentences.length,
    weakLines: 0,
    lowScoreTokens: 0,
    readingFallbackTokens: 0,
    untimedLines: 0,
    basicSplitLines: 0,
    missingEnglish: 0,
    unreviewedFlaggedLines: 0,
  };
  draft.sentences.forEach((s, i) => {
    const tokens = s.tokens ?? [];
    const lowScore = tokens.filter((t) => t.score !== undefined && t.score < CLIP_LOW_SCORE).map((t) => t.text);
    const fallback = tokens.filter((t) => t.readingFallback).map((t) => t.text);
    const untimed = s.tokens ? tokens.filter((t) => t.startSec === undefined || t.endSec === undefined).length : 0;
    const missingEnglish = !s.en?.trim();
    const weak = s.score !== undefined && s.score < CLIP_LOW_SCORE;
    if (weak) counts.weakLines++;
    counts.lowScoreTokens += lowScore.length;
    counts.readingFallbackTokens += fallback.length;
    if (s.tokens && !sentenceIsTimed(s)) counts.untimedLines++;
    if (s.basicSplit) counts.basicSplitLines++;
    if (missingEnglish) counts.missingEnglish++;
    const flagged = lowScore.length > 0 || fallback.length > 0;
    if (flagged && !s.flagsCleared) counts.unreviewedFlaggedLines++;
    if (weak || flagged || untimed > 0 || s.basicSplit || missingEnglish) {
      sentences.push({
        sentence: i,
        text: s.text,
        score: s.score ?? null,
        untimedTokens: untimed,
        lowScoreTokens: lowScore,
        readingFallbackTokens: fallback,
        basicSplit: Boolean(s.basicSplit),
        missingEnglish,
        flagsCleared: Boolean(s.flagsCleared),
      });
    }
  });
  const runs = draft.usage ?? [];
  const total = sumUsage(runs);
  return {
    id: draft.id,
    videoId: draft.videoId,
    channelName: draft.video?.channelName ?? null,
    title: draft.video?.title ?? null,
    durationSec: draft.durationSec,
    orientation: draft.orientation ?? "landscape",
    deprecated: Boolean(draft.deprecated),
    jlptLevel: draft.difficulty?.jlptLevel ?? null,
    levelSource: draft.difficulty?.source ?? null,
    feed: clipFeedStatus(draft),
    feedRules: clipFeedRules(draft),
    feedNotReady: clipFeedNotReady(draft),
    metrics: clipFeedMetrics(draft),
    missingSteps: clipMissingSteps(draft),
    noSpeech: Boolean(draft.asr) && draft.sentences.length === 0,
    highlighted: clipHasHighlights(draft),
    sentences,
    counts,
    cost: {
      usd: total.usd,
      floor: total.floor,
      unpriced: total.unpriced,
      byStep: Object.fromEntries(usageByStep(runs).map(({ step, totals }) => [step, totals.usd])),
    },
    createdAt: draft.createdAt,
    updatedAt: draft.updatedAt,
  };
}
