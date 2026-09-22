import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { slideshowDeck } from "@/lib/db/schema";
import { parsePartNumber } from "@/lib/slides/hashtags";
import { patchDeckSchema } from "@/lib/slides/schemas";
import {
  serializeDeck,
  setLastDecompositionPart,
} from "@/lib/slides/store";
import type { DecompositionPayload } from "@/lib/slides/types";

export async function GET(
  _request: NextRequest,
  ctx: RouteContext<"/api/content/slides/[deckId]">
) {
  const { deckId } = await ctx.params;
  const row = await db.query.slideshowDeck.findFirst({
    where: eq(slideshowDeck.id, deckId),
  });
  if (!row) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ deck: serializeDeck(row) });
}

export async function PATCH(
  request: NextRequest,
  ctx: RouteContext<"/api/content/slides/[deckId]">
) {
  const { deckId } = await ctx.params;
  const body = await request.json().catch(() => ({}));
  const parsed = patchDeckSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }
  if (Object.keys(parsed.data).length === 0) {
    return NextResponse.json({ error: "Nothing to update." }, { status: 400 });
  }

  const existing = await db.query.slideshowDeck.findFirst({
    where: eq(slideshowDeck.id, deckId),
  });
  if (!existing) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const [row] = await db
    .update(slideshowDeck)
    .set({
      ...parsed.data,
      updatedAt: new Date(),
    })
    .where(eq(slideshowDeck.id, deckId))
    .returning();

  const next = serializeDeck(row);
  if (
    parsed.data.status === "exported" &&
    next.kind === "decomposition"
  ) {
    const payload = next.payload as DecompositionPayload;
    const part = parsePartNumber(payload.partLabel);
    if (part != null) await setLastDecompositionPart(part);
  }

  return NextResponse.json({ deck: next });
}

export async function DELETE(
  _request: NextRequest,
  ctx: RouteContext<"/api/content/slides/[deckId]">
) {
  const { deckId } = await ctx.params;
  const existing = await db.query.slideshowDeck.findFirst({
    where: eq(slideshowDeck.id, deckId),
  });
  if (!existing) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  await db.delete(slideshowDeck).where(eq(slideshowDeck.id, deckId));
  return NextResponse.json({ ok: true });
}
