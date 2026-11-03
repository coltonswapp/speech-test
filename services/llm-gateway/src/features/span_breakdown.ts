import { Type } from "@google/genai";

import { isObject, parseJSONObject, requiredString, trimmedString, withJapanese, withoutVerbLabel } from "../validate.js";
import { GEMINI_35_FLASH_LITE, PARTICLE_READING_RULE } from "./models.js";
import { defineFeature } from "./types.js";

const INSTRUCTIONS = `You help English-speaking Japanese learners look closer at a short span they selected inside a sentence.

The span might be a set phrase or compound, or just neighboring words.

inThisSentence:
- When a grammar piece is what makes the span mean something (ばかり, から, ながら, そう, ちゃう, てみる, …), write one formula for that join. The word list drops た, て, and ます, so the formula is where that form comes back.
- Shape: slot (the word as written) + the piece — a few plain English words for the combination.
- 転入したばかり → "verb た-form (転入した) + ばかり — just transferred"
- してから → "verb て-form (して) + から — after doing"
- 飲んじゃいけない → "verb て-form (飲んで) + じゃいけない (て→じゃ) — must not drink"
- The parenthetical is the span's own word, in the form written there. The slot name is the pattern they can reuse.
- The right side is the meaning of the combination. Not a translation of the sentence, and not the Japanese word again.
- Slot labels, and no others: verb, noun, い-adjective, な-adjective, dictionary form, ます-form, て-form, ない-form, た-form. Write "verb", never "the verb".
- One line, under 120 characters. If the span is only the grammar piece, you may include the word attached to it in this sentence.
- When there is no such join — a compound, a name, a fixed phrase, or words that are only neighbors — one short plain-English sentence of what the span is doing here. Do not start with the Japanese. Do not translate the rest of the sentence.
- Gloss a verb as "to X" (働く → to work). Never write "the verb", "the verb to X", or "the verb, to X".
- For a katakana borrowing, one short mention of the source in that plain sentence or in partsNote, not both (デジタル → digital, from English). If the Japanese sense is not the English word's sense, give the Japanese meaning and name the English source (テンション → excitement, from English "tension"). Write "from English", not "loanword".
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
- One short kanji line, when the kanji add up and inThisSentence did not already say it.
- Name the kanji that carry the idea, with a plain gloss.
- 大阪名物 → "名 (notable) + 物 (thing) — a distinguished thing"
- Skip place names and characters that don't change the idea.
- Empty when inThisSentence is a formula, when the meaning is already obvious, or for kana-only spans. No readings, radicals, or history.
- Do not repeat a source language already named in inThisSentence.

components:
- The span's content words, in order: nouns, verbs, adjectives, and set phrases.
- Skip particles (を, が, に, で, は, …) and auxiliaries (ます, た, て, だ, です).
- One object per word. Do not split a compound into kanji. 学食 stays one word, not 学 and 食. partsNote still carries that kanji line.
- surface: the word as written in the span.
- lemma: dictionary form. Verbs and adjectives use the plain form (探そう → 探す, 食べた → 食べる, 高かった → 高い).
- reading: hiragana reading of the lemma. Not romaji. ${PARTICLE_READING_RULE}
- gloss: 1 to 3 plain English words a beginner would recognize. Verbs as "to X" (探す → to look for).
- Empty array when the span has no content word.
- 学食を探そう → 学食 (がくしょく, school cafeteria) and 探す (さがす, to look for). The verb's surface is 探そう and its lemma is 探す.

No grammar jargon outside those slot labels. otherUses are short Japanese phrases with a gloss, not full sentences and not English-only labels.

Return a JSON object with "inThisSentence" (string), "otherUses" (array of strings), "partsNote" (string), and "components" (array of objects with "surface", "lemma", "reading", and "gloss" strings).`;

const KANJI_RUN = /[\u3400-\u4DBF\u4E00-\u9FFF\u3005]+/gu;
const JAPANESE = /[\u3040-\u30FF\u3400-\u4DBF\u4E00-\u9FFF]/u;
const KANA_READING = /^[\u3041-\u3096\u30A1-\u30FAー]+$/u;

/** Particles and auxiliaries. Exact surface or lemma only, so 名前 is kept and な is not. */
const SKIPPED = new Set([
  "を", "が", "に", "へ", "で", "と", "は", "も", "の", "か", "や", "ね", "よ", "わ", "ぞ", "さ", "な",
  "から", "まで", "より", "って", "けど", "けれど", "けれども", "ので", "のに",
  "ば", "たら", "なら", "て", "ちゃ", "じゃ",
  "です", "ます", "ました", "ません", "でした", "だった", "だ", "である", "では",
  "た", "ない", "なかった", "ぬ", "ん", "う", "よう", "まい",
  "せる", "させる", "れる", "られる",
]);

type Component = {
  surface: string;
  lemma: string;
  reading: string;
  gloss: string;
};

function shortGloss(text: string): string {
  let gloss = withoutVerbLabel(text).replace(/[.。]+$/u, "").trim();
  gloss = gloss.replace(/^(?:a|an|the)\s+/i, "");
  if (!gloss || !/[A-Za-z]/.test(gloss)) return "";
  const words = gloss.split(/\s+/).slice(0, 3);
  while (words.length > 1 && /^(?:a|an|the|to)$/i.test(words[words.length - 1] ?? "")) {
    words.pop();
  }
  if (words.length === 1 && /^to$/i.test(words[0] ?? "")) return "";
  return words.join(" ");
}

/** The form written in the span, or a dictionary form whose kanji are in the span (探す for 探そう). */
function anchoredToSpan(surface: string, lemma: string, span: string): boolean {
  if (surface && span.includes(surface)) return true;
  if (lemma && span.includes(lemma)) return true;
  const runs = (lemma || surface).match(KANJI_RUN);
  return !!runs && runs.length > 0 && runs.every((run) => span.includes(run));
}

function parseComponents(raw: unknown, span: string): Component[] {
  if (!Array.isArray(raw)) return [];
  const parsed: Component[] = [];
  const seen = new Set<string>();
  for (const item of raw) {
    if (!isObject(item)) continue;
    const surface = trimmedString(item.surface);
    const lemma = trimmedString(item.lemma) || surface;
    const written = surface || lemma;
    if (!written || !lemma) continue;
    if (written.length > 32 || lemma.length > 32) continue;
    if (!JAPANESE.test(written) || !JAPANESE.test(lemma)) continue;
    if (SKIPPED.has(written) || SKIPPED.has(lemma)) continue;
    if (!anchoredToSpan(written, lemma, span)) continue;
    const gloss = shortGloss(trimmedString(item.gloss));
    if (!gloss) continue;
    const readingRaw = trimmedString(item.reading).replace(/[()（）\s]/g, "");
    const reading = KANA_READING.test(readingRaw) ? readingRaw : "";
    if (seen.has(lemma)) continue;
    seen.add(lemma);
    parsed.push({ surface: written, lemma, reading, gloss });
    if (parsed.length === 12) break;
  }
  const pieces = parsed.filter((item) => {
    // Drop a single character that is only a piece of another component (学 inside 学食).
    const keys = [item.surface, item.lemma].filter((key) => key.length === 1);
    if (keys.length === 0) return true;
    return !parsed.some((other) => {
      if (other.lemma === item.lemma) return false;
      const hosts = [other.surface, other.lemma];
      return keys.some((key) => hosts.some((host) => host.includes(key)));
    });
  });
  const words = pieces.filter((item) => item.surface !== span && item.lemma !== span);
  return (words.length > 0 ? words : pieces).slice(0, 8);
}

export const spanBreakdown = defineFeature({
  defaultModel: GEMINI_35_FLASH_LITE,

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
          components: {
            type: Type.ARRAY,
            items: {
              type: Type.OBJECT,
              properties: {
                surface: { type: Type.STRING },
                lemma: { type: Type.STRING },
                reading: { type: Type.STRING },
                gloss: { type: Type.STRING },
              },
              required: ["surface", "lemma", "reading", "gloss"],
              propertyOrdering: ["surface", "lemma", "reading", "gloss"],
            },
          },
        },
        required: ["inThisSentence", "otherUses", "partsNote", "components"],
        propertyOrdering: ["inThisSentence", "otherUses", "partsNote", "components"],
      },
    };
  },

  parseResult(json, { surface }) {
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
      components: parseComponents(raw.components, surface),
    };
  },
});
