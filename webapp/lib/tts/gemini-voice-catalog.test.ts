import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  GEMINI_LIBRARY_VOICES,
  GEMINI_VOICE_CATALOG,
  geminiVoiceEntry,
  geminiVoiceLabel,
  geminiVoiceSupportsModel,
} from "./gemini-voice-catalog";
import { GEMINI_VOICE_CHARACTER_NAMES } from "./gemini-voice-names";
import { GEMINI_TTS_VOICES } from "./gemini-voices";
import { voiceTakeObjectKey, voiceTakesManifestKey } from "./voice-takes";

describe("gemini voice catalog", () => {
  it("has the 30 Studio voices plus 73 ja-JP Tokyo library voices, unique", () => {
    const studio = GEMINI_VOICE_CATALOG.filter((v) => v.source === "studio").map((v) => v.voice);
    assert.deepEqual([...studio].sort(), [...GEMINI_TTS_VOICES].sort());
    assert.equal(GEMINI_LIBRARY_VOICES.length, 73);
    assert.ok(GEMINI_LIBRARY_VOICES.every((v) => v.languageCode === "ja-JP" && v.accent === "Tokyo Japanese"));
    assert.equal(new Set(GEMINI_VOICE_CATALOG.map((v) => v.voice)).size, GEMINI_VOICE_CATALOG.length);
  });

  it("gives every library voice a distinct casting name", () => {
    const names = GEMINI_LIBRARY_VOICES.map((v) => v.characterName);
    assert.ok(names.every(Boolean), "library voice missing a character name");
    assert.equal(new Set(names).size, names.length);
    assert.equal(new Set(GEMINI_LIBRARY_VOICES.map((v) => v.characterNameJa)).size, names.length);
    assert.ok(Object.keys(GEMINI_VOICE_CHARACTER_NAMES).every((id) => geminiVoiceEntry(id)?.source === "library"));
    assert.equal(
      geminiVoiceLabel("ja-jp-advisor-2"),
      "Misaki 美咲 · F 37 · Doctor (Authoritative Advisor 2)"
    );
  });

  it("gates library voices to 3.8 TTS models", () => {
    const lib = GEMINI_LIBRARY_VOICES[0].voice;
    assert.equal(geminiVoiceSupportsModel(lib, "gemini-3.8-flash-tts"), true);
    assert.equal(geminiVoiceSupportsModel(lib, "gemini-3.8-flash-lite-tts"), true);
    assert.equal(geminiVoiceSupportsModel(lib, "gemini-3.1-flash-tts-preview"), false);
    assert.equal(geminiVoiceSupportsModel("Puck", "gemini-3.1-flash-tts-preview"), true);
    assert.equal(geminiVoiceLabel("Puck"), "Puck");
    assert.match(geminiVoiceLabel(lib), / · [FMN]/);
  });

  it("keeps voice takes under one model prefix", () => {
    assert.equal(voiceTakeObjectKey("Puck", 2), "tts/voice-takes/gemini-3.8-flash-tts/Puck/take-2.wav");
    assert.equal(voiceTakesManifestKey(), "tts/voice-takes/gemini-3.8-flash-tts/manifest.json");
  });
});
