import { GoogleGenAI, ThinkingLevel, type GenerateContentConfig } from "@google/genai";

import type { FeaturePrompt } from "./features/types.js";

const TIMEOUT_MS = 20_000;
const MAX_OUTPUT_TOKENS = 600;

export class UpstreamError extends Error {}

export type GeminiUsage = {
  promptTokenCount: number;
  candidatesTokenCount: number;
  totalTokenCount: number;
};

export type GeminiJSONResult = { json: string; usage: GeminiUsage };

export type GeminiClient = {
  generateJSON(model: string, prompt: FeaturePrompt): Promise<GeminiJSONResult>;
};

export function createGeminiClient(apiKey: string): GeminiClient {
  const ai = new GoogleGenAI({ apiKey });

  return {
    async generateJSON(model, { systemInstruction, prompt, responseSchema }) {
      let response;
      try {
        response = await ai.models.generateContent({
          model,
          contents: prompt,
          config: generationConfig(model, { systemInstruction, responseSchema }),
        });
      } catch (err) {
        throw new UpstreamError("Gemini request failed", { cause: err });
      }

      const json = response.text?.trim();
      if (!json) {
        throw new UpstreamError(
          `Gemini returned no text (finishReason: ${response.candidates?.[0]?.finishReason ?? "unknown"})`,
        );
      }
      const usage = response.usageMetadata;
      return {
        json,
        usage: {
          promptTokenCount: usage?.promptTokenCount ?? 0,
          candidatesTokenCount: usage?.candidatesTokenCount ?? 0,
          totalTokenCount: usage?.totalTokenCount ?? 0,
        },
      };
    },
  };
}

/**
 * 3.5 rejects temperature, topP, and topK. 2.5 still accepts them, and thinking
 * tokens on 3.5 count against maxOutputTokens, so those calls use a low thinking level.
 */
function generationConfig(
  model: string,
  prompt: Pick<FeaturePrompt, "systemInstruction" | "responseSchema">,
): GenerateContentConfig {
  const shared: GenerateContentConfig = {
    systemInstruction: prompt.systemInstruction,
    responseMimeType: "application/json",
    responseSchema: prompt.responseSchema,
    maxOutputTokens: MAX_OUTPUT_TOKENS,
    seed: 42,
    abortSignal: AbortSignal.timeout(TIMEOUT_MS),
  };
  if (model.startsWith("gemini-2.5")) {
    return {
      ...shared,
      temperature: 0,
      topP: 1,
      topK: 1,
      thinkingConfig: { thinkingBudget: 0 },
    };
  }
  return {
    ...shared,
    thinkingConfig: { thinkingLevel: ThinkingLevel.LOW },
  };
}
