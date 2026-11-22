import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  decodeTokenSearchCursor,
  encodeTokenSearchCursor,
  isUndefinedTable,
} from "./token-index-db";
import {
  clipTokenIndexRows,
  clipTokenIndexSkip,
  findSurfaceMatches,
  matchTokens,
  memoryClipTokenIndex,
  tokenVideoSec,
} from "./token-index";
import type { ClipDraft, ClipSentence, ClipToken } from "./types";

function token(text: string, startSec: number, extra: Partial<ClipToken> = {}): ClipToken {
  return { text, startSec, endSec: extra.endSec ?? startSec + 0.2, ...extra };
}

function line(text: string, tokens: ClipToken[] | null, extra: Partial<ClipSentence> = {}): ClipSentence {
  return { text, tokens, ...extra };
}

function draft(sentences: ClipSentence[], extra: Partial<ClipDraft> = {}): ClipDraft {
  return {
    id: "short-test",
    videoId: "abcdefghijk",
    startSec: 10,
    endSec: 40,
    durationSec: 30,
    shiftSec: 0,
    sentences,
    alignment: { alignerVersion: "test-aligner", at: "2026-01-01T00:00:00.000Z" },
    createdAt: "2026-01-01T00:00:00.000Z",
    updatedAt: "2026-01-01T00:00:00.000Z",
    ...extra,
  };
}

describe("findSurfaceMatches", () => {
  const clock = { startSec: 10, shiftSec: 0 };

  it("matches a word split across adjacent tokens (て/い/ます)", () => {
    const tokens = matchTokens(
      [token("し", 0), token("て", 0.2), token("い", 0.4), token("ます", 0.6, { endSec: 1 })],
      clock
    );
    const hits = findSurfaceMatches(tokens, "ています");
    assert.equal(hits.length, 1);
    assert.equal(hits[0]!.matchedText, "ています");
    assert.equal(hits[0]!.tokenStart, 1);
    assert.equal(hits[0]!.tokenEnd, 3);
    assert.equal(hits[0]!.startSec, 10.2);
    assert.equal(hits[0]!.endSec, 11);
    assert.equal(hits[0]!.clipStartSec, 0.2);
    assert.equal(hits[0]!.clipEndSec, 1);
  });

  it("matches a suffix inside a single token (ちゃう in 行っちゃう)", () => {
    const tokens = matchTokens([token("行っちゃう", 1, { endSec: 1.8 }), token("？", 1.8, { endSec: 2 })], clock);
    const hits = findSurfaceMatches(tokens, "ちゃう");
    assert.equal(hits.length, 1);
    assert.equal(hits[0]!.tokenStart, 0);
    assert.equal(hits[0]!.tokenEnd, 0);
    assert.equal(hits[0]!.startSec, 11);
    assert.equal(hits[0]!.endSec, 11.8);
  });

  it("matches される as one token or as さ + れる", () => {
    const one = findSurfaceMatches(matchTokens([token("される", 0, { endSec: 0.5 })], clock), "される");
    assert.equal(one.length, 1);
    assert.deepEqual([one[0]!.tokenStart, one[0]!.tokenEnd], [0, 0]);

    const split = findSurfaceMatches(
      matchTokens([token("さ", 0), token("れる", 0.2, { endSec: 0.5 })], clock),
      "される"
    );
    assert.equal(split.length, 1);
    assert.deepEqual([split[0]!.tokenStart, split[0]!.tokenEnd], [0, 1]);
  });

  it("returns every non-overlapping occurrence in a line", () => {
    const tokens = matchTokens(
      [token("ちゃう", 0), token("ちゃう", 0.4, { endSec: 0.7 })],
      clock
    );
    const hits = findSurfaceMatches(tokens, "ちゃう");
    assert.equal(
      hits.length,
      2,
      JSON.stringify({ tokenCount: tokens.length, texts: tokens.map((t) => t.text), hits })
    );
    assert.equal(hits[0]!.charStart, 0);
    assert.equal(hits[1]!.charStart, 3);
  });

  it("does not match a different ending or a reading-only needle", () => {
    const tokens = matchTokens([token("しています", 0, { endSec: 1, reading: "しています" })], clock);
    assert.equal(findSurfaceMatches(tokens, "てる").length, 0);
    assert.equal(findSurfaceMatches(tokens, "").length, 0);
  });

  it("applies clip start and onset shift when converting to video seconds", () => {
    assert.equal(tokenVideoSec({ startSec: 12.5, shiftSec: -0.065 }, 1.2), 13.635);
    const hits = findSurfaceMatches(
      matchTokens([token("ちゃう", 1, { endSec: 1.4 })], { startSec: 12.5, shiftSec: -0.065 }),
      "ちゃう"
    );
    assert.equal(hits[0]!.startSec, 13.435);
    assert.equal(hits[0]!.endSec, 13.835);
  });
});

describe("clip token index rebuild and delete", () => {
  const timed = draft([
    line("しています", [token("し", 0), token("て", 0.2), token("い", 0.4), token("ます", 0.6, { endSec: 1 })]),
    line("行っちゃう", [token("行っちゃう", 1.2, { endSec: 2 })]),
  ]);

  it("emits one row per timed token, with video seconds and listed/in-feed from the clip", () => {
    const rows = clipTokenIndexRows(timed);
    assert.equal(rows.length, 5);
    assert.equal(rows[1]!.surface, "て");
    assert.equal(rows[1]!.lineIndex, 0);
    assert.equal(rows[1]!.tokenIndex, 1);
    assert.equal(rows[1]!.startSec, 10.2);
    assert.equal(rows[1]!.clipStartSec, 0.2);
    assert.equal(rows[1]!.lineText, "しています");
    assert.equal(rows[4]!.lineIndex, 1);
    assert.equal(rows[4]!.listed, true);
    assert.equal(clipTokenIndexSkip(timed), null);
  });

  it("skips clips with no tokens, and clips whose tokens have no times", () => {
    const empty = draft([line("こんにちは", null)]);
    assert.equal(clipTokenIndexSkip(empty), "no_tokens");
    assert.deepEqual(clipTokenIndexRows(empty), []);

    const untimed = draft([
      line("しています", [{ text: "し" }, { text: "て" }, { text: "い" }, { text: "ます" }]),
    ]);
    assert.equal(clipTokenIndexSkip(untimed), "no_alignment");
    assert.deepEqual(clipTokenIndexRows(untimed), []);
  });

  it("indexes only timed lines when some lines have lost their alignment", () => {
    const mixed = draft([
      line("しています", [token("し", 0), token("て", 0.2), token("い", 0.4), token("ます", 0.6, { endSec: 1 })]),
      line("行っちゃう", [{ text: "行っちゃう" }]),
    ]);
    const rows = clipTokenIndexRows(mixed);
    assert.equal(rows.length, 4);
    assert.ok(rows.every((r) => r.lineIndex === 0));
    assert.equal(clipTokenIndexSkip(mixed), null);
  });

  it("rebuild replaces a clip's rows and delete drops them", () => {
    const index = memoryClipTokenIndex();
    index.upsert(timed);
    assert.equal(index.rows("short-test").length, 5);
    assert.equal(index.all().length, 5);

    const retokenized = draft([
      line("してます", [token("し", 0), token("てます", 0.2, { endSec: 0.8 })]),
    ]);
    index.upsert(retokenized);
    const rebuilt = index.rows("short-test");
    assert.equal(rebuilt.length, 2);
    assert.deepEqual(
      rebuilt.map((r) => r.surface),
      ["し", "てます"]
    );
    assert.ok(rebuilt.every((r) => r.clipId === "short-test"));

    const other = draft([line("される", [token("される", 0, { endSec: 0.4 })])], { id: "other-clip" });
    index.upsert(other);
    assert.equal(index.all().length, 3);

    index.delete("short-test");
    assert.deepEqual(index.rows("short-test"), []);
    assert.equal(index.rows("other-clip").length, 1);
    assert.equal(index.all().length, 1);

    index.delete("other-clip");
    assert.deepEqual(index.all(), []);
  });
});

describe("token search cursor", () => {
  it("round-trips clip id, line, and character offset", () => {
    const cursor = { clipId: "short-test", lineIndex: 2, charStart: 4 };
    assert.deepEqual(decodeTokenSearchCursor(encodeTokenSearchCursor(cursor)), cursor);
    assert.equal(decodeTokenSearchCursor("not-a-cursor"), null);
  });
});

describe("isUndefinedTable", () => {
  it("matches Postgres 42P01 for clip_token_index", () => {
    assert.equal(
      isUndefinedTable(
        { code: "42P01", message: `relation "clip_token_index" does not exist` },
        "clip_token_index"
      ),
      true
    );
    assert.equal(isUndefinedTable({ code: "23505", message: "duplicate" }, "clip_token_index"), false);
  });
});
