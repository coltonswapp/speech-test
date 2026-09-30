import { GoogleGenAI } from "@google/genai";

import type { FeaturePrompt } from "./features/types.js";

const TIMEOUT_MS = 20_000;

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
          config: {
            systemInstruction,
            responseMimeType: "application/json",
            responseSchema,
            maxOutputTokens: 600,
            temperature: 0,
            topP: 1,
            topK: 1,
            seed: 42,
            // Thinking tokens count against maxOutputTokens; disable on 2.5 models
            // so short answers aren't truncated to empty text.
            ...(model.startsWith("gemini-2.5") ? { thinkingConfig: { thinkingBudget: 0 } } : {}),
            abortSignal: AbortSignal.timeout(TIMEOUT_MS),
          },
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
