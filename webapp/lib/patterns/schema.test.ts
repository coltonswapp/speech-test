import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, it } from "node:test";
import { parseAddedPatternsJson } from "./import";
import {
  normalizeTeachingPatternUpdate,
  normalizeTeachingPatternWrites,
  teachingPatternCreateBodySchema,
  teachingPatternUpdateSchema,
} from "./schema";
import {
  isMissingDescription,
  normalizePatternDescriptionFills,
  patternDescriptionFillFileSchema,
  toDescriptionDumpRow,
} from "./description-backfill";

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
    assert.equal(
      normalizeTeachingPatternWrites({ patterns: [one] })[0]?.description,
      null
    );
  });

  it("accepts a missing description and normalizes blank to null", () => {
    const without = {
      id: "te-mo-ii",
      form: "〜てもいい",
      gloss: "permission",
    };
    const parsedWithout = teachingPatternCreateBodySchema.parse(without);
    assert.equal(
      normalizeTeachingPatternWrites(parsedWithout)[0]?.description,
      null
    );

    const blank = {
      ...without,
      description: "   ",
    };
    const parsedBlank = teachingPatternCreateBodySchema.parse(blank);
    assert.equal(
      normalizeTeachingPatternWrites(parsedBlank)[0]?.description,
      null
    );

    const filled = {
      ...without,
      description:
        "Used to ask for or give permission to do something ('Is it OK if I…?' / 'You may…').",
    };
    const parsedFilled = teachingPatternCreateBodySchema.parse(filled);
    assert.equal(
      normalizeTeachingPatternWrites(parsedFilled)[0]?.description,
      filled.description
    );
  });

  it("accepts a partial PATCH body with description", () => {
    assert.equal(teachingPatternUpdateSchema.safeParse({}).success, true);
    assert.equal(
      teachingPatternUpdateSchema.safeParse({ description: null }).success,
      true
    );
    assert.equal(
      normalizeTeachingPatternUpdate({ description: "  hello  " }).description,
      "hello"
    );
    assert.equal(
      normalizeTeachingPatternUpdate({ description: "  " }).description,
      null
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

describe("pattern description backfill", () => {
  it("dumps empty description placeholders for missing rows", () => {
    assert.equal(isMissingDescription(null), true);
    assert.equal(isMissingDescription(""), true);
    assert.equal(isMissingDescription("  "), true);
    assert.equal(isMissingDescription("Used to…"), false);
    assert.deepEqual(
      toDescriptionDumpRow({
        id: "te-mo-ii",
        form: "〜てもいい",
        gloss: "permission",
        jlptBand: 5,
        category: "request_permission",
        notes: "note",
      }),
      {
        id: "te-mo-ii",
        form: "〜てもいい",
        gloss: "permission",
        jlptBand: 5,
        category: "request_permission",
        notes: "note",
        description: "",
      }
    );
  });

  it("validates filled apply JSON and skips empty descriptions", () => {
    const filled = {
      id: "te-mo-ii",
      form: "〜てもいい",
      gloss: "permission",
      jlptBand: 5,
      category: "request_permission",
      notes: null,
      description:
        "Used to ask for or give permission to do something ('Is it OK if I…?' / 'You may…').",
    };
    assert.equal(
      patternDescriptionFillFileSchema.safeParse([filled]).success,
      true
    );
    assert.equal(
      patternDescriptionFillFileSchema.safeParse({ patterns: [filled] }).success,
      true
    );
    const { fills, skippedEmpty } = normalizePatternDescriptionFills({
      patterns: [filled, { ...filled, id: "empty", description: "  " }],
    });
    assert.equal(fills.length, 1);
    assert.equal(fills[0]?.id, "te-mo-ii");
    assert.equal(skippedEmpty, 1);
  });
});
