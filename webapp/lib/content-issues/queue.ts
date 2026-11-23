import { FieldPath, Timestamp } from "firebase-admin/firestore";
import { z } from "zod";
import { issueSubjects } from "./subjects";
import { issueAttemptState, type AttemptSummary } from "./attempt-state";
import { sceneAttemptSummaries } from "./scenes";
import { listClipFeedback } from "@/lib/clip-feedback/admin";
import { clipAttemptSummaries } from "@/lib/clip-agent/store";
import { getFirebaseAdminStatus, getUsageFirestore } from "@/lib/usage/firebase-admin";
import { parseLessonReportEntry } from "@/lib/lesson-reports/types";

const cursorSchema = z.string()
  .regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{9}Z\|(clip|scene)\|[a-zA-Z0-9_-]{1,128}$/)
  .refine(value => {
    const seconds = value.slice(0, 19);
    const time = new Date(seconds + "Z");
    return Number.isFinite(time.getTime()) && time.toISOString().slice(0, 19) === seconds && !seconds.startsWith("0000");
  });

export const issueQuery = z.object({
  subject: z.enum([...issueSubjects, "all"]).default("all"),
  status: z.enum(["open", "needs_review", "resolved", "wontfix", "duplicate", "all"]).default("open"),
  cursor: cursorSchema.optional(),
});

const size = 50;
/** Open scene reports to scan when filtering to latest-attempt needs_review. */
const reviewScan = 500;

function unpack(value: string) {
  const [timestamp, subject, id] = value.split("|");
  return { timestamp, subject, id };
}

type SceneRow = {
  key: string;
  timestamp: string;
  id: string;
  subject: "scene";
  title: string;
  location: string | null;
  reasons: string[];
  status: string;
  note: string | null;
  createdAt: string;
  resolvedAt: string | null;
  reporterUserId: string | null;
};

function mapSceneDoc(doc: FirebaseFirestore.QueryDocumentSnapshot): SceneRow {
  const row = parseLessonReportEntry(doc.id, doc.data());
  const time = doc.get("createdAt") as Timestamp;
  const timestamp = new Date(time.seconds * 1000).toISOString().slice(0, 19) +
    "." + String(time.nanoseconds).padStart(9, "0") + "Z";
  return {
    key: doc.id, timestamp, id: "scene-" + doc.id, subject: "scene",
    title: String(doc.get("sceneKey")), location: row.focusTitle, reasons: row.categories,
    status: row.status, note: row.note, createdAt: row.createdAt ?? "",
    resolvedAt: row.status !== "open" ? row.statusUpdatedAt : null,
    reporterUserId: row.userId,
  };
}

function afterSceneCursor(rows: SceneRow[], cursor: string): SceneRow[] {
  const { timestamp, subject, id } = unpack(cursor);
  return rows.filter(row => {
    const cmp = row.timestamp.localeCompare(timestamp);
    if (subject === "scene") return cmp < 0 || (cmp === 0 && row.key < id);
    return cmp <= 0;
  });
}

async function listScenes(q: z.output<typeof issueQuery>) {
  const review = q.status === "needs_review";
  let query: FirebaseFirestore.Query = getUsageFirestore().collection("lessonReports");
  if (review) query = query.where("status", "==", "open");
  else if (q.status !== "all") query = query.where("status", "==", q.status);
  query = query.orderBy("createdAt", "desc").orderBy(FieldPath.documentId(), "desc");
  if (q.cursor && !review) {
    const { timestamp, subject, id } = unpack(q.cursor);
    const seconds = Date.parse(timestamp.slice(0, 19) + "Z") / 1000;
    const time = new Timestamp(seconds, Number(timestamp.slice(20, 29)));
    query = subject === "scene" ? query.startAfter(time, id) : query.startAt(time);
  }
  // Firestore retries transient connectivity errors. Bound the time a scene
  // outage can hold the clip queue open.
  let timeout: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<never>((_, reject) => {
    timeout = setTimeout(() => reject(new Error("Scene report query timed out")), 4000);
  });
  const snapshot = await Promise.race([query.limit(review ? reviewScan : size + 1).get(), deadline])
    .finally(() => clearTimeout(timeout));
  let rows = snapshot.docs.map(mapSceneDoc);
  if (!review) return { rows };
  const attempts = await sceneAttemptSummaries(rows.map(row => row.key));
  rows = rows.filter(row => issueAttemptState(attempts.get(row.key) ?? []).needsReview);
  if (q.cursor) rows = afterSceneCursor(rows, q.cursor);
  return { rows: rows.slice(0, size + 1), attempts };
}

async function withAttemptState<T extends {
  key: string;
  subject: "clip" | "scene";
  status: string | null;
}>(rows: T[], preloadedScenes?: Map<string, AttemptSummary[]>) {
  const clipIds = rows.filter(row => row.subject === "clip").map(row => row.key);
  const sceneIds = rows.filter(row => row.subject === "scene" && !preloadedScenes?.has(row.key)).map(row => row.key);
  try {
    const [clips, scenes] = await Promise.all([
      clipAttemptSummaries(clipIds),
      getFirebaseAdminStatus().ok ? sceneAttemptSummaries(sceneIds) : new Map(),
    ]);
    const sceneAttempts = preloadedScenes
      ? new Map([...preloadedScenes, ...scenes])
      : scenes;
    return rows.map(row => {
      const attempts = (row.subject === "clip" ? clips : sceneAttempts).get(row.key) ?? [];
      const state = issueAttemptState(attempts);
      return {
        ...row,
        needsReview: row.status === "open" && state.needsReview,
        agentWorking: row.status === "open" && state.agentWorking,
        agentFinishedAt: state.agentFinishedAt,
      };
    });
  } catch (error) {
    console.warn("Unable to load issue attempts", error);
    return rows.map(row => ({ ...row, needsReview: false, agentWorking: false, agentFinishedAt: null as string | null }));
  }
}

export async function listIssues(q: z.output<typeof issueQuery>) {
  async function scenePage() {
    if (q.subject === "clip" || q.status === "duplicate") return { rows: [] as SceneRow[], warning: null };
    if (!getFirebaseAdminStatus().ok) {
      return { rows: [] as SceneRow[], warning: "Scene reports unavailable. Firebase Admin is not configured." };
    }
    try {
      const listed = await listScenes(q);
      return { ...listed, warning: null };
    } catch (error) {
      console.warn("Unable to list scene reports", error);
      return { rows: [] as SceneRow[], warning: "Scene reports are temporarily unavailable." };
    }
  }

  const review = q.status === "needs_review";
  const boundary = q.cursor ? unpack(q.cursor) : undefined;
  const [clips, scenes] = await Promise.all([
    q.subject === "scene" ? [] : listClipFeedback({
      status:
        q.status === "all" ? "issues"
        : q.status === "resolved" || q.status === "wontfix" || q.status === "duplicate" ? q.status
        : "open",
      latestNeedsReview: review,
      before: boundary && {
        timestamp: boundary.timestamp.slice(0, 26) + "Z",
        id: boundary.subject === "clip" ? boundary.id : undefined,
        inclusive: boundary.subject === "scene" && boundary.timestamp.slice(26, 29) !== "000",
      },
      limit: size + 1,
    }),
    scenePage(),
  ]);
  const merged = [...clips.map(row => ({
    key: row.id, timestamp: row.cursorTimestamp, id: "clip-" + row.id, subject: "clip" as const,
    title: row.clipTitle ?? row.clipId, location: row.line?.textJP ?? null,
    reasons: row.reason ? [row.reason] : [], status: row.status, note: row.note, createdAt: row.createdAt,
    resolvedAt: row.status && row.status !== "open" ? row.resolvedAt ?? row.updatedAt : null,
    reporterUserId: row.userId,
  })), ...scenes.rows].sort((a, b) =>
    b.timestamp.localeCompare(a.timestamp) || (a.subject === b.subject ? 0 : a.subject === "clip" ? -1 : 1)
  );

  const page = await withAttemptState(
    merged.slice(0, size),
    "attempts" in scenes ? scenes.attempts : undefined,
  );
  const last = page.at(-1);
  return {
    issues: page.map(({ key, timestamp, ...issue }) => {
      void key;
      void timestamp;
      return issue;
    }),
    next: merged.length > size && last
      ? { ...q, cursor: [last.timestamp, last.subject, last.key].join("|") }
      : null,
    warning: scenes.warning,
  };
}
