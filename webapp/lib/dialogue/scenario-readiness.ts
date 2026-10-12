import {
  parsePublishedTokenSync,
  parseVariantTokenSync,
  tokenSyncStatus,
  type TokenSyncStatus,
} from "@/lib/dialogue/token-sync";
import {
  quizQuestionSchema,
  type DialogueLine,
  type VariantTokenSync,
} from "@/lib/dialogue/types";
import { scenarioLinesToConversation } from "@/lib/tts/scenario-conversation";

export type AudioReadiness = "published" | "stale" | "draft";
export type TimingReadiness = "missing" | "partial" | "ready" | "done";
export type QuizReadiness = "missing" | "ready" | "published";
/**
 * Combined line-timing + token karaoke from the aligner. Replaces the
 * separate timing + sync chips — both come from the same auto-stamp pass.
 */
export type AlignReadiness = "missing" | "partial" | "ready" | "done" | "stale";
/**
 * Human-ear review of the selected take's alignment.
 * `reviewed` = tokenSync.source reviewed (or human-stamped);
 * `flagged` = auto-stamp still has QA flags; `pending` otherwise.
 */
export type AlignReviewReadiness = "pending" | "flagged" | "reviewed";
/** Gate A: scene has a published take in CDN/DB. */
export type GateAPublishedReadiness = "unpublished" | "published" | "stale";
/**
 * Scene thumbnail: optional override. Unset inherits the lesson thumb.
 * Phase 1 has no separate thumb "stale" — CDN URL lands on upload.
 */
export type ThumbnailReadiness = "own" | "inherited" | "missing";
/** Curriculum sync: `ready` = studio complete, not in the last publish. */
export type CurriculumSyncStatus = TokenSyncStatus | "ready";
/**
 * Learner-client content QA (dialogue + quiz looked over).
 * Distinct from Studio take review / Gate A·B.
 */
export type ContentQaReadiness = "pending" | "dialogue" | "quiz" | "done";

export type ScenarioReadiness = {
  audio: AudioReadiness;
  /** Kept for lockstep tests / fallbacks; chips show `align`. */
  timing: TimingReadiness;
  /** Kept for lockstep tests / fallbacks; chips show `align`. */
  sync: CurriculumSyncStatus;
  align: AlignReadiness;
  review: AlignReviewReadiness;
  /** Gate A — published take on this scene. */
  published: GateAPublishedReadiness;
  publishedAt: string | null;
  quiz: QuizReadiness;
  quizCount: number;
  quizWithEvidence: number;
  thumbnail: ThumbnailReadiness;
  /** Learner-client content QA rollup for chips. */
  contentQa: ContentQaReadiness;
  contentQaHasNote: boolean;
};

/**
 * Line-switch completeness for a take: N spoken lines need N−1 marks
 * (`dialogueLineSwitchSamples`). A single spoken line needs none.
 * Same rule as `spokenLineWindows` / publish export, without needing WAV.
 */
export function lineTimingStatus(
  markSamples: number[] | null | undefined,
  spokenCount: number,
): Exclude<TimingReadiness, "ready"> {
  if (spokenCount <= 0) return "missing";
  if (spokenCount === 1) return "done";
  const marks = (markSamples ?? []).filter((sample) => sample > 0);
  if (marks.length === 0) return "missing";
  if (marks.length + 1 === spokenCount) return "done";
  return "partial";
}

export function quizReadiness(quiz: unknown): {
  count: number;
  withEvidence: number;
} {
  if (!Array.isArray(quiz) || quiz.length === 0) {
    return { count: 0, withEvidence: 0 };
  }
  let count = 0;
  let withEvidence = 0;
  for (const item of quiz) {
    const parsed = quizQuestionSchema.safeParse(item);
    if (!parsed.success) continue;
    count += 1;
    if (parsed.data.sourceSpokenStart !== undefined) withEvidence += 1;
  }
  return { count, withEvidence };
}

function publishedAsWorking(
  published: NonNullable<ReturnType<typeof parsePublishedTokenSync>>,
): VariantTokenSync {
  return {
    version: 1,
    contentHash: published.contentHash,
    lines: published.lines.map((line) => ({
      text: line.text,
      tokens: line.tokens.map((token) => ({
        text: token.text,
        startSeconds: token.startSeconds,
      })),
    })),
  };
}

/**
 * Green only for karaoke that last publish actually shipped and still matches
 * the current lines. Studio-only complete sync is `ready` (amber) until republish.
 */
export function curriculumSyncStatus(params: {
  publishedTokenSync: unknown;
  workingTokenSync: unknown;
  contentHash: string | null | undefined;
  spokenTexts: string[];
  /** Published snapshot ≠ what the current take would write. */
  karaokeStale?: boolean;
}): CurriculumSyncStatus {
  const { contentHash, spokenTexts } = params;
  const published = parsePublishedTokenSync(params.publishedTokenSync);
  const publishedStatus = published
    ? tokenSyncStatus(publishedAsWorking(published), contentHash, spokenTexts)
    : "missing";
  const workingStatus = tokenSyncStatus(
    parseVariantTokenSync(params.workingTokenSync),
    contentHash,
    spokenTexts,
  );

  if (publishedStatus === "complete") {
    return params.karaokeStale ? "stale" : "complete";
  }
  if (publishedStatus === "stale") return "stale";
  if (workingStatus === "complete") return "ready";
  if (publishedStatus === "tokens-only" || workingStatus === "tokens-only") {
    return "tokens-only";
  }
  if (workingStatus === "stale") return "stale";
  return "missing";
}

export function curriculumTimingStatus(params: {
  publishedAudio: boolean;
  audioStale: boolean;
  publishedMarks: number[] | null | undefined;
  workingMarks: number[] | null | undefined;
  spokenCount: number;
}): TimingReadiness {
  const publishedTiming = lineTimingStatus(
    params.publishedMarks,
    params.spokenCount,
  );
  const workingTiming = lineTimingStatus(
    params.workingMarks,
    params.spokenCount,
  );
  if (
    params.publishedAudio &&
    !params.audioStale &&
    publishedTiming === "done"
  ) {
    return "done";
  }
  if (workingTiming === "done" || publishedTiming === "done") return "ready";
  if (workingTiming === "partial" || publishedTiming === "partial") {
    return "partial";
  }
  return "missing";
}

export function curriculumAudioStatus(params: {
  publishedAudioUrl: string | null;
  audioStale: boolean;
}): AudioReadiness {
  if (!params.publishedAudioUrl) return "draft";
  return params.audioStale ? "stale" : "published";
}

export function curriculumQuizStatus(params: {
  quizCount: number;
  publishedAudio: boolean;
  audioStale: boolean;
}): QuizReadiness {
  if (params.quizCount <= 0) return "missing";
  if (params.publishedAudio && !params.audioStale) return "published";
  return "ready";
}

export function curriculumThumbnailStatus(params: {
  scenarioThumbnailUrl: string | null | undefined;
  collectionThumbnailUrl: string | null | undefined;
}): ThumbnailReadiness {
  if (params.scenarioThumbnailUrl) return "own";
  if (params.collectionThumbnailUrl) return "inherited";
  return "missing";
}

export function curriculumContentQaStatus(params: {
  dialogueReviewedAt?: Date | string | null;
  quizReviewedAt?: Date | string | null;
}): ContentQaReadiness {
  const dialogue = !!params.dialogueReviewedAt;
  const quiz = !!params.quizReviewedAt;
  if (dialogue && quiz) return "done";
  if (dialogue) return "dialogue";
  if (quiz) return "quiz";
  return "pending";
}

/**
 * Roll line-switch marks + token karaoke into one aligner chip.
 * Stale karaoke wins; both published-and-current is `done`; studio-complete
 * but not shipped is `ready` (amber until Gate A).
 */
export function curriculumAlignStatus(
  timing: TimingReadiness,
  sync: CurriculumSyncStatus,
): AlignReadiness {
  if (sync === "stale") return "stale";
  if (timing === "done" && sync === "complete") return "done";
  const timingOk = timing === "done" || timing === "ready";
  const syncOk = sync === "complete" || sync === "ready";
  if (timingOk && syncOk) return "ready";
  if (timing === "partial" || sync === "tokens-only" || timingOk || syncOk) {
    return "partial";
  }
  return "missing";
}

export function curriculumAlignReviewStatus(params: {
  workingTokenSync: unknown;
}): AlignReviewReadiness {
  const sync = parseVariantTokenSync(params.workingTokenSync);
  if (!sync) return "pending";
  if (sync.source === "reviewed" || sync.source === "human") return "reviewed";
  if ((sync.flags?.length ?? 0) > 0) return "flagged";
  if (sync.source === "auto") return "pending";
  // Legacy take with no provenance: stamps were tapped by hand.
  const hasStamps = sync.lines.some((line) =>
    line.tokens.some((token) => token.startSeconds != null),
  );
  return hasStamps ? "reviewed" : "pending";
}

export function curriculumPublishedStatus(params: {
  publishedAudioUrl: string | null;
  publishedVariantId?: string | null;
  audioStale: boolean;
}): GateAPublishedReadiness {
  if (!params.publishedAudioUrl && !params.publishedVariantId) {
    return "unpublished";
  }
  return params.audioStale ? "stale" : "published";
}

function isoOrNull(value: Date | string | null | undefined): string | null {
  if (!value) return null;
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value.toISOString();
  }
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

export function buildScenarioReadiness(params: {
  publishedAudioUrl: string | null;
  publishedVariantId?: string | null;
  publishedAt?: Date | string | null;
  audioStale?: boolean;
  karaokeStale?: boolean;
  lines: unknown;
  quiz: unknown;
  tokenSync: unknown;
  publishedMarks?: number[] | null;
  workingMarks?: number[] | null;
  workingTokenSync: unknown;
  contentHash: string | null | undefined;
  scenarioThumbnailUrl?: string | null;
  collectionThumbnailUrl?: string | null;
  dialogueReviewedAt?: Date | string | null;
  quizReviewedAt?: Date | string | null;
  contentQaHasNote?: boolean;
}): ScenarioReadiness {
  const spoken = scenarioLinesToConversation(
    Array.isArray(params.lines) ? (params.lines as DialogueLine[]) : [],
  ).lines;
  const spokenTexts = spoken.map((line) => line.text);
  const quiz = quizReadiness(params.quiz);
  const audioStale = params.audioStale === true;
  const publishedAudio = !!params.publishedAudioUrl;
  const audio = curriculumAudioStatus({
    publishedAudioUrl: params.publishedAudioUrl,
    audioStale,
  });
  const publishedMarks = params.publishedMarks;
  const workingMarks = params.workingMarks ?? publishedMarks;
  const timing = curriculumTimingStatus({
    publishedAudio,
    audioStale,
    publishedMarks,
    workingMarks,
    spokenCount: spoken.length,
  });
  const sync = curriculumSyncStatus({
    publishedTokenSync: params.tokenSync,
    workingTokenSync: params.workingTokenSync,
    contentHash: params.contentHash,
    spokenTexts,
    karaokeStale: params.karaokeStale === true,
  });
  const published = curriculumPublishedStatus({
    publishedAudioUrl: params.publishedAudioUrl,
    publishedVariantId: params.publishedVariantId,
    audioStale,
  });
  return {
    audio,
    timing,
    sync,
    align: curriculumAlignStatus(timing, sync),
    review: curriculumAlignReviewStatus({
      workingTokenSync: params.workingTokenSync,
    }),
    published,
    publishedAt: published === "unpublished" ? null : isoOrNull(params.publishedAt),
    quiz: curriculumQuizStatus({
      quizCount: quiz.count,
      publishedAudio,
      audioStale,
    }),
    quizCount: quiz.count,
    quizWithEvidence: quiz.withEvidence,
    thumbnail: curriculumThumbnailStatus({
      scenarioThumbnailUrl: params.scenarioThumbnailUrl,
      collectionThumbnailUrl: params.collectionThumbnailUrl,
    }),
    contentQa: curriculumContentQaStatus({
      dialogueReviewedAt: params.dialogueReviewedAt,
      quizReviewedAt: params.quizReviewedAt,
    }),
    contentQaHasNote: params.contentQaHasNote === true,
  };
}

/** Compact relative/short date for curriculum rows. */
export function formatCurriculumUpdatedAt(
  iso: string,
  now = new Date(),
): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "";
  const diffMs = now.getTime() - date.getTime();
  const diffSec = Math.round(diffMs / 1000);
  if (diffSec < 60) return "just now";
  const diffMin = Math.round(diffSec / 60);
  if (diffMin < 60) return `${diffMin}m ago`;
  const diffHr = Math.round(diffMin / 60);
  if (diffHr < 24) return `${diffHr}h ago`;
  const diffDay = Math.round(diffHr / 24);
  if (diffDay < 7) return `${diffDay}d ago`;
  return date.toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

export function syncChipLabel(status: CurriculumSyncStatus): string {
  switch (status) {
    case "complete":
    case "ready":
      return "sync";
    case "tokens-only":
      return "tokens";
    case "stale":
      return "stale";
    case "missing":
      return "—";
  }
}

export function alignChipLabel(status: AlignReadiness): string {
  switch (status) {
    case "done":
    case "ready":
    case "partial":
      return "align";
    case "stale":
      return "align stale";
    case "missing":
      return "align —";
  }
}

export function reviewChipLabel(status: AlignReviewReadiness): string {
  switch (status) {
    case "reviewed":
      return "review ✓";
    case "flagged":
      return "review";
    case "pending":
      return "review —";
  }
}

export function publishedChipLabel(status: GateAPublishedReadiness): string {
  switch (status) {
    case "published":
      return "published";
    case "stale":
      return "pub stale";
    case "unpublished":
      return "pub —";
  }
}

export function thumbnailChipLabel(status: ThumbnailReadiness): string {
  switch (status) {
    case "own":
      return "thumb own";
    case "inherited":
      return "thumb ↓";
    case "missing":
      return "thumb —";
  }
}

export function contentQaChipLabel(
  status: ContentQaReadiness,
  hasNote: boolean,
): string {
  const base =
    status === "done"
      ? "qa ✓"
      : status === "dialogue"
        ? "qa dial"
        : status === "quiz"
          ? "qa quiz"
          : "qa —";
  return hasNote ? `${base}·` : base;
}
