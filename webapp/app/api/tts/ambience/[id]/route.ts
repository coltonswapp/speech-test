import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db/client";
import { ambienceAsset, dialogueScenario } from "@/lib/db/schema";
import { deleteObject } from "@/lib/storage/r2";
import { layersFromScenario, normalizeAmbienceKind } from "@/lib/tts/ambience";

const updateSchema = z.object({
  title: z.string().min(1).optional(),
  kind: z
    .string()
    .min(1)
    .max(80)
    .transform((value) => normalizeAmbienceKind(value))
    .optional(),
});

export async function PATCH(
  request: NextRequest,
  ctx: RouteContext<"/api/tts/ambience/[id]">
) {
  const { id } = await ctx.params;
  const body = await request.json().catch(() => ({}));
  const parsed = updateSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }
  if (Object.keys(parsed.data).length === 0) {
    return NextResponse.json({ error: "Nothing to update." }, { status: 400 });
  }

  const [asset] = await db
    .update(ambienceAsset)
    .set({ ...parsed.data, updatedAt: new Date() })
    .where(eq(ambienceAsset.id, id))
    .returning();
  if (!asset) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ asset });
}

export async function DELETE(
  _request: NextRequest,
  ctx: RouteContext<"/api/tts/ambience/[id]">
) {
  const { id } = await ctx.params;
  const scenarios = await db.query.dialogueScenario.findMany({
    columns: {
      id: true,
      menuTitle: true,
      ambienceAssetId: true,
      ambienceGainDb: true,
      ambienceOffsetSeconds: true,
      ambienceLayers: true,
    },
  });
  const inUse = scenarios.find(
    (row) =>
      row.ambienceAssetId === id ||
      layersFromScenario(row).some((layer) => layer.assetId === id)
  );
  if (inUse) {
    return NextResponse.json(
      {
        error: `“${inUse.menuTitle}” still uses this bed. Detach it first.`,
      },
      { status: 400 }
    );
  }

  const existing = await db.query.ambienceAsset.findFirst({
    where: eq(ambienceAsset.id, id),
  });
  if (!existing) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  await db.delete(ambienceAsset).where(eq(ambienceAsset.id, id));
  await deleteObject(existing.audioObjectKey).catch(() => undefined);
  return NextResponse.json({ ok: true });
}
