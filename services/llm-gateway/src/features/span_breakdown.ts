import { Type } from "@google/genai";

import { parseJSONObject, requiredString, trimmedString, withJapanese, withoutVerbLabel } from "../validate.js";
import { defineFeature } from "./types.js";

const INSTRUCTIONS = `You help English-speaking Japanese learners look closer at a short span they selected inside a sentence.

The span might be a set phrase or compound, or just neighboring words.

inThisSentence:
- One short sentence: what this span is doing in the given sentence.
- Plain English. Do not translate the rest of the sentence.
- Do not start with the Japanese.
- Gloss a verb as "to X" (働く → to work). Never write "the verb", "the verb to X", or "the verb, to X".
- For a katakana borrowing, one short mention of the source in inThisSentence or partsNote, not both (デジタル → digital, from English). If the Japanese sense is not the English word's sense, give the Japanese meaning and name the English source (テンション → excitement, from English "tension"). Write "from English", not "loanword".
- If the span is not a borrowing (onomatopoeia, a name, native slang), or you are not sure, omit the source. Do not invent an etymology.
- Hiragana and kanji spans are unchanged.

otherUses:
- 2 to 4 other common uses, only when the span is a real expression or compound that people use on its own.
- Each item is a short Japanese phrase that shows the pattern, then " — ", then a plain English gloss.
- The Japanese must include the span and the words it attaches to. うちに → "若いうちに — while young", not "while young".
- A short phrase, not a full sentence, and under 80 characters. No English-only items.
- Empty when the words are just neighbors and do not live together as a phrase.
- Do not invent a set phrase. Do not repeat the in-sentence use.

partsNote:
- One short line on how the pieces add up, when that helps a beginner.
- Name the kanji that carry the idea, with a plain gloss.
- 大阪名物 → "名 (notable) + 物 (thing) — a distinguished thing"
- Skip place names and characters that don't change the idea.
- For kana, a short parts line is fine when the pieces are not obvious (してから → する "to do" + から "after").
- Empty when the meaning is already obvious. No readings, radicals, or history.
- Do not repeat a source language already named in inThisSentence.

No grammar jargon. otherUses are short Japanese phrases with a gloss, not full sentences and not English-only labels.

Return a JSON object with "inThisSentence" (string), "otherUses" (array of strings), and "partsNote" (string).`;

export const spanBreakdown = defineFeature({
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
          inThisSentence: { type: Type.STRING },
          otherUses: { type: Type.ARRAY, items: { type: Type.STRING } },
          partsNote: { type: Type.STRING },
        },
        required: ["inThisSentence", "otherUses", "partsNote"],
      },
    };
  },

  parseResult(json) {
    const raw = parseJSONObject(json);
    const inThisSentence = withoutVerbLabel(trimmedString(raw.inThisSentence));
    if (!inThisSentence) {
      throw new Error("span_breakdown: empty inThisSentence");
    }
    const otherUses = Array.isArray(raw.otherUses)
      ? raw.otherUses
          .map((item) => withJapanese(withoutVerbLabel(trimmedString(item))))
          .filter(Boolean)
      : [];
    return {
      inThisSentence,
      otherUses,
      partsNote: withoutVerbLabel(trimmedString(raw.partsNote)),
    };
  },
});
