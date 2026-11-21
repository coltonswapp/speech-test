/**
 * What changed between two clip snapshots (snapshot.ts), for the attempt cards
 * in Studio. Lines are matched by their Japanese text (LCS); within a stretch
 * of unmatched lines, equal numbers of removed and added lines pair up as
 * edits. Pure; nothing stores the diff.
 */
import type { ClipSnapshot, SnapshotLine, SnapshotToken } from "@/lib/clip-agent/snapshot";

/** A line whose start or end moved at least this far counts as retimed. */
export const TIMING_MOVE_SEC = 0.25;

export type FieldChange = {
  field: "shiftSec" | "feedEligible" | "jlptLevel" | "deprecated" | "durationSec";
  before: string | number | boolean | null;
  after: string | number | boolean | null;
};

export type ReadingChange = { text: string; before: string | null; after: string | null };

export type LineChange =
  | { kind: "added"; afterIndex: number; ja: string; en: string | null }
  | { kind: "removed"; beforeIndex: number; ja: string; en: string | null }
  | {
      kind: "changed";
      beforeIndex: number;
      afterIndex: number;
      ja: string;
      /** Set when the Japanese text itself was edited (an unmatched pair). */
      jaBefore?: string;
      en?: { before: string | null; after: string | null };
      /** Token split changed: surfaces joined with " | ". */
      split?: { before: string; after: string };
      /** Same split, different readings. */
      readings?: ReadingChange[];
      timing?: {
        before: { start: number | null; end: number | null };
        after: { start: number | null; end: number | null };
      };
    };

export type ClipSnapshotDiff = {
  fields: FieldChange[];
  lines: LineChange[];
  /** True when nothing a learner sees changed. */
  empty: boolean;
};

const FIELDS: FieldChange["field"][] = [
  "shiftSec",
  "feedEligible",
  "jlptLevel",
  "deprecated",
  "durationSec",
];

/** Index pairs of the longest common subsequence of `a` and `b`. */
function lcsPairs(a: string[], b: string[]): Array<[number, number]> {
  const n = a.length;
  const m = b.length;
  const dp = Array.from({ length: n + 1 }, () => new Uint32Array(m + 1));
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      dp[i][j] = a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
    }
  }
  const pairs: Array<[number, number]> = [];
  let i = 0;
  let j = 0;
  while (i < n && j < m) {
    if (a[i] === b[j]) {
      pairs.push([i, j]);
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return pairs;
}

const splitOf = (tokens: SnapshotToken[]) => tokens.map((t) => t.text).join(" | ");

const moved = (a: number | null, b: number | null) =>
  a === null || b === null ? a !== b : Math.abs(a - b) >= TIMING_MOVE_SEC;

/** Changes within a line pair, or null when the learner would see no difference. */
function compareLines(
  before: SnapshotLine,
  after: SnapshotLine,
  beforeIndex: number,
  afterIndex: number,
): LineChange | null {
  const change: Extract<LineChange, { kind: "changed" }> = {
    kind: "changed",
    beforeIndex,
    afterIndex,
    ja: after.ja,
  };
  let any = false;
  if (before.ja !== after.ja) {
    change.jaBefore = before.ja;
    any = true;
  }
  if (before.en !== after.en) {
    change.en = { before: before.en, after: after.en };
    any = true;
  }
  const bt = before.tokens ?? [];
  const at = after.tokens ?? [];
  if (splitOf(bt) !== splitOf(at)) {
    change.split = { before: splitOf(bt), after: splitOf(at) };
    any = true;
  } else {
    const readings = bt
      .map((token, i) => ({
        text: token.text,
        before: token.reading ?? null,
        after: at[i]?.reading ?? null,
      }))
      .filter((r) => r.before !== r.after);
    if (readings.length) {
      change.readings = readings;
      any = true;
    }
  }
  if (moved(before.start, after.start) || moved(before.end, after.end)) {
    change.timing = {
      before: { start: before.start, end: before.end },
      after: { start: after.start, end: after.end },
    };
    any = true;
  }
  return any ? change : null;
}

export function diffSnapshots(before: ClipSnapshot, after: ClipSnapshot): ClipSnapshotDiff {
  const fields: FieldChange[] = [];
  for (const field of FIELDS) {
    const a = before[field];
    const b = after[field];
    const same = typeof a === "number" && typeof b === "number" ? Math.abs(a - b) < 0.001 : a === b;
    if (!same) fields.push({ field, before: a, after: b });
  }

  const lines: LineChange[] = [];
  const pairs = lcsPairs(
    before.lines.map((l) => l.ja),
    after.lines.map((l) => l.ja),
  );
  let i = 0;
  let j = 0;
  // A sentinel pair past both ends flushes the last gap.
  for (const [pi, pj] of [...pairs, [before.lines.length, after.lines.length] as [number, number]]) {
    const removed = Array.from({ length: pi - i }, (_, k) => i + k);
    const added = Array.from({ length: pj - j }, (_, k) => j + k);
    if (removed.length > 0 && removed.length === added.length) {
      removed.forEach((bi, k) => {
        const change = compareLines(before.lines[bi], after.lines[added[k]], bi, added[k]);
        if (change) lines.push(change);
      });
    } else {
      for (const bi of removed) {
        lines.push({ kind: "removed", beforeIndex: bi, ja: before.lines[bi].ja, en: before.lines[bi].en });
      }
      for (const aj of added) {
        lines.push({ kind: "added", afterIndex: aj, ja: after.lines[aj].ja, en: after.lines[aj].en });
      }
    }
    if (pi < before.lines.length) {
      const change = compareLines(before.lines[pi], after.lines[pj], pi, pj);
      if (change) lines.push(change);
    }
    i = pi + 1;
    j = pj + 1;
  }

  return { fields, lines, empty: fields.length === 0 && lines.length === 0 };
}
