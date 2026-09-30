import { Type } from "@google/genai";

import { parseJSONObject, requiredString, stringArray } from "../validate.js";
import { defineFeature } from "./types.js";

const INSTRUCTIONS = `You choose which dictionary sense of one Japanese word fits a sentence.
Return JSON {"index": <zero-based integer>} for the English sense that best fits.
Use only an index from the list. Do not invent a meaning.`;

export const senseFit = defineFeature({
  defaultModel: "gemini-2.5-flash-lite",

  parseInput(body) {
    return {
      sentence: requiredString(body, "sentence", 500),
      surface: requiredString(body, "surface", 64),
      senses: stringArray(body, "senses", { minCount: 2, maxCount: 30, maxLength: 300 }),
    };
  },

  build({ sentence, surface, senses }) {
    const lines = [`Sentence: ${sentence}`, `Word: ${surface}`, "Senses:"];
    senses.forEach((sense, index) => lines.push(`${index}. ${sense}`));
    return {
      systemInstruction: INSTRUCTIONS,
      prompt: lines.join("\n"),
      responseSchema: {
        type: Type.OBJECT,
        properties: { index: { type: Type.INTEGER } },
        required: ["index"],
      },
    };
  },

  parseResult(json, { senses }) {
    const raw = parseJSONObject(json);
    const index = typeof raw.index === "string" ? Number(raw.index.trim()) : Number(raw.index);
    const rounded = Math.round(index);
    if (!Number.isFinite(index) || rounded < 0 || rounded >= senses.length) {
      throw new Error(`sense_fit: index ${String(raw.index)} out of range for ${senses.length} senses`);
    }
    return { index: rounded };
  },
});
