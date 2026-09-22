import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { romanize, readingLine } from "./romaji";

describe("romanize", () => {
  it("romanizes hiragana", () => {
    assert.equal(romanize("にほん"), "nihon");
    assert.equal(romanize("がっこう"), "gakkou");
    assert.equal(romanize("きょう"), "kyou");
  });

  it("romanizes katakana", () => {
    assert.equal(romanize("ニホン"), "nihon");
  });
});

describe("readingLine", () => {
  it("joins kana and romaji", () => {
    assert.equal(readingLine("にほん"), "にほん · nihon");
  });
});
