import { createHash } from "node:crypto";
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";

import { FeedbackError } from "./feedback.js";
import { lessonSceneKey } from "./lesson-feedback.js";
import { log, userHash } from "./log.js";
import { isObject, type Body } from "./validate.js";

export const LESSON_REPORT_CATEGORIES = [
  "audio",
  "timing",
  "translation",
  "content",
  "quiz",
  "bug",
  "other",
] as const;
export type LessonReportCategory = (typeof LESSON_REPORT_CATEGORIES)[number];

export const LESSON_REPORT_PAGES = ["dialogue", "quiz", "highlights"] as const;
export type LessonReportPage = (typeof LESSON_REPORT_PAGES)[number];

const LIMIT_PER_HOUR = 10;
const NOTE_MAX = 2000;
const FOCUS_TITLE_MAX = 200;
const FOCUS_DETAILS_MAX = 20;
const FOCUS_DETAIL_LINE_MAX = 300;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DEVICE_RE = /^[A-Za-z0-9_-]{8,64}$/;
/** Collection id and scene slug become one stats document id, so no `/` and no `__`. */
const SEGMENT_RE = /^[A-Za-z0-9._-]{1,120}$/;

type ParsedLessonReport = {
  reportId: string;
  collectionId: string;
  scenarioId: string;
  publishedVariantId?: string;
  publishedContentHash?: string;
  page: LessonReportPage;
  focusTitle: string;
  focusDetails: string[];
  sessionMode?: string;
  quizQuestionNumber?: number;
  categories: LessonReportCategory[];
  note?: string;
  appVersion?: string;
  osVersion?: string;
  deviceId?: string;
};

/**
 * One document per report id. A retry of the same report is a no-op and does not
 * increment stats. Stats use literal dotted field names, same `set(merge)` rule as usage.
 */
export async function recordLessonReport(uid: string, body: unknown, retentionDays: number): Promise<void> {
  const report = parseLessonReport(body);
  const sceneKey = lessonSceneKey(report.collectionId, report.scenarioId);
  const db = getFirestore();
  const reportRef = db.collection("lessonReports").doc(report.reportId);
  const rateRef = db.collection("lessonReportRate").doc(uid).collection("hours").doc(hourKey());

  const outcome = await db.runTransaction(async (tx) => {
    const existing = await tx.get(reportRef);
    if (existing.exists) return "noop" as const;

    const rateSnap = await tx.get(rateRef);
    if (numberField(rateSnap.get("count")) >= LIMIT_PER_HOUR) {
      throw new FeedbackError(429, "rate_limited", "too many lesson reports this hour");
    }

    const createdAt = Timestamp.now();
    const payload: Record<string, unknown> = {
      uid,
      sceneKey,
      collectionId: report.collectionId,
      scenarioId: report.scenarioId,
      status: "open",
      page: report.page,
      focusTitle: report.focusTitle,
      focusDetails: report.focusDetails,
      categories: report.categories,
      createdAt,
      expiresAt: Timestamp.fromMillis(createdAt.toMillis() + retentionDays * 86_400_000),
    };
    if (report.note) payload.note = report.note;
    if (report.sessionMode) payload.sessionMode = report.sessionMode;
    if (report.quizQuestionNumber !== undefined) payload.quizQuestionNumber = report.quizQuestionNumber;
    if (report.publishedVariantId) payload.publishedVariantId = report.publishedVariantId;
    if (report.publishedContentHash) payload.publishedContentHash = report.publishedContentHash;
    if (report.appVersion) payload.appVersion = report.appVersion;
    if (report.osVersion) payload.osVersion = report.osVersion;
    if (report.deviceId) {
      payload.deviceHash = createHash("sha256").update(report.deviceId).digest("hex").slice(0, 32);
    }

    const counters: Record<string, FieldValue> = {
      count: FieldValue.increment(1),
      open: FieldValue.increment(1),
    };
    for (const category of report.categories) {
      counters[`categories.${category}`] = FieldValue.increment(1);
    }

    tx.set(reportRef, payload);
    tx.set(rateRef, { count: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    tx.set(
      db.collection("lessonReportStats").doc(sceneKey),
      {
        ...counters,
        collectionId: report.collectionId,
        scenarioId: report.scenarioId,
        lastReportedAt: createdAt,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return "created" as const;
  });

  log("INFO", "lesson report", {
    scene: sceneKey,
    user: userHash(uid),
    reportId: report.reportId,
    categories: report.categories.join(","),
    outcome,
  });
}

function parseLessonReport(body: unknown): ParsedLessonReport {
  if (!isObject(body)) throw invalid("body must be an object");

  const reportId = stringField(body, "reportId", 64);
  if (!UUID_RE.test(reportId)) throw invalid("reportId must be a uuid");

  const collectionId = stringField(body, "collectionId", 120);
  const scenarioId = stringField(body, "scenarioId", 120);
  for (const [key, value] of [["collectionId", collectionId], ["scenarioId", scenarioId]] as const) {
    if (!SEGMENT_RE.test(value) || value.includes("__") || value === "." || value === "..") {
      throw invalid(`${key} has unsupported characters`);
    }
  }

  const page = body.page;
  if (typeof page !== "string" || !(LESSON_REPORT_PAGES as readonly string[]).includes(page)) {
    throw invalid(`page must be one of: ${LESSON_REPORT_PAGES.join(", ")}`);
  }

  const rawCategories = body.categories ?? [];
  if (!Array.isArray(rawCategories) || rawCategories.length > LESSON_REPORT_CATEGORIES.length) {
    throw invalid("categories must be an array");
  }
  const categories: LessonReportCategory[] = [];
  for (const value of rawCategories) {
    if (typeof value !== "string" || !(LESSON_REPORT_CATEGORIES as readonly string[]).includes(value)) {
      throw invalid(`category ${String(value)} is not recognized`);
    }
    if (!categories.includes(value as LessonReportCategory)) {
      categories.push(value as LessonReportCategory);
    }
  }

  const note = optionalField(body, "note", NOTE_MAX);
  if (categories.length === 0 && !note) throw invalid("a category or a note is required");

  const rawDetails = body.focusDetails ?? [];
  if (
    !Array.isArray(rawDetails) ||
    rawDetails.length > FOCUS_DETAILS_MAX ||
    rawDetails.some((line) => typeof line !== "string" || line.length > FOCUS_DETAIL_LINE_MAX)
  ) {
    throw invalid(`focusDetails must be at most ${FOCUS_DETAILS_MAX} strings of ${FOCUS_DETAIL_LINE_MAX} chars`);
  }

  let quizQuestionNumber: number | undefined;
  if (body.quizQuestionNumber !== undefined && body.quizQuestionNumber !== null) {
    const value = body.quizQuestionNumber;
    if (!Number.isInteger(value) || (value as number) < 0 || (value as number) > 1000) {
      throw invalid("quizQuestionNumber must be an integer from 0 to 1000");
    }
    quizQuestionNumber = value as number;
  }

  let deviceId: string | undefined;
  if (body.deviceId !== undefined && body.deviceId !== null) {
    if (typeof body.deviceId !== "string" || !DEVICE_RE.test(body.deviceId)) {
      throw invalid("deviceId must be 8-64 url-safe characters");
    }
    deviceId = body.deviceId;
  }

  return {
    reportId: reportId.toLowerCase(),
    collectionId,
    scenarioId,
    publishedVariantId: optionalField(body, "publishedVariantId", 120),
    publishedContentHash: optionalField(body, "publishedContentHash", 128),
    page: page as LessonReportPage,
    focusTitle: stringField(body, "focusTitle", FOCUS_TITLE_MAX),
    focusDetails: (rawDetails as string[]).map((line) => line.trim()).filter(Boolean),
    sessionMode: optionalField(body, "sessionMode", 64),
    quizQuestionNumber,
    categories,
    note,
    appVersion: optionalField(body, "appVersion", 32),
    osVersion: optionalField(body, "osVersion", 32),
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

function hourKey(at = new Date()): string {
  return at.toISOString().slice(0, 13);
}

function numberField(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}
