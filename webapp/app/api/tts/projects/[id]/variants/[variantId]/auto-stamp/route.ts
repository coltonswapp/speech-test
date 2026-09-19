import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { z } from "zod";
import {
  autoStampVariant,
  cancelAutoStampJob,
  clearAutoStampJob,
} from "@/lib/dialogue/auto-stamp";

export const maxDuration = 300;

const bodySchema = z.object({
  /** Overwrite human/reviewed stamps and mismatched marks. */
  force: z.boolean().optional(),
});

/**
 * Forced-align the take to its script and write an `auto` tokenSync (plus
 * derived line-switch marks when the take has none). KA-3.
 */
export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/variants/[variantId]/auto-stamp">
) {
  const { id, variantId } = await ctx.params;
  const parsed = bodySchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }

  const outcome = await autoStampVariant({
    variantId,
    projectId: id,
    force: parsed.data.force === true,
  });
  if (!outcome.ok) {
    return NextResponse.json(
      { error: outcome.error, ...(outcome.code ? { code: outcome.code } : {}) },
      { status: outcome.status }
    );
  }
  // A manual run supersedes any failed/done/cancelled background chain.
  await clearAutoStampJob(variantId);
  return NextResponse.json({
    variant: outcome.variant,
    flags: outcome.flags,
    marksDerived: outcome.marksDerived,
    summary: outcome.summary,
  });
}

/**
 * Abort a queued/running generate → tokenize → align chain for this take.
 * Cancels the in-flight aligner request when possible and skips the stamp
 * write (best-effort if the write has already started).
 */
export async function DELETE(
  _request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/variants/[variantId]/auto-stamp">
) {
  const { variantId } = await ctx.params;
  const result = await cancelAutoStampJob(variantId);
  if (!result.ok) {
    return NextResponse.json(
      { error: result.error ?? "Could not abort auto-stamp.", job: result.job },
      { status: result.job ? 409 : 404 }
    );
  }
  return NextResponse.json({ ok: true, job: result.job });
}
