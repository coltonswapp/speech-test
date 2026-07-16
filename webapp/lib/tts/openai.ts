import "server-only";
import { getProviderKey } from "@/lib/secrets";

export class OpenAITTSError extends Error {}

/** Ports TextToSpeechService.swift's makeSynthesisRequest(.openAI) — returns raw 16-bit PCM 24kHz mono LE. */
export async function synthesizeOpenAI(params: {
  text: string;
  voice: string;
  model?: string;
  instructions?: string | null;
}): Promise<Buffer> {
  const apiKey = getProviderKey("openai");
  if (!apiKey) {
    throw new OpenAITTSError("Missing OpenAI API key.");
  }

  const payload: Record<string, unknown> = {
    model: params.model ?? "gpt-4o-mini-tts",
    voice: params.voice,
    input: params.text,
    response_format: "pcm",
  };
  if (params.instructions) {
    payload.instructions = params.instructions;
  }

  const response = await fetch("https://api.openai.com/v1/audio/speech", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new OpenAITTSError(
      `OpenAI request failed (HTTP ${response.status}): ${body}`
    );
  }

  const arrayBuffer = await response.arrayBuffer();
  return Buffer.from(arrayBuffer);
}

export const OPENAI_SAMPLE_RATE = 24_000;
