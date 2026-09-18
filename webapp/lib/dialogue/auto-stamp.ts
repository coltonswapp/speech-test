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
import { parseVariantTokenSync, tokenSyncStatus } from "@/lib/dialogue/token-sync";
import { autoStampTokenSync } from "@/lib/dialogue/token-sync-auto";
import type { TokenSyncFlag, VariantTokenSync } from "@/lib/dialogue/types";

/**
 * Auto-stamp a take: forced-align its script and write an `auto` tokenSync
 * plus derived line marks when it has none. Shared by the manual route, the
 * generate → tokenize → align chain (KA-7) and any agent tool.
 */

export type AutoStampFailure = {
  ok: false;
  status: number;
  error: string;
  code?: "human-stamps" | "marks-mismatch" | "stale" | "not-configured";
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
}): Promise<AutoStampOutcome> {
  const force = params.force === true;
  if (!alignerConfigured()) {
    return {
      ok: false,
      status: 503,
      code: "not-configured",
      error: "Aligner is not configured (ALIGNER_URL / ALIGNER_TOKEN).",
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

  let conversation;
  try {
    conversation = await loadConversationLines(project);
  } catch (error) {
    if (error instanceof UserFacingError) {
      return { ok: false, status: 400, error: error.message };
    }
    throw error;
  }
  const spokenTexts = conversation.map((line) => line.text.trim()).filter(Boolean);
  if (spokenTexts.length === 0) {
    return { ok: false, status: 400, error: "No spoken lines." };
  }
  const contentHash = conversationContentHash(conversation);
  if (variant.contentHash && variant.contentHash !== contentHash) {
    return {
      ok: false,
      status: 409,
      code: "stale",
      error: "Dialogue text changed since this take was generated. Regenerate the take first.",
    };
  }

  const existingSync = parseVariantTokenSync(variant.tokenSync);
  const status = tokenSyncStatus(existingSync, contentHash, spokenTexts);
  if (!force && (status === "tokens-only" || status === "complete") && hasHumanStamps(existingSync)) {
    return {
      ok: false,
      status: 409,
      code: "human-stamps",
      error: "This take already has human stamps. Re-run with force to replace them.",
    };
  }

  const existingMarks = variant.dialogueLineSwitchSamples ?? [];
  const needed = spokenTexts.length - 1;
  if (!force && existingMarks.length > 0 && existingMarks.length !== needed) {
    return {
      ok: false,
      status: 409,
      code: "marks-mismatch",
      error: `This take has ${existingMarks.length} line marks but needs ${needed}. Fix the marks or re-run with force.`,
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
        return { ok: false, status: 502, error: error.message };
      }
      throw error;
    }
  }
  if (lines.some((line) => line.tokens.length === 0)) {
    return { ok: false, status: 422, error: "A line has no alignable tokens." };
  }

  const wav = await getObject(variant.audioObjectKey);
  const { pcm, sampleRate } = wavToPcm16(wav);
  const samples = pcm16ToFloat32(pcm);

  let aligned;
  try {
    aligned = await alignVariantAudio({ audioObjectKey: variant.audioObjectKey, lines });
  } catch (error) {
    if (error instanceof AlignerError) {
      return { ok: false, status: 502, error: error.message };
    }
    throw error;
  }

  const result = autoStampTokenSync({
    alignerVersion: aligned.alignerVersion,
    aligned: aligned.lines,
    lines,
    samples,
    sampleRate,
    contentHash,
    existingMarkSamples: existingMarks.length === needed ? existingMarks : null,
  });

  const [updated] = await db
    .update(ttsVariant)
    .set({
      tokenSync: result.tokenSync,
      ...(result.marksDerived ? { dialogueLineSwitchSamples: result.markSamples } : {}),
    })
    .where(eq(ttsVariant.id, variant.id))
    .returning();

  const tokenCount = lines.reduce((n, line) => n + line.tokens.length, 0);
  const summary = [
    `Auto-stamped ${tokenCount} tokens in ${lines.length} lines`,
    result.marksDerived && result.markSamples.length > 0
      ? `, derived ${result.markSamples.length} line marks`
      : "",
    result.flags.length > 0 ? `, ${result.flags.length} flagged for review` : "",
    aligned.timings?.alignSeconds != null ? ` (${aligned.timings.alignSeconds.toFixed(1)} s align)` : "",
    ".",
  ].join("");

  return { ok: true, variant: updated, flags: result.flags, marksDerived: result.marksDerived, summary };
}

// ---- background job state (generate → tokenize → align chain) ----------------
// Stored in app_settings so no migration is needed; the Audio tab polls the
// variants list while a job is queued/running.

export const autoStampJobSchema = z.object({
  status: z.enum(["queued", "running", "done", "error"]),
  message: z.string().optional(),
  updatedAt: z.string(),
});
export type AutoStampJob = z.infer<typeof autoStampJobSchema>;

function jobKey(variantId: string): string {
  return `auto-stamp-job:${variantId}`;
}

export async function setAutoStampJob(
  variantId: string,
  job: Omit<AutoStampJob, "updatedAt">
): Promise<void> {
  const value: AutoStampJob = { ...job, updatedAt: new Date().toISOString() };
  await db
    .insert(appSettings)
    .values({ key: jobKey(variantId), value })
    .onConflictDoUpdate({ target: appSettings.key, set: { value } });
}

export async function clearAutoStampJob(variantId: string): Promise<void> {
  await db.delete(appSettings).where(eq(appSettings.key, jobKey(variantId)));
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
    if (parsed.success) out.set(row.key.slice(jobKey("").length), parsed.data);
  }
  return out;
}

/**
 * The chain body: tokenize (cached) + align + write, with job state around
 * it. Never throws — the caller runs it after the generate response is sent.
 */
export async function runAutoStampChain(variantId: string): Promise<void> {
  try {
    await setAutoStampJob(variantId, { status: "running" });
    const outcome = await autoStampVariant({ variantId });
    if (outcome.ok) {
      await clearAutoStampJob(variantId);
    } else {
      await setAutoStampJob(variantId, { status: "error", message: outcome.error });
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`[auto-stamp] ${variantId}: ${message}`);
    await setAutoStampJob(variantId, { status: "error", message }).catch(() => undefined);
  }
}
