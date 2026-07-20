import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { asc } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { dialogueCollection, dialogueScenario } from "@/lib/db/schema";
import { createCollectionSchema } from "@/lib/dialogue/types";

export async function GET() {
  const [collections, scenarios] = await Promise.all([
    db.query.dialogueCollection.findMany({
      orderBy: [asc(dialogueCollection.orderIndex), asc(dialogueCollection.id)],
    }),
    db.query.dialogueScenario.findMany({
      orderBy: [asc(dialogueScenario.orderIndex)],
      columns: {
        id: true,
        collectionId: true,
        orderIndex: true,
        menuTitle: true,
        menuSubtitle: true,
        audioKey: true,
        publishedAudioUrl: true,
        publishedVariantId: true,
        publishedContentHash: true,
        publishedAt: true,
        updatedAt: true,
      },
    }),
  ]);

  const byCollection = new Map<string, typeof scenarios>();
  for (const scenario of scenarios) {
    const list = byCollection.get(scenario.collectionId) ?? [];
    list.push(scenario);
    byCollection.set(scenario.collectionId, list);
  }

  return NextResponse.json({
    collections: collections.map((collection) => ({
      ...collection,
      scenarios: byCollection.get(collection.id) ?? [],
    })),
  });
}

export async function POST(request: NextRequest) {
  const body = await request.json();
  const parsed = createCollectionSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const existing = await db.query.dialogueCollection.findFirst({
    where: (table, { eq }) => eq(table.id, parsed.data.id),
  });
  if (existing) {
    return NextResponse.json(
      { error: `Collection "${parsed.data.id}" already exists.` },
      { status: 409 }
    );
  }

  const [collection] = await db
    .insert(dialogueCollection)
    .values({
      id: parsed.data.id,
      title: parsed.data.title,
      subtitle: parsed.data.subtitle ?? null,
      sceneImage: parsed.data.sceneImage ?? null,
      unitId: parsed.data.unitId ?? null,
    })
    .returning();

  return NextResponse.json({ collection }, { status: 201 });
}
