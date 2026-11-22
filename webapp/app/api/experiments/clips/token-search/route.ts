import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { db } from "@/lib/db/client";
import { clipErrorResponse } from "@/lib/experiments/clips/route-helpers";
import {
  isUndefinedTable,
  searchClipTokenIndex,
  TokenSearchError,
} from "@/lib/experiments/clips/token-index-db";

const MAX_WORD = 80;
const MAX_LIMIT = 100;
const DEFAULT_LIMIT = 20;

/**
 * Exact surface search over clip tokens (Studio / agent). A query matches a
 * single token or concatenated adjacent tokens in a line (て + い + ます).
 *
 * `?word=` required. `?level=` exact JLPT (5 = N5 … 1 = N1). `?feed=1` keeps
 * feed clips only. `?limit=` (default 20, max 100) + `?cursor=` pages.
 *
 * Auth: same as the other /api/experiments/* routes (Studio session or
 * STUDIO_AGENT_TOKEN).
 */
export async function GET(request: NextRequest) {
  try {
    const params = request.nextUrl.searchParams;
    const word = (params.get("word") ?? "").trim();
    if (!word) {
      return NextResponse.json({ error: "word is required." }, { status: 400 });
    }
    if (word.length > MAX_WORD) {
      return NextResponse.json({ error: `word must be at most ${MAX_WORD} characters.` }, { status: 400 });
    }
    const levelParam = params.get("level");
    const level = levelParam === null ? null : Number(levelParam);
    if (level !== null && !(Number.isInteger(level) && level >= 1 && level <= 5)) {
      return NextResponse.json({ error: "level must be 1 (N1) to 5 (N5)." }, { status: 400 });
    }
    const limitParam = params.get("limit");
    const limit = limitParam === null ? DEFAULT_LIMIT : Number(limitParam);
    if (!(Number.isInteger(limit) && limit >= 1 && limit <= MAX_LIMIT)) {
      return NextResponse.json({ error: `limit must be 1 to ${MAX_LIMIT}.` }, { status: 400 });
    }
    const feed = ["1", "true"].includes(params.get("feed") ?? "");
    const listedParam = params.get("listed");
    const listed = listedParam === null ? true : ["1", "true"].includes(listedParam);
    const cursor = params.get("cursor");

    const result = await searchClipTokenIndex(db, {
      word,
      level,
      feed,
      listed,
      limit,
      cursor,
    });
    return NextResponse.json(result, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    if (error instanceof TokenSearchError) {
      return NextResponse.json({ error: error.message }, { status: error.status });
    }
    if (isUndefinedTable(error, "clip_token_index")) {
      return NextResponse.json(
        { error: "clip_token_index does not exist yet. Apply 0026_clip_token_index and run pnpm clip:index-backfill --write." },
        { status: 503 }
      );
    }
    return clipErrorResponse(error);
  }
}
