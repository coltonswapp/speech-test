import "server-only";
import {
  DialogueGenerationError,
  generateJsonWithRetries,
} from "@/lib/dialogue/gemini-generate";
import {
  formatDialogueTranscriptLine,
  generatedQuizSchema,
  hasSpokenJapanese,
  isSpokenLine,
  spokenLinesOf,
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

const RESPONSE_SCHEMA = `{"questions":[{"prompt":"...","layout":"grid","choices":["...","...","...","..."],"correctChoice":"...","wrongAnswerExplanation":"...","sourceSpokenStart":0,"sourceSpokenEnd":0}]}`;

function buildPrompt(params: GenerateQuizParams): string {
  const spoken = spokenLinesOf(params.lines);
  const transcript = params.lines
    .map((line, index) => {
      if (!isSpokenLine(line)) {
        return `Line ${index + 1} — ${formatDialogueTranscriptLine(line)}`;
      }
      const english = line.english ? ` (${line.english})` : "";
      return `Line ${index + 1} — ${line.speaker}: ${line.japanese}${english}`;
    })
    .join("\n");

  const spokenIndexGuide = spoken
    .map((line, spokenIndex) => {
      const english = line.english ? ` (${line.english})` : "";
      return `Spoken ${spokenIndex} — ${line.speaker}: ${line.japanese}${english}`;
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
  sections.push(
    `Spoken-only index map (use these integers for sourceSpokenStart / sourceSpokenEnd; stage and inline-question rows are NOT indexed):\n${spokenIndexGuide}`,
  );

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
      "- When the answer is grounded in a specific spoken line (or short consecutive range), set sourceSpokenStart to that spoken-only index from the Spoken index map. Optionally set sourceSpokenEnd (inclusive) for a multi-line span. Omit both when no single spoken span clearly supports the question.",
      `- sourceSpokenStart / sourceSpokenEnd must be integers in 0..${Math.max(spoken.length - 1, 0)} from the Spoken index map only — never display Line numbers, stage rows, or inline-question rows.`,
      "- Vary what each question tests: facts, sequence, speaker intent, numbers/prices/times if present — don't ask near-duplicate questions.",
      "- Return only the JSON object.",
    ].join("\n"),
  );

  return sections.join("\n\n");
}

export async function generateQuizQuestions(
  params: GenerateQuizParams,
): Promise<GeneratedQuiz> {
  if (!hasSpokenJapanese(params.lines)) {
    throw new DialogueGenerationError(
      "Dialogue has no Japanese text to generate quiz questions from.",
    );
  }
  return generateJsonWithRetries(buildPrompt(params), generatedQuizSchema);
}
