/**
 * Run: pnpm exec tsx lib/usage/parse-period.selftest.ts
 *
 * Examples mirror `services/llm-gateway/FIRESTORE_USAGE_CONTRACT.md`
 * (product period + sparse per-user period with flat `byFeature.*` keys).
 */
import { parseUsagePeriodDoc } from "./parse-period";

function assert(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(msg);
}

function nearlyEqual(a: number, b: number, eps = 1e-12): boolean {
  return Math.abs(a - b) <= eps;
}

const missing = parseUsagePeriodDoc({
  path: "llmUsage/_product/periods/day_2026-03-25",
  periodDocId: "day_2026-03-25",
  data: null,
});
assert(!missing.exists, "missing exists");
assert(
  missing.calls === null &&
    missing.tokens === null &&
    missing.estimatedUsd === null &&
    missing.unpricedCalls === null &&
    missing.features.length === 0,
  "missing empty",
);

/**
 * Product period example — flat dotted `byFeature.<id>.<metric>` keys as
 * written by llm-gateway `set(merge)`. No nested `byFeature` map, no
 * `tokens` / `estimatedUsd` fields on the doc.
 */
const PRODUCT_CONTRACT_EXAMPLE: Record<string, unknown> = {
  calls: 42,
  promptTokens: 12000,
  outputTokens: 3500,
  estimatedCostMicros: 45_000,
  unpricedCalls: 2,
  updatedAt: { _seconds: 1_774_454_400, _nanoseconds: 0 },
  "byFeature.common_uses.calls": 20,
  "byFeature.common_uses.promptTokens": 5000,
  "byFeature.common_uses.outputTokens": 1500,
  "byFeature.common_uses.estimatedCostMicros": 20_000,
  "byFeature.contextual_gloss.calls": 10,
  "byFeature.contextual_gloss.promptTokens": 3000,
  "byFeature.contextual_gloss.outputTokens": 800,
  "byFeature.contextual_gloss.estimatedCostMicros": 12_000,
  "byFeature.sense_fit.calls": 5,
  "byFeature.sense_fit.promptTokens": 2000,
  "byFeature.sense_fit.outputTokens": 600,
  "byFeature.sense_fit.estimatedCostMicros": 8_000,
  "byFeature.dialogue_nuance.calls": 4,
  "byFeature.dialogue_nuance.promptTokens": 1200,
  "byFeature.dialogue_nuance.outputTokens": 400,
  "byFeature.dialogue_nuance.estimatedCostMicros": 3_500,
  "byFeature.span_gloss.calls": 2,
  "byFeature.span_gloss.promptTokens": 500,
  "byFeature.span_gloss.outputTokens": 150,
  "byFeature.span_gloss.estimatedCostMicros": 1_000,
  "byFeature.span_breakdown.calls": 1,
  "byFeature.span_breakdown.promptTokens": 300,
  "byFeature.span_breakdown.outputTokens": 50,
  "byFeature.span_breakdown.estimatedCostMicros": 500,
};

const product = parseUsagePeriodDoc({
  path: "llmUsage/_product/periods/day_2026-03-25",
  periodDocId: "day_2026-03-25",
  data: PRODUCT_CONTRACT_EXAMPLE,
});
assert(product.exists && product.calls === 42, "product calls");
assert(product.tokens === 15_500, "product tokens = prompt+output");
assert(
  nearlyEqual(product.estimatedUsd!, 0.045),
  `product usd got ${product.estimatedUsd}`,
);
assert(product.unpricedCalls === 2, "product unpricedCalls");
assert(product.features.length === 6, "product feature count");
assert(product.features[0]?.feature === "common_uses", "ranked by calls");
assert(product.features[0]?.calls === 20, "common_uses calls");
assert(product.features[0]?.tokens === 6500, "common_uses tokens");
assert(
  nearlyEqual(product.features[0]!.estimatedUsd, 0.02),
  "common_uses usd",
);
assert(product.features[1]?.feature === "contextual_gloss", "second by calls");
assert(product.features[5]?.feature === "span_breakdown", "last by calls");
assert(
  !product.rawKeys.includes("tokens") &&
    !product.rawKeys.includes("estimatedUsd"),
  "no alias fields on contract docs",
);

/**
 * Sparse per-user period — only a subset of metrics / features present.
 * Missing numbers must display as 0.
 */
const SPARSE_USER_CONTRACT_EXAMPLE: Record<string, unknown> = {
  calls: 3,
  promptTokens: 400,
  // outputTokens omitted → 0
  estimatedCostMicros: 1500,
  "byFeature.span_gloss.calls": 3,
  "byFeature.span_gloss.promptTokens": 400,
  "byFeature.span_gloss.estimatedCostMicros": 1500,
  // outputTokens / unpricedCalls omitted on the feature → 0
};

const sparseUser = parseUsagePeriodDoc({
  path: "llmUsage/kYqKbEEc5FUmN2vLEWL3x9NRSVe2/periods/day_2026-03-25",
  periodDocId: "day_2026-03-25",
  data: SPARSE_USER_CONTRACT_EXAMPLE,
});
assert(sparseUser.exists && sparseUser.calls === 3, "sparse calls");
assert(sparseUser.tokens === 400, "sparse tokens (prompt only)");
assert(
  nearlyEqual(sparseUser.estimatedUsd!, 0.0015),
  `sparse usd got ${sparseUser.estimatedUsd}`,
);
assert(sparseUser.unpricedCalls === 0, "sparse missing unpriced → 0");
assert(sparseUser.features.length === 1, "sparse one feature");
assert(sparseUser.features[0]?.feature === "span_gloss", "sparse feature id");
assert(sparseUser.features[0]?.tokens === 400, "sparse feature tokens");
assert(sparseUser.features[0]?.unpricedCalls === 0, "sparse feature unpriced");

// Nested byFeature must NOT be used (writer stores literal dotted keys).
const nestedIgnored = parseUsagePeriodDoc({
  path: "x",
  periodDocId: "day_x",
  data: {
    calls: 1,
    promptTokens: 10,
    outputTokens: 5,
    estimatedCostMicros: 100,
    byFeature: {
      common_uses: { calls: 99, promptTokens: 1, outputTokens: 1 },
    },
  },
});
assert(nestedIgnored.features.length === 0, "nested byFeature ignored");
assert(nestedIgnored.tokens === 15, "top-level tokens still parse");

// Open feature-id set: unknown snake_case ids still parse.
const openFeature = parseUsagePeriodDoc({
  path: "x",
  periodDocId: "day_x",
  data: {
    calls: 1,
    promptTokens: 0,
    outputTokens: 0,
    estimatedCostMicros: 0,
    "byFeature.new_tooling.calls": 1,
    "byFeature.new_tooling.promptTokens": 11,
    "byFeature.new_tooling.outputTokens": 7,
    "byFeature.new_tooling.estimatedCostMicros": 0,
  },
});
assert(openFeature.features[0]?.feature === "new_tooling", "open feature id");
assert(openFeature.features[0]?.tokens === 18, "open feature tokens");

console.log("parse-period.selftest: ok");
