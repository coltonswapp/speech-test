import "server-only";

import { FieldValue } from "firebase-admin/firestore";
import {
  getFirebaseAdminStatus,
  getUsageFirestore,
} from "@/lib/usage/firebase-admin";
import { lessonSceneKey } from "@/lib/lesson-feedback/types";
import {
  isLessonReportStatus,
  parseLessonReportEntry,
  parseLessonReportStats,
  type LessonReportEntry,
  type LessonReportStats,
  type LessonReportStatus,
  type ScenarioReports,
} from "@/lib/lesson-reports/types";

export class LessonReportsFirestoreError extends Error {
  constructor(
    message: string,
    readonly code: "not_configured" | "read_failed" | "write_failed" | "not_found",
  ) {
    super(message);
    this.name = "LessonReportsFirestoreError";
  }
}

function ensureConfigured() {
  const status = getFirebaseAdminStatus();
  if (!status.ok) {
    throw new LessonReportsFirestoreError(status.reason, "not_configured");
  }
}

export async function readScenarioReports(
  collectionId: string,
  scenarioId: string,
  recentLimit = 50,
): Promise<ScenarioReports> {
  ensureConfigured();
  const db = getUsageFirestore();
  const sceneKey = lessonSceneKey(collectionId, scenarioId);

  let stats: LessonReportStats;
  try {
    const snap = await db.collection("lessonReportStats").doc(sceneKey).get();
    stats = parseLessonReportStats(
      sceneKey,
      snap.exists ? (snap.data() as Record<string, unknown>) : null,
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : "Firestore read failed";
    throw new LessonReportsFirestoreError(message, "read_failed");
  }

  let recent: LessonReportEntry[] = [];
  let recentError: string | null = null;
  try {
    const query = await db
      .collection("lessonReports")
      .where("sceneKey", "==", sceneKey)
      .orderBy("createdAt", "desc")
      .limit(recentLimit)
      .get();
    recent = query.docs.map((doc) =>
      parseLessonReportEntry(doc.id, doc.data() as Record<string, unknown>),
    );
  } catch (err) {
    recentError = err instanceof Error ? err.message : "Failed to load reports";
  }

  return { stats, recent, recentError };
}

/** Moves a report between statuses and keeps the scene's `open` counter in step. */
export async function updateReportStatus(
  reportId: string,
  status: LessonReportStatus,
): Promise<void> {
  ensureConfigured();
  const db = getUsageFirestore();
  const reportRef = db.collection("lessonReports").doc(reportId);

  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(reportRef);
      if (!snap.exists) {
        throw new LessonReportsFirestoreError("report not found", "not_found");
      }
      const previous = snap.get("status");
      const wasOpen = !isLessonReportStatus(previous) || previous === "open";
      const isOpen = status === "open";
      tx.update(reportRef, {
        status,
        statusUpdatedAt: FieldValue.serverTimestamp(),
      });
      const sceneKey = snap.get("sceneKey");
      if (wasOpen !== isOpen && typeof sceneKey === "string") {
        tx.set(
          db.collection("lessonReportStats").doc(sceneKey),
          {
            open: FieldValue.increment(isOpen ? 1 : -1),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
    });
  } catch (err) {
    if (err instanceof LessonReportsFirestoreError) throw err;
    const message = err instanceof Error ? err.message : "Firestore write failed";
    throw new LessonReportsFirestoreError(message, "write_failed");
  }
}
