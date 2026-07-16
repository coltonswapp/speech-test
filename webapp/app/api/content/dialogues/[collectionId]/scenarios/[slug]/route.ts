import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { dialogueScenario } from "@/lib/db/schema";
import { updateScenarioSchema } from "@/lib/dialogue/types";

// Scenario ids embed the collection ("train-station/buying-a-ticket"), so the
// route addresses them as collectionId + tail slug to keep slashes out of a
// single param.

export async function GET(
  _request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]/scenarios/[slug]">
) {
  const { collectionId, slug } = await ctx.params;
  const scenario = await db.query.dialogueScenario.findFirst({
    where: eq(dialogueScenario.id, `${collectionId}/${slug}`),
  });
  if (!scenario) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ scenario });
}

export async function PATCH(
  request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]/scenarios/[slug]">
) {
  const { collectionId, slug } = await ctx.params;
  const body = await request.json();
  const parsed = updateScenarioSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const [scenario] = await db
    .update(dialogueScenario)
    .set({ ...parsed.data, updatedAt: new Date() })
    .where(eq(dialogueScenario.id, `${collectionId}/${slug}`))
    .returning();
  if (!scenario) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ scenario });
}

export async function DELETE(
  _request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]/scenarios/[slug]">
) {
  const { collectionId, slug } = await ctx.params;
  const [deleted] = await db
    .delete(dialogueScenario)
    .where(eq(dialogueScenario.id, `${collectionId}/${slug}`))
    .returning({ id: dialogueScenario.id });
  if (!deleted) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ ok: true });
}
