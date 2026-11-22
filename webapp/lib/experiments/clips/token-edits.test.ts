import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  applyClipTokensEdit,
  applyClipTokenSwap,
  rewriteLineText,
} from "./token-edits";
import { clipTokenIndexRows } from "./token-index";
import { clipIsAligned, type ClipDraft, type ClipSentence, type ClipToken } from "./types";

function token(text: string, startSec: number, extra: Partial<ClipToken> = {}): ClipToken {
  return {
    text,
    reading: extra.reading ?? text,
    startSec,
    endSec: extra.endSec ?? startSec + 0.3,
    score: extra.score ?? 0.9,
    ...extra,
  };
}

function line(text: string, tokens: ClipToken[], extra: Partial<ClipSentence> = {}): ClipSentence {
  return { text, tokens, en: extra.en ?? `${text} (en)`, score: extra.score ?? 0.8, ...extra };
}

function draft(sentences: ClipSentence[], extra: Partial<ClipDraft> = {}): ClipDraft {
  return {
    id: "short-0kjnvmb9f0a",
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

const haunted = line("背後霊がいる。", [
  token("背後霊", 0.4, { reading: "はいきょうれい", endSec: 1.1 }),
  token("が", 1.1, { endSec: 1.2 }),
  token("いる", 1.2, { endSec: 1.6 }),
]);
const neighbour = line("大丈夫。", [token("大丈夫", 2.0, { reading: "だいじょうぶ", endSec: 2.5 })]);

describe("rewriteLineText", () => {
  it("replaces one surface and keeps punctuation", () => {
    assert.equal(
      rewriteLineText(
        "背後霊がいる。",
        [{ text: "背後霊" }, { text: "が" }, { text: "いる" }],
        [{ text: "守護霊" }, { text: "が" }, { text: "いる" }]
      ),
      "守護霊がいる。"
    );
  });
});

describe("applyClipTokenSwap", () => {
  it("keeps timings, alignment and the feed verdict for a same-count word swap", () => {
    const before = draft([haunted, neighbour]);
    const result = applyClipTokenSwap(before, {
      sentence: 0,
      token: 0,
      text: "守護霊",
      reading: "しゅごれい",
      english: "There's a guardian spirit.",
    });
    assert.equal("error" in result, false);
    if ("error" in result) return;
    assert.equal(result.keptTiming, true);
    const after = result.draft;
    assert.equal(after.sentences[0]!.text, "守護霊がいる。");
    assert.equal(after.sentences[0]!.en, "There's a guardian spirit.");
    const swapped = after.sentences[0]!.tokens![0]!;
    assert.equal(swapped.text, "守護霊");
    assert.equal(swapped.reading, "しゅごれい");
    assert.equal(swapped.startSec, 0.4);
    assert.equal(swapped.endSec, 1.1);
    assert.equal(swapped.score, 0.9);
    assert.equal(after.sentences[0]!.tokens![1]!.startSec, 1.1);
    assert.deepEqual(after.alignment, before.alignment);
    assert.deepEqual(after.feed, before.feed);
    assert.equal(clipIsAligned(after), true);
    assert.equal(after.sentences[1]!.text, neighbour.text);
  });

  it("rebuilds token-index rows with the new surface and the same clip times", () => {
    const before = draft([haunted]);
    const result = applyClipTokenSwap(before, {
      sentence: 0,
      token: 0,
      text: "守護霊",
      reading: "しゅごれい",
    });
    assert.equal("error" in result, false);
    if ("error" in result) return;
    const rows = clipTokenIndexRows(result.draft);
    assert.equal(rows.length, 3);
    assert.equal(rows[0]!.surface, "守護霊");
    assert.equal(rows[0]!.reading, "しゅごれい");
    assert.equal(rows[0]!.lineText, "守護霊がいる。");
    assert.equal(rows[0]!.clipStartSec, 0.4);
    assert.equal(rows[0]!.clipEndSec, 1.1);
    assert.equal(rows[0]!.startSec, 10.4);
  });
});

describe("applyClipTokensEdit", () => {
  it("drops only the edited line's times when the token count changes, and keeps feed", () => {
    const before = draft([haunted, neighbour]);
    const result = applyClipTokensEdit(before, {
      sentence: 0,
      tokens: [
        { text: "守", reading: "まも" },
        { text: "護", reading: "ご" },
        { text: "霊", reading: "れい" },
        { text: "が" },
        { text: "いる" },
      ],
      text: "守護霊がいる。",
    });
    assert.equal("error" in result, false);
    if ("error" in result) return;
    assert.equal(result.keptTiming, false);
    const edited = result.draft.sentences[0]!;
    assert.equal(edited.text, "守護霊がいる。");
    assert.equal(edited.tokens!.length, 5);
    assert.equal(edited.tokens!.every((t) => t.startSec === undefined), true);
    assert.equal(result.draft.sentences[1]!.tokens![0]!.startSec, 2.0);
    assert.deepEqual(result.draft.feed, before.feed);
    assert.deepEqual(result.draft.alignment, before.alignment);
    assert.equal(clipIsAligned(result.draft), false);
    assert.equal(clipTokenIndexRows(result.draft).every((row) => row.lineIndex === 1), true);
  });
});
