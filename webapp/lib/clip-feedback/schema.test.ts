import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { clipFeedbackRequestSchema, initialStatus } from "./schema";

const line = { index: 2, startSec: 4.1, endSec: 6.3, textJP: "今日は暑いね", textEN: "It's hot today" };
const parse = (body: unknown) => clipFeedbackRequestSchema.safeParse(body);

describe("clipFeedbackRequestSchema", () => {
  it("accepts a plain rating and a line flag", () => {
    assert.equal(parse({ kind: "rating", rating: "up" }).success, true);
    assert.equal(parse({ kind: "rating", rating: "down", reason: "timing" }).success, true);
    assert.equal(
      parse({ kind: "flag", reason: "tokenization", line, tokenPosition: 1, note: "split wrong" }).success,
      true,
    );
  });

  it("rejects a rating with no thumbs, a flag with no reason, or a flag with a rating", () => {
    assert.equal(parse({ kind: "rating" }).success, false);
    assert.equal(parse({ kind: "flag" }).success, false);
    assert.equal(parse({ kind: "flag", reason: "other", rating: "down" }).success, false);
  });

  it("rejects unknown reasons, long notes, and a word with no line", () => {
    assert.equal(parse({ kind: "flag", reason: "spam" }).success, false);
    assert.equal(parse({ kind: "flag", reason: "other", note: "x".repeat(1_001) }).success, false);
    assert.equal(parse({ kind: "flag", reason: "reading", tokenPosition: 0 }).success, false);
  });
});

describe("initialStatus", () => {
  const status = (body: unknown) => initialStatus(clipFeedbackRequestSchema.parse(body));
  it("opens flags and reasoned thumbs-downs only", () => {
    assert.equal(status({ kind: "flag", reason: "translation" }), "open");
    assert.equal(status({ kind: "rating", rating: "down", reason: "video" }), "open");
    assert.equal(status({ kind: "rating", rating: "down" }), null);
    assert.equal(status({ kind: "rating", rating: "up" }), null);
  });
});
