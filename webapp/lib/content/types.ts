import { z } from "zod";

export const contentStatusSchema = z.enum(["draft", "needsRevision", "approved"]);
export type ContentStatus = z.infer<typeof contentStatusSchema>;

export const grammarRegisterSchema = z.enum(["casual", "polite", "formal"]);

export const teachingBlockSchema = z.object({
  title: z.string(),
  body: z.string(),
});

export const usageLevelSchema = z.object({
  japanese: z.string(),
  register: z.string(),
});

export const usageLadderSchema = z.object({
  label: z.string(),
  levels: z.array(usageLevelSchema),
});

export const scenarioLineSchema = z.object({
  speaker: z.string(),
  japanese: z.string(),
  romaji: z.string().optional(),
  english: z.string().optional(),
  id: z.string().optional(),
  grammarPointIDs: z.array(z.string()).optional(),
});

export const scenarioSchema = z.object({
  setting: z.string().optional(),
  lines: z.array(scenarioLineSchema),
});

export const exampleSchema = z.object({
  japanese: z.string(),
  romaji: z.string().optional(),
  english: z.string(),
  targetSubstring: z.string().optional(),
  audioKey: z.string().nullable().optional(),
  scenario: scenarioSchema.optional(),
  sourceScenarioId: z.string().optional(),
});

export const drillSchema = z.object({
  kind: z.string(),
  instruction: z.string().optional(),
  prompt: z.string().optional(),
  exampleJapanese: z.string().optional(),
  targetSubstring: z.string().optional(),
  english: z.string().optional(),
  choices: z.array(z.string()).optional(),
  correctChoice: z.string().optional(),
  contrastLabel: z.string().optional(),
  buildComponents: z.array(z.string()).optional(),
});

export const contrastDrillSchema = z.object({
  contrastLabel: z.string(),
  choices: z.array(z.string()),
  correctChoice: z.string(),
  ruleTargeted: z.string().nullable().optional(),
});

export const grammarPointSchema = z.object({
  id: z.string(),
  orderIndex: z.number().int(),
  title: z.string(),
  headlineEnglish: z.string(),
  blurb: z.string().nullable().optional(),
  forms: z.array(z.string()).default([]),
  formation: z.array(teachingBlockSchema).default([]),
  formationExamples: z.array(z.string()).nullable().optional(),
  usage: z.array(teachingBlockSchema).nullable().optional(),
  usageLadders: z.array(usageLadderSchema).nullable().optional(),
  relatedPointIDs: z.array(z.string()).default([]),
  examples: z.array(exampleSchema),
  drills: z.array(drillSchema).default([]),
  pattern: z.string().nullable().optional(),
  reading: z.string().nullable().optional(),
  shortDefinition: z.string().nullable().optional(),
  structure: z.string().nullable().optional(),
  register: grammarRegisterSchema.nullable().optional(),
  contrastDrills: z.array(contrastDrillSchema).nullable().optional(),
  status: contentStatusSchema.default("draft"),
  reviewNotes: z.string().nullable().optional(),
});

export type GrammarPointInput = z.infer<typeof grammarPointSchema>;

// A dedicated partial schema for PATCH — NOT grammarPointSchema.partial(),
// since Zod still applies .default() to omitted keys even under .partial(),
// which would silently zero out fields like `forms`/`relatedPointIDs` on any
// partial update that doesn't explicitly include them.
export const updatePointSchema = z.object({
  id: z.string().optional(),
  orderIndex: z.number().int().optional(),
  title: z.string().optional(),
  headlineEnglish: z.string().optional(),
  blurb: z.string().nullable().optional(),
  forms: z.array(z.string()).optional(),
  formation: z.array(teachingBlockSchema).optional(),
  formationExamples: z.array(z.string()).nullable().optional(),
  usage: z.array(teachingBlockSchema).nullable().optional(),
  usageLadders: z.array(usageLadderSchema).nullable().optional(),
  relatedPointIDs: z.array(z.string()).optional(),
  examples: z.array(exampleSchema).optional(),
  drills: z.array(drillSchema).optional(),
  pattern: z.string().nullable().optional(),
  reading: z.string().nullable().optional(),
  shortDefinition: z.string().nullable().optional(),
  structure: z.string().nullable().optional(),
  register: grammarRegisterSchema.nullable().optional(),
  contrastDrills: z.array(contrastDrillSchema).nullable().optional(),
  status: contentStatusSchema.optional(),
  reviewNotes: z.string().nullable().optional(),
});
