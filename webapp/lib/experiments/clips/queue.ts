import { z } from "zod";
import { CLIP_ID_PATTERN, YOUTUBE_ID_PATTERN } from "@/lib/experiments/clips/types";
import { FEED_MAX_SECONDS, FEED_MIN_SECONDS } from "@/lib/experiments/clips/feed";

// Clip queue: YouTube Shorts waiting to become clips. Client-safe.
//
// One JSON file in R2 (`experiments/clip-queue/queue.json`), seeded by
// scripts/clip-queue-seed.ts and worked through in Studio
// (Experiments → Clip transcripts → Queue). Only the editor's own decisions
// are stored (queued / skipped); whether a video is being fetched or already
// is a clip is read from the clips themselves, so the queue never goes stale.

/**
 * Where an entry came from: the competitor index, a scan of a channel's
 * Shorts, or links someone picked (Studio MCP add_to_clip_queue).
 */
export const clipQueueSourceSchema = z.enum(["dump", "channel-scan", "link"]);

export const clipQueueStatusSchema = z.enum(["queued", "skipped"]);
export type ClipQueueStatus = z.infer<typeof clipQueueStatusSchema>;

export const clipQueueItemSchema = z.object({
  videoId: z.string().regex(YOUTUBE_ID_PATTERN),
  title: z.string(),
  channelName: z.string(),
  /** YouTube channel id (UC…); null when the index didn't have one. */
  channelId: z.string().nullable(),
  /** null when YouTube reported no duration. */
  durationSec: z.number().nullable(),
  source: clipQueueSourceSchema,
  status: clipQueueStatusSchema,
  /** Why it was skipped, or anything worth remembering. */
  note: z.string().optional(),
  addedAt: z.string(),
  updatedAt: z.string(),
});
export type ClipQueueItem = z.infer<typeof clipQueueItemSchema>;

export const clipQueueChannelSchema = z.object({
  channelId: z.string(),
  name: z.string(),
  /** Shorts and regular videos of this channel in the competitor index. */
  dumpShorts: z.number(),
  dumpRegular: z.number(),
  /** Set once the channel's own Shorts list has been added to the queue. */
  scannedAt: z.string().optional(),
});
export type ClipQueueChannel = z.infer<typeof clipQueueChannelSchema>;

export const clipQueueSchema = z.object({
  items: z.array(clipQueueItemSchema),
  channels: z.array(clipQueueChannelSchema),
  updatedAt: z.string(),
});
export type ClipQueue = z.infer<typeof clipQueueSchema>;

/**
 * Longest entry the batch takes (scripts/clip-queue-batch.ts SPLITS_AT_SECONDS):
 * longer audio gets split into several clips, which the queue doesn't do.
 * Adding to the queue refuses anything longer.
 */
export const QUEUE_MAX_SECONDS = 120;

/** Under this, a Short is rarely more than a reaction. */
export const QUEUE_MIN_SECONDS = 20;

const JAPANESE_CHAR = /[\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Han}]/u;
/** Titles that usually mean singing, playing or sounds rather than talk. */
const NO_TALK_TITLE =
  /歌ってみた|弾いてみた|叩いてみた|踊ってみた|cover|カバー|\bMV\b|music video|ASMR|咀嚼音|作業用|BGM/i;

/**
 * Warnings from what the index already says (no Gemini, no download). They
 * don't skip anything; they sort the entry to the back and show in Studio.
 */
export function clipQueueFlags(item: Pick<ClipQueueItem, "title" | "durationSec">): string[] {
  const flags: string[] = [];
  const d = item.durationSec;
  if (d === null) flags.push("No duration");
  else if (d < QUEUE_MIN_SECONDS) flags.push(`Under ${QUEUE_MIN_SECONDS} s`);
  else if (d < FEED_MIN_SECONDS) flags.push(`Under the feed’s ${FEED_MIN_SECONDS} s`);
  else if (d > FEED_MAX_SECONDS) flags.push(`Over the feed’s ${FEED_MAX_SECONDS} s`);
  if (!JAPANESE_CHAR.test(item.title)) flags.push("No Japanese in title");
  if (NO_TALK_TITLE.test(item.title)) flags.push("Music / ASMR title");
  return flags;
}

/** The clip id a queued Short becomes: `short-` + its video id, lowercased. */
export function clipQueueClipId(videoId: string): string {
  const id = `short-${videoId.toLowerCase().replace(/_/g, "-")}`;
  return CLIP_ID_PATTERN.test(id) ? id : `short-${Date.now()}`;
}

/** What Studio shows: an entry plus what has become of it. */
export type ClipQueueRow = ClipQueueItem & {
  flags: string[];
  /** "fetching": details saved, waiting for the audio script; "clipped": clips exist. */
  progress: "none" | "fetching" | "clipped";
  clipIds: string[];
  /** How many Shorts and videos the competitor took from this channel. */
  channelDumpCount: number;
};

/**
 * Best first: no warnings, then channels the competitor drew on most (a
 * channel they kept coming back to is probably reliable), then shorter.
 */
export function compareQueueRows(a: ClipQueueRow, b: ClipQueueRow): number {
  return (
    Number(a.flags.length > 0) - Number(b.flags.length > 0) ||
    b.channelDumpCount - a.channelDumpCount ||
    a.channelName.localeCompare(b.channelName) ||
    (a.durationSec ?? Infinity) - (b.durationSec ?? Infinity)
  );
}
