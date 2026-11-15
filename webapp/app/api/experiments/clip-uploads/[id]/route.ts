import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { clipErrorResponse } from "@/lib/experiments/clips/route-helpers";
import { discardClipPending, isValidClipId, readClipPending } from "@/lib/experiments/clips/store";
import { clipPendingInfo } from "@/lib/experiments/clips/types";

/**
 * Where a script-made clip stands, for Studio to poll while the script runs.
 * `created` is null until the upload hook has made the clip(s), then their
 * ids in video order. Both null: discarded (or never saved).
 */
export async function GET(
  _request: NextRequest,
  ctx: RouteContext<"/api/experiments/clip-uploads/[id]">
) {
  try {
    const { id } = await ctx.params;
    if (!isValidClipId(id)) {
      return NextResponse.json({ error: "Invalid clip id" }, { status: 400 });
    }
    const pending = await readClipPending(id);
    return NextResponse.json(
      {
        pending: pending && !pending.done ? clipPendingInfo(pending) : null,
        created: pending?.done?.ids ?? null,
        videoId: pending?.videoId ?? null,
      },
      { headers: { "Cache-Control": "private, no-store" } }
    );
  } catch (error) {
    return clipErrorResponse(error);
  }
}

/** Removes a pending clip and any audio uploaded for it. Clips already made from it are left alone. */
export async function DELETE(
  _request: NextRequest,
  ctx: RouteContext<"/api/experiments/clip-uploads/[id]">
) {
  try {
    const { id } = await ctx.params;
    if (!isValidClipId(id)) {
      return NextResponse.json({ error: "Invalid clip id" }, { status: 400 });
    }
    await discardClipPending(id);
    return NextResponse.json({ ok: true });
  } catch (error) {
    return clipErrorResponse(error);
  }
}
