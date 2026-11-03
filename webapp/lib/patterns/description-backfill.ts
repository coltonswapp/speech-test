import { z } from "zod";

/** Dump row for patterns that still need a textbook-style description. */
export const patternDescriptionDumpRowSchema = z.object({
  id: z.string().min(1),
  form: z.string(),
  gloss: z.string(),
  jlptBand: z.number().int(),
  category: z.string(),
  notes: z.string().nullable(),
  description: z.literal(""),
});

export type PatternDescriptionDumpRow = z.infer<
  typeof patternDescriptionDumpRowSchema
>;

/** Filled row an external LLM writes back into apply. */
export const patternDescriptionFillSchema = z.object({
  id: z.string().min(1),
  form: z.string().optional(),
  gloss: z.string().optional(),
  jlptBand: z.number().int().optional(),
  category: z.string().optional(),
  notes: z.string().nullable().optional(),
  description: z.string(),
});

export type PatternDescriptionFill = z.infer<
  typeof patternDescriptionFillSchema
>;

export const patternDescriptionFillFileSchema = z.union([
  z.array(patternDescriptionFillSchema),
  z.object({ patterns: z.array(patternDescriptionFillSchema) }),
]);

export function isMissingDescription(
  value: string | null | undefined
): boolean {
  return !value?.trim();
}

export function toDescriptionDumpRow(row: {
  id: string;
  form: string;
  gloss: string;
  jlptBand: number;
  category: string;
  notes: string | null;
}): PatternDescriptionDumpRow {
  return {
    id: row.id,
    form: row.form,
    gloss: row.gloss,
    jlptBand: row.jlptBand,
    category: row.category,
    notes: row.notes,
    description: "",
  };
}

export function normalizePatternDescriptionFills(
  body: z.infer<typeof patternDescriptionFillFileSchema>
): { fills: PatternDescriptionFill[]; skippedEmpty: number } {
  const rows = Array.isArray(body) ? body : body.patterns;
  const fills: PatternDescriptionFill[] = [];
  let skippedEmpty = 0;
  for (const row of rows) {
    const description = row.description.trim();
    if (!description) {
      skippedEmpty += 1;
      continue;
    }
    fills.push({ ...row, description });
  }
  return { fills, skippedEmpty };
}
