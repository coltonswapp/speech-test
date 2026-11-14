import { autoStampTokenSync } from "@/lib/dialogue/token-sync-auto";
import type { AlignedLine } from "@/lib/dialogue/token-sync-auto";
import type { VariantTokenSync } from "@/lib/dialogue/types";
import type { GenerateLineTiming } from "./types";

export function lineTimingsFromTokenSync(
  tokenSync: VariantTokenSync,
  durationSeconds: number,
): GenerateLineTiming[] {
  return tokenSync.lines.map((line, index) => {
    const starts = line.tokens
      .map((token) => token.startSeconds)
      .filter((value): value is number => value != null);
    const startSeconds = starts[0] ?? 0;
    const nextStart =
      tokenSync.lines[index + 1]?.tokens.find((token) => token.startSeconds != null)
        ?.startSeconds ?? durationSeconds;
    const lastStart = starts[starts.length - 1] ?? startSeconds;
    const endSeconds = Math.min(
      durationSeconds,
      Math.max(lastStart, startSeconds, nextStart > lastStart ? (lastStart + nextStart) / 2 : nextStart),
    );
    return {
      index,
      text: line.text,
      startSeconds,
      endSeconds,
      pauseAfterSeconds: Math.max(0, nextStart - endSeconds),
    };
  });
}

export function stampGenerateTokenSync(params: {
  aligned: AlignedLine[];
  lines: Array<{ text: string; tokens: Array<{ text: string; reading?: string }> }>;
  samples: Float32Array;
  sampleRate: number;
  contentHash: string;
  alignerVersion: string;
  markSamples?: number[] | null;
}): {
  tokenSync: VariantTokenSync;
  lineTimings: GenerateLineTiming[];
} {
  const result = autoStampTokenSync({
    alignerVersion: params.alignerVersion,
    aligned: params.aligned,
    lines: params.lines,
    samples: params.samples,
    sampleRate: params.sampleRate,
    contentHash: params.contentHash,
    existingMarkSamples:
      params.markSamples &&
      params.markSamples.length === Math.max(0, params.lines.length - 1)
        ? params.markSamples
        : null,
  });
  const durationSeconds = params.samples.length / params.sampleRate;
  return {
    tokenSync: result.tokenSync,
    lineTimings: lineTimingsFromTokenSync(result.tokenSync, durationSeconds),
  };
}
