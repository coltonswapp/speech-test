import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { ASR_LINE_MAX_CHARS, splitLongAsrLines } from "./asr-lines";

const RUN_ON =
  "ということで、今私たちは難波の近くに来まして、私が今回、この大阪旅行行くってなって、あ、そうだ！行きたかったんだ、ずっとって思い出した。";

const NO_PUNCT =
  "今日は天気がよかったから友達とカフェに行ってコーヒーを飲んでずっと話してたんですけど結局時間を忘れちゃいました";

describe("splitLongAsrLines", () => {
  it("leaves short lines whole", () => {
    assert.deepEqual(splitLongAsrLines(["今日はいい天気です。"]), ["今日はいい天気です。"]);
  });

  it("splits a punctuated run-on near the middle and keeps every character", () => {
    const lines = splitLongAsrLines([RUN_ON]);
    assert.equal(lines.join(""), RUN_ON);
    assert.ok(lines.length > 1);
    for (const line of lines) {
      assert.ok(line.length > 0);
      assert.ok(
        line.length <= ASR_LINE_MAX_CHARS,
        `oversized piece with a clause boundary: ${line} (${line.length})`
      );
    }
  });

  it("prefers punctuation over a particle closer to the middle", () => {
    const text =
      "そうだったんです、友達は誘ってくれたけど一緒に行くのはちょっと難しかった";
    const lines = splitLongAsrLines([text]);
    assert.equal(lines.join(""), text);
    assert.ok(lines[0]!.endsWith("、"), lines[0]);
    assert.ok(!lines[0]!.includes("けど"), lines[0]);
  });

  it("splits a particle-only run-on at から / て / けど", () => {
    const lines = splitLongAsrLines([NO_PUNCT]);
    assert.equal(lines.join(""), NO_PUNCT);
    assert.ok(lines.length > 1);
    for (const line of lines) {
      assert.ok(line.length <= ASR_LINE_MAX_CHARS, line);
    }
    const joinedEnds = lines.map((l) => l.slice(-2)).join(" ");
    assert.ok(
      /から|って|て|んで|けど/.test(joinedEnds + lines.slice(0, -1).join("")),
      lines.join(" | ")
    );
  });

  it("does not cut inside a quote", () => {
    const text =
      "お友達がもうノリで「え、日帰りだけど行っちゃう？」って言って来ましたそれからみんなで笑ってたんです";
    const lines = splitLongAsrLines([text]);
    assert.equal(lines.join(""), text);
    for (const line of lines) {
      const opens = (line.match(/「/g) ?? []).length;
      const closes = (line.match(/」/g) ?? []).length;
      assert.equal(opens, closes, `quote split across lines: ${lines.join(" | ")}`);
    }
  });

  it("does not split ている or として", () => {
    const progressive = "今は大阪に住んでいる友達と一緒に難波の方まで歩いているところです";
    const lines = splitLongAsrLines([progressive]);
    assert.equal(lines.join(""), progressive);
    assert.ok(!lines.some((l) => l.endsWith("住んで") || l.endsWith("歩いて")), lines.join(" | "));

    const toshite = "非常用のお金として使う現金とクレジットカードを包みますそれから財布に入れます";
    const as = splitLongAsrLines([toshite]);
    assert.equal(as.join(""), toshite);
    assert.ok(!as.some((l) => l.endsWith("として")), as.join(" | "));
  });

  it("leaves a long line whole when there is no safe boundary", () => {
    const text = "あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめも";
    assert.ok(text.length > ASR_LINE_MAX_CHARS);
    assert.deepEqual(splitLongAsrLines([text]), [text]);
  });

  it("does not drop, add, or reorder text across several input lines", () => {
    const input = ["短句。", RUN_ON, "はい。", NO_PUNCT];
    const output = splitLongAsrLines(input);
    assert.equal(output.join(""), input.join(""));
    assert.ok(output.length > input.length);
  });
});
