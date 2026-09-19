import type { dialogueScenario } from "@/lib/db/schema";
import type { DialogueLine } from "@/lib/dialogue/types";
import { conversationContentHash } from "@/lib/tts/content-hash";
import { scenarioLinesToConversation } from "@/lib/tts/scenario-conversation";

export function publishedDialogueAudioKey(
  collectionId: string,
  scenarioSlug: string,
  contentHash: string,
  variantId: string
): string {
  return `dialogue/${collectionId}/${scenarioSlug}/${contentHash}-${variantId}.m4a`;
}

/** True when the CDN object was baked with a mix-hash suffix (pre dual-track). */
export function publishedAudioUrlLooksMixed(
  url: string | null | undefined
): boolean {
  if (!url) return false;
  let file = url;
  try {
    file = decodeURIComponent(new URL(url).pathname.split("/").pop() ?? "");
  } catch {
    file = decodeURIComponent(url.split("/").pop()?.split("?")[0] ?? "");
  }
  if (!/\.m4a$/i.test(file)) return false;
  const stem = file.replace(/\.m4a$/i, "");
  const parts = stem.split("-");
  // dry: {contentHash}-{uuid} → 6 hyphen parts; mixed adds a 12-hex suffix.
  return parts.length >= 7 && /^[0-9a-f]{12}$/i.test(parts[parts.length - 1] ?? "");
}

export function isPublishStale(
  scenario: Pick<
    typeof dialogueScenario.$inferSelect,
    "publishedContentHash" | "lines" | "publishedAudioUrl" | "publishedAmbienceHash"
  >,
  currentMixHash: string | null = scenario.publishedAmbienceHash ?? null
): boolean {
  if (!scenario.publishedAudioUrl || !scenario.publishedContentHash) {
    return false;
  }
  const currentHash = conversationContentHash(
    scenarioLinesToConversation(scenario.lines as DialogueLine[]).lines
  );
  if (scenario.publishedContentHash !== currentHash) return true;
  if (publishedAudioUrlLooksMixed(scenario.publishedAudioUrl)) return true;
  return (scenario.publishedAmbienceHash ?? null) !== currentMixHash;
}
