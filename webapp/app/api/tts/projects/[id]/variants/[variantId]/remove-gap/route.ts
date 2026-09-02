import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db/client";
import { ttsVariant, ttsVariantSentence } from "@/lib/db/schema";
import { getObject, putObject } from "@/lib/storage/r2";
import { wavToPcm16, pcm16ToWav } from "@/lib/tts/wav";
import { shiftTokenSyncBySamples } from "@/lib/dialogue/token-sync";

const bodySchema = z.object({
  startSample: z.number().int().min(0),
  endSample: z.number().int().min(0),
});

/** Cuts [startSample, endSample) out of the take, mirrors StudioViewModel.removeGapToPlayhead(). */
export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/variants/[variantId]/remove-gap">
) {
  const { variantId } = await ctx.params;
  const body = await request.json();
  const parsed = bodySchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    );
  }
  const { startSample, endSample } = parsed.data;
  if (endSample <= startSample) {
    return NextResponse.json(
      { error: "End must be after start." },
      { status: 400 }
    );
  }

  const variant = await db.query.ttsVariant.findFirst({
    where: eq(ttsVariant.id, variantId),
  });
  if (!variant) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const wav = await getObject(variant.audioObjectKey);
  const { pcm, sampleRate } = wavToPcm16(wav);
  const totalSamples = pcm.length / 2;

  const lo = Math.min(Math.max(startSample, 0), totalSamples);
  const hi = Math.min(Math.max(endSample, lo), totalSamples);
  if (hi <= lo) {
    return NextResponse.json(
      { error: "Gap range is empty." },
      { status: 400 }
    );
  }
  const removedCount = hi - lo;

  const before = pcm.subarray(0, lo * 2);
  const after = pcm.subarray(hi * 2);
  const newPcm = Buffer.concat([before, after]);
  const newWav = pcm16ToWav(newPcm, sampleRate);

  await putObject(variant.audioObjectKey, newWav, "audio/wav");

  function shift(sample: number): number {
    if (sample >= hi) return sample - removedCount;
    if (sample > lo) return lo;
    return sample;
  }

  const sentences = await db.query.ttsVariantSentence.findMany({
    where: eq(ttsVariantSentence.variantId, variantId),
  });
  for (const sentence of sentences) {
    const newLower = shift(sentence.sampleLower);
    const newUpper = shift(sentence.sampleUpper);
    if (newUpper <= newLower) {
      await db.delete(ttsVariantSentence).where(eq(ttsVariantSentence.id, sentence.id));
    } else {
      await db
        .update(ttsVariantSentence)
        .set({ sampleLower: newLower, sampleUpper: newUpper })
        .where(eq(ttsVariantSentence.id, sentence.id));
    }
  }

  const shiftedLineSwitches = (variant.dialogueLineSwitchSamples ?? [])
    .map(shift)
    .filter((s, i, arr) => s > 0 && s < newPcm.length / 2 && arr.indexOf(s) === i);

  const shiftedTrimLower =
    variant.trimSampleLower != null ? shift(variant.trimSampleLower) : null;
  const shiftedTrimUpper =
    variant.trimSampleUpper != null ? shift(variant.trimSampleUpper) : null;

  const newLength = newPcm.length / 2;
  const shiftedTokenSync = shiftTokenSyncBySamples(
    variant.tokenSync,
    sampleRate,
    (s) => {
      const next = shift(s);
      if (next <= 0 || next >= newLength) return null;
      return next;
    }
  );

  const [updated] = await db
    .update(ttsVariant)
    .set({
      audioByteCount: newWav.length,
      trimSampleLower: shiftedTrimLower,
      trimSampleUpper: shiftedTrimUpper,
      dialogueLineSwitchSamples:
        shiftedLineSwitches.length > 0 ? shiftedLineSwitches : null,
      tokenSync: shiftedTokenSync,
    })
    .where(eq(ttsVariant.id, variantId))
    .returning();

  return NextResponse.json({ variant: updated });
}
