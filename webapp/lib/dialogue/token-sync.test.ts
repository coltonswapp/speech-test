import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  clearStampsFrom,
  midpointSplitOffset,
  restampToken,
  seekSecondsBeforeToken,
  splitTokenAt,
  TOKEN_STAMP_LOOKBACK_SECONDS,
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

function gluedSync(): VariantTokenSync {
  return {
    version: 1,
    contentHash: "hash",
    lines: [
      {
        text: "今日はいい天気",
        tokens: [
          { text: "今日は", startSeconds: 0.1 },
          { text: "いい天気", startSeconds: 0.5 },
        ],
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

describe("restampToken playback-rate lookback", () => {
  it("scales tap lookback into media time so 0.5× does not double-count wall lag", () => {
    const sync = syncWithTimes([null, null]);
    const atOne = restampToken(sync, 0, 0, 1.0, null, 1);
    const atHalf = restampToken(sync, 0, 0, 1.0, null, 0.5);
    assert.equal(atOne.lines[0].tokens[0].startSeconds, 1.0 - TOKEN_STAMP_LOOKBACK_SECONDS);
    assert.equal(
      atHalf.lines[0].tokens[0].startSeconds,
      1.0 - TOKEN_STAMP_LOOKBACK_SECONDS * 0.5
    );
    // Same media playhead + same perceived onset: half-speed stamp is later than
    // the over-subtracted 1× lookback would have been (invariant vs rate).
    assert.ok(
      (atHalf.lines[0].tokens[0].startSeconds ?? 0) >
        (atOne.lines[0].tokens[0].startSeconds ?? 0)
    );
  });

  it("keeps 1.5× lookback proportional so fast playback still tracks onset", () => {
    const sync = syncWithTimes([null]);
    const atFast = restampToken(sync, 0, 0, 2.0, null, 1.5);
    assert.equal(
      atFast.lines[0].tokens[0].startSeconds,
      2.0 - TOKEN_STAMP_LOOKBACK_SECONDS * 1.5
    );
  });
});

describe("midpointSplitOffset", () => {
  it("returns null for a single grapheme", () => {
    assert.equal(midpointSplitOffset("あ"), null);
  });

  it("splits even-length surfaces in half", () => {
    assert.equal(midpointSplitOffset("abcd"), 2);
    assert.equal(midpointSplitOffset("今日は天気"), 2); // 2 of 5 CJK chars
  });
});

describe("splitTokenAt", () => {
  it("keeps the left stamp and clears from the right half onward", () => {
    const sync = gluedSync();
    const next = splitTokenAt(sync, 0, 1, 2); // "いい" | "天気"
    assert.deepEqual(
      next.lines[0].tokens.map((token) => token.text),
      ["今日は", "いい", "天気"]
    );
    assert.deepEqual(
      next.lines[0].tokens.map((token) => token.startSeconds),
      // Left half of the split keeps the original stamp; right half is cleared.
      [0.1, 0.5, null]
    );
  });

  it("preserves the left stamp when splitting a stamped glued token", () => {
    const sync = gluedSync();
    const next = splitTokenAt(sync, 0, 0, midpointSplitOffset("今日は")!);
    assert.equal(next.lines[0].tokens[0].text, "今");
    assert.equal(next.lines[0].tokens[0].startSeconds, 0.1);
    assert.equal(next.lines[0].tokens[1].text, "日は");
    assert.equal(next.lines[0].tokens[1].startSeconds, null);
    // Later stamps cleared from the split point onward.
    assert.equal(next.lines[0].tokens[2].startSeconds, null);
  });

  it("is a no-op for invalid offsets", () => {
    const sync = gluedSync();
    assert.equal(splitTokenAt(sync, 0, 0, 0), sync);
    assert.equal(splitTokenAt(sync, 0, 0, 99), sync);
  });
});
