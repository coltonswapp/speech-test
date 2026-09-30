import { Type, type Schema } from "@google/genai";

import {
  isObject,
  oneOf,
  optionalBoolean,
  optionalString,
  parseJSONObject,
  requiredString,
  trimmedString,
  withoutVerbLabel,
} from "../validate.js";
import { defineFeature } from "./types.js";

const FRAMINGS = ["inSentence", "word"] as const;

const INSTRUCTIONS = `You help Japanese language learners understand one selected Japanese word.

The user message says whether they are reading that word inside a sentence or looking the word up on its own. Follow that framing.

Write for a beginner. Use only plain, useful English — never linguistics or morphology labels.
Gloss a verb as "to X" (働く → to work). Never write "the verb", "the verb to X", or "the verb, to X".

meaning (2-8 words):
- In a sentence: what the token means here. Do not translate the whole sentence.
- On its own: the word's natural meaning. If a usage example is included, use it only as a hint. Do not say "in this sentence" or describe the word's role in that line.
- When the word is built from familiar parts, give the natural composed meaning (何時 → what time; 大学生 → university student; スマホ → smartphone).
- For conjugated forms, reflect the inflection when it changes the sense (行きましょう → let's go).
- For a verb built with auxiliaries, give the natural meaning of the whole token (作ってあげよう → I'll make it for you).
- NEVER output meta labels such as: transparent compound, opaque compound, loanword, abbreviation, clipping, portmanteau, compound word, katakana word.

grammarNote:
- Only when the token itself has non-obvious grammar worth a short learner note.
- OK: inflection, a particle fused to the token, politeness encoded in the form.
- For a verb plus auxiliary chain, add one short note on how the parts add up (作ってあげよう → 作る "make" + てあげる "do for someone" + よう "I'll").
- Use an empty string when the meaning alone is enough (most nouns, abbreviations, and ordinary compounds such as 大学生, 何時, スマホ).
- Do NOT describe neighboring tokens (に, は, を, か, etc.).
- Do NOT restate the meaning in different words, and do not name the word's type. A parts breakdown is the note, not a second copy of meaning.
- Do NOT mention related words here.

relatedWords:
- Up to 2 other Japanese words a learner would look up because they share a root or are the other form of this word.
- 引っ越し → word 引っ越す, note "to move".
- Each word is a dictionary headword in Japanese script only.
- note is a short gloss, 1-4 words (to move, a move). Never a part-of-speech label.
- Leave the list empty for particles, names, and words with no useful relative.
- Do not include the selected token.
- Do not include a conjugation's dictionary form when that form is already given as a hint. A noun and its verb are different words and should be included.

headword, only when the user message asks for one:
- The usual dictionary form for this use of the token, in Japanese script (みたい, 見る, わ).
- Empty string when slang or dialect has no standard dictionary form.

Dictionary hints are optional. In a sentence, prioritize that sentence. On its own, prioritize the word.

Return a JSON object with "meaning", "grammarNote", and "relatedWords". relatedWords is an array of objects with "word" and "note" strings. Include "headword" only when the user message asks for a dictionary headword.`;

type Input = {
  sentence: string;
  surface: string;
  dictionaryForm?: string;
  dictionaryGloss?: string;
  framing: (typeof FRAMINGS)[number];
  requestsHeadword: boolean;
};

function framingLines({ sentence, surface, framing }: Input): string[] {
  if (framing === "inSentence") {
    return [
      "Framing: the learner is reading this token inside the sentence.",
      `Sentence: ${sentence}`,
      `Selected token (focus only on this span — not words before or after it): ${surface}`,
    ];
  }
  const lines = [
    "Framing: the learner opened this word on its own, not as part of a sentence they are reading.",
    `Selected word: ${surface}`,
  ];
  if (sentence !== surface) {
    lines.push(`Usage example (hint only — do not describe its role in this line): ${sentence}`);
  }
  return lines;
}

export const contextualGloss = defineFeature({
  defaultModel: "gemini-2.5-flash-lite",

  parseInput(body): Input {
    return {
      sentence: requiredString(body, "sentence", 500),
      surface: requiredString(body, "surface", 64),
      dictionaryForm: optionalString(body, "dictionaryForm", 64),
      dictionaryGloss: optionalString(body, "dictionaryGloss", 300),
      framing: oneOf(body, "framing", FRAMINGS),
      requestsHeadword: optionalBoolean(body, "requestsHeadword"),
    };
  },

  build(input) {
    const lines = framingLines(input);
    lines.push(
      "",
      "Return:",
      "• meaning — plain English gloss for this token only (no linguistics labels)",
      "• grammarNote — short grammar note, or empty string if none",
      "• relatedWords — up to 2 lookup-worthy Japanese relatives, or an empty list",
    );
    if (input.requestsHeadword) {
      lines.push(
        "• headword — the usual dictionary headword for this use, in Japanese script (みたい, 見る, わ), or an empty string when slang or dialect has no standard dictionary form",
      );
    }
    if (input.dictionaryForm && input.dictionaryForm !== input.surface) {
      lines.push(`Dictionary form (hint only): ${input.dictionaryForm}`);
    }
    if (input.dictionaryGloss) {
      lines.push(`Dictionary gloss (hint only): ${input.dictionaryGloss}`);
    }

    const properties: Record<string, Schema> = {
      meaning: { type: Type.STRING },
      grammarNote: { type: Type.STRING },
      relatedWords: {
        type: Type.ARRAY,
        items: {
          type: Type.OBJECT,
          properties: { word: { type: Type.STRING }, note: { type: Type.STRING } },
          required: ["word", "note"],
        },
      },
    };
    const required = ["meaning", "grammarNote", "relatedWords"];
    if (input.requestsHeadword) {
      properties.headword = { type: Type.STRING };
      required.push("headword");
    }

    return {
      systemInstruction: INSTRUCTIONS,
      prompt: lines.join("\n"),
      responseSchema: { type: Type.OBJECT, properties, required },
    };
  },

  parseResult(json, input) {
    const raw = parseJSONObject(json);
    const meaning = typeof raw.meaning === "string" ? withoutVerbLabel(raw.meaning.trim()) : "";
    if (!meaning) {
      throw new Error("contextual_gloss: missing meaning");
    }
    const relatedWords = Array.isArray(raw.relatedWords)
      ? raw.relatedWords
          .filter(isObject)
          .map((item) => ({
            word: trimmedString(item.word),
            note: withoutVerbLabel(trimmedString(item.note)),
          }))
          .filter((item) => item.word)
      : [];
    return {
      meaning,
      grammarNote: withoutVerbLabel(trimmedString(raw.grammarNote)),
      relatedWords,
      headword: input.requestsHeadword ? trimmedString(raw.headword) : "",
    };
  },
});
