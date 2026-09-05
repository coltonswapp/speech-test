import { z } from "zod";
import { dialogueDifficultyLevels } from "@/lib/dialogue/difficulty";
import { dialogueFormalityLevels } from "@/lib/dialogue/formality";

// Zod schemas for shizen dialogue collection files
// (shizen/Resources/Dialogue/*.json), mirroring the Swift decoder
// DialogueScenarioCollectionFile in shizen/Dialogue/DialogueScenarioCollection.swift.

// Spoken lines keep the existing { speaker, japanese } shape (type omitted).
// Stage / ト書き rows are non-spoken: italic in the transcript, skipped by
// TTS, and do not consume a line-switch beat. visibility "cold" is for an
// opener before the first spoken line (may show on first listen);
// "practice" is mid-scene (shadow / speak-as-B only).
// Inline-question rows are also non-spoken: they pause playback after the
// preceding spoken line and are skipped by TTS and token-sync.
export const stageVisibilitySchema = z.enum(["cold", "practice"]);
export type StageVisibility = z.infer<typeof stageVisibilitySchema>;

export const spokenLineSchema = z.object({
  type: z.literal("spoken").optional(),
  speaker: z.string(),
  japanese: z.string(),
  romaji: z.string().optional(),
  english: z.string().optional(),
  id: z.string().optional(),
  grammarPointIDs: z.array(z.string()).optional(),
});
export type SpokenLine = z.infer<typeof spokenLineSchema>;

export const stageLineSchema = z.object({
  type: z.literal("stage"),
  text: z.string(),
  visibility: stageVisibilitySchema,
  id: z.string().optional(),
});
export type StageLine = z.infer<typeof stageLineSchema>;

export const quizLayoutSchema = z.enum(["grid", "list"]);

export const quizQuestionSchema = z.object({
  prompt: z.string(),
  layout: quizLayoutSchema,
  choices: z.array(z.string()),
  correctChoice: z.string(),
  wrongAnswerExplanation: z.string(),
});
export type QuizQuestion = z.infer<typeof quizQuestionSchema>;

// Mid-listen checkpoint: sits in `lines[]` like a stage row, skipped by TTS,
// and pauses playback after the preceding spoken line.
export const inlineQuestionLineSchema = z.object({
  type: z.literal("inline-question"),
  prompt: z.string(),
  target: z.string().optional(),
  layout: quizLayoutSchema,
  choices: z.array(z.string()),
  correctChoice: z.string(),
  wrongAnswerExplanation: z.string(),
  id: z.string().optional(),
});
export type InlineQuestionLine = z.infer<typeof inlineQuestionLineSchema>;

// Discriminated variants first — spoken is too loose to go first.
export const dialogueLineSchema = z.union([
  inlineQuestionLineSchema,
  stageLineSchema,
  spokenLineSchema,
]);
export type DialogueLine = z.infer<typeof dialogueLineSchema>;

export function isStageLine(line: DialogueLine): line is StageLine {
  return line.type === "stage";
}

export function isInlineQuestionLine(
  line: DialogueLine,
): line is InlineQuestionLine {
  return line.type === "inline-question";
}

export function isSpokenLine(line: DialogueLine): line is SpokenLine {
  return line.type === undefined || line.type === "spoken";
}

export function spokenLinesOf(lines: DialogueLine[]): SpokenLine[] {
  return lines.filter(isSpokenLine);
}

export function lineGrammarIds(line: DialogueLine): string[] {
  return isSpokenLine(line) ? (line.grammarPointIDs ?? []) : [];
}

export function hasSpokenJapanese(lines: DialogueLine[]): boolean {
  return lines.some(
    (line) => isSpokenLine(line) && line.japanese.trim().length > 0,
  );
}

export function hasOpenerStage(lines: DialogueLine[]): boolean {
  for (const line of lines) {
    if (isSpokenLine(line)) return false;
    if (isStageLine(line)) return true;
  }
  return false;
}

export function defaultStageVisibility(
  lines: DialogueLine[],
  insertIndex: number,
): StageVisibility {
  return lines.slice(0, insertIndex).some(isSpokenLine) ? "practice" : "cold";
}

export function emptySpokenLine(speaker: string): SpokenLine {
  return { speaker, japanese: "", romaji: "", english: "" };
}

export function emptyStageLine(
  visibility: StageVisibility,
  text = "",
): StageLine {
  return { type: "stage", text, visibility };
}

export function emptyInlineQuestionLine(): InlineQuestionLine {
  return {
    type: "inline-question",
    prompt: "",
    layout: "grid",
    choices: [],
    correctChoice: "",
    wrongAnswerExplanation: "",
  };
}

export function formatDialogueTranscriptLine(
  line: DialogueLine,
  index?: number,
): string {
  const prefix = index === undefined ? "" : `[${index}] `;
  if (isStageLine(line)) {
    return `${prefix}[stage/${line.visibility}] ${line.text}`;
  }
  if (isInlineQuestionLine(line)) {
    const target = line.target?.trim() ? ` (${line.target.trim()})` : "";
    return `${prefix}[inline-question] ${line.prompt}${target}`;
  }
  return `${prefix}${line.speaker}: ${line.japanese}`;
}

// The Swift decoder accepts a bare string or {label, grammarPointID};
// normalize to object form (export always emits objects).
export const grammarPatternSchema = z
  .union([
    z.string(),
    z.object({ label: z.string(), grammarPointID: z.string().optional() }),
  ])
  .transform((value) => (typeof value === "string" ? { label: value } : value));
export type GrammarPatternRef = z.output<typeof grammarPatternSchema>;

export const highlightsSchema = z.object({
  vocabulary: z.array(z.string()).optional(),
  grammarPatterns: z.array(grammarPatternSchema).optional(),
  contextNotes: z.array(z.string()).optional(),
});
export type DialogueHighlights = z.output<typeof highlightsSchema>;

// Working copy on a TTS take: startSeconds is null until stamped.
export const variantTokenSchema = z.object({
  text: z.string().min(1),
  startSeconds: z.number().nullable(),
});
export type VariantToken = z.infer<typeof variantTokenSchema>;

export const variantTokenSyncLineSchema = z.object({
  text: z.string(),
  tokens: z.array(variantTokenSchema).min(1),
});
export type VariantTokenSyncLine = z.infer<typeof variantTokenSyncLineSchema>;

export const variantTokenSyncSchema = z.object({
  version: z.literal(1),
  contentHash: z.string(),
  lines: z.array(variantTokenSyncLineSchema),
});
export type VariantTokenSync = z.infer<typeof variantTokenSyncSchema>;

export const publishedTokenSchema = z.object({
  text: z.string().min(1),
  startSeconds: z.number(),
});
export type PublishedToken = z.infer<typeof publishedTokenSchema>;

export const publishedTokenSyncLineSchema = z.object({
  text: z.string(),
  tokens: z.array(publishedTokenSchema).min(1),
});
export type PublishedTokenSyncLine = z.infer<
  typeof publishedTokenSyncLineSchema
>;

export const publishedTokenSyncSchema = z.object({
  version: z.literal(1),
  variantId: z.string(),
  contentHash: z.string(),
  lines: z.array(publishedTokenSyncLineSchema),
});
export type PublishedTokenSync = z.infer<typeof publishedTokenSyncSchema>;

export const tokenizeLinesRequestSchema = z.object({
  texts: z.array(z.string()).min(1).max(48),
});
export type TokenizeLinesRequest = z.infer<typeof tokenizeLinesRequestSchema>;

export const tokenizeLinesResultSchema = z.object({
  lines: z.array(
    z.object({
      text: z.string(),
      tokens: z.array(z.string().min(1)).min(1),
    }),
  ),
});
export type TokenizeLinesResult = z.infer<typeof tokenizeLinesResultSchema>;


export const scenarioBodySchema = z.object({
  setting: z.string().optional(),
  lines: z.array(dialogueLineSchema),
});

// A scenario record exactly as it appears in a collection file.
export const scenarioFileSchema = z.object({
  id: z.string(),
  menuTitle: z.string(),
  menuSubtitle: z.string().optional(),
  japanese: z.string(),
  romaji: z.string(),
  english: z.string(),
  targetSubstring: z.string().optional(),
  audioKey: z.string().optional(),
  publishedAudioUrl: z.string().url().optional(),
  publishedVariantId: z.string().optional(),
  publishedContentHash: z.string().optional(),
  publishedAt: z.string().optional(),
  grammarPointIDs: z.array(z.string()).optional(),
  // Per-scenario CDN thumbnail; absent → the app uses the collection's.
  thumbnailUrl: z.string().url().optional(),
  scenario: scenarioBodySchema,
  highlights: highlightsSchema.optional(),
  quiz: z.array(quizQuestionSchema).optional(),
  tokenSync: publishedTokenSyncSchema.optional(),
});
export type ScenarioFile = z.output<typeof scenarioFileSchema>;

export const collectionFileSchema = z.object({
  id: z.string(),
  title: z.string(),
  subtitle: z.string().optional(),
  sceneImage: z.string().optional(),
  thumbnailUrl: z.string().url().optional(),
  scenarios: z.array(scenarioFileSchema),
});
export type CollectionFile = z.output<typeof collectionFileSchema>;

const slugPattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
export const slugSchema = z
  .string()
  .regex(
    slugPattern,
    "Use lowercase letters, digits, and hyphens (e.g. train-station)",
  );

export const createCollectionSchema = z.object({
  id: slugSchema,
  title: z.string().min(1),
  subtitle: z.string().optional(),
  premise: z.string().optional(),
  sceneImage: z.string().optional(),
  unitId: z.string().optional(),
});

export const createUnitSchema = z.object({
  id: slugSchema,
  title: z.string().min(1),
  subtitle: z.string().optional(),
  jlptLevel: z.number().int().min(1).max(5).default(5),
  orderIndex: z.number().int().optional(),
});

export const updateUnitSchema = z.object({
  title: z.string().min(1).optional(),
  subtitle: z.string().nullable().optional(),
  jlptLevel: z.number().int().min(1).max(5).optional(),
  orderIndex: z.number().int().optional(),
  collectionOrder: z.array(z.string()).optional(),
});

export const createScenarioSchema = z.object({
  slug: slugSchema,
  menuTitle: z.string().min(1),
  menuSubtitle: z.string().optional(),
  setting: z.string().optional(),
});

export const castVoiceEntrySchema = z.object({
  name: z.string().min(1),
  provider: z.enum(["gemini", "openai"]),
  voice: z.string().min(1),
});

export const castVoicesSchema = z.array(castVoiceEntrySchema);

export type CastVoiceEntry = z.infer<typeof castVoiceEntrySchema>;

// Dedicated partial schemas for PATCH — NOT .partial() on a schema with
// .default()s, since Zod still applies defaults to omitted keys, which would
// silently zero out fields like `lines`/`quiz` on any partial update.
export const updateCollectionSchema = z.object({
  title: z.string().min(1).optional(),
  unitId: z.string().nullable().optional(),
  subtitle: z.string().nullable().optional(),
  premise: z.string().nullable().optional(),
  castVoices: castVoicesSchema.optional(),
  sceneImage: z.string().nullable().optional(),
  thumbnailUrl: z.string().url().nullable().optional(),
  orderIndex: z.number().int().optional(),
  scenarioOrder: z.array(z.string()).optional(),
});

export const updateScenarioSchema = z.object({
  menuTitle: z.string().min(1).optional(),
  menuSubtitle: z.string().nullable().optional(),
  japanese: z.string().optional(),
  romaji: z.string().optional(),
  english: z.string().optional(),
  targetSubstring: z.string().nullable().optional(),
  audioKey: z.string().nullable().optional(),
  grammarPointIds: z.array(z.string()).optional(),
  setting: z.string().nullable().optional(),
  thumbnailUrl: z.string().url().nullable().optional(),
  lines: z.array(dialogueLineSchema).optional(),
  highlights: highlightsSchema.nullable().optional(),
  quiz: z.array(quizQuestionSchema).nullable().optional(),
});

export const generateLinesRequestSchema = z.object({
  prompt: z.string().min(1),
  collectionId: z.string().optional(),
  setting: z.string().optional(),
  speakerNames: z.array(z.string().min(1)).max(2).optional(),
  grammarPointIds: z.array(z.string()).optional(),
  existingLines: z.array(dialogueLineSchema).optional(),
  mode: z.enum(["replace", "append"]).default("replace"),
  lineCount: z.number().int().min(2).max(24).optional(),
  variantIndex: z.number().int().min(0).max(9).optional(),
  variantCount: z.number().int().min(1).max(10).optional(),
  difficulty: z.enum(dialogueDifficultyLevels).default("beginner"),
  formality: z.enum(dialogueFormalityLevels).default("polite"),
});
export type GenerateLinesRequest = z.infer<typeof generateLinesRequestSchema>;

export const generatedLineSchema = z.object({
  speaker: z.string().min(1),
  japanese: z.string().min(1),
  romaji: z.string().min(1),
  english: z.string().min(1),
  grammarPointIDs: z.array(z.string()).optional(),
});
export type GeneratedLine = z.infer<typeof generatedLineSchema>;

export const generatedLinesSchema = z.object({
  setting: z.string().optional(),
  lines: z.array(generatedLineSchema).min(1),
});
export type GeneratedLines = z.infer<typeof generatedLinesSchema>;

// LLM revision of existing dialogue: either targeted edits to selected line
// indices ("selection") or a rewrite of the whole dialogue ("all").
export const reviseLinesRequestSchema = z.object({
  lines: z.array(dialogueLineSchema).min(1),
  scope: z.enum(["selection", "all"]),
  selectedIndices: z.array(z.number().int().min(0)).optional(),
  instructions: z.string().min(1),
  setting: z.string().optional(),
  menuTitle: z.string().optional(),
  grammarPointIds: z.array(z.string()).optional(),
  difficulty: z.enum(dialogueDifficultyLevels).default("beginner"),
  formality: z.enum(dialogueFormalityLevels).default("polite"),
});
export type ReviseLinesRequest = z.infer<typeof reviseLinesRequestSchema>;

// LLM-authored scenario idea: a menu title, setting, and grammar points to
// seed the "Add scenario" form before generating dialogue lines.
export const generateScenarioRequestSchema = z.object({
  prompt: z.string().min(1),
  collectionId: z.string().optional(),
  existingSlugs: z.array(z.string()).optional(),
  difficulty: z.enum(dialogueDifficultyLevels).default("beginner"),
  formality: z.enum(dialogueFormalityLevels).default("polite"),
});
export type GenerateScenarioRequest = z.infer<
  typeof generateScenarioRequestSchema
>;

export const generatedScenarioSchema = z.object({
  slug: z.string().min(1),
  menuTitle: z.string().min(1),
  setting: z.string().min(1),
  grammarPointIds: z.array(z.string()).default([]),
});
export type GeneratedScenario = z.infer<typeof generatedScenarioSchema>;

export const lineRevisionSchema = z.object({
  index: z.number().int().min(0),
  line: generatedLineSchema,
});
export type LineRevision = z.infer<typeof lineRevisionSchema>;

export const revisedSelectionSchema = z.object({
  revisions: z.array(lineRevisionSchema).min(1),
});

export type ReviseLinesResult =
  | { scope: "selection"; revisions: LineRevision[] }
  | { scope: "all"; generated: GeneratedLines };

// LLM extraction of learner highlights (vocab + grammar labels) from dialogue.
// LLM-authored quiz question candidates, generated from dialogue lines so
// editors can pick which ones to keep rather than hand-writing every question.
export const generateQuizRequestSchema = z.object({
  lines: z.array(dialogueLineSchema).min(1),
  setting: z.string().optional(),
  menuTitle: z.string().optional(),
  existingQuiz: z.array(quizQuestionSchema).optional(),
  count: z.number().int().min(1).max(10).default(6),
});
export type GenerateQuizRequest = z.infer<typeof generateQuizRequestSchema>;

export const generatedQuizSchema = z.object({
  questions: z.array(quizQuestionSchema).min(1),
});
export type GeneratedQuiz = z.infer<typeof generatedQuizSchema>;

export const extractHighlightsRequestSchema = z.object({
  lines: z.array(dialogueLineSchema).min(1),
  setting: z.string().optional(),
  menuTitle: z.string().optional(),
  grammarPointIds: z.array(z.string()).optional(),
});
export type ExtractHighlightsRequest = z.infer<
  typeof extractHighlightsRequestSchema
>;

export const extractedHighlightsSchema = z.object({
  vocabulary: z.array(z.string().min(1)).min(1).max(24),
  grammarPatterns: z
    .array(
      z.object({
        label: z.string().min(1),
        grammarPointID: z.string().optional(),
      }),
    )
    .max(12)
    .optional(),
  contextNotes: z.array(z.string().min(1)).max(6).optional(),
});
export type ExtractedHighlights = z.infer<typeof extractedHighlightsSchema>;

// Scenario content audit: deterministic + LLM checks with proposed fixes.
export const auditIssueSeveritySchema = z.enum(["error", "warning", "info"]);

export const auditIssueSchema = z.object({
  severity: auditIssueSeveritySchema,
  code: z.string(),
  message: z.string(),
  lineIndex: z.number().int().min(0).optional(),
  grammarPointID: z.string().optional(),
});
export type AuditIssue = z.infer<typeof auditIssueSchema>;

export const auditProposedPatchSchema = z.object({
  lines: z.array(dialogueLineSchema).optional(),
  highlights: highlightsSchema.optional(),
  grammarPointIds: z.array(z.string()).optional(),
});
export type AuditProposedPatch = z.infer<typeof auditProposedPatchSchema>;

export const sanitizeGrammarRequestSchema = z.object({
  lines: z.array(dialogueLineSchema).min(1),
  highlights: highlightsSchema.nullable().optional(),
  grammarPointIds: z.array(z.string()).optional(),
});
export type SanitizeGrammarRequest = z.infer<
  typeof sanitizeGrammarRequestSchema
>;

export const sanitizeGrammarResultSchema = z.object({
  lines: z.array(dialogueLineSchema),
  highlights: highlightsSchema.nullable(),
  grammarPointIds: z.array(z.string()),
  removedCount: z.number().int().min(0),
});
export type SanitizeGrammarResult = z.infer<typeof sanitizeGrammarResultSchema>;

export const auditScenarioRequestSchema = z.object({
  lines: z.array(dialogueLineSchema).min(1),
  highlights: highlightsSchema.nullable().optional(),
  grammarPointIds: z.array(z.string()).optional(),
  setting: z.string().optional(),
  menuTitle: z.string().optional(),
});
export type AuditScenarioRequest = z.infer<typeof auditScenarioRequestSchema>;

export const auditScenarioResultSchema = z.object({
  issues: z.array(auditIssueSchema),
  proposed: auditProposedPatchSchema,
  llmFailed: z.boolean().optional(),
});
export type AuditScenarioResult = z.infer<typeof auditScenarioResultSchema>;

export const llmAuditResultSchema = z.object({
  mistaggedLines: z
    .array(
      z.object({
        lineIndex: z.number().int().min(0),
        grammarPointID: z.string().min(1),
        reason: z.string().min(1),
      }),
    )
    .default([]),
});
export type LlmAuditResult = z.infer<typeof llmAuditResultSchema>;
