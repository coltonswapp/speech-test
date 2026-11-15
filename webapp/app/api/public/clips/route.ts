import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { clipPayloadSummary, type ClipPayloadSummary } from "@/lib/experiments/clips/payload";
import { listClipDrafts } from "@/lib/experiments/clips/store";
import { YOUTUBE_ID_PATTERN, clipSuitsLevel } from "@/lib/experiments/clips/types";

/**
 * Aligned, non-deprecated experiment clips for the app, newest first.
 *
 * `?level=5` (5 = N5 … 1 = N1) is the learner's level: only clips rated at
 * that level or easier come back, and unrated clips are left out. Without it,
 * every clip is listed.
 *
 * `?feed=1` keeps only feed clips (see lib/experiments/clips/feed.ts): the
 * ones worth a swipe. The rest stay listed without it, and by `video_id`.
 *
 * `?video_id=<YouTube id>` keeps only the clips cut from that video, in video
 * order (earliest first): "more from this video" next to a clip.
 */
export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  const levelParam = params.get("level");
  const level = levelParam === null ? null : Number(levelParam);
  if (level !== null && !(Number.isInteger(level) && level >= 1 && level <= 5)) {
    return NextResponse.json({ error: "level must be 1 (N1) to 5 (N5)." }, { status: 400 });
  }
  const videoId = params.get("video_id");
  if (videoId !== null && !YOUTUBE_ID_PATTERN.test(videoId)) {
    return NextResponse.json({ error: "video_id must be a YouTube video id." }, { status: 400 });
  }
  const feedOnly = ["1", "true"].includes(params.get("feed") ?? "");
  const drafts = await listClipDrafts();
  const clips = drafts
    .filter((draft) => videoId === null || draft.videoId === videoId)
    .map(clipPayloadSummary)
    .filter((c): c is ClipPayloadSummary => c !== null)
    .filter((c) => !feedOnly || c.in_feed)
    .filter((c) => level === null || clipSuitsLevel(c.jlpt_level, level));
  if (videoId !== null) clips.sort((a, b) => a.start_sec - b.start_sec);
  return NextResponse.json(
    { clips },
    { headers: { "Cache-Control": "private, no-store" } }
  );
}
