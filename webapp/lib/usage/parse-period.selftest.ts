/**
 * Run: pnpm exec tsx lib/usage/parse-period.selftest.ts
 */
import { parseUsagePeriodDoc } from "./parse-period";

function assert(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(msg);
}

const missing = parseUsagePeriodDoc({
  path: "llmUsage/_product/periods/day_2026-03-25",
  periodDocId: "day_2026-03-25",
  data: null,
});
assert(!missing.exists, "missing exists");
assert(missing.calls === null && missing.features.length === 0, "missing empty");

const full = parseUsagePeriodDoc({
  path: "llmUsage/_product/periods/day_2026-03-25",
  periodDocId: "day_2026-03-25",
  data: {
    calls: 10,
    tokens: 1000,
    estimatedUsd: 0.12,
    features: {
      tokenizer: { calls: 7, tokens: 700, estimatedUsd: 0.08 },
      contextualGloss: { calls: 3, tokens: 300, estimatedUsd: 0.04 },
    },
  },
});
assert(full.exists && full.calls === 10, "full totals");
assert(full.features[0]?.feature === "tokenizer", "ranked by calls");
assert(full.features[1]?.feature === "contextualGloss", "second feature");

const sparse = parseUsagePeriodDoc({
  path: "x",
  periodDocId: "day_x",
  data: { byFeature: { foo: 42 }, totalTokens: 99 },
});
assert(sparse.tokens === 99, "alias totalTokens");
assert(sparse.features[0]?.tokens === 42 && sparse.features[0]?.calls === null, "numeric byFeature");
assert(sparse.calls === null, "no invented calls");

console.log("parse-period.selftest: ok");
