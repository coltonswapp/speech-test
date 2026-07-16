import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { asc, eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { dialogueCollection, dialogueScenario } from "@/lib/db/schema";
import { collectionFileSchema, updateCollectionSchema } from "@/lib/dialogue/types";
import { upsertCollectionFile } from "@/lib/dialogue/import";

async function loadCollection(collectionId: string) {
  const collection = await db.query.dialogueCollection.findFirst({
    where: eq(dialogueCollection.id, collectionId),
  });
  if (!collection) return null;
  const scenarios = await db.query.dialogueScenario.findMany({
    where: eq(dialogueScenario.collectionId, collectionId),
    orderBy: [asc(dialogueScenario.orderIndex)],
  });
  return { ...collection, scenarios };
}

export async function GET(
  _request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]">
) {
  const { collectionId } = await ctx.params;
  const collection = await loadCollection(collectionId);
  if (!collection) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ collection });
}

export async function PATCH(
  request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]">
) {
  const { collectionId } = await ctx.params;
  const body = await request.json();
  const parsed = updateCollectionSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const { scenarioOrder, ...fields } = parsed.data;

  const [updated] = await db
    .update(dialogueCollection)
    .set({ ...fields, updatedAt: new Date() })
    .where(eq(dialogueCollection.id, collectionId))
    .returning();
  if (!updated) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  if (scenarioOrder) {
    for (const [index, scenarioId] of scenarioOrder.entries()) {
      await db
        .update(dialogueScenario)
        .set({ orderIndex: index })
        .where(eq(dialogueScenario.id, scenarioId));
    }
  }

  const collection = await loadCollection(collectionId);
  return NextResponse.json({ collection });
}

// Whole-collection replace from a shizen collection file (the Raw JSON
// editor). Scenarios are delete-then-inserted in file order.
export async function PUT(
  request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]">
) {
  const { collectionId } = await ctx.params;
  const body = await request.json();
  const parsed = collectionFileSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    );
  }
  if (parsed.data.id !== collectionId) {
    return NextResponse.json(
      { error: `Collection id must remain "${collectionId}".` },
      { status: 400 }
    );
  }

  const existing = await db.query.dialogueCollection.findFirst({
    where: eq(dialogueCollection.id, collectionId),
  });
  if (!existing) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  await upsertCollectionFile(db, parsed.data);
  const collection = await loadCollection(collectionId);
  return NextResponse.json({ collection });
}

export async function DELETE(
  _request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]">
) {
  const { collectionId } = await ctx.params;
  const [deleted] = await db
    .delete(dialogueCollection)
    .where(eq(dialogueCollection.id, collectionId))
    .returning({ id: dialogueCollection.id });
  if (!deleted) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ ok: true });
}
