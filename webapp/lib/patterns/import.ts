// Re-exports + CSV-string upsert API for teaching patterns.
// Implementation lives in ./seed (batch insert-missing).

import { readFile } from "node:fs/promises";
import type { PostgresJsDatabase } from "drizzle-orm/postgres-js";
import type * as schema from "@/lib/db/schema";
import {
  N5_PATTERNS_CSV,
  rowsFromCsv,
  upsertTeachingPatterns,
  type TeachingPatternSeedRow,
} from "./seed";

export type TeachingPatternRow = TeachingPatternSeedRow;

export function parseCsv(raw: string): TeachingPatternRow[] {
  return rowsFromCsv(raw);
}

export async function upsertTeachingPatternsFromCsv(
  db: PostgresJsDatabase<typeof schema>,
  raw: string,
): Promise<{ inserted: number; skipped: number; total: number }> {
  return upsertTeachingPatterns(db, parseCsv(raw));
}

export async function upsertTeachingPatternsFromSeedFile(
  db: PostgresJsDatabase<typeof schema>,
  csvPath: string = N5_PATTERNS_CSV,
): Promise<{ inserted: number; skipped: number; total: number }> {
  const raw = await readFile(csvPath, "utf-8");
  return upsertTeachingPatternsFromCsv(db, raw);
}

