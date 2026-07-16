import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq, max } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { dialogueCollection, dialogueScenario } from "@/lib/db/schema";
import { createScenarioSchema } from "@/lib/dialogue/types";

export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]/scenarios">
) {
  const { collectionId } = await ctx.params;
  const body = await request.json();
  const parsed = createScenarioSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const collection = await db.query.dialogueCollection.findFirst({
    where: eq(dialogueCollection.id, collectionId),
  });
  if (!collection) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const scenarioId = `${collectionId}/${parsed.data.slug}`;
  const existing = await db.query.dialogueScenario.findFirst({
    where: eq(dialogueScenario.id, scenarioId),
  });
  if (existing) {
    return NextResponse.json(
      { error: `Scenario "${scenarioId}" already exists.` },
      { status: 409 }
    );
  }

  const [{ maxOrder }] = await db
    .select({ maxOrder: max(dialogueScenario.orderIndex) })
    .from(dialogueScenario)
    .where(eq(dialogueScenario.collectionId, collectionId));

  const [scenario] = await db
    .insert(dialogueScenario)
    .values({
      id: scenarioId,
      collectionId,
      orderIndex: (maxOrder ?? -1) + 1,
      menuTitle: parsed.data.menuTitle,
      menuSubtitle: parsed.data.menuSubtitle ?? null,
      japanese: "",
      romaji: "",
      english: "",
      setting: parsed.data.setting ?? null,
      lines: [],
    })
    .returning();

  return NextResponse.json({ scenario }, { status: 201 });
}
