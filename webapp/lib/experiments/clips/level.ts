import "server-only";
import { z } from "zod";
import { getProviderKey } from "@/lib/secrets";
import { geminiGenerateContentUrl, geminiThinkingConfig } from "@/lib/gemini/text-model";
import { GEMINI_LEVEL_MODEL_DEFAULT } from "@/lib/gemini/models";
import { ClipPipelineError } from "@/lib/experiments/clips/asr";
import type { GeminiTokenCounts } from "@/lib/experiments/clips/types";
import { geminiTokenCounts } from "@/lib/experiments/clips/usage";

const responseSchema = z.object({
  jlptLevel: z.number().int().min(1).max(5),
  reason: z.string(),
});

/**
 * Characters per second of speech at which a clip is at least N3 for a
 * listener, whatever its vocabulary. Measured over time inside lines (pauses
 * between lines left out). On Nov 15's Shorts: slow skits and anime 4–6,
 * relaxed talk 6–8, fast native dramas and vlogs 9–10.5. The editor rated
 * the 瞬間seju dramas (9.6) N2–N3; the model had said N4.
 */
export const LEVEL_FAST_PACE = 9;

/** Characters per second of speech, from the sentences' token timings. */
export function clipSpeechPace(
  sentences: Array<{ text: string; tokens: Array<{ startSec?: number; endSec?: number }> | null }>
): number | null {
  let seconds = 0;
  let chars = 0;
  for (const s of sentences) {
    const start = s.tokens?.[0]?.startSec;
    const end = s.tokens?.at(-1)?.endSec;
    if (start === undefined || end === undefined || end <= start) continue;
    seconds += end - start;
    chars += s.text.length;
  }
  return seconds > 0 ? chars / seconds : null;
}

function buildPrompt(sentences: string[], pace: number | null): string {
  const paceLine =
    pace !== null
      ? `\nPace: ${pace.toFixed(1)} characters per second of speech (pauses between lines left out). For reference: learner materials and slow, careful speech run 4–6; relaxed everyday conversation 6–8; brisk native speech 8–9; fast native speech, as in TV dramas, comedy and many vlogs, 9 or more.`
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
- This is listening, not reading: simple words said fast by native speakers to each other are hard to follow. At ${LEVEL_FAST_PACE} or more characters per second the clip is N3 or harder. Below that, judge mainly by the words and grammar; most native speech runs 6–9, so an ordinary pace is not a reason to raise the level.
- Fast, contracted or slurred casual speech, and quick back-and-forth between several speakers, are harder than their vocabulary suggests.
- "reason": one short English sentence naming the words or grammar that set the level.

Transcript (one sentence per line):
${sentences.join("\n")}${paceLine}`;
}

/** One Gemini call over the whole transcript. */
export async function estimateClipLevel(
  sentences: string[],
  pace: number | null,
  modelOverride?: string
): Promise<{ model: string; jlptLevel: number; reason: string; tokens: GeminiTokenCounts }> {
  if (sentences.length === 0) {
    throw new ClipPipelineError("Transcribe or enter the transcript first.", 400);
  }
  const apiKey = getProviderKey("gemini");
  if (!apiKey) throw new ClipPipelineError("Missing Gemini API key.");
  const model = modelOverride ?? (process.env.GEMINI_LEVEL_MODEL?.trim() || GEMINI_LEVEL_MODEL_DEFAULT);
  const thinkingConfig = geminiThinkingConfig(model, "low");

  const response = await fetch(geminiGenerateContentUrl(model), {
    method: "POST",
    headers: { "x-goog-api-key": apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: buildPrompt(sentences, pace) }] }],
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
  let { jlptLevel, reason } = parsed.data;
  reason = reason.trim();
  // The prompt asks for this; make sure of it, so fast clips never reach beginners.
  if (pace !== null && pace >= LEVEL_FAST_PACE && jlptLevel > 3) {
    jlptLevel = 3;
    reason = `${reason} Raised to N3 for its pace (${pace.toFixed(1)} characters/s).`;
  }
  return { model, jlptLevel, reason, tokens };
}
