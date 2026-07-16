import "server-only";
import { getProviderKey } from "@/lib/secrets";
import { grammarPointSchema, type GrammarPointInput } from "@/lib/content/types";
import { validatePoint } from "@/lib/content/validator";

// Ported from GrammarContentKit/Sources/GrammarContentKit/GrammarPointGenerator.swift
// and GrammarSectionGenerator.swift. Prompt structure, retry loop (temperature 0.4
// then 0.2, up to 3 attempts), and gold-example few-shot context mirror the Swift
// implementation; see also lib/dialogue/gemini-generate.ts for the sibling port.

const GEMINI_TEXT_MODEL = "gemini-2.5-flash";
const MAX_ATTEMPTS = 3;

export class GrammarGenerationError extends Error {}

export type GoldExample = Pick<
  GrammarPointInput,
  | "id"
  | "orderIndex"
  | "title"
  | "headlineEnglish"
  | "blurb"
  | "forms"
  | "formation"
  | "usage"
  | "usageLadders"
  | "relatedPointIDs"
  | "examples"
  | "pattern"
  | "reading"
  | "shortDefinition"
  | "structure"
  | "register"
  | "contrastDrills"
>;

function goldJSON(gold: GoldExample[]): string {
  if (gold.length === 0) return "[]";
  return JSON.stringify({ points: gold });
}

async function requestGemini(
  apiKey: string,
  prompt: string,
  temperature: number
): Promise<string> {
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_TEXT_MODEL}:generateContent`,
    {
      method: "POST",
      headers: {
        "x-goog-api-key": apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: {
          temperature,
          responseMimeType: "application/json",
        },
      }),
    }
  );

  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new GrammarGenerationError(
      `Gemini request failed (HTTP ${response.status}): ${body}`
    );
  }

  const json = await response.json();
  const text = json?.candidates?.[0]?.content?.parts
    ?.map((part: { text?: string }) => part?.text ?? "")
    .join("");
  if (typeof text !== "string" || text.trim().length === 0) {
    throw new GrammarGenerationError("Gemini returned no text.");
  }
  return text;
}

function stripCodeFence(text: string): string {
  let trimmed = text.trim();
  if (trimmed.startsWith("```")) {
    trimmed = trimmed
      .replace(/```json/g, "")
      .replace(/```/g, "")
      .trim();
  }
  return trimmed;
}

// --- Full grammar point generation ---

export type GrammarGenerationRequest = {
  pointID: string;
  title: string;
  headlineEnglish?: string;
  orderIndex: number;
};

const pointSchemaDescription = `
Return a JSON object with a single key "grammarPoint" whose value matches this schema:

{
  "id": "string (slug like n5-cha-ikenai)",
  "orderIndex": number,
  "title": "Japanese pattern name",
  "pattern": "display pattern (defaults to title)",
  "reading": "romaji reading of the pattern",
  "shortDefinition": "one-line English gloss",
  "headlineEnglish": "same as shortDefinition for compatibility",
  "blurb": "contextual paragraph: register, nuance, who says it",
  "structure": "how the pattern is built — formation rule as plain text",
  "register": "casual|polite|formal",
  "forms": ["surface forms"],
  "formation": [{"title": "optional", "body": "legacy teaching blocks — mirror structure"}],
  "relatedPointIDs": ["other point ids"],
  "examples": [{
    "japanese": "...",
    "romaji": "...",
    "english": "...",
    "targetSubstring": "highlighted morpheme",
    "sourceScenarioId": "optional dialogue scenario id",
    "scenario": {
      "setting": "one-line English scene setter",
      "lines": [{"speaker": "...", "japanese": "...", "romaji": "...", "english": "..."}]
    }
  }],
  "contrastDrills": [{
    "contrastLabel": "のむ → のんで → ?",
    "choices": ["のんちゃ", "のんじゃ"],
    "correctChoice": "のんじゃ",
    "ruleTargeted": "optional note on the rule tested"
  }]
}

Rules:
- 3-4 curated examples per point; at least one with a 2-4 line scenario dialogue.
- Include 1-3 contrastDrills only. Do NOT include meaningChoice, formChoice, sentenceBuilder, or precursorChoice drills.
- Write in Shizen voice: clear, learner-focused, not textbook-dry.
- Romaji should be lowercase with spaces between words.
- targetSubstring must appear verbatim in the example japanese.
- Do not include status, reviewNotes, or _provenance fields.
`.trim();

export function buildPointPrompt(
  request: GrammarGenerationRequest,
  goldExamples: GoldExample[]
): string {
  const headline = request.headlineEnglish ? ` (${request.headlineEnglish})` : "";
  return `
You are authoring JLPT N5 grammar reference content for the Shizen Japanese learning app.

${pointSchemaDescription}

Gold-standard approved examples (match this depth and voice):
${goldJSON(goldExamples)}

Generate a complete grammar point for:
- id: ${request.pointID}
- orderIndex: ${request.orderIndex}
- title: ${request.title}${headline}

Return only valid JSON with the grammarPoint wrapper object.
`.trim();
}

export type GrammarGenerationResult = {
  point: GrammarPointInput;
  validationIssues: string[];
  attemptCount: number;
};

export async function generateGrammarPoint(
  request: GrammarGenerationRequest,
  goldExamples: GoldExample[]
): Promise<GrammarGenerationResult> {
  const apiKey = getProviderKey("gemini");
  if (!apiKey) {
    throw new GrammarGenerationError("Missing Gemini API key.");
  }

  let lastIssues: string[] = [];

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    let prompt = buildPointPrompt(request, goldExamples);
    if (attempt > 1 && lastIssues.length > 0) {
      prompt += `\n\nPrevious attempt failed validation: ${lastIssues.join("; ")}. Fix all issues.`;
    }

    const temperature = attempt === 1 ? 0.4 : 0.2;

    let text: string;
    try {
      text = await requestGemini(apiKey, prompt, temperature);
    } catch (error) {
      lastIssues = [error instanceof Error ? error.message : String(error)];
      continue;
    }

    let raw: unknown;
    try {
      raw = JSON.parse(stripCodeFence(text));
    } catch {
      lastIssues = ["Could not parse JSON response"];
      continue;
    }

    const wrapped =
      raw && typeof raw === "object" && "grammarPoint" in raw
        ? (raw as { grammarPoint: unknown }).grammarPoint
        : raw;

    const parsed = grammarPointSchema.safeParse(wrapped);
    if (!parsed.success) {
      lastIssues = parsed.error.issues.map(
        (issue) => `${issue.path.join(".")}: ${issue.message}`
      );
      continue;
    }

    const normalized: GrammarPointInput = {
      ...parsed.data,
      id: request.pointID,
      orderIndex: request.orderIndex,
      status: "draft",
      reviewNotes: undefined,
    };

    const issues = validatePoint(normalized).map((i) => i.message);
    if (issues.length === 0) {
      return { point: normalized, validationIssues: [], attemptCount: attempt };
    }
    lastIssues = issues;
  }

  throw new GrammarGenerationError(
    `Generation failed after ${MAX_ATTEMPTS} attempts: ${lastIssues.join("; ")}`
  );
}

// --- Section (re)generation ---

export type SectionTask =
  | "overview"
  | "formation"
  | "usage"
  | "usageLadders"
  | "example"
  | "drills";

const taskText: Record<SectionTask, string> = {
  overview:
    "Generate overview content: blurb (1-2 paragraphs, Shizen voice) and forms array. " +
    "Optionally refine headlineEnglish. Align with the point title and any existing examples.",
  formation:
    "Generate 1-3 formation teaching blocks explaining how to build this pattern. " +
    "Must synergize with blurb, forms, and existing examples. Append-quality content.",
  usage:
    "Generate 1-3 usage teaching blocks: when/how to use, nuance, pitfalls. " +
    "Must synergize with formation, blurb, and examples.",
  usageLadders:
    "Generate usageLadders with Everyday/Casual/Formal register levels for 2-3 verbs relevant to this pattern.",
  example:
    "Generate ONE new example (japanese, romaji, english, targetSubstring). " +
    "Use a fresh situation not covered by existing examples. Include scenario dialogue when natural. " +
    "targetSubstring must appear verbatim in japanese.",
  drills:
    "Generate a complete drills array for this point from its examples and teaching. " +
    "Include meaningChoice, sentenceBuilder, sentenceChoice. Use real example sentences for precursorChoice. " +
    "For sentenceBuilder: set buildComponents to the correct tiles and correctChoice to their concatenation.",
};

const sectionSchema: Record<SectionTask, string> = {
  overview: `{"blurb":"string","forms":["string"],"headlineEnglish":"optional string"}`,
  formation: `{"formation":[{"title":"optional string","body":"string"}]}`,
  usage: `{"usage":[{"title":"optional string","body":"string"}]}`,
  usageLadders: `{"usageLadders":[{"label":"verb","levels":[{"japanese":"...","register":"Everyday|Casual|Formal"}]}]}`,
  example: `{"example":{"japanese":"...","romaji":"...","english":"...","targetSubstring":"...","scenario":{"setting":"...","lines":[{"speaker":"...","japanese":"...","romaji":"...","english":"..."}]}}}`,
  drills: `{"drills":[{"kind":"meaningChoice|sentenceBuilder|sentenceChoice|formChoice|contrastChoice|precursorChoice","instruction":"...","choices":["..."],"correctChoice":"...","english":"optional","buildComponents":["optional"],"exampleJapanese":"optional","targetSubstring":"optional"}]}`,
};

export function buildSectionPrompt(
  task: SectionTask,
  context: GrammarPointInput,
  goldExamples: GoldExample[],
  customInstructions?: string
): string {
  const instructions = customInstructions?.trim();
  return `
You are authoring JLPT N5 grammar lesson content for the Shizen Japanese learning app.

Current grammar point (use as context — stay consistent):
${JSON.stringify(context)}

Gold-standard approved points (match depth and voice):
${goldJSON(goldExamples)}

Task: ${taskText[task]}
${instructions ? `\nAuthor instructions (follow carefully):\n${instructions}\n` : ""}

Return JSON matching this schema:
${sectionSchema[task]}

Rules:
- Shizen voice: clear, learner-focused.
- Romaji lowercase with spaces.
- Synergize with existing content; do not contradict examples or formation.
- No status, reviewNotes, or _provenance fields.
`.trim();
}

export type SectionGenerationResult = {
  blurb?: string;
  headlineEnglish?: string;
  forms?: string[];
  formation?: { title?: string; body: string }[];
  usage?: { title?: string; body: string }[];
  usageLadders?: NonNullable<GrammarPointInput["usageLadders"]>;
  example?: GrammarPointInput["examples"][number];
  drills?: GrammarPointInput["drills"];
  attemptCount: number;
};

function applySectionResult(
  result: SectionGenerationResult,
  point: GrammarPointInput
): GrammarPointInput {
  const merged: GrammarPointInput = { ...point };
  if (result.blurb !== undefined) merged.blurb = result.blurb;
  if (result.headlineEnglish !== undefined) merged.headlineEnglish = result.headlineEnglish;
  if (result.forms !== undefined) merged.forms = result.forms;
  if (result.formation !== undefined) {
    merged.formation = [
      ...point.formation,
      ...result.formation.map((b) => ({ title: b.title ?? "", body: b.body })),
    ];
  }
  if (result.usage !== undefined) {
    merged.usage = [
      ...(point.usage ?? []),
      ...result.usage.map((b) => ({ title: b.title ?? "", body: b.body })),
    ];
  }
  if (result.usageLadders !== undefined) {
    merged.usageLadders = [...(point.usageLadders ?? []), ...result.usageLadders];
  }
  if (result.example !== undefined) {
    merged.examples = [...point.examples, result.example];
  }
  if (result.drills !== undefined) {
    merged.drills = result.drills;
  }
  return merged;
}

function decodeSectionPayload(task: SectionTask, payload: unknown): SectionGenerationResult {
  const obj = (payload ?? {}) as Record<string, unknown>;
  const result: SectionGenerationResult = { attemptCount: 0 };

  switch (task) {
    case "overview": {
      if (typeof obj.blurb === "string") result.blurb = obj.blurb;
      if (Array.isArray(obj.forms)) result.forms = obj.forms as string[];
      if (typeof obj.headlineEnglish === "string") result.headlineEnglish = obj.headlineEnglish;
      break;
    }
    case "formation": {
      const formation = Array.isArray(obj.formation) ? obj.formation : Array.isArray(payload) ? payload : null;
      if (!formation || formation.length === 0) throw new GrammarGenerationError("Missing formation blocks");
      result.formation = formation as { title?: string; body: string }[];
      break;
    }
    case "usage": {
      const usage = Array.isArray(obj.usage) ? obj.usage : Array.isArray(payload) ? payload : null;
      if (!usage || usage.length === 0) throw new GrammarGenerationError("Missing usage blocks");
      result.usage = usage as { title?: string; body: string }[];
      break;
    }
    case "usageLadders": {
      const ladders = Array.isArray(obj.usageLadders)
        ? obj.usageLadders
        : Array.isArray(payload)
          ? payload
          : null;
      if (!ladders || ladders.length === 0) throw new GrammarGenerationError("Missing usageLadders");
      result.usageLadders = ladders as NonNullable<GrammarPointInput["usageLadders"]>;
      break;
    }
    case "example": {
      const example = obj.example ?? (Array.isArray(obj.examples) ? obj.examples[0] : null) ?? payload;
      if (!example || typeof example !== "object") throw new GrammarGenerationError("Missing example");
      const ex = example as Record<string, unknown>;
      if (typeof ex.japanese !== "string" || !ex.japanese.trim()) {
        throw new GrammarGenerationError("Example missing japanese");
      }
      if (typeof ex.english !== "string" || !ex.english.trim()) {
        throw new GrammarGenerationError("Example missing english");
      }
      result.example = {
        japanese: ex.japanese,
        romaji: typeof ex.romaji === "string" ? ex.romaji : "",
        english: ex.english,
        targetSubstring: typeof ex.targetSubstring === "string" ? ex.targetSubstring : undefined,
        scenario:
          ex.scenario && typeof ex.scenario === "object"
            ? (ex.scenario as GrammarPointInput["examples"][number]["scenario"])
            : undefined,
      };
      break;
    }
    case "drills": {
      const drills = Array.isArray(obj.drills) ? obj.drills : Array.isArray(payload) ? payload : null;
      if (!drills || drills.length === 0) throw new GrammarGenerationError("Missing drills");
      result.drills = drills as GrammarPointInput["drills"];
      break;
    }
  }

  return result;
}

export async function regenerateSection(
  task: SectionTask,
  context: GrammarPointInput,
  goldExamples: GoldExample[],
  customInstructions?: string
): Promise<{ result: SectionGenerationResult; point: GrammarPointInput }> {
  const apiKey = getProviderKey("gemini");
  if (!apiKey) {
    throw new GrammarGenerationError("Missing Gemini API key.");
  }

  let lastError = "Unknown error";

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    let prompt = buildSectionPrompt(task, context, goldExamples, customInstructions);
    if (attempt > 1) {
      prompt += `\n\nPrevious attempt failed: ${lastError}. Fix and return valid JSON.`;
    }
    const temperature = attempt === 1 ? 0.4 : 0.2;

    let text: string;
    try {
      text = await requestGemini(apiKey, prompt, temperature);
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
      continue;
    }

    let payload: unknown;
    try {
      payload = JSON.parse(stripCodeFence(text));
    } catch {
      lastError = "Could not parse JSON response";
      continue;
    }
    // Full-point generation wraps sections in grammarPoint; unwrap only that case.
    if (payload && typeof payload === "object" && "grammarPoint" in payload) {
      payload = (payload as { grammarPoint: unknown }).grammarPoint;
    }

    try {
      const result = { ...decodeSectionPayload(task, payload), attemptCount: attempt };
      const merged = applySectionResult(result, context);
      const issues = validatePoint(merged).map((i) => i.message);
      if (issues.length === 0) {
        return { result, point: merged };
      }
      lastError = issues.join("; ");
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
    }
  }

  throw new GrammarGenerationError(
    `Section generation failed after ${MAX_ATTEMPTS} attempts: ${lastError}`
  );
}
