import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { curriculumUnit, dialogueCollection } from "@/lib/db/schema";
import { updateUnitSchema } from "@/lib/dialogue/types";

export async function PATCH(
  request: NextRequest,
  ctx: RouteContext<"/api/content/units/[unitId]">
) {
  const { unitId } = await ctx.params;
  const body = await request.json();
  const parsed = updateUnitSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const { collectionOrder, ...fields } = parsed.data;

  const [updated] = await db
    .update(curriculumUnit)
    .set({ ...fields, updatedAt: new Date() })
    .where(eq(curriculumUnit.id, unitId))
    .returning();
  if (!updated) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  if (collectionOrder) {
    for (const [index, collectionId] of collectionOrder.entries()) {
      await db
        .update(dialogueCollection)
        .set({ orderIndex: index })
        .where(
          and(
            eq(dialogueCollection.id, collectionId),
            eq(dialogueCollection.unitId, unitId)
          )
        );
    }
  }

  return NextResponse.json({ unit: updated });
}

// Deleting a unit unfiles its collections (unit_id FK is ON DELETE SET NULL).
export async function DELETE(
  _request: NextRequest,
  ctx: RouteContext<"/api/content/units/[unitId]">
) {
  const { unitId } = await ctx.params;
  const [deleted] = await db
    .delete(curriculumUnit)
    .where(eq(curriculumUnit.id, unitId))
    .returning({ id: curriculumUnit.id });
  if (!deleted) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ ok: true });
}
