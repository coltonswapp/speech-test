import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { grammarPoint, recentPointView } from "@/lib/db/schema";
import { updatePointSchema } from "@/lib/content/types";

export async function GET(
  _request: NextRequest,
  ctx: RouteContext<"/api/content/points/[id]">
) {
  const { id } = await ctx.params;
  const point = await db.query.grammarPoint.findFirst({
    where: eq(grammarPoint.id, id),
  });
  if (!point) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  await db.insert(recentPointView).values({ pointId: id });

  return NextResponse.json({ point });
}

export async function PATCH(
  request: NextRequest,
  ctx: RouteContext<"/api/content/points/[id]">
) {
  const { id } = await ctx.params;
  const body = await request.json();
  const parsed = updatePointSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const { id: _ignoredId, relatedPointIDs, ...rest } = parsed.data;
  const updateValues: Record<string, unknown> = { ...rest, updatedAt: new Date() };
  if (relatedPointIDs !== undefined) {
    updateValues.relatedPointIds = relatedPointIDs;
  }

  const [point] = await db
    .update(grammarPoint)
    .set(updateValues)
    .where(eq(grammarPoint.id, id))
    .returning();

  if (!point) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ point });
}

export async function DELETE(
  _request: NextRequest,
  ctx: RouteContext<"/api/content/points/[id]">
) {
  const { id } = await ctx.params;
  const [deleted] = await db
    .delete(grammarPoint)
    .where(eq(grammarPoint.id, id))
    .returning({ id: grammarPoint.id });
  if (!deleted) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ ok: true });
}
