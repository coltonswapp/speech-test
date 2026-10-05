import "server-only";

import {
  getFirebaseAdminStatus,
  getUsageFirestore,
} from "@/lib/usage/firebase-admin";
import {
  PRODUCT_LESSON_FEEDBACK_SCOPE,
  lessonSceneKey,
  parseLessonFeedbackEntry,
  parseLessonFeedbackStats,
  type LessonFeedbackEntry,
  type LessonFeedbackOverview,
  type LessonFeedbackStats,
  type ScenarioFeedback,
} from "@/lib/lesson-feedback/types";

export class LessonFeedbackFirestoreError extends Error {
  constructor(
    message: string,
    readonly code: "not_configured" | "read_failed",
  ) {
    super(message);
    this.name = "LessonFeedbackFirestoreError";
  }
}

function ensureConfigured() {
  const status = getFirebaseAdminStatus();
  if (!status.ok) {
    throw new LessonFeedbackFirestoreError(status.reason, "not_configured");
  }
}

function readFailed(err: unknown): LessonFeedbackFirestoreError {
  const message = err instanceof Error ? err.message : "Firestore read failed";
  return new LessonFeedbackFirestoreError(message, "read_failed");
}

export async function readScenarioFeedback(
  collectionId: string,
  scenarioId: string,
  recentLimit = 20,
): Promise<ScenarioFeedback> {
  ensureConfigured();
  const db = getUsageFirestore();
  const sceneKey = lessonSceneKey(collectionId, scenarioId);

  let stats: LessonFeedbackStats;
  try {
    const snap = await db.collection("lessonFeedbackStats").doc(sceneKey).get();
    stats = parseLessonFeedbackStats(
      sceneKey,
      snap.exists ? (snap.data() as Record<string, unknown>) : null,
    );
  } catch (err) {
    throw readFailed(err);
  }

  let recent: LessonFeedbackEntry[] = [];
  let recentError: string | null = null;
  try {
    const query = await db
      .collection("lessonFeedback")
      .where("sceneKey", "==", sceneKey)
      .orderBy("createdAt", "desc")
      .limit(recentLimit)
      .get();
    recent = query.docs.map((doc: { id: string; data: () => Record<string, unknown> }) =>
      parseLessonFeedbackEntry(doc.id, doc.data() as Record<string, unknown>),
    );
  } catch (err) {
    recentError = err instanceof Error ? err.message : "Failed to load ratings";
  }

  return { stats, recent, recentError };
}

/** All rated scenes, weakest dimension first. One collection read. */
export async function readLowestRatedScenes(
  limit = 25,
): Promise<LessonFeedbackOverview> {
  ensureConfigured();
  try {
    const snap = await getUsageFirestore()
      .collection("lessonFeedbackStats")
      .get();
    let product = parseLessonFeedbackStats(PRODUCT_LESSON_FEEDBACK_SCOPE, null);
    const scenes: LessonFeedbackStats[] = [];
    for (const doc of snap.docs) {
      const parsed = parseLessonFeedbackStats(
        doc.id,
        doc.data() as Record<string, unknown>,
      );
      if (doc.id === PRODUCT_LESSON_FEEDBACK_SCOPE) {
        product = parsed;
      } else if (parsed.lowest) {
        scenes.push(parsed);
      }
    }
    scenes.sort(
      (a, b) =>
        (a.lowest?.average ?? 5) - (b.lowest?.average ?? 5) ||
        b.count - a.count,
    );
    return { product, scenes: scenes.slice(0, limit) };
  } catch (err) {
    throw readFailed(err);
  }
}
