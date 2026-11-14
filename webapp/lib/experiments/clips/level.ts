import "server-only";
import { z } from "zod";
import { getProviderKey } from "@/lib/secrets";
import {
  geminiGenerateContentUrl,
  geminiTextModel,
  geminiThinkingConfig,
} from "@/lib/gemini/text-model";
import { ClipPipelineError } from "@/lib/experiments/clips/asr";
import type { GeminiTokenCounts } from "@/lib/experiments/clips/types";
import { geminiTokenCounts } from "@/lib/experiments/clips/usage";

const responseSchema = z.object({
  jlptLevel: z.number().int().min(1).max(5),
  reason: z.string(),
});

function buildPrompt(sentences: string[], secondsOfSpeech: number | null): string {
  const pace =
    secondsOfSpeech && secondsOfSpeech > 0
      ? `\nPace: ${sentences.join("").length} characters spoken in ${secondsOfSpeech.toFixed(1)} s.`
      : "";
  return `Rate how hard this Japanese video clip is for a learner who is listening to it with the transcript.

Answer with the JLPT level a learner needs to follow most of the clip (roughly 80% of the words and the grammar holding the sentences together):
- 5 = N5: very common words, short simple sentences, basic particles and です/ます or simple plain forms.
- 4 = N4: everyday vocabulary, て-form chains, simple conditionals, potential and giving/receiving forms.
- 3 = N3: natural everyday conversation, casual contractions, wider vocabulary, passive and causative, explanatory のだ.
- 2 = N2: abstract or topical vocabulary, long sentences, formal or written-style grammar, dense casual speech.
- 1 = N1: specialised, literary or idiomatic language, heavy slang or dialect, rare grammar.

Rules:
- Judge the clip as a whole, not its hardest word: one rare noun in an otherwise simple clip does not raise the level; several, or hard grammar throughout, do.
- Names, loanwords in katakana and fillers (えー, あの) are not difficulty.
- Fast, contracted or slurred casual speech is harder to follow than its vocabulary suggests; go one level harder when the transcript shows it.
- "reason": one short English sentence naming the words or grammar that set the level.

Transcript (one sentence per line):
${sentences.join("\n")}${pace}`;
}

/** One Gemini call over the whole transcript. */
export async function estimateClipLevel(
  sentences: string[],
  secondsOfSpeech: number | null,
  modelOverride?: string
): Promise<{ model: string; jlptLevel: number; reason: string; tokens: GeminiTokenCounts }> {
  if (sentences.length === 0) {
    throw new ClipPipelineError("Transcribe or enter the transcript first.", 400);
  }
  const apiKey = getProviderKey("gemini");
  if (!apiKey) throw new ClipPipelineError("Missing Gemini API key.");
  const model = modelOverride ?? geminiTextModel();
  const thinkingConfig = geminiThinkingConfig(model, "low");

  const response = await fetch(geminiGenerateContentUrl(model), {
    method: "POST",
    headers: { "x-goog-api-key": apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: buildPrompt(sentences, secondsOfSpeech) }] }],
      generationConfig: {
        ...(thinkingConfig ? { thinkingConfig } : {}),
        responseMimeType: "application/json",
        responseSchema: {
          type: "object",
          properties: { jlptLevel: { type: "integer" }, reason: { type: "string" } },
          required: ["jlptLevel", "reason"],
        },
      },
    }),
    signal: AbortSignal.timeout(120_000),
  });
  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new ClipPipelineError(
      `Gemini level estimate failed (HTTP ${response.status}): ${body.slice(0, 500)}`,
      502
    );
  }
  const json = await response.json();
  const tokens = geminiTokenCounts(json);
  const raw = json?.candidates?.[0]?.content?.parts
    ?.map((part: { text?: string }) => part?.text ?? "")
    .join("");
  let parsed;
  try {
    parsed = responseSchema.safeParse(JSON.parse(typeof raw === "string" ? raw : ""));
  } catch {
    throw new ClipPipelineError("Gemini level estimate was not JSON.", 502);
  }
  if (!parsed.success) {
    throw new ClipPipelineError("Gemini level estimate had no level from 1 to 5.", 502);
  }
  return { model, jlptLevel: parsed.data.jlptLevel, reason: parsed.data.reason.trim(), tokens };
}
