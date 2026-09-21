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
/** Curriculum sync: `ready` = studio complete, not in the last publish. */
export type CurriculumSyncStatus = TokenSyncStatus | "ready";

export type ScenarioReadiness = {
  audio: AudioReadiness;
  timing: TimingReadiness;
  sync: CurriculumSyncStatus;
  quiz: QuizReadiness;
  quizCount: number;
  quizWithEvidence: number;
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

export function buildScenarioReadiness(params: {
  publishedAudioUrl: string | null;
  audioStale?: boolean;
  karaokeStale?: boolean;
  lines: unknown;
  quiz: unknown;
  tokenSync: unknown;
  publishedMarks?: number[] | null;
  workingMarks?: number[] | null;
  workingTokenSync: unknown;
  contentHash: string | null | undefined;
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
  return {
    audio,
    timing: curriculumTimingStatus({
      publishedAudio,
      audioStale,
      publishedMarks,
      workingMarks,
      spokenCount: spoken.length,
    }),
    sync: curriculumSyncStatus({
      publishedTokenSync: params.tokenSync,
      workingTokenSync: params.workingTokenSync,
      contentHash: params.contentHash,
      spokenTexts,
      karaokeStale: params.karaokeStale === true,
    }),
    quiz: curriculumQuizStatus({
      quizCount: quiz.count,
      publishedAudio,
      audioStale,
    }),
    quizCount: quiz.count,
    quizWithEvidence: quiz.withEvidence,
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

/**
 * Compact published-dialogue length for curriculum unit/lesson labels.
 * Returns null for missing/zero so callers can omit the label.
 */
export function formatPublishedAudioDuration(
  totalSeconds: number | null | undefined,
): string | null {
  if (
    totalSeconds == null ||
    !Number.isFinite(totalSeconds) ||
    totalSeconds <= 0
  ) {
    return null;
  }
  const whole = Math.round(totalSeconds);
  if (whole < 60) return `${whole}s`;
  const minutes = Math.floor(whole / 60);
  const seconds = whole % 60;
  if (seconds === 0) return `${minutes}m`;
  return `${minutes}m ${seconds}s`;
}

/** Sum published-take seconds; unpublished / unknown scenes contribute 0. */
export function sumPublishedAudioDurationSeconds(
  durations: Array<number | null | undefined>,
): number {
  let total = 0;
  for (const value of durations) {
    if (value != null && Number.isFinite(value) && value > 0) {
      total += value;
    }
  }
  return total;
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
