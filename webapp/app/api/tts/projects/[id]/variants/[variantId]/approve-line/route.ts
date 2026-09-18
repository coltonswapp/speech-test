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

const bodySchema = z.object({
  lineIndex: z.number().int().nonnegative(),
});

/**
 * Approve one line in the review queue: clear tokenSync.flags for that
 * lineIndex and record it in reviewedLineIndexes. Does not flip source →
 * reviewed — whole-take Approve does that so the take stays in the queue.
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
      takeReviewed: false,
      alreadyReviewed: true,
      cleared: false,
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

  const { sync: next, cleared } = clearFlagsForLine(sync, lineIndex);
  if (!cleared) {
    return NextResponse.json({
      variant,
      takeReviewed: false,
      cleared: false,
      alreadyReviewed: false,
    });
  }

  const [updated] = await db
    .update(ttsVariant)
    .set({ tokenSync: next })
    .where(eq(ttsVariant.id, variantId))
    .returning();

  return NextResponse.json({
    variant: updated,
    takeReviewed: false,
    cleared: true,
    alreadyReviewed: false,
  });
}
