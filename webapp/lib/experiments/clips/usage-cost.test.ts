import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { runCost, STEP_LABELS, sumUsage } from "./usage-cost";
import type { ClipUsageRun } from "./types";

const asr = (model: string, extra: Partial<ClipUsageRun> = {}): ClipUsageRun => ({
  step: "asr",
  at: "2026-11-22T00:00:00.000Z",
  model,
  durationMs: 12_000,
  calls: 1,
  inputTokens: 20_000,
  audioInputTokens: 18_000,
  outputTokens: 800,
  thinkingTokens: 1_200,
  ...extra,
});

describe("ASR compare costs", () => {
  it("labels the step and estimates Gemini cost so issue totals include it", () => {
    assert.equal(STEP_LABELS.asr, "ASR compare");
    const pro = runCost(asr("gemini-3.1-pro-preview"));
    const flash = runCost(asr("gemini-3.8-flash"));
    assert.ok(pro && pro.usd > 0);
    assert.ok(flash && flash.usd > 0);
    const total = sumUsage([
      asr("gemini-3.1-pro-preview"),
      asr("gemini-3.8-flash"),
      {
        step: "tokenize",
        at: "2026-11-22T00:01:00.000Z",
        model: "gemini-3.8-flash",
        durationMs: 800,
        calls: 1,
        inputTokens: 400,
        audioInputTokens: 0,
        outputTokens: 200,
        thinkingTokens: 0,
      },
    ]);
    assert.equal(total.runs, 3);
    assert.ok(total.usd > (pro?.usd ?? 0));
    assert.equal(total.floor, true);
  });

  it("still treats align as unpriced", () => {
    assert.equal(
      runCost({
        step: "align",
        at: "2026-11-22T00:00:00.000Z",
        model: "test-aligner",
        durationMs: 4000,
        calls: 0,
        inputTokens: 0,
        audioInputTokens: 0,
        outputTokens: 0,
        thinkingTokens: 0,
      }),
      null
    );
  });
});
