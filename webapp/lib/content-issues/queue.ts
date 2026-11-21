import { FieldPath, Timestamp } from "firebase-admin/firestore";
import { z } from "zod";
import { clipEditorHref, issueSubjects, sceneEditorHref } from "./subjects";
import { listClipFeedback } from "@/lib/clip-feedback/admin";
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
  status: z.enum(["open", "resolved", "wontfix", "duplicate", "all"]).default("open"),
  cursor: cursorSchema.optional(),
});

const size = 50;

function unpack(value: string) {
  const [timestamp, subject, id] = value.split("|");
  return { timestamp, subject, id };
}

async function listScenes(q: z.output<typeof issueQuery>) {
  let query: FirebaseFirestore.Query = getUsageFirestore().collection("lessonReports");
  if (q.status !== "all") query = query.where("status", "==", q.status);
  query = query.orderBy("createdAt", "desc").orderBy(FieldPath.documentId(), "desc");
  if (q.cursor) {
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
  const snapshot = await Promise.race([query.limit(size + 1).get(), deadline])
    .finally(() => clearTimeout(timeout));
  return snapshot.docs.map(doc => {
    const row = parseLessonReportEntry(doc.id, doc.data());
    const time = doc.get("createdAt") as Timestamp;
    const timestamp = new Date(time.seconds * 1000).toISOString().slice(0, 19) +
      "." + String(time.nanoseconds).padStart(9, "0") + "Z";
    const collectionId = doc.get("collectionId");
    const scenarioId = doc.get("scenarioId");
    const sceneKey = doc.get("sceneKey");
    return {
      editorHref: typeof collectionId === "string" && collectionId && typeof scenarioId === "string" && scenarioId
        ? sceneEditorHref(collectionId, scenarioId) : null,
      key: doc.id, timestamp, id: "scene-" + doc.id, subject: "scene" as const,
      title: typeof sceneKey === "string" ? sceneKey : "Lesson scene", location: row.focusTitle, reasons: row.categories,
      status: row.status, note: row.note, createdAt: row.createdAt ?? "",
    };
  });
}

export async function listIssues(q: z.output<typeof issueQuery>) {
  async function scenePage() {
    if (q.subject === "clip" || q.status === "duplicate") return { rows: [], warning: null };
    if (!getFirebaseAdminStatus().ok) {
      return { rows: [], warning: "Scene reports unavailable. Firebase Admin is not configured." };
    }
    try {
      return { rows: await listScenes(q), warning: null };
    } catch (error) {
      console.warn("Unable to list scene reports", error);
      return { rows: [], warning: "Scene reports are temporarily unavailable." };
    }
  }

  const boundary = q.cursor ? unpack(q.cursor) : undefined;
  const [clips, scenes] = await Promise.all([
    q.subject === "scene" ? [] : listClipFeedback({
      status: q.status === "all" ? "issues" : q.status,
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
    editorHref: clipEditorHref(row.clipId),
    title: row.clipTitle ?? row.clipId, location: row.line?.textJP ?? null,
    reasons: row.reason ? [row.reason] : [], status: row.status, note: row.note, createdAt: row.createdAt,
  })), ...scenes.rows].sort((a, b) =>
    b.timestamp.localeCompare(a.timestamp) || (a.subject === b.subject ? 0 : a.subject === "clip" ? -1 : 1)
  );

  const page = merged.slice(0, size);
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
