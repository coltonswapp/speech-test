import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  contentQaStatusFromFlags,
  shouldClearContentQaOnSelectedTakeChange,
  upsertContentQaRequestSchema,
} from "./content-qa";

describe("contentQaStatusFromFlags", () => {
  it("derives pending / dialogue / quiz / done", () => {
    assert.equal(
      contentQaStatusFromFlags({
        dialogueReviewedAt: null,
        quizReviewedAt: null,
      }),
      "pending",
    );
    assert.equal(
      contentQaStatusFromFlags({
        dialogueReviewedAt: new Date(),
        quizReviewedAt: null,
      }),
      "dialogue",
    );
    assert.equal(
      contentQaStatusFromFlags({
        dialogueReviewedAt: null,
        quizReviewedAt: "2026-09-24T00:00:00.000Z",
      }),
      "quiz",
    );
    assert.equal(
      contentQaStatusFromFlags({
        dialogueReviewedAt: new Date(),
        quizReviewedAt: new Date(),
      }),
      "done",
    );
  });
});

describe("upsertContentQaRequestSchema", () => {
  it("requires at least one field", () => {
    assert.equal(upsertContentQaRequestSchema.safeParse({}).success, false);
    assert.equal(
      upsertContentQaRequestSchema.safeParse({ dialogueReviewed: true })
        .success,
      true,
    );
    assert.equal(
      upsertContentQaRequestSchema.safeParse({ reviewNote: null }).success,
      true,
    );
    assert.equal(
      upsertContentQaRequestSchema.safeParse({ checkedOff: true }).success,
      true,
    );
  });
});

describe("checkedOff vs status", () => {
  it("maps done to checkedOff via toContentQaRecord fields", () => {
    assert.equal(
      contentQaStatusFromFlags({
        dialogueReviewedAt: new Date(),
        quizReviewedAt: new Date(),
      }),
      "done",
    );
  });
});

describe("shouldClearContentQaOnSelectedTakeChange", () => {
  it("clears only when the selected take id actually changes", () => {
    assert.equal(
      shouldClearContentQaOnSelectedTakeChange("take-a", "take-b"),
      true,
    );
    assert.equal(
      shouldClearContentQaOnSelectedTakeChange("take-a", null),
      true,
    );
    assert.equal(
      shouldClearContentQaOnSelectedTakeChange(null, "take-a"),
      true,
    );
    assert.equal(
      shouldClearContentQaOnSelectedTakeChange(undefined, "take-a"),
      true,
    );
  });

  it("no-ops when re-selecting the same take (incl. both null)", () => {
    assert.equal(
      shouldClearContentQaOnSelectedTakeChange("take-a", "take-a"),
      false,
    );
    assert.equal(
      shouldClearContentQaOnSelectedTakeChange(null, null),
      false,
    );
    assert.equal(
      shouldClearContentQaOnSelectedTakeChange(undefined, null),
      false,
    );
    assert.equal(
      shouldClearContentQaOnSelectedTakeChange(null, undefined),
      false,
    );
  });
});
