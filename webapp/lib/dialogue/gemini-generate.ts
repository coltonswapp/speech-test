import "server-only";
import type { z } from "zod";
import { getProviderKey } from "@/lib/secrets";
import {
  dialogueDifficultyPrompt,
  type DialogueDifficulty,
} from "@/lib/dialogue/difficulty";
import {
  dialogueFormalityPrompt,
  type DialogueFormality,
} from "@/lib/dialogue/formality";
import {
  generatedLinesSchema,
  generatedScenarioSchema,
  type DialogueLine,
  type GeneratedLines,
  type GeneratedScenario,
} from "@/lib/dialogue/types";

// Gemini text generation for dialogue lines. Prompt structure and retry loop
// ported from GrammarContentKit/GrammarSectionGenerator.swift +
// GeminiClient.swift (temperature 0.4, retries at 0.2, up to 3 attempts).

const GEMINI_TEXT_MODEL = "gemini-2.5-flash";
const MAX_ATTEMPTS = 3;

export class DialogueGenerationError extends Error {}

export type GenerateLinesParams = {
  prompt: string;
  setting?: string;
  speakerNames?: string[];
  grammarPointContext?: Array<{
    id: string;
    title: string;
    pattern?: string | null;
    shortDefinition?: string | null;
  }>;
  existingLines?: DialogueLine[];
  mode: "replace" | "append";
  lineCount?: number;
  variantIndex?: number;
  variantCount?: number;
  difficulty?: DialogueDifficulty;
  formality?: DialogueFormality;
};

const RESPONSE_SCHEMA = `{"setting":"...","lines":[{"speaker":"...","japanese":"...","romaji":"...","english":"...","grammarPointIDs":["point-id"]}]}`;

function buildPrompt(params: GenerateLinesParams): string {
  const difficulty = params.difficulty ?? "beginner";
  const formality = params.formality ?? "polite";
  const sections: string[] = [
    "You are authoring Japanese dialogue content for the Shizen Japanese learning app.",
    "Task: Write a natural Japanese conversation as line-by-line dialogue.",
    dialogueDifficultyPrompt(difficulty),
    dialogueFormalityPrompt(formality),
    `Author brief: ${params.prompt.trim()}`,
  ];

  if (params.setting?.trim()) {
    sections.push(`Setting: ${params.setting.trim()}`);
  }

  const speakers = (params.speakerNames ?? []).filter((name) => name.trim());
  if (speakers.length > 0) {
    sections.push(`Speakers (use these exact names): ${speakers.join(", ")}`);
  } else {
    sections.push(
      'Speakers: invent two natural role names in English (e.g. "Tourist", "Attendant").'
    );
  }

  if (params.grammarPointContext && params.grammarPointContext.length > 0) {
    const points = params.grammarPointContext
      .map((point) => {
        const pattern = point.pattern ? ` (${point.pattern})` : "";
        const definition = point.shortDefinition
          ? ` — ${point.shortDefinition}`
          : "";
        return `- ${point.id}: ${point.title}${pattern}${definition}`;
      })
      .join("\n");
    sections.push(
      `Target grammar points (weave in naturally; tag each line with matching ids):\n${points}`
    );
  }

  if (
    params.variantCount &&
    params.variantCount > 1 &&
    params.variantIndex !== undefined
  ) {
    sections.push(
      `This is variation ${params.variantIndex + 1} of ${params.variantCount}. Make it meaningfully different from the other variations while still practicing the target grammar points.`
    );
  }

  if (params.mode === "append" && params.existingLines?.length) {
    const transcript = params.existingLines
      .map((line) => `${line.speaker}: ${line.japanese}`)
      .join("\n");
    sections.push(
      `Existing dialogue (continue naturally from these lines; return ONLY the new lines, do not repeat them):\n${transcript}`
    );
  }

  sections.push(`Return JSON matching this schema:\n${RESPONSE_SCHEMA}`);

  const lineCount = params.lineCount ?? null;
  sections.push(
    [
      "Rules:",
      "- Shizen voice: clear, learner-focused, natural spoken Japanese.",
      `- Vocabulary and sentence complexity must match the ${difficulty} difficulty level above.`,
      `- Speech register must match the ${formality} formality level above.`,
      '- Romaji: Hepburn with macrons, sentence-style capitalization (e.g. "Tōkyō ni ikitai n desu kedo...").',
      "- english is a natural translation, not word-by-word.",
      `- ${lineCount ? `Exactly ${lineCount}` : "6-10"} lines, alternating speakers where natural.`,
      "- Every line needs speaker, japanese, romaji, and english.",
      params.grammarPointContext && params.grammarPointContext.length > 0
        ? "- Each line must include grammarPointIDs: an array of ids from the target grammar list that the line demonstrates (use only ids from that list; omit the field only if no point applies)."
        : "- grammarPointIDs is optional when no target grammar points were provided.",
      "- Return only the JSON object.",
    ].join("\n")
  );

  return sections.join("\n\n");
}

export async function requestGemini(
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
    throw new DialogueGenerationError(
      `Gemini request failed (HTTP ${response.status}): ${body}`
    );
  }

  const json = await response.json();
  const text = json?.candidates?.[0]?.content?.parts
    ?.map((part: { text?: string }) => part?.text ?? "")
    .join("");
  if (typeof text !== "string" || text.trim().length === 0) {
    throw new DialogueGenerationError("Gemini returned no text.");
  }
  return text;
}

// Generic JSON-with-retries wrapper around the Gemini text model: temperature
// 0.4 then 0.2, up to 3 attempts, feeding the previous validation failure back
// into the retry prompt. Shared by dialogue generation and revision.
export async function generateJsonWithRetries<T>(
  basePrompt: string,
  schema: { safeParse: (data: unknown) => z.ZodSafeParseResult<T> }
): Promise<T> {
  const apiKey = getProviderKey("gemini");
  if (!apiKey) {
    throw new DialogueGenerationError("Missing Gemini API key.");
  }

  let lastError = "";

  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    const prompt =
      attempt === 0
        ? basePrompt
        : `${basePrompt}\n\nPrevious attempt failed: ${lastError}. Fix the problem and return valid JSON matching the schema.`;
    const temperature = attempt === 0 ? 0.4 : 0.2;

    let text: string;
    try {
      text = await requestGemini(apiKey, prompt, temperature);
    } catch (error) {
      if (attempt === MAX_ATTEMPTS - 1) throw error;
      lastError = error instanceof Error ? error.message : String(error);
      continue;
    }

    try {
      const parsed = schema.safeParse(JSON.parse(text));
      if (parsed.success) {
        return parsed.data;
      }
      lastError = parsed.error.issues
        .map((issue) => `${issue.path.join(".")}: ${issue.message}`)
        .join("; ");
    } catch (error) {
      lastError = error instanceof Error ? error.message : "Invalid JSON.";
    }
  }

  throw new DialogueGenerationError(
    `Gemini returned invalid JSON after ${MAX_ATTEMPTS} attempts: ${lastError}`
  );
}

export async function generateDialogueLines(
  params: GenerateLinesParams
): Promise<GeneratedLines> {
  return generateJsonWithRetries(buildPrompt(params), generatedLinesSchema);
}

export type GenerateScenarioIdeaParams = {
  prompt: string;
  existingSlugs: string[];
  grammarPointCatalog: Array<{
    id: string;
    title: string;
    pattern?: string | null;
    shortDefinition?: string | null;
  }>;
  difficulty?: DialogueDifficulty;
  formality?: DialogueFormality;
};

const SCENARIO_RESPONSE_SCHEMA = `{"slug":"kebab-case-id","menuTitle":"...","setting":"...","grammarPointIds":["point-id"]}`;

function buildScenarioPrompt(params: GenerateScenarioIdeaParams): string {
  const difficulty = params.difficulty ?? "beginner";
  const formality = params.formality ?? "polite";
  const sections: string[] = [
    "You are authoring a new dialogue scenario for the Shizen Japanese learning app.",
    "Task: Invent a short, natural real-world scenario for a Japanese conversation practice exercise.",
    dialogueDifficultyPrompt(difficulty),
    dialogueFormalityPrompt(formality),
    `Author brief: ${params.prompt.trim()}`,
  ];

  if (params.existingSlugs.length > 0) {
    sections.push(
      `Existing scenario slugs in this collection (avoid duplicating the idea or slug): ${params.existingSlugs.join(", ")}`
    );
  }

  if (params.grammarPointCatalog.length > 0) {
    const points = params.grammarPointCatalog
      .map((point) => {
        const pattern = point.pattern ? ` (${point.pattern})` : "";
        const definition = point.shortDefinition
          ? ` — ${point.shortDefinition}`
          : "";
        return `- ${point.id}: ${point.title}${pattern}${definition}`;
      })
      .join("\n");
    sections.push(
      `Grammar point catalog (choose 1-3 ids that fit the scenario naturally; use only ids from this list):\n${points}`
    );
  }

  sections.push(`Return JSON matching this schema:\n${SCENARIO_RESPONSE_SCHEMA}`);

  sections.push(
    [
      "Rules:",
      "- slug is kebab-case, 2-5 words, unique from the existing slugs above.",
      "- menuTitle is a short human-friendly title (e.g. \"Buying a ticket\").",
      "- setting is 1-2 sentences describing who is talking and why, enough to brief a dialogue writer.",
      "- grammarPointIds must only use ids from the catalog provided; omit the field only if no catalog was provided.",
      "- Return only the JSON object.",
    ].join("\n")
  );

  return sections.join("\n\n");
}

export async function generateScenarioIdea(
  params: GenerateScenarioIdeaParams
): Promise<GeneratedScenario> {
  return generateJsonWithRetries(
    buildScenarioPrompt(params),
    generatedScenarioSchema
  );
}
