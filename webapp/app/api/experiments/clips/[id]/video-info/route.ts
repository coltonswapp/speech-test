import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { clipErrorResponse, loadClipOr404 } from "@/lib/experiments/clips/route-helpers";
import { writeClipDraft } from "@/lib/experiments/clips/store";
import { fetchYouTubeVideoInfo } from "@/lib/experiments/clips/youtube-info";

/**
 * Fetch (or refresh) the clip's video title and channel from YouTube. Errors
 * leave the saved info as it was; a 404 or 422 means the video is gone,
 * private or not embeddable.
 */
export async function POST(
  _request: NextRequest,
  ctx: RouteContext<"/api/experiments/clips/[id]/video-info">
) {
  try {
    const { id } = await ctx.params;
    const loaded = await loadClipOr404(id);
    if ("response" in loaded) return loaded.response;
    const video = await fetchYouTubeVideoInfo(loaded.draft.videoId);
    return NextResponse.json({ draft: await writeClipDraft({ ...loaded.draft, video }) });
  } catch (error) {
    return clipErrorResponse(error);
  }
}
