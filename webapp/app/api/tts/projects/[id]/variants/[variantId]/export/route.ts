import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db/client";
import { ttsExport, ttsVariant } from "@/lib/db/schema";
import { getObject, putObject } from "@/lib/storage/r2";
import { encodeWavToM4a, encodeWavToMp3 } from "@/lib/tts/audio-encode";
import {
  lineSwitchSecondsForExport,
  trimmedWav,
} from "@/lib/tts/variant-audio";

const formatSchema = z.enum(["wav", "mp3", "m4a"]);

export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/variants/[variantId]/export">
) {
  const { variantId } = await ctx.params;
  const body = await request.json().catch(() => ({}));
  const parsed = formatSchema.safeParse(body?.format);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "format must be one of: wav, mp3, m4a" },
      { status: 400 }
    );
  }
  const format = parsed.data;

  const variant = await db.query.ttsVariant.findFirst({
    where: eq(ttsVariant.id, variantId),
  });
  if (!variant) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const sourceWav = await getObject(variant.audioObjectKey);
  const exportWav = trimmedWav(sourceWav, variant.trimSampleLower, variant.trimSampleUpper);

  let outputBuffer: Buffer;
  let contentType: string;
  if (format === "wav") {
    outputBuffer = exportWav;
    contentType = "audio/wav";
  } else if (format === "mp3") {
    outputBuffer = await encodeWavToMp3(exportWav);
    contentType = "audio/mpeg";
  } else {
    outputBuffer = await encodeWavToM4a(exportWav, lineSwitchSecondsForExport(variant));
    contentType = "audio/mp4";
  }

  const exportObjectKey = `tts/${variant.projectId}/variants/${variantId}/exports/${crypto.randomUUID()}.${format}`;
  await putObject(exportObjectKey, outputBuffer, contentType);

  const durationSeconds = exportWav.length > 44
    ? (exportWav.length - 44) / 2 / variant.sampleRate
    : 0;

  const [record] = await db
    .insert(ttsExport)
    .values({
      variantId,
      format,
      objectKey: exportObjectKey,
      byteCount: outputBuffer.length,
      durationSeconds,
      sourceByteCount: variant.audioByteCount,
    })
    .returning();

  return NextResponse.json({ export: record }, { status: 201 });
}
