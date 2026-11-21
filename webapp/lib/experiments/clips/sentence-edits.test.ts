import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { applyClipMerge, applyClipSplit } from "./sentence-edits";
import { applySentenceEdits, type ClipDraft, type ClipSentence, type ClipToken } from "./types";

function token(text: string, startSec: number, extra: Partial<ClipToken> = {}): ClipToken {
  return {
    text,
    reading: extra.reading ?? text,
    startSec,
    endSec: extra.endSec ?? startSec + 0.2,
    score: extra.score ?? 0.9,
    ...extra,
  };
}

function line(text: string, tokens: ClipToken[], extra: Partial<ClipSentence> = {}): ClipSentence {
  return { text, tokens, en: extra.en ?? `${text} (en)`, score: extra.score ?? 0.8, ...extra };
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
    feed: {
      auto: { eligible: true, reason: "worth watching", model: "test", at: "2026-01-01T00:00:00.000Z" },
    },
    createdAt: "2026-01-01T00:00:00.000Z",
    updatedAt: "2026-01-01T00:00:00.000Z",
    ...extra,
  };
}

const longText = "まずは、これを見てください。";
const longTokens = [
  token("まずは", 0.5, { reading: "まずは", endSec: 0.7 }),
  token("これ", 1.2, { reading: "これ", endSec: 1.5 }),
  token("を", 1.5, { reading: "を", endSec: 1.7 }),
  token("見て", 1.7, { reading: "みて", endSec: 2.1 }),
  token("ください", 2.1, { reading: "ください", endSec: 2.3 }),
];
const neighbour = line("今日は暑いです。", [
  token("今日", 3.0, { reading: "きょう" }),
  token("は", 3.3),
  token("暑い", 3.5, { reading: "あつい" }),
  token("です", 3.8),
]);

describe("applySentenceEdits (transcript rewrite)", () => {
  it("drops tokens on a split line and timings on every line, including neighbours", () => {
    const before = draft([
      line(longText, longTokens, { en: "First, look at this." }),
      neighbour,
    ]);
    const after = applySentenceEdits(before, ["まずは、", "これを見てください。", neighbour.text]);

    assert.equal(after.length, 3);
    assert.equal(after[0]!.tokens, null);
    assert.equal(after[1]!.tokens, null);
    // Index shift makes the unchanged neighbour look new, so its tokens go too.
    assert.equal(after[2]!.tokens, null);
    assert.equal(after[0]!.en, undefined);
    assert.equal(after.every((s) => (s.tokens ?? []).every((t) => t.startSec === undefined)), true);
  });

  it("strips timings from an unchanged line even when only another line's text changes", () => {
    const before = draft([neighbour, line(longText, longTokens)]);
    const after = applySentenceEdits(before, [neighbour.text, "まずはこれを見てください。"]);
    assert.equal(after[0]!.text, neighbour.text);
    assert.ok(after[0]!.tokens);
    assert.equal(after[0]!.tokens!.every((t) => t.startSec === undefined && t.endSec === undefined), true);
    assert.equal(after[1]!.tokens, null);
  });
});

describe("applyClipSplit", () => {
  it("keeps every token's text, reading and timing, and leaves alignment, feed and neighbours alone", () => {
    const untouched = neighbour;
    const before = draft([line(longText, longTokens, { en: "First, look at this.", flagsCleared: true }), untouched], {
      highlights: {
        grammarPatterns: [
          { label: "まずは", sourceSpokenStart: 0, sourceSpokenEnd: 0 },
          { label: "今日は", sourceSpokenStart: 1 },
        ],
      },
    });
    const result = applyClipSplit(before, {
      sentence: 0,
      atToken: 1,
      english: ["First of all,", "Look at this."],
    });
    assert.ok(!("error" in result), "error" in result ? result.error : "");
    const { draft: after } = result;

    assert.equal(after.alignment, before.alignment);
    assert.equal(after.feed, before.feed);
    assert.equal(after.sentences[2], untouched);
    assert.equal(after.sentences.length, 3);

    assert.equal(after.sentences.map((s) => s.text).join(""), `${longText}${neighbour.text}`);
    assert.equal(after.sentences[0]!.text, "まずは、");
    assert.equal(after.sentences[1]!.text, "これを見てください。");
    assert.deepEqual(
      after.sentences[0]!.tokens,
      [longTokens[0]],
    );
    assert.deepEqual(after.sentences[1]!.tokens, longTokens.slice(1));
    assert.equal(after.sentences[0]!.en, "First of all,");
    assert.equal(after.sentences[1]!.en, "Look at this.");
    assert.equal(after.sentences[0]!.flagsCleared, true);
    assert.equal(after.sentences[1]!.flagsCleared, true);

    // Payload (and the app) take a line's start/end from its first and last token.
    assert.equal(after.sentences[0]!.tokens![0]!.startSec, 0.5);
    assert.equal(after.sentences[0]!.tokens!.at(-1)!.endSec, 0.7);
    assert.equal(after.sentences[1]!.tokens![0]!.startSec, 1.2);
    assert.equal(after.sentences[1]!.tokens!.at(-1)!.endSec, 2.3);

    assert.deepEqual(after.highlights?.grammarPatterns, [
      { label: "まずは", sourceSpokenStart: 0, sourceSpokenEnd: 1 },
      { label: "今日は", sourceSpokenStart: 2 },
    ]);
  });

  it("splits at several token boundaries and leaves English empty when omitted", () => {
    const before = draft([line(longText, longTokens, { en: "First, look at this." })]);
    const result = applyClipSplit(before, { sentence: 0, atToken: [1, 3] });
    assert.ok(!("error" in result), "error" in result ? result.error : "");
    const texts = result.draft.sentences.map((s) => s.text);
    assert.deepEqual(texts, ["まずは、", "これを", "見てください。"]);
    assert.equal(texts.join(""), longText);
    assert.equal(result.draft.sentences.every((s) => s.en === undefined), true);
    assert.equal(result.draft.sentences.flatMap((s) => s.tokens ?? []).length, longTokens.length);
  });

  it("drops spaces at the cut so pieces are stored trimmed", () => {
    const text = "まずは、 これを見て";
    const tokens = [token("まずは", 0.5), token("これ", 1.2), token("を", 1.5), token("見て", 1.7)];
    const result = applyClipSplit(draft([line(text, tokens)]), { sentence: 0, atToken: 1 });
    assert.ok(!("error" in result), "error" in result ? result.error : "");
    assert.deepEqual(result.draft.sentences.map((s) => s.text), ["まずは、", "これを見て"]);
  });

  it("starts the next line with an opening bracket instead of leaving it dangling", () => {
    const text = "彼は「行こう」と言った";
    const tokens = [token("彼", 0), token("は", 0.2), token("行こう", 0.5), token("と", 1), token("言った", 1.2)];
    const result = applyClipSplit(draft([line(text, tokens)]), { sentence: 0, atToken: 2 });
    assert.ok(!("error" in result), "error" in result ? result.error : "");
    assert.deepEqual(result.draft.sentences.map((s) => s.text), ["彼は", "「行こう」と言った"]);
    // Closing punctuation still stays on the left.
    const atTo = applyClipSplit(draft([line(text, tokens)]), { sentence: 0, atToken: 3 });
    assert.ok(!("error" in atTo), "error" in atTo ? atTo.error : "");
    assert.deepEqual(atTo.draft.sentences.map((s) => s.text), ["彼は「行こう」", "と言った"]);
  });

  it("rejects a split that would drop tokens or miss a boundary", () => {
    const before = draft([line(longText, longTokens), neighbour]);
    assert.equal("error" in applyClipSplit(before, { sentence: 0, atToken: 0 }), true);
    assert.equal("error" in applyClipSplit(before, { sentence: 0, atToken: 5 }), true);
    assert.equal("error" in applyClipSplit(before, { sentence: 9, atToken: 1 }), true);
    assert.equal("error" in applyClipSplit(before, { sentence: 0, atToken: 1, english: ["only one"] }), true);
    const untokenized = draft([{ text: longText, tokens: null }]);
    assert.equal("error" in applyClipSplit(untokenized, { sentence: 0, atToken: 1 }), true);
  });
});

describe("applyClipMerge", () => {
  it("is the reverse of a split: tokens, timings, alignment and the neighbour stay", () => {
    const untouched = neighbour;
    const split = applyClipSplit(draft([line(longText, longTokens, { en: "First, look at this." }), untouched]), {
      sentence: 0,
      atToken: 1,
      english: ["First of all,", "Look at this."],
    });
    assert.ok(!("error" in split));
    const merged = applyClipMerge(split.draft, { sentence: 0, english: "First, look at this." });
    assert.ok(!("error" in merged), "error" in merged ? merged.error : "");
    assert.equal(merged.draft.alignment, split.draft.alignment);
    assert.equal(merged.draft.feed, split.draft.feed);
    assert.equal(merged.draft.sentences[1], untouched);
    assert.equal(merged.draft.sentences[0]!.text, longText);
    assert.deepEqual(merged.draft.sentences[0]!.tokens, longTokens);
    assert.equal(merged.draft.sentences[0]!.en, "First, look at this.");
  });

  it("joins existing English when none is given, and remaps later highlight indices", () => {
    const before = draft(
      [
        line("まずは、", [longTokens[0]!], { en: "First of all," }),
        line("これを見てください。", longTokens.slice(1), { en: "Look at this." }),
        neighbour,
      ],
      {
        highlights: { grammarPatterns: [{ label: "暑い", sourceSpokenStart: 2 }] },
      }
    );
    const result = applyClipMerge(before, { sentence: 0 });
    assert.ok(!("error" in result), "error" in result ? result.error : "");
    assert.equal(result.draft.sentences[0]!.en, "First of all, Look at this.");
    assert.equal(result.draft.sentences[1], neighbour);
    assert.equal(result.draft.highlights?.grammarPatterns?.[0]?.sourceSpokenStart, 1);
  });

  it("keeps existing English when some merged lines have none", () => {
    const before = draft([
      line("まずは、", [longTokens[0]!], { en: "First of all," }),
      { ...line("これを見てください。", longTokens.slice(1)), en: undefined },
    ]);
    const result = applyClipMerge(before, { sentence: 0 });
    assert.ok(!("error" in result), "error" in result ? result.error : "");
    assert.equal(result.draft.sentences[0]!.en, "First of all,");
  });
});
