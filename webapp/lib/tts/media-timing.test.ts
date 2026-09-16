import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { stampMediaTimeNow, wallDelayToMediaSeconds } from "./media-timing";

describe("wallDelayToMediaSeconds", () => {
  it("scales wall-clock latency by playback rate into media time", () => {
    assert.equal(wallDelayToMediaSeconds(0.08, 1), 0.08);
    assert.equal(wallDelayToMediaSeconds(0.08, 0.5), 0.04);
    assert.equal(wallDelayToMediaSeconds(0.08, 1.5), 0.12);
  });

  it("treats non-positive or non-finite wall delay as zero", () => {
    assert.equal(wallDelayToMediaSeconds(0, 0.5), 0);
    assert.equal(wallDelayToMediaSeconds(-0.1, 1), 0);
    assert.equal(wallDelayToMediaSeconds(Number.NaN, 1), 0);
  });

  it("falls back to 1× when playback rate is invalid", () => {
    assert.equal(wallDelayToMediaSeconds(0.1, 0), 0.1);
    assert.equal(wallDelayToMediaSeconds(0.1, -1), 0.1);
    assert.equal(wallDelayToMediaSeconds(0.1, Number.NaN), 0.1);
  });
});

describe("stampMediaTimeNow", () => {
  it("returns the media clock unchanged when paused (no latency pull-back)", () => {
    assert.equal(
      stampMediaTimeNow({
        mediaCurrentTime: 1.25,
        isPlaying: false,
        playbackRate: 0.5,
        wallLatencySeconds: 0.08,
      }),
      1.25
    );
  });

  it("subtracts rate-scaled wall latency while playing", () => {
    assert.equal(
      stampMediaTimeNow({
        mediaCurrentTime: 1.0,
        isPlaying: true,
        playbackRate: 1,
        wallLatencySeconds: 0.08,
      }),
      0.92
    );
    assert.equal(
      stampMediaTimeNow({
        mediaCurrentTime: 1.0,
        isPlaying: true,
        playbackRate: 0.5,
        wallLatencySeconds: 0.08,
      }),
      0.96
    );
    assert.equal(
      stampMediaTimeNow({
        mediaCurrentTime: 1.0,
        isPlaying: true,
        playbackRate: 1.5,
        wallLatencySeconds: 0.08,
      }),
      0.88
    );
  });

  it("keeps Apple-touch native path (zero latency) equal to the media clock", () => {
    assert.equal(
      stampMediaTimeNow({
        mediaCurrentTime: 2.5,
        isPlaying: true,
        playbackRate: 0.5,
        wallLatencySeconds: 0,
      }),
      2.5
    );
  });

  it("clamps non-finite or negative media time to zero", () => {
    assert.equal(
      stampMediaTimeNow({
        mediaCurrentTime: Number.NaN,
        isPlaying: true,
        playbackRate: 1,
        wallLatencySeconds: 0.1,
      }),
      0
    );
    assert.equal(
      stampMediaTimeNow({
        mediaCurrentTime: -0.5,
        isPlaying: false,
        playbackRate: 1,
        wallLatencySeconds: 0,
      }),
      0
    );
  });
});
