import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, it } from "node:test";
import { parseAddedPatternsJson } from "./import";
import {
  normalizeTeachingPatternWrites,
  teachingPatternCreateBodySchema,
} from "./schema";

describe("teaching pattern create body", () => {
  it("accepts one pattern, an array, or { patterns }", () => {
    const one = {
      id: "te-shimau",
      form: "〜てしまう",
      gloss: "end up ~",
      jlptBand: 4,
      category: "experience_aspect",
      status: "seed",
      notes: "note",
      orderIndex: 200,
    };
    assert.equal(teachingPatternCreateBodySchema.safeParse(one).success, true);
    assert.equal(
      teachingPatternCreateBodySchema.safeParse([one]).success,
      true
    );
    assert.equal(
      teachingPatternCreateBodySchema.safeParse({ patterns: [one] }).success,
      true
    );
    assert.equal(
      normalizeTeachingPatternWrites({ patterns: [one] })[0]?.notes,
      "note"
    );
  });

  it("parses the committed added-patterns.json seed (23 drafts)", () => {
    const raw = readFileSync(
      path.resolve(process.cwd(), "content/seeds/added-patterns.json"),
      "utf8"
    );
    const rows = parseAddedPatternsJson(raw);
    assert.equal(rows.length, 23);
    assert.equal(rows[0]?.id, "te-shimau");
    assert.ok(rows.every((row) => row.form && row.gloss));
  });
});
