import { Type } from "@google/genai";

import {
  InputError,
  objectArray,
  optionalString,
  parseJSONObject,
  requiredString,
  trimmedString,
  withoutVerbLabel,
  withPhraseReading,
  type Body,
} from "../validate.js";
import { defineFeature } from "./types.js";

const MAX_LINES = 12;
const MAX_EXAMPLES = 3;

const INSTRUCTIONS = `You help English-speaking Japanese learners see how one grammar pattern from a dialogue is used.

The learner tapped a pattern label such as "___ ちゃいけない" or "〜ていい？". "___" and "〜" mark where other words go. Lines marked → use the pattern. When no line is marked, find the line that uses it. Other lines are context only.

Explain the pattern, not the whole line or the whole conversation.

inThisScene:
- One short sentence: what the pattern is doing in the line that uses it.
- Plain English. Do not translate the whole line.
- Do not start with the Japanese.
- Lead with the use: "Asking if it's okay to…", "Saying you must not…", "Giving a reason with…".

form:
- One short line on how the pattern is built, so the learner can make their own.
- Write the slot in plain terms, then the pattern: "verb て-form + もいい？", "noun + じゃダメ", "verb ない-form + といけない".
- Start with the slot the dialogue uses (静かだし → "な-adjective + だし"). Add one other slot, after a semicolon, only when it changes the ending ("な-adjective / noun + だし; い-adjective + し").
- Only these labels: verb, noun, い-adjective, な-adjective, dictionary form, ます-form, て-form, ない-form, た-form. No other grammar terms.
- Empty string when the pattern is a fixed phrase that does not attach to other words.

examples:
- 2 to 3 short everyday examples of the same pattern with different words than the dialogue.
- Each item is the Japanese, then " — ", then a plain English gloss.
- When the Japanese has any kanji, add a hiragana reading of the whole example in parentheses after the Japanese and before the em dash: 窓を開けてもいい？ (まどをあけてもいい？) — Can I open the window?
- Hiragana only. Not romaji. Not a reading of only the kanji. If the Japanese is already all kana, do not add a reading: これ、食べてもいい？ needs one; ちょっといい？ does not.
- Same register as the dialogue (casual stays casual). Under 40 Japanese characters each. No English-only items.
- Do not repeat a line from the dialogue.

note:
- At most one short sentence on a single thing that trips learners up: a casual contraction (ちゃ = ては), a politer or more casual version, or a near form that means something different.
- Empty string when there is nothing worth adding. Do not restate inThisScene or form.

Plain text only, no markdown.

Return a JSON object with "inThisScene" (string), "form" (string), "examples" (array of strings), and "note" (string).`;

type Line = { speaker?: string; japanese: string; english?: string; focus: boolean };

function parseLine(body: Body, label: string): Line {
  const japanese = typeof body.japanese === "string" ? body.japanese.trim() : "";
  if (!japanese || japanese.length > 300) {
    throw new InputError(`${label}.japanese must be a non-empty string (max 300 chars)`);
  }
  if (body.focus !== undefined && body.focus !== null && typeof body.focus !== "boolean") {
    throw new InputError(`${label}.focus must be a boolean`);
  }
  return {
    speaker: optionalString(body, "speaker", 64),
    japanese,
    english: optionalString(body, "english", 500),
    focus: body.focus === true,
  };
}

function formatLine(line: Line): string {
  const head = `${line.focus ? "→ " : "  "}${line.japanese}`;
  return line.english ? `${head}\n     (${line.english})` : head;
}

/** Drops examples that are just a scene line, and duplicates. */
function sanitizedExamples(raw: unknown, lines: Line[]): string[] {
  if (!Array.isArray(raw)) return [];
  const sceneLines = new Set(lines.map((line) => line.japanese));
  const seen = new Set<string>();
  const examples: string[] = [];
  for (const item of raw) {
    const example = withPhraseReading(withoutVerbLabel(trimmedString(item)));
    if (!example || example.length > 160) continue;
    const japanese = example.split(/\s*[(（—]/u)[0].trim();
    if (sceneLines.has(japanese) || seen.has(example)) continue;
    seen.add(example);
    examples.push(example);
    if (examples.length === MAX_EXAMPLES) break;
  }
  return examples;
}

export const grammarUsage = defineFeature({
  defaultModel: "gemini-2.5-flash",

  parseInput(body) {
    const lines = objectArray(body, "lines", MAX_LINES).map((line, i) => parseLine(line, `lines[${i}]`));
    if (lines.length === 0) {
      throw new InputError("lines must have at least one line");
    }
    return {
      pattern: requiredString(body, "pattern", 60),
      grammarPointID: optionalString(body, "grammarPointID", 80),
      lines,
    };
  },

  build({ pattern, grammarPointID, lines }) {
    const prompt = [
      `Pattern: ${pattern}`,
      ...(grammarPointID ? [`Curriculum id (hint only): ${grammarPointID}`] : []),
      "",
      "Dialogue:",
      ...lines.map(formatLine),
      "",
      "Return for this pattern only:",
      "• inThisScene — one short sentence on what it does here",
      "• form — how to build it, or empty for a fixed phrase",
      "• examples — 2 to 3 new everyday examples",
      "• note — one short tip, or empty",
    ];
    return {
      systemInstruction: INSTRUCTIONS,
      prompt: prompt.join("\n"),
      responseSchema: {
        type: Type.OBJECT,
        properties: {
          inThisScene: { type: Type.STRING },
          form: { type: Type.STRING },
          examples: { type: Type.ARRAY, items: { type: Type.STRING } },
          note: { type: Type.STRING },
        },
        required: ["inThisScene", "form", "examples", "note"],
        propertyOrdering: ["inThisScene", "form", "examples", "note"],
      },
    };
  },

  parseResult(json, { lines }) {
    const raw = parseJSONObject(json);
    const inThisScene = withoutVerbLabel(trimmedString(raw.inThisScene));
    if (!inThisScene) {
      throw new Error("grammar_usage: empty inThisScene");
    }
    const note = trimmedString(raw.note);
    return {
      inThisScene,
      form: trimmedString(raw.form),
      examples: sanitizedExamples(raw.examples, lines),
      note: note === inThisScene ? "" : note,
    };
  },
});
