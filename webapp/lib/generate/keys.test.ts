import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  assertGenerateObjectKey,
  generateMp3Key,
  generateWavKey,
  isGenerateObjectKey,
} from "./keys";

describe("generate R2 keys", () => {
  it("stays under tts/generate and scopes files to an attempt", () => {
    const id = "11111111-1111-1111-1111-111111111111";
    assert.equal(generateWavKey(id, 0), `tts/generate/${id}/0/audio.wav`);
    assert.equal(generateMp3Key(id, 2), `tts/generate/${id}/2/audio.mp3`);
    assert.notEqual(generateWavKey(id, 0), generateWavKey(id, 1));
    assert.equal(isGenerateObjectKey(generateWavKey(id, 0)), true);
    assert.equal(isGenerateObjectKey("tts/abc/variants/x.wav"), false);
    assert.equal(isGenerateObjectKey("tts/voice-takes/x.wav"), false);
    assert.equal(isGenerateObjectKey("dialogue/n5/scene.m4a"), false);
  });

  it("refuses path traversal", () => {
    assert.throws(() => assertGenerateObjectKey("tts/generate/../variants/x.wav"));
    assert.throws(() => assertGenerateObjectKey("tts/projects/x.wav"));
    assert.throws(() => generateWavKey("11111111-1111-1111-1111-111111111111", -1));
  });
});
