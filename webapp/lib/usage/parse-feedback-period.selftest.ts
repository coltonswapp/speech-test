/**
 * Run: pnpm exec tsx lib/usage/parse-feedback-period.selftest.ts
 *
 * Feedback stats use literal dotted `byFeature.<id>.(up|down)` keys via
 * `set(merge)` — no nested `byFeature` map.
 */
import { parseFeedbackPeriodDoc } from "./parse-feedback-period";
import {
  mergeUsageWithFeedback,
  parseUsagePeriodDoc,
} from "./parse-period";

function assert(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(msg);
}

const missing = parseFeedbackPeriodDoc({
  path: "llmFeedbackStats/_product/periods/day_2026-03-25",
  periodDocId: "day_2026-03-25",
  data: null,
});
assert(!missing.exists, "missing exists");
assert(
  missing.up === null &&
    missing.down === null &&
    missing.features.length === 0,
  "missing empty",
);

const PRODUCT_FEEDBACK_EXAMPLE: Record<string, unknown> = {
  up: 12,
  down: 3,
  updatedAt: { _seconds: 1_774_454_400, _nanoseconds: 0 },
  "byFeature.span_gloss.up": 5,
  "byFeature.span_gloss.down": 1,
  "byFeature.common_uses.up": 4,
  "byFeature.common_uses.down": 0,
  "byFeature.span_breakdown.up": 2,
  "byFeature.span_breakdown.down": 1,
  "byFeature.dialogue_nuance.up": 1,
  "byFeature.dialogue_nuance.down": 1,
};

const product = parseFeedbackPeriodDoc({
  path: "llmFeedbackStats/_product/periods/day_2026-03-25",
  periodDocId: "day_2026-03-25",
  data: PRODUCT_FEEDBACK_EXAMPLE,
});
assert(product.exists && product.up === 12, "product up");
assert(product.down === 3, "product down");
assert(product.features.length === 4, "product feature count");
assert(product.features[0]?.feature === "span_gloss", "ranked by vote total");
assert(product.features[0]?.up === 5 && product.features[0]?.down === 1, "span_gloss votes");
assert(product.features[1]?.feature === "common_uses", "second by votes");

// Nested byFeature must NOT be used (writer stores literal dotted keys).
const nestedIgnored = parseFeedbackPeriodDoc({
  path: "x",
  periodDocId: "day_x",
  data: {
    up: 1,
    down: 0,
    byFeature: {
      span_gloss: { up: 99, down: 99 },
    },
  },
});
assert(nestedIgnored.features.length === 0, "nested byFeature ignored");
assert(nestedIgnored.up === 1, "top-level up still parses");

// Usage call/token dotted keys must not be mistaken for votes.
const usageKeysIgnored = parseFeedbackPeriodDoc({
  path: "x",
  periodDocId: "day_x",
  data: {
    up: 0,
    down: 0,
    "byFeature.span_gloss.calls": 10,
    "byFeature.span_gloss.up": 2,
    "byFeature.span_gloss.down": 1,
  },
});
assert(usageKeysIgnored.features.length === 1, "only vote keys count");
assert(
  usageKeysIgnored.features[0]?.up === 2 &&
    usageKeysIgnored.features[0]?.down === 1,
  "vote metrics only",
);

// Sparse per-user — missing down on a feature → 0.
const sparse = parseFeedbackPeriodDoc({
  path: "llmFeedbackStats/kYqKbEEc5FUmN2vLEWL3x9NRSVe2/periods/day_2026-03-25",
  periodDocId: "day_2026-03-25",
  data: {
    up: 2,
    "byFeature.span_gloss.up": 2,
  },
});
assert(sparse.down === 0, "sparse missing top-level down → 0");
assert(sparse.features[0]?.down === 0, "sparse missing feature down → 0");

// Open feature-id set.
const openFeature = parseFeedbackPeriodDoc({
  path: "x",
  periodDocId: "day_x",
  data: {
    up: 1,
    down: 0,
    "byFeature.new_tooling.up": 1,
    "byFeature.new_tooling.down": 0,
  },
});
assert(openFeature.features[0]?.feature === "new_tooling", "open feature id");

// Merge onto usage: votes land on matching features; feedback-only features appear.
const usage = parseUsagePeriodDoc({
  path: "llmUsage/_product/periods/day_2026-03-25",
  periodDocId: "day_2026-03-25",
  data: {
    calls: 5,
    promptTokens: 100,
    outputTokens: 20,
    estimatedCostMicros: 1000,
    "byFeature.span_gloss.calls": 5,
    "byFeature.span_gloss.promptTokens": 100,
    "byFeature.span_gloss.outputTokens": 20,
    "byFeature.span_gloss.estimatedCostMicros": 1000,
  },
});
const merged = mergeUsageWithFeedback(usage, product);
assert(merged.feedbackPath === product.path, "feedback path attached");
assert(merged.up === 12 && merged.down === 3, "totals from feedback");
assert(merged.features.some((f) => f.feature === "span_gloss" && f.up === 5 && f.down === 1 && f.calls === 5), "merged span_gloss");
assert(merged.features.some((f) => f.feature === "common_uses" && f.up === 4 && f.calls === 0), "feedback-only feature kept");

// Usage vote dotted keys must not be parsed by usage BY_FEATURE_FIELD_RE.
assert(
  usage.features.every((f) => f.up === 0 && f.down === 0),
  "usage parse leaves votes at 0",
);
const usageWithVoteKeys = parseUsagePeriodDoc({
  path: "x",
  periodDocId: "day_x",
  data: {
    calls: 1,
    promptTokens: 0,
    outputTokens: 0,
    estimatedCostMicros: 0,
    "byFeature.span_gloss.up": 9,
    "byFeature.span_gloss.down": 8,
    "byFeature.span_gloss.calls": 1,
  },
});
assert(usageWithVoteKeys.features.length === 1, "usage still sees calls");
assert(
  usageWithVoteKeys.features[0]?.up === 0 &&
    usageWithVoteKeys.features[0]?.down === 0,
  "BY_FEATURE_FIELD_RE ignores up/down",
);

console.log("parse-feedback-period.selftest: ok");
