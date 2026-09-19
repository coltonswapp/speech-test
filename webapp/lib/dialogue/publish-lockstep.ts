import {
  completeTokenSyncForVariant,
  estimatedWavDurationSeconds,
  isKaraokeSnapshotsEqual,
  lineSwitchSecondsFromMarks,
  parsePublishedTokenSync,
} from "@/lib/dialogue/token-sync";
import type { DialogueLine, PublishedTokenSync } from "@/lib/dialogue/types";
import { scenarioLinesToConversation } from "@/lib/tts/scenario-conversation";

export type KaraokeTakeInput = {
  id: string;
  tokenSync: unknown;
  contentHash?: string | null;
  dialogueLineSwitchSamples?: number[] | null;
  sampleRate: number;
  audioByteCount: number;
  trimSampleLower?: number | null;
  trimSampleUpper?: number | null;
};

/** What publish would write for this take — same snapshot as the learner JSON. */
export function karaokeSnapshotForTake(params: {
  take: KaraokeTakeInput;
  lines: unknown;
  contentHash: string;
}): PublishedTokenSync | null {
  const spokenTexts = scenarioLinesToConversation(
    Array.isArray(params.lines) ? (params.lines as DialogueLine[]) : [],
  ).lines.map((line) => line.text);
  return completeTokenSyncForVariant({
    tokenSync: params.take.tokenSync,
    variantId: params.take.id,
    contentHash: params.contentHash,
    spokenTexts,
    lineSwitchSeconds: lineSwitchSecondsFromMarks({
      markSamples: params.take.dialogueLineSwitchSamples,
      trimSampleLower: params.take.trimSampleLower,
      sampleRate: params.take.sampleRate,
    }),
    durationSeconds: estimatedWavDurationSeconds(params.take),
    trimSampleLower: params.take.trimSampleLower,
    sampleRate: params.take.sampleRate,
  });
}

/** True when the published karaoke snapshot is not what this take would ship. */
export function isKaraokeSnapshotStale(
  publishedTokenSync: unknown,
  nextSnapshot: PublishedTokenSync | null,
): boolean {
  const published = parsePublishedTokenSync(publishedTokenSync);
  if (!published && !nextSnapshot) return false;
  if (!published || !nextSnapshot) return true;
  return !isKaraokeSnapshotsEqual(published, nextSnapshot);
}

export function isPublishKaraokeStale(params: {
  publishedTokenSync: unknown;
  take: KaraokeTakeInput | null | undefined;
  lines: unknown;
  contentHash: string;
}): boolean {
  if (!params.take) return false;
  return isKaraokeSnapshotStale(
    params.publishedTokenSync,
    karaokeSnapshotForTake({
      take: params.take,
      lines: params.lines,
      contentHash: params.contentHash,
    }),
  );
}
