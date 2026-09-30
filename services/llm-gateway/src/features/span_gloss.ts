import { Type } from "@google/genai";

import { parseJSONObject, requiredString, trimmedString } from "../validate.js";
import { defineFeature } from "./types.js";

const INSTRUCTIONS = `You help English-speaking Japanese learners understand a short span they selected inside a sentence.

The span may be a compound, a set phrase, or neighboring words. Say what those words mean together here.

meaning:
- Plain English, about 2-12 words.
- The span's meaning in this sentence, not a translation of the whole sentence.
- If the span is a set phrase or compound, give that meaning.

note:
- One short sentence only when the parts combine in a way a beginner would miss.
- Empty string when meaning is enough.

No grammar jargon. Do not describe words outside the span.

Return a JSON object with "meaning" and "note" string fields.`;

export const spanGloss = defineFeature({
  defaultModel: "gemini-2.5-flash",

  parseInput(body) {
    return {
      sentence: requiredString(body, "sentence", 500),
      surface: requiredString(body, "surface", 120),
    };
  },

  build({ sentence, surface }) {
    return {
      systemInstruction: INSTRUCTIONS,
      prompt: `Sentence: ${sentence}\nSelected span: ${surface}`,
      responseSchema: {
        type: Type.OBJECT,
        properties: {
          meaning: { type: Type.STRING },
          note: { type: Type.STRING },
        },
        required: ["meaning", "note"],
      },
    };
  },

  parseResult(json) {
    const raw = parseJSONObject(json);
    const meaning = trimmedString(raw.meaning);
    if (!meaning) {
      throw new Error("span_gloss: empty meaning");
    }
    return { meaning, note: trimmedString(raw.note) };
  },
});
