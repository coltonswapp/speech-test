import "server-only";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { getProviderKey } from "@/lib/secrets";
import { db } from "@/lib/db/client";
import { appSettings } from "@/lib/db/schema";
import { DialogueGenerationError } from "@/lib/dialogue/gemini-generate";
import { validatedTokens } from "@/lib/dialogue/japanese-segmentation";
import {
  rawTokenSpans,
  readingsForSegments,
  tokenizeCacheKey,
  type RawToken,
} from "@/lib/dialogue/token-readings";
import type { TokenizedToken } from "@/lib/dialogue/types";

const GEMINI_TOKENIZE_MODEL = "gemini-2.5-flash";
const DETERMINISTIC_SEED = 42;

const segmentationPayloadSchema = z.object({
  tokens: z.array(
    z.object({
      text: z.string(),
      reading: z.string().optional(),
    })
  ),
});

const cachedLineSchema = z.object({
  tokens: z.array(z.object({ text: z.string().min(1), reading: z.string().optional() })).min(1),
});

// Copied from shizen/Dictionary/GeminiJapaneseTokenizer.swift instructionsText.
const INSTRUCTIONS_TEXT = `Segment Japanese text into dictionary lookup units for language learners.
Return a JSON object with a "tokens" array in original left-to-right order.
Every token MUST be copied verbatim from the input — a contiguous substring of the original text (kanji, hiragana, katakana, and any Latin letters or digits that already appear in the input such as ATM, Wi-Fi, OK).
NEVER invent romaji, phonetic Latin spellings, English translations, or Latin letters that are not already present in the input. Copy acronyms and Latin fragments exactly when they appear in the source.
Tokens must appear in order and together cover the full input.
Include every part of the sentence — do not skip particles, endings, or punctuation.
Keep conjugated verbs together as one token when a learner would tap them as a unit (e.g. 食べちゃいけない, 行きましょう, 飲まなくちゃ, 残ってる, 走ってる, 持ってる).
NEVER split a verb mid-contraction — っ and the following て/てる/た/たら must stay with the verb stem (e.g. 残ってる is one token, NOT 残っ + てる).
Use sentence context: do not split casual endings into standalone hiragana that would mislead lookup (e.g. in 食べちゃいけない keep ちゃ with the verb — not as separate ちゃ "tea").
Keep the colloquial explanatory ending ん + です/だ glued together as one token, and glue it together with an immediately following けど/か/よ/から/が too — do not split ん from です/だ or from that trailing particle (e.g. in 行きたいんですけど keep んですけど as one token, not ん + です + けど; similarly んですか, んだよ, んだから, んですが each stay as one token).
Split standalone particles, nouns, and punctuation when that helps lookup.
Keep punctuation as separate tokens when present.
Punctuation (、 。 ， ． , . ！ ？ ! ? … ・ etc.) is always a hard token boundary. NEVER keep words on both sides of a comma or period in one token (e.g. え、いいん must be え and いいん, not one token).`;

// Readings feed the forced aligner (KA-5): it needs the pronunciation as
// spoken, which the surface alone cannot give for numerals and names.
const READING_INSTRUCTIONS = `

Each token is an object {"text", "reading"}. "text" is the verbatim surface as described above. "reading" is the token's pronunciation in kana exactly as it is spoken in this sentence:
- Hiragana for native and Sino-Japanese words (今日 → きょう, 分からなくて → わからなくて); katakana surfaces may keep katakana.
- Numbers, counters and Latin letters are written out as spoken in context, never as digits (302 → さんまるに for a room number, 430円 → よんひゃくさんじゅうえん, 三〇二 → さんまるに, ATM → えーてぃーえむ, 9時 → くじ).
- Long vowels use ー or the spelled kana as pronounced (はいー → はいー, コーヒー → コーヒー).
- Punctuation tokens get an empty reading.
Never put kanji, digits or Latin letters in "reading".`;

const RETRY_SUFFIX = `

CRITICAL: Copy tokens exactly from the input string. For 歩いて use 歩いて or 歩い and て in Japanese script — never invent arui, aruite, or te in Latin letters. Latin/digits are allowed only when copied exactly from the input (e.g. ATM).`;

async function requestTokenSurfaces(
  apiKey: string,
  text: string,
  isRetry: boolean
): Promise<RawToken[]> {
  const base = `${INSTRUCTIONS_TEXT}${READING_INSTRUCTIONS}`;
  const prompt = isRetry
    ? `${base}${RETRY_SUFFIX}\n\nInput:\n${text}`
    : `${base}\n\nInput:\n${text}`;

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
              tokens: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    text: { type: "string" },
                    reading: { type: "string" },
                  },
                  required: ["text", "reading"],
                },
              },
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

/** Validated segments plus whichever readings survive the split/merge pass. */
function tokensWithReadings(raw: RawToken[], text: string): TokenizedToken[] | null {
  const segments = validatedTokens(
    raw.map((token) => token.text),
    text
  );
  if (!segments || segments.length === 0) return null;
  const readings = readingsForSegments(segments, rawTokenSpans(raw, text));
  return segments.map((segment, i) => ({
    text: segment.text,
    ...(readings[i] ? { reading: readings[i] } : {}),
  }));
}

async function readCachedLine(text: string): Promise<TokenizedToken[] | null> {
  try {
    const row = await db.query.appSettings.findFirst({
      where: eq(appSettings.key, tokenizeCacheKey(text)),
    });
    if (!row) return null;
    const parsed = cachedLineSchema.safeParse(row.value);
    return parsed.success ? parsed.data.tokens : null;
  } catch {
    // The cache is an optimization; never let it block tokenizing.
    return null;
  }
}

async function writeCachedLine(text: string, tokens: TokenizedToken[]): Promise<void> {
  try {
    await db
      .insert(appSettings)
      .values({ key: tokenizeCacheKey(text), value: { tokens } })
      .onConflictDoUpdate({ target: appSettings.key, set: { value: { tokens } } });
  } catch {
    // ignore — see readCachedLine
  }
}

export async function tokenizeJapaneseLine(
  text: string
): Promise<TokenizedToken[]> {
  const trimmed = text.trim();
  if (!trimmed) return [];

  const cached = await readCachedLine(trimmed);
  if (cached) return cached;

  const apiKey = getProviderKey("gemini");
  if (!apiKey) {
    throw new DialogueGenerationError("Missing Gemini API key.");
  }

  const first = await requestTokenSurfaces(apiKey, trimmed, false);
  const firstTokens = tokensWithReadings(first, trimmed);
  if (firstTokens) {
    await writeCachedLine(trimmed, firstTokens);
    return firstTokens;
  }

  const retry = await requestTokenSurfaces(apiKey, trimmed, true);
  const retryTokens = tokensWithReadings(retry, trimmed);
  if (retryTokens) {
    await writeCachedLine(trimmed, retryTokens);
    return retryTokens;
  }

  throw new DialogueGenerationError(
    `Could not segment “${trimmed.slice(0, 24)}”.`
  );
}

export async function tokenizeJapaneseLines(
  texts: string[]
): Promise<Array<{ text: string; tokens: TokenizedToken[] }>> {
  const results: Array<{ text: string; tokens: TokenizedToken[] }> = [];
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
