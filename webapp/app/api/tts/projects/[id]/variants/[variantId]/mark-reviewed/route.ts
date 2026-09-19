import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { ttsVariant } from "@/lib/db/schema";
import { clearFlagsForReviewed } from "@/lib/dialogue/token-sync";
import { parseVariantTokenSync } from "@/lib/dialogue/token-sync";
import { recordReviewEvent } from "@/lib/dialogue/review-timing";

/**
 * Mark an auto-stamped take as reviewed: flip source → reviewed, clear QA
 * flags so amber chips go away, and record review telemetry.
 */
export async function POST(
  _request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/variants/[variantId]/mark-reviewed">
) {
  const { id, variantId } = await ctx.params;
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
    return NextResponse.json({ variant, alreadyReviewed: true });
  }
  if (sync.source !== "auto") {
    return NextResponse.json(
      { error: "Only auto-stamped takes can be marked reviewed." },
      { status: 409 }
    );
  }

  const next = clearFlagsForReviewed(sync);
  const [updated] = await db
    .update(ttsVariant)
    .set({ tokenSync: next })
    .where(eq(ttsVariant.id, variantId))
    .returning();

  await recordReviewEvent(variantId, "reviewed").catch((error: unknown) => {
    console.error(`[mark-reviewed] timing record failed for ${variantId}:`, error);
  });

  return NextResponse.json({ variant: updated, alreadyReviewed: false });
}
