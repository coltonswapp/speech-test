import "server-only";
import {
  dialogueDifficultyPrompt,
  type DialogueDifficulty,
} from "@/lib/dialogue/difficulty";
import {
  dialogueFormalityPrompt,
  type DialogueFormality,
} from "@/lib/dialogue/formality";
import {
  formatDialogueTranscriptLine,
  generatedLinesSchema,
  isSpokenLine,
  revisedSelectionSchema,
  type DialogueLine,
  type ReviseLinesResult,
} from "@/lib/dialogue/types";
import {
  DialogueGenerationError,
  generateJsonWithRetries,
} from "@/lib/dialogue/gemini-generate";

// LLM revision of existing dialogue lines. Unlike generation, revision edits
// in place: "selection" scope returns per-index replacements (the untouched
// lines never round-trip through the model, so they can't drift), "all" scope
// rewrites the whole dialogue and may add or remove lines.

export type ReviseLinesParams = {
  lines: DialogueLine[];
  scope: "selection" | "all";
  selectedIndices?: number[];
  instructions: string;
  setting?: string;
  menuTitle?: string;
  grammarPointContext?: Array<{
    id: string;
    title: string;
    pattern?: string | null;
    shortDefinition?: string | null;
  }>;
  difficulty?: DialogueDifficulty;
  formality?: DialogueFormality;
};

const SELECTION_RESPONSE_SCHEMA = `{"revisions":[{"index":0,"line":{"speaker":"...","japanese":"...","romaji":"...","english":"...","grammarPointIDs":["point-id"]}}]}`;
const ALL_RESPONSE_SCHEMA = `{"setting":"...","lines":[{"speaker":"...","japanese":"...","romaji":"...","english":"...","grammarPointIDs":["point-id"]}]}`;

function transcript(lines: DialogueLine[]): string {
  return lines
    .map((line, index) => {
      if (!isSpokenLine(line)) {
        return formatDialogueTranscriptLine(line, index);
      }
      const parts = [`[${index}] ${line.speaker}: ${line.japanese}`];
      if (line.romaji) parts.push(`    romaji: ${line.romaji}`);
      if (line.english) parts.push(`    english: ${line.english}`);
      if (line.grammarPointIDs?.length) {
        parts.push(`    grammar: ${line.grammarPointIDs.join(", ")}`);
      }
      return parts.join("\n");
    })
    .join("\n");
}

function buildPrompt(params: ReviseLinesParams): string {
  const difficulty = params.difficulty ?? "beginner";
  const formality = params.formality ?? "polite";
  const sections: string[] = [
    "You are revising Japanese dialogue content for the Shizen Japanese learning app.",
    dialogueDifficultyPrompt(difficulty),
    dialogueFormalityPrompt(formality),
  ];

  if (params.menuTitle?.trim()) {
    sections.push(`Scenario: ${params.menuTitle.trim()}`);
  }
  if (params.setting?.trim()) {
    sections.push(`Setting: ${params.setting.trim()}`);
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
      `Target grammar points (keep them woven in; tag lines with matching ids):\n${points}`
    );
  }

  sections.push(
    `Current dialogue (lines numbered by index):\n${transcript(params.lines)}`
  );

  sections.push(`Revision instructions: ${params.instructions.trim()}`);

  if (params.scope === "selection") {
    const indices = params.selectedIndices ?? [];
    sections.push(
      [
        `Revise ONLY the lines at indices ${indices.join(", ")} according to the instructions.`,
        "The other lines are context — do not return them.",
        `Return JSON matching this schema:\n${SELECTION_RESPONSE_SCHEMA}`,
      ].join("\n")
    );
  } else {
    sections.push(
      [
        "Rewrite the dialogue according to the instructions. You may add, remove, or reorder lines.",
        `Return JSON matching this schema:\n${ALL_RESPONSE_SCHEMA}`,
      ].join("\n")
    );
  }

  sections.push(
    [
      "Rules:",
      "- Shizen voice: clear, learner-focused, natural spoken Japanese.",
      `- Vocabulary and sentence complexity must match the ${difficulty} difficulty level above.`,
      `- Speech register must match the ${formality} formality level above.`,
      '- Romaji: Hepburn with macrons, sentence-style capitalization (e.g. "Tōkyō ni ikitai n desu kedo...").',
      "- english is a natural translation, not word-by-word.",
      "- Keep speaker names exactly as they appear in the current dialogue unless instructed otherwise.",
      "- Every returned line needs speaker, japanese, romaji, and english.",
      "- Return only the JSON object.",
    ].join("\n")
  );

  return sections.join("\n\n");
}

export async function reviseDialogueLines(
  params: ReviseLinesParams
): Promise<ReviseLinesResult> {
  if (params.scope === "selection") {
    const indices = [...new Set(params.selectedIndices ?? [])].filter(
      (i) => i >= 0 && i < params.lines.length
    );
    if (indices.length === 0) {
      throw new DialogueGenerationError("Select at least one line to revise.");
    }

    const result = await generateJsonWithRetries(
      buildPrompt({ ...params, selectedIndices: indices }),
      revisedSelectionSchema
    );
    const allowed = new Set(indices);
    const revisions = result.revisions.filter((r) => allowed.has(r.index));
    if (revisions.length === 0) {
      throw new DialogueGenerationError(
        "The model did not revise any of the selected lines."
      );
    }
    return { scope: "selection", revisions };
  }

  const generated = await generateJsonWithRetries(
    buildPrompt(params),
    generatedLinesSchema
  );
  return { scope: "all", generated };
}
