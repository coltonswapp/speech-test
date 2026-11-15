import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { splitSentencePhrases } from "./phrases";

/** Tokens for `words`, one after another, with a pause after the indexes in `pausesAfter`. */
function timed(words: string[], pausesAfter: number[] = []) {
  let t = 0;
  return words.map((text, i) => {
    const token = { text, startSec: t, endSec: t + 0.2 };
    t += pausesAfter.includes(i) ? 0.6 : 0.2;
    return token;
  });
}

function lines(text: string, words: string[], pausesAfter: number[] = []): string[] {
  return splitSentencePhrases(text, timed(words, pausesAfter)).map((p) => text.slice(p.charStart, p.charEnd));
}

describe("splitSentencePhrases", () => {
  it("leaves short sentences on one line", () => {
    assert.deepEqual(lines("今日は暑いですね。", ["今日", "は", "暑い", "です", "ね"]), ["今日は暑いですね。"]);
  });

  it("breaks after commas, keeping the comma on the left, and covers the whole text", () => {
    const text = "強力な竜巻が頻繁に発生する地域では、一瞬で家が壊れたり、建物の瓦礫に閉じ込められるそうです。";
    const words = ["強力な", "竜巻", "が", "頻繁に", "発生する", "地域", "では", "一瞬", "で", "家", "が", "壊れたり", "建物", "の", "瓦礫", "に", "閉じ込められる", "そう", "です"];
    const out = lines(text, words);
    assert.deepEqual(out, ["強力な竜巻が頻繁に発生する地域では、", "一瞬で家が壊れたり、", "建物の瓦礫に閉じ込められるそうです。"]);
    assert.equal(out.join(""), text);
  });

  it("does not break on a bare pause inside a clause", () => {
    const text = "毎日朝が来るのは、地球が自らの軸を回る自転をしているからだ。";
    const words = ["毎日", "朝", "が", "来る", "の", "は", "地球", "が", "自ら", "の", "軸", "を", "回る", "自転", "を", "している", "から", "だ"];
    assert.deepEqual(lines(text, words, [12]), ["毎日朝が来るのは、", "地球が自らの軸を回る自転をしているからだ。"]);
  });

  it("never breaks inside a quote or before a quotative particle", () => {
    const text = "お友達がもうノリで「え、日帰りだけど行っちゃう？」って言って来ました。";
    const words = ["お友達", "が", "もう", "ノリ", "で", "え", "日帰り", "だけど", "行っちゃう", "って", "言って", "来ました"];
    assert.deepEqual(lines(text, words, [8]), [text]);
  });

  it("does not treat として as a clause ending", () => {
    const text = "非常用のお金として使う現金とクレジットカードを包みます。";
    const words = ["非常用", "の", "お金", "として", "使う", "現金", "と", "クレジットカード", "を", "包みます"];
    assert.deepEqual(lines(text, words, [3]), [text]);
  });
});
