import "server-only";
import { getProviderKey } from "@/lib/secrets";
import { GEMINI_TTS_DEFAULT_MODEL } from "@/lib/tts/gemini-voices";
import {
  buildGeminiConversationPayload,
  resolveSpeakerLabels,
  type ConversationDialogueLine,
} from "@/lib/tts/gemini-tts-request";
import { geminiAudioToPcm16 } from "@/lib/tts/wav";

// Multi-speaker conversation synthesis via Gemini's generateContent API.
// Request shape (3.1 transcript vs 3.8 speechMetadata) lives in
// gemini-tts-request.ts.

export { GEMINI_TTS_VOICES, GEMINI_TTS_DEFAULT_MODEL } from "@/lib/tts/gemini-voices";

export type {
  ConversationSpeaker,
  ConversationDialogueLine,
} from "@/lib/tts/gemini-tts-request";

export class GeminiTTSError extends Error {}

export async function synthesizeGeminiConversation(params: {
  lines: ConversationDialogueLine[];
  speaker1Voice: string;
  speaker2Voice: string;
  /** Display names used as Gemini speaker aliases (e.g. Kaito / Mika). */
  speaker1Name?: string | null;
  speaker2Name?: string | null;
  model?: string;
  temperature?: number;
}): Promise<Buffer> {
  const apiKey = getProviderKey("gemini");
  if (!apiKey) {
    throw new GeminiTTSError("Missing Gemini API key.");
  }

  const trimmedLines = params.lines.filter((l) => l.text.trim().length > 0);
  if (trimmedLines.length === 0) {
    throw new GeminiTTSError("Add at least one dialogue line.");
  }

  const model = params.model ?? GEMINI_TTS_DEFAULT_MODEL;
  const labels = resolveSpeakerLabels({
    speaker1Name: params.speaker1Name,
    speaker2Name: params.speaker2Name,
  });
  const payload = buildGeminiConversationPayload({
    model,
    lines: trimmedLines,
    labels,
    speaker1Voice: params.speaker1Voice,
    speaker2Voice: params.speaker2Voice,
    temperature: params.temperature,
  });

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: "POST",
      headers: {
        "x-goog-api-key": apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    }
  );

  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new GeminiTTSError(
      `Gemini request failed (HTTP ${response.status}): ${body}`
    );
  }

  const json = await response.json();
  const responseParts = json?.candidates?.[0]?.content?.parts;
  if (!Array.isArray(responseParts)) {
    throw new GeminiTTSError("Gemini returned no audio data.");
  }

  for (const part of responseParts) {
    const base64 = part?.inlineData?.data;
    if (typeof base64 === "string" && base64.length > 0) {
      // 3.8 returns WAV (with a trailing C2PA chunk); 3.1 returns raw PCM.
      return geminiAudioToPcm16(Buffer.from(base64, "base64"));
    }
  }

  throw new GeminiTTSError("Gemini returned no audio data.");
}

export const GEMINI_TTS_SAMPLE_RATE = 24_000;
