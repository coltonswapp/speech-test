import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db/client";
import { ttsVariant } from "@/lib/db/schema";
import { recordReviewEvent } from "@/lib/dialogue/review-timing";

const bodySchema = z.object({ event: z.enum(["opened", "reviewed"]) });

/** KA-8 telemetry: the token editor reports first open and Mark reviewed. */
export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/variants/[variantId]/review-event">
) {
  const { id, variantId } = await ctx.params;
  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }
  const variant = await db.query.ttsVariant.findFirst({ where: eq(ttsVariant.id, variantId) });
  if (!variant || variant.projectId !== id) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  await recordReviewEvent(variantId, parsed.data.event);
  return NextResponse.json({ ok: true });
}
