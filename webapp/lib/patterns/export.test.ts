import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { exportedTeachingPatternSchema } from "@/lib/dialogue/types";
import { toExportedTeachingPattern } from "./export";

const baseRow = {
  id: "te-mo-ii",
  form: "〜てもいい",
  gloss: "may I 〜?; is OK to 〜; permission",
  notes: null as string | null,
};

describe("toExportedTeachingPattern description", () => {
  it("omits description when missing, empty, or whitespace", () => {
    assert.equal(
      toExportedTeachingPattern(baseRow).description,
      undefined
    );
    assert.equal(
      toExportedTeachingPattern({ ...baseRow, description: null }).description,
      undefined
    );
    assert.equal(
      toExportedTeachingPattern({ ...baseRow, description: "" }).description,
      undefined
    );
    assert.equal(
      toExportedTeachingPattern({ ...baseRow, description: "   " }).description,
      undefined
    );
    assert.deepEqual(toExportedTeachingPattern(baseRow), {
      id: "te-mo-ii",
      label: "〜てもいい",
      shortMeaning: "may I 〜?; is OK to 〜; permission",
    });
  });

  it("includes a trimmed description when non-empty", () => {
    const exported = toExportedTeachingPattern({
      ...baseRow,
      description:
        "  Used to ask for or give permission to do something ('Is it OK if I…?' / 'You may…').  ",
    });
    assert.equal(
      exported.description,
      "Used to ask for or give permission to do something ('Is it OK if I…?' / 'You may…')."
    );
  });
});

describe("exportedTeachingPatternSchema description", () => {
  it("accepts a payload with no description (older iOS / existing consumers)", () => {
    const parsed = exportedTeachingPatternSchema.safeParse({
      id: "te-mo-ii",
      label: "〜てもいい",
      shortMeaning: "may I 〜?; is OK to 〜; permission",
    });
    assert.equal(parsed.success, true);
    if (parsed.success) {
      assert.equal(parsed.data.description, undefined);
    }
  });

  it("accepts an optional description", () => {
    const parsed = exportedTeachingPatternSchema.safeParse({
      id: "te-mo-ii",
      label: "〜てもいい",
      shortMeaning: "permission",
      description: "Used to ask for or give permission.",
    });
    assert.equal(parsed.success, true);
    if (parsed.success) {
      assert.equal(
        parsed.data.description,
        "Used to ask for or give permission."
      );
    }
  });
});
