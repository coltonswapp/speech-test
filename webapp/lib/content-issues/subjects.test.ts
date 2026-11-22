import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  clipIssueId,
  issueIdOf,
  issuePath,
  parseIssueId,
  parseIssueRef,
} from "./subjects";

describe("parseIssueRef", () => {
  it("accepts a clip issue id, feedback id, path, and absolute URL", () => {
    const key = "cfb_rmhDq5Yj9HtA";
    const expected = { subject: "clip" as const, key };
    assert.deepEqual(parseIssueRef(`clip-${key}`), expected);
    assert.deepEqual(parseIssueRef(key), expected);
    assert.deepEqual(parseIssueRef(`/content/issues/clip-${key}`), expected);
    assert.deepEqual(
      parseIssueRef(`https://shizen-studio.vercel.app/content/issues/clip-${key}`),
      expected
    );
    assert.deepEqual(
      parseIssueRef(`https://shizen-studio.vercel.app/content/issues/clip-${key}?from=slack#attempts`),
      expected
    );
  });

  it("accepts a scene issue URL", () => {
    assert.deepEqual(parseIssueRef("https://studio.example/content/issues/scene-abc_1"), {
      subject: "scene",
      key: "abc_1",
    });
  });

  it("rejects junk", () => {
    assert.equal(parseIssueRef(""), null);
    assert.equal(parseIssueRef("not-an-issue"), null);
    assert.equal(parseIssueRef("https://example.com/other/clip-cfb_x"), null);
  });
});

describe("issue path helpers", () => {
  it("builds the stable clip issue path", () => {
    const ref = parseIssueId("clip-cfb_rmhDq5Yj9HtA");
    assert.ok(ref);
    assert.equal(issueIdOf(ref), "clip-cfb_rmhDq5Yj9HtA");
    assert.equal(clipIssueId("cfb_rmhDq5Yj9HtA"), "clip-cfb_rmhDq5Yj9HtA");
    assert.equal(issuePath(ref), "/content/issues/clip-cfb_rmhDq5Yj9HtA");
  });
});
