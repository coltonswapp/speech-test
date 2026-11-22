// Cost estimates for clip usage runs (client-safe). Shared by the clip
// editor's Usage section and the whole-video page's totals.

import { estimateGeminiCostUSD } from "@/lib/gemini/models";
import {
  CLIP_USAGE_STEPS,
  type ClipUsageRun,
  type ClipUsageStep,
} from "@/lib/experiments/clips/types";

export const STEP_LABELS: Record<ClipUsageStep, string> = {
  transcribe: "Transcribe",
  asr: "ASR compare",
  translate: "Translate",
  tokenize: "Tokenize",
  align: "Align",
  level: "Level",
  tag: "Tag",
  feed: "Feed",
};

export const formatCount = (n: number) => n.toLocaleString("en-US");

export function formatUSD(value: number): string {
  if (value === 0) return "$0";
  if (value < 0.0001) return "<$0.0001";
  return `$${value.toFixed(4)}`;
}

/** "$0.0123", or "≥ $0.0123" when the figure is a floor. */
export function formatCost(cost: { usd: number; floor: boolean }): string {
  return `${cost.floor ? "≥ " : ""}${formatUSD(cost.usd)}`;
}

/**
 * Text-rate estimate (thinking billed as output). Audio input costs more than
 * text and our rate table has no audio rates, so runs with audio are a floor.
 * Align runs on our own aligner: no Gemini cost (null).
 */
export function runCost(run: ClipUsageRun): { usd: number; floor: boolean } | null {
  if (run.step === "align") return null;
  if (run.calls === 0) return { usd: 0, floor: false };
  const usd = estimateGeminiCostUSD(
    run.model,
    run.inputTokens,
    run.outputTokens + run.thinkingTokens,
    new Date(run.at)
  );
  return usd === undefined ? null : { usd, floor: run.audioInputTokens > 0 };
}

export type UsageTotals = {
  runs: number;
  calls: number;
  inputTokens: number;
  audioInputTokens: number;
  outputTokens: number;
  thinkingTokens: number;
  durationMs: number;
  usd: number;
  /** Some run sent audio (billed above the text rate used here). */
  floor: boolean;
  /** Some Gemini run's model isn't in the rate table, so `usd` leaves it out. */
  unpriced: boolean;
};

const ZERO: UsageTotals = {
  runs: 0,
  calls: 0,
  inputTokens: 0,
  audioInputTokens: 0,
  outputTokens: 0,
  thinkingTokens: 0,
  durationMs: 0,
  usd: 0,
  floor: false,
  unpriced: false,
};

export function sumUsage(runs: ClipUsageRun[]): UsageTotals {
  return runs.reduce<UsageTotals>((t, run) => {
    const cost = runCost(run);
    return {
      runs: t.runs + 1,
      calls: t.calls + run.calls,
      inputTokens: t.inputTokens + run.inputTokens,
      audioInputTokens: t.audioInputTokens + run.audioInputTokens,
      outputTokens: t.outputTokens + run.outputTokens,
      thinkingTokens: t.thinkingTokens + run.thinkingTokens,
      durationMs: t.durationMs + run.durationMs,
      usd: t.usd + (cost?.usd ?? 0),
      floor: t.floor || Boolean(cost?.floor),
      unpriced: t.unpriced || (run.step !== "align" && cost === null),
    };
  }, ZERO);
}

/** Totals per step, in pipeline order, for steps that ran at least once. */
export function usageByStep(runs: ClipUsageRun[]): Array<{ step: ClipUsageStep; totals: UsageTotals }> {
  return CLIP_USAGE_STEPS.map((step) => ({
    step,
    totals: sumUsage(runs.filter((run) => run.step === step)),
  })).filter(({ totals }) => totals.runs > 0);
}
