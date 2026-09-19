import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { normalizeReading, rawTokenSpans, readingsForSegments } from "./token-readings";

describe("normalizeReading", () => {
  it("accepts hiragana, katakana and long-vowel marks", () => {
    assert.equal(normalizeReading("さんまるに"), "さんまるに");
    assert.equal(normalizeReading("カイト"), "カイト");
    assert.equal(normalizeReading("はいー"), "はいー");
  });
  it("strips whitespace and punctuation, rejects non-kana", () => {
    assert.equal(normalizeReading(" さん まる に。"), "さんまるに");
    assert.equal(normalizeReading("302"), undefined);
    assert.equal(normalizeReading("三〇二"), undefined);
    assert.equal(normalizeReading("sanmaruni"), undefined);
    assert.equal(normalizeReading(""), undefined);
    assert.equal(normalizeReading(null), undefined);
  });
});

describe("readingsForSegments", () => {
  const text = "はい。302がどれか分からなくて。";
  const raw = rawTokenSpans(
    [
      { text: "はい", reading: "はい" },
      { text: "。", reading: "" },
      { text: "302", reading: "さんまるに" },
      { text: "が", reading: "が" },
      { text: "どれ", reading: "どれ" },
      { text: "か", reading: "か" },
      { text: "分からなくて", reading: "wakaranakute" },
      { text: "。" },
    ],
    text
  );

  it("maps one-to-one spans and drops invalid readings", () => {
    const segments = raw.filter((s) => s.text !== "。").map(({ text, start, end }) => ({ text, start, end }));
    assert.deepEqual(readingsForSegments(segments, raw), [
      "はい", "さんまるに", "が", "どれ", "か", undefined,
    ]);
  });

  it("concatenates readings across an exact merge of consecutive spans", () => {
    const t = "行きたいんですけど";
    const spans = rawTokenSpans(
      [
        { text: "行きたい", reading: "いきたい" },
        { text: "ん", reading: "ん" },
        { text: "です", reading: "です" },
        { text: "けど", reading: "けど" },
      ],
      t
    );
    const merged = [
      { text: "行きたい", start: 0, end: 4 },
      { text: "んですけど", start: 4, end: 9 },
    ];
    assert.deepEqual(readingsForSegments(merged, spans), ["いきたい", "んですけど"]);
  });

  it("gives no reading to a segment split out of a larger raw span", () => {
    const t = "え、いいん";
    const spans = rawTokenSpans([{ text: "え、いいん", reading: "えいいん" }], t);
    const split = [
      { text: "え", start: 0, end: 1 },
      { text: "いいん", start: 2, end: 5 },
    ];
    assert.deepEqual(readingsForSegments(split, spans), [undefined, undefined]);
  });
});
