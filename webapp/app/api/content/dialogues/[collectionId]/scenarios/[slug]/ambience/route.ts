import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq, inArray } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db/client";
import { ambienceAsset, dialogueScenario } from "@/lib/db/schema";
import {
  DEFAULT_AMBIENCE_GAIN_DB,
  MAX_AMBIENCE_GAIN_DB,
  MAX_AMBIENCE_LAYERS,
  MIN_AMBIENCE_GAIN_DB,
  clampAmbienceGainDb,
  createAmbienceLayer,
  layersFromScenario,
  normalizeAmbienceLayers,
  wrapAmbienceOffset,
} from "@/lib/tts/ambience";
import { mixHashForScenario, scenarioAmbienceColumns } from "@/lib/tts/ambience-mix";

const layerSchema = z.object({
  id: z.string().min(1).optional(),
  assetId: z.string().uuid(),
  gainDb: z.number().min(MIN_AMBIENCE_GAIN_DB).max(MAX_AMBIENCE_GAIN_DB).optional(),
  offsetSeconds: z.number().optional(),
  startSeconds: z.number().optional(),
  endSeconds: z.number().nullable().optional(),
});

const bodySchema = z.object({
  assetId: z.string().uuid().nullable().optional(),
  gainDb: z.number().min(MIN_AMBIENCE_GAIN_DB).max(MAX_AMBIENCE_GAIN_DB).nullable().optional(),
  offsetSeconds: z.number().nullable().optional(),
  layers: z.array(layerSchema).max(MAX_AMBIENCE_LAYERS).optional(),
});

export async function PATCH(
  request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]/scenarios/[slug]/ambience">
) {
  const { collectionId, slug } = await ctx.params;
  const scenarioId = `${collectionId}/${slug}`;
  const body = await request.json().catch(() => ({}));
  const parsed = bodySchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }

  const scenario = await db.query.dialogueScenario.findFirst({
    where: eq(dialogueScenario.id, scenarioId),
  });
  if (!scenario) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  let nextLayers = layersFromScenario(scenario);

  if (parsed.data.layers) {
    nextLayers = normalizeAmbienceLayers(parsed.data.layers);
  } else if (parsed.data.assetId === null) {
    nextLayers = [];
  } else if (parsed.data.assetId) {
    const existing = nextLayers.find((layer) => layer.assetId === parsed.data.assetId);
    if (existing && nextLayers.length === 1) {
      nextLayers = [
        {
          ...existing,
          gainDb: clampAmbienceGainDb(
            parsed.data.gainDb ?? existing.gainDb ?? DEFAULT_AMBIENCE_GAIN_DB
          ),
          offsetSeconds: parsed.data.offsetSeconds ?? existing.offsetSeconds,
        },
      ];
    } else {
      const asset = await db.query.ambienceAsset.findFirst({
        where: eq(ambienceAsset.id, parsed.data.assetId),
      });
      if (!asset) {
        return NextResponse.json({ error: "Ambience bed not found." }, { status: 404 });
      }
      nextLayers = [
        createAmbienceLayer({
          assetId: asset.id,
          bedDuration: asset.durationSeconds,
          full: true,
        }),
      ];
      if (parsed.data.gainDb != null) {
        nextLayers[0].gainDb = clampAmbienceGainDb(parsed.data.gainDb);
      }
      if (parsed.data.offsetSeconds != null) {
        nextLayers[0].offsetSeconds = wrapAmbienceOffset(
          parsed.data.offsetSeconds,
          asset.durationSeconds
        );
      }
    }
  }

  const assetIds = [...new Set(nextLayers.map((layer) => layer.assetId))];
  if (assetIds.length > 0) {
    const found = await db.query.ambienceAsset.findMany({
      where: inArray(ambienceAsset.id, assetIds),
    });
    const foundIds = new Set(found.map((asset) => asset.id));
    const missing = assetIds.filter((id) => !foundIds.has(id));
    if (missing.length > 0) {
      return NextResponse.json({ error: "Ambience bed not found." }, { status: 404 });
    }
    const durationById = new Map(found.map((asset) => [asset.id, asset.durationSeconds]));
    nextLayers = nextLayers.map((layer) => ({
      ...layer,
      offsetSeconds: wrapAmbienceOffset(
        layer.offsetSeconds,
        durationById.get(layer.assetId) ?? 0
      ),
    }));
  }

  const [updated] = await db
    .update(dialogueScenario)
    .set({
      ...scenarioAmbienceColumns(nextLayers),
      updatedAt: new Date(),
    })
    .where(eq(dialogueScenario.id, scenarioId))
    .returning();
  if (!updated) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  return NextResponse.json({
    scenario: updated,
    ambienceMixHash: mixHashForScenario(updated),
  });
}
