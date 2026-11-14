import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { clipPayloadSummary, type ClipPayloadSummary } from "@/lib/experiments/clips/payload";
import { listClipDrafts } from "@/lib/experiments/clips/store";
import { clipSuitsLevel } from "@/lib/experiments/clips/types";

/**
 * Aligned, non-deprecated experiment clips for the app, newest first.
 *
 * `?level=5` (5 = N5 … 1 = N1) is the learner's level: only clips rated at
 * that level or easier come back, and unrated clips are left out. Without it,
 * every clip is listed.
 */
export async function GET(request: NextRequest) {
  const levelParam = request.nextUrl.searchParams.get("level");
  const level = levelParam === null ? null : Number(levelParam);
  if (level !== null && !(Number.isInteger(level) && level >= 1 && level <= 5)) {
    return NextResponse.json({ error: "level must be 1 (N1) to 5 (N5)." }, { status: 400 });
  }
  const drafts = await listClipDrafts();
  const clips = drafts
    .map(clipPayloadSummary)
    .filter((c): c is ClipPayloadSummary => c !== null)
    .filter((c) => level === null || clipSuitsLevel(c.jlpt_level, level));
  return NextResponse.json(
    { clips },
    { headers: { "Cache-Control": "private, no-store" } }
  );
}
