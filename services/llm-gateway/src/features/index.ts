import { commonUses } from "./common_uses.js";
import { contextualGloss } from "./contextual_gloss.js";
import { dialogueNuance } from "./dialogue_nuance.js";
import { senseFit } from "./sense_fit.js";
import { spanBreakdown } from "./span_breakdown.js";
import { spanGloss } from "./span_gloss.js";
import type { FeatureDefinition } from "./types.js";

const FEATURES: Record<string, FeatureDefinition<any, unknown>> = {
  common_uses: commonUses,
  contextual_gloss: contextualGloss,
  sense_fit: senseFit,
  dialogue_nuance: dialogueNuance,
  span_gloss: spanGloss,
  span_breakdown: spanBreakdown,
};

export const FEATURE_NAMES = Object.keys(FEATURES);

export function featureNamed(value: unknown): FeatureDefinition<unknown, unknown> | undefined {
  return typeof value === "string" && Object.hasOwn(FEATURES, value) ? FEATURES[value] : undefined;
}

/** `GEMINI_MODEL_<FEATURE>` env overrides the feature's default model. */
export function modelFor(name: string): string {
  const override = process.env[`GEMINI_MODEL_${name.toUpperCase()}`]?.trim();
  return override || FEATURES[name].defaultModel;
}
