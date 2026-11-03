// Gemini voice catalog with metadata from the Extended Voice Library.
// Client-safe. "studio" = the 30 prebuilt voices Studio has always offered
// (work on 3.1 and 3.8); "library" = ja-JP Tokyo-accent library voices, which
// only 3.8+ TTS accepts (3.1 answers "No matching speaker voice found").

import { usesSpeechMetadata } from "../gemini/models";
import { GENERATED_GEMINI_VOICE_CATALOG } from "./gemini-voice-catalog.generated";

export type GeminiVoiceCatalogEntry = {
  /** Value sent as prebuiltVoiceConfig.voiceName and stored on projects. */
  voice: string;
  displayName: string;
  source: "studio" | "library";
  languageCode: string;
  accent: string;
  gender: string;
  ageYears: number | null;
  pitch: string;
  persona: string;
  context: string;
  description: string;
};

export const GEMINI_VOICE_CATALOG: readonly GeminiVoiceCatalogEntry[] =
  GENERATED_GEMINI_VOICE_CATALOG;

export const GEMINI_LIBRARY_VOICES = GEMINI_VOICE_CATALOG.filter(
  (entry) => entry.source === "library"
);

const BY_VOICE = new Map(GEMINI_VOICE_CATALOG.map((entry) => [entry.voice, entry]));

export function geminiVoiceEntry(voice: string): GeminiVoiceCatalogEntry | undefined {
  return BY_VOICE.get(voice);
}

/** Library voices need the 3.8 TTS schema; Studio's 30 work everywhere. */
export function geminiVoiceSupportsModel(voice: string, model: string): boolean {
  const entry = BY_VOICE.get(voice);
  if (!entry || entry.source === "studio") return true;
  return usesSpeechMetadata(model);
}

/** Short label for pickers, e.g. "Tutor 3 · F 28" or "Puck". */
export function geminiVoiceLabel(voice: string): string {
  const entry = BY_VOICE.get(voice);
  if (!entry || entry.source === "studio") return voice;
  const gender = entry.gender === "female" ? "F" : entry.gender === "male" ? "M" : "N";
  return `${entry.displayName} · ${gender}${entry.ageYears ? ` ${entry.ageYears}` : ""}`;
}
