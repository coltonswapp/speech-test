// English video titles (ClipVideoInfo.titleEn). Client-safe; the Gemini call
// is in youtube-info.ts.
//
// Shorts titles often end in a run of hashtags (#shorts #おすすめ #陸上…):
// SEO filler, not title, so it is cut before translating. A hashtag inside
// the title is often the only place a name appears
// (『#僕のヒーローアカデミア FINAL SEASON』), so those keep their word.

const TRAILING_HASHTAGS = /(?:\s*[#＃][^\s#＃]+)+\s*$/;
const HASHTAG_MARK = /[#＃](?=[^\s#＃])/g;
const JAPANESE = /[぀-ヿ㐀-䶿一-鿿ｦ-ﾟ]/;

/** The title without its trailing hashtags, other hashtags as plain words, spacing tidied. */
export function cleanVideoTitle(title: string): string {
  return title.replace(TRAILING_HASHTAGS, "").replace(HASHTAG_MARK, "").replace(/\s+/g, " ").trim();
}

/**
 * Whether the title is worth translating: Japanese left after cleaning. A
 * title that is English already, or only hashtags, gets no English title.
 */
export function titleNeedsTranslation(title: string): boolean {
  return JAPANESE.test(cleanVideoTitle(title));
}

/** `title` is the cleaned title (cleanVideoTitle). */
export function buildVideoTitlePrompt(title: string): string {
  return `Translate this YouTube video title from Japanese into natural English, for a learner browsing a catalog of clips.

Rules:
- Quotes 「…」 and 『…』 become "…". Labels in 【…】 become [...], translated.
- Names in romaji, as fans would write them. Keep emoji and English words as they are.
- Keep the title's tone; don't explain or add anything.

Title: ${title}`;
}

export const VIDEO_TITLE_GEMINI_SCHEMA = {
  type: "object",
  properties: { en: { type: "string" } },
  required: ["en"],
} as const;

/** The model's English title, tidied; null when it is empty or echoes the original. */
export function parseVideoTitleAnswer(raw: unknown, title: string): string | null {
  const en = (raw as { en?: unknown } | null)?.en;
  if (typeof en !== "string") return null;
  let text = cleanVideoTitle(en);
  // Quotes around the whole answer only; a title that starts with a quote keeps it.
  if (/^["“].*["”]$/.test(text) && !/["“”]/.test(text.slice(1, -1))) text = text.slice(1, -1).trim();
  if (!text || text === title.trim() || text === cleanVideoTitle(title)) return null;
  return text;
}
