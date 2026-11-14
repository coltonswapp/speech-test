import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { GEMINI_TTS_VOICES } from "@/lib/tts/gemini-voices";
import { GEMINI_LIBRARY_VOICES } from "@/lib/tts/gemini-voice-catalog";
import { GenerateUserError, validateGenerateLines } from "./validate";

describe("validateGenerateLines", () => {
  it("accepts a real Studio voice on 3.8 Flash TTS", () => {
    const lines = validateGenerateLines(
      [{ id: "1", text: "こんにちは", voice: GEMINI_TTS_VOICES[0] }],
      "gemini-3.8-flash-tts",
    );
    assert.equal(lines[0].voice, GEMINI_TTS_VOICES[0]);
  });

  it("rejects unknown voices", () => {
    assert.throws(
      () =>
        validateGenerateLines(
          [{ id: "1", text: "hi", voice: "NotARealVoice" }],
          "gemini-3.8-flash-tts",
        ),
      GenerateUserError,
    );
  });

  it("rejects a library voice on the legacy 3.1 model", () => {
    const library = GEMINI_LIBRARY_VOICES[0];
    assert.ok(library);
    assert.throws(
      () =>
        validateGenerateLines(
          [{ id: "1", text: "はい", voice: library.voice }],
          "gemini-3.1-flash-tts-preview",
        ),
      /3\.8 TTS/,
    );
  });
});
