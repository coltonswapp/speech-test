import "server-only";
import { eq, inArray } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db/client";
import { appSettings, ttsProject, ttsVariant } from "@/lib/db/schema";
import { getObject } from "@/lib/storage/r2";
import { wavToPcm16, pcm16ToFloat32 } from "@/lib/tts/wav";
import { conversationContentHash } from "@/lib/tts/content-hash";
import { loadConversationLines, UserFacingError } from "@/lib/tts/project-lines";
import { alignerConfigured, alignVariantAudio, AlignerError } from "@/lib/aligner/client";
import { tokenizeJapaneseLines } from "@/lib/dialogue/gemini-tokenize";
import { DialogueGenerationError } from "@/lib/dialogue/gemini-generate";
import { isAllPunctuationOrWhitespace } from "@/lib/dialogue/japanese-segmentation";
import { parseVariantTokenSync, tokenSyncStatus, clearFlagsForReviewed } from "@/lib/dialogue/token-sync";
import { autoStampTokenSync } from "@/lib/dialogue/token-sync-auto";
import { recordAutoStamp } from "@/lib/dialogue/review-timing";
import {
  lineMarkAttentionCount,
  notifyAutoStampReview,
} from "@/lib/dialogue/auto-stamp-review-webhook";
import type { TokenSyncFlag, VariantTokenSync } from "@/lib/dialogue/types";

export { clearFlagsForReviewed };

/**
 * Auto-stamp a take: forced-align its script and write an `auto` tokenSync
 * plus derived line marks when it has none. Shared by the manual route, the
 * generate → tokenize → align chain (KA-7) and any agent tool.
 */

export type AutoStampFailure = {
  ok: false;
  status: number;
  error: string;
  code?: "human-stamps" | "marks-mismatch" | "stale" | "not-configured" | "cancelled";
};
export type AutoStampSuccess = {
  ok: true;
  variant: typeof ttsVariant.$inferSelect;
  flags: TokenSyncFlag[];
  marksDerived: boolean;
  summary: string;
};
export type AutoStampOutcome = AutoStampSuccess | AutoStampFailure;

function hasHumanStamps(sync: VariantTokenSync | null): boolean {
  if (!sync) return false;
  if (sync.source === "human" || sync.source === "reviewed") return true;
  if (sync.source === "auto") return false;
  // Legacy take with no provenance: any non-first stamp was tapped by hand.
  return sync.lines.some((line) =>
    line.tokens.some((token, i) => i > 0 && token.startSeconds != null)
  );
}

export async function autoStampVariant(params: {
  variantId: string;
  projectId?: string;
  force?: boolean;
  /** Cooperative cancel for the generate → align chain. */
  signal?: AbortSignal;
}): Promise<AutoStampOutcome> {
  const force = params.force === true;
  const signal = params.signal;
  const wallStartMs = Date.now();
  const wallSeconds = () =>
    Math.round(((Date.now() - wallStartMs) / 1000) * 10) / 10;

  const notifyFailed = (
    error: string,
    opts?: {
      project?: typeof ttsProject.$inferSelect;
      projectId?: string;
      alignSeconds?: number | null;
    }
  ) => {
    notifyAutoStampReview({
      kind: "auto-stamp-failed",
      variantId: params.variantId,
      projectId: opts?.projectId ?? opts?.project?.id ?? params.projectId,
      project: opts?.project,
      summary: error,
      alignSeconds: opts?.alignSeconds ?? null,
      wallSeconds: wallSeconds(),
    });
  };

  if (signal?.aborted) {
    return { ok: false, status: 499, code: "cancelled", error: "Auto-stamp aborted." };
  }
  if (!alignerConfigured()) {
    const error = "Aligner is not configured (ALIGNER_URL / ALIGNER_TOKEN).";
    notifyFailed(error, { projectId: params.projectId });
    return {
      ok: false,
      status: 503,
      code: "not-configured",
      error,
    };
  }

  const variant = await db.query.ttsVariant.findFirst({
    where: eq(ttsVariant.id, params.variantId),
  });
  if (!variant || (params.projectId && variant.projectId !== params.projectId)) {
    return { ok: false, status: 404, error: "Not found" };
  }
  const project = await db.query.ttsProject.findFirst({
    where: eq(ttsProject.id, variant.projectId),
  });
  if (!project) return { ok: false, status: 404, error: "Not found" };

  try {
    return await runAutoStampBody({
      params,
      force,
      signal,
      variant,
      project,
      wallSeconds,
      notifyFailed,
    });
  } catch (error) {
    if (!signal?.aborted) {
      const message = error instanceof Error ? error.message : String(error);
      notifyFailed(message, { project });
    }
    throw error;
  }
}

async function runAutoStampBody(args: {
  params: { variantId: string; projectId?: string; force?: boolean; signal?: AbortSignal };
  force: boolean;
  signal?: AbortSignal;
  variant: typeof ttsVariant.$inferSelect;
  project: typeof ttsProject.$inferSelect;
  wallSeconds: () => number;
  notifyFailed: (
    error: string,
    opts?: {
      project?: typeof ttsProject.$inferSelect;
      projectId?: string;
      alignSeconds?: number | null;
    }
  ) => void;
}): Promise<AutoStampOutcome> {
  const { force, signal, variant, project, wallSeconds, notifyFailed, params } = args;

  let conversation;
  try {
    conversation = await loadConversationLines(project);
  } catch (error) {
    if (error instanceof UserFacingError) {
      notifyFailed(error.message, { project });
      return { ok: false, status: 400, error: error.message };
    }
    throw error;
  }
  const spokenTexts = conversation.map((line) => line.text.trim()).filter(Boolean);
  if (spokenTexts.length === 0) {
    const error = "No spoken lines.";
    notifyFailed(error, { project });
    return { ok: false, status: 400, error };
  }
  const contentHash = conversationContentHash(conversation);
  if (variant.contentHash && variant.contentHash !== contentHash) {
    const error =
      "Dialogue text changed since this take was generated. Regenerate the take first.";
    notifyFailed(error, { project });
    return {
      ok: false,
      status: 409,
      code: "stale",
      error,
    };
  }

  const existingSync = parseVariantTokenSync(variant.tokenSync);
  const status = tokenSyncStatus(existingSync, contentHash, spokenTexts);
  if (!force && (status === "tokens-only" || status === "complete") && hasHumanStamps(existingSync)) {
    const error = "This take already has human stamps. Re-run with force to replace them.";
    notifyFailed(error, { project });
    return {
      ok: false,
      status: 409,
      code: "human-stamps",
      error,
    };
  }

  const existingMarks = variant.dialogueLineSwitchSamples ?? [];
  const needed = spokenTexts.length - 1;
  if (!force && existingMarks.length > 0 && existingMarks.length !== needed) {
    const error = `This take has ${existingMarks.length} line marks but needs ${needed}. Fix the marks or re-run with force.`;
    notifyFailed(error, { project });
    return {
      ok: false,
      status: 409,
      code: "marks-mismatch",
      error,
    };
  }

  // Token surfaces: reuse the take's current tokens when they still match the
  // script (they may carry editor splits/merges), otherwise tokenize (cached).
  let lines: Array<{ text: string; tokens: Array<{ text: string; reading?: string }> }>;
  if (existingSync && status !== "missing" && status !== "stale") {
    lines = existingSync.lines.map((line) => ({
      text: line.text,
      tokens: line.tokens.map((token) => ({
        text: token.text,
        ...(token.reading ? { reading: token.reading } : {}),
      })),
    }));
  } else {
    try {
      const tokenized = await tokenizeJapaneseLines(spokenTexts);
      lines = tokenized.map((line) => ({
        text: line.text,
        tokens: line.tokens
          .filter((token) => token.text.length > 0 && !isAllPunctuationOrWhitespace(token.text))
          .map((token) => ({
            text: token.text,
            ...(token.reading ? { reading: token.reading } : {}),
          })),
      }));
    } catch (error) {
      if (error instanceof DialogueGenerationError) {
        notifyFailed(error.message, { project });
        return { ok: false, status: 502, error: error.message };
      }
      throw error;
    }
  }
  if (lines.some((line) => line.tokens.length === 0)) {
    const error = "A line has no alignable tokens.";
    notifyFailed(error, { project });
    return { ok: false, status: 422, error };
  }

  if (signal?.aborted) {
    return { ok: false, status: 499, code: "cancelled", error: "Auto-stamp aborted." };
  }

  const wav = await getObject(variant.audioObjectKey);
  const { pcm, sampleRate } = wavToPcm16(wav);
  const samples = pcm16ToFloat32(pcm);

  let aligned;
  try {
    aligned = await alignVariantAudio({
      audioObjectKey: variant.audioObjectKey,
      lines,
      signal,
    });
  } catch (error) {
    if (signal?.aborted) {
      return { ok: false, status: 499, code: "cancelled", error: "Auto-stamp aborted." };
    }
    if (error instanceof AlignerError) {
      notifyFailed(error.message, { project });
      return { ok: false, status: 502, error: error.message };
    }
    throw error;
  }

  const alignSeconds =
    typeof aligned.timings?.alignSeconds === "number"
      ? aligned.timings.alignSeconds
      : null;

  const result = autoStampTokenSync({
    alignerVersion: aligned.alignerVersion,
    aligned: aligned.lines,
    lines,
    samples,
    sampleRate,
    contentHash,
    existingMarkSamples: existingMarks.length === needed ? existingMarks : null,
  });

  // Best-effort: if abort landed mid-align, skip the write so stamps/marks
  // are not committed. If the write has already started, it may still land.
  if (signal?.aborted || (await isAutoStampCancelled(params.variantId))) {
    return { ok: false, status: 499, code: "cancelled", error: "Auto-stamp aborted." };
  }

  const [updated] = await db
    .update(ttsVariant)
    .set({
      tokenSync: result.tokenSync,
      ...(result.marksDerived ? { dialogueLineSwitchSamples: result.markSamples } : {}),
    })
    .where(eq(ttsVariant.id, variant.id))
    .returning();
  await recordAutoStamp(variant.id, result.tokenSync).catch((error: unknown) => {
    console.error(`[auto-stamp] timing record failed for ${variant.id}:`, error);
  });

  const tokenCount = lines.reduce((n, line) => n + line.tokens.length, 0);
  const summary = [
    `Auto-stamped ${tokenCount} tokens in ${lines.length} lines`,
    result.marksDerived && result.markSamples.length > 0
      ? `, derived ${result.markSamples.length} line marks`
      : "",
    result.flags.length > 0 ? `, ${result.flags.length} flagged for review` : "",
    alignSeconds != null ? ` (${alignSeconds.toFixed(1)} s align)` : "",
    ".",
  ].join("");

  const lmAttention = lineMarkAttentionCount(result.flags);
  if (result.flags.length > 0 || lmAttention > 0) {
    notifyAutoStampReview({
      kind: "auto-stamp-review",
      variantId: variant.id,
      projectId: project.id,
      project,
      flags: result.flags,
      summary,
      alignSeconds,
      wallSeconds: wallSeconds(),
    });
  }

  return { ok: true, variant: updated, flags: result.flags, marksDerived: result.marksDerived, summary };
}

// ---- background job state (generate → tokenize → align chain) ----------------
// Stored in app_settings so no migration is needed; the Audio tab polls the
// variants list while a job is queued/running.

export const autoStampJobSchema = z.object({
  status: z.enum(["queued", "running", "done", "error", "cancelled"]),
  message: z.string().optional(),
  /** Set once when the job is first queued; used for elapsed/final duration. */
  startedAt: z.string(),
  updatedAt: z.string(),
  /** Set when the job reaches done / error / cancelled. */
  finishedAt: z.string().optional(),
});
export type AutoStampJob = z.infer<typeof autoStampJobSchema>;

function jobKey(variantId: string): string {
  return `auto-stamp-job:${variantId}`;
}

/** In-flight AbortControllers for cooperative cancel of the background chain. */
const chainControllers = new Map<string, AbortController>();

export async function setAutoStampJob(
  variantId: string,
  job: Omit<AutoStampJob, "updatedAt"> & { updatedAt?: string }
): Promise<void> {
  const value: AutoStampJob = {
    ...job,
    updatedAt: job.updatedAt ?? new Date().toISOString(),
  };
  await db
    .insert(appSettings)
    .values({ key: jobKey(variantId), value })
    .onConflictDoUpdate({ target: appSettings.key, set: { value } });
}

export async function clearAutoStampJob(variantId: string): Promise<void> {
  chainControllers.get(variantId)?.abort();
  chainControllers.delete(variantId);
  await db.delete(appSettings).where(eq(appSettings.key, jobKey(variantId)));
}

export async function getAutoStampJob(variantId: string): Promise<AutoStampJob | null> {
  const jobs = await getAutoStampJobs([variantId]);
  return jobs.get(variantId) ?? null;
}

export async function getAutoStampJobs(
  variantIds: string[]
): Promise<Map<string, AutoStampJob>> {
  const out = new Map<string, AutoStampJob>();
  if (variantIds.length === 0) return out;
  const rows = await db
    .select()
    .from(appSettings)
    .where(inArray(appSettings.key, variantIds.map(jobKey)));
  for (const row of rows) {
    const parsed = autoStampJobSchema.safeParse(row.value);
    if (parsed.success) {
      out.set(row.key.slice(jobKey("").length), parsed.data);
      continue;
    }
    // Back-compat: jobs written before startedAt existed.
    const legacy = z
      .object({
        status: z.enum(["queued", "running", "done", "error", "cancelled"]),
        message: z.string().optional(),
        updatedAt: z.string(),
        startedAt: z.string().optional(),
        finishedAt: z.string().optional(),
      })
      .safeParse(row.value);
    if (legacy.success) {
      out.set(row.key.slice(jobKey("").length), {
        ...legacy.data,
        startedAt: legacy.data.startedAt ?? legacy.data.updatedAt,
      });
    }
  }
  return out;
}

export async function isAutoStampCancelled(variantId: string): Promise<boolean> {
  const job = await getAutoStampJob(variantId);
  return job?.status === "cancelled";
}

/**
 * Abort a queued/running background auto-stamp. Aborts the in-flight aligner
 * fetch when present, and marks the job cancelled so the chain skips the
 * stamp write (best-effort if already mid-write).
 */
export async function cancelAutoStampJob(variantId: string): Promise<{
  ok: boolean;
  job: AutoStampJob | null;
  error?: string;
}> {
  const job = await getAutoStampJob(variantId);
  if (!job) {
    return { ok: false, job: null, error: "No auto-stamp job for this take." };
  }
  if (job.status !== "queued" && job.status !== "running") {
    return { ok: false, job, error: `Job is already ${job.status}.` };
  }
  chainControllers.get(variantId)?.abort();
  const finishedAt = new Date().toISOString();
  const next: AutoStampJob = {
    status: "cancelled",
    message: "Aborted",
    startedAt: job.startedAt,
    updatedAt: finishedAt,
    finishedAt,
  };
  await setAutoStampJob(variantId, next);
  return { ok: true, job: next };
}

/**
 * The chain body: tokenize (cached) + align + write, with job state around
 * it. Never throws — the caller runs it after the generate response is sent.
 */
export async function runAutoStampChain(variantId: string): Promise<void> {
  const existing = await getAutoStampJob(variantId);
  if (existing?.status === "cancelled") return;

  const startedAt = existing?.startedAt ?? new Date().toISOString();
  const controller = new AbortController();
  chainControllers.set(variantId, controller);

  try {
    await setAutoStampJob(variantId, { status: "running", startedAt });
    if (controller.signal.aborted || (await isAutoStampCancelled(variantId))) {
      return;
    }

    const outcome = await autoStampVariant({
      variantId,
      signal: controller.signal,
    });

    // Re-read: cancel may have won the race during align/write checks.
    if ((!outcome.ok && outcome.code === "cancelled") || (await isAutoStampCancelled(variantId))) {
      const finishedAt = new Date().toISOString();
      await setAutoStampJob(variantId, {
        status: "cancelled",
        message: "Aborted",
        startedAt,
        finishedAt,
      });
      return;
    }

    const finishedAt = new Date().toISOString();
    if (outcome.ok) {
      await setAutoStampJob(variantId, {
        status: "done",
        startedAt,
        finishedAt,
      });
    } else {
      await setAutoStampJob(variantId, {
        status: "error",
        message: outcome.error,
        startedAt,
        finishedAt,
      });
    }
  } catch (error) {
    if (controller.signal.aborted || (await isAutoStampCancelled(variantId))) {
      const finishedAt = new Date().toISOString();
      await setAutoStampJob(variantId, {
        status: "cancelled",
        message: "Aborted",
        startedAt,
        finishedAt,
      }).catch(() => undefined);
      return;
    }
    const message = error instanceof Error ? error.message : String(error);
    console.error(`[auto-stamp] ${variantId}: ${message}`);
    const finishedAt = new Date().toISOString();
    // Failure notify already fired inside autoStampVariant (returned error or throw).
    await setAutoStampJob(variantId, {
      status: "error",
      message,
      startedAt,
      finishedAt,
    }).catch(() => undefined);
  } finally {
    chainControllers.delete(variantId);
  }
}
