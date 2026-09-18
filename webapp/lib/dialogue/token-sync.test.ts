import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  applyTokenSelection,
  clearFlagsForLine,
  clearFlagsForReviewed,
  clearStampsFrom,
  midpointSplitOffset,
  publishedTokenSyncFromWorking,
  restampToken,
  seekSecondsBeforeToken,
  splitTokenAt,
  activeTokenAtTime,
  activeTokenIndexInLine,
  TOKEN_STAMP_LOOKBACK_SECONDS,
  type LineWindow,
} from "./token-sync";
import {
  publishedTokenSyncSchema,
  variantTokenSyncSchema,
  type VariantTokenSync,
} from "./types";

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

describe("tokenSync provenance (KA-1)", () => {
  const stamped: VariantTokenSync = {
    version: 1,
    contentHash: "hash",
    lines: [
      {
        text: "今日はいい天気",
        tokens: [
          { text: "今日は", startSeconds: 0.1, reading: "きょうは" },
          { text: "いい", startSeconds: 0.5, reading: "いい" },
          { text: "天気", startSeconds: 0.9, reading: "てんき" },
        ],
      },
    ],
  };
  const publishParams = {
    variantId: "v1",
    contentHash: "hash",
    spokenTexts: ["今日はいい天気"],
    windows: null,
    sampleRate: 24000,
  };

  it("working schema accepts source, alignerVersion, flags and readings", () => {
    const parsed = variantTokenSyncSchema.safeParse({
      ...stamped,
      source: "auto",
      alignerVersion: "mms-fa-1",
      flags: [
        { code: "stamp-in-silence", lineIndex: 0, tokenIndex: 1 },
        { code: "script-mismatch", lineIndex: 0, detail: "score 0.02" },
      ],
    });
    assert.ok(parsed.success);
    assert.equal(parsed.data.source, "auto");
    assert.equal(parsed.data.flags?.length, 2);
    assert.equal(parsed.data.lines[0].tokens[0].reading, "きょうは");
  });

  it("working schema still accepts a legacy sync with none of the new keys", () => {
    const legacy = {
      version: 1,
      contentHash: "hash",
      lines: [{ text: "はい", tokens: [{ text: "はい", startSeconds: null }] }],
    };
    const parsed = variantTokenSyncSchema.safeParse(legacy);
    assert.ok(parsed.success);
    assert.equal(parsed.data.source, undefined);
  });

  it("working schema rejects an unknown source or flag code", () => {
    assert.equal(
      variantTokenSyncSchema.safeParse({ ...stamped, source: "robot" }).success,
      false
    );
    assert.equal(
      variantTokenSyncSchema.safeParse({
        ...stamped,
        flags: [{ code: "made-up", lineIndex: 0 }],
      }).success,
      false
    );
  });

  it("clearFlagsForReviewed flips source and drops amber flags", () => {
    const reviewed = clearFlagsForReviewed({
      ...stamped,
      source: "auto",
      flags: [
        { code: "stamp-in-silence", lineIndex: 0, tokenIndex: 1 },
        { code: "no-gap", lineIndex: 1 },
      ],
    });
    assert.equal(reviewed.source, "reviewed");
    assert.equal("flags" in reviewed, false);
  });

  it("clearFlagsForLine drops one line and auto-reviews when none remain", () => {
    const withFlags: VariantTokenSync = {
      ...stamped,
      source: "auto",
      flags: [
        { code: "stamp-in-silence", lineIndex: 0, tokenIndex: 1 },
        { code: "no-gap", lineIndex: 1 },
      ],
    };
    const afterOne = clearFlagsForLine(withFlags, 0);
    assert.equal(afterOne.takeReviewed, false);
    assert.equal(afterOne.sync.source, "auto");
    assert.deepEqual(afterOne.sync.flags, [
      { code: "no-gap", lineIndex: 1 },
    ]);

    const afterLast = clearFlagsForLine(afterOne.sync, 1);
    assert.equal(afterLast.takeReviewed, true);
    assert.equal(afterLast.sync.source, "reviewed");
    assert.equal("flags" in afterLast.sync, false);
  });

  it("clearFlagsForLine is a no-op when the line has no flags", () => {
    const withFlags: VariantTokenSync = {
      ...stamped,
      source: "auto",
      flags: [{ code: "no-gap", lineIndex: 1 }],
    };
    const result = clearFlagsForLine(withFlags, 0);
    assert.equal(result.takeReviewed, false);
    assert.equal(result.sync, withFlags);
  });

  it("publish carries source and drops flags, alignerVersion and readings", () => {
    const published = publishedTokenSyncFromWorking({
      ...publishParams,
      sync: {
        ...stamped,
        source: "reviewed",
        alignerVersion: "mms-fa-1",
        flags: [{ code: "no-gap", lineIndex: 0 }],
      },
    });
    assert.ok(published);
    assert.equal(published.source, "reviewed");
    assert.equal("flags" in published, false);
    assert.equal("alignerVersion" in published, false);
    assert.deepEqual(Object.keys(published.lines[0].tokens[0]), [
      "text",
      "startSeconds",
    ]);
    assert.ok(publishedTokenSyncSchema.safeParse(published).success);
  });

  it("publish omits source when the working sync has none", () => {
    const published = publishedTokenSyncFromWorking({
      ...publishParams,
      sync: stamped,
    });
    assert.ok(published);
    assert.equal("source" in published, false);
  });

  it("applyTokenSelection keeps readings on tokens it does not touch", () => {
    // Re-select the middle token only; neighbours must survive intact.
    const next = applyTokenSelection(stamped, 0, 3, 5);
    // Selecting exactly an existing token is a no-op.
    assert.equal(next, null);
    const merged = applyTokenSelection(stamped, 0, 3, 7);
    assert.ok(merged);
    assert.deepEqual(merged.lines[0].tokens[0], {
      text: "今日は",
      startSeconds: 0.1,
      reading: "きょうは",
    });
    assert.equal(merged.lines[0].tokens[1].text, "いい天気");
    assert.equal(merged.lines[0].tokens[1].reading, undefined);
  });
});

describe("activeTokenAtTime", () => {
  const lines = [
    {
      tokens: [
        { startSeconds: 0.1 },
        { startSeconds: 0.5 },
        { startSeconds: 0.9 },
      ],
    },
    {
      tokens: [
        { startSeconds: 1.2 },
        { startSeconds: 1.6 },
        { startSeconds: null },
      ],
    },
  ];

  it("returns null before the first stamp", () => {
    assert.equal(activeTokenAtTime(lines, 0), null);
  });

  it("follows the latest started token across lines", () => {
    assert.deepEqual(activeTokenAtTime(lines, 0.5), {
      lineIndex: 0,
      tokenIndex: 1,
    });
    assert.deepEqual(activeTokenAtTime(lines, 1.0), {
      lineIndex: 0,
      tokenIndex: 2,
    });
    assert.deepEqual(activeTokenAtTime(lines, 1.4), {
      lineIndex: 1,
      tokenIndex: 0,
    });
    assert.deepEqual(activeTokenAtTime(lines, 2.0), {
      lineIndex: 1,
      tokenIndex: 1,
    });
  });
});

describe("activeTokenIndexInLine", () => {
  const tokens = [
    { startSeconds: 0.1 },
    { startSeconds: 0.5 },
    { startSeconds: 0.9 },
    { startSeconds: null },
  ];

  it("matches Token timing: latest start on this line at or before time", () => {
    assert.equal(activeTokenIndexInLine(tokens, 0), null);
    assert.equal(activeTokenIndexInLine(tokens, 0.1), 0);
    assert.equal(activeTokenIndexInLine(tokens, 0.49), 0);
    assert.equal(activeTokenIndexInLine(tokens, 0.5), 1);
    assert.equal(activeTokenIndexInLine(tokens, 2.0), 2);
  });
});
