import "server-only";
import { z } from "zod";
import { getProviderKey } from "@/lib/secrets";
import { GEMINI_TAG_MODEL_DEFAULT } from "@/lib/gemini/models";
import { geminiGenerateContentUrl, geminiThinkingConfig } from "@/lib/gemini/text-model";
import { ClipPipelineError } from "@/lib/experiments/clips/asr";
import type { ClipVideoInfo } from "@/lib/experiments/clips/types";
import {
  buildVideoTitlePrompt,
  cleanVideoTitle,
  parseVideoTitleAnswer,
  titleNeedsTranslation,
  VIDEO_TITLE_GEMINI_SCHEMA,
} from "@/lib/experiments/clips/video-title";

// Video title and channel from YouTube's public oEmbed endpoint: no API key,
// and only the video id leaves Studio. It has no description, publish date or
// video length; those would need the YouTube Data API and a key. The title is
// also translated into English: one short call (~110 tokens in) on the Tag
// step's model, which got names and numbers (200万 = 2M) right where
// Flash-Lite slipped.

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
 *
 * `previous` (on Refresh): its English title is kept while YouTube's title is
 * unchanged. The English title is best effort: if the translation fails, the
 * info comes back without one.
 */
export async function fetchYouTubeVideoInfo(
  videoId: string,
  previous?: ClipVideoInfo
): Promise<ClipVideoInfo> {
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
  const { title: rawTitle, author_name, author_url, thumbnail_url } = parsed.data;
  const title = rawTitle.trim();
  const titleEn =
    previous?.titleEn && previous.title === title
      ? previous.titleEn
      : await translateVideoTitle(title).catch((error) => {
          console.warn(`English title for ${videoId} failed: ${error instanceof Error ? error.message : error}`);
          return undefined;
        });
  return {
    title,
    channelName: author_name.trim(),
    ...(author_url ? { channelUrl: author_url } : {}),
    ...(thumbnail_url ? { thumbnailUrl: thumbnail_url } : {}),
    ...(titleEn ? { titleEn } : {}),
    fetchedAt: new Date().toISOString(),
  };
}

/** The title in English, trailing hashtags left out; undefined when it has no Japanese to translate. */
async function translateVideoTitle(title: string): Promise<ClipVideoInfo["titleEn"]> {
  if (!titleNeedsTranslation(title)) return undefined;
  const apiKey = getProviderKey("gemini");
  if (!apiKey) throw new Error("Missing Gemini API key.");
  const model = process.env.GEMINI_TAG_MODEL?.trim() || GEMINI_TAG_MODEL_DEFAULT;
  const thinkingConfig = geminiThinkingConfig(model, "low");
  const response = await fetch(geminiGenerateContentUrl(model), {
    method: "POST",
    headers: { "x-goog-api-key": apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: buildVideoTitlePrompt(cleanVideoTitle(title)) }] }],
      generationConfig: {
        ...(thinkingConfig ? { thinkingConfig } : {}),
        responseMimeType: "application/json",
        responseSchema: VIDEO_TITLE_GEMINI_SCHEMA,
      },
    }),
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) throw new Error(`Gemini HTTP ${response.status}`);
  const json = await response.json();
  const raw = json?.candidates?.[0]?.content?.parts?.map((p: { text?: string }) => p?.text ?? "").join("");
  const text = parseVideoTitleAnswer(JSON.parse(typeof raw === "string" ? raw : "null"), title);
  if (!text) throw new Error("Gemini gave no usable English title.");
  return { text, model, at: new Date().toISOString() };
}
