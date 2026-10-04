import { createHash } from "node:crypto";
import { FieldValue, Timestamp, getFirestore, type Transaction } from "firebase-admin/firestore";

import { FeedbackError } from "./feedback.js";
import { log, userHash } from "./log.js";
import { isObject, type Body } from "./validate.js";

export const LESSON_FEEDBACK_DIMENSIONS = ["audio", "content", "highlighting", "quiz"] as const;
export type LessonFeedbackDimension = (typeof LESSON_FEEDBACK_DIMENSIONS)[number];

const LIMIT_PER_HOUR = 20;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DEVICE_RE = /^[A-Za-z0-9_-]{8,64}$/;
/** Collection id and scene slug become one stats document id, so no `/` and no `__`. */
const SEGMENT_RE = /^[A-Za-z0-9._-]{1,120}$/;

type ParsedLessonVote = {
  attemptId: string;
  collectionId: string;
  scenarioId: string;
  publishedVariantId?: string;
  publishedContentHash?: string;
  ratings: Partial<Record<LessonFeedbackDimension, number>>;
  score: { correct: number; total: number; stars: number };
  englishPeeks?: number;
  appVersion?: string;
  deviceId?: string;
};

export function lessonSceneKey(collectionId: string, scenarioId: string): string {
  return `${collectionId}__${scenarioId}`;
}

/**
 * One document per attempt id. A retry of the same attempt is a no-op and does not
 * increment stats. Stats use literal dotted field names, same `set(merge)` rule as usage.
 */
export async function recordLessonFeedback(uid: string, body: unknown, retentionDays: number): Promise<void> {
  const vote = parseLessonVote(body);
  const sceneKey = lessonSceneKey(vote.collectionId, vote.scenarioId);
  const db = getFirestore();
  const voteRef = db.collection("lessonFeedback").doc(vote.attemptId);
  const rateRef = db.collection("lessonFeedbackRate").doc(uid).collection("hours").doc(hourKey());

  const outcome = await db.runTransaction(async (tx) => {
    const existing = await tx.get(voteRef);
    if (existing.exists) return "noop" as const;

    const rateSnap = await tx.get(rateRef);
    if (numberField(rateSnap.get("count")) >= LIMIT_PER_HOUR) {
      throw new FeedbackError(429, "rate_limited", "too many lesson ratings this hour");
    }

    const createdAt = Timestamp.now();
    const payload: Record<string, unknown> = {
      uid,
      sceneKey,
      collectionId: vote.collectionId,
      scenarioId: vote.scenarioId,
      ratings: vote.ratings,
      score: vote.score,
      createdAt,
      expiresAt: Timestamp.fromMillis(createdAt.toMillis() + retentionDays * 86_400_000),
    };
    if (vote.publishedVariantId) payload.publishedVariantId = vote.publishedVariantId;
    if (vote.publishedContentHash) payload.publishedContentHash = vote.publishedContentHash;
    if (vote.englishPeeks !== undefined) payload.englishPeeks = vote.englishPeeks;
    if (vote.appVersion) payload.appVersion = vote.appVersion;
    if (vote.deviceId) {
      payload.deviceHash = createHash("sha256").update(vote.deviceId).digest("hex").slice(0, 32);
    }

    tx.set(voteRef, payload);
    tx.set(rateRef, { count: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    incrementStats(tx, sceneKey, vote);
    return "created" as const;
  });

  log("INFO", "lesson feedback", {
    scene: sceneKey,
    user: userHash(uid),
    attemptId: vote.attemptId,
    outcome,
  });
}

function incrementStats(tx: Transaction, sceneKey: string, vote: ParsedLessonVote): void {
  const counters: Record<string, FieldValue> = { count: FieldValue.increment(1) };
  for (const [dimension, value] of Object.entries(vote.ratings)) {
    counters[`${dimension}.sum`] = FieldValue.increment(value);
    counters[`${dimension}.n`] = FieldValue.increment(1);
    counters[`${dimension}.h${value}`] = FieldValue.increment(1);
  }
  const stats = getFirestore().collection("lessonFeedbackStats");
  tx.set(
    stats.doc(sceneKey),
    {
      ...counters,
      collectionId: vote.collectionId,
      scenarioId: vote.scenarioId,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  tx.set(stats.doc("_product"), { ...counters, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
}

function parseLessonVote(body: unknown): ParsedLessonVote {
  if (!isObject(body)) throw invalid("body must be an object");

  const attemptId = stringField(body, "attemptId", 64);
  if (!UUID_RE.test(attemptId)) throw invalid("attemptId must be a uuid");

  const collectionId = stringField(body, "collectionId", 120);
  const scenarioId = stringField(body, "scenarioId", 120);
  for (const [key, value] of [["collectionId", collectionId], ["scenarioId", scenarioId]] as const) {
    if (!SEGMENT_RE.test(value) || value.includes("__") || value === "." || value === "..") {
      throw invalid(`${key} has unsupported characters`);
    }
  }

  if (!isObject(body.ratings)) throw invalid("ratings must be an object");
  const ratings: Partial<Record<LessonFeedbackDimension, number>> = {};
  for (const [key, value] of Object.entries(body.ratings)) {
    if (!(LESSON_FEEDBACK_DIMENSIONS as readonly string[]).includes(key)) {
      throw invalid(`rating ${key} is not recognized`);
    }
    if (!Number.isInteger(value) || (value as number) < 1 || (value as number) > 5) {
      throw invalid(`rating ${key} must be an integer from 1 to 5`);
    }
    ratings[key as LessonFeedbackDimension] = value as number;
  }
  if (Object.keys(ratings).length === 0) throw invalid("at least one rating is required");

  if (!isObject(body.score)) throw invalid("score must be an object");
  const score = {
    correct: boundedInt(body.score, "correct", 0, 100),
    total: boundedInt(body.score, "total", 0, 100),
    stars: boundedInt(body.score, "stars", 0, 3),
  };
  if (score.correct > score.total) throw invalid("score.correct cannot exceed score.total");

  let deviceId: string | undefined;
  if (body.deviceId !== undefined && body.deviceId !== null) {
    if (typeof body.deviceId !== "string" || !DEVICE_RE.test(body.deviceId)) {
      throw invalid("deviceId must be 8-64 url-safe characters");
    }
    deviceId = body.deviceId;
  }

  return {
    attemptId: attemptId.toLowerCase(),
    collectionId,
    scenarioId,
    publishedVariantId: optionalField(body, "publishedVariantId", 120),
    publishedContentHash: optionalField(body, "publishedContentHash", 128),
    ratings,
    score,
    englishPeeks: body.englishPeeks === undefined || body.englishPeeks === null
      ? undefined
      : boundedInt(body, "englishPeeks", 0, 1000),
    appVersion: optionalField(body, "appVersion", 32),
    deviceId,
  };
}

function invalid(detail: string): FeedbackError {
  return new FeedbackError(400, "invalid_request", detail);
}

function stringField(body: Body, key: string, maxLength: number): string {
  const value = body[key];
  const trimmed = typeof value === "string" ? value.trim() : "";
  if (!trimmed || trimmed.length > maxLength) throw invalid(`${key} must be a non-empty string`);
  return trimmed;
}

function optionalField(body: Body, key: string, maxLength: number): string | undefined {
  const value = body[key];
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string" || value.trim().length > maxLength) {
    throw invalid(`${key} must be a string of at most ${maxLength} chars`);
  }
  return value.trim() || undefined;
}

function boundedInt(body: Body, key: string, min: number, max: number): number {
  const value = body[key];
  if (!Number.isInteger(value) || (value as number) < min || (value as number) > max) {
    throw invalid(`${key} must be an integer from ${min} to ${max}`);
  }
  return value as number;
}

function hourKey(at = new Date()): string {
  return at.toISOString().slice(0, 13);
}

function numberField(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}
