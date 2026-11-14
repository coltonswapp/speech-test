import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { isMissingObjectError } from "./missing-object";

describe("isMissingObjectError", () => {
  it("accepts NoSuchKey / 404 only", () => {
    assert.equal(isMissingObjectError({ name: "NoSuchKey" }), true);
    assert.equal(
      isMissingObjectError({ name: "Error", $metadata: { httpStatusCode: 404 } }),
      true,
    );
    assert.equal(isMissingObjectError(new Error("AccessDenied")), false);
    assert.equal(isMissingObjectError({ name: "AccessDenied" }), false);
    assert.equal(isMissingObjectError({ $metadata: { httpStatusCode: 500 } }), false);
  });
});
