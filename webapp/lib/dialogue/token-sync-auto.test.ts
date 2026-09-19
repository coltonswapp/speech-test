import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  AUTO_STAMP_SHIFT_SECONDS,
  autoStampTokenSync,
  type AlignedLine,
} from "./token-sync-auto";

const SR = 1000; // 1 kHz keeps sample↔second math trivial; RMS window = 10 samples.

/** Synthetic take: speech bursts (loud) separated by silence. */
function synth(bursts: Array<[number, number]>, durationSeconds: number): Float32Array {
  const out = new Float32Array(Math.round(durationSeconds * SR));
  for (const [from, to] of bursts) {
    for (let i = Math.round(from * SR); i < Math.round(to * SR) && i < out.length; i++) {
      out[i] = i % 2 === 0 ? 0.5 : -0.5;
    }
  }
  return out;
}

function alignedLine(starts: number[], score = 0.8): AlignedLine {
  return {
    score,
    tokens: starts.map((s) => ({ startSeconds: s, endSeconds: s + 0.1, score, readingFallback: true })),
  };
}

describe("autoStampTokenSync", () => {
  // Line A speaks 0.10–1.00 s, silence, line B speaks 1.60–2.50 s.
  const samples = synth([[0.1, 1.0], [1.6, 2.5]], 3.0);
  const lines = [
    { text: "こんにちはお元気", tokens: [{ text: "こんにちは" }, { text: "お元気" }] },
    { text: "はいとても", tokens: [{ text: "はい" }, { text: "とても" }] },
  ];
  // Raw CTC starts run ~26 ms late of onset.
  const aligned = [alignedLine([0.126, 0.6]), alignedLine([1.626, 2.1])];

  it("derives a mark in the silence gap, 80–250 ms before the next onset", () => {
    const r = autoStampTokenSync({ alignerVersion: "t", aligned, lines, samples, sampleRate: SR, contentHash: "h" });
    assert.equal(r.marksDerived, true);
    assert.equal(r.markSamples.length, 1);
    const mark = r.markSamples[0] / SR;
    // Gap is 1.0–1.6 (600 ms) → midpoint lead is clamped to 250 ms before onset.
    assert.ok(mark > 1.0 && mark < 1.6, `mark ${mark} not inside gap`);
    assert.ok(Math.abs(mark - (1.6 - 0.25)) < 0.011, `mark ${mark} not 250 ms before onset`);
    assert.equal(r.flags.length, 0);
  });

  it("first tokens follow the line mark; later tokens are shifted raw starts", () => {
    const r = autoStampTokenSync({ alignerVersion: "t", aligned, lines, samples, sampleRate: SR, contentHash: "h" });
    const [a, b] = r.tokenSync.lines;
    assert.equal(a.tokens[0].startSeconds, 0);
    assert.equal(b.tokens[0].startSeconds, r.markSamples[0] / SR);
    assert.equal(a.tokens[1].startSeconds, Math.round((0.6 - AUTO_STAMP_SHIFT_SECONDS) * 1000) / 1000);
    assert.equal(r.tokenSync.source, "auto");
    assert.equal(r.tokenSync.alignerVersion, "t");
  });

  it("keeps existing marks when the take has one per boundary", () => {
    const r = autoStampTokenSync({
      alignerVersion: "t", aligned, lines, samples, sampleRate: SR, contentHash: "h",
      existingMarkSamples: [1200],
    });
    assert.equal(r.marksDerived, false);
    assert.deepEqual(r.markSamples, [1200]);
    assert.equal(r.tokenSync.lines[1].tokens[0].startSeconds, 1.2);
  });

  it("honours a shift override and stays monotonic", () => {
    const r = autoStampTokenSync({
      alignerVersion: "t", aligned, lines, samples, sampleRate: SR, contentHash: "h",
      options: { shiftSeconds: 0.15 },
    });
    assert.equal(r.tokenSync.lines[0].tokens[1].startSeconds, 0.45);
    const all = r.tokenSync.lines.flatMap((l) => l.tokens.map((t) => t.startSeconds!));
    for (let i = 1; i < all.length; i++) assert.ok(all[i] > all[i - 1]);
  });

  it("ignores a short blip before the onset and marks inside the real gap", () => {
    // Line A 0.10–1.00, a 20 ms click at 1.50, line B from 1.60.
    const blip = synth([[0.1, 1.0], [1.5, 1.52], [1.6, 2.5]], 3.0);
    const r = autoStampTokenSync({ alignerVersion: "t", aligned, lines, samples: blip, sampleRate: SR, contentHash: "h" });
    const mark = r.markSamples[0] / SR;
    assert.ok(!r.flags.some((f) => f.code === "no-gap"), "blip must not read as no-gap");
    assert.ok(mark > 1.0 && mark < 1.5, `mark ${mark} should sit in the 1.0–1.5 silence`);
  });

  it("flags no-gap when speakers overlap and still places a mark", () => {
    const glued = synth([[0.1, 2.5]], 3.0);
    const r = autoStampTokenSync({ alignerVersion: "t", aligned, lines, samples: glued, sampleRate: SR, contentHash: "h" });
    assert.ok(r.flags.some((f) => f.code === "no-gap" && f.lineIndex === 1));
    assert.equal(r.markSamples.length, 1);
  });

  it("flags script-mismatch and leaves that line's later tokens unstamped", () => {
    const bad = [alignedLine([0.126, 0.6], 0.8), alignedLine([1.626, 2.1], 0.1)];
    const r = autoStampTokenSync({ alignerVersion: "t", aligned: bad, lines, samples, sampleRate: SR, contentHash: "h" });
    assert.ok(r.flags.some((f) => f.code === "script-mismatch" && f.lineIndex === 1));
    assert.equal(r.tokenSync.lines[1].tokens[1].startSeconds, null);
    assert.notEqual(r.tokenSync.lines[1].tokens[0].startSeconds, null);
  });

  it("flags stamp-in-silence only for post-pause tokens landing well before speech", () => {
    // Line A: two bursts with a 400 ms pause; token 2's raw start is far too early.
    const paused = synth([[0.1, 0.5], [0.9, 1.4], [1.9, 2.5]], 3.0);
    const al = [alignedLine([0.126, 0.7]), alignedLine([1.926, 2.2])];
    const r = autoStampTokenSync({ alignerVersion: "t", aligned: al, lines, samples: paused, sampleRate: SR, contentHash: "h" });
    assert.ok(r.flags.some((f) => f.code === "stamp-in-silence" && f.lineIndex === 0 && f.tokenIndex === 1));
    assert.ok(!r.flags.some((f) => f.lineIndex === 1));
  });

  it("flags reading-fallback only when a supplied reading was rejected", () => {
    const withReading = [
      { text: "こんにちはお元気", tokens: [{ text: "こんにちは", reading: "こんにちは" }, { text: "お元気" }] },
      lines[1],
    ];
    const r = autoStampTokenSync({ alignerVersion: "t", aligned, lines: withReading, samples, sampleRate: SR, contentHash: "h" });
    const fb = r.flags.filter((f) => f.code === "reading-fallback");
    assert.deepEqual(fb.map((f) => [f.lineIndex, f.tokenIndex]), [[0, 0]]);
    assert.equal(r.tokenSync.lines[0].tokens[0].reading, "こんにちは");
  });
});
