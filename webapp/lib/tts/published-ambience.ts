import "server-only";

import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { ambienceAsset } from "@/lib/db/schema";
import { putPublishedObject } from "@/lib/storage/published-r2";
import { getObject } from "@/lib/storage/r2";
import { encodeAudioToM4a } from "@/lib/tts/audio-encode";
import { layersFromScenario } from "@/lib/tts/ambience";
import {
  publishedAmbienceAudioKey,
  publishedAmbiencePublicUrl,
} from "@/lib/tts/published-ambience-url";

export {
  publishedAmbienceAudioKey,
  publishedAmbiencePublicUrl,
} from "@/lib/tts/published-ambience-url";

const publishedThisProcess = new Set<string>();

export async function publishAmbienceAsset(assetId: string): Promise<string> {
  const asset = await db.query.ambienceAsset.findFirst({
    where: eq(ambienceAsset.id, assetId),
  });
  if (!asset) {
    throw new Error(`Ambience bed ${assetId} is missing from the library.`);
  }
  const source = await getObject(asset.audioObjectKey);
  const m4a = await encodeAudioToM4a(source);
  const objectKey = publishedAmbienceAudioKey(asset.id);
  await putPublishedObject(objectKey, m4a, "audio/mp4");
  publishedThisProcess.add(asset.id);
  return publishedAmbiencePublicUrl(asset.id);
}

export async function ensurePublishedAmbienceAsset(
  assetId: string
): Promise<string> {
  if (publishedThisProcess.has(assetId)) {
    return publishedAmbiencePublicUrl(assetId);
  }
  return publishAmbienceAsset(assetId);
}

export async function publishPrimaryAmbienceBed(scenario: {
  ambienceAssetId: string | null;
  ambienceGainDb: number | null;
  ambienceOffsetSeconds: number | null;
  ambienceLayers?: unknown;
}): Promise<string | null> {
  const layer = layersFromScenario(scenario)[0];
  if (!layer) return null;
  return ensurePublishedAmbienceAsset(layer.assetId);
}
