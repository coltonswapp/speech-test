import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  buildGeminiConversationPayload,
  deliveryForSpeech,
} from "./gemini-tts-request";
import { geminiAudioToPcm16, pcm16ToWav, wavToPcm16 } from "./wav";

const lines = [
  { speaker: "speaker1" as const, text: "すみません。", delivery: "[warmly]" },
  { speaker: "speaker2" as const, text: " 大丈夫です。", delivery: "[laughs]" },
  { speaker: "speaker1" as const, text: "よかった。" },
];
const labels = { speaker1: "Kaito", speaker2: "Mika" };

describe("deliveryForSpeech", () => {
  it("routes mood tags to style and sound tags to inline events", () => {
    assert.deepEqual(deliveryForSpeech("[warmly]"), { style: "warmly", events: [] });
    assert.deepEqual(deliveryForSpeech("[laughs]"), { events: ["<laugh>"] });
    assert.deepEqual(deliveryForSpeech("[softly] [sighs]"), {
      style: "softly",
      events: ["<sigh>"],
    });
    assert.deepEqual(deliveryForSpeech("  "), { events: [] });
    assert.deepEqual(deliveryForSpeech("a little shy"), { style: "a little shy", events: [] });
  });
});

describe("buildGeminiConversationPayload", () => {
  it("3.8: one part per turn, verbatim text, speaker + style metadata", () => {
    const payload = buildGeminiConversationPayload({
      model: "gemini-3.8-flash-tts",
      lines,
      labels,
      speaker1Voice: "Orus",
      speaker2Voice: "Despina",
    });
    assert.deepEqual(payload.contents[0].parts, [
      { text: "すみません。", speechMetadata: { speaker: "Kaito", style: "warmly" } },
      { text: "<laugh> 大丈夫です。", speechMetadata: { speaker: "Mika" } },
      { text: "よかった。", speechMetadata: { speaker: "Kaito" } },
    ]);
    assert.equal("temperature" in payload.generationConfig, false);
    const json = JSON.stringify(payload.contents);
    assert.equal(json.includes("Kaito:"), false);
    assert.equal(json.includes("TTS dialogue"), false);
  });

  it("3.1: keeps the legacy single transcript block", () => {
    const payload = buildGeminiConversationPayload({
      model: "gemini-3.1-flash-tts-preview",
      lines,
      labels,
      speaker1Voice: "Orus",
      speaker2Voice: "Despina",
    });
    const parts = payload.contents[0].parts as Array<{ text: string }>;
    assert.equal(parts.length, 1);
    assert.match(parts[0].text, /^TTS dialogue\./);
    assert.match(parts[0].text, /Kaito: \[warmly\] すみません。/);
    assert.equal(payload.generationConfig.temperature, 1);
  });
});

describe("geminiAudioToPcm16", () => {
  it("returns only the data chunk when a chunk follows it (3.8 C2PA)", () => {
    const pcm = Buffer.from([1, 0, 2, 0, 3, 0]);
    const wav = pcm16ToWav(pcm, 24_000);
    const trailer = Buffer.alloc(8 + 6);
    trailer.write("C2PA", 0, "ascii");
    trailer.writeUInt32LE(6, 4);
    const withTrailer = Buffer.concat([wav, trailer]);
    withTrailer.writeUInt32LE(withTrailer.length - 8, 4);
    assert.deepEqual(geminiAudioToPcm16(withTrailer), pcm);
    assert.deepEqual(wavToPcm16(withTrailer), { pcm, sampleRate: 24_000 });
  });

  it("passes raw PCM (3.1) through", () => {
    const pcm = Buffer.from([9, 0, 8, 0]);
    assert.deepEqual(geminiAudioToPcm16(pcm), pcm);
  });
});
