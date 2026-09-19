import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { correctionStats, summarizeReviewTiming } from "./review-timing-core";
import type { VariantTokenSync } from "./types";

const sync: VariantTokenSync = {
  version: 1, contentHash: "h", source: "reviewed",
  lines: [
    { text: "ab", tokens: [{ text: "a", startSeconds: 0 }, { text: "b", startSeconds: 0.5 }] },
    { text: "cd", tokens: [{ text: "c", startSeconds: 1.0 }, { text: "d", startSeconds: 1.5 }] },
  ],
};

describe("correctionStats", () => {
  it("counts moved tokens and touched lines against the auto snapshot", () => {
    const r = correctionStats(sync, [0, 0.5, 1.0, 1.25]);
    assert.deepEqual(r, { linesTouched: 1, tokensMoved: 1, maxCorrectionMs: 250 });
  });
  it("ignores sub-millisecond drift and returns null on shape mismatch", () => {
    assert.deepEqual(correctionStats(sync, [0, 0.5004, 1.0, 1.5]), { linesTouched: 0, tokensMoved: 0, maxCorrectionMs: 0 });
    assert.equal(correctionStats(sync, [0, 0.5]), null);
    assert.equal(correctionStats(sync, undefined), null);
  });
});

describe("summarizeReviewTiming", () => {
  it("splits by source and reports medians and untouched share", () => {
    const s = summarizeReviewTiming([
      { publishedAt: "2026-09-18T10:10:00Z", openedAt: "2026-09-18T10:00:00Z", publishedSource: "reviewed", lineCount: 10, linesTouched: 2, maxCorrectionMs: 90 },
      { publishedAt: "2026-09-18T11:30:00Z", openedAt: "2026-09-18T11:00:00Z", publishedSource: "auto", lineCount: 10, linesTouched: 0, maxCorrectionMs: 300 },
      { publishedAt: "2026-09-18T12:00:00Z", openedAt: "2026-09-18T11:48:00Z", publishedSource: "human" },
      { publishedAt: "2026-09-18T13:00:00Z" },
      { openedAt: "2026-09-18T14:00:00Z" },
    ]);
    const auto = s.bySource.find((r) => r.source === "auto")!;
    const human = s.bySource.find((r) => r.source === "human")!;
    assert.equal(auto.published, 2);
    assert.equal(auto.medianOpenToPublishMinutes, 20);
    assert.equal(auto.linesUntouchedPct, 90);
    assert.equal(auto.correctionsOver200msPct, 50);
    assert.equal(human.published, 2);
    assert.equal(human.withOpenTiming, 1);
    assert.equal(human.medianOpenToPublishMinutes, 12);
    assert.equal(human.linesUntouchedPct, null);
    assert.equal(s.since, "2026-09-18T10:10:00Z");
  });
});
