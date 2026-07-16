import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { asc, eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { ttsDialogueLine, ttsVariant } from "@/lib/db/schema";
import { getObject } from "@/lib/storage/r2";
import { wavToPcm16, pcm16ToFloat32 } from "@/lib/tts/wav";
import { align, leadInAdjustedBoundaries } from "@/lib/tts/alignment";

/** Runs VAD/proportional alignment against the current dialogue lines and audio; returns suggested (unsaved) line-switch sample marks. */
export async function POST(
  _request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/variants/[variantId]/suggest-breaks">
) {
  const { id, variantId } = await ctx.params;

  const variant = await db.query.ttsVariant.findFirst({
    where: eq(ttsVariant.id, variantId),
  });
  if (!variant) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const dialogueLines = await db.query.ttsDialogueLine.findMany({
    where: eq(ttsDialogueLine.projectId, id),
    orderBy: [asc(ttsDialogueLine.orderIndex)],
  });
  const lineTexts = dialogueLines
    .map((l) => l.text.trim())
    .filter((t) => t.length > 0);

  if (lineTexts.length < 2) {
    return NextResponse.json({
      suggestedSamples: [],
      summary: "Add at least 2 dialogue lines above to preview auto breaks.",
    });
  }

  const wav = await getObject(variant.audioObjectKey);
  const { pcm, sampleRate } = wavToPcm16(wav);
  const samples = pcm16ToFloat32(pcm);

  const aligned = align(lineTexts, samples, sampleRate);
  if (aligned.length !== lineTexts.length) {
    return NextResponse.json({
      suggestedSamples: [],
      summary: `Auto alignment could not split ${lineTexts.length} lines.`,
    });
  }

  const onsetSamples = aligned
    .slice(1)
    .map((line) => line.sampleRange[0])
    .filter((sample) => sample > 0 && sample < samples.length);

  const suggestedSamples = leadInAdjustedBoundaries(onsetSamples, samples, sampleRate);

  const needed = lineTexts.length - 1;
  const summary =
    suggestedSamples.length === needed
      ? `Auto suggests ${needed} break${needed === 1 ? "" : "s"} at ${suggestedSamples
          .map((s) => (s / sampleRate).toFixed(3))
          .join(", ")}s`
      : `Auto found ${suggestedSamples.length} break(s), need ${needed} for ${lineTexts.length} lines — add marks manually.`;

  return NextResponse.json({ suggestedSamples, summary });
}
