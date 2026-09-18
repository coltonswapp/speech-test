import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db/client";
import { ttsVariant } from "@/lib/db/schema";
import {
  clearFlagsForLine,
  parseVariantTokenSync,
} from "@/lib/dialogue/token-sync";
import { recordReviewEvent } from "@/lib/dialogue/review-timing";

const bodySchema = z.object({
  lineIndex: z.number().int().nonnegative(),
});

/**
 * Approve one flagged line in the review queue: clear tokenSync.flags for that
 * lineIndex. When no flags remain, flip source → reviewed (take leaves queue).
 */
export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/variants/[variantId]/approve-line">
) {
  const { id, variantId } = await ctx.params;
  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: "lineIndex is required." }, { status: 400 });
  }
  const { lineIndex } = parsed.data;

  const variant = await db.query.ttsVariant.findFirst({
    where: eq(ttsVariant.id, variantId),
  });
  if (!variant || variant.projectId !== id) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const sync = parseVariantTokenSync(variant.tokenSync);
  if (!sync) {
    return NextResponse.json({ error: "Take has no token sync." }, { status: 400 });
  }
  if (sync.source === "reviewed") {
    return NextResponse.json({
      variant,
      takeReviewed: true,
      alreadyReviewed: true,
    });
  }
  if (sync.source !== "auto") {
    return NextResponse.json(
      { error: "Only auto-stamped takes can approve lines from the queue." },
      { status: 409 }
    );
  }
  if (lineIndex >= sync.lines.length) {
    return NextResponse.json({ error: "lineIndex out of range." }, { status: 400 });
  }

  const { sync: next, takeReviewed } = clearFlagsForLine(sync, lineIndex);
  if (next === sync) {
    return NextResponse.json({ variant, takeReviewed: false, cleared: false });
  }

  const [updated] = await db
    .update(ttsVariant)
    .set({ tokenSync: next })
    .where(eq(ttsVariant.id, variantId))
    .returning();

  if (takeReviewed) {
    await recordReviewEvent(variantId, "reviewed").catch((error: unknown) => {
      console.error(`[approve-line] timing record failed for ${variantId}:`, error);
    });
  }

  return NextResponse.json({
    variant: updated,
    takeReviewed,
    cleared: true,
    alreadyReviewed: false,
  });
}
