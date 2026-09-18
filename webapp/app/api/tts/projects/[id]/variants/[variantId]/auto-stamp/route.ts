import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db/client";
import { ttsProject, ttsVariant } from "@/lib/db/schema";
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
import type { VariantTokenSync } from "@/lib/dialogue/types";

const bodySchema = z.object({
  /** Overwrite human/reviewed stamps and mismatched marks. */
  force: z.boolean().optional(),
});

function hasHumanStamps(sync: VariantTokenSync | null): boolean {
  if (!sync) return false;
  if (sync.source === "human" || sync.source === "reviewed") return true;
  if (sync.source === "auto") return false;
  // Legacy take with no provenance: any non-first stamp was tapped by hand.
  return sync.lines.some((line) =>
    line.tokens.some((token, i) => i > 0 && token.startSeconds != null)
  );
}

/**
 * Forced-align the take to its script and write an `auto` tokenSync (plus
 * derived line-switch marks when the take has none). KA-3.
 */
export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/variants/[variantId]/auto-stamp">
) {
  const { id, variantId } = await ctx.params;
  const parsed = bodySchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }
  const force = parsed.data.force === true;

  if (!alignerConfigured()) {
    return NextResponse.json(
      { error: "Aligner is not configured (ALIGNER_URL / ALIGNER_TOKEN)." },
      { status: 503 }
    );
  }

  const [project, variant] = await Promise.all([
    db.query.ttsProject.findFirst({ where: eq(ttsProject.id, id) }),
    db.query.ttsVariant.findFirst({ where: eq(ttsVariant.id, variantId) }),
  ]);
  if (!project || !variant || variant.projectId !== project.id) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  let conversation;
  try {
    conversation = await loadConversationLines(project);
  } catch (error) {
    if (error instanceof UserFacingError) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    throw error;
  }
  const spokenTexts = conversation.map((line) => line.text.trim()).filter(Boolean);
  if (spokenTexts.length === 0) {
    return NextResponse.json({ error: "No spoken lines." }, { status: 400 });
  }
  const contentHash = conversationContentHash(conversation);
  if (variant.contentHash && variant.contentHash !== contentHash) {
    return NextResponse.json(
      { error: "Dialogue text changed since this take was generated. Regenerate the take first." },
      { status: 409 }
    );
  }

  const existingSync = parseVariantTokenSync(variant.tokenSync);
  const status = tokenSyncStatus(existingSync, contentHash, spokenTexts);
  if (!force && (status === "tokens-only" || status === "complete") && hasHumanStamps(existingSync)) {
    return NextResponse.json(
      {
        error: "This take already has human stamps. Re-run with force to replace them.",
        code: "human-stamps",
      },
      { status: 409 }
    );
  }

  const existingMarks = variant.dialogueLineSwitchSamples ?? [];
  const needed = spokenTexts.length - 1;
  if (!force && existingMarks.length > 0 && existingMarks.length !== needed) {
    return NextResponse.json(
      {
        error: `This take has ${existingMarks.length} line marks but needs ${needed}. Fix the marks or re-run with force.`,
        code: "marks-mismatch",
      },
      { status: 409 }
    );
  }

  // Token surfaces: reuse the take's current tokens when they still match the
  // script (they may carry editor splits/merges), otherwise tokenize.
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
          .filter((text) => text.length > 0 && !isAllPunctuationOrWhitespace(text))
          .map((text) => ({ text })),
      }));
    } catch (error) {
      if (error instanceof DialogueGenerationError) {
        return NextResponse.json({ error: error.message }, { status: 502 });
      }
      throw error;
    }
  }
  if (lines.some((line) => line.tokens.length === 0)) {
    return NextResponse.json({ error: "A line has no alignable tokens." }, { status: 422 });
  }

  const wav = await getObject(variant.audioObjectKey);
  const { pcm, sampleRate } = wavToPcm16(wav);
  const samples = pcm16ToFloat32(pcm);

  let aligned;
  try {
    aligned = await alignVariantAudio({ audioObjectKey: variant.audioObjectKey, lines });
  } catch (error) {
    if (error instanceof AlignerError) {
      return NextResponse.json({ error: error.message }, { status: 502 });
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
    .where(eq(ttsVariant.id, variantId))
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

  return NextResponse.json({
    variant: updated,
    flags: result.flags,
    marksDerived: result.marksDerived,
    summary,
  });
}
