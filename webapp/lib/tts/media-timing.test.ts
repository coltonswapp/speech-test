import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { wallDelayToMediaSeconds } from "./media-timing";

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
