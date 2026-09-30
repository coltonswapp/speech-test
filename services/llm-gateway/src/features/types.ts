import type { Schema } from "@google/genai";

import type { Body } from "../validate.js";

export type FeaturePrompt = {
  systemInstruction: string;
  prompt: string;
  responseSchema: Schema;
};

/**
 * One LLM feature served by `POST /v1/generate`. Prompts live here so they can
 * change with a redeploy instead of an app release.
 */
export type FeatureDefinition<Input, Result> = {
  /** Overridable per feature with env `GEMINI_MODEL_<FEATURE>` (e.g. GEMINI_MODEL_CONTEXTUAL_GLOSS). */
  defaultModel: string;
  /** Throws `InputError` for bad requests. */
  parseInput(body: Body): Input;
  build(input: Input): FeaturePrompt;
  /** Throws when the model output doesn't match the result shape (→ 502). */
  parseResult(json: string, input: Input): Result;
};

export function defineFeature<Input, Result>(
  definition: FeatureDefinition<Input, Result>,
): FeatureDefinition<Input, Result> {
  return definition;
}
