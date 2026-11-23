import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { shortReporterId, usageUserHref } from "./reporter";

describe("shortReporterId", () => {
  it("keeps ids of 8 characters or fewer", () => {
    assert.equal(shortReporterId("abc"), "abc");
    assert.equal(shortReporterId("12345678"), "12345678");
  });

  it("truncates longer ids to 8 characters", () => {
    assert.equal(shortReporterId("abcdefghij"), "abcdefgh");
  });
});

describe("usageUserHref", () => {
  it("links to Usage with the uid query", () => {
    assert.equal(usageUserHref("user_1"), "/usage?uid=user_1");
  });

  it("encodes special characters in the uid", () => {
    assert.equal(usageUserHref("a b/c"), "/usage?uid=a%20b%2Fc");
  });
});
