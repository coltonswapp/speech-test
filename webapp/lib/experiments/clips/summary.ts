import { clipFeedStatus } from "@/lib/experiments/clips/feed";
import { clipPayloadSummary, type ClipPayloadSummary } from "@/lib/experiments/clips/payload";
import { clipEffectiveTags, clipSpeechPace, clipTagKeys } from "@/lib/experiments/clips/tags";
import {
  clipHasHighlights,
  clipIsAligned,
  clipIsTokenized,
  clipIsTranslated,
  clipListedAt,
  type ClipDraft,
  type ClipSummary,
} from "@/lib/experiments/clips/types";

// What the clip index (lib/db/schema.ts `clip_index`) keeps per draft. No
// server-only imports: scripts/clip-index-backfill.ts uses it too.

export function clipSummary(d: ClipDraft): ClipSummary {
  const feed = clipFeedStatus(d);
  return {
    feed: feed.state,
    feedReason: feed.reason,
    tags: clipEffectiveTags(d.tags),
    tagsSource: d.tags?.manual ? "manual" : d.tags?.auto ? "auto" : null,
    pace: clipIsAligned(d) ? roundPace(clipSpeechPace(d.sentences)) : null,
    id: d.id,
    videoId: d.videoId,
    videoTitle: d.video?.title ?? null,
    videoTitleEn: d.video?.titleEn?.text ?? null,
    channelName: d.video?.channelName ?? null,
    channelUrl: d.video?.channelUrl ?? null,
    startSec: d.startSec,
    endSec: d.endSec,
    orientation: d.orientation ?? "landscape",
    sentenceCount: d.sentences.length,
    tokenized: clipIsTokenized(d),
    translated: clipIsTranslated(d),
    highlighted: clipHasHighlights(d),
    aligned: clipIsAligned(d),
    jlptLevel: d.difficulty?.jlptLevel ?? null,
    deprecated: Boolean(d.deprecated),
    listedAt: clipListedAt(d),
    createdAt: d.createdAt,
    updatedAt: d.updatedAt,
  };
}

const roundPace = (pace: number | null) => (pace === null ? null : Math.round(pace * 10) / 10);

export type ClipIndexRow = {
  id: string;
  videoId: string;
  listed: boolean;
  inFeed: boolean;
  jlptLevel: number | null;
  /** `facet:value` keys (see clipTagKeys), pace included once aligned. */
  tags: string[];
  /** Characters per second of speech; null until aligned. */
  pace: number | null;
  startSec: number;
  /** When the clip first appeared in the app (the public list's order); null if never. */
  listedAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
  summary: ClipSummary;
  publicSummary: ClipPayloadSummary | null;
};

export function clipIndexRow(draft: ClipDraft): ClipIndexRow {
  const publicSummary = clipPayloadSummary(draft);
  const pace = clipIsAligned(draft) ? roundPace(clipSpeechPace(draft.sentences)) : null;
  const listedAt = clipListedAt(draft);
  return {
    id: draft.id,
    videoId: draft.videoId,
    listed: publicSummary !== null,
    inFeed: publicSummary?.in_feed ?? false,
    jlptLevel: draft.difficulty?.jlptLevel ?? null,
    tags: clipTagKeys(clipEffectiveTags(draft.tags), pace),
    pace,
    startSec: draft.startSec,
    listedAt: listedAt ? new Date(listedAt) : null,
    createdAt: new Date(draft.createdAt),
    updatedAt: new Date(draft.updatedAt),
    summary: clipSummary(draft),
    publicSummary,
  };
}

/**
 * Same as the table in lib/db/schema.ts. The backfill script runs it so the
 * table exists without a drizzle-kit push of the whole schema.
 */
export const CLIP_INDEX_DDL = `
CREATE TABLE IF NOT EXISTS clip_index (
  id text PRIMARY KEY,
  video_id text NOT NULL,
  listed boolean NOT NULL,
  in_feed boolean NOT NULL,
  jlpt_level integer,
  start_sec real NOT NULL,
  created_at timestamp with time zone NOT NULL,
  updated_at timestamp with time zone NOT NULL,
  summary jsonb NOT NULL,
  public_summary jsonb
);
CREATE INDEX IF NOT EXISTS clip_index_video_idx ON clip_index (video_id);
ALTER TABLE clip_index ADD COLUMN IF NOT EXISTS tags text[] NOT NULL DEFAULT '{}';
ALTER TABLE clip_index ADD COLUMN IF NOT EXISTS pace real;
CREATE INDEX IF NOT EXISTS clip_index_tags_idx ON clip_index USING gin (tags);
ALTER TABLE clip_index ADD COLUMN IF NOT EXISTS listed_at timestamp with time zone;
DROP INDEX IF EXISTS clip_index_public_idx;
CREATE INDEX IF NOT EXISTS clip_index_listed_idx ON clip_index (listed, in_feed, listed_at);
`;
