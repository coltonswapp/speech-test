import "server-only";
import {
  CLIP_USAGE_HISTORY_LIMIT,
  type ClipDraft,
  type ClipUsageRun,
  type ClipUsageStep,
  type GeminiTokenCounts,
} from "@/lib/experiments/clips/types";

export const ZERO_TOKENS: GeminiTokenCounts = {
  inputTokens: 0,
  audioInputTokens: 0,
  outputTokens: 0,
  thinkingTokens: 0,
};

/** Reads `usageMetadata` from a generateContent response. */
export function geminiTokenCounts(json: unknown): GeminiTokenCounts {
  const usage = (json as { usageMetadata?: Record<string, unknown> } | null)?.usageMetadata;
  if (!usage) return { ...ZERO_TOKENS };
  const num = (value: unknown) => (typeof value === "number" && Number.isFinite(value) ? value : 0);
  const details = Array.isArray(usage.promptTokensDetails) ? usage.promptTokensDetails : [];
  const audio = details
    .filter((d: { modality?: string }) => d?.modality === "AUDIO")
    .reduce((sum: number, d: { tokenCount?: unknown }) => sum + num(d?.tokenCount), 0);
  return {
    inputTokens: num(usage.promptTokenCount),
    audioInputTokens: audio,
    outputTokens: num(usage.candidatesTokenCount),
    thinkingTokens: num(usage.thoughtsTokenCount),
  };
}

export function addTokenCounts(a: GeminiTokenCounts, b: GeminiTokenCounts): GeminiTokenCounts {
  return {
    inputTokens: a.inputTokens + b.inputTokens,
    audioInputTokens: a.audioInputTokens + b.audioInputTokens,
    outputTokens: a.outputTokens + b.outputTokens,
    thinkingTokens: a.thinkingTokens + b.thinkingTokens,
  };
}

/** Appends a run to the draft's usage log (oldest dropped past the cap). */
export function withUsageRun(
  draft: ClipDraft,
  run: {
    step: ClipUsageStep;
    model: string;
    startedAt: number;
    calls: number;
    tokens?: GeminiTokenCounts;
    cachedLines?: number;
    lines?: number;
  }
): ClipDraft {
  const entry: ClipUsageRun = {
    step: run.step,
    at: new Date().toISOString(),
    model: run.model,
    durationMs: Date.now() - run.startedAt,
    calls: run.calls,
    ...(run.tokens ?? ZERO_TOKENS),
    ...(run.cachedLines !== undefined ? { cachedLines: run.cachedLines } : {}),
    ...(run.lines !== undefined ? { lines: run.lines } : {}),
  };
  return { ...draft, usage: [...(draft.usage ?? []), entry].slice(-CLIP_USAGE_HISTORY_LIMIT) };
}
