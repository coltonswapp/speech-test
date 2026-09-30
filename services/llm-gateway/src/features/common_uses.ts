import { Type } from "@google/genai";

import { optionalString, parseJSONObject, requiredString, trimmedString, withoutVerbLabel } from "../validate.js";
import { defineFeature } from "./types.js";

const INSTRUCTIONS = `You help English-speaking Japanese learners compare how one word is used.

They selected one word inside a full sentence. The selected word is marked 【like this】 in the sentence. Explain this use, then list other common uses of the same word.

Every field is about the selected word only. Other words in the sentence are context, never the subject. If the sentence is お疲れ。今帰り？ and the selected word is お疲れ, talk about お疲れ, not 帰り.

word: copy the selected word exactly.

inThisSentence:
- One short sentence: what this word is doing in the given sentence.
- Plain English. Do not translate the rest of the sentence.
- Do not start with the Japanese word.
- Gloss a verb as "to X" (働く → to work). Never write "the verb", "the verb to X", or "the verb, to X".

otherUses:
- 2 to 4 other common uses of this word, each a short phrase.
- These are uses in general, not more notes about this sentence.
- Do not repeat the in-sentence use.
- If the word really has only one everyday use, return an empty list.

kanjiNote:
- One short line only when a kanji piece makes the meaning click.
- Only kanji written in the selected word itself. Never kanji from the rest of the sentence.
- Name just those kanji, with a plain gloss, and how they add up.
- 大阪名物 → "名 (notable) + 物 (thing) — a distinguished thing"
- Skip place names and characters that don't change the idea (don't gloss 大阪).
- Skip kana-only words, particles, and words where the pieces add nothing.
- Empty string when it doesn't help. No readings, radicals, or history.

No grammar jargon and no example sentences. Plain text only, no markdown.

A dictionary hint, when present, is optional. Prioritize the sentence.

Return a JSON object with "word" (string), "inThisSentence" (string), "otherUses" (array of strings), and "kanjiNote" (string).`;

const KANJI = /[\u3400-\u4DBF\u4E00-\u9FFF\u3005]/gu;

/** First occurrence only; the client does not send the token's offset. */
function markSelection(sentence: string, surface: string): string {
  const at = sentence.indexOf(surface);
  if (at < 0) return sentence;
  return `${sentence.slice(0, at)}【${surface}】${sentence.slice(at + surface.length)}`;
}

/** Drops a note that glosses kanji the selected word doesn't contain (帰 for お疲れ). */
function kanjiNoteForSurface(note: string, surface: string): string {
  const own = new Set(surface.match(KANJI) ?? []);
  const named = note.match(KANJI) ?? [];
  if (own.size === 0 || named.length === 0) return "";
  return named.every((kanji) => own.has(kanji)) ? note : "";
}

export const commonUses = defineFeature({
  defaultModel: "gemini-2.5-flash",

  parseInput(body) {
    return {
      surface: requiredString(body, "surface", 64),
      sentence: requiredString(body, "sentence", 500),
      dictionaryGloss: optionalString(body, "dictionaryGloss", 300),
    };
  },

  build({ surface, sentence, dictionaryGloss }) {
    const lines = [`Sentence: ${markSelection(sentence, surface)}`, `Selected word: ${surface}`];
    if (dictionaryGloss) {
      lines.push(`Dictionary hint (optional): ${dictionaryGloss}`);
    }
    return {
      systemInstruction: INSTRUCTIONS,
      prompt: lines.join("\n"),
      responseSchema: {
        type: Type.OBJECT,
        properties: {
          word: { type: Type.STRING },
          inThisSentence: { type: Type.STRING },
          otherUses: { type: Type.ARRAY, items: { type: Type.STRING } },
          kanjiNote: { type: Type.STRING },
        },
        required: ["word", "inThisSentence", "otherUses", "kanjiNote"],
        propertyOrdering: ["word", "inThisSentence", "otherUses", "kanjiNote"],
      },
    };
  },

  parseResult(json, { surface }) {
    const raw = parseJSONObject(json);
    const word = trimmedString(raw.word);
    if (word !== surface) {
      throw new Error(`common_uses: answered for "${word}" instead of "${surface}"`);
    }
    const inThisSentence = withoutVerbLabel(trimmedString(raw.inThisSentence));
    if (!inThisSentence) {
      throw new Error("common_uses: empty inThisSentence");
    }
    const otherUses = Array.isArray(raw.otherUses)
      ? raw.otherUses.map((item) => withoutVerbLabel(trimmedString(item))).filter(Boolean)
      : [];
    return {
      inThisSentence,
      otherUses,
      kanjiNote: kanjiNoteForSurface(withoutVerbLabel(trimmedString(raw.kanjiNote)), surface),
    };
  },
});
