import { clipIndexRow } from "@/lib/experiments/clips/summary";
import {
  sentenceIsTimed,
  type ClipDraft,
  type ClipToken,
} from "@/lib/experiments/clips/types";

// One row per timed token per clip line (`clip_token_index` in schema.ts).
// No server-only imports: scripts/clip-index-backfill.ts and the tests use it.
// v1 matches exact surface text, including a query that spans adjacent tokens
// in a line (て + い + ます → ています). lemma / grammar_tags stay null.

const round3 = (n: number) => Math.round(n * 1000) / 1000;

/** Video-timeline seconds: same formula as buildClipPayload. */
export function tokenVideoSec(draft: Pick<ClipDraft, "startSec" | "shiftSec">, clipSeconds: number): number {
  return round3(Math.max(0, draft.startSec + clipSeconds + draft.shiftSec));
}

export type ClipTokenIndexRow = {
  clipId: string;
  videoId: string;
  lineIndex: number;
  lineText: string;
  tokenIndex: number;
  surface: string;
  reading: string | null;
  startSec: number;
  endSec: number;
  clipStartSec: number;
  clipEndSec: number;
  listed: boolean;
  inFeed: boolean;
  jlptLevel: number | null;
  lemma: string | null;
  grammarTags: string[] | null;
};

export type ClipTokenIndexSkip = "no_tokens" | "no_alignment";

export type ClipTokenMatch = {
  /** Index of the first covering token (inclusive). */
  tokenStart: number;
  /** Index of the last covering token (inclusive). */
  tokenEnd: number;
  /** Character offset of the query in the concatenated token surfaces. */
  charStart: number;
  matchedText: string;
  startSec: number;
  endSec: number;
  clipStartSec: number;
  clipEndSec: number;
};

export type ClipTokenSearchHit = {
  clipId: string;
  videoId: string;
  lineIndex: number;
  lineText: string;
  matchedText: string;
  startSec: number;
  endSec: number;
  clipStartSec: number;
  clipEndSec: number;
  tokenStart: number;
  tokenEnd: number;
  charStart: number;
};

/**
 * Same as the table in lib/db/schema.ts. The backfill script runs it so the
 * table exists without a drizzle-kit push of the whole schema.
 */
export const CLIP_TOKEN_INDEX_DDL = `
CREATE TABLE IF NOT EXISTS clip_token_index (
  clip_id text NOT NULL,
  video_id text NOT NULL,
  line_index integer NOT NULL,
  line_text text NOT NULL,
  token_index integer NOT NULL,
  surface text NOT NULL,
  reading text,
  start_sec real NOT NULL,
  end_sec real NOT NULL,
  clip_start_sec real NOT NULL,
  clip_end_sec real NOT NULL,
  listed boolean NOT NULL,
  in_feed boolean NOT NULL,
  jlpt_level integer,
  lemma text,
  grammar_tags text[],
  PRIMARY KEY (clip_id, line_index, token_index)
);
CREATE INDEX IF NOT EXISTS clip_token_index_surface_idx ON clip_token_index (surface);
CREATE INDEX IF NOT EXISTS clip_token_index_reading_idx ON clip_token_index (reading);
CREATE INDEX IF NOT EXISTS clip_token_index_listed_idx ON clip_token_index (listed, in_feed, jlpt_level);
CREATE INDEX IF NOT EXISTS clip_token_index_clip_idx ON clip_token_index (clip_id);
`;

function hasAnyTokens(draft: ClipDraft): boolean {
  return draft.sentences.some((s) => (s.tokens?.length ?? 0) > 0);
}

/**
 * Why a clip contributes no token rows. null means at least one timed line
 * will be indexed (other lines on the same clip may still be skipped).
 */
export function clipTokenIndexSkip(draft: ClipDraft): ClipTokenIndexSkip | null {
  if (!hasAnyTokens(draft)) return "no_tokens";
  if (clipTokenIndexRows(draft).length === 0) return "no_alignment";
  return null;
}

/** Timed tokens only; untimed lines (and empty transcripts) are omitted. */
export function clipTokenIndexRows(draft: ClipDraft): ClipTokenIndexRow[] {
  const index = clipIndexRow(draft);
  const rows: ClipTokenIndexRow[] = [];
  draft.sentences.forEach((sentence, lineIndex) => {
    const tokens = sentence.tokens;
    if (!tokens || tokens.length === 0 || !sentenceIsTimed(sentence)) return;
    tokens.forEach((token, tokenIndex) => {
      rows.push({
        clipId: draft.id,
        videoId: draft.videoId,
        lineIndex,
        lineText: sentence.text,
        tokenIndex,
        surface: token.text,
        reading: token.reading ?? null,
        startSec: tokenVideoSec(draft, token.startSec ?? 0),
        endSec: tokenVideoSec(draft, token.endSec ?? 0),
        clipStartSec: round3(token.startSec ?? 0),
        clipEndSec: round3(token.endSec ?? 0),
        listed: index.listed,
        inFeed: index.inFeed,
        jlptLevel: index.jlptLevel,
        lemma: null,
        grammarTags: null,
      });
    });
  });
  return rows;
}

type MatchToken = {
  text: string;
  startSec: number;
  endSec: number;
  clipStartSec: number;
  clipEndSec: number;
};

/**
 * Non-overlapping exact matches of `word` in the concatenated token surfaces
 * of one line. A hit may cover one token (`ちゃう` inside `行っちゃう`) or
 * several adjacent ones (`て` + `い` + `ます`).
 */
export function findSurfaceMatches(tokens: MatchToken[], word: string): ClipTokenMatch[] {
  if (!word || tokens.length === 0) return [];
  const concat = tokens.map((t) => t.text).join("");
  const hits: ClipTokenMatch[] = [];
  let from = 0;
  while (from <= concat.length - word.length) {
    const at = concat.indexOf(word, from);
    if (at < 0) break;
    const end = at + word.length;
    let char = 0;
    let tokenStart = -1;
    let tokenEnd = -1;
    for (let i = 0; i < tokens.length; i++) {
      const next = char + tokens[i]!.text.length;
      if (tokenStart < 0 && at < next) tokenStart = i;
      if (end > char) tokenEnd = i;
      if (tokenStart >= 0 && end <= next) break;
      char = next;
    }
    if (tokenStart < 0 || tokenEnd < 0) break;
    const first = tokens[tokenStart]!;
    const last = tokens[tokenEnd]!;
    hits.push({
      tokenStart,
      tokenEnd,
      charStart: at,
      matchedText: word,
      startSec: first.startSec,
      endSec: last.endSec,
      clipStartSec: first.clipStartSec,
      clipEndSec: last.clipEndSec,
    });
    from = end;
  }
  return hits;
}

export function matchesForLine(rows: ClipTokenIndexRow[], word: string): ClipTokenSearchHit[] {
  if (rows.length === 0) return [];
  const first = rows[0]!;
  const matches = findSurfaceMatches(
    rows.map((r) => ({
      text: r.surface,
      startSec: r.startSec,
      endSec: r.endSec,
      clipStartSec: r.clipStartSec,
      clipEndSec: r.clipEndSec,
    })),
    word
  );
  return matches.map((m) => ({
    clipId: first.clipId,
    videoId: first.videoId,
    lineIndex: first.lineIndex,
    lineText: first.lineText,
    matchedText: m.matchedText,
    startSec: m.startSec,
    endSec: m.endSec,
    clipStartSec: m.clipStartSec,
    clipEndSec: m.clipEndSec,
    tokenStart: m.tokenStart,
    tokenEnd: m.tokenEnd,
    charStart: m.charStart,
  }));
}

/** In-memory stand-in for replace/delete on `clip_token_index`. */
export function memoryClipTokenIndex() {
  const byClip = new Map<string, ClipTokenIndexRow[]>();
  return {
    upsert(draft: ClipDraft) {
      byClip.set(draft.id, clipTokenIndexRows(draft));
    },
    delete(id: string) {
      byClip.delete(id);
    },
    rows(id: string): ClipTokenIndexRow[] {
      return byClip.get(id) ?? [];
    },
    all(): ClipTokenIndexRow[] {
      return [...byClip.values()].flat();
    },
  };
}

/** Timed tokens as MatchToken, for tests that don't build full index rows. */
export function matchTokens(tokens: ClipToken[], draft: Pick<ClipDraft, "startSec" | "shiftSec">): MatchToken[] {
  return tokens.map((t) => ({
    text: t.text,
    startSec: tokenVideoSec(draft, t.startSec ?? 0),
    endSec: tokenVideoSec(draft, t.endSec ?? 0),
    clipStartSec: round3(t.startSec ?? 0),
    clipEndSec: round3(t.endSec ?? 0),
  }));
}
