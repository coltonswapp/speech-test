import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { decodeClipCursor, listPublicClips } from "@/lib/experiments/clips/clip-index";
import { YOUTUBE_ID_PATTERN } from "@/lib/experiments/clips/types";

const PUBLIC_CLIPS_MAX_LIMIT = 50;

/**
 * Aligned, non-deprecated experiment clips for the app, newest first. Read
 * from the clip index (lib/experiments/clips/clip-index.ts).
 *
 * `?level=5` (5 = N5 … 1 = N1) is the learner's level: only clips rated at
 * that level or easier come back, and unrated clips are left out. Without it,
 * every clip is listed.
 *
 * `?feed=1` keeps only feed clips (see lib/experiments/clips/feed.ts): the
 * ones worth a swipe. The rest stay listed without it, and by `video_id`.
 *
 * `?limit=20` pages the list (at most 50): the response's `next_cursor`,
 * passed back as `?cursor=`, gets the next page; null on the last one.
 * Without `limit`, every clip comes back at once (older app builds).
 *
 * `?video_id=<YouTube id>` keeps only the clips cut from that video, in video
 * order (earliest first): "more from this video" next to a clip. Not paged.
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
  const limitParam = params.get("limit");
  const limit = limitParam === null ? null : Number(limitParam);
  if (limit !== null && !(Number.isInteger(limit) && limit >= 1 && limit <= PUBLIC_CLIPS_MAX_LIMIT)) {
    return NextResponse.json(
      { error: `limit must be 1 to ${PUBLIC_CLIPS_MAX_LIMIT}.` },
      { status: 400 }
    );
  }
  const cursorParam = params.get("cursor");
  const cursor = cursorParam ? decodeClipCursor(cursorParam) : null;
  if (cursorParam && !cursor) {
    return NextResponse.json({ error: "Bad cursor." }, { status: 400 });
  }
  const feedOnly = ["1", "true"].includes(params.get("feed") ?? "");
  try {
    const { clips, nextCursor } = await listPublicClips({ feedOnly, level, videoId, limit, cursor });
    return NextResponse.json(
      { clips, ...(limit !== null ? { next_cursor: nextCursor } : {}) },
      { headers: { "Cache-Control": "private, no-store" } }
    );
  } catch (error) {
    console.error("[public/clips]", error);
    return NextResponse.json({ error: "Couldn’t list clips." }, { status: 500 });
  }
}
