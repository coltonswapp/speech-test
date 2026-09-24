import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  contentQaStatusFromFlags,
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
  });
});
