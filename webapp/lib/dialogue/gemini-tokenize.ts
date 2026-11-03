import "server-only";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { getProviderKey } from "@/lib/secrets";
import {
  geminiGenerateContentUrl,
  geminiThinkingConfig,
  geminiTokenizeModel,
  type GeminiThinkingLevel,
} from "@/lib/gemini/text-model";
import { db } from "@/lib/db/client";
import { appSettings } from "@/lib/db/schema";
import { DialogueGenerationError } from "@/lib/dialogue/gemini-generate";
import { validatedTokens } from "@/lib/dialogue/japanese-segmentation";
import {
  buildTokenizePrompt,
  TOKENIZE_THINKING_LEVEL,
} from "@/lib/dialogue/tokenize-prompt";
import {
  rawTokenSpans,
  readingsForSegments,
  tokenizeCacheKey,
  type RawToken,
} from "@/lib/dialogue/token-readings";
import type { TokenizedToken } from "@/lib/dialogue/types";

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

export type TokenizeUsage = { promptTokens: number; outputTokens: number };

/** One tokenize round-trip. Exported for scripts/eval-tokenize-model.ts. */
export async function requestTokenSurfaces(
  apiKey: string,
  text: string,
  isRetry: boolean,
  options: {
    model?: string;
    thinkingLevel?: GeminiThinkingLevel;
    onUsage?: (usage: TokenizeUsage) => void;
  } = {}
): Promise<RawToken[]> {
  const model = options.model ?? geminiTokenizeModel();
  const thinkingConfig = geminiThinkingConfig(
    model,
    options.thinkingLevel ?? TOKENIZE_THINKING_LEVEL
  );
  const prompt = buildTokenizePrompt(text, isRetry);

  const response = await fetch(
    geminiGenerateContentUrl(model),
    {
      method: "POST",
      headers: {
        "x-goog-api-key": apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        // Gemini 3+ ignores temperature/topP/topK and rejects candidateCount;
        // the seed plus schema keep output stable enough for the line cache.
        generationConfig: {
          seed: DETERMINISTIC_SEED,
          ...(thinkingConfig ? { thinkingConfig } : {}),
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
  const usage = json?.usageMetadata;
  options.onUsage?.({
    promptTokens: Number(usage?.promptTokenCount ?? 0),
    outputTokens: Math.max(
      Number(usage?.candidatesTokenCount ?? 0),
      Number(usage?.totalTokenCount ?? 0) - Number(usage?.promptTokenCount ?? 0)
    ),
  });
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
export function tokensWithReadings(raw: RawToken[], text: string): TokenizedToken[] | null {
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
