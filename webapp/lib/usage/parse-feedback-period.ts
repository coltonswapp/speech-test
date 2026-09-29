/**
 * Normalized shape for an `llmFeedbackStats` period document.
 *
 * Writer contract (llm-gateway Feedback stats): top-level `up` / `down` /
 * `updatedAt`, plus **literal dotted field names**
 * (`byFeature.<id>.up` / `byFeature.<id>.down`) via `set(merge)`.
 * There is no nested `byFeature` map — do not read `doc.byFeature`.
 *
 * Vote metrics stay separate from usage call/token parsing
 * (`BY_FEATURE_FIELD_RE` in parse-period.ts).
 */

export type FeedbackFeatureRow = {
  feature: string;
  up: number;
  down: number;
};

export type FeedbackPeriodSnapshot = {
  /** Firestore path that was read. */
  path: string;
  periodDocId: string;
  exists: boolean;
  up: number | null;
  down: number | null;
  /** Ranked by (up+down) desc; ties broken by feature name. */
  features: FeedbackFeatureRow[];
  /** Raw top-level keys present on the doc (for sparse-schema debugging). */
  rawKeys: string[];
};

/** Literal dotted vote keys written by llm-gateway `set(merge)`. */
const BY_FEATURE_VOTE_FIELD_RE = /^byFeature\.(.+)\.(up|down)$/;

type VoteMetric = "up" | "down";

type FeatureVoteAccum = Record<VoteMetric, number>;

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

function emptyVoteAccum(): FeatureVoteAccum {
  return { up: 0, down: 0 };
}

function parseFlatByFeatureVotes(
  data: Record<string, unknown>,
): FeedbackFeatureRow[] {
  const byId = new Map<string, FeatureVoteAccum>();

  for (const [key, value] of Object.entries(data)) {
    const match = BY_FEATURE_VOTE_FIELD_RE.exec(key);
    if (!match) continue;

    const featureId = match[1]!;
    const metric = match[2] as VoteMetric;
    if (featureId.trim() === "") continue;

    let accum = byId.get(featureId);
    if (!accum) {
      accum = emptyVoteAccum();
      byId.set(featureId, accum);
    }
    accum[metric] = numberOrZero(value);
  }

  return [...byId.entries()]
    .map(([feature, accum]) => ({
      feature,
      up: accum.up,
      down: accum.down,
    }))
    .sort((a, b) => {
      const aVotes = a.up + a.down;
      const bVotes = b.up + b.down;
      if (bVotes !== aVotes) return bVotes - aVotes;
      return a.feature.localeCompare(b.feature);
    });
}

/** Normalize a Firestore feedback-stats period document (or null when missing). */
export function parseFeedbackPeriodDoc(args: {
  path: string;
  periodDocId: string;
  data: Record<string, unknown> | null;
}): FeedbackPeriodSnapshot {
  const { path, periodDocId, data } = args;
  if (!data) {
    return {
      path,
      periodDocId,
      exists: false,
      up: null,
      down: null,
      features: [],
      rawKeys: [],
    };
  }

  return {
    path,
    periodDocId,
    exists: true,
    up: numberOrZero(data.up),
    down: numberOrZero(data.down),
    features: parseFlatByFeatureVotes(data),
    rawKeys: Object.keys(data).sort(),
  };
}
