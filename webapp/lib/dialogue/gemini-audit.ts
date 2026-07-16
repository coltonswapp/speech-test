import "server-only";
import {
  DialogueGenerationError,
  generateJsonWithRetries,
} from "@/lib/dialogue/gemini-generate";
import {
  llmAuditResultSchema,
  type DialogueLine,
  type LlmAuditResult,
} from "@/lib/dialogue/types";

export type AuditDialogueParams = {
  lines: DialogueLine[];
  setting?: string;
  menuTitle?: string;
  grammarPointContext: Array<{
    id: string;
    title: string;
    pattern?: string | null;
    shortDefinition?: string | null;
  }>;
};

const RESPONSE_SCHEMA = `{"mistaggedLines":[{"lineIndex":0,"grammarPointID":"point-id","reason":"Brief explanation"}]}`;

function buildPrompt(params: AuditDialogueParams): string {
  const transcript = params.lines
    .map((line, index) => {
      const tags =
        line.grammarPointIDs && line.grammarPointIDs.length > 0
          ? ` [tags: ${line.grammarPointIDs.join(", ")}]`
          : "";
      const romaji = line.romaji ? `\n  romaji: ${line.romaji}` : "";
      const english = line.english ? `\n  english: ${line.english}` : "";
      return `${index}: ${line.speaker}: ${line.japanese}${tags}${romaji}${english}`;
    })
    .join("\n");

  const sections: string[] = [
    "You are auditing Japanese dialogue content for the Shizen learning app.",
    "Task: Find per-line grammarPointIDs tags that do NOT match what the line actually demonstrates.",
    "A tag is wrong when the Japanese (and romaji if present) does not contain or clearly use that grammar point.",
    "Example: tagging n5-kedo (けど) on a line with no けど / kedo is a mistag.",
    "Only report clear mistakes — do not flag borderline cases.",
  ];

  if (params.menuTitle?.trim()) {
    sections.push(`Scenario title: ${params.menuTitle.trim()}`);
  }
  if (params.setting?.trim()) {
    sections.push(`Setting: ${params.setting.trim()}`);
  }

  sections.push(`Dialogue (0-based line indices):\n${transcript}`);

  if (params.grammarPointContext.length > 0) {
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
      `Grammar point catalog (only use these ids in mistaggedLines):\n${points}`
    );
  }

  sections.push(`Return JSON matching this schema:\n${RESPONSE_SCHEMA}`);

  sections.push(
    [
      "Rules:",
      "- mistaggedLines: list each (lineIndex, grammarPointID) pair that should be removed from that line's tags.",
      "- lineIndex is 0-based and must refer to a line in the transcript above.",
      "- grammarPointID must be one of that line's current grammarPointIDs.",
      "- reason: one short sentence explaining why the tag is wrong.",
      "- If all tags look correct, return {\"mistaggedLines\": []}.",
      "- Return only the JSON object.",
    ].join("\n")
  );

  return sections.join("\n\n");
}

export async function auditDialogueWithGemini(
  params: AuditDialogueParams
): Promise<LlmAuditResult> {
  const taggedLineCount = params.lines.filter(
    (line) => (line.grammarPointIDs?.length ?? 0) > 0
  ).length;

  if (taggedLineCount === 0) {
    return { mistaggedLines: [] };
  }

  return generateJsonWithRetries(buildPrompt(params), llmAuditResultSchema);
}

export { DialogueGenerationError };
