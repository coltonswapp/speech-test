// Gemini model ids and published per-1M-token rates used by Studio.
// Client-safe: no env reads here (see text-model.ts for the server-side
// GEMINI_TEXT_MODEL override).
//
// Rates: https://ai.google.dev/gemini-api/docs/pricing (checked 2026-11-02).
// Several models double their rate on 2027-01-01, so rows are date-effective.

export const GEMINI_TEXT_MODEL_DEFAULT = "gemini-3.5-flash-lite";

/**
 * Tokenize + readings model. Provisional default: a 40-line eval (Nov 2) had
 * 3.5 Flash-Lite splitting verbs/words learners tap (多|い, 聞か|れた); a
 * prompt-tuning eval is deciding between it and 3.8 Flash.
 */
export const GEMINI_TOKENIZE_MODEL_DEFAULT = "gemini-3.8-flash";

export const GEMINI_TTS_MODELS = [
  { id: "gemini-3.8-flash-tts", label: "3.8 Flash TTS" },
  { id: "gemini-3.8-flash-lite-tts", label: "3.8 Flash-Lite TTS" },
] as const;

export type GeminiTtsModel = (typeof GEMINI_TTS_MODELS)[number]["id"];

export const GEMINI_TTS_DEFAULT_MODEL: GeminiTtsModel = "gemini-3.8-flash-tts";

/** Retired 2026-11-17; kept so the legacy request shape stays testable until then. */
export const GEMINI_TTS_LEGACY_MODEL = "gemini-3.1-flash-tts-preview";

export function isGeminiTtsModel(value: unknown): value is GeminiTtsModel {
  return GEMINI_TTS_MODELS.some((model) => model.id === value);
}

/**
 * 3.8+ TTS reads `text` verbatim: speaker labels and style go in per-part
 * `speechMetadata`, and unary responses are WAV, not raw PCM. 3.1 and earlier
 * use the inline "Speaker: text" transcript.
 */
export function usesSpeechMetadata(model: string): boolean {
  return model !== GEMINI_TTS_LEGACY_MODEL && !model.startsWith("gemini-2.5-");
}

export type GeminiRate = {
  /** USD per 1M input tokens (text). */
  inputPerMillion: number;
  /** USD per 1M output tokens (text incl. thinking, or audio for TTS). */
  outputPerMillion: number;
};

type RateRow = { model: string; from?: string; rate: GeminiRate };

// Order matters: for a model, the last row whose `from` is <= the date wins.
const RATE_ROWS: RateRow[] = [
  // Text
  { model: "gemini-2.5-flash", rate: { inputPerMillion: 0.3, outputPerMillion: 2.5 } },
  { model: "gemini-3.5-flash-lite", rate: { inputPerMillion: 0.3, outputPerMillion: 2.5 } },
  { model: "gemini-3.8-flash", rate: { inputPerMillion: 0.75, outputPerMillion: 3.75 } },
  { model: "gemini-3.8-flash", from: "2027-01-01", rate: { inputPerMillion: 1.5, outputPerMillion: 7.5 } },
  // TTS (output is audio, 25 tokens per second)
  { model: "gemini-3.1-flash-tts-preview", rate: { inputPerMillion: 1, outputPerMillion: 20 } },
  { model: "gemini-3.8-flash-tts", rate: { inputPerMillion: 0.5, outputPerMillion: 9 } },
  { model: "gemini-3.8-flash-tts", from: "2027-01-01", rate: { inputPerMillion: 1, outputPerMillion: 18 } },
  { model: "gemini-3.8-flash-lite-tts", rate: { inputPerMillion: 0.5, outputPerMillion: 6 } },
  { model: "gemini-3.8-flash-lite-tts", from: "2027-01-01", rate: { inputPerMillion: 1, outputPerMillion: 12 } },
];

/** Published standard-tier rate for `model` on `at` (UTC), or undefined if unpriced. */
export function geminiRate(model: string, at: Date = new Date()): GeminiRate | undefined {
  let match: GeminiRate | undefined;
  for (const row of RATE_ROWS) {
    if (row.model !== model) continue;
    if (row.from && at.getTime() < Date.parse(`${row.from}T00:00:00Z`)) continue;
    match = row.rate;
  }
  return match;
}

export function estimateGeminiCostUSD(
  model: string,
  inputTokens: number,
  outputTokens: number,
  at: Date = new Date()
): number | undefined {
  const rate = geminiRate(model, at);
  if (!rate) return undefined;
  return (
    (inputTokens / 1_000_000) * rate.inputPerMillion +
    (outputTokens / 1_000_000) * rate.outputPerMillion
  );
}
