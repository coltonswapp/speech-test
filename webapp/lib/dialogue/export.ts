import {
  isInlineQuestionLine,
  isStageLine,
  type CollectionFile,
  type DialogueHighlights,
  type DialogueLine,
  type PublishedTokenSync,
  type QuizQuestion,
  type ScenarioFile,
} from "@/lib/dialogue/types";
import { parsePublishedTokenSync } from "@/lib/dialogue/token-sync";

// Structural input types satisfied by both the drizzle rows (jsonb columns
// infer as unknown) and the client-side types in lib/dialogue/client.ts, so
// the collection file can be assembled on either side.
export type ExportableCollection = {
  id: string;
  title: string;
  subtitle: string | null;
  sceneImage: string | null;
  thumbnailUrl: string | null;
};

export type ExportableScenario = {
  id: string;
  orderIndex: number;
  menuTitle: string;
  menuSubtitle: string | null;
  japanese: string;
  romaji: string;
  english: string;
  targetSubstring: string | null;
  audioKey: string | null;
  publishedAudioUrl: string | null;
  publishedVariantId: string | null;
  publishedContentHash: string | null;
  publishedAt: string | null;
  grammarPointIds: string[];
  setting: string | null;
  thumbnailUrl: string | null;
  lines: unknown;
  highlights: unknown;
  quiz: unknown;
  tokenSync?: unknown;
};

// Assembles the exact shizen collection file shape
// (shizen/Resources/Dialogue/train-station.json). Key insertion order matters
// only for diff-friendliness against the hand-authored files; the Swift
// decoder ignores order. Absent optionals are left undefined so
// JSON.stringify omits them.

function exportLine(
  line: DialogueLine,
  scenarioId: string,
  index: number
): DialogueLine {
  if (isStageLine(line)) {
    return {
      type: "stage",
      text: line.text,
      visibility: line.visibility,
      id: line.id || `${scenarioId}/stage-${index}`,
    };
  }
  if (isInlineQuestionLine(line)) {
    return {
      type: "inline-question",
      prompt: line.prompt,
      target: line.target || undefined,
      layout: line.layout,
      choices: line.choices,
      correctChoice: line.correctChoice,
      wrongAnswerExplanation: line.wrongAnswerExplanation,
      id: line.id || `${scenarioId}/inline-question-${index}`,
    };
  }
  return {
    speaker: line.speaker,
    japanese: line.japanese,
    romaji: line.romaji || undefined,
    english: line.english || undefined,
    id: line.id || `${scenarioId}/line-${index}`,
    grammarPointIDs:
      line.grammarPointIDs && line.grammarPointIDs.length > 0
        ? line.grammarPointIDs
        : undefined,
  };
}

function exportHighlights(
  highlights: DialogueHighlights | null
): DialogueHighlights | undefined {
  if (!highlights) return undefined;
  const vocabulary = highlights.vocabulary ?? [];
  const grammarPatterns = (highlights.grammarPatterns ?? []).map((pattern) => ({
    label: pattern.label,
    grammarPointID: pattern.grammarPointID || undefined,
  }));
  const contextNotes = highlights.contextNotes ?? [];
  if (
    vocabulary.length === 0 &&
    grammarPatterns.length === 0 &&
    contextNotes.length === 0
  ) {
    return undefined;
  }
  return { vocabulary, grammarPatterns, contextNotes };
}

// jsonb loses key insertion order, so rebuild quiz objects in file order.
function exportQuiz(quiz: QuizQuestion[] | null): QuizQuestion[] | undefined {
  if (!quiz || quiz.length === 0) return undefined;
  return quiz.map((question) => ({
    prompt: question.prompt,
    layout: question.layout,
    choices: question.choices,
    correctChoice: question.correctChoice,
    wrongAnswerExplanation: question.wrongAnswerExplanation,
  }));
}

function exportTokenSync(raw: unknown): PublishedTokenSync | undefined {
  return parsePublishedTokenSync(raw) ?? undefined;
}

export function buildScenarioFile(scenario: ExportableScenario): ScenarioFile {
  const lines = (scenario.lines as DialogueLine[]) ?? [];
  return {
    id: scenario.id,
    menuTitle: scenario.menuTitle,
    menuSubtitle: scenario.menuSubtitle ?? undefined,
    japanese: scenario.japanese,
    romaji: scenario.romaji,
    english: scenario.english,
    targetSubstring: scenario.targetSubstring ?? undefined,
    audioKey: scenario.audioKey ?? undefined,
    publishedAudioUrl: scenario.publishedAudioUrl ?? undefined,
    publishedVariantId: scenario.publishedVariantId ?? undefined,
    publishedContentHash: scenario.publishedContentHash ?? undefined,
    publishedAt: scenario.publishedAt ?? undefined,
    scenario: {
      setting: scenario.setting ?? undefined,
      lines: lines.map((line, index) => exportLine(line, scenario.id, index)),
    },
    highlights: exportHighlights(
      scenario.highlights as DialogueHighlights | null
    ),
    grammarPointIDs:
      scenario.grammarPointIds.length > 0 ? scenario.grammarPointIds : undefined,
    thumbnailUrl: scenario.thumbnailUrl ?? undefined,
    quiz: exportQuiz(scenario.quiz as QuizQuestion[] | null),
    tokenSync: exportTokenSync(scenario.tokenSync),
  };
}

export function buildCollectionFile(
  collection: ExportableCollection,
  scenarios: ExportableScenario[]
): CollectionFile {
  return {
    id: collection.id,
    title: collection.title,
    subtitle: collection.subtitle ?? undefined,
    sceneImage: collection.sceneImage ?? undefined,
    thumbnailUrl: collection.thumbnailUrl ?? undefined,
    scenarios: scenarios
      .slice()
      .sort((a, b) => a.orderIndex - b.orderIndex)
      .map(buildScenarioFile),
  };
}

export function serializeCollectionFile(file: CollectionFile): string {
  return `${JSON.stringify(file, null, 2)}\n`;
}
