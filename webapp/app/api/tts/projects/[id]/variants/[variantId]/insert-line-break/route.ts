import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db/client";
import { ttsVariant } from "@/lib/db/schema";
import { getObject, putObject } from "@/lib/storage/r2";
import { wavToPcm16, pcm16ToWav } from "@/lib/tts/wav";

/** Fixed-duration silence inserted between dialogue lines for reliable splitting — mirrors TTSAudioAlignmentMarker.silenceDuration. */
const SILENCE_DURATION_SECONDS = 0.15;

const bodySchema = z.object({
  sample: z.number().int().min(0),
});

/** Inserts 0.15s of silence at `sample` and shifts existing marks/trim past the insertion point. Does not add a new mark. */
export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/variants/[variantId]/insert-line-break">
) {
  const { variantId } = await ctx.params;
  const body = await request.json();
  const parsed = bodySchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }
  const { sample } = parsed.data;

  const variant = await db.query.ttsVariant.findFirst({
    where: eq(ttsVariant.id, variantId),
  });
  if (!variant) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const wav = await getObject(variant.audioObjectKey);
  const { pcm, sampleRate } = wavToPcm16(wav);
  const totalSamples = pcm.length / 2;

  const insertAt = Math.min(Math.max(sample, 1), totalSamples - 1);
  const insertCount = Math.max(1, Math.round(SILENCE_DURATION_SECONDS * sampleRate));

  const before = pcm.subarray(0, insertAt * 2);
  const after = pcm.subarray(insertAt * 2);
  const silence = Buffer.alloc(insertCount * 2);
  const newPcm = Buffer.concat([before, silence, after]);
  const newWav = pcm16ToWav(newPcm, sampleRate);

  await putObject(variant.audioObjectKey, newWav, "audio/wav");

  // Shift marks that fall at/after the insert so they stay aligned with speech;
  // do not create a new dialogue-line mark for this gap.
  const shiftedMarks = (variant.dialogueLineSwitchSamples ?? []).map((s) =>
    s >= insertAt ? s + insertCount : s
  );

  const shiftedTrimLower =
    variant.trimSampleLower != null && variant.trimSampleLower >= insertAt
      ? variant.trimSampleLower + insertCount
      : variant.trimSampleLower;
  const shiftedTrimUpper =
    variant.trimSampleUpper != null && variant.trimSampleUpper >= insertAt
      ? variant.trimSampleUpper + insertCount
      : variant.trimSampleUpper;

  const [updated] = await db
    .update(ttsVariant)
    .set({
      audioByteCount: newWav.length,
      trimSampleLower: shiftedTrimLower,
      trimSampleUpper: shiftedTrimUpper,
      dialogueLineSwitchSamples: shiftedMarks,
    })
    .where(eq(ttsVariant.id, variantId))
    .returning();

  return NextResponse.json({ variant: updated });
}
