import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { ttsProject, ttsVariant } from "@/lib/db/schema";

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

  await db
    .update(ttsProject)
    .set({ selectedVariantId: variantId, updatedAt: new Date() })
    .where(eq(ttsProject.id, id));

  return NextResponse.json({ ok: true });
}
