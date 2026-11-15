import "server-only";
import { z } from "zod";
import { getProviderKey } from "@/lib/secrets";
import {
  geminiAsrModel,
  geminiGenerateContentUrl,
  geminiThinkingConfig,
} from "@/lib/gemini/text-model";
import type { GeminiTokenCounts } from "@/lib/experiments/clips/types";
import { geminiTokenCounts } from "@/lib/experiments/clips/usage";

export class ClipPipelineError extends Error {
  constructor(
    message: string,
    readonly status = 500
  ) {
    super(message);
    this.name = "ClipPipelineError";
  }
}

const ASR_PROMPT = `Transcribe the Japanese speech in this audio verbatim.

Rules:
- Write exactly what is spoken, in standard Japanese orthography (kanji and kana as a native subtitle would use). Do not summarize, correct grammar, or translate.
- Keep fillers and hesitations that are clearly spoken (えー, あの, まあ). Drop coughs, laughter, music and sound effects.
- Write numbers the way a Japanese subtitle would (e.g. 三つ, 2020年).
- Write English words and phrases the speaker says in katakana, as a Japanese subtitle would (Let's go → レッツゴー！, OK → オッケー). Never use the Latin alphabet.
- Split the transcript into sentences, one per array item, each ending with 。, ？ or ！ where natural. Keep the order they are spoken in.
- No speaker labels, timestamps, romaji or notes.
- If there is no Japanese speech, return an empty array.`;

const responseSchema = z.object({ sentences: z.array(z.string()) });

/** Gemini audio-in ASR. Returns one trimmed sentence per entry. */
export async function transcribeClipAudio(
  wav: Buffer,
  modelOverride?: string
): Promise<{ model: string; sentences: string[]; tokens: GeminiTokenCounts }> {
  const apiKey = getProviderKey("gemini");
  if (!apiKey) throw new ClipPipelineError("Missing Gemini API key.");
  const model = modelOverride ?? geminiAsrModel();
  const thinkingConfig = geminiThinkingConfig(model, "low");

  const response = await fetch(geminiGenerateContentUrl(model), {
    method: "POST",
    headers: { "x-goog-api-key": apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [
        {
          role: "user",
          parts: [
            { inlineData: { mimeType: "audio/wav", data: wav.toString("base64") } },
            { text: ASR_PROMPT },
          ],
        },
      ],
      generationConfig: {
        ...(thinkingConfig ? { thinkingConfig } : {}),
        responseMimeType: "application/json",
        responseSchema: {
          type: "object",
          properties: { sentences: { type: "array", items: { type: "string" } } },
          required: ["sentences"],
        },
      },
    }),
    // Pro can take over a minute on a 2-minute clip.
    signal: AbortSignal.timeout(240_000),
  });

  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new ClipPipelineError(
      `Gemini ASR failed (HTTP ${response.status}): ${body.slice(0, 500)}`,
      502
    );
  }
  const json = await response.json();
  const tokens = geminiTokenCounts(json);
  const raw = json?.candidates?.[0]?.content?.parts
    ?.map((part: { text?: string }) => part?.text ?? "")
    .join("");
  if (typeof raw !== "string" || raw.trim().length === 0) {
    throw new ClipPipelineError("Gemini returned no transcript.", 502);
  }
  let parsed;
  try {
    parsed = responseSchema.safeParse(JSON.parse(raw));
  } catch {
    throw new ClipPipelineError("Gemini transcript was not JSON.", 502);
  }
  if (!parsed.success) {
    throw new ClipPipelineError("Gemini transcript JSON was missing sentences.", 502);
  }
  return {
    model,
    tokens,
    sentences: parsed.data.sentences.map((s) => s.trim()).filter((s) => s.length > 0),
  };
}
