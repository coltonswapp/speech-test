import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { pcm16ToWav } from "@/lib/tts/wav";
import {
  composeLinePcm,
  generationContentHash,
  isMpegAudio,
  silencePcm16,
  splitTranscript,
} from "./compose";

const RATE = 24_000;

function pcm(samples: number, value = 1000): Buffer {
  const buf = Buffer.alloc(samples * 2);
  for (let i = 0; i < samples; i++) buf.writeInt16LE(value, i * 2);
  return buf;
}

describe("composeLinePcm", () => {
  it("keeps a single line effortless: no trailing pause", () => {
    const clip = pcm(RATE); // 1s
    const composed = composeLinePcm(
      [{ line: { id: "1", text: "hello", voice: "Kore" }, pcm: clip }],
      RATE,
    );
    assert.equal(composed.durationSeconds, 1);
    assert.equal(composed.lineTimings.length, 1);
    assert.equal(composed.lineTimings[0].pauseAfterSeconds, 0);
    assert.deepEqual(composed.markSamples, []);
  });

  it("inserts exact silence between lines so timing matches the playable file", () => {
    const a = pcm(RATE); // 1s
    const b = pcm(RATE / 2); // 0.5s
    const composed = composeLinePcm(
      [
        {
          line: {
            id: "1",
            text: "one",
            voice: "Kore",
            pauseAfterSeconds: 0.25,
          },
          pcm: a,
        },
        { line: { id: "2", text: "two", voice: "Puck" }, pcm: b },
      ],
      RATE,
    );
    assert.equal(composed.durationSeconds, 1.75);
    assert.equal(composed.lineTimings[0].startSeconds, 0);
    assert.equal(composed.lineTimings[0].endSeconds, 1);
    assert.equal(composed.lineTimings[1].startSeconds, 1.25);
    assert.equal(composed.lineTimings[1].endSeconds, 1.75);
    assert.deepEqual(composed.markSamples, [Math.round(1.25 * RATE)]);
    const pause = composed.pcm.subarray(RATE * 2, RATE * 2 + Math.round(0.25 * RATE) * 2);
    assert.ok(pause.every((byte) => byte === 0));
  });
});

describe("isMpegAudio", () => {
  it("accepts ID3 and frame-sync, rejects WAV bytes", () => {
    assert.equal(isMpegAudio(Buffer.from("ID3....")), true);
    assert.equal(isMpegAudio(Buffer.from([0xff, 0xfb, 0x90, 0x00])), true);
    const wav = pcm16ToWav(silencePcm16(RATE, 0.05), RATE);
    assert.equal(isMpegAudio(wav), false);
  });
});

describe("generationContentHash", () => {
  it("changes when pause or voice changes", () => {
    const base = {
      kind: "tts" as const,
      model: "gemini-3.8-flash-tts",
      lines: [{ text: "a", voice: "Kore", pauseAfterSeconds: 0.4 }],
    };
    const paused = generationContentHash({
      ...base,
      lines: [{ text: "a", voice: "Kore", pauseAfterSeconds: 1 }],
    });
    assert.notEqual(generationContentHash(base), paused);
  });
});

describe("splitTranscript", () => {
  it("drops blank lines", () => {
    assert.deepEqual(splitTranscript("a\n\n  b  \n"), ["a", "b"]);
  });
});
