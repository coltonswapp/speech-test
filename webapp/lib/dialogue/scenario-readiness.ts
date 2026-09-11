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

export type TimingReadiness = "missing" | "partial" | "done";

export type ScenarioReadiness = {
  audio: "published" | "draft";
  timing: TimingReadiness;
  sync: TokenSyncStatus;
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
): TimingReadiness {
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

/** Prefer the published karaoke snapshot; fall back to the take's working sync. */
export function curriculumSyncStatus(params: {
  publishedTokenSync: unknown;
  workingTokenSync: unknown;
  contentHash: string | null | undefined;
  spokenTexts: string[];
}): TokenSyncStatus {
  const { contentHash, spokenTexts } = params;
  const published = parsePublishedTokenSync(params.publishedTokenSync);
  if (published) {
    const asWorking: VariantTokenSync = {
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
    return tokenSyncStatus(asWorking, contentHash, spokenTexts);
  }
  return tokenSyncStatus(
    parseVariantTokenSync(params.workingTokenSync),
    contentHash,
    spokenTexts,
  );
}

export function buildScenarioReadiness(params: {
  publishedAudioUrl: string | null;
  lines: unknown;
  quiz: unknown;
  tokenSync: unknown;
  /** Prefer published take; otherwise selected take. */
  markSamples: number[] | null | undefined;
  workingTokenSync: unknown;
  contentHash: string | null | undefined;
}): ScenarioReadiness {
  const spoken = scenarioLinesToConversation(
    Array.isArray(params.lines) ? (params.lines as DialogueLine[]) : [],
  ).lines;
  const spokenTexts = spoken.map((line) => line.text);
  const quiz = quizReadiness(params.quiz);
  return {
    audio: params.publishedAudioUrl ? "published" : "draft",
    timing: lineTimingStatus(params.markSamples, spoken.length),
    sync: curriculumSyncStatus({
      publishedTokenSync: params.tokenSync,
      workingTokenSync: params.workingTokenSync,
      contentHash: params.contentHash,
      spokenTexts,
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

export function syncChipLabel(status: TokenSyncStatus): string {
  switch (status) {
    case "complete":
      return "sync";
    case "tokens-only":
      return "tokens";
    case "stale":
      return "stale";
    case "missing":
      return "—";
  }
}
