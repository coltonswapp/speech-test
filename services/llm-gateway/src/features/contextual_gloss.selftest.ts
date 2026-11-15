/**
 * Deterministic checks for the contextual_gloss prompt, schema, and related-word ranking.
 * These do not call Gemini. Model-output cases live in contextual_gloss.model-eval.ts.
 *
 * Run: npx tsx src/features/contextual_gloss.selftest.ts
 */
import assert from "node:assert/strict";

import { contextualGloss } from "./contextual_gloss.js";

const sentence = "そうですね…最近、人口減少のニュースをよく見ます。";

function parse(
  surface: string,
  relatedWords: { word: string; note: string }[],
  extra: { dictionaryForm?: string; requestsHeadword?: boolean; headword?: string } = {},
) {
  return contextualGloss.parseResult(
    JSON.stringify({
      meaning: "decrease in population",
      grammarNote: "",
      relatedWords,
      ...(extra.headword !== undefined ? { headword: extra.headword } : {}),
    }),
    {
      sentence,
      surface,
      dictionaryForm: extra.dictionaryForm,
      framing: "inSentence",
      requestsHeadword: extra.requestsHeadword ?? false,
    },
  );
}

function words(surface: string, related: { word: string; note: string }[]) {
  return parse(surface, related).relatedWords;
}

// Ranking: a real split leads, and a looser relative does not take a component's slot.
assert.deepEqual(
  words("人口減少", [
    { word: "人口", note: "population" },
    { word: "減る", note: "the verb to decrease" },
    { word: "減少", note: "decrease" },
    { word: "人", note: "person" },
    { word: "口減", note: "chunk" },
    { word: "人口", note: "duplicate" },
  ]),
  [
    { word: "人口", note: "population" },
    { word: "減少", note: "decrease" },
  ],
);

assert.deepEqual(
  words("人口減少", [
    { word: "減る", note: "to decrease" },
    { word: "減少", note: "decrease" },
    { word: "人口", note: "population" },
  ]).map((item) => item.word),
  ["人口", "減少"],
);

assert.deepEqual(
  words("高速道路", [
    { word: "速い", note: "fast" },
    { word: "道路", note: "road" },
    { word: "高速", note: "high speed" },
  ]).map((item) => item.word),
  ["高速", "道路"],
);

// No full split: keep model order, still cap at 2, and do not invent the missing piece.
assert.deepEqual(
  words("人口減少", [
    { word: "減る", note: "to decrease" },
    { word: "人口", note: "population" },
  ]).map((item) => item.word),
  ["減る", "人口"],
);

assert.deepEqual(
  words("大学生", [
    { word: "学生", note: "student" },
    { word: "大学", note: "university" },
    { word: "生", note: "life" },
  ]).map((item) => item.word),
  ["学生", "大学"],
);

// Non-compounds do not gain invented parts. Single characters of the word are dropped.
assert.deepEqual(words("引っ越し", [{ word: "引っ越す", note: "to move" }]), [
  { word: "引っ越す", note: "to move" },
]);
assert.deepEqual(words("今日", [
  { word: "今", note: "now" },
  { word: "日", note: "day" },
]), []);
assert.deepEqual(
  words("働く", [
    { word: "働", note: "work" },
    { word: "く", note: "kana" },
    { word: "労働", note: "labor" },
  ]),
  [{ word: "労働", note: "labor" }],
);
assert.deepEqual(words("スマホ", []), []);

// Junk the card would hide does not consume a slot.
assert.deepEqual(
  words("引っ越し", [
    { word: "は", note: "topic" },
    { word: "population", note: "english" },
    { word: "引っ越す", note: "to move" },
  ]).map((item) => item.word),
  ["引っ越す"],
);

const excluded = parse("行きます", [
  { word: "行く", note: "to go" },
  { word: "来る", note: "to come" },
], { dictionaryForm: "行く" });
assert.deepEqual(excluded.relatedWords.map((item) => item.word), ["来る"]);

assert.deepEqual(words("人口減少", [
  { word: "人口減少", note: "itself" },
  { word: "人口", note: "population" },
  { word: "減少", note: "decrease" },
]).map((item) => item.word), ["人口", "減少"]);

assert.equal(words("減る", [{ word: "減少", note: "the verb to decrease" }])[0]?.note, "to decrease");

assert.throws(
  () =>
    contextualGloss.parseResult(JSON.stringify({ meaning: " ", grammarNote: "", relatedWords: [] }), {
      sentence,
      surface: "人口減少",
      framing: "inSentence",
      requestsHeadword: false,
    }),
  /missing meaning/,
);

const withHeadword = parse("人口減少", [], { requestsHeadword: true, headword: "人口減少" });
assert.equal(withHeadword.headword, "人口減少");
assert.equal(parse("人口減少", []).headword, "");

const built = contextualGloss.build({
  sentence,
  surface: "人口減少",
  framing: "inSentence",
  requestsHeadword: false,
});
assert.match(built.systemInstruction, /人口減少 → 人口 "population", then 減少 "decrease"/);
assert.match(built.systemInstruction, /減る "to decrease" must not take the place of 減少/);
assert.match(built.systemInstruction, /高速道路 → 高速 "high speed", then 道路 "road"/);
assert.match(built.systemInstruction, /Do not split a word that does not come apart/);
assert.match(built.systemInstruction, /今日, スマホ, and 働く have no component words/);
assert.match(built.systemInstruction, /Do not suggest a single kanji/);
assert.match(built.systemInstruction, /引っ越し → 引っ越す "to move"/);
assert.match(built.systemInstruction, /Up to 2 other Japanese words/);
assert.match(built.prompt, /real component words first, in written order/);
assert.doesNotMatch(built.systemInstruction, /人口減少 is a special case/);

const schema = built.responseSchema;
assert.deepEqual(schema.required, ["meaning", "grammarNote", "relatedWords"]);
const relatedSchema = schema.properties?.relatedWords;
assert.equal(relatedSchema?.type, "ARRAY");
assert.equal(relatedSchema?.maxItems, undefined);
assert.match(relatedSchema?.description ?? "", /component words first/);
assert.deepEqual(relatedSchema?.items && !Array.isArray(relatedSchema.items) ? relatedSchema.items.required : [], [
  "word",
  "note",
]);

const headwordSchema = contextualGloss.build({
  sentence,
  surface: "人口減少",
  framing: "inSentence",
  requestsHeadword: true,
}).responseSchema;
assert.ok(headwordSchema.required?.includes("headword"));
assert.equal(headwordSchema.required?.length, 4);

console.log("contextual_gloss selftest ok");
