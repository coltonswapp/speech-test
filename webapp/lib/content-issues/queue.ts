import { z } from "zod";
import { issueSubjects } from "./subjects";
import { listClipFeedback } from "@/lib/clip-feedback/admin";
import { getFirebaseAdminStatus, getUsageFirestore } from "@/lib/usage/firebase-admin";
import { parseLessonReportEntry } from "@/lib/lesson-reports/types";

export const issueQuery = z.object({
  subject: z.enum([...issueSubjects, "all"]).default("all"),
  status: z.enum(["open","resolved","wontfix","duplicate","all"]).default("open"),
  clips: z.coerce.number().int().min(0).max(10000000).default(0),
  scenes: z.coerce.number().int().min(0).max(10000000).default(0),
});
const size = 50;
export async function listIssues(q: z.output<typeof issueQuery>) {
  const firebase = getFirebaseAdminStatus();
  async function sceneRows() {
    if (q.subject === "clip" || !firebase.ok || q.status === "duplicate") return [];
    let query: FirebaseFirestore.Query = getUsageFirestore().collection("lessonReports");
    if (q.status !== "all") query = query.where("status","==",q.status);
    const snapshot = await query.orderBy("createdAt","desc").offset(q.scenes).limit(size+1).get();
    return snapshot.docs.map(doc => {
      const row = parseLessonReportEntry(doc.id, doc.data());
      return { id:"scene-"+doc.id, subject:"scene", title: String(doc.get("sceneKey")), location: row.focusTitle, reasons: row.categories, status: row.status, note: row.note, createdAt: row.createdAt ?? "" };
    });
  }
  const [clips, scenes] = await Promise.all([
    q.subject === "scene" ? [] : listClipFeedback({status:q.status === "all" ? "issues" : q.status, offset:q.clips, limit:size+1}),
    sceneRows(),
  ]);
  const merged = [...clips.map(r => ({ id:"clip-"+r.id, subject:"clip", title:r.clipTitle ?? r.clipId, location:r.line?.textJP ?? null, reasons:r.reason ? [r.reason] : [], status:r.status, note:r.note, createdAt:r.createdAt })), ...scenes]
    .sort((a,b) => b.createdAt.localeCompare(a.createdAt));
  const issues = merged.slice(0,size);
  const clipCount = issues.filter(r => r.subject === "clip").length;
  return {issues, next: merged.length > size ? {...q, clips:q.clips+clipCount, scenes:q.scenes+issues.length-clipCount} : null,
    warning: !firebase.ok && q.subject !== "clip" ? "Scene reports unavailable: Firebase Admin is not configured." : null};
}
