import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { suggestedSelection } from "./selection";
import type { CatalogShowcaseItem } from "./types";

function item(
  expression: string,
  reading: string,
  kind: "compound" | "verb" = "compound"
): CatalogShowcaseItem {
  return { expression, reading, gloss: expression, kind };
}

describe("suggestedSelection", () => {
  it("prefers compounds with distinct readings", () => {
    const compounds = [
      item("日本", "にほん"),
      item("本日", "ほんじつ"),
      item("日曜", "にちよう"),
      item("毎日", "まいにち"),
    ];
    const picked = suggestedSelection(compounds, [], 3, 0);
    assert.equal(picked.length, 3);
    const readings = new Set(picked.map((row) => row.reading));
    assert.equal(readings.size, 3);
  });

  it("fills remaining slots even if readings repeat", () => {
    const compounds = [
      item("日本", "にほん"),
      item("日日", "にほん"),
      item("本日", "にほん"),
    ];
    const picked = suggestedSelection(compounds, [], 3, 0);
    assert.equal(picked.length, 3);
  });

  it("appends verbs after compounds", () => {
    const compounds = [item("入口", "いりぐち")];
    const verbs = [item("入る", "はいる", "verb")];
    const picked = suggestedSelection(compounds, verbs, 1, 1);
    assert.equal(picked[0].expression, "入口");
    assert.equal(picked[1].expression, "入る");
  });
});
