/**
 * Normalized shape for an `llmFeedback/{requestId}` vote document.
 *
 * Writer: `services/llm-gateway/src/feedback.ts`.
 * Contract: `services/llm-gateway/FIRESTORE_USAGE_CONTRACT.md` § Vote documents.
 *
 * Downs always store `input` + `result`. About 1 in 10 ups do too; the rest
 * are vote-only (no payload). Do not invent a gloss when payload is absent.
 */

export const FEEDBACK_RATINGS = ["up", "down"] as const;
export type FeedbackRating = (typeof FEEDBACK_RATINGS)[number];

export const FEEDBACK_REASONS = [
  "wrong_meaning",
  "not_about_sentence",
  "confusing",
] as const;
export type FeedbackReason = (typeof FEEDBACK_REASONS)[number];

export type FeedbackVoteDoc = {
  /** Firestore document id (= requestId). */
  id: string;
  path: string;
  requestId: string;
  rating: FeedbackRating;
  feature: string;
  model: string;
  uid: string;
  /** Present on downs only when the learner picked a chip. */
  reason: FeedbackReason | null;
  createdAt: string | null;
  expiresAt: string | null;
  /** True when the writer stored input and/or result. */
  hasPayload: boolean;
  input: unknown | null;
  result: unknown | null;
};

function asNonEmptyString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

/**
 * Admin SDK Timestamp, Firestore REST `{_seconds,_nanoseconds}`, Date, or ISO string.
 */
export function serializeFirestoreTime(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (!trimmed) return null;
    const ms = Date.parse(trimmed);
    return Number.isFinite(ms) ? new Date(ms).toISOString() : trimmed;
  }
  if (value instanceof Date) {
    return Number.isFinite(value.getTime()) ? value.toISOString() : null;
  }
  if (typeof value === "object") {
    const maybe = value as {
      toDate?: () => Date;
      toMillis?: () => number;
      _seconds?: unknown;
      seconds?: unknown;
    };
    if (typeof maybe.toDate === "function") {
      try {
        return serializeFirestoreTime(maybe.toDate());
      } catch {
        // fall through
      }
    }
    if (typeof maybe.toMillis === "function") {
      try {
        const ms = maybe.toMillis();
        if (typeof ms === "number" && Number.isFinite(ms)) {
          return new Date(ms).toISOString();
        }
      } catch {
        // fall through
      }
    }
    const seconds =
      typeof maybe._seconds === "number"
        ? maybe._seconds
        : typeof maybe.seconds === "number"
          ? maybe.seconds
          : null;
    if (seconds != null && Number.isFinite(seconds)) {
      return new Date(seconds * 1000).toISOString();
    }
  }
  return null;
}

function parseRating(value: unknown): FeedbackRating | null {
  return value === "up" || value === "down" ? value : null;
}

function parseReason(value: unknown): FeedbackReason | null {
  if (typeof value !== "string") return null;
  return (FEEDBACK_REASONS as readonly string[]).includes(value)
    ? (value as FeedbackReason)
    : null;
}

/**
 * Normalize one `llmFeedback` document (or null fields when the snap is sparse).
 * Returns null when rating is missing/invalid — those docs are not operator-readable votes.
 */
export function parseFeedbackVoteDoc(args: {
  id: string;
  path?: string;
  data: Record<string, unknown> | null | undefined;
}): FeedbackVoteDoc | null {
  const { id, data } = args;
  if (!data) return null;

  const rating = parseRating(data.rating);
  if (!rating) return null;

  const requestId = asNonEmptyString(data.requestId) ?? id;
  const feature = asNonEmptyString(data.feature) ?? "";
  const model = asNonEmptyString(data.model) ?? "";
  const uid = asNonEmptyString(data.uid) ?? "";

  const hasInput = Object.prototype.hasOwnProperty.call(data, "input");
  const hasResult = Object.prototype.hasOwnProperty.call(data, "result");
  const hasPayload = hasInput || hasResult;

  return {
    id,
    path: args.path ?? `llmFeedback/${id}`,
    requestId,
    rating,
    feature,
    model,
    uid,
    reason: parseReason(data.reason),
    createdAt: serializeFirestoreTime(data.createdAt),
    expiresAt: serializeFirestoreTime(data.expiresAt),
    hasPayload,
    input: hasInput ? data.input : null,
    result: hasResult ? data.result : null,
  };
}
