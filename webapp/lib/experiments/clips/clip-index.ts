import "server-only";
import { and, arrayOverlaps, asc, desc, eq, gte, inArray, lt, or, sql, type SQL } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { clipIndex } from "@/lib/db/schema";
import type { ClipPayloadSummary } from "@/lib/experiments/clips/payload";
import { clipIndexRow } from "@/lib/experiments/clips/summary";
import { CLIP_TAG_FACETS, clipTagKey, type ClipTagFacet } from "@/lib/experiments/clips/tags";
import type { ClipDraft, ClipSummary } from "@/lib/experiments/clips/types";

// Postgres index of clip drafts (see `clip_index` in lib/db/schema.ts). R2
// holds the drafts; this holds what lists need, kept in step by
// writeClipDraft / deleteClip. `pnpm clip:index-backfill` rebuilds it.

export async function upsertClipIndex(draft: ClipDraft): Promise<void> {
  const row = clipIndexRow(draft);
  await db
    .insert(clipIndex)
    .values(row)
    .onConflictDoUpdate({ target: clipIndex.id, set: { ...row, id: undefined } });
}

export async function deleteClipIndex(id: string): Promise<void> {
  await db.delete(clipIndex).where(eq(clipIndex.id, id));
}

/** Every clip, newest edit first (Studio's list). */
export async function listIndexedClipSummaries(): Promise<ClipSummary[]> {
  const rows = await db
    .select({ summary: clipIndex.summary })
    .from(clipIndex)
    .orderBy(desc(clipIndex.updatedAt));
  return rows.map((r) => r.summary as ClipSummary);
}

/** Clip ids per YouTube video id, for the given videos (or all). */
export async function indexedClipIdsByVideo(videoIds?: string[]): Promise<Map<string, string[]>> {
  const rows = await db
    .select({ id: clipIndex.id, videoId: clipIndex.videoId })
    .from(clipIndex)
    .where(videoIds ? inArray(clipIndex.videoId, videoIds) : undefined)
    .orderBy(asc(clipIndex.startSec));
  const byVideo = new Map<string, string[]>();
  for (const r of rows) byVideo.set(r.videoId, [...(byVideo.get(r.videoId) ?? []), r.id]);
  return byVideo;
}

/** Opaque page cursor: the last row's listed_at and id. */
function encodeCursor(listedAt: Date, id: string): string {
  return Buffer.from(`${listedAt.toISOString()}|${id}`, "utf8").toString("base64url");
}

export function decodeClipCursor(cursor: string): { listedAt: Date; id: string } | null {
  const text = Buffer.from(cursor, "base64url").toString("utf8");
  const bar = text.indexOf("|");
  if (bar < 0) return null;
  const listedAt = new Date(text.slice(0, bar));
  const id = text.slice(bar + 1);
  return Number.isNaN(listedAt.getTime()) || !id ? null : { listedAt, id };
}

export type PublicClipQuery = {
  feedOnly: boolean;
  /** Learner level: clips at it or easier; unrated clips never match. */
  level: number | null;
  /** One video's clips, in video order (not paged). */
  videoId: string | null;
  /**
   * Tag filters: any of the values within a facet, every facet given
   * (format=vlog,anime & topic=food → vlogs or anime, about food).
   */
  tags?: Partial<Record<ClipTagFacet, string[]>>;
  /** Text search: video title (Japanese or English), channel, first line, or a tag value (case-insensitive). */
  q?: string | null;
  /** null = everything (older app builds). */
  limit: number | null;
  cursor: { listedAt: Date; id: string } | null;
};

/** Listed clips for the app: newest in the app first, or video order for one video. */
export async function listPublicClips(
  q: PublicClipQuery
): Promise<{ clips: ClipPayloadSummary[]; nextCursor: string | null }> {
  const where: SQL[] = [eq(clipIndex.listed, true)];
  if (q.feedOnly) where.push(eq(clipIndex.inFeed, true));
  if (q.level !== null) where.push(gte(clipIndex.jlptLevel, q.level));
  if (q.videoId !== null) where.push(eq(clipIndex.videoId, q.videoId));
  if (q.q) {
    const like = `%${q.q.replace(/[\\%_]/g, (c) => `\\${c}`)}%`;
    where.push(sql`(
      ${clipIndex.publicSummary}->>'title' ILIKE ${like}
      OR ${clipIndex.publicSummary}->>'title_en' ILIKE ${like}
      OR ${clipIndex.publicSummary}->>'channel_name' ILIKE ${like}
      OR ${clipIndex.publicSummary}->>'preview_jp' ILIKE ${like}
      OR ${clipIndex.id} ILIKE ${like}
      OR array_to_string(${clipIndex.tags}, ' ') ILIKE ${like}
    )`);
  }
  for (const [facet, values] of Object.entries(q.tags ?? {}) as Array<[ClipTagFacet, string[]]>) {
    if (values.length > 0) where.push(arrayOverlaps(clipIndex.tags, values.map((v) => clipTagKey(facet, v))));
  }
  const paged = q.videoId === null && q.limit !== null;
  if (paged && q.cursor) {
    where.push(
      or(
        lt(clipIndex.listedAt, q.cursor.listedAt),
        and(eq(clipIndex.listedAt, q.cursor.listedAt), lt(clipIndex.id, q.cursor.id))
      )!
    );
  }
  const base = db
    .select({
      id: clipIndex.id,
      listedAt: clipIndex.listedAt,
      publicSummary: clipIndex.publicSummary,
    })
    .from(clipIndex)
    .where(and(...where))
    .orderBy(
      ...(q.videoId !== null
        ? [asc(clipIndex.startSec)]
        : [desc(clipIndex.listedAt), desc(clipIndex.id)])
    );
  const rows = paged ? await base.limit(q.limit! + 1) : await base;
  const page = paged ? rows.slice(0, q.limit!) : rows;
  const last = page[page.length - 1];
  // Listed rows always have listed_at (clipListedAt), so the cursor never lacks one.
  const nextCursor =
    paged && rows.length > q.limit! && last?.listedAt ? encodeCursor(last.listedAt, last.id) : null;
  return {
    clips: page.map((r) => r.publicSummary as ClipPayloadSummary),
    nextCursor,
  };
}

/** Rows in the index (for a sanity check against R2). */
export async function countIndexedClips(): Promise<number> {
  const [row] = await db.select({ n: sql<number>`count(*)::int` }).from(clipIndex);
  return row?.n ?? 0;
}

export type ClipFacetCounts = Record<ClipTagFacet, Array<{ value: string; count: number }>>;

/** How many listed clips (or feed clips) carry each tag value, most first. */
export async function listedClipFacetCounts(feedOnly: boolean): Promise<ClipFacetCounts> {
  const rows = await db.execute(sql`
    SELECT key, count(*)::int AS n
    FROM ${clipIndex}, unnest(${clipIndex.tags}) AS key
    WHERE ${clipIndex.listed} ${feedOnly ? sql`AND ${clipIndex.inFeed}` : sql``}
    GROUP BY key
    ORDER BY n DESC, key
  `);
  const counts = Object.fromEntries(CLIP_TAG_FACETS.map((f) => [f, []])) as unknown as ClipFacetCounts;
  // postgres-js returns the rows as an array.
  for (const row of rows as unknown as Array<{ key: string; n: number }>) {
    const colon = row.key.indexOf(":");
    const facet = row.key.slice(0, colon) as ClipTagFacet;
    if (colon > 0 && facet in counts) counts[facet].push({ value: row.key.slice(colon + 1), count: row.n });
  }
  return counts;
}
