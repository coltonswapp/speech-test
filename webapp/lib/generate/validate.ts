import {
  geminiVoiceEntry,
  geminiVoiceSupportsModel,
} from "@/lib/tts/gemini-voice-catalog";
import type { GenerateLineInput } from "./types";
import { GENERATE_MAX_LINES } from "./types";

export class GenerateUserError extends Error {
  constructor(
    message: string,
    readonly status: number = 400,
  ) {
    super(message);
    this.name = "GenerateUserError";
  }
}

export function validateGenerateLines(
  lines: GenerateLineInput[],
  model: string,
): GenerateLineInput[] {
  if (lines.length === 0) {
    throw new GenerateUserError("Add at least one line.");
  }
  if (lines.length > GENERATE_MAX_LINES) {
    throw new GenerateUserError(`Keep it to ${GENERATE_MAX_LINES} lines.`);
  }
  return lines.map((line, index) => {
    const text = line.text.trim();
    if (!text) {
      throw new GenerateUserError(`Line ${index + 1} is empty.`);
    }
    const entry = geminiVoiceEntry(line.voice);
    if (!entry) {
      throw new GenerateUserError(
        `Unknown voice “${line.voice}”. Pick one from the Studio voice library.`,
      );
    }
    if (!geminiVoiceSupportsModel(line.voice, model)) {
      throw new GenerateUserError(
        `${line.voice} needs 3.8 TTS. Switch the model in Settings → Voices.`,
      );
    }
    return {
      ...line,
      text,
      delivery: line.delivery?.trim() || undefined,
      pauseAfterSeconds: line.pauseAfterSeconds ?? 0,
    };
  });
}
