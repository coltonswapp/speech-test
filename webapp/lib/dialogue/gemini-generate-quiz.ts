import "server-only";
import {
  DialogueGenerationError,
  generateJsonWithRetries,
} from "@/lib/dialogue/gemini-generate";
import {
  generatedQuizSchema,
  type DialogueLine,
  type GeneratedQuiz,
  type QuizQuestion,
} from "@/lib/dialogue/types";

export type GenerateQuizParams = {
  lines: DialogueLine[];
  setting?: string;
  menuTitle?: string;
  existingQuiz?: QuizQuestion[];
  count: number;
};

const RESPONSE_SCHEMA = `{"questions":[{"prompt":"...","layout":"grid","choices":["...","...","...","..."],"correctChoice":"...","wrongAnswerExplanation":"..."}]}`;

function buildPrompt(params: GenerateQuizParams): string {
  const transcript = params.lines
    .map((line, index) => {
      const english = line.english ? ` (${line.english})` : "";
      return `Line ${index + 1} — ${line.speaker}: ${line.japanese}${english}`;
    })
    .join("\n");

  const sections: string[] = [
    "You are writing comprehension quiz questions for a Japanese dialogue in the Shizen app.",
    "Task: Write multiple-choice questions that test whether a learner understood the dialogue — its facts, sequence of events, and what each speaker said or meant.",
  ];

  if (params.menuTitle?.trim()) {
    sections.push(`Scenario title: ${params.menuTitle.trim()}`);
  }
  if (params.setting?.trim()) {
    sections.push(`Setting: ${params.setting.trim()}`);
  }

  sections.push(`Dialogue:\n${transcript}`);

  if (params.existingQuiz && params.existingQuiz.length > 0) {
    const existing = params.existingQuiz
      .map((question) => `- ${question.prompt}`)
      .join("\n");
    sections.push(
      `Existing quiz questions (write NEW questions that cover different facts, do not repeat these):\n${existing}`,
    );
  }

  sections.push(`Return JSON matching this schema:\n${RESPONSE_SCHEMA}`);

  sections.push(
    [
      "Rules:",
      `- Return exactly ${params.count} question candidates; the editor will pick which ones to keep.`,
      "- prompt, choices, correctChoice, and wrongAnswerExplanation are all in English — this checks comprehension, not vocabulary recall.",
      "- Each question must be answerable from the dialogue alone (a fact stated or clearly implied by a line), not outside knowledge.",
      "- choices: 3-4 plausible options; exactly one must be correct. correctChoice must match one of the choices exactly (verbatim).",
      '- layout is "grid" when choices are short (single words or numbers), "list" when choices are longer phrases.',
      "- wrongAnswerExplanation is 1 short sentence in English explaining the correct answer, referencing the relevant Japanese line.",
      "- Vary what each question tests: facts, sequence, speaker intent, numbers/prices/times if present — don't ask near-duplicate questions.",
      "- Return only the JSON object.",
    ].join("\n"),
  );

  return sections.join("\n\n");
}

export async function generateQuizQuestions(
  params: GenerateQuizParams,
): Promise<GeneratedQuiz> {
  if (params.lines.every((line) => !line.japanese.trim())) {
    throw new DialogueGenerationError(
      "Dialogue has no Japanese text to generate quiz questions from.",
    );
  }
  return generateJsonWithRetries(buildPrompt(params), generatedQuizSchema);
}
