import { Type } from "@google/genai";

import { InputError, isObject, objectArray, optionalString, parseJSONObject, trimmedString, type Body } from "../validate.js";
import { defineFeature } from "./types.js";

const MAX_NEIGHBORS = 2;

const INSTRUCTIONS = `You help English-speaking Japanese learners notice what one dialogue line really means — especially anything hidden in context.

Surrounding lines (up to two before and two after) are for context only. Explain the focused line, not the whole conversation.

Keep it light. One idea per field. Short sentences. No linguistics jargon, no lectures, no stacked interpretations, no cultural essays.

The learner is looking at this line alone and usually does not know who said what. Write about what the line is doing, not who is doing it. Do not name speakers, roles, or characters, and do not use he/she or other identity details, unless the implication is otherwise unclear.

Japanese often hides the real move in a light way:
- Naming something can be an offer (麦茶です。冷たいですよ。).
- Stating a circumstance and trailing off can be a polite no (今から駅なんですけど → can’t take the tea; heading to the station).

The learner already sees a translation. Do not translate the line again, and do not give it a short title.

impliedMeaning: one short sentence explaining what the line is doing, written so it is clearly an interpretation. Good: お疲れ → "A common way to greet someone you know, like a coworker." Good: 麦茶です。冷たいですよ。 → "Offering a cold drink without actually asking." Bad: "Greeting Mika." Bad: "Hey Mika, good work." Do not name people who appear in the line. Do not start with a bare label. Empty only when the line has no social move to explain.

naturalMeaning: always an empty string. Do not put the explanation here.

notes: at most one short sentence on a single tell (trailing けど, ですよ). Empty if impliedMeaning already covers it. Do not repeat the explanation.

Return a JSON object with "naturalMeaning", "impliedMeaning", and "notes" string fields.`;

type Line = { speaker?: string; japanese: string; english?: string };

function parseLine(body: Body, label: string): Line {
  const japanese = typeof body.japanese === "string" ? body.japanese.trim() : "";
  if (!japanese || japanese.length > 300) {
    throw new InputError(`${label}.japanese must be a non-empty string (max 300 chars)`);
  }
  return {
    speaker: optionalString(body, "speaker", 64),
    japanese,
    english: optionalString(body, "english", 500),
  };
}

function formatLine(line: Line, focused: boolean): string {
  const head = `${focused ? "→ " : "  "}${line.japanese}`;
  if (focused || !line.english) return head;
  return `${head}\n     (${line.english})`;
}

export const dialogueNuance = defineFeature({
  defaultModel: "gemini-2.5-flash",

  parseInput(body) {
    if (!isObject(body.focused)) {
      throw new InputError("focused must be an object");
    }
    return {
      preceding: objectArray(body, "preceding", MAX_NEIGHBORS).map((line, i) => parseLine(line, `preceding[${i}]`)),
      focused: parseLine(body.focused, "focused"),
      following: objectArray(body, "following", MAX_NEIGHBORS).map((line, i) => parseLine(line, `following[${i}]`)),
    };
  },

  build({ preceding, focused, following }) {
    const lines: string[] = [];
    if (preceding.length > 0 || following.length > 0) {
      lines.push("Dialogue (context; the line marked → is the focus):");
      preceding.forEach((line) => lines.push(formatLine(line, false)));
      lines.push(formatLine(focused, true));
      following.forEach((line) => lines.push(formatLine(line, false)));
      lines.push("");
    }
    lines.push(`Focused Japanese: ${focused.japanese}`);
    if (focused.english) {
      lines.push(`English hint (may be approximate): ${focused.english}`);
    }
    lines.push(
      "",
      "Stay brief. One idea per field. Do not over-explain.",
      "Do not mention who spoke unless that identity is required to understand the line.",
      "",
      "Return for the focused line only:",
      "• impliedMeaning — one short sentence explaining the move, not a translation or a title",
      "• naturalMeaning — empty string",
      "• notes — one short tell, or empty",
    );
    return {
      systemInstruction: INSTRUCTIONS,
      prompt: lines.join("\n"),
      responseSchema: {
        type: Type.OBJECT,
        properties: {
          naturalMeaning: { type: Type.STRING },
          impliedMeaning: { type: Type.STRING },
          notes: { type: Type.STRING },
        },
        required: ["naturalMeaning", "impliedMeaning", "notes"],
      },
    };
  },

  parseResult(json) {
    const raw = parseJSONObject(json);
    if (typeof raw.impliedMeaning !== "string") {
      throw new Error("dialogue_nuance: missing impliedMeaning");
    }
    return {
      naturalMeaning: trimmedString(raw.naturalMeaning),
      impliedMeaning: raw.impliedMeaning.trim(),
      notes: trimmedString(raw.notes),
    };
  },
});
