import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { asc } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { curriculumUnit, dialogueCollection } from "@/lib/db/schema";
import { createUnitSchema } from "@/lib/dialogue/types";

export async function GET() {
  const [units, collections] = await Promise.all([
    db.query.curriculumUnit.findMany({
      orderBy: [asc(curriculumUnit.orderIndex), asc(curriculumUnit.id)],
    }),
    db.query.dialogueCollection.findMany({
      orderBy: [asc(dialogueCollection.orderIndex), asc(dialogueCollection.id)],
      columns: { id: true, unitId: true, title: true },
    }),
  ]);

  const collectionsByUnit = new Map<string, typeof collections>();
  for (const collection of collections) {
    if (!collection.unitId) continue;
    const list = collectionsByUnit.get(collection.unitId) ?? [];
    list.push(collection);
    collectionsByUnit.set(collection.unitId, list);
  }

  return NextResponse.json({
    units: units.map((unit) => ({
      ...unit,
      collections: collectionsByUnit.get(unit.id) ?? [],
    })),
  });
}

export async function POST(request: NextRequest) {
  const body = await request.json();
  const parsed = createUnitSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const existing = await db.query.curriculumUnit.findFirst({
    where: (table, { eq }) => eq(table.id, parsed.data.id),
  });
  if (existing) {
    return NextResponse.json(
      { error: `Unit "${parsed.data.id}" already exists.` },
      { status: 409 }
    );
  }

  const [unit] = await db
    .insert(curriculumUnit)
    .values({
      id: parsed.data.id,
      title: parsed.data.title,
      subtitle: parsed.data.subtitle ?? null,
      jlptLevel: parsed.data.jlptLevel,
      orderIndex: parsed.data.orderIndex ?? 0,
    })
    .returning();

  return NextResponse.json({ unit }, { status: 201 });
}
