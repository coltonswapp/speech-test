import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { clauseChunks, mergeInflections } from "./fallback-tokens";

describe("clauseChunks", () => {
  it("cuts after punctuation, joins short clauses, and keeps every character", () => {
    const text =
      "ということで、今私たちは難波の近くに来まして、私が今回、この大阪旅行行くってなって、あ、そうだ！行きたかったんだ、ずっとって思い出した。";
    const chunks = clauseChunks(text);
    assert.equal(chunks.join(""), text);
    assert.ok(chunks.length > 1);
    for (const c of chunks) assert.ok(c.length <= 30, c);
    assert.equal(chunks[0], "ということで、今私たちは難波の近くに来まして、私が今回、");
  });

  it("keeps a line without punctuation whole", () => {
    assert.deepEqual(clauseChunks("今日はいい天気"), ["今日はいい天気"]);
  });
});

describe("mergeInflections", () => {
  const texts = (words: string[]) => mergeInflections(words.map((text) => ({ text }))).map((t) => t.text);

  it("joins polite endings and okurigana onto the word before", () => {
    assert.deepEqual(texts(["近く", "に", "来", "まして"]), ["近く", "に", "来まして"]);
    assert.deepEqual(texts(["どら焼", "き", "と"]), ["どら焼き", "と"]);
    assert.deepEqual(texts(["行き", "たか", "っ", "たん", "だ"]), ["行き", "たかっ", "たん", "だ"]);
  });

  it("leaves particles alone", () => {
    assert.deepEqual(texts(["大阪", "は", "旅行", "が", "好き"]), ["大阪", "は", "旅行", "が", "好き"]);
  });

  it("keeps readings only when both halves had one", () => {
    assert.deepEqual(mergeInflections([{ text: "来" }, { text: "まして", reading: "まして" }]), [{ text: "来まして" }]);
    assert.deepEqual(
      mergeInflections([{ text: "し", reading: "し" }, { text: "ます", reading: "ます" }]),
      [{ text: "します", reading: "します" }]
    );
  });
});
