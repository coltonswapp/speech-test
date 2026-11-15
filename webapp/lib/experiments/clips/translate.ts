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
import { addTokenCounts, geminiTokenCounts, ZERO_TOKENS } from "@/lib/experiments/clips/usage";

const responseSchema = z.object({
  translations: z.array(z.object({ line: z.number().int(), en: z.string() })),
});

/** Calls after the first only ask for lines still missing. */
const MAX_ATTEMPTS = 3;

function buildPrompt(sentences: string[], wanted: number[]): string {
  const numbered = sentences.map((s, i) => `[${i}] ${s}`).join("\n");
  const scope =
    wanted.length === sentences.length
      ? `Return one translation for every line, [0] to [${sentences.length - 1}].`
      : `Return translations only for these lines: ${wanted.map((i) => `[${i}]`).join(", ")}. The other lines are context.`;
  return `Translate this Japanese video transcript into natural English for a Japanese learner reading along.

Rules:
- ${scope} Each item is {"line": <the line number>, "en": <its translation>}. Never merge or split lines; a short line ("Yes.", "Wow!") still gets its own item.
- Use the whole transcript as context (who is speaking, what "it" refers to), but translate each line on its own so it lines up with its Japanese.
- Keep the speaker's tone and register. Translate fillers lightly ("um", "well") or drop them when English wouldn't say them.
- Keep names as written in romaji (e.g. Shun, Nara). No notes, brackets, romaji or explanations.
- A line cut off mid-sentence stays cut off ("...").

Transcript:
${numbered}`;
}

async function requestTranslations(
  apiKey: string,
  model: string,
  prompt: string
): Promise<{ byLine: Map<number, string>; tokens: GeminiTokenCounts }> {
  const thinkingConfig = geminiThinkingConfig(model, "low");
  const response = await fetch(geminiGenerateContentUrl(model), {
    method: "POST",
    headers: { "x-goog-api-key": apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: {
        ...(thinkingConfig ? { thinkingConfig } : {}),
        responseMimeType: "application/json",
        responseSchema: {
          type: "object",
          properties: {
            translations: {
              type: "array",
              items: {
                type: "object",
                properties: { line: { type: "integer" }, en: { type: "string" } },
                required: ["line", "en"],
              },
            },
          },
          required: ["translations"],
        },
      },
    }),
    signal: AbortSignal.timeout(120_000),
  });

  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new ClipPipelineError(
      `Gemini translate failed (HTTP ${response.status}): ${body.slice(0, 500)}`,
      502
    );
  }
  const json = await response.json();
  const tokens = geminiTokenCounts(json);
  const empty = { byLine: new Map<number, string>(), tokens };
  const raw = json?.candidates?.[0]?.content?.parts
    ?.map((part: { text?: string }) => part?.text ?? "")
    .join("");
  if (typeof raw !== "string" || raw.trim().length === 0) return empty;
  let parsed;
  try {
    parsed = responseSchema.safeParse(JSON.parse(raw));
  } catch {
    return empty;
  }
  if (!parsed.success) return empty;
  const byLine = new Map<number, string>();
  for (const { line, en } of parsed.data.translations) {
    const text = en.trim();
    if (text && !byLine.has(line)) byLine.set(line, text);
  }
  return { byLine, tokens };
}

/**
 * Translates the whole transcript in one Gemini call, keyed by line number so
 * a dropped or merged line can't shift the rest. Lines still missing are
 * re-requested (with the full transcript as context) up to MAX_ATTEMPTS.
 */
export async function translateClipSentences(
  sentences: string[],
  modelOverride?: string
): Promise<{ model: string; translations: string[]; calls: number; tokens: GeminiTokenCounts }> {
  if (sentences.length === 0) {
    throw new ClipPipelineError("Transcribe or enter the transcript first.", 400);
  }
  const apiKey = getProviderKey("gemini");
  if (!apiKey) throw new ClipPipelineError("Missing Gemini API key.");
  const model = modelOverride ?? geminiTextModel();

  const translations: (string | undefined)[] = sentences.map(() => undefined);
  let missing = sentences.map((_, i) => i);
  let calls = 0;
  let tokens = ZERO_TOKENS;
  for (let attempt = 0; attempt < MAX_ATTEMPTS && missing.length > 0; attempt++) {
    const result = await requestTranslations(apiKey, model, buildPrompt(sentences, missing));
    calls += 1;
    tokens = addTokenCounts(tokens, result.tokens);
    const byLine = result.byLine;
    for (const i of missing) {
      const en = byLine.get(i);
      if (en) translations[i] = en;
    }
    missing = missing.filter((i) => translations[i] === undefined);
  }
  if (missing.length > 0) {
    throw new ClipPipelineError(
      `Gemini didn't translate line${missing.length === 1 ? "" : "s"} ${missing
        .map((i) => i + 1)
        .join(", ")} after ${MAX_ATTEMPTS} tries. Try again, or fill ${
        missing.length === 1 ? "it" : "them"
      } in by hand.`,
      502
    );
  }
  return { model, translations: translations as string[], calls, tokens };
}
