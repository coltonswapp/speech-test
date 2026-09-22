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

/**
 * Karaoke the learner file should carry for an already-published take.
 *
 * `dialogue_scenario.token_sync` is only copied at publish. Approving stamps
 * later leaves that column null while Studio still shows the take. When the
 * published variant and content hash still match, use the snapshot publish
 * would write now. Incomplete or mismatched takes keep the stored snapshot.
 */
export function learnerTokenSyncForPublishedTake(params: {
  storedTokenSync: unknown;
  publishedVariantId: string | null;
  publishedContentHash: string | null;
  take: KaraokeTakeInput | null | undefined;
  lines: unknown;
}): PublishedTokenSync | null {
  const stored = parsePublishedTokenSync(params.storedTokenSync);
  const take = params.take;
  if (
    !take ||
    !params.publishedVariantId ||
    !params.publishedContentHash ||
    take.id !== params.publishedVariantId ||
    take.contentHash !== params.publishedContentHash
  ) {
    return stored;
  }
  return (
    karaokeSnapshotForTake({
      take,
      lines: params.lines,
      contentHash: params.publishedContentHash,
    }) ?? stored
  );
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
