import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { ttsVariant, ttsVariantSentence } from "@/lib/db/schema";
import { getObject, putObject } from "@/lib/storage/r2";
import { wavToPcm16, pcm16ToWav } from "@/lib/tts/wav";
import { shiftTokenSyncBySamples } from "@/lib/dialogue/token-sync";

/** Permanently rewrites the take's WAV to the current trim bounds, mirrors StudioViewModel.commitTrimToLoadedTake(). */
export async function POST(
  _request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/variants/[variantId]/commit-trim">
) {
  const { variantId } = await ctx.params;

  const variant = await db.query.ttsVariant.findFirst({
    where: eq(ttsVariant.id, variantId),
  });
  if (!variant) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const wav = await getObject(variant.audioObjectKey);
  const { pcm, sampleRate } = wavToPcm16(wav);
  const totalSamples = pcm.length / 2;

  const lo = Math.min(Math.max(variant.trimSampleLower ?? 0, 0), totalSamples - 1);
  const hi = Math.min(Math.max(variant.trimSampleUpper ?? totalSamples, lo + 1), totalSamples);

  if (lo === 0 && hi === totalSamples) {
    return NextResponse.json(
      { error: "Trim range is the full clip — nothing to commit." },
      { status: 400 }
    );
  }

  const trimmedPcm = pcm.subarray(lo * 2, hi * 2);
  const trimmedWav = pcm16ToWav(Buffer.from(trimmedPcm), sampleRate);

  await putObject(variant.audioObjectKey, trimmedWav, "audio/wav");

  const sentences = await db.query.ttsVariantSentence.findMany({
    where: eq(ttsVariantSentence.variantId, variantId),
  });
  for (const sentence of sentences) {
    const newLower = sentence.sampleLower - lo;
    const newUpper = sentence.sampleUpper - lo;
    if (newUpper <= 0 || newLower >= hi - lo) {
      await db.delete(ttsVariantSentence).where(eq(ttsVariantSentence.id, sentence.id));
    } else {
      await db
        .update(ttsVariantSentence)
        .set({
          sampleLower: Math.max(0, newLower),
          sampleUpper: Math.min(hi - lo, newUpper),
        })
        .where(eq(ttsVariantSentence.id, sentence.id));
    }
  }

  const shiftedLineSwitches = (variant.dialogueLineSwitchSamples ?? [])
    .map((s) => s - lo)
    .filter((s) => s > 0 && s < hi - lo);

  const newLength = hi - lo;
  const shiftedTokenSync = shiftTokenSyncBySamples(
    variant.tokenSync,
    sampleRate,
    (s) => {
      const next = s - lo;
      if (next <= 0 || next >= newLength) return null;
      return next;
    }
  );

  const [updated] = await db
    .update(ttsVariant)
    .set({
      audioByteCount: trimmedWav.length,
      trimSampleLower: null,
      trimSampleUpper: null,
      dialogueLineSwitchSamples:
        shiftedLineSwitches.length > 0 ? shiftedLineSwitches : null,
      tokenSync: shiftedTokenSync,
    })
    .where(eq(ttsVariant.id, variantId))
    .returning();

  return NextResponse.json({ variant: updated });
}
