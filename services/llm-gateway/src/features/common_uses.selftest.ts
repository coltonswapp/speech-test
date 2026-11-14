import assert from "node:assert/strict";

import { commonUses } from "./common_uses.js";
import { mappedExampleTokens, parseOtherUse } from "./example_tokens.js";
import { validatedTokens } from "./token_mapping.js";

function parse(
  surface: string,
  result: { inThisSentence: string; otherUses: unknown[]; kanjiNote: string },
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
assert.equal(kanji.examples.length, 3);
assert.equal(kanji.examples[0]?.japanese, "物置小屋");
assert.equal(kanji.examples[0]?.reading, "ものおきごや");
assert.equal(kanji.examples[0]?.english, "a storage shed");
assert.deepEqual(kanji.examples[0]?.tokens, []);
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
assert.equal(fallback.examples[0]?.tokens.length, 0, "legacy string examples keep empty tokens");

const framed = parse("似合う", {
  inThisSentence: "This word is used to say that something looks good on someone.",
  otherUses: [],
  kanjiNote: "",
});
assert.equal(framed.inThisSentence, "Used to say that something looks good on someone.");

const alreadyDirect = parse("似合う", {
  inThisSentence: "Used to say something looks good on someone.",
  otherUses: [],
  kanjiNote: "",
});
assert.equal(alreadyDirect.inThisSentence, "Used to say something looks good on someone.");

const heard = parse("確かに", {
  inThisSentence: "Used to say something is definitely the case.",
  otherUses: [
    {
      japanese: "確かに聞いた",
      reading: "たしかにきいた",
      english: "I definitely heard it",
      tokens: [
        { surface: "確かに", lemma: "確かに", reading: "たしかに" },
        { surface: "聞いた", lemma: "聞く", reading: "きいた" },
      ],
    },
  ],
  kanjiNote: "",
});
assert.equal(heard.otherUses[0], "確かに聞いた (たしかにきいた) — I definitely heard it");
assert.equal(heard.examples[0]?.japanese, "確かに聞いた");
assert.deepEqual(
  heard.examples[0]?.tokens.map((token) => ({
    surface: token.surface,
    lemma: token.lemma,
    reading: token.reading,
    start: token.start,
    end: token.end,
  })),
  [
    { surface: "確かに", lemma: "確かに", reading: "たしかに", start: 0, end: 3 },
    { surface: "聞いた", lemma: "聞く", reading: "きいた", start: 3, end: 6 },
  ],
);
assert.equal("確かに聞いた".slice(3, 6), "聞いた");
assert.equal(heard.examples[0]?.tokens[1]?.lemma, "聞く");
assert.equal(heard.examples[0]?.tokens[1]?.surface, "聞いた");

const punctuated = parse("聞く", {
  inThisSentence: "Used to talk about hearing something.",
  otherUses: [
    {
      japanese: "え、図書館で聞いた。",
      reading: "え、としょかんできいた。",
      english: "Huh, I heard it at the library.",
      tokens: [
        { surface: "え", lemma: "え", reading: "え" },
        { surface: "、", lemma: "、", reading: "" },
        { surface: "図書館", lemma: "図書館", reading: "としょかん" },
        { surface: "で", lemma: "で", reading: "で" },
        { surface: "聞いた", lemma: "聞く", reading: "きいた" },
        { surface: "。", lemma: "。", reading: "" },
      ],
    },
  ],
  kanjiNote: "",
});
const punctTokens = punctuated.examples[0]?.tokens ?? [];
assert.deepEqual(
  punctTokens.map((token) => token.surface),
  ["え", "図書館", "で", "聞いた"],
);
assert.equal(punctTokens.find((token) => token.surface === "図書館")?.lemma, "図書館");
assert.equal(punctTokens.find((token) => token.surface === "聞いた")?.lemma, "聞く");
assert.equal("え、図書館で聞いた。".slice(punctTokens[1]!.start, punctTokens[1]!.end), "図書館");
assert.equal("え、図書館で聞いた。".slice(punctTokens[3]!.start, punctTokens[3]!.end), "聞いた");

const unmapped = parse("聞く", {
  inThisSentence: "Used to talk about hearing something.",
  otherUses: [
    {
      japanese: "確かに聞いた",
      reading: "たしかにきいた",
      english: "I definitely heard it",
      tokens: [
        { surface: "tashika", lemma: "確か", reading: "たしか" },
        { surface: "ni kiita", lemma: "聞く", reading: "きいた" },
      ],
    },
  ],
  kanjiNote: "",
});
assert.equal(unmapped.examples[0]?.japanese, "確かに聞いた");
assert.deepEqual(unmapped.examples[0]?.tokens, [], "invented romaji surfaces are dropped, example kept");

const prompt = commonUses.build({
  surface: "物置",
  sentence: "物置にしまう。",
  dictionaryGloss: undefined,
}).systemInstruction;
assert.match(prompt, /Empty string when japanese is already all kana/);
assert.match(prompt, /Particles are read as pronounced, not as spelled/);
assert.match(prompt, /こんにちは → こんにちわ/);
assert.match(prompt, /Empty string when it doesn't help\. No readings/);
assert.match(prompt, /Used to say/);
assert.match(prompt, /Do not start with "This word is used"/);
assert.match(prompt, /聞いた → 聞く/);
assert.match(prompt, /Keep conjugated verbs as one token/);

const mappedHeard = validatedTokens(["確かに", "聞いた"], "確かに聞いた");
assert.ok(mappedHeard);
assert.deepEqual(
  mappedHeard.map((token) => ({ text: token.text, start: token.start, end: token.end })),
  [
    { text: "確かに", start: 0, end: 3 },
    { text: "聞いた", start: 3, end: 6 },
  ],
);

const mappedPunct = validatedTokens(
  ["え", "、", "図書館", "で", "聞いた", "。"],
  "え、図書館で聞いた。",
);
assert.ok(mappedPunct);
assert.deepEqual(
  mappedPunct.map((token) => token.text),
  ["え", "図書館", "で", "聞いた"],
);
assert.equal("え、図書館で聞いた。".slice(mappedPunct[1]!.start, mappedPunct[1]!.end), "図書館");

const lemmaTokens = mappedExampleTokens(
  [
    { surface: "確かに", lemma: "確かに", reading: "たしかに" },
    { surface: "聞いた", lemma: "聞く", reading: "きいた" },
  ],
  "確かに聞いた",
);
assert.equal(lemmaTokens[1]?.surface, "聞いた");
assert.equal(lemmaTokens[1]?.lemma, "聞く");

const legacyParsed = parseOtherUse("確かに聞いた (たしかにきいた) — I definitely heard it");
assert.equal(legacyParsed?.example.japanese, "確かに聞いた");
assert.deepEqual(legacyParsed?.example.tokens, []);
assert.equal(legacyParsed?.display, "確かに聞いた (たしかにきいた) — I definitely heard it");

console.log("common_uses selftest ok");
