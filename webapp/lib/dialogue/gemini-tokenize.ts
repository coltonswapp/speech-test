import "server-only";
import { z } from "zod";
import { getProviderKey } from "@/lib/secrets";
import { DialogueGenerationError } from "@/lib/dialogue/gemini-generate";
import { validatedTokens } from "@/lib/dialogue/japanese-segmentation";

const GEMINI_TOKENIZE_MODEL = "gemini-2.5-flash";
const DETERMINISTIC_SEED = 42;

const segmentationPayloadSchema = z.object({
  tokens: z.array(z.string()),
});

// Copied from shizen/Dictionary/GeminiJapaneseTokenizer.swift instructionsText.
const INSTRUCTIONS_TEXT = `Segment Japanese text into dictionary lookup units for language learners.
Return a JSON object with a "tokens" array in original left-to-right order.
Every token MUST be copied verbatim from the input — a contiguous substring using the original Japanese script (kanji, hiragana, katakana).
NEVER output romaji, Latin letters, English, phonetic spellings, or translations.
Tokens must appear in order and together cover the full input.
Include every part of the sentence — do not skip particles, endings, or punctuation.
Keep conjugated verbs together as one token when a learner would tap them as a unit (e.g. 食べちゃいけない, 行きましょう, 飲まなくちゃ, 残ってる, 走ってる, 持ってる).
NEVER split a verb mid-contraction — っ and the following て/てる/た/たら must stay with the verb stem (e.g. 残ってる is one token, NOT 残っ + てる).
Use sentence context: do not split casual endings into standalone hiragana that would mislead lookup (e.g. in 食べちゃいけない keep ちゃ with the verb — not as separate ちゃ "tea").
Keep the colloquial explanatory ending ん + です/だ glued together as one token, and glue it together with an immediately following けど/か/よ/から/が too — do not split ん from です/だ or from that trailing particle (e.g. in 行きたいんですけど keep んですけど as one token, not ん + です + けど; similarly んですか, んだよ, んだから, んですが each stay as one token).
Split standalone particles, nouns, and punctuation when that helps lookup.
Keep punctuation as separate tokens when present.
Punctuation (、 。 ， ． , . ！ ？ ! ? … ・ etc.) is always a hard token boundary. NEVER keep words on both sides of a comma or period in one token (e.g. え、いいん must be え and いいん, not one token).`;

const RETRY_SUFFIX = `

CRITICAL: Copy tokens exactly from the input string. For 歩いて use 歩いて or 歩い and て in Japanese script — never arui, aruite, or te in Latin letters.`;

async function requestTokenSurfaces(
  apiKey: string,
  text: string,
  isRetry: boolean
): Promise<string[]> {
  const prompt = isRetry
    ? `${INSTRUCTIONS_TEXT}${RETRY_SUFFIX}\n\nInput:\n${text}`
    : `${INSTRUCTIONS_TEXT}\n\nInput:\n${text}`;

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_TOKENIZE_MODEL}:generateContent`,
    {
      method: "POST",
      headers: {
        "x-goog-api-key": apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0,
          topP: 1,
          topK: 1,
          seed: DETERMINISTIC_SEED,
          candidateCount: 1,
          responseMimeType: "application/json",
          responseSchema: {
            type: "object",
            properties: {
              tokens: { type: "array", items: { type: "string" } },
            },
            required: ["tokens"],
          },
        },
      }),
    }
  );

  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new DialogueGenerationError(
      `Gemini tokenize failed (HTTP ${response.status}): ${body}`
    );
  }

  const json = await response.json();
  const raw = json?.candidates?.[0]?.content?.parts
    ?.map((part: { text?: string }) => part?.text ?? "")
    .join("");
  if (typeof raw !== "string" || raw.trim().length === 0) {
    throw new DialogueGenerationError("Gemini returned no tokenize text.");
  }

  let parsedJson: unknown;
  try {
    parsedJson = JSON.parse(raw);
  } catch {
    throw new DialogueGenerationError("Gemini tokenize response was not JSON.");
  }
  const parsed = segmentationPayloadSchema.safeParse(parsedJson);
  if (!parsed.success) {
    throw new DialogueGenerationError("Gemini tokenize JSON was missing tokens.");
  }
  return parsed.data.tokens;
}

export async function tokenizeJapaneseLine(text: string): Promise<string[]> {
  const trimmed = text.trim();
  if (!trimmed) return [];

  const apiKey = getProviderKey("gemini");
  if (!apiKey) {
    throw new DialogueGenerationError("Missing Gemini API key.");
  }

  const first = await requestTokenSurfaces(apiKey, trimmed, false);
  const firstTokens = validatedTokens(first, trimmed);
  if (firstTokens && firstTokens.length > 0) {
    return firstTokens.map((token) => token.text);
  }

  const retry = await requestTokenSurfaces(apiKey, trimmed, true);
  const retryTokens = validatedTokens(retry, trimmed);
  if (retryTokens && retryTokens.length > 0) {
    return retryTokens.map((token) => token.text);
  }

  throw new DialogueGenerationError(
    `Could not segment “${trimmed.slice(0, 24)}”.`
  );
}

export async function tokenizeJapaneseLines(
  texts: string[]
): Promise<Array<{ text: string; tokens: string[] }>> {
  const results: Array<{ text: string; tokens: string[] }> = [];
  for (const text of texts) {
    const trimmed = text.trim();
    if (!trimmed) {
      throw new DialogueGenerationError("Spoken lines must not be empty.");
    }
    const tokens = await tokenizeJapaneseLine(trimmed);
    if (tokens.length === 0) {
      throw new DialogueGenerationError(
        `Could not segment “${trimmed.slice(0, 24)}”.`
      );
    }
    results.push({ text: trimmed, tokens });
  }
  return results;
}
