import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { z } from "zod";
import { clipErrorResponse } from "@/lib/experiments/clips/route-helpers";
import { listClipPendings } from "@/lib/experiments/clips/store";
import { indexedClipIdsByVideo } from "@/lib/experiments/clips/clip-index";
import { readClipQueue, writeClipQueue } from "@/lib/experiments/clips/queue-store";
import {
  QUEUE_MAX_SECONDS,
  clipQueueFlags,
  clipQueueSourceSchema,
  clipQueueStatusSchema,
  compareQueueRows,
  type ClipQueueItem,
  type ClipQueueRow,
} from "@/lib/experiments/clips/queue";
import { YOUTUBE_ID_PATTERN } from "@/lib/experiments/clips/types";

/**
 * The clip queue, best entries first, each with its warnings and what has
 * become of it (read from the clips and pending uploads, not stored).
 */
export async function GET() {
  try {
    const [queue, clipIds, pendings] = await Promise.all([
      readClipQueue(),
      indexedClipIdsByVideo(),
      listClipPendings(),
    ]);
    const fetching = new Set(pendings.filter((p) => !p.done).map((p) => p.videoId));
    const channelCount = new Map(
      queue.channels.map((c) => [c.channelId, c.dumpShorts + c.dumpRegular])
    );
    const rows: ClipQueueRow[] = queue.items.map((item) => {
      const ids = clipIds.get(item.videoId) ?? [];
      return {
        ...item,
        flags: clipQueueFlags(item),
        progress: ids.length > 0 ? "clipped" : fetching.has(item.videoId) ? "fetching" : "none",
        clipIds: ids,
        channelDumpCount: item.channelId ? (channelCount.get(item.channelId) ?? 0) : 0,
      };
    });
    rows.sort(compareQueueRows);
    return NextResponse.json(
      { rows, channels: queue.channels.length, updatedAt: queue.updatedAt },
      { headers: { "Cache-Control": "private, no-store" } }
    );
  } catch (error) {
    return clipErrorResponse(error);
  }
}

const patchSchema = z.object({
  videoIds: z.array(z.string().regex(YOUTUBE_ID_PATTERN)).min(1).max(500),
  status: clipQueueStatusSchema,
  note: z.string().max(500).optional(),
});

/** Skip entries (or put them back in the queue). */
export async function PATCH(request: NextRequest) {
  try {
    const parsed = patchSchema.safeParse(await request.json().catch(() => null));
    if (!parsed.success) {
      return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
    }
    const { videoIds, status, note } = parsed.data;
    const wanted = new Set(videoIds);
    const queue = await readClipQueue();
    const now = new Date().toISOString();
    let changed = 0;
    const items = queue.items.map((item) => {
      if (!wanted.has(item.videoId)) return item;
      changed++;
      const next = { ...item, status, updatedAt: now };
      if (note !== undefined) {
        if (note.trim()) next.note = note.trim();
        else delete next.note;
      }
      return next;
    });
    if (changed === 0) return NextResponse.json({ error: "Not in the queue." }, { status: 404 });
    await writeClipQueue({ ...queue, items });
    return NextResponse.json({ changed });
  } catch (error) {
    return clipErrorResponse(error);
  }
}

const addItemSchema = z.object({
  videoId: z.string().regex(YOUTUBE_ID_PATTERN),
  title: z.string().trim().min(1).max(500),
  channelName: z.string().trim().min(1).max(200),
  channelId: z.string().max(64).nullable(),
  durationSec: z.number().nonnegative().nullable(),
});

const postSchema = z.object({
  items: z.array(addItemSchema).min(1).max(100),
  source: clipQueueSourceSchema,
  /** Only report what would happen; nothing is written. */
  dryRun: z.boolean().default(false),
});

type AddOutcome =
  | { videoId: string; result: "new" | "added"; flags: string[] }
  | { videoId: string; result: "duplicate" }
  | {
      videoId: string;
      result: "exists";
      status: ClipQueueItem["status"];
      note?: string;
      progress: ClipQueueRow["progress"];
      clipIds: string[];
    }
  | { videoId: string; result: "clipped"; clipIds: string[] }
  | { videoId: string; result: "fetching" }
  | { videoId: string; result: "rejected"; reason: string }
  | { videoId: string; result: "lost"; reason: string };

/**
 * Add videos to the queue as `queued`. Never starts processing (that is
 * run_clip_queue_batch). Safe to retry: entries already in the queue are
 * reported and left untouched, and so are videos that already have clips or
 * an audio fetch in progress. Over QUEUE_MAX_SECONDS is refused. With dryRun,
 * reports the same outcomes ("new" instead of "added") without writing.
 */
export async function POST(request: NextRequest) {
  try {
    const parsed = postSchema.safeParse(await request.json().catch(() => null));
    if (!parsed.success) {
      return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
    }
    const { items, source, dryRun } = parsed.data;
    const videoIds = [...new Set(items.map((i) => i.videoId))];
    const [queue, clipIds, pendings] = await Promise.all([
      readClipQueue(),
      indexedClipIdsByVideo(videoIds),
      listClipPendings(),
    ]);
    const fetching = new Set(pendings.filter((p) => !p.done).map((p) => p.videoId));
    const inQueue = new Map(queue.items.map((item) => [item.videoId, item]));
    const now = new Date().toISOString();
    const seen = new Set<string>();
    const outcomes: AddOutcome[] = [];
    const toAdd: ClipQueueItem[] = [];

    for (const item of items) {
      const { videoId } = item;
      if (seen.has(videoId)) {
        outcomes.push({ videoId, result: "duplicate" });
        continue;
      }
      seen.add(videoId);
      const ids = clipIds.get(videoId) ?? [];
      const existing = inQueue.get(videoId);
      if (existing) {
        outcomes.push({
          videoId,
          result: "exists",
          status: existing.status,
          ...(existing.note ? { note: existing.note } : {}),
          progress: ids.length > 0 ? "clipped" : fetching.has(videoId) ? "fetching" : "none",
          clipIds: ids,
        });
      } else if (ids.length > 0) {
        outcomes.push({ videoId, result: "clipped", clipIds: ids });
      } else if (fetching.has(videoId)) {
        outcomes.push({ videoId, result: "fetching" });
      } else if (item.durationSec !== null && item.durationSec > QUEUE_MAX_SECONDS) {
        outcomes.push({
          videoId,
          result: "rejected",
          reason: `${Math.round(item.durationSec)} s is over the queue's ${QUEUE_MAX_SECONDS} s; make clips from it directly instead.`,
        });
      } else {
        toAdd.push({ ...item, source, status: "queued", addedAt: now, updatedAt: now });
        outcomes.push({ videoId, result: dryRun ? "new" : "added", flags: clipQueueFlags(item) });
      }
    }

    if (!dryRun && toAdd.length > 0) {
      await writeClipQueue({ ...queue, items: [...queue.items, ...toAdd] });
      // The store is read-modify-write; a write landing at the same moment
      // can drop ours. Look again and say which ones to retry.
      const after = new Set((await readClipQueue()).items.map((i) => i.videoId));
      for (let i = 0; i < outcomes.length; i++) {
        const o = outcomes[i]!;
        if (o.result === "added" && !after.has(o.videoId)) {
          outcomes[i] = {
            videoId: o.videoId,
            result: "lost",
            reason: "Another queue write overwrote this one. Retry; entries already added are left alone.",
          };
        }
      }
    }

    return NextResponse.json({ dryRun, outcomes });
  } catch (error) {
    return clipErrorResponse(error);
  }
}
