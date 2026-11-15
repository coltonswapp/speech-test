import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { z } from "zod";
import { clipErrorResponse } from "@/lib/experiments/clips/route-helpers";
import { listClipDrafts, listClipPendings } from "@/lib/experiments/clips/store";
import { readClipQueue, writeClipQueue } from "@/lib/experiments/clips/queue-store";
import {
  clipQueueFlags,
  clipQueueStatusSchema,
  compareQueueRows,
  type ClipQueueRow,
} from "@/lib/experiments/clips/queue";
import { YOUTUBE_ID_PATTERN } from "@/lib/experiments/clips/types";

/**
 * The clip queue, best entries first, each with its warnings and what has
 * become of it (read from the clips and pending uploads, not stored).
 */
export async function GET() {
  try {
    const [queue, drafts, pendings] = await Promise.all([
      readClipQueue(),
      listClipDrafts(),
      listClipPendings(),
    ]);
    const clipIds = new Map<string, string[]>();
    for (const d of drafts) clipIds.set(d.videoId, [...(clipIds.get(d.videoId) ?? []), d.id]);
    const fetching = new Set(pendings.filter((p) => !p.done).map((p) => p.videoId));
    const channelCount = new Map(
      queue.channels.map((c) => [c.channelId, c.dumpShorts + c.dumpRegular])
    );
    const rows: ClipQueueRow[] = queue.items.map((item) => {
      const ids = (clipIds.get(item.videoId) ?? []).sort();
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
