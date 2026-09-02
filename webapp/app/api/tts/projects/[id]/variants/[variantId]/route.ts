import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { and, eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db/client";
import { ttsProject, ttsVariant } from "@/lib/db/schema";
import { variantTokenSyncSchema } from "@/lib/dialogue/types";

const updateVariantSchema = z.object({
  trimSampleLower: z.number().int().nullable().optional(),
  trimSampleUpper: z.number().int().nullable().optional(),
  dialogueLineSwitchSamples: z.array(z.number().int()).nullable().optional(),
  notes: z.string().nullable().optional(),
  rating: z.number().int().nullable().optional(),
  isSelected: z.boolean().optional(),
  tokenSync: variantTokenSyncSchema.nullable().optional(),
});

export async function GET(
  _request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/variants/[variantId]">
) {
  const { variantId } = await ctx.params;
  const variant = await db.query.ttsVariant.findFirst({
    where: eq(ttsVariant.id, variantId),
  });
  if (!variant) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ variant });
}

export async function PATCH(
  request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/variants/[variantId]">
) {
  const { variantId } = await ctx.params;
  const body = await request.json();
  const parsed = updateVariantSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const [variant] = await db
    .update(ttsVariant)
    .set(parsed.data)
    .where(eq(ttsVariant.id, variantId))
    .returning();

  if (!variant) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ variant });
}

export async function DELETE(
  _request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/variants/[variantId]">
) {
  const { id, variantId } = await ctx.params;
  const [deleted] = await db
    .delete(ttsVariant)
    .where(eq(ttsVariant.id, variantId))
    .returning({ id: ttsVariant.id });
  if (!deleted) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  // Don't leave the project pointing at a deleted take.
  await db
    .update(ttsProject)
    .set({ selectedVariantId: null, updatedAt: new Date() })
    .where(
      and(eq(ttsProject.id, id), eq(ttsProject.selectedVariantId, variantId))
    );
  return NextResponse.json({ ok: true });
}
