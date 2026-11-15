import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { tokenizeClipDraft } from "@/lib/experiments/clips/pipeline";
import { clipErrorResponse, loadClipOr404 } from "@/lib/experiments/clips/route-helpers";
import { writeClipDraft } from "@/lib/experiments/clips/store";

export const maxDuration = 300;

/**
 * Tokenize sentences that have no tokens yet (surface + reading, cached per
 * line). Body `{ "retokenize": [0, 3] }` redoes those lines (0-based) from
 * scratch; then "Align edited lines" times them.
 */
export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/experiments/clips/[id]/tokenize">
) {
  try {
    const { id } = await ctx.params;
    const loaded = await loadClipOr404(id);
    if ("response" in loaded) return loaded.response;
    const body = (await request.json().catch(() => null)) as { retokenize?: unknown } | null;
    const retokenize = Array.isArray(body?.retokenize)
      ? body.retokenize.filter((n): n is number => typeof n === "number")
      : undefined;
    const next = await tokenizeClipDraft(loaded.draft, { retokenize });
    return NextResponse.json({ draft: await writeClipDraft(next) });
  } catch (error) {
    return clipErrorResponse(error);
  }
}
