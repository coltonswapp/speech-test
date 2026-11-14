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

meaning (2-10 words):
- In a sentence: what the token means here. Do not translate the whole sentence.
- On its own: the word's natural meaning. If a usage example is included, use it only as a hint. Do not say "in this sentence" or describe the word's role in that line.
- When the word is built from familiar parts, give the natural composed meaning (何時 → what time; 大学生 → university student; スマホ → smartphone).
- For conjugated forms, reflect the inflection when it changes the sense (行きましょう → let's go).
- For a verb built with auxiliaries, give the natural meaning of the whole token (作ってあげよう → I'll make it for you).
- For a sentence-ending chain or fused particle/auxiliary token, gloss only that chunk. 雨なのかもしれない → it might be, not "it might rain". 大変だろうなって思った → probably, I'd guess, not "it's tough and I thought". No dangling "and so", "because", or "and then".
- When って or と quotes a thought, meaning is that thought (なのかなって → wondering whether it's really OK).
- For a katakana borrowing, fold the source into this field in plain English (デジタル → digital, from English; ナイター → night game, from English). If the Japanese sense is not the English word's sense, give the Japanese meaning and name the English source (テンション → excitement, from English "tension"). Write "from English", not "loanword".
- For katakana that is not a borrowing (onomatopoeia, a name, native slang), give the meaning only. If you are not sure it is borrowed, omit the source. Do not invent an etymology.
- Hiragana and kanji words are unchanged — do not add a source language.
- NEVER use a linguistics label as the whole meaning, and do not start meaning with one: transparent compound, opaque compound, loanword, abbreviation, clipping, portmanteau, compound word, katakana word. A real gloss that also names a source language is fine.

grammarNote:
- Only when the token itself has non-obvious grammar worth a short learner note.
- OK: inflection, a particle fused to the token, politeness encoded in the form.
- For a verb plus auxiliary chain, add one short note on how the parts add up (作ってあげよう → 作る "make" + てあげる "do for someone" + よう "I'll").
- For a fused particle/auxiliary chain, one short parts line. Every piece gets a short English gloss. Never part-of-speech names (not copula, nominalizer, question particle, quotation particle).
- な right before の is the attributive form of だ ("is"). A な that is not before の is the soft sentence-ending particle (だろうなって → だろう "probably" + な "you know" + って "quoting that thought").
- の in のだ, んだ, or のか is explanatory ("it's that…"), not a nominalizer. かな is "I wonder". って or と quotes a thought.
- なのかなって → な "is" + の "it's that" + かな "I wonder" + って "quoting that thought"
- んじゃないかな → ん "it's that" + じゃない "isn't" + かな "I wonder"
- ないかなと → ない "not" + かな "I wonder" + と "quoting that thought"
- Use an empty string when the meaning alone is enough (most nouns, abbreviations, and ordinary compounds such as 大学生, 何時, スマホ).
- Do NOT describe neighboring tokens (に, は, を, か, etc.).
- Do NOT restate the meaning in different words, and do not name the word's type. A parts breakdown is the note, not a second copy of meaning.
- Do NOT mention related words here.
- Do NOT put a source language here. That belongs in meaning.

relatedWords:
- Up to 2 other Japanese words a learner would look up. Order is the display order.
- When the selected word is a transparent compound of real words, those component words come first, in the order they are written. A component has to be a word or an established meaningful unit in this context. 人口減少 → 人口 "population", then 減少 "decrease". 高速道路 → 高速 "high speed", then 道路 "road".
- A looser relative may use a slot only after those components. 減る "to decrease" must not take the place of 減少.
- Do not split a word that does not come apart. 今日, スマホ, and 働く have no component words. Do not invent pieces or arbitrary character chunks (not 口減 from 人口減少, not 今 and 日 from 今日).
- Do not suggest a single kanji. Each character is already shown on its own. 大学生 → 大学 "university", not 大, 学, or 生.
- When there is no such compound, suggest a word that shares a root or is the other form of this word. 引っ越し → 引っ越す "to move".
- Each word is a dictionary headword in Japanese script only.
- note is a short gloss, 1-4 words (population, to move). Never a part-of-speech label.
- Leave the list empty for particles, names, and words with no useful relative.
- Do not include the selected token. Do not repeat a word.
- Do not include a conjugation's dictionary form when that form is already given as a hint. A noun and its verb are different words; include that verb only when a slot remains after the real components.

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

type RelatedWord = { word: string; note: string };

const RELATED_LIMIT = 2;

const PARTICLES = new Set([
  "は", "が", "を", "に", "で", "と", "も", "か", "よ", "ね", "の", "へ", "や", "わ",
  "から", "まで", "より", "って",
]);

/** Japanese script plus 々 / ー, matching the iOS lookup-word check. */
function isLookupWord(word: string): boolean {
  const chars = characters(word);
  let hasJapanese = false;
  for (const char of chars) {
    const code = char.codePointAt(0) ?? 0;
    const japanese =
      (code >= 0x3040 && code <= 0x309f) ||
      (code >= 0x30a0 && code <= 0x30ff) ||
      (code >= 0x4e00 && code <= 0x9fff) ||
      (code >= 0x3400 && code <= 0x4dbf);
    if (!japanese && char !== "々" && char !== "ー") return false;
    if (japanese) hasJapanese = true;
  }
  return hasJapanese;
}

function displayNote(note: string, word: string): string {
  if (note === word || characters(note).length > 40) return "";
  return note;
}

function characters(text: string): string[] {
  return Array.from(text);
}

/** A one-character suggestion that is already one of the word's own characters. */
function isSingleCharacterOf(surface: string, word: string): boolean {
  const wordChars = characters(word);
  return wordChars.length === 1 && characters(surface).includes(wordChars[0] ?? "");
}

/**
 * Component words that tile the whole surface, preferring fewer and longer pieces.
 * Returns null when the suggestions do not split the word exactly — nothing is invented.
 */
function componentCover(surface: string, words: string[]): string[] | null {
  const surfaceChars = characters(surface);
  const n = surfaceChars.length;
  const pieces: string[] = [];
  const seen = new Set<string>();
  for (const word of words) {
    const len = characters(word).length;
    if (len < 2 || len >= n || seen.has(word) || !surface.includes(word)) continue;
    seen.add(word);
    pieces.push(word);
  }
  if (pieces.length < 2) return null;

  const at: string[][] = Array.from({ length: n }, () => []);
  for (const piece of pieces) {
    const len = characters(piece).length;
    for (let index = 0; index + len <= n; index++) {
      if (surfaceChars.slice(index, index + len).join("") === piece) at[index].push(piece);
    }
  }
  for (const bucket of at) {
    bucket.sort((a, b) => characters(b).length - characters(a).length);
  }

  const best: { count: number; path: string[] }[] = Array.from({ length: n + 1 }, () => ({
    count: Number.POSITIVE_INFINITY,
    path: [],
  }));
  best[n] = { count: 0, path: [] };
  for (let index = n - 1; index >= 0; index--) {
    for (const piece of at[index] ?? []) {
      const len = characters(piece).length;
      const next = best[index + len];
      if (!next || !Number.isFinite(next.count)) continue;
      const count = next.count + 1;
      const path = [piece, ...next.path];
      const current = best[index];
      if (!current || count < current.count || (count === current.count && longerEarlier(path, current.path))) {
        best[index] = { count, path };
      }
    }
  }

  const chosen = best[0];
  if (!chosen || !Number.isFinite(chosen.count) || chosen.count < 2) return null;
  if (chosen.path.join("") !== surface) return null;
  return chosen.path;
}

function longerEarlier(path: string[], other: string[]): boolean {
  const left = path.map((part) => characters(part).length);
  const right = other.map((part) => characters(part).length);
  const count = Math.max(left.length, right.length);
  for (let index = 0; index < count; index++) {
    const a = left[index] ?? 0;
    const b = right[index] ?? 0;
    if (a !== b) return a > b;
  }
  return false;
}

/**
 * Keeps model order unless the suggestions include a real split of the whole word.
 * Those components then lead, and a leftover character chunk of that split is dropped.
 * Display stays at two words. Words the model did not return are never added.
 */
function selectRelatedWords(items: RelatedWord[], surface: string, dictionaryForm?: string): RelatedWord[] {
  const excluded = new Set([surface, dictionaryForm ?? ""].map((value) => value.trim()).filter(Boolean));
  const seen = new Set<string>();
  const cleaned: RelatedWord[] = [];
  for (const item of items) {
    const word = item.word.trim();
    if (!word || excluded.has(word) || seen.has(word)) continue;
    if (characters(word).length > 12 || !isLookupWord(word) || PARTICLES.has(word)) continue;
    if (isSingleCharacterOf(surface, word)) continue;
    seen.add(word);
    cleaned.push({ word, note: displayNote(item.note, word) });
  }

  const cover = componentCover(surface, cleaned.map((item) => item.word));
  if (!cover) return cleaned.slice(0, RELATED_LIMIT);

  const coverSet = new Set(cover);
  const byWord = new Map(cleaned.map((item) => [item.word, item]));
  const ordered: RelatedWord[] = [];
  const used = new Set<string>();
  for (const word of cover) {
    const item = byWord.get(word);
    if (!item || used.has(word)) continue;
    used.add(word);
    ordered.push(item);
  }
  for (const item of cleaned) {
    if (used.has(item.word) || surface.includes(item.word)) continue;
    used.add(item.word);
    ordered.push(item);
  }
  return ordered.slice(0, RELATED_LIMIT);
}

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
      "• meaning — plain English gloss for this token only (no linguistics labels as the whole answer)",
      "• grammarNote — short grammar note, or empty string if none",
      "• relatedWords — up to 2 Japanese words. Transparent compounds: real component words first, in written order. Otherwise one close relative. Empty list if none",
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
        description:
          "Up to 2 lookup words. For a transparent compound, the meaningful component words first, in written order. A looser relative only if a slot remains. Empty when nothing useful.",
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
    const relatedWords = selectRelatedWords(
      Array.isArray(raw.relatedWords)
        ? raw.relatedWords.filter(isObject).map((item) => ({
            word: trimmedString(item.word),
            note: withoutVerbLabel(trimmedString(item.note)),
          }))
        : [],
      input.surface,
      input.dictionaryForm,
    );
    return {
      meaning,
      grammarNote: withoutVerbLabel(trimmedString(raw.grammarNote)),
      relatedWords,
      headword: input.requestsHeadword ? trimmedString(raw.headword) : "",
    };
  },
});
