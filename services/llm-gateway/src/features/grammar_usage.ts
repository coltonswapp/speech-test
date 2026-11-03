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
import { GEMINI_35_FLASH_LITE, PARTICLE_READING_RULE } from "./models.js";
import { defineFeature } from "./types.js";

const MAX_LINES = 12;
const MAX_EXAMPLES = 3;

const INSTRUCTIONS = `You help English-speaking Japanese learners see how one grammar pattern from a dialogue is used.

The learner tapped a pattern label such as "___ ちゃいけない" or "〜ていい？". "___" and "〜" mark where other words go. Lines marked → use the pattern. When no line is marked, find the line that uses it. Other lines are context only.

Explain how this pattern is featured in the → line. Not the whole line. Not the whole conversation.

inThisScene:
- Quote the exact stretch from the → line that is this pattern (the word that fills the slot plus the pattern ending).
- Then one short sentence: what that stretch is doing here.
- Example: "飲んじゃいけない — saying you must not drink (here)."
- Example: "青いの方が — saying the blue one is more (lighter) than the other."
- Do not translate the whole line. Do not retell the conversation.

form:
- Break down how this line builds the pattern, using those actual words.
- Slot-fill + pattern: "飲んで + じゃいけない (て→じゃ)", "青い + の方が".
- After a semicolon, add the generic recipe so they can make their own: "verb て-form + じゃいけない", "い-adjective + のほうが".
- Only these labels in the recipe: verb, noun, い-adjective, な-adjective, dictionary form, ます-form, て-form, ない-form, た-form. No other grammar terms.
- Empty string when the pattern is a fixed phrase that does not attach to other words.

examples:
- 2 to 3 short everyday examples of the same pattern with different words than the dialogue.
- Each item is the Japanese, then " — ", then a plain English gloss.
- When the Japanese has any kanji, add a hiragana reading of the whole example in parentheses after the Japanese and before the em dash: 窓を開けてもいい？ (まどおあけてもいい？) — Can I open the window?
- Hiragana only. Not romaji. Not a reading of only the kanji. If the Japanese is already all kana, do not add a reading: これ、食べてもいい？ needs one; ちょっといい？ does not.
- ${PARTICLE_READING_RULE}
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
  defaultModel: GEMINI_35_FLASH_LITE,

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
      "• inThisScene — the exact stretch from the → line, then what it does here",
      "• form — this line's breakdown, then the generic recipe, or empty for a fixed phrase",
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
