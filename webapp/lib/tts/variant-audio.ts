// Shared take-audio assembly: trim bounds + chapter marks + encoding, used by
// the per-variant export route and the collection zip export.

import { getObject } from "@/lib/storage/r2";
import { wavToPcm16, pcm16ToWav } from "@/lib/tts/wav";
import { encodeWavToM4a } from "@/lib/tts/audio-encode";
import type { ttsVariant } from "@/lib/db/schema";

type Variant = typeof ttsVariant.$inferSelect;

/** Applies stored trim bounds (if any) to a full-clip WAV buffer. */
export function trimmedWav(
  wav: Buffer,
  trimLower: number | null,
  trimUpper: number | null
): Buffer {
  if (trimLower == null && trimUpper == null) return wav;
  const { pcm, sampleRate } = wavToPcm16(wav);
  const totalSamples = pcm.length / 2;
  const lo = Math.min(Math.max(trimLower ?? 0, 0), totalSamples - 1);
  const hi = Math.min(Math.max(trimUpper ?? totalSamples, lo + 1), totalSamples);
  const slice = pcm.subarray(lo * 2, hi * 2);
  return pcm16ToWav(Buffer.from(slice), sampleRate);
}

export function lineSwitchSecondsForExport(variant: Variant): number[] {
  const marks = variant.dialogueLineSwitchSamples ?? [];
  if (marks.length === 0) return [];
  const trimLower = variant.trimSampleLower ?? 0;
  return marks
    .map((s) => (s - trimLower) / variant.sampleRate)
    .filter((s) => s > 0);
}

/** Fetches the take's WAV from R2, applies trim, encodes to m4a with chapter marks. */
export async function renderVariantM4a(variant: Variant): Promise<Buffer> {
  const sourceWav = await getObject(variant.audioObjectKey);
  const exportWav = trimmedWav(
    sourceWav,
    variant.trimSampleLower,
    variant.trimSampleUpper
  );
  return encodeWavToM4a(exportWav, lineSwitchSecondsForExport(variant));
}
