import assert from "node:assert/strict";

import { commonUses } from "./common_uses.js";

function parse(
  surface: string,
  result: { inThisSentence: string; otherUses: string[]; kanjiNote: string },
) {
  return commonUses.parseResult(JSON.stringify({ word: surface, ...result }), {
    surface,
    sentence: `${surface}。`,
    dictionaryGloss: undefined,
  });
}

const kanji = parse("物置", {
  inThisSentence: "A place for storing things.",
  otherUses: [
    "物置小屋 (ものおきごや) — a storage shed",
    "物置を整理する (ものおきをせいりする) — to organize a storage room",
    "to store things",
    "物置小屋 (mono-oki-goya) — a storage shed in romaji",
  ],
  kanjiNote: "物 (thing) + 置 (put) — a place to put things",
});
assert.equal(kanji.inThisSentence, "A place for storing things.");
assert.deepEqual(kanji.otherUses, [
  "物置小屋 (ものおきごや) — a storage shed",
  "物置を整理する (ものおきをせいりする) — to organize a storage room",
  "物置小屋 — a storage shed in romaji",
]);
assert.equal(kanji.kanjiNote, "物 (thing) + 置 (put) — a place to put things");
assert.equal(kanji.kanjiNote.includes("ものおき"), false);

const kana = parse("おはよう", {
  inThisSentence: "A morning greeting.",
  otherUses: [
    "おはようございます — good morning (polite)",
    "おはよう (おはよう) — morning",
    "おはようございます（おはようございます）— good morning",
  ],
  kanjiNote: "お (honorific) + 早 (early)",
});
assert.deepEqual(kana.otherUses, [
  "おはようございます — good morning (polite)",
  "おはよう — morning",
  "おはようございます — good morning",
]);
assert.equal(kana.kanjiNote, "", "kanjiNote stays empty when it names kanji the word does not have");

const fallback = parse("物置", {
  inThisSentence: "A closet.",
  otherUses: ["物置小屋 — a storage shed"],
  kanjiNote: "",
});
assert.deepEqual(fallback.otherUses, ["物置小屋 — a storage shed"]);

const prompt = commonUses.build({
  surface: "物置",
  sentence: "物置にしまう。",
  dictionaryGloss: undefined,
}).systemInstruction;
assert.match(prompt, /物置小屋 \(ものおきごや\) — a storage shed/);
assert.match(prompt, /If the Japanese is already all kana, do not add a reading/);
assert.match(prompt, /Empty string when it doesn't help\. No readings/);

console.log("common_uses selftest ok");
