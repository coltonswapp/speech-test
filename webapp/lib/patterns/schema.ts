import { z } from "zod";
import type { TeachingPatternSeedRow } from "./seed";

const slugPattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

/** Writable teaching_pattern row (matches Studio Pattern library model). */
export const teachingPatternWriteSchema = z.object({
  id: z
    .string()
    .min(1)
    .regex(slugPattern, "Use lowercase letters, digits, and hyphens"),
  form: z.string().min(1),
  gloss: z.string().min(1),
  jlptBand: z.number().int().min(1).max(5).default(5),
  category: z.string().min(1).default("other"),
  status: z.string().min(1).default("seed"),
  notes: z.string().nullable().optional(),
  orderIndex: z.number().int().default(0),
});

export type TeachingPatternWrite = z.infer<typeof teachingPatternWriteSchema>;

/** Body: one pattern, an array, or `{ patterns: [...] }`. */
export const teachingPatternCreateBodySchema = z.union([
  teachingPatternWriteSchema,
  z.array(teachingPatternWriteSchema).min(1),
  z.object({ patterns: z.array(teachingPatternWriteSchema).min(1) }),
]);

export function normalizeTeachingPatternWrites(
  body: z.infer<typeof teachingPatternCreateBodySchema>
): TeachingPatternSeedRow[] {
  const rows = Array.isArray(body)
    ? body
    : "patterns" in body
      ? body.patterns
      : [body];
  return rows.map((row) => ({
    id: row.id,
    form: row.form.trim(),
    gloss: row.gloss.trim(),
    jlptBand: row.jlptBand,
    category: row.category.trim() || "other",
    status: row.status.trim() || "seed",
    notes: row.notes?.trim() ? row.notes.trim() : null,
    orderIndex: row.orderIndex,
  }));
}
