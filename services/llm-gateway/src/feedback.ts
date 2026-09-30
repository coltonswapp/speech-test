import { createHash, randomUUID } from "node:crypto";
import { FieldValue, Timestamp, getFirestore, type Transaction } from "firebase-admin/firestore";

import { jsonReady } from "./canonical.js";
import { featureNamed } from "./features/index.js";
import { storesFeedbackPayload, verifyFeedbackToken } from "./feedback-token.js";
import { log, userHash } from "./log.js";
import { periodKeys, USAGE_PERIODS, type UsagePeriod } from "./usage.js";
import { InputError, isObject, type Body } from "./validate.js";

export const FEEDBACK_REASONS = ["wrong_meaning", "not_about_sentence", "confusing"] as const;
export type FeedbackReason = (typeof FEEDBACK_REASONS)[number];

const VOTE_LIMIT_PER_HOUR = 40;
const DEVICE_WARN_PER_HOUR = 40;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DEVICE_RE = /^[A-Za-z0-9_-]{8,64}$/;

export class FeedbackError extends Error {
  constructor(
    readonly status: 400 | 429,
    readonly code: string,
    readonly detail?: string,
  ) {
    super(detail ?? code);
  }
}

export function newRequestId(): string {
  return randomUUID();
}

type Rating = "up" | "down";

type ParsedVote = {
  requestId: string;
  feedbackToken: string;
  feature: string;
  model: string;
  rating: Rating;
  reason?: FeedbackReason;
  input: unknown;
  result: unknown;
  deviceId?: string;
};

/**
 * One vote per requestId. The rating is immutable after create.
 * A later reason chip merges `reason` on a down vote and does not increment stats.
 */
export async function recordFeedback(uid: string, body: unknown, secret: string, retentionDays: number): Promise<void> {
  const vote = parseVote(body);
  const check = verifyFeedbackToken(secret, vote.feedbackToken, {
    uid,
    requestId: vote.requestId,
    feature: vote.feature,
    model: vote.model,
    input: vote.input,
    result: vote.result,
  });
  if (!check.ok) {
    const detail = check.reason === "expired" ? "feedback token expired" : "feedback token rejected";
    throw new FeedbackError(400, "invalid_request", detail);
  }

  const hour = hourKey();
  const db = getFirestore();
  const feedbackRef = db.collection("llmFeedback").doc(vote.requestId);
  const rateRef = db.collection("llmFeedbackRate").doc(uid).collection("hours").doc(hour);
  const deviceHash = vote.deviceId ? createHash("sha256").update(vote.deviceId).digest("hex").slice(0, 32) : null;
  const deviceRef = deviceHash
    ? db.collection("llmFeedbackRate").doc(`device_${deviceHash}`).collection("hours").doc(hour)
    : null;

  const outcome = await db.runTransaction(async (tx) => {
    const existing = await tx.get(feedbackRef);
    const rateSnap = await tx.get(rateRef);
    const deviceSnap = deviceRef ? await tx.get(deviceRef) : null;

    if (existing.exists) {
      const rating = existing.get("rating");
      const priorReason = existing.get("reason");
      if (vote.rating === "down" && rating === "down" && vote.reason && (priorReason === undefined || priorReason === null || priorReason === "")) {
        tx.update(feedbackRef, { reason: vote.reason });
        return "reason" as const;
      }
      return "noop" as const;
    }

    const used = numberField(rateSnap.get("count"));
    if (used >= VOTE_LIMIT_PER_HOUR) {
      throw new FeedbackError(429, "rate_limited", "too many votes this hour");
    }

    const deviceUsed = deviceSnap ? numberField(deviceSnap.get("count")) : 0;
    const createdAt = Timestamp.now();
    const expiresAt = Timestamp.fromMillis(createdAt.toMillis() + retentionDays * 86_400_000);
    const payload: Record<string, unknown> = {
      rating: vote.rating,
      feature: vote.feature,
      model: vote.model,
      requestId: vote.requestId,
      uid,
      createdAt,
      expiresAt,
    };
    if (vote.reason) payload.reason = vote.reason;
    if (storesFeedbackPayload(vote.rating, vote.requestId)) {
      payload.input = jsonReady(vote.input);
      payload.result = jsonReady(vote.result);
    }

    tx.set(feedbackRef, payload);
    tx.set(rateRef, { count: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    if (deviceRef) {
      tx.set(deviceRef, { count: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    }
    incrementStats(tx, uid, vote.feature, vote.rating);
    return deviceUsed + 1 > DEVICE_WARN_PER_HOUR ? ("created_device_hot" as const) : ("created" as const);
  });

  log("INFO", "feedback", {
    feature: vote.feature,
    rating: vote.rating,
    user: userHash(uid),
    requestId: vote.requestId,
    outcome: outcome === "created_device_hot" ? "created" : outcome,
  });
  if (outcome === "created_device_hot") {
    log("WARNING", "feedback device cap", {
      feature: vote.feature,
      user: userHash(uid),
      requestId: vote.requestId,
    });
  }
}

function parseVote(body: unknown): ParsedVote {
  if (!isObject(body)) throw new FeedbackError(400, "invalid_request", "body must be an object");
  const requestId = requiredString(body, "requestId", 64);
  if (!UUID_RE.test(requestId)) {
    throw new FeedbackError(400, "invalid_request", "requestId must be a uuid");
  }
  const feedbackToken = requiredString(body, "feedbackToken", 512);
  const featureName = requiredString(body, "feature", 64);
  const feature = featureNamed(featureName);
  if (!feature) throw new FeedbackError(400, "invalid_request", "unknown feature");
  const model = requiredString(body, "model", 80);
  const rating = body.rating;
  if (rating !== "up" && rating !== "down") {
    throw new FeedbackError(400, "invalid_request", "rating must be up or down");
  }
  if (!isObject(body.input)) throw new FeedbackError(400, "invalid_request", "input must be an object");
  if (!isObject(body.result)) throw new FeedbackError(400, "invalid_request", "result must be an object");

  let reason: FeedbackReason | undefined;
  if (body.reason !== undefined && body.reason !== null) {
    if (typeof body.reason !== "string" || !(FEEDBACK_REASONS as readonly string[]).includes(body.reason)) {
      throw new FeedbackError(400, "invalid_request", "reason is not recognized");
    }
    if (rating !== "down") {
      throw new FeedbackError(400, "invalid_request", "reason is only allowed on a down vote");
    }
    reason = body.reason as FeedbackReason;
  }

  let deviceId: string | undefined;
  if (body.deviceId !== undefined && body.deviceId !== null) {
    if (typeof body.deviceId !== "string" || !DEVICE_RE.test(body.deviceId)) {
      throw new FeedbackError(400, "invalid_request", "deviceId must be 8-64 url-safe characters");
    }
    deviceId = body.deviceId;
  }

  let input: unknown;
  try {
    input = feature.parseInput(body.input);
  } catch (err) {
    if (err instanceof InputError) throw new FeedbackError(400, "invalid_request", err.message);
    throw err;
  }

  return {
    requestId,
    feedbackToken,
    feature: featureName,
    model,
    rating,
    reason,
    input,
    result: body.result,
    deviceId,
  };
}

function requiredString(body: Body, key: string, maxLength: number): string {
  const value = body[key];
  if (typeof value !== "string") {
    throw new FeedbackError(400, "invalid_request", `${key} must be a string`);
  }
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > maxLength) {
    throw new FeedbackError(400, "invalid_request", `${key} must be a non-empty string`);
  }
  return trimmed;
}

/** Literal dotted field names, same `set(merge)` shape as usage. Not a nested `byFeature` map. */
function incrementStats(
  tx: Transaction,
  uid: string,
  feature: string,
  rating: Rating,
): void {
  const keys = periodKeys();
  const metric = rating === "up" ? "up" : "down";
  for (const scope of [uid, "_product"]) {
    for (const period of USAGE_PERIODS) {
      const ref = statsDoc(scope, period, keys[period]);
      tx.set(
        ref,
        {
          [metric]: FieldValue.increment(1),
          [`byFeature.${feature}.${metric}`]: FieldValue.increment(1),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
  }
}

function statsDoc(scope: string, period: UsagePeriod, key: string) {
  return getFirestore().collection("llmFeedbackStats").doc(scope).collection("periods").doc(`${period}_${key}`);
}

function hourKey(at = new Date()): string {
  const year = at.getUTCFullYear();
  const month = String(at.getUTCMonth() + 1).padStart(2, "0");
  const day = String(at.getUTCDate()).padStart(2, "0");
  const hour = String(at.getUTCHours()).padStart(2, "0");
  return `${year}-${month}-${day}T${hour}`;
}

function numberField(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}
