import "server-only";
import { and, arrayOverlaps, asc, desc, eq, gte, inArray, lt, or, sql, type SQL } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { clipIndex } from "@/lib/db/schema";
import type { ClipPayloadSummary } from "@/lib/experiments/clips/payload";
import { clipIndexRow } from "@/lib/experiments/clips/summary";
import { CLIP_TAG_FACETS, clipTagKey, type ClipTagFacet } from "@/lib/experiments/clips/tags";
import {
  deleteClipTokenIndex,
  isUndefinedTable,
  replaceClipTokenIndex,
} from "@/lib/experiments/clips/token-index-db";
import type { ClipDraft, ClipSummary } from "@/lib/experiments/clips/types";

// Postgres index of clip drafts (see `clip_index` in lib/db/schema.ts). R2
// holds the drafts; this holds what lists need, kept in step by
// writeClipDraft / deleteClip. `pnpm clip:index-backfill` rebuilds it.
// Token rows (`clip_token_index`) are rebuilt in the same calls so a
// re-tokenized clip is searchable without a separate pipeline step.

export async function upsertClipIndex(draft: ClipDraft): Promise<void> {
  const row = clipIndexRow(draft);
  await db
    .insert(clipIndex)
    .values(row)
    .onConflictDoUpdate({ target: clipIndex.id, set: { ...row, id: undefined } });
  try {
    await replaceClipTokenIndex(db, draft);
  } catch (error) {
    // Table is created by the drizzle migration / `pnpm clip:index-backfill --write`.
    // Never fail tokenize/align/feed/patch because search index writes failed:
    // the draft is already in R2.
    if (isUndefinedTable(error, "clip_token_index")) {
      console.warn("[clips] clip_token_index is missing; skipping token index upsert");
    } else {
      console.warn("[clips] clip_token_index replace failed; clip draft was saved", error);
    }
  }
}

export async function deleteClipIndex(id: string): Promise<void> {
  try {
    await deleteClipTokenIndex(db, id);
  } catch (error) {
    if (isUndefinedTable(error, "clip_token_index")) {
      console.warn("[clips] clip_token_index is missing; skipping token index delete");
    } else {
      console.warn("[clips] clip_token_index delete failed", error);
    }
  }
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

/**
 * Opaque page cursor: the last row's sort key and id. Newest-first lists key
 * on listed_at; shuffled lists (`seed`) on the row's shuffle key.
 */
export type ClipCursor =
  | { kind: "listed"; listedAt: Date; id: string }
  | { kind: "shuffle"; key: string; id: string };

const SHUFFLE_CURSOR_PREFIX = "~";
const SHUFFLE_KEY = /^[0-9a-f]{32}$/;

function encodeCursor(cursor: ClipCursor): string {
  const text =
    cursor.kind === "listed"
      ? `${cursor.listedAt.toISOString()}|${cursor.id}`
      : `${SHUFFLE_CURSOR_PREFIX}${cursor.key}|${cursor.id}`;
  return Buffer.from(text, "utf8").toString("base64url");
}

export function decodeClipCursor(cursor: string): ClipCursor | null {
  const text = Buffer.from(cursor, "base64url").toString("utf8");
  const bar = text.indexOf("|");
  if (bar < 0) return null;
  const head = text.slice(0, bar);
  const id = text.slice(bar + 1);
  if (!id) return null;
  if (head.startsWith(SHUFFLE_CURSOR_PREFIX)) {
    const key = head.slice(SHUFFLE_CURSOR_PREFIX.length);
    return SHUFFLE_KEY.test(key) ? { kind: "shuffle", key, id } : null;
  }
  const listedAt = new Date(head);
  return Number.isNaN(listedAt.getTime()) ? null : { kind: "listed", listedAt, id };
}

/** `?seed=`: short and URL-safe (the app sends a random one per feed). */
export const CLIP_SHUFFLE_SEED = /^[A-Za-z0-9_-]{1,64}$/;

export type PublicClipQuery = {
  feedOnly: boolean;
  /** Learner level: clips at it or easier; unrated clips never match. */
  level: number | null;
  /** Exactly this JLPT level (5 = N5 … 1 = N1); unrated clips never match. */
  jlpt?: number | null;
  /** One video's clips, in video order (not paged). */
  videoId: string | null;
  /**
   * Tag filters: any of the values within a facet, every facet given
   * (format=vlog,anime & topic=food → vlogs or anime, about food).
   */
  tags?: Partial<Record<ClipTagFacet, string[]>>;
  /** Text search: video title (Japanese or English), channel, first line, or a tag value (case-insensitive). */
  q?: string | null;
  /**
   * Shuffle seed: a stable random order for this seed (md5 of id + seed), so
   * each feed session gets its own order and paging still works. null =
   * newest first. Ignored with videoId.
   */
  seed?: string | null;
  /** null = everything (older app builds). */
  limit: number | null;
  /** Must match the order: a shuffle cursor with a seed, a listed one without. */
  cursor: ClipCursor | null;
};

/**
 * Listed clips for the app: newest in the app first, shuffled by `seed`, or
 * video order for one video.
 */
export async function listPublicClips(
  q: PublicClipQuery
): Promise<{ clips: ClipPayloadSummary[]; nextCursor: string | null }> {
  const where: SQL[] = [eq(clipIndex.listed, true)];
  if (q.feedOnly) where.push(eq(clipIndex.inFeed, true));
  if (q.level !== null) where.push(gte(clipIndex.jlptLevel, q.level));
  if (q.jlpt != null) where.push(eq(clipIndex.jlptLevel, q.jlpt));
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
  const seed = q.videoId === null ? (q.seed ?? null) : null;
  // "C" collation: plain byte order for the hex keys, the same in ORDER BY and the cursor test.
  const shuffleKey = sql<string>`(md5(${clipIndex.id} || ${seed ?? ""}::text) COLLATE "C")`;
  if (paged && q.cursor) {
    if (q.cursor.kind === "shuffle") {
      const { key, id } = q.cursor;
      where.push(sql`(${shuffleKey} > ${key} OR (${shuffleKey} = ${key} AND ${clipIndex.id} > ${id}))`);
    } else {
      const { listedAt, id } = q.cursor;
      where.push(
        or(
          lt(clipIndex.listedAt, listedAt),
          and(eq(clipIndex.listedAt, listedAt), lt(clipIndex.id, id))
        )!
      );
    }
  }
  const base = db
    .select({
      id: clipIndex.id,
      listedAt: clipIndex.listedAt,
      shuffleKey,
      publicSummary: clipIndex.publicSummary,
    })
    .from(clipIndex)
    .where(and(...where))
    .orderBy(
      ...(q.videoId !== null
        ? [asc(clipIndex.startSec)]
        : seed !== null
          ? [asc(shuffleKey), asc(clipIndex.id)]
          : [desc(clipIndex.listedAt), desc(clipIndex.id)])
    );
  const rows = paged ? await base.limit(q.limit! + 1) : await base;
  const page = paged ? rows.slice(0, q.limit!) : rows;
  const last = page[page.length - 1];
  let nextCursor: string | null = null;
  if (paged && rows.length > q.limit! && last) {
    if (seed !== null) {
      nextCursor = encodeCursor({ kind: "shuffle", key: last.shuffleKey, id: last.id });
    } else if (last.listedAt) {
      // Listed rows always have listed_at (clipListedAt), so the cursor never lacks one.
      nextCursor = encodeCursor({ kind: "listed", listedAt: last.listedAt, id: last.id });
    }
  }
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

/**
 * How many listed clips (or feed clips) carry each tag value, most first.
 * `jlpt`: count only clips rated exactly that level (5 = N5 … 1 = N1).
 */
export async function listedClipFacetCounts(
  feedOnly: boolean,
  jlpt: number | null = null
): Promise<ClipFacetCounts> {
  const rows = await db.execute(sql`
    SELECT key, count(*)::int AS n
    FROM ${clipIndex}, unnest(${clipIndex.tags}) AS key
    WHERE ${clipIndex.listed} ${feedOnly ? sql`AND ${clipIndex.inFeed}` : sql``}
      ${jlpt !== null ? sql`AND ${clipIndex.jlptLevel} = ${jlpt}` : sql``}
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
