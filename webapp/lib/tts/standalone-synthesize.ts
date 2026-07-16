// Single-voice synthesis for use in standalone scripts run outside the
// Next.js runtime — lib/tts/openai.ts and lib/tts/gemini-tts.ts both import
// "server-only" (via lib/secrets.ts), which throws when required from a
// plain Node process via tsx. Mirrors lib/db/standalone-client.ts.

function requiredEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`${name} is not set`);
  }
  return value;
}

export async function synthesizeOpenAIStandalone(params: {
  text: string;
  voice: string;
  model?: string;
}): Promise<Buffer> {
  const apiKey = requiredEnv("OPENAI_API_KEY");

  const response = await fetch("https://api.openai.com/v1/audio/speech", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: params.model ?? "gpt-4o-mini-tts",
      voice: params.voice,
      input: params.text,
      response_format: "pcm",
    }),
  });

  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new Error(`OpenAI request failed (HTTP ${response.status}): ${body}`);
  }

  return Buffer.from(await response.arrayBuffer());
}

export const OPENAI_STANDALONE_SAMPLE_RATE = 24_000;

/** Strips a 44-byte WAV header if the response happens to be WAV-wrapped. */
function stripWavHeaderIfPresent(data: Buffer): Buffer {
  if (data.length > 44 && data.toString("ascii", 0, 4) === "RIFF") {
    return data.subarray(44);
  }
  return data;
}

export async function synthesizeGeminiSingleStandalone(params: {
  text: string;
  voice: string;
  model?: string;
}): Promise<Buffer> {
  const apiKey = requiredEnv("GEMINI_API_KEY");
  const model = params.model ?? "gemini-3.1-flash-tts-preview";

  const payload = {
    contents: [{ role: "user", parts: [{ text: params.text }] }],
    generationConfig: {
      responseModalities: ["AUDIO"],
      speechConfig: {
        voiceConfig: {
          prebuiltVoiceConfig: { voiceName: params.voice },
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
    throw new Error(`Gemini request failed (HTTP ${response.status}): ${body}`);
  }

  const json = await response.json();
  const parts = json?.candidates?.[0]?.content?.parts;
  if (!Array.isArray(parts)) {
    throw new Error("Gemini returned no audio data.");
  }

  for (const part of parts) {
    const base64 = part?.inlineData?.data;
    if (typeof base64 === "string" && base64.length > 0) {
      return stripWavHeaderIfPresent(Buffer.from(base64, "base64"));
    }
  }

  throw new Error("Gemini returned no audio data.");
}

export const GEMINI_STANDALONE_SAMPLE_RATE = 24_000;
