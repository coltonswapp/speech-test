import assert from "node:assert/strict";

import { spanBreakdown } from "./span_breakdown.js";

const span = "学食を探そう";

function parse(surface: string, result: Record<string, unknown>) {
  return spanBreakdown.parseResult(JSON.stringify(result), {
    sentence: `${surface}。`,
    surface,
  });
}

const cafeteria = parse(span, {
  inThisSentence: "Suggests looking for the school cafeteria.",
  otherUses: ["学食で食べる — to eat at the cafeteria", "to look around"],
  partsNote: "学 (study) + 食 (food) — school cafeteria",
  components: [
    { surface: "学食", lemma: "学食", reading: "がくしょく", gloss: "school cafeteria" },
    { surface: "を", lemma: "を", reading: "を", gloss: "object marker" },
    { surface: "探そう", lemma: "探す", reading: "さがす", gloss: "the verb to look for" },
    { surface: "学", lemma: "学", reading: "がく", gloss: "study" },
    { surface: "食", lemma: "食", reading: "しょく", gloss: "food" },
    { surface: "ます", lemma: "ます", reading: "ます", gloss: "polite" },
    { surface: "東京", lemma: "東京", reading: "とうきょう", gloss: "Tokyo" },
  ],
});

assert.equal(cafeteria.inThisSentence, "Suggests looking for the school cafeteria.");
assert.equal(cafeteria.partsNote, "学 (study) + 食 (food) — school cafeteria");
assert.deepEqual(cafeteria.otherUses, ["学食で食べる — to eat at the cafeteria"]);
assert.deepEqual(cafeteria.components, [
  { surface: "学食", lemma: "学食", reading: "がくしょく", gloss: "school cafeteria" },
  { surface: "探そう", lemma: "探す", reading: "さがす", gloss: "to look for" },
]);

const withWholeSpan = parse(span, {
  inThisSentence: "Suggests looking for the cafeteria.",
  otherUses: [],
  partsNote: "",
  components: [
    { surface: span, lemma: span, reading: "", gloss: "look for cafeteria" },
    { surface: "学食", lemma: "学食", reading: "がくしょく", gloss: "school cafeteria" },
    { surface: "探そう", lemma: "探す", reading: "さがす", gloss: "to look for" },
  ],
});
assert.deepEqual(
  withWholeSpan.components.map((item) => item.lemma),
  ["学食", "探す"],
);

const dictionaryFormAsSurface = parse(span, {
  inThisSentence: "Suggests looking for the cafeteria.",
  otherUses: [],
  partsNote: "",
  components: [
    { surface: "探す", lemma: "探す", reading: "（さがす）", gloss: "to look for food now" },
    { surface: "学食", lemma: "学食", reading: "gakushoku", gloss: "A school cafeteria." },
  ],
});
assert.deepEqual(dictionaryFormAsSurface.components, [
  { surface: "探す", lemma: "探す", reading: "さがす", gloss: "to look for" },
  { surface: "学食", lemma: "学食", reading: "", gloss: "school cafeteria" },
]);

const legacy = parse(span, {
  inThisSentence: "Suggests looking for the cafeteria.",
  otherUses: [],
  partsNote: "学 (study) + 食 (food) — school cafeteria",
});
assert.deepEqual(legacy.components, []);
assert.equal(legacy.partsNote, "学 (study) + 食 (food) — school cafeteria");

assert.throws(
  () => parse(span, { inThisSentence: " ", otherUses: [], partsNote: "", components: [] }),
  /empty inThisSentence/,
);

const prompt = spanBreakdown.build({
  sentence: "学食を探そう。",
  surface: span,
}).systemInstruction;
assert.match(prompt, /学食を探そう/);
assert.match(prompt, /lemma is 探す/);
assert.match(prompt, /Skip particles/);
assert.match(prompt, /Particles are read as pronounced, not as spelled/);
assert.match(prompt, /母 → はは/);
assert.match(prompt, /Do not split a compound into kanji/);
assert.match(prompt, /"components"/);
assert.match(prompt, /verb た-form \(転入した\) \+ ばかり — just transferred/);
assert.match(prompt, /Slot labels/);
assert.match(prompt, /Empty when inThisSentence is a formula/);

const schema = spanBreakdown.build({ sentence: "学食を探そう。", surface: span }).responseSchema;
assert.ok(schema.required?.includes("components"));
assert.ok(schema.required?.includes("partsNote"));

console.log("span_breakdown selftest ok");
