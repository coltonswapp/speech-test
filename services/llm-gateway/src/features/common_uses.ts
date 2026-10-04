import { Type } from "@google/genai";

import { optionalString, parseJSONObject, requiredString, trimmedString, withoutVerbLabel, withPhraseReading } from "../validate.js";
import { defineFeature } from "./types.js";

const INSTRUCTIONS = `You help English-speaking Japanese learners compare how one word is used.

They selected one word inside a full sentence. The selected word is marked 【like this】 in the sentence. Explain this use, then list other common uses of the same word.

Every field is about the selected word only. Other words in the sentence are context, never the subject. If the sentence is お疲れ。今帰り？ and the selected word is お疲れ, talk about お疲れ, not 帰り.

word: copy the selected word exactly.

inThisSentence:
- One short sentence: what this word is doing in the given sentence.
- Plain English. Do not translate the rest of the sentence.
- Do not start with the Japanese word.
- Do not start with "This word is used" or talk about "this word" as the subject. Lead with the use: "Used to say…", "Commonly heard when…", "Typically used to express…".
- Gloss a verb as "to X" (働く → to work). Never write "the verb", "the verb to X", or "the verb, to X".
- For a katakana borrowing, include the source in this field in plain English (デジタル → digital, from English; ナイター → a night game, from English). If the Japanese sense is not the English word's sense, give the Japanese meaning and name the English source (テンション → excitement, from English "tension"). Write "from English", not "loanword".
- For katakana that is not a borrowing (onomatopoeia, a name, native slang), omit the source. If you are not sure it is borrowed, omit the source. Do not invent an etymology.
- Hiragana and kanji words are unchanged — do not add a source language.

otherUses:
- 2 to 4 other common uses of this word.
- Each item is a short Japanese phrase that shows the use, then " — ", then a plain English gloss.
- The Japanese must include this word in a real phrase. かける → "眼鏡をかける (めがねをかける) — to put on glasses", not "to put on glasses".
- After the Japanese and before the em dash, add a hiragana reading of the whole phrase in parentheses: 物置小屋 (ものおきごや) — a storage shed.
- Hiragana only. Not romaji. Not furigana over the characters. Not a reading of only the selected word.
- If the Japanese is already all kana, do not add a reading.
- These are uses in general, not more notes about this sentence.
- A short phrase, not a full sentence, and under 80 characters. No English-only items.
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
- Never put a source language here. For a katakana borrowing, that belongs in inThisSentence.

No grammar jargon. otherUses are short Japanese phrases with a gloss, not full sentences and not English-only labels. Plain text only, no markdown.

A dictionary hint, when present, is optional. Prioritize the sentence.

Return a JSON object with "word" (string), "inThisSentence" (string), "otherUses" (array of strings), and "kanjiNote" (string).`;

const KANJI = /[\u3400-\u4DBF\u4E00-\u9FFF\u3005]/gu;

/** First occurrence only; the client does not send the token's offset. */
function markSelection(sentence: string, surface: string): string {
  const at = sentence.indexOf(surface);
  if (at < 0) return sentence;
  return `${sentence.slice(0, at)}【${surface}】${sentence.slice(at + surface.length)}`;
}

/** "This word is used to say X" → "Used to say X". */
function withoutWordSubject(text: string): string {
  const stripped = text.replace(/^(?:this|the|that)\s+word\s+is\s+/i, "");
  if (stripped === text || !stripped) return text;
  return stripped.charAt(0).toUpperCase() + stripped.slice(1);
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
    const inThisSentence = withoutWordSubject(withoutVerbLabel(trimmedString(raw.inThisSentence)));
    if (!inThisSentence) {
      throw new Error("common_uses: empty inThisSentence");
    }
    const otherUses = Array.isArray(raw.otherUses)
      ? raw.otherUses
          .map((item) => withPhraseReading(withoutVerbLabel(trimmedString(item))))
          .filter(Boolean)
      : [];
    return {
      inThisSentence,
      otherUses,
      kanjiNote: kanjiNoteForSurface(withoutVerbLabel(trimmedString(raw.kanjiNote)), surface),
    };
  },
});
