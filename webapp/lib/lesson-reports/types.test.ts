import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { parseLessonReportEntry } from "./types";

describe("parseLessonReportEntry reporter", () => {
  it("reads uid from the gateway field", () => {
    const row = parseLessonReportEntry("r1", { uid: "abc123" });
    assert.equal(row.userId, "abc123");
  });

  it("prefers userId when both are present", () => {
    const row = parseLessonReportEntry("r1", { uid: "from-uid", userId: "from-userId" });
    assert.equal(row.userId, "from-userId");
  });

  it("is null when neither field is present", () => {
    const row = parseLessonReportEntry("r1", {});
    assert.equal(row.userId, null);
  });
});
