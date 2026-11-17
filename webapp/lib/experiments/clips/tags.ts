import { z } from "zod";

// Clip catalog tags, for filtering the catalog. Client-safe.
//
// Facets:
// - format: what kind of video it is (one). Channel and title are good hints.
// - topic: what the clip is about (0–3). The transcript decides, not hashtags.
// - register / speakers / dialect: how it's spoken, from the transcript.
// - pace: measured from token timings (clipSpeechPace), never asked of a model.
// - series: the show or franchise, free text, when the title names one.
//
// The Tag step picks from the vocabulary below (closed lists, so filters keep
// working: free-form model tags drift between food / cooking / gourmet). It
// also suggests values the lists lack; `pnpm clip:tag` tallies them.
// Growing the vocabulary is a code change here: drafts and the index store
// plain strings, so a new value needs no migration, only a re-tag
// (`pnpm clip:tag --write --retag`) of the clips that should get it.

export const CLIP_FORMATS = [
  "anime",
  "drama", // TV, film and short dramas with actors
  "comedy-skit", // コント, あるある sketches
  "variety", // TV variety, talk shows, panel shows, reality TV
  "vlog",
  "streamer", // game streams, VTuber and streamer clips (切り抜き)
  "explainer", // trivia, news, commentary, reviews to camera
  "how-to", // cooking, recipes, tutorials, life hacks
  "interview", // interviews, podcasts, street interviews
  "learner", // made for Japanese learners
  "other",
] as const;

export const CLIP_TOPICS = [
  "food",
  "travel",
  "school",
  "work",
  "romance",
  "family",
  "friends",
  "sports",
  "games",
  "health-fitness",
  "money-shopping",
  "tech",
  "animals",
  "history-culture",
  "beauty-fashion",
  "entertainment", // celebrities, anime/film/music talk
  "daily-life",
] as const;

export const CLIP_REGISTERS = ["casual", "polite", "keigo"] as const;
export const CLIP_SPEAKERS = ["monologue", "dialogue", "group", "narration"] as const;
export const CLIP_DIALECTS = ["standard", "kansai", "other"] as const;
export const CLIP_PACES = ["slow", "natural", "fast"] as const;

export const CLIP_TOPICS_MAX = 3;

/**
 * Characters per second of speech (pauses between lines left out). On the
 * Nov 15 Shorts: learner material and slow skits 4–6, relaxed talk 6–8, fast
 * native dramas and vlogs 9–10.5. FAST matches the Level step's N3 floor.
 */
export const CLIP_PACE_SLOW_BELOW = 6;
export const CLIP_PACE_FAST_FROM = 9;

export type ClipPace = (typeof CLIP_PACES)[number];

export function clipPaceLabel(charsPerSecond: number): ClipPace {
  if (charsPerSecond < CLIP_PACE_SLOW_BELOW) return "slow";
  if (charsPerSecond >= CLIP_PACE_FAST_FROM) return "fast";
  return "natural";
}

/** Characters per second of speech, from the sentences' token timings. */
export function clipSpeechPace(
  sentences: Array<{ text: string; tokens: Array<{ startSec?: number; endSec?: number }> | null }>
): number | null {
  let seconds = 0;
  let chars = 0;
  for (const s of sentences) {
    const start = s.tokens?.[0]?.startSec;
    const end = s.tokens?.at(-1)?.endSec;
    if (start === undefined || end === undefined || end <= start) continue;
    seconds += end - start;
    chars += s.text.length;
  }
  return seconds > 0 ? chars / seconds : null;
}

/** What a tagger or editor picks: values from the vocabulary above. */
export const clipTagPickSchema = z.object({
  format: z.enum(CLIP_FORMATS),
  topics: z.array(z.enum(CLIP_TOPICS)).max(CLIP_TOPICS_MAX),
  register: z.enum(CLIP_REGISTERS),
  speakers: z.enum(CLIP_SPEAKERS),
  dialect: z.enum(CLIP_DIALECTS),
  /** Show, anime or franchise, if the title names one. */
  series: z.string().trim().min(1).max(80).optional(),
});
export type ClipTagPick = z.infer<typeof clipTagPickSchema>;

/**
 * Tags as stored on a draft: plain strings, so a value later dropped from the
 * vocabulary never makes a draft unreadable.
 */
export const clipTagValuesSchema = z.object({
  format: z.string(),
  topics: z.array(z.string()),
  register: z.string(),
  speakers: z.string(),
  dialect: z.string(),
  series: z.string().optional(),
});
export type ClipTagValues = z.infer<typeof clipTagValuesSchema>;

/**
 * On the draft: `auto` is the Tag step's answer; `manual` a hand-set answer in
 * Studio, which always wins and which the Tag step never overwrites.
 */
export const clipTagsSchema = z.object({
  auto: clipTagValuesSchema
    .extend({
      reason: z.string().optional(),
      /** Values the vocabulary lacks, as `facet:value` (e.g. `topic:cars`). */
      suggested: z.array(z.string()).optional(),
      model: z.string(),
      at: z.string(),
    })
    .optional(),
  manual: clipTagValuesSchema.extend({ at: z.string() }).optional(),
});
export type ClipTags = z.infer<typeof clipTagsSchema>;

/** The tags that count: hand-set if any, else the Tag step's. */
export function clipEffectiveTags(tags: ClipTags | undefined): ClipTagValues | null {
  const t = tags?.manual ?? tags?.auto;
  if (!t) return null;
  return {
    format: t.format,
    topics: t.topics,
    register: t.register,
    speakers: t.speakers,
    dialect: t.dialect,
    ...(t.series ? { series: t.series } : {}),
  };
}

/** Facets the public clip list filters on (query params of the same name). */
export const CLIP_TAG_FACETS = ["format", "topic", "register", "speakers", "dialect", "pace", "series"] as const;
export type ClipTagFacet = (typeof CLIP_TAG_FACETS)[number];

/** Known values per facet (series is open). */
export const CLIP_TAG_VOCABULARY: Record<Exclude<ClipTagFacet, "series">, readonly string[]> = {
  format: CLIP_FORMATS,
  topic: CLIP_TOPICS,
  register: CLIP_REGISTERS,
  speakers: CLIP_SPEAKERS,
  dialect: CLIP_DIALECTS,
  pace: CLIP_PACES,
};

export const clipTagKey = (facet: ClipTagFacet, value: string) => `${facet}:${value}`;

/**
 * The index's `tags` column: `facet:value` strings (`format:vlog`,
 * `topic:food`, `pace:fast`…), so one GIN index serves every facet and a new
 * facet or value needs no migration.
 */
export function clipTagKeys(tags: ClipTagValues | null, pace: number | null): string[] {
  const keys: string[] = [];
  if (tags) {
    keys.push(clipTagKey("format", tags.format));
    for (const topic of tags.topics) keys.push(clipTagKey("topic", topic));
    keys.push(clipTagKey("register", tags.register));
    keys.push(clipTagKey("speakers", tags.speakers));
    keys.push(clipTagKey("dialect", tags.dialect));
    if (tags.series) keys.push(clipTagKey("series", tags.series));
  }
  if (pace !== null) keys.push(clipTagKey("pace", clipPaceLabel(pace)));
  return [...new Set(keys)];
}

/** Gemini responseSchema for the Tag step. */
export const CLIP_TAGS_GEMINI_SCHEMA = {
  type: "object",
  properties: {
    format: { type: "string", enum: [...CLIP_FORMATS] },
    topics: { type: "array", items: { type: "string", enum: [...CLIP_TOPICS] } },
    register: { type: "string", enum: [...CLIP_REGISTERS] },
    speakers: { type: "string", enum: [...CLIP_SPEAKERS] },
    dialect: { type: "string", enum: [...CLIP_DIALECTS] },
    series: { type: "string" },
    suggested: { type: "array", items: { type: "string" } },
    reason: { type: "string" },
  },
  required: ["format", "topics", "register", "speakers", "dialect", "reason"],
} as const;

const SUGGESTION = /^(format|topic|register|speakers|dialect):[a-z0-9]+(-[a-z0-9]+)*$/;

/**
 * Checks a Tag step answer against the vocabulary. Drops duplicate topics,
 * caps them, and keeps only well-formed suggestions for values the
 * vocabulary lacks.
 */
export function parseClipTagAnswer(
  raw: unknown
): { pick: ClipTagPick; reason: string; suggested: string[] } | null {
  if (!raw || typeof raw !== "object") return null;
  const obj = { ...(raw as Record<string, unknown>) };
  if (Array.isArray(obj.topics)) obj.topics = [...new Set(obj.topics)].slice(0, CLIP_TOPICS_MAX);
  if (typeof obj.series !== "string" || !obj.series.trim()) delete obj.series;
  const parsed = clipTagPickSchema.safeParse(obj);
  if (!parsed.success) return null;
  const known = new Set(
    Object.entries(CLIP_TAG_VOCABULARY).flatMap(([facet, values]) => values.map((v) => `${facet}:${v}`))
  );
  const suggested = Array.isArray(obj.suggested)
    ? [
        ...new Set(
          obj.suggested
            .filter((s): s is string => typeof s === "string")
            .map((s) => s.trim().toLowerCase())
            .filter((s) => SUGGESTION.test(s) && !known.has(s))
        ),
      ]
    : [];
  return {
    pick: parsed.data,
    reason: typeof obj.reason === "string" ? obj.reason.trim() : "",
    suggested,
  };
}

/** Hashtags that say nothing about the clip. */
const NOISE_HASHTAGS = new Set([
  "shorts", "short", "ショート", "ショート動画", "fyp", "tiktok", "おすすめ", "おすすめにのりたい",
  "バズれ", "viral", "youtube", "youtuber", "面白い", "おもしろ", "爆笑", "神回",
]);

/** Hashtags and 【…】 labels from a video title, noise dropped. */
export function titleHints(title: string): { hashtags: string[]; labels: string[] } {
  const hashtags = [...title.matchAll(/[#＃]([^\s#＃]+)/g)]
    .map((m) => m[1])
    .filter((h) => !NOISE_HASHTAGS.has(h.toLowerCase()));
  const labels = [...title.matchAll(/【([^】]+)】/g)].map((m) => m[1]);
  return { hashtags: [...new Set(hashtags)], labels: [...new Set(labels)] };
}

export type ClipTagInput = {
  title?: string;
  channelName?: string;
  /** Japanese lines with their English, if translated. */
  lines: Array<{ ja: string; en?: string }>;
  contextNotes?: string[];
};

export function clipTagInput(draft: {
  video?: { title: string; channelName: string };
  sentences: Array<{ text: string; en?: string }>;
  highlights?: { contextNotes?: string[] };
}): ClipTagInput {
  return {
    title: draft.video?.title,
    channelName: draft.video?.channelName,
    lines: draft.sentences.map((s) => ({ ja: s.text, en: s.en })),
    contextNotes: draft.highlights?.contextNotes,
  };
}

export function buildClipTagPrompt(input: ClipTagInput): string {
  const hints = input.title ? titleHints(input.title) : { hashtags: [], labels: [] };
  const meta = [
    input.title ? `Video title: ${input.title}` : "Video title: (unknown)",
    input.channelName ? `Channel: ${input.channelName}` : "Channel: (unknown)",
    hints.hashtags.length ? `Title hashtags: ${hints.hashtags.join(", ")}` : null,
    hints.labels.length ? `Title labels: ${hints.labels.join(", ")}` : null,
  ]
    .filter(Boolean)
    .join("\n");
  const transcript = input.lines
    .map((l) => (l.en ? `${l.ja}\n  (${l.en})` : l.ja))
    .join("\n");
  const notes = input.contextNotes?.length ? `\n\nNotes on the clip:\n- ${input.contextNotes.join("\n- ")}` : "";

  return `Tag this Japanese video clip for a catalog that language learners browse and filter.

The clip is a short excerpt (usually under a minute) of a YouTube video. The title, channel and hashtags describe the whole video and are often clickbait or SEO filler; use them as hints, and let the transcript decide.

Fields:
- format (one): what kind of video this is. The channel and title are usually right about this, since a short transcript often can't tell a drama from a skit.
  anime: animated. drama: scripted scenes with actors (TV, film, short dramas). comedy-skit: comedy sketches, コント, あるある. variety: TV variety, talk, panel or reality shows. vlog: someone filming their own day, trip or meal. streamer: game streams, VTuber or streamer clips (切り抜き). explainer: trivia, news, commentary or reviews spoken to camera. how-to: recipes, tutorials, life hacks. interview: interviews, podcasts, street interviews. learner: made to teach Japanese. other: none of these.
- topics (0 to ${CLIP_TOPICS_MAX}, most important first): what the clip itself talks about, judged from the transcript. Only tag a topic the clip spends real time on; a passing mention is not a topic. A title hashtag the transcript doesn't bear out is not a topic. Use daily-life only for ordinary routines with no stronger topic. Empty is fine.
- register: the dominant speech style. casual: plain forms between friends or family. polite: mostly です/ます. keigo: honorific or humble language throughout (service, business, formal TV).
- speakers: monologue (one person talking, to camera or themselves), dialogue (two people), group (three or more), narration (a voice-over describing or explaining).
- dialect: standard (Tokyo / standard Japanese), kansai (Osaka, Kyoto, Kobe speech: や, へん, ねん, めっちゃ as a pattern), other (another regional dialect, clearly marked).
- series: the anime, show or franchise the clip comes from, in its usual Japanese name, if the title or channel names one. Omit otherwise.
- suggested: values the lists above lack that would describe this clip clearly better, as "facet:value" in lowercase English with hyphens (e.g. "topic:cars", "format:music-video"). Facets: format, topic, register, speakers, dialect. Usually empty; only suggest when no listed value fits well.
- reason: one short English sentence on what decided format and topics.

${meta}

Transcript (Japanese, English in brackets):
${transcript}${notes}`;
}

export const CLIP_TAG_LABELS: Record<string, string> = {
  "comedy-skit": "Comedy skit",
  "how-to": "How-to",
  "health-fitness": "Health & fitness",
  "money-shopping": "Money & shopping",
  "history-culture": "History & culture",
  "beauty-fashion": "Beauty & fashion",
  "daily-life": "Daily life",
};

/** "comedy-skit" → "Comedy skit". */
export function clipTagLabel(value: string): string {
  return CLIP_TAG_LABELS[value] ?? value.charAt(0).toUpperCase() + value.slice(1).replace(/-/g, " ");
}
