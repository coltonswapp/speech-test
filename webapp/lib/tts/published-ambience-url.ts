import { publishedObjectPublicUrl } from "@/lib/storage/published-r2-core";

export function publishedAmbienceAudioKey(assetId: string): string {
  return `ambience/${assetId}.m4a`;
}

export function publishedAmbiencePublicUrl(assetId: string): string {
  return publishedObjectPublicUrl(publishedAmbienceAudioKey(assetId));
}
