import "server-only";
import { z } from "zod";
import { ClipPipelineError } from "@/lib/experiments/clips/asr";
import type { ClipVideoInfo } from "@/lib/experiments/clips/types";

// Video title and channel from YouTube's public oEmbed endpoint: no API key,
// and only the video id leaves Studio. It has no description, publish date or
// video length; those would need the YouTube Data API and a key.

const oembedSchema = z.object({
  title: z.string(),
  author_name: z.string(),
  author_url: z.string().optional(),
  thumbnail_url: z.string().optional(),
});

/**
 * Throws ClipPipelineError when YouTube won't describe the video: 404 = it is
 * deleted or the id is wrong; 401/403 = private or embedding is turned off
 * (the app's player can't show those either).
 */
export async function fetchYouTubeVideoInfo(videoId: string): Promise<ClipVideoInfo> {
  const watchUrl = `https://www.youtube.com/watch?v=${videoId}`;
  let response: Response;
  try {
    response = await fetch(
      `https://www.youtube.com/oembed?format=json&url=${encodeURIComponent(watchUrl)}`,
      { signal: AbortSignal.timeout(10_000), cache: "no-store" }
    );
  } catch (error) {
    throw new ClipPipelineError(
      `Couldn’t reach YouTube: ${error instanceof Error ? error.message : String(error)}`,
      502
    );
  }
  if (response.status === 404 || response.status === 400) {
    throw new ClipPipelineError(
      `YouTube has no video ${videoId}. It may have been deleted; consider deprecating the clip.`,
      404
    );
  }
  if (response.status === 401 || response.status === 403) {
    throw new ClipPipelineError(
      `YouTube video ${videoId} is private or can’t be embedded, so the app can’t play it; consider deprecating the clip.`,
      422
    );
  }
  if (!response.ok) {
    throw new ClipPipelineError(`YouTube video info failed (HTTP ${response.status}).`, 502);
  }
  const parsed = oembedSchema.safeParse(await response.json().catch(() => null));
  if (!parsed.success) {
    throw new ClipPipelineError("YouTube video info was not in the expected shape.", 502);
  }
  const { title, author_name, author_url, thumbnail_url } = parsed.data;
  return {
    title: title.trim(),
    channelName: author_name.trim(),
    ...(author_url ? { channelUrl: author_url } : {}),
    ...(thumbnail_url ? { thumbnailUrl: thumbnail_url } : {}),
    fetchedAt: new Date().toISOString(),
  };
}
