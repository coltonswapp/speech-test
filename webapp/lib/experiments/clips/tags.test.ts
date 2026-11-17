import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  clipEffectiveTags,
  clipPaceLabel,
  clipTagKeys,
  parseClipTagAnswer,
  titleHints,
} from "./tags";

const answer = {
  format: "vlog",
  topics: ["food", "travel", "food", "money-shopping", "daily-life"],
  register: "casual",
  speakers: "dialogue",
  dialect: "standard",
  series: "  ",
  suggested: ["topic:gardening", "topic:food", "Topic:Cars", "nonsense", "pace:slow"],
  reason: " A trip to Osaka. ",
};

describe("parseClipTagAnswer", () => {
  it("dedupes and caps topics, drops blank series, keeps only new well-formed suggestions", () => {
    const parsed = parseClipTagAnswer(answer);
    assert.ok(parsed);
    assert.deepEqual(parsed.pick.topics, ["food", "travel", "money-shopping"]);
    assert.equal(parsed.pick.series, undefined);
    assert.equal(parsed.reason, "A trip to Osaka.");
    // topic:food is already known; pace isn't a suggestible facet.
    assert.deepEqual(parsed.suggested, ["topic:gardening", "topic:cars"]);
  });

  it("rejects values outside the vocabulary", () => {
    assert.equal(parseClipTagAnswer({ ...answer, format: "podcast" }), null);
    assert.equal(parseClipTagAnswer({ ...answer, topics: ["cars"] }), null);
  });
});

describe("clipEffectiveTags", () => {
  const auto = { format: "vlog", topics: ["food"], register: "casual", speakers: "dialogue", dialect: "standard", model: "m", at: "t" };
  it("prefers hand-set tags", () => {
    const manual = { ...auto, format: "drama", at: "t2" };
    assert.equal(clipEffectiveTags({ auto, manual })?.format, "drama");
    assert.equal(clipEffectiveTags({ auto })?.format, "vlog");
    assert.equal(clipEffectiveTags(undefined), null);
  });
});

describe("clipTagKeys", () => {
  it("prefixes each facet and adds the pace bucket", () => {
    const keys = clipTagKeys(
      { format: "anime", topics: ["romance"], register: "casual", speakers: "dialogue", dialect: "kansai", series: "名探偵コナン" },
      9.6
    );
    assert.deepEqual(keys, [
      "format:anime",
      "topic:romance",
      "register:casual",
      "speakers:dialogue",
      "dialect:kansai",
      "series:名探偵コナン",
      "pace:fast",
    ]);
    assert.deepEqual(clipTagKeys(null, 5.2), ["pace:slow"]);
    assert.deepEqual(clipTagKeys(null, null), []);
  });

  it("buckets pace at the thresholds", () => {
    assert.equal(clipPaceLabel(5.99), "slow");
    assert.equal(clipPaceLabel(6), "natural");
    assert.equal(clipPaceLabel(8.99), "natural");
    assert.equal(clipPaceLabel(9), "fast");
  });
});

describe("titleHints", () => {
  it("pulls hashtags and 【】 labels, minus noise", () => {
    const hints = titleHints("【莉子旅】大阪で食べ歩き #shorts #グルメ ＃大阪 #おすすめ");
    assert.deepEqual(hints, { hashtags: ["グルメ", "大阪"], labels: ["莉子旅"] });
  });
});
