import assert from "node:assert/strict";

import { InputError } from "../validate.js";
import { grammarUsage } from "./grammar_usage.js";

const input = grammarUsage.parseInput({
  pattern: "___ ちゃいけない",
  grammarPointID: "n5-cha-ikenai",
  lines: [
    { speaker: "A", japanese: "ここで宿題してもいい？", english: "Can I do homework here?" },
    { speaker: "B", japanese: "飲み物を飲んじゃいけないよ。", english: "You can't drink here.", focus: true },
  ],
});
assert.equal(input.lines.length, 2);
assert.equal(input.lines[1].focus, true);
assert.equal(input.lines[0].focus, false);

assert.throws(() => grammarUsage.parseInput({ pattern: "___ だし", lines: [] }), InputError);
assert.throws(() => grammarUsage.parseInput({ pattern: "", lines: [{ japanese: "だし" }] }), InputError);
assert.throws(
  () => grammarUsage.parseInput({ pattern: "___ だし", lines: [{ japanese: "静かだし", focus: "yes" }] }),
  InputError,
);

const prompt = grammarUsage.build(input).prompt;
assert.match(prompt, /^Pattern: ___ ちゃいけない/);
assert.match(prompt, /Curriculum id \(hint only\): n5-cha-ikenai/);
assert.match(prompt, /→ 飲み物を飲んじゃいけないよ。/);
assert.match(prompt, / {2}ここで宿題してもいい？/);

const punctuated = grammarUsage.parseResult(
  JSON.stringify({
    inThisScene: "Saying you must not drink here.",
    form: "",
    examples: [
      "ここで写真を撮っちゃいけないよ。 (ここでしゃしんをとっちゃいけないよ。) — You can't take photos here.",
      "ケーキ、食べちゃいけない？ (ケーキ、たべちゃいけない？) — Can't I eat the cake?",
    ],
    note: "",
  }),
  input,
);
assert.deepEqual(punctuated.examples, [
  "ここで写真を撮っちゃいけないよ。 (ここでしゃしんをとっちゃいけないよ。) — You can't take photos here.",
  "ケーキ、食べちゃいけない？ (ケーキ、たべちゃいけない？) — Can't I eat the cake?",
]);

const result = grammarUsage.parseResult(
  JSON.stringify({
    inThisScene: "Saying you must not drink here.",
    form: "verb て-form (て→ちゃ) + いけない",
    examples: [
      "ここで写真を撮っちゃいけない (ここでしゃしんをとっちゃいけない) — You can't take photos here.",
      "飲み物を飲んじゃいけないよ。 — You can't drink here.",
      "走っちゃいけない (hashiccha ikenai) — You must not run.",
      "ここで写真を撮っちゃいけない (ここでしゃしんをとっちゃいけない) — You can't take photos here.",
      "You must not run.",
      "触っちゃいけない — Don't touch.",
    ],
    note: "ちゃ is the casual form of ては.",
  }),
  input,
);
assert.equal(result.inThisScene, "Saying you must not drink here.");
assert.deepEqual(result.examples, [
  "ここで写真を撮っちゃいけない (ここでしゃしんをとっちゃいけない) — You can't take photos here.",
  "走っちゃいけない — You must not run.",
  "触っちゃいけない — Don't touch.",
]);
assert.equal(result.note, "ちゃ is the casual form of ては.");

assert.throws(
  () => grammarUsage.parseResult(JSON.stringify({ inThisScene: " ", form: "", examples: [], note: "" }), input),
  /empty inThisScene/,
);

console.log("grammar_usage selftest ok");
