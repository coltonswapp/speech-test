import "server-only";
import { createHash } from "node:crypto";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { ambienceAsset } from "@/lib/db/schema";
import { getObject } from "@/lib/storage/r2";
import {
  DEFAULT_AMBIENCE_GAIN_DB,
  ambienceLayersMixKeyParts,
  clampAmbienceGainDb,
  layersFromScenario,
  wrapAmbienceOffset,
  type AmbienceLayer,
} from "@/lib/tts/ambience";
import type { AmbienceMixOptions } from "@/lib/tts/audio-encode";

export function hashAmbienceMix(parts: string): string {
  return createHash("sha256").update(parts, "utf8").digest("hex").slice(0, 12);
}

export function currentAmbienceMixHash(params: {
  assetId: string | null;
  gainDb: number | null;
  offsetSeconds: number | null;
  layers?: unknown;
}): string | null {
  const layers = layersFromScenario({
    ambienceAssetId: params.assetId,
    ambienceGainDb: params.gainDb,
    ambienceOffsetSeconds: params.offsetSeconds,
    ambienceLayers: params.layers,
  });
  if (layers.length === 0) return null;
  return hashAmbienceMix(ambienceLayersMixKeyParts(layers));
}

export function mixHashForScenario(scenario: {
  ambienceAssetId: string | null;
  ambienceGainDb: number | null;
  ambienceOffsetSeconds: number | null;
  ambienceLayers?: unknown;
}): string | null {
  return currentAmbienceMixHash({
    assetId: scenario.ambienceAssetId,
    gainDb: scenario.ambienceGainDb,
    offsetSeconds: scenario.ambienceOffsetSeconds,
    layers: scenario.ambienceLayers,
  });
}

export function scenarioAmbienceColumns(layers: AmbienceLayer[]): {
  ambienceLayers: AmbienceLayer[] | null;
  ambienceAssetId: string | null;
  ambienceGainDb: number | null;
  ambienceOffsetSeconds: number | null;
} {
  const first = layers[0];
  return {
    ambienceLayers: layers.length > 0 ? layers : null,
    ambienceAssetId: first?.assetId ?? null,
    ambienceGainDb: first?.gainDb ?? null,
    ambienceOffsetSeconds: first?.offsetSeconds ?? null,
  };
}

export async function loadAmbienceMixOptions(params: {
  assetId: string;
  gainDb: number | null;
  offsetSeconds: number | null;
  startSeconds?: number;
  endSeconds?: number | null;
}): Promise<{ mix: AmbienceMixOptions; hash: string; durationSeconds: number } | null> {
  const asset = await db.query.ambienceAsset.findFirst({
    where: eq(ambienceAsset.id, params.assetId),
  });
  if (!asset) return null;
  const bed = await getObject(asset.audioObjectKey);
  const gainDb = clampAmbienceGainDb(params.gainDb ?? DEFAULT_AMBIENCE_GAIN_DB);
  const offsetSeconds = wrapAmbienceOffset(
    params.offsetSeconds ?? 0,
    asset.durationSeconds
  );
  const hash = currentAmbienceMixHash({
    assetId: asset.id,
    gainDb,
    offsetSeconds,
  });
  if (!hash) return null;
  return {
    mix: {
      bed,
      gainDb,
      offsetSeconds,
      startSeconds: params.startSeconds ?? 0,
      endSeconds: params.endSeconds ?? null,
    },
    hash,
    durationSeconds: asset.durationSeconds,
  };
}

export async function loadScenarioAmbienceMix(scenario: {
  ambienceAssetId: string | null;
  ambienceGainDb: number | null;
  ambienceOffsetSeconds: number | null;
  ambienceLayers?: unknown;
}): Promise<{ mix: AmbienceMixOptions | AmbienceMixOptions[]; hash: string } | null> {
  const layers = layersFromScenario(scenario);
  if (layers.length === 0) return null;
  const mixes: AmbienceMixOptions[] = [];
  for (const layer of layers) {
    const loaded = await loadAmbienceMixOptions({
      assetId: layer.assetId,
      gainDb: layer.gainDb,
      offsetSeconds: layer.offsetSeconds,
      startSeconds: layer.startSeconds,
      endSeconds: layer.endSeconds,
    });
    if (loaded) mixes.push(loaded.mix);
  }
  if (mixes.length === 0) return null;
  const hash = hashAmbienceMix(ambienceLayersMixKeyParts(layers));
  return { mix: mixes.length === 1 ? mixes[0] : mixes, hash };
}
