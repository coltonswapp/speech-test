import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { validatedTokens } from "./japanese-segmentation";

describe("validatedTokens", () => {
  it("accepts Latin acronyms copied verbatim from the input (ATM)", () => {
    const text = "食べ物が、多いのと、ATMが、私のカードで使えます。";
    const surfaces = [
      "食べ物",
      "が",
      "、",
      "多い",
      "の",
      "と",
      "、",
      "ATM",
      "が",
      "、",
      "私",
      "の",
      "カード",
      "で",
      "使えます",
      "。",
    ];
    const tokens = validatedTokens(surfaces, text);
    assert.ok(tokens, "expected ATM line to validate");
    assert.equal(
      tokens!.map((t) => t.text).join(""),
      "食べ物が多いのとATMが私のカードで使えます"
    );
    assert.ok(tokens!.some((t) => t.text === "ATM"));
  });

  it("accepts a short ATM acknowledgement line", () => {
    const text = "あ、わかりました。ATM、大事ですね。";
    const surfaces = [
      "あ",
      "、",
      "わかりました",
      "。",
      "ATM",
      "、",
      "大事",
      "です",
      "ね",
      "。",
    ];
    const tokens = validatedTokens(surfaces, text);
    assert.ok(tokens);
    assert.ok(tokens!.some((t) => t.text === "ATM"));
  });

  it("rejects invented romaji that is not in the input", () => {
    const text = "わかりました。";
    const surfaces = ["wakarimashita", "。"];
    assert.equal(validatedTokens(surfaces, text), null);
  });

  it("still glues んですけど endings", () => {
    const text = "行きたいんですけど";
    const surfaces = ["行きたい", "ん", "です", "けど"];
    const tokens = validatedTokens(surfaces, text);
    assert.ok(tokens);
    assert.deepEqual(
      tokens!.map((t) => t.text),
      ["行きたい", "んですけど"]
    );
  });
});
