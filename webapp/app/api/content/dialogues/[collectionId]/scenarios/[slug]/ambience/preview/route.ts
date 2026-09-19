import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db/client";
import { dialogueScenario, ttsProject, ttsVariant } from "@/lib/db/schema";
import {
  MAX_AMBIENCE_GAIN_DB,
  MAX_AMBIENCE_LAYERS,
  MIN_AMBIENCE_GAIN_DB,
  normalizeAmbienceLayers,
} from "@/lib/tts/ambience";
import { loadAmbienceMixOptions } from "@/lib/tts/ambience-mix";
import { renderVariantM4a } from "@/lib/tts/variant-audio";
import type { AmbienceMixOptions } from "@/lib/tts/audio-encode";

export const maxDuration = 120;

const layerSchema = z.object({
  assetId: z.string().uuid(),
  gainDb: z.number().min(MIN_AMBIENCE_GAIN_DB).max(MAX_AMBIENCE_GAIN_DB),
  offsetSeconds: z.number(),
  startSeconds: z.number().optional(),
  endSeconds: z.number().nullable().optional(),
});

const bodySchema = z.object({
  variantId: z.string().uuid(),
  assetId: z.string().uuid().optional(),
  gainDb: z.number().min(MIN_AMBIENCE_GAIN_DB).max(MAX_AMBIENCE_GAIN_DB).optional(),
  offsetSeconds: z.number().optional(),
  layers: z.array(layerSchema).max(MAX_AMBIENCE_LAYERS).optional(),
});

export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]/scenarios/[slug]/ambience/preview">
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

  const project = await db.query.ttsProject.findFirst({
    where: eq(ttsProject.sourceScenarioId, scenarioId),
  });
  if (!project) {
    return NextResponse.json({ error: "No audio track for this scene." }, { status: 400 });
  }

  const variant = await db.query.ttsVariant.findFirst({
    where: eq(ttsVariant.id, parsed.data.variantId),
  });
  if (!variant || variant.projectId !== project.id) {
    return NextResponse.json({ error: "Take does not belong to this scene." }, { status: 400 });
  }

  const layers = parsed.data.layers?.length
    ? normalizeAmbienceLayers(parsed.data.layers)
    : parsed.data.assetId
      ? normalizeAmbienceLayers([
          {
            assetId: parsed.data.assetId,
            gainDb: parsed.data.gainDb,
            offsetSeconds: parsed.data.offsetSeconds,
            startSeconds: 0,
            endSeconds: null,
          },
        ])
      : [];
  if (layers.length === 0) {
    return NextResponse.json({ error: "Attach an ambience loop first." }, { status: 400 });
  }

  const mixes: AmbienceMixOptions[] = [];
  for (const layer of layers) {
    const loaded = await loadAmbienceMixOptions({
      assetId: layer.assetId,
      gainDb: layer.gainDb,
      offsetSeconds: layer.offsetSeconds,
      startSeconds: layer.startSeconds,
      endSeconds: layer.endSeconds,
    });
    if (!loaded) {
      return NextResponse.json({ error: "Ambience bed not found." }, { status: 404 });
    }
    mixes.push(loaded.mix);
  }

  try {
    const m4a = await renderVariantM4a(variant, mixes.length === 1 ? mixes[0] : mixes);
    return new NextResponse(new Uint8Array(m4a), {
      headers: {
        "Content-Type": "audio/mp4",
        "Content-Length": String(m4a.length),
        "Cache-Control": "no-store",
      },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Encode failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
