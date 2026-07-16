import "server-only";
import {
  DialogueGenerationError,
  generateJsonWithRetries,
} from "@/lib/dialogue/gemini-generate";
import {
  extractedHighlightsSchema,
  type DialogueLine,
  type ExtractedHighlights,
} from "@/lib/dialogue/types";

export type ExtractHighlightsParams = {
  lines: DialogueLine[];
  setting?: string;
  menuTitle?: string;
  grammarPointContext?: Array<{
    id: string;
    title: string;
    pattern?: string | null;
    shortDefinition?: string | null;
  }>;
};

const RESPONSE_SCHEMA = `{"vocabulary":["単語"],"grammarPatterns":[{"label":"〜たいんですけど。。。","grammarPointID":"point-id"}],"contextNotes":["Optional cultural note"]}`;

function buildPrompt(params: ExtractHighlightsParams): string {
  const transcript = params.lines
    .map((line, index) => {
      const english = line.english ? ` (${line.english})` : "";
      const tags =
        line.grammarPointIDs && line.grammarPointIDs.length > 0
          ? ` [grammarPointIDs: ${line.grammarPointIDs.join(", ")}]`
          : "";
      return `Line ${index + 1} — ${line.speaker}: ${line.japanese}${english}${tags}`;
    })
    .join("\n");

  const sections: string[] = [
    "You are curating learning highlights for a Japanese dialogue in the Shizen app.",
    "Task: Extract useful vocabulary and grammar pattern labels that learners should notice while studying this conversation.",
    "These become the VOCAB and GRAMMAR pills shown after the dialogue — keep them short, concrete, and drawn from the lines.",
  ];

  if (params.menuTitle?.trim()) {
    sections.push(`Scenario title: ${params.menuTitle.trim()}`);
  }
  if (params.setting?.trim()) {
    sections.push(`Setting: ${params.setting.trim()}`);
  }

  sections.push(`Dialogue:\n${transcript}`);

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
      `Linked grammar points (use these ids when a pattern clearly matches; label should look like the spoken form in the dialogue):\n${points}`
    );
  }

  sections.push(`Return JSON matching this schema:\n${RESPONSE_SCHEMA}`);

  sections.push(
    [
      "Rules:",
      "- vocabulary: 6–16 short Japanese entries useful for learners (words, set phrases, or verb dictionary forms). Prefer forms that appear in the dialogue. Use \"行く / 行きたい\" style when both base and conjugated forms matter. No romaji, no English.",
      "- grammarPatterns: 1–6 spoken-form labels copied from the dialogue (e.g. \"〜たいんですけど。。。\", \"〜です\", \"お〜ください\"). Labels must quote how the pattern actually sounds in the lines — not catalog titles like \"The 〜たい form\". Include grammarPointID when it matches an id from the linked list and that point appears on the tagged line(s).",
      "- For each grammarPointID tagged on a line, prefer one pattern entry with a label taken from that line's Japanese.",
      "- contextNotes: 0–3 short English notes about culture, register, or situation — omit when nothing useful to add.",
      "- Do not invent vocabulary that is not present or closely implied by the dialogue.",
      "- Return only the JSON object.",
    ].join("\n")
  );

  return sections.join("\n\n");
}

export async function extractDialogueHighlights(
  params: ExtractHighlightsParams
): Promise<ExtractedHighlights> {
  if (params.lines.every((line) => !line.japanese.trim())) {
    throw new DialogueGenerationError(
      "Dialogue has no Japanese text to extract highlights from."
    );
  }
  return generateJsonWithRetries(buildPrompt(params), extractedHighlightsSchema);
}
