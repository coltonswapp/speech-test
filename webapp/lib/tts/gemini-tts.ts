import "server-only";
import { getProviderKey } from "@/lib/secrets";
import { GEMINI_TTS_DEFAULT_MODEL } from "@/lib/tts/gemini-voices";

// Port of TTSCore/Sources/TTSCore/GeminiTTS.swift — multi-speaker conversation
// synthesis via Gemini's generateContent API.

export { GEMINI_TTS_VOICES, GEMINI_TTS_DEFAULT_MODEL } from "@/lib/tts/gemini-voices";

export type ConversationSpeaker = "speaker1" | "speaker2";

const DEFAULT_SPEAKER_LABEL: Record<ConversationSpeaker, string> = {
  speaker1: "Speaker 1",
  speaker2: "Speaker 2",
};

export type ConversationDialogueLine = {
  speaker: ConversationSpeaker;
  text: string;
};

export class GeminiTTSError extends Error {}

/**
 * Labels used in the Gemini transcript + multiSpeakerVoiceConfig.speaker fields.
 * Prefer character names (Kaito/Mika) — generic "Speaker 1/2" is more prone to the
 * known multi-speaker voice-swap quirk on the first turn.
 */
function resolveSpeakerLabels(params: {
  speaker1Name?: string | null;
  speaker2Name?: string | null;
}): Record<ConversationSpeaker, string> {
  const raw1 = params.speaker1Name?.trim() || "";
  const raw2 = params.speaker2Name?.trim() || "";
  if (raw1 && raw2 && raw1.toLowerCase() !== raw2.toLowerCase()) {
    return { speaker1: raw1, speaker2: raw2 };
  }
  return { ...DEFAULT_SPEAKER_LABEL };
}

function buildTranscript(
  lines: ConversationDialogueLine[],
  labels: Record<ConversationSpeaker, string>
): string {
  const body = lines
    .map((line) => `${labels[line.speaker]}: ${line.text.trim()}`)
    .join("\n");
  // Brief style cue helps Gemini keep voices attached to the right speaker.
  const cue = `TTS dialogue. ${labels.speaker1} uses voice A; ${labels.speaker2} uses voice B. Keep each speaker's voice consistent for every line.\n\n`;
  return `${cue}## Transcript:\n${body}`;
}

/** Strips a 44-byte WAV header if the response happens to be WAV-wrapped. */
function stripWavHeaderIfPresent(data: Buffer): Buffer {
  if (data.length > 44 && data.toString("ascii", 0, 4) === "RIFF") {
    return data.subarray(44);
  }
  return data;
}

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
  const transcript = buildTranscript(trimmedLines, labels);

  const payload = {
    contents: [
      {
        role: "user",
        parts: [{ text: transcript }],
      },
    ],
    generationConfig: {
      temperature: params.temperature ?? 1,
      responseModalities: ["AUDIO"],
      speechConfig: {
        multiSpeakerVoiceConfig: {
          speakerVoiceConfigs: [
            {
              speaker: labels.speaker1,
              voiceConfig: {
                prebuiltVoiceConfig: { voiceName: params.speaker1Voice },
              },
            },
            {
              speaker: labels.speaker2,
              voiceConfig: {
                prebuiltVoiceConfig: { voiceName: params.speaker2Voice },
              },
            },
          ],
        },
      },
    },
  };

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
  const parts = json?.candidates?.[0]?.content?.parts;
  if (!Array.isArray(parts)) {
    throw new GeminiTTSError("Gemini returned no audio data.");
  }

  for (const part of parts) {
    const base64 = part?.inlineData?.data;
    if (typeof base64 === "string" && base64.length > 0) {
      const audioData = Buffer.from(base64, "base64");
      return stripWavHeaderIfPresent(audioData);
    }
  }

  throw new GeminiTTSError("Gemini returned no audio data.");
}

export const GEMINI_TTS_SAMPLE_RATE = 24_000;
