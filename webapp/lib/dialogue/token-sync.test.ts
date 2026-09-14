import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  clearStampsFrom,
  seekSecondsBeforeToken,
  type LineWindow,
} from "./token-sync";
import type { VariantTokenSync } from "./types";

function syncWithTimes(
  times: Array<number | null>
): VariantTokenSync {
  return {
    version: 1,
    contentHash: "hash",
    lines: [
      {
        text: times.map((_, i) => `t${i}`).join(""),
        tokens: times.map((startSeconds, i) => ({
          text: `t${i}`,
          startSeconds,
        })),
      },
    ],
  };
}

describe("clearStampsFrom", () => {
  it("clears from the cut token onward and leaves earlier stamps", () => {
    const sync = syncWithTimes([0.1, 0.4, 0.7, 1.0]);
    const next = clearStampsFrom(sync, 0, 2);
    assert.deepEqual(
      next.lines[0].tokens.map((token) => token.startSeconds),
      [0.1, 0.4, null, null]
    );
  });

  it("re-seeds the first token from the line mark when clearing from index 0", () => {
    const sync = syncWithTimes([0.1, 0.4, 0.7]);
    const next = clearStampsFrom(sync, 0, 0, 0.05);
    assert.deepEqual(
      next.lines[0].tokens.map((token) => token.startSeconds),
      [0.05, null, null]
    );
  });

  it("is a no-op when tokens at/after the cut are already untimed", () => {
    const sync = syncWithTimes([0.1, null, null]);
    const next = clearStampsFrom(sync, 0, 1);
    assert.equal(next, sync);
  });
});

describe("seekSecondsBeforeToken", () => {
  const windows: LineWindow[] = [{ start: 0.05, end: 2 }];

  it("prefers the token two before the cut when enough stamps exist", () => {
    const sync = syncWithTimes([0.1, 0.4, 0.7, 1.0]);
    assert.equal(seekSecondsBeforeToken(sync, 0, 3, windows), 0.4);
  });

  it("falls back to line start at the first token", () => {
    const sync = syncWithTimes([0.1, 0.4, 0.7]);
    assert.equal(seekSecondsBeforeToken(sync, 0, 0, windows), 0.05);
  });

  it("falls back to line start when fewer than two earlier stamps exist", () => {
    const sync = syncWithTimes([0.1, null, 0.7]);
    assert.equal(seekSecondsBeforeToken(sync, 0, 1, windows), 0.05);
  });
});
