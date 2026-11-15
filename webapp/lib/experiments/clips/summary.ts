import { clipFeedStatus } from "@/lib/experiments/clips/feed";
import { clipPayloadSummary, type ClipPayloadSummary } from "@/lib/experiments/clips/payload";
import {
  clipHasHighlights,
  clipIsAligned,
  clipIsTokenized,
  clipIsTranslated,
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
    id: d.id,
    videoId: d.videoId,
    videoTitle: d.video?.title ?? null,
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
    createdAt: d.createdAt,
    updatedAt: d.updatedAt,
  };
}

export type ClipIndexRow = {
  id: string;
  videoId: string;
  listed: boolean;
  inFeed: boolean;
  jlptLevel: number | null;
  startSec: number;
  createdAt: Date;
  updatedAt: Date;
  summary: ClipSummary;
  publicSummary: ClipPayloadSummary | null;
};

export function clipIndexRow(draft: ClipDraft): ClipIndexRow {
  const publicSummary = clipPayloadSummary(draft);
  return {
    id: draft.id,
    videoId: draft.videoId,
    listed: publicSummary !== null,
    inFeed: publicSummary?.in_feed ?? false,
    jlptLevel: draft.difficulty?.jlptLevel ?? null,
    startSec: draft.startSec,
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
CREATE INDEX IF NOT EXISTS clip_index_public_idx ON clip_index (listed, in_feed, created_at);
CREATE INDEX IF NOT EXISTS clip_index_video_idx ON clip_index (video_id);
`;
