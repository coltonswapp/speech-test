import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { cleanVideoTitle, parseVideoTitleAnswer, titleNeedsTranslation } from "./video-title";

describe("cleanVideoTitle", () => {
  it("cuts the trailing run of hashtags, half- or full-width, with or without spaces", () => {
    assert.equal(cleanVideoTitle("飛距離が伸びる練習ドリル#ゴルフ #ゴルフレッスン ＃ゴルフ初心者"), "飛距離が伸びる練習ドリル");
    assert.equal(cleanVideoTitle("『好きバレしちゃう！』#キュリエーション学院#学園ショートドラマ"), "『好きバレしちゃう！』");
  });
  it("keeps the word of a hashtag inside the title", () => {
    assert.equal(
      cleanVideoTitle("#物間寧人：7期第153話より／『#僕のヒーローアカデミア FINAL SEASON』放送開始"),
      "物間寧人：7期第153話より／『僕のヒーローアカデミア FINAL SEASON』放送開始"
    );
  });
});

describe("titleNeedsTranslation", () => {
  it("is true for Japanese outside the trailing hashtags", () => {
    assert.equal(titleNeedsTranslation("夫を殺した仇に対して、彼女は忍耐を選びました。#shorts"), true);
  });
  it("is false for English titles and hashtag-only titles", () => {
    assert.equal(titleNeedsTranslation("【N5】Japanese listening practice #japanese #n5"), false);
    assert.equal(titleNeedsTranslation("#ゴルフ #ゴルフレッスン"), false);
  });
});

describe("parseVideoTitleAnswer", () => {
  const title = "飛距離が伸びる練習ドリル#ゴルフ";
  it("drops quotes around the whole answer and trailing hashtags", () => {
    assert.equal(
      parseVideoTitleAnswer({ en: "“Practice Drills to Increase Your Distance” #Golf" }, title),
      "Practice Drills to Increase Your Distance"
    );
  });
  it("keeps quotes that are part of the title", () => {
    assert.equal(
      parseVideoTitleAnswer({ en: '"A good wave has come, Anya-san!" / SPY×FAMILY Season 2' }, title),
      '"A good wave has come, Anya-san!" / SPY×FAMILY Season 2'
    );
  });
  it("rejects empty answers and echoes of the original", () => {
    assert.equal(parseVideoTitleAnswer({ en: "  " }, title), null);
    assert.equal(parseVideoTitleAnswer({ en: "飛距離が伸びる練習ドリル" }, title), null);
    assert.equal(parseVideoTitleAnswer({}, title), null);
  });
});
