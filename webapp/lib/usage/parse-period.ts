/**
 * Normalized shape for a usage period document.
 *
 * Authoritative writer contract:
 * `services/llm-gateway/FIRESTORE_USAGE_CONTRACT.md`
 *
 * Top-level metrics use prompt/output token split and cost in micros.
 * Feature breakdown is stored as **literal dotted field names**
 * (`byFeature.<id>.<metric>`), not a nested `byFeature` map — Firestore
 * `set(merge)` with those keys does not create `doc.byFeature`.
 */

export type UsageFeatureRow = {
  feature: string;
  calls: number;
  tokens: number;
  estimatedUsd: number;
  unpricedCalls: number;
  /** Thumbs-up count from `llmFeedbackStats` (0 until merged). */
  up: number;
  /** Thumbs-down count from `llmFeedbackStats` (0 until merged). */
  down: number;
};

export type UsagePeriodSnapshot = {
  /** Firestore path that was read (`llmUsage/...`). */
  path: string;
  /** Feedback stats path when loaded (`llmFeedbackStats/...`); null if not merged. */
  feedbackPath: string | null;
  periodDocId: string;
  exists: boolean;
  calls: number | null;
  tokens: number | null;
  estimatedUsd: number | null;
  unpricedCalls: number | null;
  /** Product/user thumbs-up for the period; null when feedback doc missing. */
  up: number | null;
  /** Product/user thumbs-down for the period; null when feedback doc missing. */
  down: number | null;
  /** Ranked by calls (desc); ties broken by feature name. */
  features: UsageFeatureRow[];
  /** Raw top-level keys present on the usage doc (for sparse-schema debugging). */
  rawKeys: string[];
};

const MICROS_PER_USD = 1_000_000;

/** Literal dotted keys written by llm-gateway `set(merge)`. */
const BY_FEATURE_FIELD_RE =
  /^byFeature\.(.+)\.(calls|promptTokens|outputTokens|estimatedCostMicros|unpricedCalls)$/;

type FeatureMetric =
  | "calls"
  | "promptTokens"
  | "outputTokens"
  | "estimatedCostMicros"
  | "unpricedCalls";

type FeatureAccum = Record<FeatureMetric, number>;

function asFiniteNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() !== "") {
    const n = Number(value);
    if (Number.isFinite(n)) return n;
  }
  return null;
}

/** Missing / non-numeric → 0 (contract display math). */
function numberOrZero(value: unknown): number {
  return asFiniteNumber(value) ?? 0;
}

function emptyFeatureAccum(): FeatureAccum {
  return {
    calls: 0,
    promptTokens: 0,
    outputTokens: 0,
    estimatedCostMicros: 0,
    unpricedCalls: 0,
  };
}

function tokensFromParts(promptTokens: number, outputTokens: number): number {
  return promptTokens + outputTokens;
}

function usdFromMicros(estimatedCostMicros: number): number {
  return estimatedCostMicros / MICROS_PER_USD;
}

function parseFlatByFeature(data: Record<string, unknown>): UsageFeatureRow[] {
  const byId = new Map<string, FeatureAccum>();

  for (const [key, value] of Object.entries(data)) {
    const match = BY_FEATURE_FIELD_RE.exec(key);
    if (!match) continue;

    const featureId = match[1]!;
    const metric = match[2] as FeatureMetric;
    if (featureId.trim() === "") continue;

    let accum = byId.get(featureId);
    if (!accum) {
      accum = emptyFeatureAccum();
      byId.set(featureId, accum);
    }
    accum[metric] = numberOrZero(value);
  }

  return [...byId.entries()]
    .map(([feature, accum]) => ({
      feature,
      calls: accum.calls,
      tokens: tokensFromParts(accum.promptTokens, accum.outputTokens),
      estimatedUsd: usdFromMicros(accum.estimatedCostMicros),
      unpricedCalls: accum.unpricedCalls,
      up: 0,
      down: 0,
    }))
    .sort((a, b) => {
      if (b.calls !== a.calls) return b.calls - a.calls;
      return a.feature.localeCompare(b.feature);
    });
}

/** Normalize a Firestore period document (or null when missing). */
export function parseUsagePeriodDoc(args: {
  path: string;
  periodDocId: string;
  data: Record<string, unknown> | null;
}): UsagePeriodSnapshot {
  const { path, periodDocId, data } = args;
  if (!data) {
    return {
      path,
      feedbackPath: null,
      periodDocId,
      exists: false,
      calls: null,
      tokens: null,
      estimatedUsd: null,
      unpricedCalls: null,
      up: null,
      down: null,
      features: [],
      rawKeys: [],
    };
  }

  const promptTokens = numberOrZero(data.promptTokens);
  const outputTokens = numberOrZero(data.outputTokens);
  const estimatedCostMicros = numberOrZero(data.estimatedCostMicros);

  return {
    path,
    feedbackPath: null,
    periodDocId,
    exists: true,
    calls: numberOrZero(data.calls),
    tokens: tokensFromParts(promptTokens, outputTokens),
    estimatedUsd: usdFromMicros(estimatedCostMicros),
    unpricedCalls: numberOrZero(data.unpricedCalls),
    up: null,
    down: null,
    features: parseFlatByFeature(data),
    rawKeys: Object.keys(data).sort(),
  };
}

/**
 * Merge vote rollups from `llmFeedbackStats` onto a usage snapshot.
 * Usage call/token parsing stays unchanged; feedback uses its own dotted-key parser.
 */
export function mergeUsageWithFeedback(
  usage: UsagePeriodSnapshot,
  feedback: {
    path: string;
    exists: boolean;
    up: number | null;
    down: number | null;
    features: { feature: string; up: number; down: number }[];
  },
): UsagePeriodSnapshot {
  const votesByFeature = new Map(
    feedback.features.map((row) => [row.feature, row] as const),
  );

  const mergedFeatures = new Map<string, UsageFeatureRow>();

  for (const row of usage.features) {
    const votes = votesByFeature.get(row.feature);
    mergedFeatures.set(row.feature, {
      ...row,
      up: votes?.up ?? 0,
      down: votes?.down ?? 0,
    });
  }

  for (const votes of feedback.features) {
    if (mergedFeatures.has(votes.feature)) continue;
    mergedFeatures.set(votes.feature, {
      feature: votes.feature,
      calls: 0,
      tokens: 0,
      estimatedUsd: 0,
      unpricedCalls: 0,
      up: votes.up,
      down: votes.down,
    });
  }

  const features = [...mergedFeatures.values()].sort((a, b) => {
    if (b.calls !== a.calls) return b.calls - a.calls;
    return a.feature.localeCompare(b.feature);
  });

  return {
    ...usage,
    feedbackPath: feedback.path,
    exists: usage.exists || feedback.exists,
    up: feedback.exists ? (feedback.up ?? 0) : null,
    down: feedback.exists ? (feedback.down ?? 0) : null,
    features,
  };
}
