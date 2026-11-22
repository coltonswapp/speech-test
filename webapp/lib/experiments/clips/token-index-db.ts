import { asc, eq, inArray, sql } from "drizzle-orm";
import type { PostgresJsDatabase } from "drizzle-orm/postgres-js";
import { clipTokenIndex } from "@/lib/db/schema";
import type * as schema from "@/lib/db/schema";
import {
  clipTokenIndexRows,
  matchesForLine,
  type ClipTokenIndexRow,
  type ClipTokenSearchHit,
} from "@/lib/experiments/clips/token-index";
import type { ClipDraft } from "@/lib/experiments/clips/types";

// Drizzle helpers for clip_token_index. No server-only import, so the
// backfill and supercut scripts can use the standalone client.

export type ClipTokenDb = PostgresJsDatabase<typeof schema>;

/** The insert/delete surface both `db` and a transaction share. */
export type ClipTokenWriter = Pick<ClipTokenDb, "delete" | "insert">;

export function isUndefinedTable(error: unknown, table: string): boolean {
  const err = error as { code?: string; message?: string };
  return err.code === "42P01" && (err.message ?? "").includes(table);
}

/** Drop a clip's token rows and insert whatever the current draft warrants. */
export async function replaceClipTokenIndex(db: ClipTokenWriter, draft: ClipDraft): Promise<number> {
  await db.delete(clipTokenIndex).where(eq(clipTokenIndex.clipId, draft.id));
  const rows = clipTokenIndexRows(draft);
  if (rows.length > 0) await db.insert(clipTokenIndex).values(rows);
  return rows.length;
}

export async function deleteClipTokenIndex(db: ClipTokenWriter, clipId: string): Promise<void> {
  await db.delete(clipTokenIndex).where(eq(clipTokenIndex.clipId, clipId));
}

export type ClipTokenSearchQuery = {
  word: string;
  /** Exact JLPT (5 = N5 … 1 = N1). Unrated clips never match. */
  level?: number | null;
  /** When true, only clips in the feed. */
  feed?: boolean;
  /** Default true: aligned, non-deprecated clips. */
  listed?: boolean;
  limit: number;
  cursor?: string | null;
};

export type ClipTokenSearchResult = {
  hits: ClipTokenSearchHit[];
  nextCursor: string | null;
};

export type ClipTokenSearchCursor = {
  clipId: string;
  lineIndex: number;
  charStart: number;
};

const CLIP_ID = /^[a-z0-9-]+$/;

export function encodeTokenSearchCursor(cursor: ClipTokenSearchCursor): string {
  return Buffer.from(`${cursor.clipId}\t${cursor.lineIndex}\t${cursor.charStart}`, "utf8").toString(
    "base64url"
  );
}

export function decodeTokenSearchCursor(cursor: string): ClipTokenSearchCursor | null {
  const text = Buffer.from(cursor, "base64url").toString("utf8");
  const parts = text.split("\t");
  if (parts.length !== 3) return null;
  const clipId = parts[0] ?? "";
  const lineIndex = Number(parts[1]);
  const charStart = Number(parts[2]);
  if (!CLIP_ID.test(clipId) || !Number.isInteger(lineIndex) || lineIndex < 0) return null;
  if (!Number.isInteger(charStart) || charStart < 0) return null;
  return { clipId, lineIndex, charStart };
}

function hitAfterCursor(hit: ClipTokenSearchHit, cursor: ClipTokenSearchCursor | null): boolean {
  if (!cursor) return true;
  if (hit.clipId > cursor.clipId) return true;
  if (hit.clipId < cursor.clipId) return false;
  if (hit.lineIndex > cursor.lineIndex) return true;
  if (hit.lineIndex < cursor.lineIndex) return false;
  return hit.charStart > cursor.charStart;
}

type LineKey = { clip_id: string; line_index: number };

/**
 * Exact surface search over concatenated token text within a line. Pages by
 * (clip id, line, character offset).
 */
export async function searchClipTokenIndex(
  db: ClipTokenDb,
  query: ClipTokenSearchQuery
): Promise<ClipTokenSearchResult> {
  const word = query.word;
  const limit = query.limit;
  const listed = query.listed !== false;
  const cursor = query.cursor ? decodeTokenSearchCursor(query.cursor) : null;
  if (query.cursor && !cursor) {
    throw new TokenSearchError("Bad cursor.", 400);
  }

  const hits: ClipTokenSearchHit[] = [];
  let lineAfter: { clipId: string; lineIndex: number } | null = cursor
    ? { clipId: cursor.clipId, lineIndex: cursor.lineIndex }
    : null;
  const batch = Math.max(limit, 20);

  while (hits.length <= limit) {
    const lines = await fetchMatchingLines(db, {
      word,
      listed,
      feed: query.feed === true,
      level: query.level ?? null,
      after: lineAfter,
      includeAfterLine: Boolean(cursor && hits.length === 0),
      limit: batch,
    });
    if (lines.length === 0) break;
    const lineHits = await hitsForLines(db, lines, word);
    for (const hit of lineHits) {
      if (hitAfterCursor(hit, cursor)) hits.push(hit);
    }
    const last = lines[lines.length - 1]!;
    if (lines.length < batch) break;
    lineAfter = { clipId: last.clip_id, lineIndex: last.line_index + 1 };
  }

  const page = hits.slice(0, limit);
  const nextCursor =
    hits.length > limit && page[page.length - 1]
      ? encodeTokenSearchCursor({
          clipId: page[page.length - 1]!.clipId,
          lineIndex: page[page.length - 1]!.lineIndex,
          charStart: page[page.length - 1]!.charStart,
        })
      : null;
  return { hits: page, nextCursor };
}

export class TokenSearchError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

async function fetchMatchingLines(
  db: ClipTokenDb,
  opts: {
    word: string;
    listed: boolean;
    feed: boolean;
    level: number | null;
    after: { clipId: string; lineIndex: number } | null;
    includeAfterLine: boolean;
    limit: number;
  }
): Promise<LineKey[]> {
  const filters = [
    opts.listed ? sql`listed = true` : sql`true`,
    opts.feed ? sql`AND in_feed = true` : sql``,
    opts.level !== null ? sql`AND jlpt_level = ${opts.level}` : sql``,
  ];
  let afterClause = sql``;
  if (opts.after) {
    const { clipId, lineIndex } = opts.after;
    afterClause = opts.includeAfterLine
      ? sql`AND (clip_id, line_index) >= (${clipId}, ${lineIndex})`
      : sql`AND (clip_id > ${clipId} OR (clip_id = ${clipId} AND line_index >= ${lineIndex}))`;
  }
  const rows = (await db.execute(sql`
    SELECT clip_id, line_index
    FROM clip_token_index
    WHERE ${sql.join(filters, sql` `)}
      ${afterClause}
    GROUP BY clip_id, line_index
    HAVING position(${opts.word} in string_agg(surface, '' ORDER BY token_index)) > 0
    ORDER BY clip_id, line_index
    LIMIT ${opts.limit}
  `)) as unknown as LineKey[];
  return rows;
}

async function hitsForLines(
  db: ClipTokenDb,
  lines: LineKey[],
  word: string
): Promise<ClipTokenSearchHit[]> {
  const clipIds = [...new Set(lines.map((l) => l.clip_id))];
  if (clipIds.length === 0) return [];
  const wanted = new Set(lines.map((l) => `${l.clip_id}\t${l.line_index}`));
  const tokenRows = await db
    .select()
    .from(clipTokenIndex)
    .where(inArray(clipTokenIndex.clipId, clipIds))
    .orderBy(asc(clipTokenIndex.clipId), asc(clipTokenIndex.lineIndex), asc(clipTokenIndex.tokenIndex));
  const grouped = new Map<string, ClipTokenIndexRow[]>();
  for (const row of tokenRows) {
    const key = `${row.clipId}\t${row.lineIndex}`;
    if (!wanted.has(key)) continue;
    const list = grouped.get(key) ?? [];
    list.push(row);
    grouped.set(key, list);
  }
  const hits: ClipTokenSearchHit[] = [];
  for (const line of lines) {
    const rows = grouped.get(`${line.clip_id}\t${line.line_index}`) ?? [];
    hits.push(...matchesForLine(rows, word));
  }
  return hits;
}
