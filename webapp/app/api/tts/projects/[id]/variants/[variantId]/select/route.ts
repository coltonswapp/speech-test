import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { ttsVariant } from "@/lib/db/schema";
import { setProjectSelectedTake } from "@/lib/tts/selected-take";

export async function POST(
  _request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/variants/[variantId]/select">
) {
  const { id, variantId } = await ctx.params;

  const variant = await db.query.ttsVariant.findFirst({
    where: eq(ttsVariant.id, variantId),
  });
  if (!variant || variant.projectId !== id) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const result = await setProjectSelectedTake({
    projectId: id,
    nextSelectedTakeId: variantId,
  });
  if (!result.found) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  return NextResponse.json({ ok: true });
}
