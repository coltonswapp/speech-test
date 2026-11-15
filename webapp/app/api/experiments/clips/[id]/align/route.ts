import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { alignClipDraft } from "@/lib/experiments/clips/pipeline";
import { clipErrorResponse, loadClipOr404 } from "@/lib/experiments/clips/route-helpers";
import { writeClipDraft } from "@/lib/experiments/clips/store";

export const maxDuration = 300;

/**
 * Force-align all tokens to clip.wav (clip-relative seconds). Body
 * `{ onlyUntimed: true }` keeps already-timed lines as they are.
 */
export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/experiments/clips/[id]/align">
) {
  try {
    const { id } = await ctx.params;
    const loaded = await loadClipOr404(id);
    if ("response" in loaded) return loaded.response;
    const body: unknown = await request.json().catch(() => null);
    const onlyUntimed =
      typeof body === "object" && body !== null && "onlyUntimed" in body && body.onlyUntimed === true;
    const next = await alignClipDraft(loaded.draft, { onlyUntimed });
    return NextResponse.json({ draft: await writeClipDraft(next) });
  } catch (error) {
    return clipErrorResponse(error);
  }
}
