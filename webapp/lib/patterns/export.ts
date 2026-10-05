import { inArray } from "drizzle-orm";
import type { PostgresJsDatabase } from "drizzle-orm/postgres-js";
import { teachingPattern } from "@/lib/db/schema";
import type * as schema from "@/lib/db/schema";
import type { ExportedTeachingPattern } from "@/lib/dialogue/types";

type Db = PostgresJsDatabase<typeof schema>;

/** Map a teaching_pattern row to the public/iOS catalog card shape. */
export function toExportedTeachingPattern(row: {
  id: string;
  form: string;
  gloss: string;
  notes: string | null;
}): ExportedTeachingPattern {
  const shortMeaning = row.gloss.trim();
  const formNote = row.notes?.trim();
  return {
    id: row.id,
    label: row.form.trim() || row.id,
    ...(shortMeaning ? { shortMeaning } : {}),
    ...(formNote ? { formNote } : {}),
  };
}

export async function fetchExportedTeachingPatterns(
  db: Db,
  ids: string[]
): Promise<ExportedTeachingPattern[]> {
  if (ids.length === 0) return [];
  const rows = await db.query.teachingPattern.findMany({
    where: inArray(teachingPattern.id, ids),
    columns: {
      id: true,
      form: true,
      gloss: true,
      notes: true,
    },
  });
  const byId = new Map(rows.map((row) => [row.id, toExportedTeachingPattern(row)]));
  // Preserve reference order; skip orphans (missing catalog rows).
  return ids
    .map((id) => byId.get(id))
    .filter((row): row is ExportedTeachingPattern => row != null);
}
