import "server-only";
import { createHash, randomUUID } from "node:crypto";
import { FieldValue } from "firebase-admin/firestore";
import { getFirebaseAdminStatus, getUsageFirestore } from "@/lib/usage/firebase-admin";
import { setReportStatusInTransaction } from "@/lib/lesson-reports/firestore";
import { parseLessonReportEntry, isLessonReportStatus } from "@/lib/lesson-reports/types";
import { getPublicDialogueCollectionFile } from "@/lib/dialogue/public-api";
import { AttemptError } from "@/lib/clip-agent/store";
import { outcomeResolvesReport, type ClipAgentOutcome } from "@/lib/clip-agent/schema";
import { agentSettings } from "./agents";

type SceneAttempt = {
  id: string;
  status: "dispatched" | "working" | "done" | "failed";
  agent: string;
  createdAt: string;
  startedAt: string | null;
  finishedAt?: string;
  outcome?: ClipAgentOutcome;
  summary?: string;
  revision?: string | null;
};

function reference(id: string) {
  if (!getFirebaseAdminStatus().ok) throw new AttemptError("Scene reports are unavailable.", 503);
  return getUsageFirestore().collection("lessonReports").doc(id);
}

export async function sceneDetail(id: string) {
  const ref = reference(id);
  const doc = await ref.get();
  if (!doc.exists) throw new AttemptError("Scene report not found", 404);
  const data = doc.data()!;
  const history = await ref.collection("attempts").orderBy("createdAt", "desc").get();
  return {
    ...parseLessonReportEntry(id, data), collectionId: String(data.collectionId), scenarioId: String(data.scenarioId),
    pickedWord: typeof data.pickedWord === "string" ? data.pickedWord : null,
    playbackSeconds: typeof data.playbackSeconds === "number" && Number.isFinite(data.playbackSeconds) ? data.playbackSeconds : null,
    reportedContentHash: data.publishedContentHash ?? null,
    activeAttempt: typeof data.activeAttempt === "string" ? data.activeAttempt : null,
    attempts: history.docs.map(doc => ({ ...doc.data(), id: doc.id }) as SceneAttempt),
  };
}

export async function publishedScene(id: string) {
  const doc = await reference(id).get();
  if (!doc.exists) throw new AttemptError("Scene report not found", 404);
  const collectionId = doc.get("collectionId");
  const slug = doc.get("scenarioId");
  const collection = await getPublicDialogueCollectionFile(collectionId);
  const scene = collection?.scenarios.find(s => s.id === slug || s.id === collectionId + "/" + slug);
  if (!scene) throw new AttemptError("Scene unavailable in the learner export", 409);
  // Includes quiz, highlights and timing, which a voice take's hash alone cannot identify.
  const content = { ...scene, publishedAt: undefined };
  return { revision: createHash("sha256").update(JSON.stringify(content)).digest("hex"), scene };
}

export async function startScene(id: string, dispatch: boolean, agent: string, requester: string, expectedAttempt?: string) {
  if (agent !== "hana") throw new AttemptError("Scenes are assigned to Hana", 400);
  if (dispatch && !(await agentSettings()).hana) throw new AttemptError("Configure Hana in Settings → Agents", 409);
  const ref = reference(id);
  // A missing public scene can still be investigated, but needs review.
  const before = dispatch ? null : await publishedScene(id).catch(error => {
    if (error instanceof AttemptError && error.status === 409) return null;
    throw error;
  });
  const attemptId = await getUsageFirestore().runTransaction(async tx => {
    const report = await tx.get(ref);
    if (!report.exists) throw new AttemptError("Scene report not found", 404);
    if (report.get("status") !== "open") throw new AttemptError("Issue is closed", 409);
    const active = report.get("activeAttempt");
    if (expectedAttempt && active !== expectedAttempt) throw new AttemptError("Dispatch is no longer active", 409);
    if (active) {
      const attempt = ref.collection("attempts").doc(active);
      const snap = await tx.get(attempt);
      if (!dispatch && snap.get("agent") === agent && snap.get("status") === "dispatched") {
        tx.update(attempt, {status: "working", startedAt: new Date().toISOString(), baselineRevision: before?.revision ?? null});
        return attempt.id;
      }
      if (!dispatch && expectedAttempt === active && snap.get("agent") === agent && snap.get("status") === "working") return attempt.id;
      throw new AttemptError("An agent already has this issue", 409);
    }
    const attempt = ref.collection("attempts").doc(randomUUID());
    const now = new Date().toISOString();
    tx.create(attempt, {agent, requester, status: dispatch ? "dispatched" : "working", createdAt: now, startedAt: dispatch ? null : now, baselineRevision: before?.revision ?? null});
    tx.update(ref, {activeAttempt: attempt.id});
    return attempt.id;
  });
  if (dispatch) {
    try {
      const response = await fetch(process.env.HANA_ISSUES_WEBHOOK_URL!, {
        method: "POST", redirect: "error", signal: AbortSignal.timeout(10000),
        headers: {"Content-Type":"application/json", Authorization: "Bearer " + process.env.HANA_ISSUES_WEBHOOK_SECRET},
        body: JSON.stringify({type: "content-issue.dispatched", agent, issueId: "scene-" + id, attemptId}),
      });
      if (!response.ok) throw new Error("Webhook returned HTTP " + response.status);
    } catch (error) {
      const failed = await getUsageFirestore().runTransaction(async tx => {
        const attempt = ref.collection("attempts").doc(attemptId);
        const [report, snap] = await Promise.all([tx.get(ref), tx.get(attempt)]);
        if (report.get("activeAttempt") !== attemptId || snap.get("status") !== "dispatched") return false;
        tx.update(attempt, {status: "failed", summary: error instanceof Error ? error.message : "Delivery failed", finishedAt: new Date().toISOString()});
        tx.update(ref, {activeAttempt: FieldValue.delete()});
        return true;
      });
      if (failed) throw new AttemptError("Hana webhook delivery failed. The issue can be dispatched again.", 502);
    }
  }
  return {attemptId, issueId: "scene-" + id};
}

export async function finishScene(id: string, attemptId: string, outcome: ClipAgentOutcome, summary: string, revision?: string) {
  const ref = reference(id);
  const attempt = ref.collection("attempts").doc(attemptId);
  const sameFinish = (current: FirebaseFirestore.DocumentSnapshot) =>
    current.get("status") === "done" && current.get("outcome") === outcome &&
    current.get("summary") === summary && (current.get("revision") ?? null) === (revision ?? null);

  const initial = await attempt.get();
  if (sameFinish(initial)) return {attemptId, outcome};
  if (initial.get("status") !== "working") throw new AttemptError("Attempt is not active", 409);
  const verified = outcome === "fixed" && revision
    ? (await publishedScene(id)).revision
    : null;

  return getUsageFirestore().runTransaction(async tx => {
    const [report, current] = await Promise.all([tx.get(ref), tx.get(attempt)]);
    if (sameFinish(current)) return {attemptId, outcome};
    if (!report.exists || current.get("status") !== "working" || report.get("activeAttempt") !== attemptId) {
      throw new AttemptError("Attempt is not active", 409);
    }
    const baseline = current.get("baselineRevision");
    if (outcome === "fixed" && (!baseline || !verified || verified !== revision || verified === baseline)) {
      throw new AttemptError("Publish a correction and verify the changed learner export before marking fixed. Use needs_review for a draft.", 409);
    }
    tx.update(attempt, {
      status: "done", outcome, summary, revision: revision ?? null, finishedAt: new Date().toISOString(),
    });
    tx.update(ref, { activeAttempt: FieldValue.delete() });
    const status = report.get("status");
    if ((!isLessonReportStatus(status) || status === "open") && outcomeResolvesReport(outcome)) {
      setReportStatusInTransaction(tx, report, "resolved");
    }
    return {attemptId, outcome};
  });
}

export async function recoverSceneAttempt(id: string, attemptId: string, requester: string, reason: string) {
  const ref = reference(id);
  const attempt = ref.collection("attempts").doc(attemptId);
  return ref.firestore.runTransaction(async tx => {
    const [report, current] = await Promise.all([tx.get(ref), tx.get(attempt)]);
    if (!report.exists) throw new AttemptError("Scene report not found", 404);
    if (report.get("activeAttempt") !== attemptId ||
        (current.exists && !["working", "dispatched"].includes(current.get("status")))) {
      throw new AttemptError("Attempt is no longer active", 409);
    }
    const now = new Date().toISOString();
    tx.set(attempt, {
      ...(!current.exists ? { agent: "hana", createdAt: now, startedAt: null } : {}),
      status: "failed", outcome: "could_not_fix", finishedAt: now,
      summary: `Stopped by ${requester}: ${reason}`,
    }, { merge: true });
    tx.update(ref, { activeAttempt: FieldValue.delete() });
    return { attemptId, status: "failed" };
  });
}
