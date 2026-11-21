import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { diffSnapshots } from "./diff";
import type { ClipSnapshot, SnapshotLine } from "./snapshot";

const line = (ja: string, extra: Partial<SnapshotLine> = {}): SnapshotLine => ({
  ja,
  en: `${ja} (en)`,
  start: 1,
  end: 2,
  tokens: [{ text: ja }],
  ...extra,
});

const snap = (lines: SnapshotLine[], extra: Partial<ClipSnapshot> = {}): ClipSnapshot => ({
  takenAt: "2026-11-20T00:00:00.000Z",
  durationSec: 30,
  shiftSec: 0,
  feedEligible: true,
  jlptLevel: 5,
  deprecated: null,
  lines,
  ...extra,
});

describe("diffSnapshots", () => {
  it("is empty for identical snapshots", () => {
    const s = snap([line("あ"), line("い")]);
    const d = diffSnapshots(s, s);
    assert.equal(d.empty, true);
    assert.deepEqual(d.lines, []);
  });

  it("finds an inserted line without touching its neighbours", () => {
    const d = diffSnapshots(snap([line("あ"), line("う")]), snap([line("あ"), line("い"), line("う")]));
    assert.deepEqual(
      d.lines.map((c) => c.kind),
      ["added"],
    );
    assert.equal(d.lines[0].kind === "added" && d.lines[0].afterIndex, 1);
  });

  it("pairs an edited line as a change, not a remove plus an add", () => {
    const d = diffSnapshots(snap([line("あ"), line("いい")]), snap([line("あ"), line("いいね")]));
    assert.equal(d.lines.length, 1);
    const c = d.lines[0];
    assert.equal(c.kind, "changed");
    assert.equal(c.kind === "changed" && c.jaBefore, "いい");
  });

  it("reports English, readings and timing moves past the threshold only", () => {
    const before = snap([line("今日", { tokens: [{ text: "今日", reading: "こんにち" }], start: 1, end: 2 })]);
    const after = snap([
      line("今日", {
        en: "Today",
        tokens: [{ text: "今日", reading: "きょう" }],
        start: 1.1, // under the threshold
        end: 2.6, // over it
      }),
    ]);
    const [c] = diffSnapshots(before, after).lines;
    assert.equal(c.kind, "changed");
    if (c.kind !== "changed") return;
    assert.deepEqual(c.en, { before: "今日 (en)", after: "Today" });
    assert.deepEqual(c.readings, [{ text: "今日", before: "こんにち", after: "きょう" }]);
    assert.deepEqual(c.timing?.after, { start: 1.1, end: 2.6 });
  });

  it("ignores timing jitter under the threshold", () => {
    const d = diffSnapshots(snap([line("あ")]), snap([line("あ", { start: 1.2, end: 1.9 })]));
    assert.equal(d.empty, true);
  });

  it("reports a resplit instead of readings when the token split differs", () => {
    const d = diffSnapshots(
      snap([line("食べた", { tokens: [{ text: "食べた" }] })]),
      snap([line("食べた", { tokens: [{ text: "食べ" }, { text: "た" }] })]),
    );
    const [c] = d.lines;
    assert.equal(c.kind === "changed" && c.split?.after, "食べ | た");
    assert.equal(c.kind === "changed" && c.readings, undefined);
  });

  it("lists unequal stretches as removals and additions, and clip field changes", () => {
    const d = diffSnapshots(
      snap([line("あ"), line("い")], { shiftSec: 0 }),
      snap([line("か"), line("き"), line("く")], { shiftSec: -0.2, deprecated: "broken" }),
    );
    assert.deepEqual(
      d.lines.map((c) => c.kind),
      ["removed", "removed", "added", "added", "added"],
    );
    assert.deepEqual(
      d.fields.map((f) => f.field),
      ["shiftSec", "deprecated"],
    );
  });
});
