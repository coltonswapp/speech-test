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
};

export type UsagePeriodSnapshot = {
  /** Firestore path that was read. */
  path: string;
  periodDocId: string;
  exists: boolean;
  calls: number | null;
  tokens: number | null;
  estimatedUsd: number | null;
  unpricedCalls: number | null;
  /** Ranked by calls (desc); ties broken by feature name. */
  features: UsageFeatureRow[];
  /** Raw top-level keys present on the doc (for sparse-schema debugging). */
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
      periodDocId,
      exists: false,
      calls: null,
      tokens: null,
      estimatedUsd: null,
      unpricedCalls: null,
      features: [],
      rawKeys: [],
    };
  }

  const promptTokens = numberOrZero(data.promptTokens);
  const outputTokens = numberOrZero(data.outputTokens);
  const estimatedCostMicros = numberOrZero(data.estimatedCostMicros);

  return {
    path,
    periodDocId,
    exists: true,
    calls: numberOrZero(data.calls),
    tokens: tokensFromParts(promptTokens, outputTokens),
    estimatedUsd: usdFromMicros(estimatedCostMicros),
    unpricedCalls: numberOrZero(data.unpricedCalls),
    features: parseFlatByFeature(data),
    rawKeys: Object.keys(data).sort(),
  };
}
