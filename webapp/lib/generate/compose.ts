import { createHash } from "node:crypto";
import type { GenerateLineInput, GenerateLineTiming } from "./types";

export function silencePcm16(sampleRate: number, seconds: number): Buffer {
  const samples = Math.max(0, Math.round(sampleRate * seconds));
  return Buffer.alloc(samples * 2);
}

export type LineClip = {
  line: GenerateLineInput;
  pcm: Buffer;
};

export type ComposedAudio = {
  pcm: Buffer;
  durationSeconds: number;
  lineTimings: GenerateLineTiming[];
  /** Sample index of each later line start — aligner line-boundary marks. */
  markSamples: number[];
};

/**
 * Concatenate per-line PCM in order, inserting the requested pause after every
 * line except the last. Pause duration is exact (zeroed samples), so later
 * alignment is on the same timeline as the playable file.
 */
export function composeLinePcm(
  clips: LineClip[],
  sampleRate: number,
): ComposedAudio {
  if (clips.length === 0) {
    throw new Error("Add at least one line.");
  }
  if (sampleRate <= 0) {
    throw new Error("Invalid sample rate.");
  }

  const parts: Buffer[] = [];
  const lineTimings: GenerateLineTiming[] = [];
  const markSamples: number[] = [];
  let sampleCursor = 0;

  clips.forEach((clip, index) => {
    const isLast = index === clips.length - 1;
    const pauseAfterSeconds = isLast
      ? 0
      : Math.max(0, clip.line.pauseAfterSeconds ?? 0);
    const startSample = sampleCursor;
    const lineSamples = Math.floor(clip.pcm.length / 2);
    const startSeconds = startSample / sampleRate;
    const endSeconds = (startSample + lineSamples) / sampleRate;

    parts.push(clip.pcm);
    sampleCursor += lineSamples;

    if (pauseAfterSeconds > 0) {
      const silence = silencePcm16(sampleRate, pauseAfterSeconds);
      parts.push(silence);
      sampleCursor += Math.floor(silence.length / 2);
    }

    lineTimings.push({
      index,
      text: clip.line.text,
      voice: clip.line.voice,
      startSeconds,
      endSeconds,
      pauseAfterSeconds,
    });

    if (!isLast) {
      markSamples.push(sampleCursor);
    }
  });

  const pcm = Buffer.concat(parts);
  return {
    pcm,
    durationSeconds: Math.floor(pcm.length / 2) / sampleRate,
    lineTimings,
    markSamples,
  };
}

export function generationContentHash(input: {
  kind: "tts" | "upload";
  model?: string | null;
  lines: Array<{ text: string; voice: string; delivery?: string; pauseAfterSeconds?: number }>;
  transcript?: string | null;
}): string {
  const payload = JSON.stringify({
    kind: input.kind,
    model: input.model ?? null,
    lines: input.lines.map((line) => [
      line.text.trim(),
      line.voice,
      line.delivery?.trim() ?? "",
      line.pauseAfterSeconds ?? 0,
    ]),
    transcript: input.transcript?.trim() ?? "",
  });
  return createHash("sha256").update(payload, "utf8").digest("hex");
}

export function defaultTitleFromLines(lines: Array<{ text: string }>): string {
  const first = lines[0]?.text.trim() ?? "";
  if (!first) return "Untitled clip";
  return first.length > 48 ? `${first.slice(0, 47)}…` : first;
}

export function transcriptFromLines(lines: Array<{ text: string }>): string {
  return lines.map((line) => line.text.trim()).filter(Boolean).join("\n");
}

export function splitTranscript(transcript: string): string[] {
  return transcript
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
}

/** MPEG-1/2 audio (ID3 tag or frame sync). Rejects WAV bytes renamed to .mp3. */
export function isMpegAudio(buffer: Buffer): boolean {
  if (buffer.length < 3) return false;
  if (buffer[0] === 0x49 && buffer[1] === 0x44 && buffer[2] === 0x33) return true;
  return buffer[0] === 0xff && (buffer[1] & 0xe0) === 0xe0;
}
