/**
 * Normalized shape for a usage period document.
 *
 * No in-repo writer defines the Firestore schema yet. The parser only surfaces
 * fields that are actually present (never invents metrics). Accepted aliases
 * mirror common gateway / iOS naming so sparse docs still render.
 */

export type UsageFeatureRow = {
  feature: string;
  calls: number | null;
  tokens: number | null;
  estimatedUsd: number | null;
};

export type UsagePeriodSnapshot = {
  /** Firestore path that was read. */
  path: string;
  periodDocId: string;
  exists: boolean;
  calls: number | null;
  tokens: number | null;
  estimatedUsd: number | null;
  /** Ranked by calls (desc); ties broken by feature name. Missing calls sort last. */
  features: UsageFeatureRow[];
  /** Raw top-level keys present on the doc (for sparse-schema debugging). */
  rawKeys: string[];
};

function asFiniteNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() !== "") {
    const n = Number(value);
    if (Number.isFinite(n)) return n;
  }
  return null;
}

function firstNumber(
  record: Record<string, unknown>,
  keys: string[],
): number | null {
  for (const key of keys) {
    if (!(key in record)) continue;
    const n = asFiniteNumber(record[key]);
    if (n != null) return n;
  }
  return null;
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value != null && !Array.isArray(value);
}

function parseFeatureEntry(
  feature: string,
  value: unknown,
): UsageFeatureRow | null {
  if (feature.trim() === "") return null;

  if (typeof value === "number" && Number.isFinite(value)) {
    // Map-of-counts: treat as tokens when only a number is stored (iOS-style).
    return { feature, calls: null, tokens: value, estimatedUsd: null };
  }

  if (!isPlainObject(value)) return null;

  return {
    feature,
    calls: firstNumber(value, [
      "calls",
      "callCount",
      "requestCount",
      "requests",
      "count",
    ]),
    tokens: firstNumber(value, [
      "tokens",
      "totalTokens",
      "tokenCount",
      "totalTokenCount",
    ]),
    estimatedUsd: firstNumber(value, [
      "estimatedUsd",
      "estimatedUSD",
      "costUSD",
      "totalCostUSD",
      "usd",
    ]),
  };
}

function parseFeatures(data: Record<string, unknown>): UsageFeatureRow[] {
  const rows: UsageFeatureRow[] = [];

  const mapCandidates = [data.features, data.byFeature, data.breakdown];
  for (const candidate of mapCandidates) {
    if (isPlainObject(candidate)) {
      for (const [feature, value] of Object.entries(candidate)) {
        const row = parseFeatureEntry(feature, value);
        if (row) rows.push(row);
      }
      break;
    }
    if (Array.isArray(candidate)) {
      for (const item of candidate) {
        if (!isPlainObject(item)) continue;
        const feature = String(
          item.feature ?? item.name ?? item.id ?? "",
        ).trim();
        const row = parseFeatureEntry(feature, item);
        if (row) rows.push(row);
      }
      break;
    }
  }

  return rows.sort((a, b) => {
    const ac = a.calls;
    const bc = b.calls;
    if (ac == null && bc == null) return a.feature.localeCompare(b.feature);
    if (ac == null) return 1;
    if (bc == null) return -1;
    if (bc !== ac) return bc - ac;
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
      features: [],
      rawKeys: [],
    };
  }

  return {
    path,
    periodDocId,
    exists: true,
    calls: firstNumber(data, [
      "calls",
      "callCount",
      "requestCount",
      "requests",
      "count",
    ]),
    tokens: firstNumber(data, [
      "tokens",
      "totalTokens",
      "tokenCount",
      "totalTokenCount",
    ]),
    estimatedUsd: firstNumber(data, [
      "estimatedUsd",
      "estimatedUSD",
      "costUSD",
      "totalCostUSD",
      "usd",
    ]),
    features: parseFeatures(data),
    rawKeys: Object.keys(data).sort(),
  };
}
