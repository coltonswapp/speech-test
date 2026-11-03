// Tokenize prompt, isolated so the prompt (or its thinking level) can be
// swapped in one place. The model comes from GEMINI_TOKENIZE_MODEL
// (lib/gemini/text-model.ts). Pure: safe for evals and scripts.

import type { GeminiThinkingLevel } from "@/lib/gemini/text-model";

/** Thinking level for tokenize calls; geminiThinkingConfig adapts it per model. */
export const TOKENIZE_THINKING_LEVEL: GeminiThinkingLevel = "low";

// Copied from shizen/Dictionary/GeminiJapaneseTokenizer.swift instructionsText.
const INSTRUCTIONS_TEXT = `Segment Japanese text into dictionary lookup units for language learners.
Return a JSON object with a "tokens" array in original left-to-right order.
Every token MUST be copied verbatim from the input — a contiguous substring of the original text (kanji, hiragana, katakana, and any Latin letters or digits that already appear in the input such as ATM, Wi-Fi, OK).
NEVER invent romaji, phonetic Latin spellings, English translations, or Latin letters that are not already present in the input. Copy acronyms and Latin fragments exactly when they appear in the source.
Tokens must appear in order and together cover the full input.
Include every part of the sentence — do not skip particles, endings, or punctuation.
Keep conjugated verbs together as one token when a learner would tap them as a unit (e.g. 食べちゃいけない, 行きましょう, 飲まなくちゃ, 残ってる, 走ってる, 持ってる).
NEVER split a verb mid-contraction — っ and the following て/てる/た/たら must stay with the verb stem (e.g. 残ってる is one token, NOT 残っ + てる).
Use sentence context: do not split casual endings into standalone hiragana that would mislead lookup (e.g. in 食べちゃいけない keep ちゃ with the verb — not as separate ちゃ "tea").
Keep the colloquial explanatory ending ん + です/だ glued together as one token, and glue it together with an immediately following けど/か/よ/から/が too — do not split ん from です/だ or from that trailing particle (e.g. in 行きたいんですけど keep んですけど as one token, not ん + です + けど; similarly んですか, んだよ, んだから, んですが each stay as one token).
Split standalone particles, nouns, and punctuation when that helps lookup.
Keep punctuation as separate tokens when present.
Punctuation (、 。 ， ． , . ！ ？ ! ? … ・ etc.) is always a hard token boundary. NEVER keep words on both sides of a comma or period in one token (e.g. え、いいん must be え and いいん, not one token).`;

// Readings feed the forced aligner (KA-5): it needs the pronunciation as
// spoken, which the surface alone cannot give for numerals and names.
const READING_INSTRUCTIONS = `

Each token is an object {"text", "reading"}. "text" is the verbatim surface as described above. "reading" is the token's pronunciation in kana exactly as it is spoken in this sentence:
- Hiragana for native and Sino-Japanese words (今日 → きょう, 分からなくて → わからなくて); katakana surfaces may keep katakana.
- Numbers, counters and Latin letters are written out as spoken in context, never as digits (302 → さんまるに for a room number, 430円 → よんひゃくさんじゅうえん, 三〇二 → さんまるに, ATM → えーてぃーえむ, 9時 → くじ).
- Long vowels use ー or the spelled kana as pronounced (はいー → はいー, コーヒー → コーヒー).
- Particles are read as pronounced, not as spelled: topic は → わ, direction へ → え, object を → お. This holds inside fixed expressions and merged tokens too (こんにちは → こんにちわ, こんばんは → こんばんわ, では → でわ, には → にわ). A は or へ that is part of a word keeps its own reading (はい → はい, へえ → へえ, 母 → はは, 部屋 → へや).
- Punctuation tokens get an empty reading.
Never put kanji, digits or Latin letters in "reading".`;

const RETRY_SUFFIX = `

CRITICAL: Copy tokens exactly from the input string. For 歩いて use 歩いて or 歩い and て in Japanese script — never invent arui, aruite, or te in Latin letters. Latin/digits are allowed only when copied exactly from the input (e.g. ATM).`;

export function buildTokenizePrompt(text: string, isRetry: boolean): string {
  const base = `${INSTRUCTIONS_TEXT}${READING_INSTRUCTIONS}`;
  return isRetry
    ? `${base}${RETRY_SUFFIX}\n\nInput:\n${text}`
    : `${base}\n\nInput:\n${text}`;
}
